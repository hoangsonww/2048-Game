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
                message: (error?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Request failed with status \(status).",
                status: status
            )
        }

        return json
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

    func currentUser() async throws -> CloudUser? {
        guard tokens.read() != nil else { return nil }
        return readUser(try await authed("GET", "/api/v1/auth/me")["user"] as? [String: Any])
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
