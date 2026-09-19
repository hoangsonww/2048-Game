package com.sonnguyenhoang.game2048

import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.isRoot
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
        override val hasTokens: Boolean get() = tokens != null
    }

    private val sessionBody = """
        {"user":{"id":"u1","username":"ada","displayName":"Ada","email":"ada@example.test",
          "statistics":{"bestScore":900,"gamesPlayed":12,"highestTile":256}},
         "accessToken":"a","refreshToken":"r"}
    """.trimIndent()

    private fun controller(routes: Map<String, HttpResponse> = emptyMap(), store: MemoryStore = MemoryStore()) =
        CloudController(
            api = CloudApi(ScriptedTransport(routes), store, baseUrl = "https://api.test"),
            preferences = store,
            background = { it() },
            main = { it() }
        )

    @Test
    fun guestPromptInvitesWithoutBlockingTheBoard() {
        show(controller())

        compose.onNodeWithText("Playing as a guest").assertExists()
        compose.onNodeWithText("Create account").assertExists()
        // The invitation must never take the board away from the player.
        compose.onNodeWithContentDescription("2048 game board").assertExists()
    }

    @Test
    fun dismissingTheInvitationLeavesTheGameIntact() {
        show(controller())

        compose.onNodeWithContentDescription("Dismiss this suggestion").performClick()

        compose.onNodeWithText("Playing as a guest").assertDoesNotExist()
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

        compose.onNodeWithContentDescription("Account: Ada").assertExists()
        compose.onNodeWithText("Playing as a guest").assertDoesNotExist()
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

        compose.onNodeWithContentDescription("Sign-in problem: That email or password is not correct.").assertExists()
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

        compose.onNodeWithContentDescription("Leaderboard").performClick()
        compose.waitForIdle()

        compose.onNodeWithContentDescription("Rank 1, Ada, 9000 points").assertExists()
    }

    @Test
    fun theStatusLineTellsAGuestWhereTheirRoundLives() {
        show(controller())
        compose.onNodeWithContentDescription("Sync status: Playing on this device. Your round is saved locally.").assertExists()
    }

    private fun show(cloud: CloudController) {
        val game = GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 })
        compose.setContent { Game2048Theme { GameScreen(game, providedCloud = cloud) } }
        awaitFirstComposition()
    }

    /** Opens LOGIN via the guest prompt and submits the form. */
    private fun openSignInAndSubmit(identifier: String, password: String) {
        compose.onNodeWithContentDescription("Open sign in").performClick()
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodes(hasContentDescription("Username or email"))
                .fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithContentDescription("Username or email").performTextInput(identifier)
        compose.onNodeWithContentDescription("Password").performTextInput(password)
        compose.onNodeWithContentDescription("Submit sign in").performClick()
        compose.waitForIdle()
    }

    /** See the note on the same helper in [GameScreenTest]. */
    private fun awaitFirstComposition() {
        compose.waitUntil(timeoutMillis = 30_000) {
            compose.onAllNodes(isRoot()).fetchSemanticsNodes(atLeastOneRootRequired = false).isNotEmpty()
        }
        compose.waitForIdle()
    }
}
