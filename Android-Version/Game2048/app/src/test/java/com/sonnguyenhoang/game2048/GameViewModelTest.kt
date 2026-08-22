package com.sonnguyenhoang.game2048

import org.junit.Assert.*
import org.junit.Test

class GameViewModelTest {
    @Test
    fun newGameStartsWithExactlyTwoValidTiles() {
        val game = game()
        val tiles = nonZero(game)
        assertEquals(2, tiles.size)
        assertTrue(tiles.all { it == 2 || it == 4 })
        assertEquals(0, game.score)
        assertEquals(0, game.highScore)
        assertFalse(game.hasWon)
        assertFalse(game.canUndo)
    }

    @Test
    fun restartResetsRoundAndPreservesBestScore() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros), 20)
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))
        assertEquals(24, game.highScore)
        game.restartGame()
        assertEquals(0, game.score)
        assertEquals(24, game.highScore)
        assertEquals(2, nonZero(game).size)
        assertFalse(game.canUndo)
    }

    @Test
    fun leftMoveCompactsMergesOnceScoresAndSpawns() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 4, 4), zeros, zeros, zeros))
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))
        assertEquals(listOf(4, 8, 2, 0), game.grid.first())
        assertEquals(12, game.score)
        assertTrue(game.canUndo)
    }

    @Test
    fun rightMoveUsesReverseMergeOrder() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 2, 0), zeros, zeros, zeros))
        assertTrue(game.swipe(GameViewModel.Direction.RIGHT))
        assertEquals(listOf(2, 0, 2, 4), game.grid.first())
        assertEquals(4, game.score)
    }

    @Test
    fun upAndDownMovesMergeColumnsInCorrectOrder() {
        val up = game(randomIndex = { it - 1 })
        up.setGameForTesting(listOf(listOf(2, 0, 0, 0), listOf(2, 0, 0, 0), listOf(4, 0, 0, 0), listOf(4, 0, 0, 0)))
        assertTrue(up.swipe(GameViewModel.Direction.UP))
        assertEquals(listOf(4, 8, 0, 0), up.grid.map { it[0] })
        assertEquals(12, up.score)

        val down = game(randomIndex = { it - 1 })
        down.setGameForTesting(listOf(listOf(2, 0, 0, 0), listOf(2, 0, 0, 0), listOf(2, 0, 0, 0), zeros))
        assertTrue(down.swipe(GameViewModel.Direction.DOWN))
        assertEquals(listOf(0, 0, 2, 4), down.grid.map { it[0] })
        assertEquals(4, down.score)
    }

    @Test
    fun ineffectiveMoveDoesNotSpawnScoreOrCreateHistory() {
        val game = game()
        val board = listOf(listOf(2, 4, 0, 0), zeros, zeros, zeros)
        game.setGameForTesting(board, 8)
        assertFalse(game.swipe(GameViewModel.Direction.LEFT))
        assertEquals(board, game.grid)
        assertEquals(8, game.score)
        assertFalse(game.canUndo)
    }

    @Test
    fun undoRestoresBoardScoreAndWinStateOnlyOnce() {
        val game = game()
        val board = listOf(listOf(1024, 1024, 0, 0), zeros, zeros, zeros)
        game.setGameForTesting(board, 100, false)
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))
        assertTrue(game.hasWon)
        game.undo()
        assertEquals(board, game.grid)
        assertEquals(100, game.score)
        assertFalse(game.hasWon)
        assertFalse(game.canUndo)
        game.undo()
        assertEquals(board, game.grid)
        assertEquals(100, game.score)
    }

    @Test
    fun tileProbabilityBoundaryAndFullBoardNoOp() {
        val two = game(randomUnit = { 0.899999 })
        two.setGameForTesting(List(4) { zeros })
        two.restartGame()
        assertTrue(nonZero(two).all { it == 2 })
        val four = game(randomUnit = { 0.9 })
        four.setGameForTesting(List(4) { zeros })
        four.restartGame()
        assertTrue(nonZero(four).all { it == 4 })
        val full = listOf(listOf(2, 4, 2, 4), listOf(4, 2, 4, 2), listOf(2, 4, 2, 4), listOf(4, 2, 4, 2))
        four.setGameForTesting(full)
        assertFalse(four.swipe(GameViewModel.Direction.LEFT))
        assertEquals(full, four.grid)
    }

    @Test
    fun gameOverRequiresFullBoardWithoutAnyMerge() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 4, 2, 4), listOf(4, 2, 4, 2), listOf(2, 4, 2, 4), listOf(4, 2, 4, 2)))
        assertTrue(game.isGameOver())
        game.setGameForTesting(listOf(listOf(2, 2, 4, 8), listOf(4, 8, 16, 32), listOf(8, 16, 32, 64), listOf(16, 32, 64, 128)))
        assertFalse(game.isGameOver())
        game.setGameForTesting(listOf(listOf(2, 4, 8, 16), listOf(2, 8, 16, 32), listOf(4, 16, 32, 64), listOf(8, 32, 64, 128)))
        assertFalse(game.isGameOver())
        game.setGameForTesting(listOf(listOf(2, 4, 0, 8), listOf(4, 8, 16, 32), listOf(8, 16, 32, 64), listOf(16, 32, 64, 128)))
        assertFalse(game.isGameOver())
    }

    @Test
    fun savedRoundBestScoreAndWinStateRestore() {
        val storage = MemoryStorage()
        val game = game(storage)
        game.setGameForTesting(listOf(listOf(1024, 1024, 0, 0), zeros, zeros, zeros), 40, false)
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))
        val restored = game(storage)
        assertEquals(game.grid, restored.grid)
        assertEquals(2088, restored.score)
        assertEquals(2088, restored.highScore)
        assertTrue(restored.hasWon)
        assertFalse(restored.canUndo)
    }

    @Test
    fun corruptSavedBoardIsRejectedAndNegativeBestIsClamped() {
        val storage = MemoryStorage(SavedGame(List(4) { List(4) { 3 } }, -10, -20, false))
        val game = game(storage)
        assertEquals(2, nonZero(game).size)
        assertEquals(0, game.score)
        assertEquals(0, game.highScore)
    }

    private val zeros = listOf(0, 0, 0, 0)

    private fun game(
        storage: GameStorage? = null,
        randomIndex: (Int) -> Int = { 0 },
        randomUnit: () -> Double = { 0.0 }
    ) = GameViewModel(storage, randomIndex, randomUnit)

    private fun nonZero(game: GameViewModel) = game.grid.flatten().filter { it != 0 }

    private class MemoryStorage(private var saved: SavedGame? = null) : GameStorage {
        override fun load(): SavedGame? = saved
        override fun loadBest(): Int = saved?.best ?: 0
        override fun save(game: SavedGame) { saved = game }
    }
}
