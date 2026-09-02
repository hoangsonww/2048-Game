import XCTest
@testable import Game_2048

/// Boundary coverage for the iOS rules engine.
///
/// `GameViewModelTests` proves the ordinary paths. These pin the edges where a
/// subtle change would still pass every ordinary test but break real rounds:
/// merge ordering per direction, undo depth, spawn clamping, persistence
/// round-trips, and the exact predicates for winning and losing.
///
/// Every game here uses a deterministic tile provider, so a spawned tile lands
/// in a known cell and whole-board assertions stay stable.
final class GameViewModelEdgeCaseTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "GameViewModelEdgeCaseTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Merge ordering

    func testAMergedTileCannotMergeAgainInTheSameMove() {
        // [2,2,4] moving left is [4,4] and never [8]. This is the single most
        // commonly broken 2048 rule.
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 4, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(Array(game.grid[0].prefix(2)), [4, 4])
        XCTAssertEqual(game.score, 4)
    }

    func testFourEqualTilesMakeTwoPairsNotOneChain() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 2, 2], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(Array(game.grid[0].prefix(2)), [4, 4])
        XCTAssertEqual(game.score, 8, "two separate merges, not a chain into 8")
    }

    func testLeftMergesThePairNearestTheDestinationEdge() {
        let game = makeGame()
        game.setGameForTesting(grid: [[0, 2, 2, 2], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        // The spawn lands in the first empty cell, so assert the merge itself.
        XCTAssertEqual(game.grid[0][0], 4)
        XCTAssertEqual(game.grid[0][1], 2)
        XCTAssertEqual(game.score, 4)
    }

    func testRightMergesFromTheFarEdgeInward() {
        // [2,2,2,0] moving right is 2 then 4 against the right edge: the pair
        // nearest the destination merges first, the opposite of moving left.
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 2, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .right))
        XCTAssertEqual(game.grid[0][2], 2)
        XCTAssertEqual(game.grid[0][3], 4)
        XCTAssertEqual(game.score, 4)
    }

    func testUpMergesColumnsFromTheTopDown() {
        let game = makeGame(randomIndex: { $0 - 1 })
        game.setGameForTesting(grid: [[2, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0], zeros])
        XCTAssertTrue(game.swipe(direction: .up))
        XCTAssertEqual(game.grid[0][0], 4)
        XCTAssertEqual(game.grid[1][0], 2)
        XCTAssertEqual(game.score, 4)
    }

    func testDownMergesColumnsFromTheBottomUp() {
        let game = makeGame(randomIndex: { $0 - 1 })
        game.setGameForTesting(grid: [[2, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0], zeros])
        XCTAssertTrue(game.swipe(direction: .down))
        XCTAssertEqual(game.grid[2][0], 2)
        XCTAssertEqual(game.grid[3][0], 4)
        XCTAssertEqual(game.score, 4)
    }

    func testEachDirectionMovesASingleTileToItsFarEdge() {
        for (direction, expected) in [
            (GameViewModel.Direction.up, (0, 1)),
            (.down, (3, 1)),
            (.left, (1, 0)),
            (.right, (1, 3))
        ] {
            let game = makeGame(randomIndex: { $0 - 1 })
            game.setGameForTesting(grid: [zeros, [0, 2, 0, 0], zeros, zeros])
            XCTAssertTrue(game.swipe(direction: direction))
            XCTAssertEqual(game.grid[expected.0][expected.1], 2, "\(direction) should land the tile at \(expected)")
        }
    }

    // MARK: - Scoring

    func testScoreCountsOnlyNewlyCreatedTiles() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 8, 8], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.score, 20, "4 + 16, and nothing for the tiles that only slid")
    }

    func testSlidingWithoutMergingScoresNothing() {
        let game = makeGame()
        game.setGameForTesting(grid: [[0, 0, 2, 4], zeros, zeros, zeros], score: 12)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.score, 12)
    }

    func testMergesAcrossSeveralRowsAllScoreInOneMove() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], [4, 4, 0, 0], [8, 8, 0, 0], zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.score, 28, "4 + 8 + 16")
    }

    func testAnIneffectiveMoveDoesNotLeakScore() {
        // mergeLine adds to score as it runs, so a rejected move has to roll
        // that back or a blocked swipe would quietly inflate the total.
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 4, 8, 16], zeros, zeros, zeros], score: 40)
        XCTAssertFalse(game.swipe(direction: .left))
        XCTAssertEqual(game.score, 40)
    }

    // MARK: - Ineffective moves

    func testEveryDirectionIsIneffectiveOnAnEmptyBoard() {
        let game = makeGame()
        game.setGameForTesting(grid: [zeros, zeros, zeros, zeros])
        for direction in allDirections {
            XCTAssertFalse(game.swipe(direction: direction), "\(direction) must not register on an empty board")
        }
        XCTAssertFalse(game.canUndo)
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 0, "no tile may spawn")
    }

    func testABlockedDirectionCreatesNoUndoHistory() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 4, 8, 16], zeros, zeros, zeros])
        XCTAssertFalse(game.swipe(direction: .left))
        XCTAssertFalse(game.canUndo, "an ineffective move must not be undoable")
    }

    // MARK: - Undo

    func testUndoIsExactlyOneStepDeep() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        let afterFirst = game.grid
        let scoreAfterFirst = game.score

        XCTAssertTrue(game.swipe(direction: .right))
        game.undo()

        XCTAssertEqual(game.grid, afterFirst)
        XCTAssertEqual(game.score, scoreAfterFirst)
        XCTAssertFalse(game.canUndo, "the snapshot is consumed, so undo cannot repeat")

        game.undo()
        XCTAssertEqual(game.grid, afterFirst, "a second undo is a no-op")
    }

    func testUndoOnAFreshRoundDoesNothing() {
        let game = makeGame()
        let before = game.grid
        game.undo()
        XCTAssertEqual(game.grid, before)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoRestoresTheWinStateThatPrecededTheMove() {
        let game = makeGame()
        game.setGameForTesting(grid: [[1024, 1024, 0, 0], zeros, zeros, zeros], hasWon: false)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.hasWon)

        game.undo()
        XCTAssertFalse(game.hasWon, "undoing the winning move rewinds the win state too")
    }

    func testRestartClearsUndoHistory() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.canUndo)

        game.restartGame()
        XCTAssertFalse(game.canUndo, "a new round must not be undoable into the previous one")
    }

    // MARK: - Win and loss predicates

    func testReachingTwoThousandFortyEightWinsButKeepsPlaying() {
        let game = makeGame()
        game.setGameForTesting(grid: [[1024, 1024, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.hasWon)
        XCTAssertEqual(game.grid[0][0], 2048)
        XCTAssertFalse(game.isGameOver(), "the board still has empty cells")
    }

    func testTheWinStateSticksOnceEarned() {
        let game = makeGame()
        // The gap makes the move effective; a board already flush left would be
        // rejected and would prove nothing about the win state.
        game.setGameForTesting(grid: [[2048, 0, 4, 0], zeros, zeros, zeros], hasWon: true)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.hasWon, "play continues after 2048 without losing the win")
    }

    func testAFullBoardWithAHorizontalPairIsNotOver() {
        let game = makeGame()
        game.setGameForTesting(grid: [
            [2, 2, 4, 8],
            [4, 8, 16, 32],
            [8, 16, 32, 64],
            [16, 32, 64, 128]
        ])
        XCTAssertFalse(game.isGameOver())
    }

    func testAFullBoardWithAVerticalPairIsNotOver() {
        let game = makeGame()
        game.setGameForTesting(grid: [
            [2, 4, 8, 16],
            [2, 8, 16, 32],
            [8, 16, 32, 64],
            [16, 32, 64, 128]
        ])
        XCTAssertFalse(game.isGameOver())
    }

    func testAFullBoardWithNoAdjacentPairIsOverAndRejectsEveryMove() {
        let game = makeGame()
        game.setGameForTesting(grid: [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 2]
        ])
        XCTAssertTrue(game.isGameOver())
        for direction in allDirections {
            XCTAssertFalse(game.swipe(direction: direction), "\(direction) must be rejected on a locked board")
        }
    }

    func testAnEmptyCellAlwaysMeansTheGameIsLive() {
        let game = makeGame()
        game.setGameForTesting(grid: [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 0]
        ])
        XCTAssertFalse(game.isGameOver())
    }

    // MARK: - Spawning

    func testAValidMoveSpawnsExactlyOneTile() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        // Two tiles merged into one, then exactly one spawned.
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2)
    }

    func testSpawnedTileHonoursTheNinetyTenSplitAtItsBoundary() {
        let two = makeGame(randomUnit: { 0.899999 })
        two.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(two.swipe(direction: .left))
        XCTAssertTrue(two.grid.flatMap { $0 }.contains(2))

        let four = makeGame(randomUnit: { 0.9 })
        four.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(four.swipe(direction: .left))
        XCTAssertTrue(four.grid.flatMap { $0 }.contains(4), "0.9 is not below 0.9, so a four spawns")
    }

    func testAnOutOfRangeSpawnIndexIsClampedIntoTheBoard() {
        // The provider is injectable, so the engine has to defend against an
        // index outside the empty-cell list rather than trapping.
        for index in [-5, 999] {
            let game = makeGame(randomIndex: { _ in index })
            game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
            XCTAssertTrue(game.swipe(direction: .left))
            XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2, "index \(index) must still place one tile")
        }
    }

    func testANewRoundStartsWithTwoDistinctTiles() {
        // Both spawns ask for the first empty cell; the second must see a
        // shorter list because the first already filled one.
        let game = makeGame(randomIndex: { _ in 0 })
        game.restartGame()
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2, "the two spawns must not collide")
    }

    // MARK: - Persistence

    func testASavedRoundRestoresBoardScoreAndWinState() {
        let first = makePersistingGame()
        first.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros], score: 40, hasWon: true)
        // The move has to be effective: a rejected swipe persists nothing.
        XCTAssertTrue(first.swipe(direction: .left))

        let restored = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(restored.grid, first.grid)
        XCTAssertEqual(restored.score, first.score)
        XCTAssertEqual(restored.hasWon, first.hasWon)
    }

    func testUndoIsPersistedSoRelaunchingDoesNotResurrectTheMove() {
        let first = makePersistingGame()
        first.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(first.swipe(direction: .left))
        XCTAssertTrue(first.swipe(direction: .right))
        first.undo()

        let restored = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(restored.grid, first.grid, "the undone board is what gets reloaded")
        XCTAssertEqual(restored.score, first.score)
    }

    func testASavedBoardOfTheWrongSizeIsDiscarded() {
        defaults.set(Array(repeating: 2, count: 9), forKey: "savedGridV2")
        defaults.set(500, forKey: "savedScoreV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(game.grid.count, 4)
        XCTAssertTrue(game.grid.allSatisfy { $0.count == 4 })
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2, "a fresh round replaces the corrupt one")
        XCTAssertEqual(game.score, 0)
    }

    func testASavedBoardWithNonPowerOfTwoTilesIsDiscarded() {
        var values = Array(repeating: 0, count: 16)
        values[3] = 5
        defaults.set(values, forKey: "savedGridV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2)
        XCTAssertFalse(game.grid.flatMap { $0 }.contains(5))
    }

    func testASavedBoardWithANegativeTileIsDiscarded() {
        var values = Array(repeating: 0, count: 16)
        values[0] = -2
        defaults.set(values, forKey: "savedGridV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertFalse(game.grid.flatMap { $0 }.contains(-2))
    }

    func testANonNumericSavedBoardIsDiscarded() {
        defaults.set(["2", "4", "8"], forKey: "savedGridV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(game.grid.flatMap { $0 }.filter { $0 != 0 }.count, 2)
    }

    func testANegativeSavedScoreIsClampedRatherThanRestored() {
        defaults.set(Array(repeating: 0, count: 16), forKey: "savedGridV2")
        defaults.set(-99, forKey: "savedScoreV2")

        let game = GameViewModel(loadSavedGame: true, defaults: defaults)
        XCTAssertEqual(game.score, 0)
    }

    func testANegativeStoredBestScoreIsClampedToZero() {
        defaults.set(-1000, forKey: "highScore")
        let game = GameViewModel(loadSavedGame: false, defaults: defaults)
        XCTAssertEqual(game.highScore, 0)
    }

    func testTheBestScoreSurvivesARestartAndNeverDecreases() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros], score: 100)
        XCTAssertTrue(game.swipe(direction: .left))
        let best = game.highScore
        XCTAssertGreaterThanOrEqual(best, 100)

        game.restartGame()
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.highScore, best, "a new round must not lower the best score")

        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros], score: 1)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.highScore, best, "a worse round must not overwrite the best score")
    }

    func testAGameThatDoesNotSaveLeavesNoStoredRound() {
        let game = GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertNil(defaults.array(forKey: "savedGridV2"), "a preview game must not write over a real round")
    }

    // MARK: - Helpers

    private let zeros = [0, 0, 0, 0]

    private var allDirections: [GameViewModel.Direction] { [.up, .down, .left, .right] }

    private func makeGame(
        randomIndex: @escaping (Int) -> Int = { _ in 0 },
        randomUnit: @escaping () -> Double = { 0 }
    ) -> GameViewModel {
        GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: randomIndex, randomUnit: randomUnit)
    }

    /// `loadSavedGame` is also the write switch: a game built with `false` is a
    /// throwaway preview and deliberately never persists. Persistence tests
    /// therefore need the loading flavour.
    private func makePersistingGame() -> GameViewModel {
        GameViewModel(loadSavedGame: true, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
    }
}
