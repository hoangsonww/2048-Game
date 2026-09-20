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
    enum class Activity { IDLE, AUTHENTICATING, SYNCING, LOADING_LEADERBOARD, SIGNING_OUT }

    var phase by mutableStateOf(Phase.SIGNED_OUT)
        private set
    var activity by mutableStateOf(Activity.IDLE)
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
    private var inflight = 0

    val isSignedIn: Boolean get() = user != null
    val isBusy: Boolean get() = activity != Activity.IDLE

    /**
     * Whether this device is holding tokens from a previous launch.
     *
     * The caller needs this *before* the network is asked, because the round
     * on screen has to belong to the right profile from the first frame — not
     * from whenever the server answers.
     */
    val hasStoredSession: Boolean get() = preferences.hasTokens

    /** Whether the guest prompt should be shown. An invitation, never a gate. */
    val showGuestPrompt: Boolean get() = !isSignedIn && !dismissed

    fun dismissPrompt() {
        preferences.promptDismissed = true
        dismissed = true
    }

    /* ------------------------------------------------------------------ */
    /* Session                                                             */
    /* ------------------------------------------------------------------ */

    /**
     * Re-establishes a stored session on launch.
     *
     * Reconciling is the caller's next step, not this one's: which round may
     * be offered to the server depends on which profile the device adopted,
     * and that is a decision the game owns. [onRestored] runs with true only
     * once the session is live.
     */
    fun restore(onRestored: (Boolean) -> Unit = {}) {
        if (!preferences.hasTokens) {
            onRestored(false)
            return
        }
        phase = Phase.WORKING
        status = "Restoring your session…"
        run(
            activity = Activity.SYNCING,
            work = { api.currentUser() },
            onSuccess = { restored ->
                if (restored == null) {
                    phase = Phase.SIGNED_OUT
                    onRestored(false)
                } else {
                    user = restored
                    phase = Phase.SIGNED_IN
                    onRestored(true)
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
                onRestored(false)
            }
        )
    }

    fun register(username: String, email: String, password: String, onSignedIn: () -> Unit = {}) {
        authenticate(creating = true, { api.register(username, email, password) }, onSignedIn)
    }

    fun login(identifier: String, password: String, onSignedIn: () -> Unit = {}) {
        authenticate(creating = false, { api.login(identifier, password) }, onSignedIn)
    }

    private fun authenticate(creating: Boolean, work: () -> CloudSession, onSignedIn: () -> Unit) {
        authError = null
        phase = Phase.WORKING
        status = if (creating) "Creating account…" else "Signing in…"
        run(
            activity = Activity.AUTHENTICATING,
            work = work,
            onSuccess = { session ->
                user = session.user
                phase = Phase.SIGNED_IN
                preferences.promptDismissed = true
                dismissed = true
                // A revision remembered from an earlier session belongs to an
                // earlier session. Carrying it would let the next upload claim
                // to descend from a round this account has never seen.
                preferences.knownRevision = null
                onSignedIn()
            },
            onFailure = { error ->
                phase = Phase.SIGNED_OUT
                authError = error.message
            }
        )
    }

    /**
     * Loads the account's round, offering the server nothing in return.
     *
     * The `null` local save is the point. A round played before signing in
     * belongs to the device, not to the account that just signed in on it, so
     * there is nothing here to merge or conflict with: the server either hands
     * back the round this account already had, or it has none and the clean
     * board the game just created stands.
     */
    fun adoptAccountRound(applySave: (CloudSave) -> Unit, onAdopted: () -> Unit = {}) {
        if (!isSignedIn) return
        status = "Syncing…"
        run(
            activity = Activity.SYNCING,
            work = {
                val result = api.sync(null, "auto")
                val refreshed = runCatching { api.currentUser() }.getOrNull()
                result to refreshed
            },
            onSuccess = { (result, refreshed) ->
                lastResolution = result.resolution
                status = if (result.save == null) {
                    "Signed in. Your account is ready."
                } else {
                    "Restored the round from your account."
                }
                result.save?.revision?.takeIf { it > 0 }?.let { preferences.knownRevision = it }
                result.save?.let(applySave)
                if (refreshed != null) user = refreshed
                onAdopted()
            },
            onFailure = { error -> status = error.message }
        )
    }

    /**
     * Resets a forgotten password and ends the session this device was holding.
     *
     * Reported through [authError] like the other credential failures,
     * because it is the same kind of failure to the player: something they
     * typed did not match an account.
     */
    fun resetPassword(username: String, email: String, newPassword: String, onReset: () -> Unit = {}) {
        authError = null
        status = "Resetting your password…"
        run(
            activity = Activity.AUTHENTICATING,
            work = { api.resetPassword(username, email, newPassword) },
            onSuccess = {
                // The server revoked every session, this one included.
                user = null
                phase = Phase.SIGNED_OUT
                lastResolution = null
                preferences.knownRevision = null
                status = "Password reset. Sign in with your new password."
                onReset()
            },
            onFailure = { error -> authError = error.message }
        )
    }

    fun signOut() {
        val previous = user
        inflight += 1
        activity = Activity.SIGNING_OUT
        user = null
        phase = Phase.SIGNED_OUT
        lastResolution = null
        preferences.knownRevision = null
        status = "Signed out. Your device's own round is back."
        if (previous != null) {
            background {
                runCatching { api.logout() }
                main { finishActivity() }
            }
        } else {
            finishActivity()
        }
    }

    /* ------------------------------------------------------------------ */
    /* Game data                                                           */
    /* ------------------------------------------------------------------ */

    /** Explicit Sync now: push this device's board. */
    fun syncNow(currentSave: () -> CloudSave, applySave: (CloudSave) -> Unit) {
        if (!isSignedIn) return
        val stamped = stamp(currentSave())
        status = "Syncing…"
        run(
            activity = Activity.SYNCING,
            work = {
                val result = api.sync(stamped, "prefer-local")
                val refreshed = runCatching { api.currentUser() }.getOrNull()
                result to refreshed
            },
            onSuccess = { (result, refreshed) ->
                lastResolution = result.resolution
                status = describe(result)
                result.save?.revision?.takeIf { it > 0 }?.let { preferences.knownRevision = it }
                if (shouldApply(result) && result.save != null) applySave(result.save)
                if (refreshed != null) user = refreshed
            },
            onFailure = { error -> status = error.message }
        )
    }

    fun sync(currentSave: () -> CloudSave, applySave: (CloudSave) -> Unit, strategy: String = "auto") {
        if (!isSignedIn) return
        val stamped = stamp(currentSave())
        status = "Syncing…"
        run(
            activity = Activity.SYNCING,
            work = { api.sync(stamped, strategy) },
            onSuccess = { result ->
                lastResolution = result.resolution
                status = describe(result)
                result.save?.revision?.takeIf { it > 0 }?.let { preferences.knownRevision = it }
                if (shouldApply(result) && result.save != null) applySave(result.save)
            },
            onFailure = { error -> status = error.message }
        )
    }

    fun submitRound(save: CloudSave, durationSeconds: Int = 0) {
        if (!isSignedIn || save.score <= 0) return
        // A round that fails to reach the leaderboard is a shame, not something
        // the player needs to action: the score is already on their screen.
        background {
            runCatching { api.submitScore(save, durationSeconds) }
            main { refreshUserQuietly() }
        }
    }

    fun loadLeaderboard(period: String = leaderboardPeriod) {
        leaderboardPeriod = period
        leaderboardNote = "Loading…"
        run(
            activity = Activity.LOADING_LEADERBOARD,
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

    private fun stamp(save: CloudSave): CloudSave {
        val revision = preferences.knownRevision ?: return save
        return if (save.baseRevision != null) save else save.copy(baseRevision = revision)
    }

    private fun shouldApply(result: SyncResult): Boolean = when (result.resolution) {
        SyncResolution.DOWNLOADED -> true
        SyncResolution.CONFLICTED -> result.winner == "remote"
        else -> false
    }

    /**
     * Reloads career totals from the account.
     *
     * What the server returns replaces what was held, with no local maximum
     * merged in. Career statistics belong to the account; folding this
     * device's best score into them is how an account that had played nothing
     * ended up advertising a best score and a highest tile it never earned.
     */
    private fun refreshUserQuietly() {
        if (!isSignedIn) return
        run(
            activity = Activity.SYNCING,
            work = { api.currentUser() },
            onSuccess = { refreshed -> if (refreshed != null) user = refreshed },
            onFailure = { /* career totals can wait */ }
        )
    }

    private fun describe(result: SyncResult): String = when (result.resolution) {
        SyncResolution.UPLOADED -> "Round saved to your account."
        SyncResolution.DOWNLOADED -> "Restored the round from your account."
        SyncResolution.IN_SYNC -> "Everything is in sync."
        SyncResolution.CONFLICTED ->
            "Two devices had different rounds — the further one was kept, and the other is safe in your saves."
    }

    private fun finishActivity() {
        inflight = (inflight - 1).coerceAtLeast(0)
        if (inflight == 0) activity = Activity.IDLE
    }

    private fun <T> run(activity: Activity, work: () -> T, onSuccess: (T) -> Unit, onFailure: (CloudException) -> Unit) {
        inflight += 1
        this.activity = activity
        background {
            val outcome = runCatching(work)
            main {
                try {
                    outcome
                        .onSuccess(onSuccess)
                        .onFailure { thrown ->
                            onFailure(
                                thrown as? CloudException
                                    ?: CloudException("unexpected", thrown.message ?: "Something went wrong.")
                            )
                        }
                } finally {
                    finishActivity()
                }
            }
        }
    }
}

/** The handful of cloud settings that live on the device. */
interface CloudPreferences {
    var promptDismissed: Boolean
    val hasTokens: Boolean
    /** Last revision this device successfully synced — sent as `baseRevision`. */
    var knownRevision: Int?
}
