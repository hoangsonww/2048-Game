package com.sonnguyenhoang.game2048

import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import com.sonnguyenhoang.game2048.ui.theme.Game2048Theme
import org.junit.Rule
import org.junit.Test

class GameScreenTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun initialScreenExposesBoardActionsAndHelpFlow() {
        show(GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 }))
        compose.onNodeWithContentDescription("2048 game board").assertExists()
        compose.onNodeWithText("Make space.").assertExists()
        compose.onNodeWithText("Undo").assertIsNotEnabled()
        compose.onNodeWithContentDescription("How to play").performClick()
        compose.onNodeWithText("Small rules.\nDeep decisions.").assertExists()
        compose.onNodeWithText("Slide").assertExists()
        compose.onNodeWithText("Match").assertExists()
        compose.onNodeWithText("Protect space").assertExists()
        compose.onNodeWithText("Got it").performClick()
        compose.onNodeWithText("Small rules.\nDeep decisions.").assertDoesNotExist()
    }

    @Test
    fun swipeUpdatesScoreEnablesUndoAndUndoRestoresScore() {
        val game = GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 })
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros), 32)
        show(game)
        compose.onNodeWithContentDescription("2048 game board").performTouchInput { swipeLeft() }
        compose.onNodeWithContentDescription("Score: 36").assertExists()
        compose.onNodeWithText("Undo").assertIsEnabled().performClick()
        compose.onNodeWithContentDescription("Score: 32").assertExists()
        compose.onNodeWithText("Undo").assertIsNotEnabled()
    }

    @Test
    fun newGameDialogSupportsCancelAndConfirmedReset() {
        val game = GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 })
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros), 32)
        show(game)
        compose.onNodeWithText("New game").performClick()
        compose.onNodeWithText("Start a fresh board?").assertExists()
        compose.onNodeWithText("Keep playing").performClick()
        compose.onNodeWithText("Start a fresh board?").assertDoesNotExist()
        compose.onNodeWithContentDescription("Score: 32").assertExists()
        compose.onNodeWithText("New game").performClick()
        compose.onAllNodesWithText("New game")[1].performClick()
        compose.onNodeWithContentDescription("Score: 0").assertExists()
        compose.onNodeWithText("Undo").assertIsNotEnabled()
    }

    @Test
    fun winOverlayCanContinuePlaying() {
        val won = GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 })
        won.setGameForTesting(listOf(listOf(2048, 4, 2, 0), zeros, zeros, zeros), 4096, true)
        show(won)
        compose.onNodeWithText("You made 2048").assertExists()
        compose.onNodeWithText("Keep playing").performClick()
        compose.onNodeWithText("You made 2048").assertDoesNotExist()

    }

    @Test
    fun gameOverOverlayCanStartFreshRound() {
        val lost = GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 })
        lost.setGameForTesting(listOf(listOf(2, 4, 2, 4), listOf(4, 2, 4, 2), listOf(2, 4, 2, 4), listOf(4, 2, 4, 2)), 512)
        show(lost)
        compose.onNodeWithText("No more moves").assertExists()
        compose.onNodeWithText("Try again").performClick()
        compose.onNodeWithText("No more moves").assertDoesNotExist()
        compose.onNodeWithContentDescription("Score: 0").assertExists()
    }

    private val zeros = listOf(0, 0, 0, 0)

    private fun show(game: GameViewModel) {
        compose.setContent { Game2048Theme { GameScreen(game) } }
        awaitFirstComposition()
    }

    /**
     * Blocks until the rule's host activity has actually attached a Compose
     * hierarchy.
     *
     * `setContent` returns before the hierarchy is guaranteed to be registered.
     * On a warm machine the first query wins that race; on a cold or loaded
     * emulator it does not, and the failure surfaces as
     * `IllegalStateException: No compose hierarchies found in the app` from
     * whichever assertion happened to run first — which points at the test
     * rather than at the launch it is actually waiting on.
     *
     * `atLeastOneRootRequired = false` is what makes this a barrier rather than
     * another way to hit the same exception: it reports "no roots yet" as an
     * empty list, so the predicate can poll instead of throwing.
     */
    private fun awaitFirstComposition() {
        compose.waitUntil(timeoutMillis = 30_000) {
            compose.onAllNodes(isRoot())
                .fetchSemanticsNodes(atLeastOneRootRequired = false)
                .isNotEmpty()
        }
        compose.waitForIdle()
    }
}
