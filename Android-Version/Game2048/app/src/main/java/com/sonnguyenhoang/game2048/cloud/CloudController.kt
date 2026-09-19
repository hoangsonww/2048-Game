package com.sonnguyenhoang.game2048.cloud

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * The state the account surface renders and the orchestration behind it.
 *
 * Work is handed to two injected runners rather than to a coroutine scope:
 * `background` for the request and `main` for the state write. That keeps the
 * whole controller — including the ordering, the error paths, and the
 * debounce decision — testable on the JVM with two synchronous lambdas, and
 * it adds no dependency to an APK whose point is being a self-contained
 * offline game. Same reasoning as the injected tile generator in
 * `GameViewModel`; see ARCHITECTURE.md, "Determinism seams".
 */
class CloudController(
    private val api: CloudApi,
    private val preferences: CloudPreferences,
    private val background: (() -> Unit) -> Unit,
    private val main: (() -> Unit) -> Unit
) {
    enum class Phase { SIGNED_OUT, WORKING, SIGNED_IN }

    var phase by mutableStateOf(Phase.SIGNED_OUT)
        private set
    var user by mutableStateOf<CloudUser?>(null)
        private set
    var status by mutableStateOf("Playing on this device. Your round is saved locally.")
        private set
    var lastResolution by mutableStateOf<SyncResolution?>(null)
        private set
    var authError by mutableStateOf<String?>(null)
        private set
    var leaderboard by mutableStateOf<LeaderboardPage?>(null)
        private set
    var leaderboardNote by mutableStateOf("")
        private set
    var leaderboardPeriod by mutableStateOf("all")
        private set

    /**
     * Mirrored into Compose state rather than read from preferences on every
     * recomposition: a plain getter would not invalidate the banner when the
     * value changed, so dismissing it would do nothing until the next redraw.
     */
    private var dismissed by mutableStateOf(preferences.promptDismissed)

    val isSignedIn: Boolean get() = user != null

    /** Whether the guest prompt should be shown. An invitation, never a gate. */
    val showGuestPrompt: Boolean get() = !isSignedIn && !dismissed

    fun dismissPrompt() {
        preferences.promptDismissed = true
        dismissed = true
    }

    /* ------------------------------------------------------------------ */
    /* Session                                                             */
    /* ------------------------------------------------------------------ */

    /** Re-establishes a stored session on launch, then reconciles. */
    fun restore(currentSave: () -> CloudSave, applySave: (CloudSave) -> Unit) {
        if (!preferences.hasTokens) return
        phase = Phase.WORKING
        run(
            work = { api.currentUser() },
            onSuccess = { restored ->
                if (restored == null) {
                    phase = Phase.SIGNED_OUT
                } else {
                    user = restored
                    phase = Phase.SIGNED_IN
                    sync(currentSave, applySave)
                }
            },
            onFailure = { error ->
                phase = Phase.SIGNED_OUT
                // A dropped connection has not signed anybody out — the stored
                // token is untouched and the next launch will try again. A
                // rejected one has, and `CloudApi` already discarded it.
                status = if (error.isNetworkFailure) {
                    "Offline. Your round is saved on this device and will sync when you reconnect."
                } else {
                    "Your session expired. Sign in again to keep syncing."
                }
            }
        )
    }

    fun register(username: String, email: String, password: String, currentSave: () -> CloudSave, applySave: (CloudSave) -> Unit) {
        authenticate({ api.register(username, email, password) }, currentSave, applySave)
    }

    fun login(identifier: String, password: String, currentSave: () -> CloudSave, applySave: (CloudSave) -> Unit) {
        authenticate({ api.login(identifier, password) }, currentSave, applySave)
    }

    private fun authenticate(work: () -> CloudSession, currentSave: () -> CloudSave, applySave: (CloudSave) -> Unit) {
        authError = null
        phase = Phase.WORKING
        run(
            work = work,
            onSuccess = { session ->
                user = session.user
                phase = Phase.SIGNED_IN
                preferences.promptDismissed = true
                // Signing in is exactly when the two sides are most likely to
                // disagree, so it runs a full reconciliation.
                sync(currentSave, applySave)
            },
            onFailure = { error ->
                phase = Phase.SIGNED_OUT
                authError = error.message
            }
        )
    }

    fun signOut() {
        val previous = user
        user = null
        phase = Phase.SIGNED_OUT
        lastResolution = null
        status = "Signed out. Your round stays on this device."
        if (previous != null) background { runCatching { api.logout() } }
    }

    /* ------------------------------------------------------------------ */
    /* Game data                                                           */
    /* ------------------------------------------------------------------ */

    fun sync(currentSave: () -> CloudSave, applySave: (CloudSave) -> Unit, strategy: String = "auto") {
        if (!isSignedIn) return
        val save = currentSave()
        run(
            work = { api.sync(save, strategy) },
            onSuccess = { result ->
                lastResolution = result.resolution
                status = describe(result)
                // A download replaces the round. An upload does not touch the
                // board — this device is already showing what it sent.
                if (result.resolution == SyncResolution.DOWNLOADED && result.save != null) applySave(result.save)
            },
            onFailure = { error -> status = error.message }
        )
    }

    fun submitRound(save: CloudSave, durationSeconds: Int = 0) {
        if (!isSignedIn || save.score <= 0) return
        // A round that fails to reach the leaderboard is a shame, not something
        // the player needs to action: the score is already on their screen.
        background { runCatching { api.submitScore(save, durationSeconds) } }
    }

    fun loadLeaderboard(period: String = leaderboardPeriod) {
        leaderboardPeriod = period
        leaderboardNote = "Loading…"
        run(
            work = { api.leaderboard(period) },
            onSuccess = { page ->
                leaderboard = page
                leaderboardNote = if (page.entries.isEmpty()) {
                    "No rounds in this window yet. Finish a game to be the first."
                } else {
                    "%,d players · top score %,d".format(page.players, page.topScore)
                }
            },
            onFailure = { error ->
                leaderboard = null
                leaderboardNote = error.message
            }
        )
    }

    fun clearAuthError() {
        authError = null
    }

    private fun describe(result: SyncResult): String = when (result.resolution) {
        SyncResolution.UPLOADED -> "Round saved to your account."
        SyncResolution.DOWNLOADED -> "Restored the round from your account."
        SyncResolution.IN_SYNC -> "Everything is in sync."
        SyncResolution.CONFLICTED ->
            "Two devices had different rounds — the further one was kept, and the other is safe in your saves."
    }

    private fun <T> run(work: () -> T, onSuccess: (T) -> Unit, onFailure: (CloudException) -> Unit) {
        background {
            val outcome = runCatching(work)
            main {
                outcome
                    .onSuccess(onSuccess)
                    .onFailure { thrown ->
                        onFailure(
                            thrown as? CloudException
                                ?: CloudException("unexpected", thrown.message ?: "Something went wrong.")
                        )
                    }
            }
        }
    }
}

/** The handful of cloud settings that live on the device. */
interface CloudPreferences {
    var promptDismissed: Boolean
    val hasTokens: Boolean
}
