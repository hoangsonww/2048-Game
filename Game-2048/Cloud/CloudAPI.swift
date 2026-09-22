import Foundation

/// The one place this app touches the network.
///
/// A protocol with a single method, so `CloudAPI` — which holds every decision
/// worth testing: what to send, how to read a reply, when to refresh a token —
/// runs entirely under XCTest with a fake. The `URLSession` implementation
/// below is the only part that needs a real network, and it contains no logic
/// to get wrong.
protocol HTTPTransport: Sendable {
    func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data)
}

struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (status, data)
        } catch {
            // A dropped connection, airplane mode, a captive portal. The caller
            // decides whether to retry; the game never waits on it.
            throw CloudError.network
        }
    }
}

/// Where the session lives between launches.
protocol TokenStoring: AnyObject {
    func read() -> CloudTokens?
    func write(_ tokens: CloudTokens?)
}

/// The typed client for the 2048 Cloud API.
///
/// An actor because the token-refresh retry is the one piece of shared mutable
/// state here, and two requests racing a 401 would otherwise each rotate the
/// refresh token — which the server treats as a replay and answers by revoking
/// the session. Serialising the client is a smaller price than signing a
/// player out because their own requests overlapped.
actor CloudAPI {
    static let defaultBaseURL = URL(string: "https://game-2048-cloud-api.vercel.app")!

    private let transport: HTTPTransport
    private let tokens: TokenStoring
    private let baseURL: URL
    private let deviceID: String
    private let decoder = JSONDecoder()

    init(
        transport: HTTPTransport = URLSessionTransport(),
        tokens: TokenStoring,
        baseURL: URL = CloudAPI.defaultBaseURL,
        deviceID: String = "ios"
    ) {
        self.transport = transport
        self.tokens = tokens
        self.baseURL = baseURL
        self.deviceID = deviceID
    }

    // MARK: - Transport

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil, token: String? = nil) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CloudError(code: "bad_request", message: "That request could not be built.")
        }

        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Client": "ios"
        ]
        if let token { headers["Authorization"] = "Bearer \(token)" }

        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let (status, data) = try await transport.send(method: method, url: url, headers: headers, body: payload)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard (200..<300).contains(status) else {
            let error = json["error"] as? [String: Any]
            throw CloudError(
                code: (error?["code"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "http_error",
                message: Self.humanMessage(error: error, status: status),
                status: status
            )
        }

        return json
    }

    /// Prefer field-level validation hints over the generic 422 summary.
    private static func humanMessage(error: [String: Any]?, status: Int) -> String {
        if let details = error?["details"] as? [String: Any],
           let issues = details["issues"] as? [[String: Any]] {
            let lines = issues.compactMap { $0["message"] as? String }.filter { !$0.isEmpty }
            if !lines.isEmpty { return lines.joined(separator: " ") }
        }
        if let message = error?["message"] as? String, !message.isEmpty { return message }
        return "Request failed with status \(status)."
    }

    /// Runs an authenticated request, refreshing once on a 401.
    ///
    /// One retry, never a loop: if the refreshed token is also rejected the
    /// session is genuinely gone, and retrying would just rotate a dead token
    /// until the server revoked it.
    private func authed(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let current = tokens.read() else { throw CloudError.unauthorized }
        do {
            return try await request(method, path, body: body, token: current.accessToken)
        } catch let error as CloudError where error.isUnauthorized {
            let refreshed = try await refresh()
            return try await request(method, path, body: body, token: refreshed.accessToken)
        }
    }

    @discardableResult
    private func refresh() async throws -> CloudTokens {
        guard let current = tokens.read(), current.refreshToken.isEmpty == false else {
            tokens.write(nil)
            throw CloudError(code: "unauthorized", message: "You are signed out.", status: 401)
        }

        do {
            let json = try await request("POST", "/api/v1/auth/refresh", body: ["refreshToken": current.refreshToken])
            let next = readTokens(json)
            tokens.write(next)
            return next
        } catch let error as CloudError {
            // A dropped connection must not sign a player out — they may
            // simply be on a train. Anything else means the session is over.
            if error.isNetworkFailure == false { tokens.write(nil) }
            throw error
        }
    }

    // MARK: - Session

    func register(username: String, email: String, password: String) async throws -> CloudSession {
        let json = try await request("POST", "/api/v1/auth/register", body: [
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "client": "ios"
        ])
        return adopt(json)
    }

    func login(identifier: String, password: String) async throws -> CloudSession {
        let json = try await request("POST", "/api/v1/auth/login", body: [
            "identifier": identifier.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "client": "ios"
        ])
        return adopt(json)
    }

    /**
     Sets a new password from a username and the email address on it.

     Interim recovery, with no mailed token — see the endpoint's own comment
     in `server/src/routes/auth.routes.js`. The server revokes every session
     on the account, so the local tokens are dropped here whether or not this
     device held one.
     */
    func resetPassword(username: String, email: String, newPassword: String) async throws {
        _ = try await request("POST", "/api/v1/auth/reset-password", body: [
            "username": username.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "newPassword": newPassword
        ])
        tokens.write(nil)
    }

    func currentUser() async throws -> CloudUser? {
        guard tokens.read() != nil else { return nil }
        // A reply carrying no user object is not a user. Reading one out of
        // it anyway yields a blank name and zeroed career totals, which then
        // replace a perfectly good session on screen.
        guard let user = try await authed("GET", "/api/v1/auth/me")["user"] as? [String: Any] else { return nil }
        return readUser(user)
    }

    func logout() async {
        guard let current = tokens.read() else { return }
        tokens.write(nil)
        // The local session is already gone, which is what the player asked
        // for. A failed server-side revoke is never worth an error dialog.
        _ = try? await request("POST", "/api/v1/auth/logout", body: ["refreshToken": current.refreshToken])
    }

    private func adopt(_ json: [String: Any]) -> CloudSession {
        let session = CloudSession(user: readUser(json["user"] as? [String: Any]), tokens: readTokens(json))
        tokens.write(session.tokens)
        return session
    }

    // MARK: - Game data

    func sync(_ save: CloudSave?, strategy: String = "auto") async throws -> SyncResult {
        var body: [String: Any] = ["slot": "current", "strategy": strategy]
        body["save"] = save.map(write) ?? NSNull()

        let json = try await authed("POST", "/api/v1/saves/sync", body: body)
        return SyncResult(
            resolution: SyncResolution(rawValue: json["resolution"] as? String ?? ""),
            save: (json["save"] as? [String: Any]).flatMap(read),
            conflictSlot: json["conflictSlot"] as? String,
            winner: json["winner"] as? String
        )
    }

    func submitScore(_ save: CloudSave, durationSeconds: Int = 0) async throws {
        _ = try await authed("POST", "/api/v1/scores", body: [
            "board": save.board,
            "score": save.score,
            "moves": save.moves,
            "durationSeconds": durationSeconds,
            "client": "ios"
        ])
    }

    func leaderboard(period: String = "all", limit: Int = 20) async throws -> LeaderboardPage {
        let path = "/api/v1/leaderboard?period=\(period)&limit=\(limit)&offset=0"
        // Readable signed out as well as signed in, so the board is reachable
        // before anyone has an account.
        let json = tokens.read() == nil
            ? try await request("GET", path)
            : try await authed("GET", path)

        let rows = json["entries"] as? [[String: Any]] ?? []
        let summary = json["summary"] as? [String: Any] ?? [:]

        return LeaderboardPage(
            entries: rows.map(readEntry),
            players: summary["players"] as? Int ?? 0,
            topScore: summary["topScore"] as? Int ?? 0
        )
    }

    // MARK: - Wire format

    private func write(_ save: CloudSave) -> [String: Any] {
        var json: [String: Any] = [
            "board": save.board,
            "score": save.score,
            "bestScore": save.bestScore,
            "won": save.won,
            "gameOver": save.gameOver,
            "moves": save.moves,
            "elapsedSeconds": save.elapsedSeconds,
            "client": "ios",
            "deviceId": deviceID
        ]
        if let baseRevision = save.baseRevision { json["baseRevision"] = baseRevision }
        return json
    }

    private func read(_ json: [String: Any]) -> CloudSave {
        CloudSave(
            board: json["board"] as? [Int] ?? [],
            score: json["score"] as? Int ?? 0,
            bestScore: json["bestScore"] as? Int ?? 0,
            won: json["won"] as? Bool ?? false,
            gameOver: json["gameOver"] as? Bool ?? false,
            moves: json["moves"] as? Int ?? 0,
            elapsedSeconds: json["elapsedSeconds"] as? Int ?? 0,
            revision: json["revision"] as? Int ?? 0
        )
    }

    private func readTokens(_ json: [String: Any]) -> CloudTokens {
        CloudTokens(
            accessToken: json["accessToken"] as? String ?? "",
            refreshToken: json["refreshToken"] as? String ?? ""
        )
    }

    private func readUser(_ json: [String: Any]?) -> CloudUser {
        let user = json ?? [:]
        let statistics = user["statistics"] as? [String: Any] ?? [:]
        let username = user["username"] as? String ?? ""
        let displayName = user["displayName"] as? String ?? ""

        return CloudUser(
            id: user["id"] as? String ?? "",
            username: username,
            displayName: displayName.isEmpty ? username : displayName,
            email: user["email"] as? String ?? "",
            statistics: CloudStatistics(
                bestScore: statistics["bestScore"] as? Int ?? 0,
                gamesPlayed: statistics["gamesPlayed"] as? Int ?? 0,
                gamesWon: statistics["gamesWon"] as? Int ?? 0,
                highestTile: statistics["highestTile"] as? Int ?? 0
            )
        )
    }

    private func readEntry(_ json: [String: Any]) -> LeaderboardEntry {
        let username = json["username"] as? String ?? ""
        let displayName = json["displayName"] as? String ?? ""
        return LeaderboardEntry(
            rank: json["rank"] as? Int ?? 0,
            username: username,
            displayName: displayName.isEmpty ? username : displayName,
            score: json["score"] as? Int ?? 0,
            highestTile: json["highestTile"] as? Int ?? 0,
            isViewer: json["isViewer"] as? Bool ?? false
        )
    }
}

// MARK: - Maintainer reference (documentation only)
//
// Cloud API, backend contract, and schema reference.
//
// This section is intentionally comment-only. The named repository files remain
// canonical; their contents are mirrored here as an in-source reading reference.
// No declaration, executable statement, build setting, or runtime behavior follows.

// SOURCE: docs/backend.md

// # 2048 Cloud API
//
// The optional backend behind accounts, cross-device saves, scores, and leaderboards.
//
// Live deployment: [https://game-2048-cloud-api.vercel.app](https://game-2048-cloud-api.vercel.app)
// Reference: [/docs](https://game-2048-cloud-api.vercel.app/docs) · [/redoc](https://game-2048-cloud-api.vercel.app/redoc) · [/reference](https://game-2048-cloud-api.vercel.app/reference) · [/openapi.json](https://game-2048-cloud-api.vercel.app/openapi.json)
//
// The service root (`/`) redirects to Swagger UI at `/docs`.
//
// ## Product posture
//
// The game is still **local-first**. Every client plays, scores, undoes, and restores a round with no network. An account is an invitation under the board, never a gate on the board.
//
// | Layer | Responsibility |
// | --- | --- |
// | Rules engine | Local, unchanged, no knowledge of the cloud |
// | Local store | Still the source of truth for the active round |
// | Cloud client | Additive: auth, sync, leaderboard — removable without breaking play |
// | API | Stores rounds, scores, and account metadata; never ships game rules or UI |
//
// If the API is unreachable, play continues on the device. Sync retries on the next signed-in move or restore.
//
// ## Stack
//
// - **Express 5** + **Mongoose 8** against MongoDB Atlas database `game2048`
// - **JWT** access + refresh tokens (refresh hashed at rest, rotated on use, race-safe)
// - **Zod** request validation, **Helmet** / **CORS** / in-memory rate limits
// - **OpenAPI 3.1** built in code, rendered by Swagger UI, Redoc, and Scalar; Postman collection derived from the same document
// - Deployed as one **Vercel** serverless function (`server/api/index.js`); local `node src/server.js` for development
//
// ## Wire contract (clients)
//
// All three clients speak the same shapes. Boards travel as a flat 16-element row-major array.
//
// ```json
// {
//   "board": [2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
//   "score": 40,
//   "bestScore": 1200,
//   "won": false,
//   "gameOver": false,
//   "moves": 12,
//   "elapsedSeconds": 90,
//   "baseRevision": 3,
//   "client": "ios",
//   "deviceId": "…"
// }
// ```
//
// `moves` measures how far a round has gone. Undo must not decrease it — a number a player can lower by pressing a button is not a progress signal for sync.
//
// ### Sync resolution
//
// `POST /api/v1/saves/sync` compares the device save with the stored `current` slot:
//
// | Resolution | Meaning |
// | --- | --- |
// | `uploaded` | This device's round is now `current` |
// | `downloaded` | The server's round replaced the local board |
// | `in_sync` | Nothing changed |
// | `conflicted` | The further round won; the other was parked in a recoverable conflict slot |
//
// Nothing is silently discarded. Prefer the higher `moves` (then score) when both sides advanced.
//
// ### What a client may offer
//
// A sign-in sends `save: null`. A round played before anyone signed in belongs
// to the device, not to the account that just signed in on it, so there is
// nothing to reconcile: the server either returns the account's own round
// (`downloaded`) or has none (`in_sync`, `save: null`) and the clean board the
// client just created stands. Clients keep that round in a storage slot of its
// own — see [ARCHITECTURE.md](../ARCHITECTURE.md#guest-and-account-profiles) —
// and a session's first upload happens on the first move made while signed in.
//
// Career statistics in `GET /api/v1/auth/me` are computed by the server from
// submitted rounds. Clients render them verbatim and never merge a local best
// score or highest tile into them.
//
// ## Auth
//
// - Register / login issue an access token (short TTL) and a refresh token (long TTL)
// - `POST /auth/reset-password` is an **interim** recovery path: a matching username and email set a new password and revoke every session. Knowing both is therefore account takeover, which is why it is gated behind `FEATURE_PASSWORD_RESET`, sits under the auth rate limiter, and answers identically whichever half is wrong. Replace it with a mailed single-use token before this service holds anything a person would mind losing.
// - Refresh rotates: the previous refresh hash is invalidated; concurrent refreshes are serialised on the client so two 401 retries cannot revoke each other
// - Access tokens live in memory or local storage per platform; see [privacy.md](privacy.md) for the deliberate Keychain / EncryptedSharedPreferences trade-offs
// - `Authorization: Bearer <access>` on protected routes; public leaderboard and health stay open
//
// ## Client map
//
// | Client | Cloud module | Bridge into the rules engine |
// | --- | --- | --- |
// | Web | `Web-Version/cloud.js`, `account.js` | `Game2048Game` exposes `cloudSave` / `applyCloudSave` plus `beginAccountSession` / `endAccountSession` |
// | Android | `…/cloud/*` + `CloudController` | `GameViewModel` cloud save / apply plus `beginAccountSession` / `endAccountSession` |
// | iOS | `Game-2048/Cloud/*` + `CloudController` | `GameViewModel.cloudSave()` / `applyCloudSave(_:)` plus `beginAccountSession(fresh:)` / `endAccountSession()` |
//
// Authenticating and adopting a round are separate calls on every client.
// `register` / `login` return a session and nothing more; the game then switches
// profile and asks the controller to adopt the account's round. Only the game
// knows which board is on screen, so only the game can decide what may be sent.
//
// Removing the cloud layer is a delete of those modules plus the header / banner wiring. The board and rules stay.
//
// ## Screenshots
//
// Canonical captures live under `images/` (`web-cloud-*`, `android-cloud-*`, and `ios-cloud-*`). Regenerate the browser set with `make screenshots-web` and the native set from booted simulators with `make screenshots-mobile`. QA-only native captures stay under `output/mobile/` when run through `make screenshots-mobile-qa`.
//
// ## Local development
//
// ```bash
// cd server
// cp .env.example .env   # fill MONGODB_URI, JWT secrets
// npm install
// npm run dev            # http://localhost:4000
// npm test               # unit
// npm run test:integration   # requires MONGODB_TEST_URI ending in _test
// npm run smoke          # against PUBLIC_URL or the live deploy
// ```
//
// Environment variables are documented in `server/.env.example`. Never commit `.env`. Production refuses to boot without `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET`.
//
// ## Deploy
//
// Deployed with the Vercel CLI (not GitHub integration):
//
// ```bash
// cd server
// vercel --prod
// ```
//
// Project env vars mirror `.env.example`. The function entry is `api/index.js`; static docs assets live under `public/`.
//
// ## Rate limits
//
// In-memory, per-instance. That stops a runaway client loop; it is not a distributed DDoS shield. Documented honestly so a Redis store can replace it later without redesigning callers.
//
// ## Feature flags
//
// `FEATURE_REGISTRATION`, `FEATURE_LEADERBOARDS`, `FEATURE_CLOUD_SAVES`, `FEATURE_SOCIAL`, `FEATURE_DAILY_CHALLENGE`, `FEATURE_EVENTS` — a disabled feature answers `503` with `feature_disabled` so surfaces can be retired without redeploying every client.

// SOURCE: server/src/docs/openapi.js

// /**
//  * The OpenAPI 3.1 description of this API.
//  *
//  * It is a single document built in code rather than a scatter of JSDoc
//  * annotations, for one reason: a reference page is read top to bottom by a
//  * human deciding whether to use the API, and that reading order is impossible
//  * to control when the source is comment fragments distributed across a dozen
//  * route files. Here the tag order, the prose, and the examples are all
//  * deliberate.
//  *
//  * `tests/unit/openapi.test.js` asserts that every route the Express app mounts
//  * appears here, so the document cannot silently fall behind the code.
//  */
// import config from "../config/env.js";
// import schemas from "./schemas.js";
//
// const BASE = "/api/v1";
//
// /* ---------------------------------------------------------------------- */
// /* Builders                                                                */
// /* ---------------------------------------------------------------------- */
//
// const ref = name => ({ $ref: `#/components/schemas/${name}` });
//
// const body = (schema, { required = true, description } = {}) => ({
//     required,
//     ...(description ? { description } : {}),
//     content: { "application/json": { schema } }
// });
//
// const response = (description, schema) => ({
//     description,
//     ...(schema ? { content: { "application/json": { schema } } } : {})
// });
//
// const errorResponse = description => response(description, ref("Error"));
//
// const query = (name, schema, description, extra = {}) => ({ name, in: "query", schema, description, ...extra });
// const pathParam = (name, schema, description) => ({ name, in: "path", required: true, schema, description });
//
// const PAGINATION_PARAMS = [
//     query("limit", { type: "integer", minimum: 1, maximum: config.limits.pageSizeMax, default: config.limits.pageSizeDefault }, "Page size."),
//     query("offset", { type: "integer", minimum: 0, default: 0 }, "Rows to skip.")
// ];
//
// const PERIOD_PARAM = query(
//     "period",
//     { type: "string", enum: ["daily", "weekly", "monthly", "yearly", "all"], default: "all" },
//     "Window to rank within. All windows are UTC; `GET /leaderboard/periods` returns the exact boundaries."
// );
//
// const MODE_PARAM = query("mode", { type: "string", enum: ["classic", "daily"], default: "classic" }, "Which board to read.");
//
// /**
//  * @param {object} spec
//  * @param {string} spec.tag
//  * @param {string} spec.summary
//  * @param {string} [spec.description]
//  * @param {boolean} [spec.auth]
//  */
// function operation({ tag, summary, description, auth = false, parameters, requestBody, responses, operationId }) {
//     return {
//         tags: [tag],
//         operationId,
//         summary,
//         ...(description ? { description } : {}),
//         ...(auth ? { security: [{ bearerAuth: [] }] } : { security: [] }),
//         ...(parameters ? { parameters } : {}),
//         ...(requestBody ? { requestBody } : {}),
//         responses: {
//             ...responses,
//             "422": errorResponse("The request failed validation. `error.details.issues` names each offending field."),
//             ...(auth ? { "401": errorResponse("Missing, expired, or malformed access token.") } : {}),
//             "429": errorResponse("Rate limit exceeded."),
//             "500": errorResponse("Unhandled server error.")
//         }
//     };
// }
//
// /* ---------------------------------------------------------------------- */
// /* Paths                                                                    */
// /* ---------------------------------------------------------------------- */
//
// const metaPaths = {
//     [`${BASE}/health`]: {
//         get: operation({
//             tag: "Meta",
//             operationId: "getHealth",
//             summary: "Liveness",
//             description:
//                 "Answers whether the process is running. It deliberately does **not** touch the database: a health check that fails because a dependency is slow invites a platform to restart a service that was fine. Use `/ready` for the dependency question.",
//             responses: { "200": response("The service is running.", { type: "object", properties: { status: { type: "string", example: "ok" }, version: { type: "string" }, uptimeSeconds: { type: "integer" } } }) }
//         })
//     },
//     [`${BASE}/ready`]: {
//         get: operation({
//             tag: "Meta",
//             operationId: "getReadiness",
//             summary: "Readiness, including a database ping",
//             responses: {
//                 "200": response("The database answered.", { type: "object", properties: { status: { type: "string" }, database: { type: "object", additionalProperties: true } } }),
//                 "503": response("The database is unreachable.", { type: "object", additionalProperties: true })
//             }
//         })
//     },
//     [`${BASE}/version`]: {
//         get: operation({ tag: "Meta", operationId: "getVersion", summary: "Build and runtime versions", responses: { "200": response("Version information.", { type: "object", additionalProperties: true }) } })
//     },
//     [`${BASE}/config`]: {
//         get: operation({
//             tag: "Meta",
//             operationId: "getClientConfig",
//             summary: "Public client configuration",
//             description: "Feature flags and limits, read once at start-up so clients do not hard-code values the server also enforces.",
//             responses: { "200": response("Client configuration.", { type: "object", additionalProperties: true }) }
//         })
//     },
//     [`${BASE}/metrics`]: {
//         get: operation({
//             tag: "Meta",
//             operationId: "getMetrics",
//             summary: "Request counters for this instance",
//             description: "Counters belong to one warm serverless instance and reset when it recycles. They are not fleet-wide totals.",
//             responses: { "200": response("Counters.", { type: "object", additionalProperties: true }) }
//         })
//     },
//     [`${BASE}/metrics.prom`]: {
//         get: operation({
//             tag: "Meta",
//             operationId: "getPrometheusMetrics",
//             summary: "The same counters in Prometheus exposition format",
//             responses: { "200": { description: "Prometheus text.", content: { "text/plain": { schema: { type: "string" } } } } }
//         })
//     }
// };
//
// const authPaths = {
//     [`${BASE}/auth/register`]: {
//         post: operation({
//             tag: "Authentication",
//             operationId: "register",
//             summary: "Create an account",
//             description: "Returns a token pair immediately, so a player who signs up mid-round can sync without a second request.",
//             requestBody: body({
//                 type: "object",
//                 required: ["username", "email", "password"],
//                 properties: {
//                     username: { type: "string", minLength: 3, maxLength: 24, example: "ada" },
//                     email: { type: "string", format: "email", example: "ada@example.com" },
//                     password: { type: "string", minLength: 8, description: "At least 8 characters, including one letter and one number." },
//                     displayName: { type: "string", maxLength: 40 },
//                     country: { type: "string", minLength: 2, maxLength: 2, example: "GB" },
//                     client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] }
//                 }
//             }),
//             responses: {
//                 "201": response("Account created and signed in.", ref("AuthResponse")),
//                 "409": errorResponse("The username or email address is already taken. `error.details.field` says which."),
//                 "403": errorResponse("Registration is closed on this deployment.")
//             }
//         })
//     },
//     [`${BASE}/auth/login`]: {
//         post: operation({
//             tag: "Authentication",
//             operationId: "login",
//             summary: "Sign in",
//             description: "An unknown account and a wrong password return the same error, so this endpoint cannot be used to discover who has an account.",
//             requestBody: body({
//                 type: "object",
//                 required: ["identifier", "password"],
//                 properties: {
//                     identifier: { type: "string", description: "Username or email address.", example: "ada" },
//                     password: { type: "string" },
//                     client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] }
//                 }
//             }),
//             responses: { "200": response("Signed in.", ref("AuthResponse")), "401": errorResponse("Invalid credentials.") }
//         })
//     },
//     [`${BASE}/auth/refresh`]: {
//         post: operation({
//             tag: "Authentication",
//             operationId: "refresh",
//             summary: "Rotate a token pair",
//             description: "Refresh tokens are single-use. Replaying a rotated token revokes the whole session, which is what turns a stolen token into a detectable event rather than a silent one.",
//             requestBody: body({ type: "object", required: ["refreshToken"], properties: { refreshToken: { type: "string" } } }),
//             responses: { "200": response("A fresh pair.", ref("AuthResponse")), "401": errorResponse("The session is gone, expired, or the token was already rotated.") }
//         })
//     },
//     [`${BASE}/auth/logout`]: {
//         post: operation({
//             tag: "Authentication",
//             operationId: "logout",
//             summary: "Revoke one session",
//             requestBody: body({ type: "object", properties: { refreshToken: { type: "string" } } }, { required: false }),
//             responses: { "200": response("Signed out.", { type: "object", properties: { signedOut: { type: "boolean" } } }) }
//         })
//     },
//     [`${BASE}/auth/logout-all`]: {
//         post: operation({
//             tag: "Authentication",
//             operationId: "logoutAll",
//             summary: "Revoke every session on the account",
//             auth: true,
//             responses: { "200": response("All sessions revoked.", { type: "object", properties: { signedOut: { type: "boolean" }, sessionsRevoked: { type: "integer" } } }) }
//         })
//     },
//     [`${BASE}/auth/me`]: {
//         get: operation({ tag: "Authentication", operationId: "getCurrentUser", summary: "The signed-in account", auth: true, responses: { "200": response("The account.", { type: "object", properties: { user: ref("PrivateUser") } }) } }),
//         patch: operation({
//             tag: "Authentication",
//             operationId: "updateCurrentUser",
//             summary: "Update profile fields",
//             auth: true,
//             requestBody: body({
//                 type: "object",
//                 properties: {
//                     displayName: { type: "string", maxLength: 40 },
//                     country: { type: "string", minLength: 2, maxLength: 2, nullable: true },
//                     avatarColor: { type: "string", pattern: "^#[0-9a-fA-F]{6}$" },
//                     bio: { type: "string", maxLength: 280 }
//                 }
//             }),
//             responses: { "200": response("Updated.", { type: "object", properties: { user: ref("PrivateUser") } }) }
//         }),
//         delete: operation({
//             tag: "Authentication",
//             operationId: "deleteAccount",
//             summary: "Delete the account and every trace of it",
//             description: "Removes the account, its sessions, saves, scores, achievements, follows, and telemetry in one request. There is no tombstone and no recovery window.",
//             auth: true,
//             requestBody: body({ type: "object", required: ["password", "confirm"], properties: { password: { type: "string" }, confirm: { type: "string", enum: ["DELETE"] } } }),
//             responses: { "200": response("Deleted.", { type: "object", properties: { deleted: { type: "boolean" } } }), "401": errorResponse("The password is wrong.") }
//         })
//     },
//     [`${BASE}/auth/change-password`]: {
//         post: operation({
//             tag: "Authentication",
//             operationId: "changePassword",
//             summary: "Change the password",
//             description: "By default every other session is revoked, because a password change that leaves other devices signed in is not a password change.",
//             auth: true,
//             requestBody: body({
//                 type: "object",
//                 required: ["currentPassword", "newPassword"],
//                 properties: { currentPassword: { type: "string" }, newPassword: { type: "string", minLength: 8 }, signOutOtherSessions: { type: "boolean", default: true } }
//             }),
//             responses: { "200": response("Changed.", { type: "object", properties: { changed: { type: "boolean" }, sessionsRevoked: { type: "integer" } } }), "401": errorResponse("The current password is wrong.") }
//         })
//     },
//     [`${BASE}/auth/reset-password`]: {
//         post: operation({
//             tag: "Authentication",
//             operationId: "resetPassword",
//             summary: "Reset a forgotten password",
//             description:
//                 "Interim recovery path with no email round trip: a matching username and email address are enough to set a new password, and every session on the account is revoked. Knowing both is therefore account takeover, so this is gated behind `FEATURE_PASSWORD_RESET` and the auth rate limiter, and answers identically whichever half is wrong. Replace with a mailed single-use token before relying on it.",
//             requestBody: body({
//                 type: "object",
//                 required: ["username", "email", "newPassword"],
//                 properties: {
//                     username: { type: "string", minLength: 3, maxLength: 24 },
//                     email: { type: "string", format: "email" },
//                     newPassword: { type: "string", minLength: 8 }
//                 }
//             }),
//             responses: {
//                 "200": response("Reset.", { type: "object", properties: { reset: { type: "boolean" }, sessionsRevoked: { type: "integer" } } }),
//                 "401": errorResponse("The username and email do not match an account."),
//                 "503": errorResponse("Password reset is disabled on this deployment.")
//             }
//         })
//     },
//     [`${BASE}/auth/sessions`]: {
//         get: operation({ tag: "Authentication", operationId: "listSessions", summary: "List signed-in devices", auth: true, responses: { "200": response("Sessions, newest first.", { type: "object", properties: { items: { type: "array", items: ref("Session") } } }) } })
//     },
//     [`${BASE}/auth/sessions/{sessionId}`]: {
//         delete: operation({
//             tag: "Authentication",
//             operationId: "revokeSession",
//             summary: "Revoke one device",
//             auth: true,
//             parameters: [pathParam("sessionId", { type: "string", format: "uuid" }, "Session identifier from `GET /auth/sessions`.")],
//             responses: { "200": response("Revoked.", { type: "object", properties: { revoked: { type: "boolean" }, id: { type: "string" } } }), "404": errorResponse("No such session on this account.") }
//         })
//     },
//     [`${BASE}/auth/available`]: {
//         get: operation({
//             tag: "Authentication",
//             operationId: "checkAvailability",
//             summary: "Check whether a username or email is free",
//             description: "Intended for inline validation on a sign-up form. The unique indexes remain the real guarantee; this is a better error message, not the enforcement.",
//             parameters: [query("username", { type: "string" }, "Username to test."), query("email", { type: "string", format: "email" }, "Email address to test.")],
//             responses: { "200": response("Availability.", { type: "object", additionalProperties: true }) }
//         })
//     }
// };
//
// const userPaths = {
//     [`${BASE}/users`]: {
//         get: operation({
//             tag: "Players",
//             operationId: "listPlayers",
//             summary: "Search players",
//             description: "Matching is an anchored prefix on the username so the query uses an index rather than scanning the collection on every keystroke.",
//             parameters: [...PAGINATION_PARAMS, query("q", { type: "string" }, "Username prefix."), query("sort", { type: "string", enum: ["best", "recent", "name"], default: "best" }, "Ordering.")],
//             responses: { "200": response("Matching players.", { type: "object", properties: { items: { type: "array", items: ref("PublicUser") }, pagination: ref("Pagination") } }) }
//         })
//     },
//     [`${BASE}/users/me/preferences`]: {
//         get: operation({ tag: "Players", operationId: "getPreferences", summary: "Read preferences", auth: true, responses: { "200": response("Preferences.", { type: "object", properties: { preferences: ref("Preferences") } }) } }),
//         put: operation({
//             tag: "Players",
//             operationId: "updatePreferences",
//             summary: "Update preferences",
//             auth: true,
//             requestBody: body(ref("Preferences")),
//             responses: { "200": response("Updated.", { type: "object", properties: { preferences: ref("Preferences") } }) }
//         })
//     },
//     [`${BASE}/users/me/export`]: {
//         get: operation({
//             tag: "Players",
//             operationId: "exportAccountData",
//             summary: "Download everything stored about the account",
//             description: "The counterpart to account deletion: data about a player should be theirs to read as well as theirs to remove.",
//             auth: true,
//             responses: { "200": response("A JSON export.", { type: "object", additionalProperties: true }) }
//         })
//     },
//     [`${BASE}/users/{username}`]: {
//         get: operation({
//             tag: "Players",
//             operationId: "getPlayer",
//             summary: "A public profile",
//             parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")],
//             responses: { "200": response("The profile.", { type: "object", properties: { user: ref("PublicUser"), isSelf: { type: "boolean" } } }), "404": errorResponse("No such player.") }
//         })
//     },
//     [`${BASE}/users/{username}/scores`]: {
//         get: operation({
//             tag: "Players",
//             operationId: "getPlayerScores",
//             summary: "A player's best rounds",
//             parameters: [pathParam("username", { type: "string" }, "Case-insensitive username."), ...PAGINATION_PARAMS],
//             responses: { "200": response("Scores, highest first.", { type: "object", properties: { items: { type: "array", items: ref("Score") }, pagination: ref("Pagination") } }), "403": errorResponse("That profile is private."), "404": errorResponse("No such player.") }
//         })
//     },
//     [`${BASE}/users/{username}/achievements`]: {
//         get: operation({
//             tag: "Players",
//             operationId: "getPlayerAchievements",
//             summary: "A player's achievements",
//             parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")],
//             responses: { "200": response("Achievements and a completion summary.", { type: "object", properties: { items: { type: "array", items: ref("Achievement") }, summary: { type: "object", additionalProperties: true } } }), "403": errorResponse("That profile is private."), "404": errorResponse("No such player.") }
//         })
//     },
//     [`${BASE}/users/{username}/stats`]: {
//         get: operation({
//             tag: "Players",
//             operationId: "getPlayerStats",
//             summary: "A player's statistics",
//             parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")],
//             responses: { "200": response("Statistics.", ref("PersonalStats")), "403": errorResponse("That profile is private."), "404": errorResponse("No such player.") }
//         })
//     }
// };
//
// const savePaths = {
//     [`${BASE}/saves`]: {
//         get: operation({ tag: "Cloud saves", operationId: "listSaves", summary: "List every slot", auth: true, responses: { "200": response("Slots, most recently updated first.", { type: "object", properties: { items: { type: "array", items: ref("GameSave") }, limits: { type: "object", additionalProperties: true } } }) } }),
//         delete: operation({
//             tag: "Cloud saves",
//             operationId: "deleteAllSaves",
//             summary: "Delete every slot",
//             auth: true,
//             requestBody: body({ type: "object", required: ["confirm"], properties: { confirm: { type: "string", enum: ["DELETE"] } } }),
//             responses: { "200": response("Deleted.", { type: "object", properties: { deleted: { type: "boolean" }, count: { type: "integer" } } }) }
//         })
//     },
//     [`${BASE}/saves/sync`]: {
//         post: operation({
//             tag: "Cloud saves",
//             operationId: "syncSave",
//             summary: "Two-way synchronisation",
//             description:
//                 "The endpoint to call on launch, on sign-in, and on reconnect — the only one that can reconcile two devices without losing a round.\n\n" +
//                 "Resolution order: no remote save uploads the local one; no local save downloads the remote one; identical rounds report `in_sync`; " +
//                 "a local save carrying a `baseRevision` at or above the stored revision is a continuation and uploads; otherwise the further round (score, then moves) wins and **the other is preserved in a `conflict-…` slot**. Nothing is discarded.",
//             auth: true,
//             requestBody: body({
//                 type: "object",
//                 properties: {
//                     slot: { type: "string", default: "current" },
//                     strategy: { type: "string", enum: ["auto", "prefer-local", "prefer-remote"], default: "auto", description: "`auto` applies the resolution order above. The other two are for an explicit user choice after a conflict." },
//                     save: { oneOf: [ref("SavePayload"), { type: "null" }], description: "The device's local save, or null when it has none." }
//                 }
//             }),
//             responses: { "200": response("Resolved.", ref("SyncResult")) }
//         })
//     },
//     [`${BASE}/saves/current`]: {
//         get: operation({ tag: "Cloud saves", operationId: "getCurrentSave", summary: "Read the active round", auth: true, responses: { "200": response("The save.", { type: "object", properties: { save: ref("GameSave") } }), "404": errorResponse("No cloud save yet.") } }),
//         put: operation({
//             tag: "Cloud saves",
//             operationId: "putCurrentSave",
//             summary: "Overwrite the active round",
//             description: "Unconditional: the caller's save wins. Use `POST /saves/sync` unless the player has explicitly chosen this device's round.",
//             auth: true,
//             requestBody: body(ref("SavePayload")),
//             responses: { "200": response("Stored.", { type: "object", properties: { save: ref("GameSave"), resolution: { type: "string" } } }) }
//         })
//     },
//     [`${BASE}/saves/{slot}`]: {
//         get: operation({ tag: "Cloud saves", operationId: "getSave", summary: "Read a slot", auth: true, parameters: [pathParam("slot", { type: "string" }, "Slot name.")], responses: { "200": response("The save.", { type: "object", properties: { save: ref("GameSave") } }), "404": errorResponse("No such slot.") } }),
//         put: operation({
//             tag: "Cloud saves",
//             operationId: "putSave",
//             summary: "Create or overwrite a slot",
//             auth: true,
//             parameters: [pathParam("slot", { type: "string" }, "Slot name.")],
//             requestBody: body(ref("SavePayload")),
//             responses: { "200": response("Updated.", { type: "object", properties: { save: ref("GameSave") } }), "201": response("Created.", { type: "object", properties: { save: ref("GameSave") } }), "409": errorResponse("The slot limit for this account is already reached.") }
//         }),
//         delete: operation({ tag: "Cloud saves", operationId: "deleteSave", summary: "Delete a slot", auth: true, parameters: [pathParam("slot", { type: "string" }, "Slot name.")], responses: { "200": response("Deleted.", { type: "object", properties: { deleted: { type: "boolean" }, slot: { type: "string" } } }), "404": errorResponse("No such slot.") } })
//     }
// };
//
// const scorePaths = {
//     [`${BASE}/scores`]: {
//         post: operation({
//             tag: "Scores",
//             operationId: "submitScore",
//             summary: "Submit a finished round",
//             description:
//                 "Idempotent: the same board and score from the same player returns the original row with `duplicate: true` and a 200 rather than creating a second leaderboard entry, so a retry after a flaky network is safe.\n\n" +
//                 "A score that exceeds what its final board could have produced is stored with `verified: false` and kept out of every leaderboard. It is flagged rather than refused, because refusing would lose a genuine round to a client bug.",
//             auth: true,
//             requestBody: body({
//                 type: "object",
//                 required: ["score"],
//                 properties: {
//                     board: ref("Board"),
//                     grid: ref("Board"),
//                     score: { type: "integer", minimum: 0 },
//                     moves: { type: "integer", minimum: 0 },
//                     durationSeconds: { type: "integer", minimum: 0 },
//                     mode: { type: "string", enum: ["classic", "daily"], default: "classic" },
//                     challengeDate: { type: "string", nullable: true },
//                     client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] }
//                 }
//             }),
//             responses: {
//                 "201": response("Recorded.", { type: "object", properties: { score: ref("Score"), duplicate: { type: "boolean" }, unlockedAchievements: { type: "array", items: ref("Achievement") }, statistics: ref("Statistics") } }),
//                 "200": response("Already recorded; the original row is returned.", { type: "object", properties: { score: ref("Score"), duplicate: { type: "boolean" } } })
//             }
//         }),
//         get: operation({
//             tag: "Scores",
//             operationId: "listMyScores",
//             summary: "The signed-in player's rounds",
//             auth: true,
//             parameters: [
//                 ...PAGINATION_PARAMS,
//                 query("mode", { type: "string", enum: ["classic", "daily", "all"], default: "all" }, "Filter by mode."),
//                 query("sort", { type: "string", enum: ["recent", "score"], default: "recent" }, "Ordering."),
//                 query("wonOnly", { type: "boolean", default: false }, "Only rounds that reached 2048.")
//             ],
//             responses: { "200": response("Rounds.", { type: "object", properties: { items: { type: "array", items: ref("Score") }, pagination: ref("Pagination") } }) }
//         })
//     },
//     [`${BASE}/scores/best`]: {
//         get: operation({ tag: "Scores", operationId: "getPersonalBest", summary: "Personal best", auth: true, responses: { "200": response("The best verified round, or null.", { type: "object", properties: { best: { oneOf: [ref("Score"), { type: "null" }] } } }) } })
//     },
//     [`${BASE}/scores/stats`]: {
//         get: operation({ tag: "Scores", operationId: "getMyScoreStats", summary: "Career statistics", auth: true, responses: { "200": response("Statistics.", ref("PersonalStats")) } })
//     },
//     [`${BASE}/scores/{id}`]: {
//         get: operation({ tag: "Scores", operationId: "getScore", summary: "One round, with its final board", auth: true, parameters: [pathParam("id", { type: "string" }, "Score identifier.")], responses: { "200": response("The round.", { type: "object", properties: { score: ref("Score") } }), "404": errorResponse("No such round on this account.") } }),
//         delete: operation({
//             tag: "Scores",
//             operationId: "deleteScore",
//             summary: "Delete a round",
//             description: "Career totals are intentionally left alone: they record rounds played, and making `gamesPlayed` go down because a row was removed is not what anyone expects.",
//             auth: true,
//             parameters: [pathParam("id", { type: "string" }, "Score identifier.")],
//             responses: { "200": response("Deleted.", { type: "object", properties: { deleted: { type: "boolean" } } }), "404": errorResponse("No such round on this account.") }
//         })
//     }
// };
//
// const leaderboardPaths = {
//     [`${BASE}/leaderboard`]: {
//         get: operation({
//             tag: "Leaderboard",
//             operationId: "getLeaderboard",
//             summary: "A ranked page",
//             description:
//                 "One row per player — their best qualifying round in the window, never three of the same player's games in the top ten. Ties break by the earlier submission, so a player's rank does not drift between two identical requests.\n\n" +
//                 "Authenticated requests mark the viewer's own row with `isViewer` and are never shared-cached.",
//             parameters: [...PAGINATION_PARAMS, PERIOD_PARAM, MODE_PARAM, query("challengeDate", { type: "string" }, "For `mode=daily`, the challenge date.")],
//             responses: { "200": response("A page of the board.", ref("LeaderboardPage")) }
//         })
//     },
//     [`${BASE}/leaderboard/periods`]: {
//         get: operation({ tag: "Leaderboard", operationId: "getLeaderboardPeriods", summary: "The exact UTC boundaries of every window", responses: { "200": response("Window boundaries.", { type: "object", additionalProperties: true }) } })
//     },
//     [`${BASE}/leaderboard/me`]: {
//         get: operation({ tag: "Leaderboard", operationId: "getMyRank", summary: "The signed-in player's rank", auth: true, parameters: [PERIOD_PARAM, MODE_PARAM], responses: { "200": response("Rank and percentile.", ref("Rank")) } })
//     },
//     [`${BASE}/leaderboard/around-me`]: {
//         get: operation({
//             tag: "Leaderboard",
//             operationId: "getRanksAroundMe",
//             summary: "The slice of the board around the player",
//             auth: true,
//             parameters: [PERIOD_PARAM, MODE_PARAM, query("radius", { type: "integer", minimum: 1, maximum: 25, default: 4 }, "Rows either side.")],
//             responses: { "200": response("Neighbouring ranks.", { type: "object", additionalProperties: true }) }
//         })
//     },
//     [`${BASE}/leaderboard/friends`]: {
//         get: operation({ tag: "Leaderboard", operationId: "getFriendsLeaderboard", summary: "A board of the people the player follows", auth: true, parameters: [...PAGINATION_PARAMS, PERIOD_PARAM], responses: { "200": response("A page of the board.", ref("LeaderboardPage")) } })
//     },
//     [`${BASE}/leaderboard/users/{username}`]: {
//         get: operation({ tag: "Leaderboard", operationId: "getPlayerRank", summary: "Any player's rank", parameters: [pathParam("username", { type: "string" }, "Case-insensitive username."), PERIOD_PARAM, MODE_PARAM], responses: { "200": response("Rank and percentile.", ref("Rank")), "404": errorResponse("No such player.") } })
//     }
// };
//
// const achievementPaths = {
//     [`${BASE}/achievements`]: {
//         get: operation({ tag: "Achievements", operationId: "listAchievements", summary: "The catalog", description: "Definitions are compiled into the build, so this changes only on deploy and is cached for an hour.", responses: { "200": response("Every achievement.", { type: "object", properties: { items: { type: "array", items: ref("Achievement") } } }) } })
//     },
//     [`${BASE}/achievements/me`]: {
//         get: operation({ tag: "Achievements", operationId: "getMyAchievements", summary: "Progress for the signed-in player", auth: true, responses: { "200": response("Every achievement, earned or not, plus a completion summary.", { type: "object", properties: { items: { type: "array", items: ref("Achievement") }, summary: { type: "object", additionalProperties: true } } }) } })
//     },
//     [`${BASE}/achievements/{key}`]: {
//         get: operation({ tag: "Achievements", operationId: "getAchievement", summary: "One definition", parameters: [pathParam("key", { type: "string" }, "Achievement key, for example `tile_2048`.")], responses: { "200": response("The definition.", { type: "object", properties: { achievement: ref("Achievement") } }), "404": errorResponse("No such achievement.") } })
//     }
// };
//
// const statsPaths = {
//     [`${BASE}/stats/global`]: {
//         get: operation({ tag: "Statistics", operationId: "getGlobalStats", summary: "Service-wide totals", responses: { "200": response("Totals.", ref("GlobalStats")) } })
//     },
//     [`${BASE}/stats/tiles`]: {
//         get: operation({ tag: "Statistics", operationId: "getTileDistribution", summary: "How far rounds get", description: "The share of rounds ending at each highest tile — the clearest single picture of the difficulty curve.", responses: { "200": response("Distribution.", { type: "object", additionalProperties: true }) } })
//     },
//     [`${BASE}/stats/activity`]: {
//         get: operation({ tag: "Statistics", operationId: "getActivitySeries", summary: "A dense daily series", description: "Days with no games appear as zeroes rather than being omitted, so the series can be charted without silently rewriting the x-axis.", parameters: [query("days", { type: "integer", minimum: 1, maximum: 365, default: 30 }, "Length of the window.")], responses: { "200": response("The series.", { type: "object", additionalProperties: true }) } })
//     },
//     [`${BASE}/stats/me`]: {
//         get: operation({ tag: "Statistics", operationId: "getMyStats", summary: "The signed-in player's statistics", auth: true, responses: { "200": response("Statistics.", ref("PersonalStats")) } })
//     },
//     [`${BASE}/stats/me/activity`]: {
//         get: operation({ tag: "Statistics", operationId: "getMyActivity", summary: "The signed-in player's daily series", auth: true, parameters: [query("days", { type: "integer", minimum: 1, maximum: 365, default: 30 }, "Length of the window.")], responses: { "200": response("The series.", { type: "object", additionalProperties: true }) } })
//     }
// };
//
// const socialPaths = {
//     [`${BASE}/social/follow/{username}`]: {
//         post: operation({ tag: "Social", operationId: "followPlayer", summary: "Follow a player", description: "Idempotent: following twice succeeds rather than returning a duplicate-key error the client has to special-case.", auth: true, parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")], responses: { "201": response("Now following.", { type: "object", additionalProperties: true }), "200": response("Already following.", { type: "object", additionalProperties: true }), "400": errorResponse("You cannot follow yourself.") } }),
//         delete: operation({ tag: "Social", operationId: "unfollowPlayer", summary: "Unfollow a player", auth: true, parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")], responses: { "200": response("No longer following.", { type: "object", additionalProperties: true }) } })
//     },
//     [`${BASE}/social/following`]: {
//         get: operation({ tag: "Social", operationId: "listFollowing", summary: "Who the player follows", auth: true, parameters: PAGINATION_PARAMS, responses: { "200": response("Players.", { type: "object", properties: { items: { type: "array", items: ref("PublicUser") }, pagination: ref("Pagination") } }) } })
//     },
//     [`${BASE}/social/followers`]: {
//         get: operation({ tag: "Social", operationId: "listFollowers", summary: "Who follows the player", auth: true, parameters: PAGINATION_PARAMS, responses: { "200": response("Players.", { type: "object", properties: { items: { type: "array", items: ref("PublicUser") }, pagination: ref("Pagination") } }) } })
//     },
//     [`${BASE}/social/relationship/{username}`]: {
//         get: operation({ tag: "Social", operationId: "getRelationship", summary: "The edge between two players", auth: true, parameters: [pathParam("username", { type: "string" }, "Case-insensitive username.")], responses: { "200": response("Both directions.", { type: "object", additionalProperties: true }) } })
//     },
//     [`${BASE}/social/suggestions`]: {
//         get: operation({ tag: "Social", operationId: "getFollowSuggestions", summary: "Players worth following", description: "Strong players the viewer does not already follow. The heuristic is deliberately that simple.", auth: true, parameters: [query("limit", { type: "integer", minimum: 1, maximum: 25, default: 10 }, "How many.")], responses: { "200": response("Suggestions.", { type: "object", properties: { items: { type: "array", items: ref("PublicUser") } } }) } })
//     }
// };
//
// const challengePaths = {
//     [`${BASE}/challenges/daily`]: {
//         get: operation({
//             tag: "Daily challenge",
//             operationId: "getDailyChallenge",
//             summary: "Today's challenge",
//             description: "The board is *derived* from the date with a seeded generator, not stored, so every client gets the same opening position and can reproduce it offline from the seed alone.",
//             responses: { "200": response("The challenge.", { type: "object", properties: { challenge: ref("DailyChallenge"), attempted: { type: "boolean" } } }) }
//         })
//     },
//     [`${BASE}/challenges/daily/leaderboard`]: {
//         get: operation({ tag: "Daily challenge", operationId: "getDailyLeaderboard", summary: "The board for one day", parameters: [...PAGINATION_PARAMS, query("date", { type: "string", example: "2026-09-18" }, "Defaults to today (UTC).")], responses: { "200": response("A page of the board.", { type: "object", additionalProperties: true }) } })
//     },
//     [`${BASE}/challenges/daily/me`]: {
//         get: operation({ tag: "Daily challenge", operationId: "getMyDailyRank", summary: "The player's rank in a day's challenge", auth: true, parameters: [query("date", { type: "string" }, "Defaults to today (UTC).")], responses: { "200": response("Rank and percentile.", ref("Rank")) } })
//     },
//     [`${BASE}/challenges/daily/submit`]: {
//         post: operation({
//             tag: "Daily challenge",
//             operationId: "submitDailyScore",
//             summary: "Submit today's attempt",
//             description: "Only today's challenge accepts submissions. Without that rule the daily board becomes a backlog anyone can grind through.",
//             auth: true,
//             requestBody: body({
//                 type: "object",
//                 required: ["score"],
//                 properties: { date: { type: "string" }, board: ref("Board"), grid: ref("Board"), score: { type: "integer", minimum: 0 }, moves: { type: "integer", minimum: 0 }, durationSeconds: { type: "integer", minimum: 0 }, client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] } }
//             }),
//             responses: { "201": response("Recorded.", { type: "object", additionalProperties: true }), "200": response("Already recorded.", { type: "object", additionalProperties: true }), "400": errorResponse("The date is invalid or is not today.") }
//         })
//     },
//     [`${BASE}/challenges/daily/{date}`]: {
//         get: operation({ tag: "Daily challenge", operationId: "getChallengeForDate", summary: "Any day's challenge", parameters: [pathParam("date", { type: "string", example: "2026-09-18" }, "ISO date.")], responses: { "200": response("The challenge.", { type: "object", properties: { challenge: ref("DailyChallenge") } }), "400": errorResponse("Not a valid calendar date.") } })
//     }
// };
//
// const eventPaths = {
//     [`${BASE}/events`]: {
//         post: operation({
//             tag: "Telemetry",
//             operationId: "recordEvents",
//             summary: "Record gameplay events",
//             description:
//                 "Coarse, opt-in, pseudonymous, and closed-vocabulary: both the event types and the metadata keys are enumerated, so this cannot become a general sink or accidentally carry a board. Rows expire after 90 days. See `docs/privacy.md`.",
//             requestBody: body({
//                 type: "object",
//                 required: ["events"],
//                 properties: {
//                     client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] },
//                     anonymousId: { type: "string", maxLength: 64, description: "Ignored for signed-in callers, so the two identities are never linked." },
//                     events: { type: "array", minItems: 1, maxItems: config.limits.maxEventsPerBatch, items: { type: "object", additionalProperties: true } }
//                 }
//             }),
//             responses: { "202": response("Accepted.", { type: "object", properties: { accepted: { type: "integer" } } }) }
//         })
//     },
//     [`${BASE}/events/summary`]: {
//         get: operation({ tag: "Telemetry", operationId: "getEventSummary", summary: "Event counts by type and client", parameters: [query("days", { type: "integer", minimum: 1, maximum: 90, default: 7 }, "Window length.")], responses: { "200": response("Counts.", { type: "object", additionalProperties: true }) } })
//     }
// };
//
// /* ---------------------------------------------------------------------- */
// /* Document                                                                 */
// /* ---------------------------------------------------------------------- */
//
// export function buildOpenApiDocument({ serverUrl = config.publicUrl } = {}) {
//     return {
//         openapi: "3.1.0",
//         info: {
//             title: "2048 Cloud API",
//             version: config.version,
//             summary: "Accounts, cross-device saves, leaderboards, achievements, and statistics for the 2048 game.",
//             description: [
//                 "This API is the optional cloud half of [2048](https://hoangsonww.github.io/2048-Game/). The game itself is still entirely local: every client plays, scores, undoes, and saves without ever calling this service, and a player who never signs in never touches it.",
//                 "",
//                 "What an account adds is continuity — the same round and the same best score on a laptop, a phone, and a tablet — plus leaderboards, achievements, and a daily challenge.",
//                 "",
//                 "The service root (`GET /`) redirects to this documentation at `/docs`. Machine-readable OpenAPI lives at `/openapi.json`; Redoc and Scalar are at `/redoc` and `/reference`.",
//                 "",
//                 "### Principles",
//                 "",
//                 "- **The game never depends on the network.** Every endpoint here is additive. If this service is down, all three clients keep working exactly as they did before it existed.",
//                 "- **Rules stay in the clients.** The server validates boards and sanity-checks scores; it never simulates a move. A single-player puzzle has no authoritative server simulation to offer.",
//                 "- **Nothing is silently discarded.** When two devices disagree about a round, the further one wins and the other is preserved in a conflict slot the player can recover.",
//                 "- **Deletion means deletion.** `DELETE /auth/me` removes the account and every row that references it, in one request, with no tombstone.",
//                 "",
//                 "### Authentication",
//                 "",
//                 "Send `Authorization: Bearer <accessToken>`. Access tokens are short-lived and stateless; refresh tokens are long-lived, stored only as a hash, and rotated on every use. Replaying a rotated refresh token revokes the session.",
//                 "",
//                 "### Errors",
//                 "",
//                 "Every failure is `{ \"error\": { \"code\", \"message\", \"details\"? }, \"requestId\" }`. Branch on `code`, never on `message`. Quote `requestId` in a bug report; it is also returned in the `X-Request-Id` header."
//             ].join("\n"),
//             contact: { name: "Son Nguyen", url: "https://github.com/hoangsonww/2048-Game" },
//             license: { name: "MIT", identifier: "MIT" }
//         },
//         servers: [
//             { url: serverUrl, description: "This deployment" },
//             { url: "http://localhost:4000", description: "Local development" }
//         ],
//         externalDocs: { description: "Repository and architecture notes", url: "https://github.com/hoangsonww/2048-Game/blob/main/docs/backend.md" },
//         tags: [
//             { name: "Meta", description: "Health, readiness, version, configuration, and counters." },
//             { name: "Authentication", description: "Accounts, tokens, sessions, and deletion." },
//             { name: "Players", description: "Profiles, preferences, search, and data export." },
//             { name: "Cloud saves", description: "Cross-device round synchronisation with conflict preservation." },
//             { name: "Scores", description: "Submitting and reading finished rounds." },
//             { name: "Leaderboard", description: "Ranked boards over UTC windows." },
//             { name: "Achievements", description: "The catalog and a player's progress through it." },
//             { name: "Statistics", description: "Aggregates, distributions, and activity series." },
//             { name: "Social", description: "Follows, used only to scope a leaderboard." },
//             { name: "Daily challenge", description: "A seeded board everyone plays on the same UTC day." },
//             { name: "Telemetry", description: "Coarse, opt-in, expiring gameplay events." }
//         ],
//         components: {
//             securitySchemes: {
//                 bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "JWT", description: "An access token from `/auth/login`, `/auth/register`, or `/auth/refresh`." }
//             },
//             schemas
//         },
//         security: [],
//         paths: {
//             ...metaPaths,
//             ...authPaths,
//             ...userPaths,
//             ...savePaths,
//             ...scorePaths,
//             ...leaderboardPaths,
//             ...achievementPaths,
//             ...statsPaths,
//             ...socialPaths,
//             ...challengePaths,
//             ...eventPaths
//         }
//     };
// }
//
// export default buildOpenApiDocument;

// SOURCE: server/src/docs/schemas.js

// /**
//  * Reusable OpenAPI component schemas.
//  *
//  * They are written by hand rather than generated from the Zod schemas. A
//  * generator would keep them mechanically in step but would also produce the
//  * shape of the *input* only, and would strip every example and description —
//  * which is most of what makes a reference page usable. The contract test in
//  * `tests/unit/openapi.test.js` is what keeps these honest: it asserts that
//  * every route the app actually mounts has a documented operation.
//  */
// export const schemas = {
//     Error: {
//         type: "object",
//         required: ["error"],
//         properties: {
//             error: {
//                 type: "object",
//                 required: ["code", "message"],
//                 properties: {
//                     code: { type: "string", example: "not_found", description: "Stable machine-readable identifier. Branch on this, never on the message." },
//                     message: { type: "string", example: "Score was not found." },
//                     details: { type: "object", additionalProperties: true }
//                 }
//             },
//             requestId: { type: "string", format: "uuid", description: "Echoed in the `X-Request-Id` response header. Quote it in a bug report." }
//         }
//     },
//
//     Pagination: {
//         type: "object",
//         properties: {
//             total: { type: "integer", example: 412 },
//             limit: { type: "integer", example: 25 },
//             offset: { type: "integer", example: 0 },
//             count: { type: "integer", example: 25 },
//             hasMore: { type: "boolean", example: true }
//         }
//     },
//
//     Board: {
//         description: "A board, either as 16 flat cells (row-major) or as a 4x4 grid. Every value is zero or a power of two.",
//         oneOf: [
//             { type: "array", items: { type: "integer", minimum: 0 }, minItems: 16, maxItems: 16 },
//             { type: "array", items: { type: "array", items: { type: "integer", minimum: 0 }, minItems: 4, maxItems: 4 }, minItems: 4, maxItems: 4 }
//         ],
//         example: [2, 4, 0, 0, 0, 8, 0, 0, 0, 0, 16, 0, 0, 0, 0, 2]
//     },
//
//     Preferences: {
//         type: "object",
//         properties: {
//             theme: { type: "string", enum: ["system", "light", "dark"] },
//             reducedMotion: { type: "boolean" },
//             soundEnabled: { type: "boolean" },
//             hapticsEnabled: { type: "boolean" },
//             autoSync: { type: "boolean", description: "Whether the client should sync automatically after each valid move." },
//             publicProfile: { type: "boolean" },
//             showOnLeaderboard: { type: "boolean", description: "Turning this off hides the player's rows without deleting them." }
//         }
//     },
//
//     Statistics: {
//         type: "object",
//         properties: {
//             bestScore: { type: "integer", example: 24_680 },
//             totalScore: { type: "integer", example: 812_400 },
//             gamesPlayed: { type: "integer", example: 137 },
//             gamesWon: { type: "integer", example: 6 },
//             totalMoves: { type: "integer", example: 41_205 },
//             highestTile: { type: "integer", example: 4096 },
//             totalPlaytimeSeconds: { type: "integer", example: 92_400 },
//             lastPlayedAt: { type: "string", format: "date-time", nullable: true }
//         }
//     },
//
//     PublicUser: {
//         type: "object",
//         properties: {
//             id: { type: "string", example: "66b2f0c0a1c4de00126ab9f1" },
//             username: { type: "string", example: "ada" },
//             displayName: { type: "string", example: "Ada L." },
//             country: { type: "string", nullable: true, example: "GB" },
//             avatarColor: { type: "string", example: "#e96345" },
//             bio: { type: "string" },
//             statistics: { $ref: "#/components/schemas/Statistics" },
//             followerCount: { type: "integer" },
//             followingCount: { type: "integer" },
//             createdAt: { type: "string", format: "date-time" }
//         }
//     },
//
//     PrivateUser: {
//         allOf: [
//             { $ref: "#/components/schemas/PublicUser" },
//             {
//                 type: "object",
//                 properties: {
//                     email: { type: "string", format: "email" },
//                     roles: { type: "array", items: { type: "string", enum: ["player", "moderator", "admin"] } },
//                     preferences: { $ref: "#/components/schemas/Preferences" },
//                     emailVerified: { type: "boolean" },
//                     lastSeenAt: { type: "string", format: "date-time" },
//                     updatedAt: { type: "string", format: "date-time" }
//                 }
//             }
//         ]
//     },
//
//     TokenPair: {
//         type: "object",
//         properties: {
//             accessToken: { type: "string", description: "Short-lived bearer token. Send as `Authorization: Bearer <token>`." },
//             refreshToken: { type: "string", description: "Long-lived, single-use. Every refresh rotates it; replaying an old one revokes the session." },
//             tokenType: { type: "string", example: "Bearer" },
//             expiresIn: { type: "integer", example: 3600, description: "Access token lifetime in seconds." },
//             refreshExpiresIn: { type: "integer", example: 5_184_000 },
//             sessionId: { type: "string", format: "uuid" }
//         }
//     },
//
//     AuthResponse: {
//         allOf: [
//             { type: "object", properties: { user: { $ref: "#/components/schemas/PrivateUser" } } },
//             { $ref: "#/components/schemas/TokenPair" }
//         ]
//     },
//
//     Session: {
//         type: "object",
//         properties: {
//             id: { type: "string", format: "uuid" },
//             client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] },
//             userAgent: { type: "string" },
//             createdAt: { type: "string", format: "date-time" },
//             lastUsedAt: { type: "string", format: "date-time" },
//             expiresAt: { type: "string", format: "date-time" },
//             revoked: { type: "boolean" },
//             current: { type: "boolean", description: "True for the session that made this request." }
//         }
//     },
//
//     GameSave: {
//         type: "object",
//         properties: {
//             slot: { type: "string", example: "current" },
//             label: { type: "string" },
//             board: { type: "array", items: { type: "integer" }, minItems: 16, maxItems: 16 },
//             grid: { type: "array", items: { type: "array", items: { type: "integer" } }, description: "The same board as 4x4 rows, for clients that store it that way." },
//             score: { type: "integer" },
//             bestScore: { type: "integer" },
//             won: { type: "boolean" },
//             gameOver: { type: "boolean" },
//             moves: { type: "integer" },
//             highestTile: { type: "integer" },
//             elapsedSeconds: { type: "integer" },
//             undo: {
//                 type: "object",
//                 nullable: true,
//                 description: "The one-step undo snapshot, carried so a device handoff mid-round does not consume the player's undo.",
//                 properties: { board: { type: "array", items: { type: "integer" } }, score: { type: "integer" }, won: { type: "boolean" } }
//             },
//             revision: { type: "integer", description: "Increments on every write. Send it back as `baseRevision` to prove a save is a continuation rather than a divergence." },
//             client: { type: "string" },
//             deviceId: { type: "string" },
//             createdAt: { type: "string", format: "date-time" },
//             updatedAt: { type: "string", format: "date-time" }
//         }
//     },
//
//     SavePayload: {
//         type: "object",
//         required: ["score"],
//         properties: {
//             board: { $ref: "#/components/schemas/Board" },
//             grid: { $ref: "#/components/schemas/Board" },
//             score: { type: "integer", minimum: 0 },
//             bestScore: { type: "integer", minimum: 0 },
//             won: { type: "boolean" },
//             gameOver: { type: "boolean" },
//             moves: { type: "integer", minimum: 0 },
//             elapsedSeconds: { type: "integer", minimum: 0 },
//             label: { type: "string", maxLength: 60 },
//             deviceId: { type: "string", maxLength: 64 },
//             client: { type: "string", enum: ["web", "ios", "android", "cli", "unknown"] },
//             baseRevision: { type: "integer", minimum: 0, description: "The `revision` this device last saw." },
//             undo: {
//                 type: "object",
//                 nullable: true,
//                 properties: { board: { $ref: "#/components/schemas/Board" }, score: { type: "integer" }, won: { type: "boolean" } }
//             }
//         }
//     },
//
//     SyncResult: {
//         type: "object",
//         properties: {
//             resolution: {
//                 type: "string",
//                 enum: ["uploaded", "downloaded", "in_sync", "conflicted"],
//                 description: "`conflicted` means both sides had real progress. The further round wins and the other is preserved in `conflictSlot` — nothing is ever discarded."
//             },
//             winner: { type: "string", nullable: true, enum: ["local", "remote", null] },
//             conflictSlot: { type: "string", nullable: true, example: "conflict-m8s2k1" },
//             save: { $ref: "#/components/schemas/GameSave" }
//         }
//     },
//
//     Score: {
//         type: "object",
//         properties: {
//             id: { type: "string" },
//             username: { type: "string" },
//             displayName: { type: "string" },
//             country: { type: "string", nullable: true },
//             avatarColor: { type: "string" },
//             score: { type: "integer" },
//             highestTile: { type: "integer" },
//             moves: { type: "integer" },
//             durationSeconds: { type: "integer" },
//             won: { type: "boolean" },
//             gameOver: { type: "boolean" },
//             mode: { type: "string", enum: ["classic", "daily"] },
//             challengeDate: { type: "string", nullable: true },
//             client: { type: "string" },
//             verified: {
//                 type: "boolean",
//                 description: "False when the score exceeds what its final board could have produced. Unverified rounds are kept but never ranked."
//             },
//             createdAt: { type: "string", format: "date-time" }
//         }
//     },
//
//     LeaderboardEntry: {
//         type: "object",
//         properties: {
//             rank: { type: "integer", example: 1 },
//             userId: { type: "string" },
//             username: { type: "string" },
//             displayName: { type: "string" },
//             country: { type: "string", nullable: true },
//             avatarColor: { type: "string" },
//             score: { type: "integer" },
//             highestTile: { type: "integer" },
//             moves: { type: "integer" },
//             durationSeconds: { type: "integer" },
//             won: { type: "boolean" },
//             client: { type: "string" },
//             entries: { type: "integer", description: "How many qualifying rounds this player has in the window." },
//             achievedAt: { type: "string", format: "date-time" },
//             isViewer: { type: "boolean", description: "Present when the request is authenticated." }
//         }
//     },
//
//     LeaderboardPage: {
//         type: "object",
//         properties: {
//             entries: { type: "array", items: { $ref: "#/components/schemas/LeaderboardEntry" } },
//             summary: {
//                 type: "object",
//                 properties: {
//                     players: { type: "integer" },
//                     topScore: { type: "integer" },
//                     averageScore: { type: "integer" },
//                     winners: { type: "integer" }
//                 }
//             },
//             window: {
//                 type: "object",
//                 properties: {
//                     period: { type: "string", enum: ["daily", "weekly", "monthly", "yearly", "all"] },
//                     since: { type: "string", format: "date-time", nullable: true },
//                     until: { type: "string", format: "date-time", nullable: true }
//                 }
//             },
//             pagination: { $ref: "#/components/schemas/Pagination" }
//         }
//     },
//
//     Rank: {
//         type: "object",
//         properties: {
//             ranked: { type: "boolean", description: "False when the player has no qualifying round in the window." },
//             rank: { type: "integer", nullable: true },
//             players: { type: "integer" },
//             percentile: { type: "number", nullable: true, example: 97.4 },
//             entry: { $ref: "#/components/schemas/LeaderboardEntry" },
//             window: { type: "object", additionalProperties: true }
//         }
//     },
//
//     Achievement: {
//         type: "object",
//         properties: {
//             key: { type: "string", example: "tile_2048" },
//             name: { type: "string", example: "2048" },
//             description: { type: "string" },
//             category: { type: "string", enum: ["milestone", "tiles", "score", "dedication", "skill", "daily"] },
//             points: { type: "integer" },
//             progress: { type: "integer" },
//             target: { type: "integer" },
//             unlocked: { type: "boolean" },
//             unlockedAt: { type: "string", format: "date-time", nullable: true }
//         }
//     },
//
//     DailyChallenge: {
//         type: "object",
//         properties: {
//             date: { type: "string", example: "2026-09-18" },
//             dayNumber: { type: "integer", example: 992 },
//             seed: { type: "integer", description: "FNV-1a of the date. A client can reproduce the board offline from this alone." },
//             board: { type: "array", items: { type: "integer" }, minItems: 16, maxItems: 16 },
//             modifier: {
//                 type: "object",
//                 properties: {
//                     key: { type: "string", enum: ["classic", "tile_hunt", "efficiency", "endurance"] },
//                     name: { type: "string" },
//                     description: { type: "string" },
//                     targetScore: { type: "integer" }
//                 }
//             },
//             expiresAt: { type: "string", format: "date-time" }
//         }
//     },
//
//     GlobalStats: {
//         type: "object",
//         properties: {
//             players: { type: "integer" },
//             activeToday: { type: "integer" },
//             games: { type: "integer" },
//             gamesToday: { type: "integer" },
//             savedRounds: { type: "integer" },
//             wins: { type: "integer" },
//             winRate: { type: "number" },
//             topScore: { type: "integer" },
//             averageScore: { type: "integer" },
//             totalScore: { type: "integer" },
//             totalMoves: { type: "integer" },
//             highestTile: { type: "integer" },
//             generatedAt: { type: "string", format: "date-time" }
//         }
//     },
//
//     PersonalStats: {
//         type: "object",
//         properties: {
//             games: { type: "integer" },
//             wins: { type: "integer" },
//             winRate: { type: "number" },
//             bestScore: { type: "integer" },
//             averageScore: { type: "integer" },
//             totalScore: { type: "integer" },
//             totalMoves: { type: "integer" },
//             totalPlaytimeSeconds: { type: "integer" },
//             highestTile: { type: "integer" },
//             averageMovesPerGame: { type: "integer" },
//             pointsPerMove: { type: "number" },
//             firstGameAt: { type: "string", format: "date-time", nullable: true },
//             lastGameAt: { type: "string", format: "date-time", nullable: true },
//             tiles: {
//                 type: "object",
//                 properties: {
//                     games: { type: "integer" },
//                     buckets: {
//                         type: "array",
//                         items: {
//                             type: "object",
//                             properties: { tile: { type: "integer" }, games: { type: "integer" }, bestScore: { type: "integer" }, share: { type: "number" } }
//                         }
//                     }
//                 }
//             },
//             activity: {
//                 type: "object",
//                 properties: {
//                     days: { type: "integer" },
//                     since: { type: "string", format: "date-time" },
//                     series: {
//                         type: "array",
//                         description: "Dense: days with no games appear as zeroes rather than being omitted.",
//                         items: {
//                             type: "object",
//                             properties: { date: { type: "string" }, games: { type: "integer" }, bestScore: { type: "integer" }, totalScore: { type: "integer" }, wins: { type: "integer" } }
//                         }
//                     }
//                 }
//             },
//             recentGames: { type: "array", items: { $ref: "#/components/schemas/Score" } }
//         }
//     }
// };
//
// export default schemas;
