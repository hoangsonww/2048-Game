package com.sonnguyenhoang.game2048.cloud

/**
 * The data the Android client exchanges with the 2048 Cloud API.
 *
 * These are plain Kotlin — no Compose, no Android framework, no annotation
 * processor — so the whole cloud layer is testable on the JVM. See
 * `docs/backend.md` for the wire contract they mirror.
 */

/** A round, in the shape the API stores it: flat cells, row-major. */
data class CloudSave(
    val board: List<Int>,
    val score: Int,
    val bestScore: Int,
    val won: Boolean,
    val gameOver: Boolean,
    val moves: Int,
    val elapsedSeconds: Int = 0,
    /** The revision this device last saw, proving a save is a continuation. */
    val baseRevision: Int? = null,
    val revision: Int = 0
)

data class CloudUser(
    val id: String,
    val username: String,
    val displayName: String,
    val email: String,
    val bestScore: Int,
    val gamesPlayed: Int,
    val highestTile: Int
)

data class CloudTokens(val accessToken: String, val refreshToken: String)

data class CloudSession(val user: CloudUser, val tokens: CloudTokens)

/**
 * How a sync was resolved. `CONFLICTED` is not an error: the further round
 * won and the other was preserved in a recoverable slot, which is the whole
 * reason the API refuses to do last-writer-wins.
 */
enum class SyncResolution { UPLOADED, DOWNLOADED, IN_SYNC, CONFLICTED;

    companion object {
        fun from(raw: String?): SyncResolution = when (raw) {
            "uploaded" -> UPLOADED
            "downloaded" -> DOWNLOADED
            "conflicted" -> CONFLICTED
            else -> IN_SYNC
        }
    }
}

data class SyncResult(
    val resolution: SyncResolution,
    val save: CloudSave?,
    val conflictSlot: String?,
    val winner: String?
)

data class LeaderboardEntry(
    val rank: Int,
    val username: String,
    val displayName: String,
    val score: Int,
    val highestTile: Int,
    val isViewer: Boolean
)

data class LeaderboardPage(
    val entries: List<LeaderboardEntry>,
    val players: Int,
    val topScore: Int
)

/**
 * A failure a caller can show to a player.
 *
 * `code` is the server's stable identifier, or one of `network` / `offline`
 * when the request never got that far. Branch on the code; the message is for
 * the screen.
 */
class CloudException(
    val code: String,
    override val message: String,
    val status: Int = 0
) : Exception(message) {
    val isUnauthorized: Boolean get() = status == 401
    val isNetworkFailure: Boolean get() = code == "network" || code == "offline"
}
