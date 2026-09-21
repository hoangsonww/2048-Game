package com.sonnguyenhoang.game2048

import android.os.Handler
import android.os.Looper
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import com.sonnguyenhoang.game2048.cloud.CloudApi
import com.sonnguyenhoang.game2048.cloud.CloudController
import com.sonnguyenhoang.game2048.cloud.CloudPreferences
import com.sonnguyenhoang.game2048.cloud.CloudTokens
import com.sonnguyenhoang.game2048.cloud.HttpResponse
import com.sonnguyenhoang.game2048.cloud.HttpTransport
import com.sonnguyenhoang.game2048.cloud.TokenStore
import com.sonnguyenhoang.game2048.ui.theme.Game2048Theme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/**
 * The account surface on a real device.
 *
 * [CloudControllerTest] proves the state machine on the JVM; what only a
 * device can prove is that the surface is rendered, reachable, and — the
 * property that matters most — never in the way of the board.
 *
 * Every test runs against a scripted transport, so no request leaves the
 * device and the emulator needs no network.
 */
class GameScreenCloudTest {
    @get:Rule
    val compose = createComposeRule()

    private class ScriptedTransport(private val routes: Map<String, HttpResponse>) : HttpTransport {
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse {
            val path = url.substringAfter("https://api.test").substringBefore("?")
            return routes[path] ?: HttpResponse(200, "{}")
        }
    }

    private class MemoryStore(private var tokens: CloudTokens? = null) : TokenStore, CloudPreferences {
        override fun read(): CloudTokens? = tokens
        override fun write(tokens: CloudTokens?) { this.tokens = tokens }
        override var promptDismissed: Boolean = false
        override var knownRevision: Int? = null
        override val hasTokens: Boolean get() = tokens != null
    }

    private val sessionBody = """
        {"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test",
          "statistics":{"bestScore":900,"gamesPlayed":12,"highestTile":256}},
         "accessToken":"a","refreshToken":"r"}
    """.trimIndent()

    /**
     * A controller wired the way production wires it, except that the request
     * is answered from a script instead of a socket.
     *
     * `main` posts to the main looper rather than running inline. Compose
     * state has one owner thread, and a controller that writes it from
     * whichever thread happened to deliver a tap is a controller that
     * intermittently throws `Detected multithreaded access to
     * SnapshotStateObserver` — in a test today and on a device tomorrow.
     */
    private fun controller(routes: Map<String, HttpResponse> = emptyMap(), store: MemoryStore = MemoryStore()): CloudController {
        val mainHandler = Handler(Looper.getMainLooper())
        return CloudController(
            api = CloudApi(ScriptedTransport(routes), store, baseUrl = "https://api.test"),
            preferences = store,
            background = { it() },
            main = { work -> mainHandler.post(work) }
        )
    }

    @Test
    fun guestPromptInvitesWithoutBlockingTheBoard() {
        compose.mainClock.autoAdvance = false
        show(controller())

        compose.onNodeWithText("Playing as a guest").assertExists()
        compose.onNodeWithText("Create account").assertExists()
        // The invitation must never take the board away from the player.
        compose.onNodeWithContentDescription("2048 game board").assertExists()

        compose.mainClock.advanceTimeBy(5_500L)
        awaitGone(hasText("Playing as a guest"), "The guest invite")
        compose.onNodeWithContentDescription("2048 game board").assertExists()
    }

    @Test
    fun dismissingTheInvitationLeavesTheGameIntact() {
        compose.mainClock.autoAdvance = false
        show(controller())

        awaitNode("Dismiss this suggestion").performClick()

        awaitGone(hasText("Playing as a guest"), "The guest invite")
        compose.onNodeWithContentDescription("2048 game board").assertExists()
    }

    @Test
    fun signingInReplacesTheInvitationWithTheAccountName() {
        show(
            controller(
                mapOf(
                    "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                    "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"uploaded","save":null}""")
                )
            )
        )

        // Guest "Sign in" opens LOGIN mode. The header account button opens
        // REGISTER, which has Username/Email — not the identifier field.
        openSignInAndSubmit(identifier = "ada", password = "Password1")

        awaitNode("Account: Ada").assertExists()
        awaitGone(hasText("Playing as a guest"), "The guest invite")
    }

    @Test
    fun aRejectedSignInExplainsItselfAndKeepsTheFormOpen() {
        show(
            controller(
                mapOf(
                    "/api/v1/auth/login" to HttpResponse(
                        401,
                        """{"error":{"code":"invalid_credentials","message":"That email or password is not correct."}}"""
                    )
                )
            )
        )

        openSignInAndSubmit(identifier = "ada", password = "wrong")

        awaitNode("Sign-in problem: That email or password is not correct.").assertExists()
        compose.onNodeWithText("Welcome back").assertExists()
    }

    @Test
    fun theLeaderboardOpensAndRendersRankedRows() {
        show(
            controller(
                mapOf(
                    "/api/v1/leaderboard" to HttpResponse(
                        200,
                        """{"entries":[{"rank":1,"username":"ada","displayName":"Ada","score":9000,"highestTile":2048,"isViewer":false}],
                            "summary":{"players":1,"topScore":9000}}"""
                    )
                )
            )
        )

        awaitNode("Leaderboard").performClick()

        awaitNode("Rank 1, Ada, 9000 points").assertExists()
    }

    @Test
    fun theStatusLineTellsAGuestWhereTheirRoundLives() {
        show(controller())
        compose.onNodeWithContentDescription("Sync status: Playing on this device. Your round is saved locally.").assertExists()
    }

    @Test
    fun signingInMidRoundWarnsBeforeTheBoardLeavesTheScreen() {
        val game = playedRound()
        show(
            controller(
                mapOf(
                    "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                    "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"in_sync","save":null}""")
                )
            ),
            game
        )

        val scoreBefore = game.score
        awaitNode("Open sign in").performClick()
        awaitNode("Sign-in intro").assertExists()
        awaitNode("Username or email").performTextInput("ada")
        awaitNode("Password").performTextInput("Password1")
        awaitNode("Submit sign in").performClick()
        settle()

        // Nothing has happened yet: the player has been asked, not signed in.
        compose.onNodeWithText("Set this round aside?").assertExists()
        awaitNode("Keep playing this round").performClick()

        awaitGone(hasText("Set this round aside?"), "The handover warning")
        assertEquals(scoreBefore, game.score)
        assertEquals(GameViewModel.Profile.GUEST, game.profile)
    }

    @Test
    fun continuingTheWarningHandsTheDeviceToTheAccount() {
        val game = playedRound()
        show(
            controller(
                mapOf(
                    "/api/v1/auth/login" to HttpResponse(200, sessionBody),
                    "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"in_sync","save":null}"""),
                    "/api/v1/auth/me" to HttpResponse(200, """{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"a@b.test","statistics":{"bestScore":900,"gamesPlayed":12,"highestTile":256}}}""")
                )
            ),
            game
        )

        awaitNode("Open sign in").performClick()
        awaitNode("Username or email").performTextInput("ada")
        awaitNode("Password").performTextInput("Password1")
        awaitNode("Submit sign in").performClick()
        settle()
        awaitNode("Continue signing in").performClick()
        settle()

        awaitNode("Account: Ada").assertExists()
        assertEquals(GameViewModel.Profile.ACCOUNT, game.profile)
        assertEquals("the account starts on a clean board", 0, game.score)
    }

    @Test
    fun theAccountPanelShowsTheAccountsOwnCareerTotals() {
        val store = MemoryStore(CloudTokens("a", "r"))
        val game = playedRound()
        show(
            controller(
                mapOf(
                    "/api/v1/auth/me" to HttpResponse(200, """{"user":{"id":"u1","username":"ada","displayName":"Ada","email":"a@b.test","statistics":{"bestScore":0,"gamesPlayed":0,"highestTile":0}}}"""),
                    "/api/v1/saves/sync" to HttpResponse(200, """{"resolution":"in_sync","save":null}""")
                ),
                store
            ),
            game
        )

        awaitNode("Account: Ada").performClick()
        settle()

        // The guest round on this device is not part of this account's history.
        compose.onNodeWithText("Best 0 · 0 rounds · highest tile 0").assertExists()
    }

    @Test
    fun aMismatchedConfirmationNeverReachesTheNetwork() {
        // No pinned clock here: nothing in this flow depends on the invite
        // toast's timer, and letting Compose drive its own frames keeps the
        // modal sheets swapping the way they do on a real device.
        show(controller(mapOf("/api/v1/auth/register" to HttpResponse(201, sessionBody))))

        awaitNode("Open create account").performClick()
        awaitNode("Username").performTextInput("ada")
        awaitNode("Email").performTextInput("ada@example.test")
        awaitNode("Password").performTextInput("Password1")
        awaitNode("Confirm password").performTextInput("Password2")
        awaitNode("Submit create account").performClick()

        awaitNode("Those passwords do not match.").assertExists()
        compose.onNodeWithText("Create your account").assertExists()
    }

    @Test
    fun aPasswordFieldRevealsAndHidesOnItsOwn() {
        // No pinned clock here: nothing in this flow depends on the invite
        // toast's timer, and letting Compose drive its own frames keeps the
        // modal sheets swapping the way they do on a real device.
        show(controller())

        awaitNode("Open create account").performClick()
        awaitNode("Password").performTextInput("Password1")
        awaitNode("Confirm password").performTextInput("Password1")

        // Hidden to start: the confirmation control is still offering to show.
        awaitNode("Show Password").performClick()
        awaitNode("Hide Password").assertExists()
        // Revealing one field reveals only that field.
        awaitNode("Show Confirm password").assertExists()

        awaitNode("Hide Password").performClick()
        awaitNode("Show Password").assertExists()
    }

    @Test
    fun forgotPasswordOpensTheResetSheet() {
        // No pinned clock here: nothing in this flow depends on the invite
        // toast's timer, and letting Compose drive its own frames keeps the
        // modal sheets swapping the way they do on a real device.
        show(controller(), playedRound())

        awaitNode("Open sign in").performClick()
        awaitNode("Open password reset").performClick()

        awaitNode("Password reset intro").assertExists()
        // The sheet it came from is gone, so the two forms cannot both be up.
        compose.onNodeWithText("Welcome back").assertDoesNotExist()
    }

    @Test
    fun aResetNeedsTheTwoNewPasswordsToAgree() {
        // No pinned clock here: nothing in this flow depends on the invite
        // toast's timer, and letting Compose drive its own frames keeps the
        // modal sheets swapping the way they do on a real device.
        show(controller(), playedRound())

        awaitNode("Open sign in").performClick()
        awaitNode("Open password reset").performClick()
        awaitNode("Username").performTextInput("ada")
        awaitNode("Email").performTextInput("ada@example.test")
        awaitNode("New password").performTextInput("Recovered1")
        awaitNode("Confirm new password").performTextInput("Recovered2")
        awaitNode("Submit password reset").performClick()

        awaitNode("Those passwords do not match.").assertExists()
        awaitNode("Password reset intro").assertExists()
    }

    @Test
    fun aResetSendsThePairAndReturnsToSignIn() {
        // No pinned clock here: nothing in this flow depends on the invite
        // toast's timer, and letting Compose drive its own frames keeps the
        // modal sheets swapping the way they do on a real device.
        val game = playedRound()
        show(
            controller(
                mapOf("/api/v1/auth/reset-password" to HttpResponse(200, """{"reset":true,"sessionsRevoked":2}"""))
            ),
            game
        )

        awaitNode("Open sign in").performClick()
        awaitNode("Open password reset").performClick()
        awaitNode("Username").performTextInput("ada")
        awaitNode("Email").performTextInput("ada@example.test")
        awaitNode("New password").performTextInput("Recovered1")
        awaitNode("Confirm new password").performTextInput("Recovered1")
        awaitNode("Submit password reset").performClick()
        settle()

        awaitGone(hasContentDescription("Password reset intro"), "The reset sheet")
        awaitNode("Sign-in intro").assertExists()
    }

    /** A view model with a round a player would mind losing. */
    private fun playedRound(): GameViewModel {
        val game = GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 })
        game.setGameForTesting(
            listOf(listOf(2, 2, 0, 0), listOf(0, 0, 0, 0), listOf(0, 0, 0, 0), listOf(0, 0, 0, 0))
        )
        game.swipe(GameViewModel.Direction.LEFT)
        return game
    }

    private fun show(cloud: CloudController, provided: GameViewModel? = null) {
        val game = provided ?: GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 })
        compose.setContent { Game2048Theme { GameScreen(game, providedCloud = cloud) } }
        awaitFirstComposition()
    }

    /** Opens LOGIN via the guest prompt and submits the form. */
    private fun openSignInAndSubmit(identifier: String, password: String) {
        awaitNode("Open sign in").performClick()
        awaitNode("Username or email").performTextInput(identifier)
        awaitNode("Password").performTextInput(password)
        awaitNode("Submit sign in").performClick()
        settle()
    }

    /**
     * Lets composition catch up.
     *
     * Most of these tests pin the clock so the invite toast's 5.5 s auto-hide
     * is a decision the test makes rather than a race it runs. A pinned clock
     * also means nothing recomposes on its own — including the `LaunchedEffect`
     * that raises the toast in the first place — so every step has to pump a
     * few frames by hand. With the clock running this is just `waitForIdle`.
     */
    private fun settle() {
        if (!compose.mainClock.autoAdvance) repeat(FRAMES_PER_SETTLE) { compose.mainClock.advanceTimeByFrame() }
        compose.waitForIdle()
    }

    /** Waits for a node to appear, pumping frames while it does. */
    private fun awaitNode(description: String): SemanticsNodeInteraction {
        repeat(SETTLE_ATTEMPTS) {
            if (compose.onAllNodes(hasContentDescription(description)).fetchSemanticsNodes().isNotEmpty()) {
                return compose.onNodeWithContentDescription(description)
            }
            settle()
        }
        throw AssertionError("No node described as \"$description\" appeared.")
    }

    /**
     * Waits for a node to go away, pumping frames while it does.
     *
     * Disappearing takes longer than appearing: a sheet or a toast leaves
     * through an exit animation, and with the clock pinned that animation only
     * runs while frames are being pumped.
     */
    private fun awaitGone(matcher: SemanticsMatcher, label: String) {
        repeat(SETTLE_ATTEMPTS) {
            if (compose.onAllNodes(matcher).fetchSemanticsNodes().isEmpty()) return
            settle()
        }
        throw AssertionError("$label never went away.")
    }

    /** See the note on the same helper in [GameScreenTest]. */
    private fun awaitFirstComposition() {
        compose.waitUntil(timeoutMillis = 30_000) {
            compose.onAllNodes(isRoot()).fetchSemanticsNodes(atLeastOneRootRequired = false).isNotEmpty()
        }
        settle()
    }

    private companion object {
        /** Four frames of pumping is ample for one state change to land. */
        const val FRAMES_PER_SETTLE = 4

        /** Roughly five seconds of pumped frames before giving up on a node. */
        const val SETTLE_ATTEMPTS = 80
    }
}
