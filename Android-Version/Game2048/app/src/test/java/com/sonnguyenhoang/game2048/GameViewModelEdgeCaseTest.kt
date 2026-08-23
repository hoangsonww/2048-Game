package com.sonnguyenhoang.game2048

import org.junit.Assert.*
import org.junit.Test

/**
 * Boundary coverage for the Android rules engine.
 *
 * [GameViewModelTest] proves the ordinary paths; these pin the edges where a
 * subtle change would still pass every ordinary test but break real rounds —
 * merge ordering per direction, undo depth, persistence round-trips, and the
 * exact predicates for winning and losing.
 */
class GameViewModelEdgeCaseTest {
    // MARK: - Merge ordering

    @Test
    fun aMergedTileCannotMergeAgainInTheSameMove() {
        // [2,2,4] moving left is [4,4] and never [8].
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 4, 0), zeros, zeros, zeros))
        game.swipe(GameViewModel.Direction.LEFT)
        assertEquals(listOf(4, 4), game.grid[0].take(2))
    }

    @Test
    fun fourEqualTilesMakeTwoPairsNotOneChain() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 2, 2), zeros, zeros, zeros))
        game.swipe(GameViewModel.Direction.LEFT)
        assertEquals(listOf(4, 4), game.grid[0].take(2))
        assertEquals(8, game.score)
    }

    // A valid move always spawns a tile, so these assert the cells the merge
    // itself produced rather than the whole line — the spawn lands in one of
    // the vacated cells and would otherwise make the expectation ambiguous.

    @Test
    fun rightMergesThePairNearestTheDestinationEdge() {
        // [2,2,2,0] moving right leaves 2 then 4 against the right edge: the
        // far pair merges first, so the 4 ends up outermost.
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 2, 0), zeros, zeros, zeros))
        game.swipe(GameViewModel.Direction.RIGHT)
        assertEquals(2, game.grid[0][2])
        assertEquals(4, game.grid[0][3])
        assertEquals(4, game.score)
    }

    @Test
    fun leftMergesThePairNearestTheDestinationEdge() {
        val game = game()
        game.setGameForTesting(listOf(listOf(0, 2, 2, 2), zeros, zeros, zeros))
        game.swipe(GameViewModel.Direction.LEFT)
        assertEquals(4, game.grid[0][0])
        assertEquals(2, game.grid[0][1])
        assertEquals(4, game.score)
    }

    @Test
    fun downMergesColumnsFromTheBottomUp() {
        val game = game()
        game.setGameForTesting(
            listOf(listOf(2, 0, 0, 0), listOf(2, 0, 0, 0), listOf(2, 0, 0, 0), zeros)
        )
        game.swipe(GameViewModel.Direction.DOWN)
        assertEquals(2, game.grid[2][0])
        assertEquals(4, game.grid[3][0])
        assertEquals(4, game.score)
    }

    @Test
    fun upMergesColumnsFromTheTopDown() {
        val game = game()
        game.setGameForTesting(
            listOf(listOf(2, 0, 0, 0), listOf(2, 0, 0, 0), listOf(2, 0, 0, 0), zeros)
        )
        game.swipe(GameViewModel.Direction.UP)
        assertEquals(4, game.grid[0][0])
        assertEquals(2, game.grid[1][0])
        assertEquals(4, game.score)
    }

    // MARK: - Scoring

    @Test
    fun scoreCountsOnlyNewlyCreatedTiles() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 8, 8), zeros, zeros, zeros))
        game.swipe(GameViewModel.Direction.LEFT)
        assertEquals(20, game.score)
    }

    @Test
    fun slidingWithoutMergingScoresNothing() {
        val game = game()
        game.setGameForTesting(listOf(listOf(0, 0, 2, 4), zeros, zeros, zeros), newScore = 12)
        game.swipe(GameViewModel.Direction.LEFT)
        assertEquals(12, game.score)
    }

    // MARK: - Ineffective moves

    @Test
    fun everyDirectionIsIneffectiveOnAnEmptyBoard() {
        val game = game()
        game.setGameForTesting(listOf(zeros, zeros, zeros, zeros))
        for (direction in GameViewModel.Direction.entries) {
            assertFalse("$direction must not register on an empty board", game.swipe(direction))
        }
        assertFalse(game.canUndo)
    }

    @Test
    fun aBlockedDirectionCreatesNoUndoHistory() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 4, 8, 16), zeros, zeros, zeros))
        assertFalse(game.swipe(GameViewModel.Direction.LEFT))
        assertFalse("an ineffective move must not be undoable", game.canUndo)
    }

    // MARK: - Undo

    @Test
    fun undoIsExactlyOneStepDeep() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros))
        game.swipe(GameViewModel.Direction.LEFT)
        val afterFirst = game.grid.map { it.toList() }
        val scoreAfterFirst = game.score

        game.swipe(GameViewModel.Direction.RIGHT)
        game.undo()

        assertEquals(afterFirst, game.grid)
        assertEquals(scoreAfterFirst, game.score)
        assertFalse("the snapshot is consumed, so undo cannot repeat", game.canUndo)
    }

    @Test
    fun undoOnAFreshRoundDoesNothing() {
        val game = game()
        val before = game.grid.map { it.toList() }
        game.undo()
        assertEquals(before, game.grid)
    }

    // MARK: - Win and loss predicates

    @Test
    fun reachingTwoThousandFortyEightWinsButKeepsPlaying() {
        val game = game()
        game.setGameForTesting(listOf(listOf(1024, 1024, 0, 0), zeros, zeros, zeros))
        game.swipe(GameViewModel.Direction.LEFT)
        assertTrue(game.hasWon)
        assertEquals(2048, game.grid[0][0])
        assertFalse("the board still has empty cells", game.isGameOver())
    }

    @Test
    fun aFullBoardWithAHorizontalPairIsNotOver() {
        val game = game()
        game.setGameForTesting(
            listOf(
                listOf(2, 2, 4, 8),
                listOf(4, 8, 16, 32),
                listOf(8, 16, 32, 64),
                listOf(16, 32, 64, 128)
            )
        )
        assertFalse(game.isGameOver())
    }

    @Test
    fun aFullBoardWithAVerticalPairIsNotOver() {
        val game = game()
        game.setGameForTesting(
            listOf(
                listOf(2, 4, 8, 16),
                listOf(2, 8, 16, 32),
                listOf(8, 16, 32, 64),
                listOf(16, 32, 64, 128)
            )
        )
        assertFalse(game.isGameOver())
    }

    @Test
    fun aFullBoardWithNoAdjacentPairIsOver() {
        val game = game()
        game.setGameForTesting(
            listOf(
                listOf(2, 4, 2, 4),
                listOf(4, 2, 4, 2),
                listOf(2, 4, 2, 4),
                listOf(4, 2, 4, 2)
            )
        )
        assertTrue(game.isGameOver())
        for (direction in GameViewModel.Direction.entries) {
            assertFalse(game.swipe(direction))
        }
    }

    // MARK: - Spawning

    @Test
    fun spawnedTileHonoursTheNinetyTenSplitAtItsBoundary() {
        val justUnder = game(randomUnit = { 0.8999 })
        justUnder.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros))
        justUnder.swipe(GameViewModel.Direction.LEFT)
        assertTrue(justUnder.grid.flatten().any { it == 2 })

        val exactlyAt = game(randomUnit = { 0.9 })
        exactlyAt.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros))
        exactlyAt.swipe(GameViewModel.Direction.LEFT)
        assertTrue("0.9 is not below 0.9, so a four spawns", exactlyAt.grid.flatten().any { it == 4 })
    }

    @Test
    fun aValidMoveSpawnsExactlyOneTile() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros))
        val before = game.grid.flatten().count { it != 0 }
        game.swipe(GameViewModel.Direction.LEFT)
        val after = game.grid.flatten().count { it != 0 }
        // Two tiles merged into one, then exactly one spawned.
        assertEquals(before - 1 + 1, after)
    }

    // MARK: - Persistence

    @Test
    fun aSavedRoundRestoresBoardScoreAndWinState() {
        val storage = MemoryStorage()
        val first = game(storage)
        // The move has to be effective: an ineffective swipe writes nothing, so
        // there would be no saved round to restore.
        first.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros), newScore = 40, won = true)
        assertTrue(first.swipe(GameViewModel.Direction.LEFT))

        val restored = game(storage)
        assertEquals(first.grid, restored.grid)
        assertEquals(first.score, restored.score)
        assertEquals(first.hasWon, restored.hasWon)
    }

    @Test
    fun aBoardOfTheWrongShapeIsDiscarded() {
        val storage = MemoryStorage(SavedGame(listOf(listOf(2, 2), listOf(4, 4)), 10, 10, false))
        val game = game(storage)
        assertEquals(4, game.grid.size)
        assertTrue(game.grid.all { it.size == 4 })
        assertEquals(2, nonZero(game).size)
    }

    @Test
    fun aBoardWithNonPowerOfTwoValuesIsDiscarded() {
        val storage = MemoryStorage(SavedGame(List(4) { List(4) { 5 } }, 10, 10, false))
        val game = game(storage)
        assertEquals(2, nonZero(game).size)
        assertEquals(0, game.score)
    }

    @Test
    fun theBestScoreSurvivesARestart() {
        val game = game()
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros), newScore = 100)
        game.swipe(GameViewModel.Direction.LEFT)
        val best = game.highScore
        assertTrue(best >= 100)

        game.restartGame()
        assertEquals(0, game.score)
        assertEquals("a new round must not lower the best score", best, game.highScore)
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
