package com.sonnguyenhoang.game2048.cloud

import org.json.JSONArray
import org.json.JSONObject

/**
 * The typed client for the 2048 Cloud API.
 *
 * Every network effect goes through the injected [HttpTransport] and every
 * stored credential through the injected [TokenStore], so this whole class —
 * including the token-refresh retry, which is the part most likely to be
 * wrong — runs under `node`-speed JVM unit tests with no device and no
 * server. See ARCHITECTURE.md, "Determinism seams".
 *
 * Nothing here is ever on the path of a move. The game does not wait on it.
 */
interface TokenStore {
    fun read(): CloudTokens?
    fun write(tokens: CloudTokens?)
}

class CloudApi(
    private val transport: HttpTransport,
    private val tokens: TokenStore,
    private val baseUrl: String = DEFAULT_BASE_URL,
    private val deviceId: String = "android"
) {
    companion object {
        const val DEFAULT_BASE_URL = "https://game-2048-cloud-api.vercel.app"
    }

    private val root = baseUrl.trimEnd('/')

    /* ------------------------------------------------------------------ */
    /* Transport                                                           */
    /* ------------------------------------------------------------------ */

    private fun request(method: String, path: String, body: JSONObject?, token: String?): JSONObject {
        val headers = buildMap {
            put("Content-Type", "application/json")
            put("Accept", "application/json")
            put("X-Client", "android")
            if (token != null) put("Authorization", "Bearer $token")
        }

        val response = transport.send(method, "$root$path", headers, body?.toString())
        val payload = parse(response.body)

        if (response.status !in 200..299) {
            val error = payload?.optJSONObject("error")
            throw CloudException(
                code = error?.optString("code").orEmpty().ifEmpty { "http_error" },
                message = error?.optString("message").orEmpty().ifEmpty { "Request failed with status ${response.status}." },
                status = response.status
            )
        }

        return payload ?: JSONObject()
    }

    /** A body that is not JSON is treated as absent rather than fatal. */
    private fun parse(body: String): JSONObject? = runCatching {
        if (body.isBlank()) null else JSONObject(body)
    }.getOrNull()

    /**
     * Runs an authenticated request, refreshing once on a 401.
     *
     * One retry, never a loop: if the refreshed token is also rejected the
     * session is genuinely gone, and retrying again would just rotate a dead
     * refresh token until the server revoked it.
     */
    private fun authed(method: String, path: String, body: JSONObject? = null): JSONObject {
        val current = tokens.read() ?: throw CloudException("unauthorized", "Sign in to use this.", 401)
        return try {
            request(method, path, body, current.accessToken)
        } catch (error: CloudException) {
            if (!error.isUnauthorized) throw error
            val refreshed = refresh()
            request(method, path, body, refreshed.accessToken)
        }
    }

    private fun refresh(): CloudTokens {
        val current = tokens.read()
        if (current == null || current.refreshToken.isEmpty()) {
            tokens.write(null)
            throw CloudException("unauthorized", "You are signed out.", 401)
        }

        return try {
            val payload = request("POST", "/api/v1/auth/refresh", JSONObject().put("refreshToken", current.refreshToken), null)
            readTokens(payload).also { tokens.write(it) }
        } catch (error: CloudException) {
            // A refresh that fails for any reason other than a lost connection
            // means the session is over. A dropped connection must not sign a
            // player out — they may simply be on a train.
            if (!error.isNetworkFailure) tokens.write(null)
            throw error
        }
    }

    /* ------------------------------------------------------------------ */
    /* Session                                                             */
    /* ------------------------------------------------------------------ */

    fun register(username: String, email: String, password: String): CloudSession {
        val payload = request(
            "POST",
            "/api/v1/auth/register",
            JSONObject()
                .put("username", username.trim())
                .put("email", email.trim())
                .put("password", password)
                .put("client", "android"),
            null
        )
        return adopt(payload)
    }

    fun login(identifier: String, password: String): CloudSession {
        val payload = request(
            "POST",
            "/api/v1/auth/login",
            JSONObject().put("identifier", identifier.trim()).put("password", password).put("client", "android"),
            null
        )
        return adopt(payload)
    }

    /** Returns the account behind the stored tokens, or null when there is none. */
    fun currentUser(): CloudUser? {
        if (tokens.read() == null) return null
        return readUser(authed("GET", "/api/v1/auth/me").optJSONObject("user"))
    }

    fun logout() {
        val current = tokens.read()
        tokens.write(null)
        if (current == null) return
        // The local session is already gone, which is what the player asked
        // for. A failed server-side revoke is never worth an error dialog.
        runCatching { request("POST", "/api/v1/auth/logout", JSONObject().put("refreshToken", current.refreshToken), null) }
    }

    private fun adopt(payload: JSONObject): CloudSession {
        val session = CloudSession(readUser(payload.optJSONObject("user")), readTokens(payload))
        tokens.write(session.tokens)
        return session
    }

    /* ------------------------------------------------------------------ */
    /* Game data                                                           */
    /* ------------------------------------------------------------------ */

    fun sync(save: CloudSave?, strategy: String = "auto"): SyncResult {
        val body = JSONObject()
            .put("slot", "current")
            .put("strategy", strategy)
            .put("save", save?.let(::writeSave) ?: JSONObject.NULL)

        val payload = authed("POST", "/api/v1/saves/sync", body)
        return SyncResult(
            resolution = SyncResolution.from(payload.optString("resolution")),
            save = payload.optJSONObject("save")?.let(::readSave),
            conflictSlot = payload.optString("conflictSlot").takeIf { it.isNotEmpty() && it != "null" },
            winner = payload.optString("winner").takeIf { it.isNotEmpty() && it != "null" }
        )
    }

    fun submitScore(save: CloudSave, durationSeconds: Int = 0) {
        authed(
            "POST",
            "/api/v1/scores",
            JSONObject()
                .put("board", JSONArray(save.board))
                .put("score", save.score)
                .put("moves", save.moves)
                .put("durationSeconds", durationSeconds)
                .put("client", "android")
        )
    }

    fun leaderboard(period: String = "all", limit: Int = 20): LeaderboardPage {
        val path = "/api/v1/leaderboard?period=$period&limit=$limit&offset=0"
        // Readable signed out as well as signed in, so the board is reachable
        // before anyone has an account.
        val payload = if (tokens.read() != null) authed("GET", path) else request("GET", path, null, null)
        val rows = payload.optJSONArray("entries") ?: JSONArray()
        val summary = payload.optJSONObject("summary") ?: JSONObject()

        return LeaderboardPage(
            entries = (0 until rows.length()).map { index -> readEntry(rows.getJSONObject(index)) },
            players = summary.optInt("players"),
            topScore = summary.optInt("topScore")
        )
    }

    /* ------------------------------------------------------------------ */
    /* Wire format                                                         */
    /* ------------------------------------------------------------------ */

    private fun writeSave(save: CloudSave): JSONObject = JSONObject()
        .put("board", JSONArray(save.board))
        .put("score", save.score)
        .put("bestScore", save.bestScore)
        .put("won", save.won)
        .put("gameOver", save.gameOver)
        .put("moves", save.moves)
        .put("elapsedSeconds", save.elapsedSeconds)
        .put("client", "android")
        .put("deviceId", deviceId)
        .apply { save.baseRevision?.let { put("baseRevision", it) } }

    private fun readSave(json: JSONObject): CloudSave {
        val cells = json.optJSONArray("board") ?: JSONArray()
        return CloudSave(
            board = (0 until cells.length()).map { cells.optInt(it) },
            score = json.optInt("score"),
            bestScore = json.optInt("bestScore"),
            won = json.optBoolean("won"),
            gameOver = json.optBoolean("gameOver"),
            moves = json.optInt("moves"),
            elapsedSeconds = json.optInt("elapsedSeconds"),
            revision = json.optInt("revision")
        )
    }

    private fun readTokens(json: JSONObject) = CloudTokens(
        accessToken = json.optString("accessToken"),
        refreshToken = json.optString("refreshToken")
    )

    private fun readUser(json: JSONObject?): CloudUser {
        val user = json ?: JSONObject()
        val statistics = user.optJSONObject("statistics") ?: JSONObject()
        val username = user.optString("username")
        return CloudUser(
            id = user.optString("id"),
            username = username,
            // A player with no display name is shown by username rather than
            // by a blank row.
            displayName = user.optString("displayName").ifEmpty { username },
            email = user.optString("email"),
            bestScore = statistics.optInt("bestScore"),
            gamesPlayed = statistics.optInt("gamesPlayed"),
            highestTile = statistics.optInt("highestTile")
        )
    }

    private fun readEntry(json: JSONObject): LeaderboardEntry {
        val username = json.optString("username")
        return LeaderboardEntry(
            rank = json.optInt("rank"),
            username = username,
            displayName = json.optString("displayName").ifEmpty { username },
            score = json.optInt("score"),
            highestTile = json.optInt("highestTile"),
            isViewer = json.optBoolean("isViewer")
        )
    }
}
