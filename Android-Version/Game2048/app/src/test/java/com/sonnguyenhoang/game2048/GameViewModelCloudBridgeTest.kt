package com.sonnguyenhoang.game2048

import com.sonnguyenhoang.game2048.cloud.CloudSave
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The bridge between the local round and the optional cloud layer.
 *
 * Every test here asserts the same underlying property from a different angle:
 * the cloud can read and replace a round, and nothing it does can change a
 * rule, corrupt a board, or break the game when it misbehaves.
 */
class GameViewModelCloudBridgeTest {

    private class MemoryStorage(private var saved: SavedGame? = null) : GameStorage {
        var writes = 0
        override fun load(): SavedGame? = saved
        override fun loadBest(): Int = saved?.best ?: 0
        override fun save(game: SavedGame) {
            saved = game
            writes += 1
        }
        override fun clear() { saved = null }
    }

    /** A deterministic model: every spawn is a 2 in the first empty cell. */
    private fun model(storage: GameStorage? = null) =
        GameViewModel(storage, randomIndex = { 0 }, randomUnit = { 0.0 })

    @Test
    fun `a fresh round reports no moves and a flat board`() {
        val save = model().cloudSave()

        assertEquals(16, save.board.size)
        assertEquals(0, save.moves)
        assertEquals(0, save.score)
        assertFalse(save.won)
    }

    @Test
    fun `moves are counted and travel with the save`() {
        val viewModel = model()
        viewModel.swipe(GameViewModel.Direction.LEFT)
        viewModel.swipe(GameViewModel.Direction.RIGHT)

        assertEquals(2, viewModel.cloudSave().moves)
    }

    @Test
    fun `a blocked swipe is not a move`() {
        val viewModel = model()
        viewModel.setGameForTesting(
            listOf(listOf(2, 0, 0, 0), listOf(0, 0, 0, 0), listOf(0, 0, 0, 0), listOf(0, 0, 0, 0))
        )

        assertFalse(viewModel.swipe(GameViewModel.Direction.LEFT))
        assertEquals(0, viewModel.moves)
    }

    @Test
    fun `undo does not rewind the move count`() {
        // A number a player can lower by pressing a button is not a measurement.
        val viewModel = model()
        viewModel.swipe(GameViewModel.Direction.LEFT)
        val afterMove = viewModel.moves

        viewModel.undo()

        assertEquals(afterMove, viewModel.moves)
    }

    @Test
    fun `the move count survives a relaunch`() {
        val storage = MemoryStorage()
        val first = model(storage)
        first.swipe(GameViewModel.Direction.LEFT)
        first.swipe(GameViewModel.Direction.RIGHT)

        assertEquals(2, model(storage).moves)
    }

    @Test
    fun `a negative move count in storage is discarded rather than trusted`() {
        val storage = MemoryStorage(
            SavedGame(
                grid = listOf(listOf(2, 4, 0, 0), listOf(0, 0, 0, 0), listOf(0, 0, 0, 0), listOf(0, 0, 0, 0)),
                score = 4,
                best = 4,
                hasWon = false,
                moves = -12
            )
        )

        assertEquals(0, model(storage).moves)
    }

    @Test
    fun `applying a remote save replaces the round`() {
        val viewModel = model()
        val remote = CloudSave(
            board = listOf(2, 4, 8, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            score = 60, bestScore = 900, won = false, gameOver = false, moves = 12
        )

        assertTrue(viewModel.applyCloudSave(remote))
        assertEquals(listOf(2, 4, 8, 16), viewModel.grid[0])
        assertEquals(60, viewModel.score)
        assertEquals(900, viewModel.highScore)
        assertEquals(12, viewModel.moves)
        assertFalse("a downloaded round carries no undo of this device's making", viewModel.canUndo)
    }

    @Test
    fun `applying a remote save persists it locally`() {
        val storage = MemoryStorage()
        val viewModel = model(storage)
        viewModel.applyCloudSave(
            CloudSave(listOf(2, 4) + List(14) { 0 }, 4, 4, won = false, gameOver = false, moves = 1)
        )

        assertEquals(listOf(2, 4) + List(14) { 0 }, storage.load()?.grid?.flatten())
    }

    @Test
    fun `a remote save can never lower the best score`() {
        val storage = MemoryStorage(
            SavedGame(List(4) { List(4) { 0 } }, score = 0, best = 5_000, hasWon = false)
        )
        val viewModel = model(storage)

        viewModel.applyCloudSave(CloudSave(List(16) { 0 }, 0, 10, won = false, gameOver = false, moves = 0))

        assertEquals("the best score is monotonic, wherever it came from", 5_000, viewModel.highScore)
    }

    @Test
    fun `a winning remote board sets the win state even if the payload forgot to`() {
        val viewModel = model()
        viewModel.applyCloudSave(
            CloudSave(listOf(2048) + List(15) { 0 }, 20_000, 20_000, won = false, gameOver = false, moves = 500)
        )

        assertTrue(viewModel.hasWon)
    }

    @Test
    fun `an invalid remote board is refused rather than half-applied`() {
        val viewModel = model()
        viewModel.swipe(GameViewModel.Direction.LEFT)
        val before = viewModel.grid.map { it.toList() }
        val scoreBefore = viewModel.score

        val rejected = listOf(
            CloudSave(listOf(1, 2, 3), 0, 0, won = false, gameOver = false, moves = 0),
            CloudSave(List(16) { 3 }, 0, 0, won = false, gameOver = false, moves = 0),
            CloudSave(List(16) { -2 }, 0, 0, won = false, gameOver = false, moves = 0),
            CloudSave(List(17) { 0 }, 0, 0, won = false, gameOver = false, moves = 0)
        )

        for (save in rejected) assertFalse("$save should be refused", viewModel.applyCloudSave(save))
        assertEquals("a refused payload must leave the round untouched", before, viewModel.grid)
        assertEquals(scoreBefore, viewModel.score)
    }

    @Test
    fun `a remote save with negative numbers is clamped, not stored`() {
        val viewModel = model()
        viewModel.applyCloudSave(
            CloudSave(listOf(2, 4) + List(14) { 0 }, -50, -1, won = false, gameOver = false, moves = -3)
        )

        assertEquals(0, viewModel.score)
        assertEquals(0, viewModel.moves)
    }

    @Test
    fun `observers are told what changed`() {
        val viewModel = model()
        val seen = mutableListOf<GameViewModel.RoundChange>()
        viewModel.onRoundChanged = { seen += it }

        viewModel.swipe(GameViewModel.Direction.LEFT)
        viewModel.undo()
        viewModel.restartGame()
        viewModel.applyCloudSave(CloudSave(listOf(2) + List(15) { 0 }, 0, 0, won = false, gameOver = false, moves = 0))

        assertEquals(
            listOf(
                GameViewModel.RoundChange.MOVE,
                GameViewModel.RoundChange.UNDO,
                GameViewModel.RoundChange.NEW_GAME,
                GameViewModel.RoundChange.RESTORED
            ),
            seen
        )
    }

    @Test
    fun `the end of a round is announced distinctly from an ordinary move`() {
        val viewModel = model()
        // Sliding right compacts row 0, and the spawn — pinned to the first
        // empty cell — completes a locked checkerboard.
        viewModel.setGameForTesting(
            listOf(listOf(4, 0, 2, 4), listOf(4, 2, 4, 2), listOf(2, 4, 2, 4), listOf(4, 2, 4, 2))
        )
        val seen = mutableListOf<GameViewModel.RoundChange>()
        viewModel.onRoundChanged = { seen += it }

        viewModel.swipe(GameViewModel.Direction.RIGHT)

        assertEquals(listOf(GameViewModel.RoundChange.GAME_OVER), seen)
        assertTrue(viewModel.isGameOver())
    }

    @Test
    fun `an observer that throws cannot break a move`() {
        // The game is the thing that has to keep working. A cloud layer with a
        // bug in it must degrade to "no sync", never to "the board froze".
        val viewModel = model()
        viewModel.onRoundChanged = { throw IllegalStateException("observer exploded") }

        assertTrue(viewModel.swipe(GameViewModel.Direction.LEFT))
        assertEquals(1, viewModel.moves)
    }

    @Test
    fun `a round with no observer still plays`() {
        val viewModel = model()
        viewModel.onRoundChanged = null

        assertTrue(viewModel.swipe(GameViewModel.Direction.LEFT))
    }
}
