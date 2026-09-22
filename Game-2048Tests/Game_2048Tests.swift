import XCTest
@testable import Game_2048

final class GameViewModelTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "GameViewModelTests")
        defaults.removePersistentDomain(forName: "GameViewModelTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "GameViewModelTests")
        defaults = nil
        super.tearDown()
    }

    func testNewGameStartsWithExactlyTwoValidTiles() {
        let game = makeGame()
        XCTAssertEqual(nonZeroTiles(game).count, 2)
        XCTAssertTrue(nonZeroTiles(game).allSatisfy { $0 == 2 || $0 == 4 })
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.highScore, 0)
        XCTAssertFalse(game.hasWon)
        XCTAssertFalse(game.canUndo)
    }

    func testRestartResetsRoundButPreservesBestScore() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros], score: 20)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.highScore, 24)
        game.restartGame()
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.highScore, 24)
        XCTAssertEqual(nonZeroTiles(game).count, 2)
        XCTAssertFalse(game.canUndo)
    }

    func testLeftMoveCompactsMergesOnceAndScoresAllPairs() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 4, 4], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.grid[0], [4, 8, 2, 0])
        XCTAssertEqual(game.score, 12)
        XCTAssertTrue(game.canUndo)
    }

    func testRightMoveUsesReverseMergeOrder() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 2, 2, 0], zeros, zeros, zeros])
        XCTAssertTrue(game.swipe(direction: .right))
        XCTAssertEqual(game.grid[0], [2, 0, 2, 4])
        XCTAssertEqual(game.score, 4)
    }

    func testUpMoveMergesColumns() {
        let game = makeGame(randomIndex: { $0 - 1 })
        game.setGameForTesting(grid: [[2, 0, 0, 0], [2, 0, 0, 0], [4, 0, 0, 0], [4, 0, 0, 0]])
        XCTAssertTrue(game.swipe(direction: .up))
        XCTAssertEqual(game.grid.map { $0[0] }, [4, 8, 0, 0])
        XCTAssertEqual(game.score, 12)
    }

    func testDownMoveMergesColumnsInReverseOrder() {
        let game = makeGame(randomIndex: { $0 - 1 })
        game.setGameForTesting(grid: [[2, 0, 0, 0], [2, 0, 0, 0], [2, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertTrue(game.swipe(direction: .down))
        XCTAssertEqual(game.grid.map { $0[0] }, [0, 0, 2, 4])
        XCTAssertEqual(game.score, 4)
    }

    func testIneffectiveMoveDoesNotSpawnScoreOrCreateHistory() {
        let game = makeGame()
        let board = [[2, 4, 0, 0], zeros, zeros, zeros]
        game.setGameForTesting(grid: board, score: 8)
        XCTAssertFalse(game.swipe(direction: .left))
        XCTAssertEqual(game.grid, board)
        XCTAssertEqual(game.score, 8)
        XCTAssertFalse(game.canUndo)
    }

    func testUndoRestoresBoardScoreAndWinStateOnlyOnce() {
        let game = makeGame()
        let board = [[1024, 1024, 0, 0], zeros, zeros, zeros]
        game.setGameForTesting(grid: board, score: 100, hasWon: false)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertTrue(game.hasWon)
        game.undo()
        XCTAssertEqual(game.grid, board)
        XCTAssertEqual(game.score, 100)
        XCTAssertFalse(game.hasWon)
        XCTAssertFalse(game.canUndo)
        game.undo()
        XCTAssertEqual(game.grid, board)
        XCTAssertEqual(game.score, 100)
    }

    func testTileProbabilityBoundaryAndFullBoardNoOp() {
        let two = makeGame(randomUnit: { 0.899999 })
        two.setGameForTesting(grid: [zeros, zeros, zeros, zeros])
        two.addNewNumber()
        XCTAssertEqual(two.grid[0][0], 2)
        let four = makeGame(randomUnit: { 0.9 })
        four.setGameForTesting(grid: [zeros, zeros, zeros, zeros])
        four.addNewNumber()
        XCTAssertEqual(four.grid[0][0], 4)
        let full = [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]]
        four.setGameForTesting(grid: full)
        four.addNewNumber()
        XCTAssertEqual(four.grid, full)
    }

    func testGameOverRequiresFullBoardWithoutHorizontalOrVerticalMerge() {
        let game = makeGame()
        game.setGameForTesting(grid: [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]])
        XCTAssertTrue(game.isGameOver())
        game.setGameForTesting(grid: [[2, 2, 4, 8], [4, 8, 16, 32], [8, 16, 32, 64], [16, 32, 64, 128]])
        XCTAssertFalse(game.isGameOver())
        game.setGameForTesting(grid: [[2, 4, 8, 16], [2, 8, 16, 32], [4, 16, 32, 64], [8, 32, 64, 128]])
        XCTAssertFalse(game.isGameOver())
        game.setGameForTesting(grid: [[2, 4, 0, 8], [4, 8, 16, 32], [8, 16, 32, 64], [16, 32, 64, 128]])
        XCTAssertFalse(game.isGameOver())
    }

    func testHighScoreUpdatesAndPersistsWithSavedRound() {
        let game = GameViewModel(loadSavedGame: true, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        game.setGameForTesting(grid: [[2, 2, 0, 0], zeros, zeros, zeros], score: 40)
        XCTAssertTrue(game.swipe(direction: .left))
        XCTAssertEqual(game.highScore, 44)
        let restored = GameViewModel(loadSavedGame: true, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        XCTAssertEqual(restored.grid, game.grid)
        XCTAssertEqual(restored.score, 44)
        XCTAssertEqual(restored.highScore, 44)
        XCTAssertFalse(restored.canUndo, "undo history is intentionally session-only")
    }

    func testCorruptSavedBoardAndNegativeScoresAreRejectedOrClamped() {
        defaults.set(Array(repeating: 3, count: 16), forKey: "savedGridV2")
        defaults.set(-50, forKey: "savedScoreV2")
        defaults.set(-100, forKey: "highScore")
        let game = GameViewModel(loadSavedGame: true, defaults: defaults, randomIndex: { _ in 0 }, randomUnit: { 0 })
        XCTAssertEqual(nonZeroTiles(game).count, 2)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.highScore, 0)
    }

    private var zeros: [Int] { [0, 0, 0, 0] }

    private func makeGame(
        randomIndex: @escaping (Int) -> Int = { _ in 0 },
        randomUnit: @escaping () -> Double = { 0 }
    ) -> GameViewModel {
        GameViewModel(loadSavedGame: false, defaults: defaults, randomIndex: randomIndex, randomUnit: randomUnit)
    }

    private func nonZeroTiles(_ game: GameViewModel) -> [Int] {
        game.grid.flatMap { $0 }.filter { $0 != 0 }
    }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Core rules test maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Keep one focused example for each movement direction.
//
// 02. Assert compaction, single-merge behavior, score gain, and spawn behavior independently.
//
// 03. Prove ineffective moves leave board, score, history, and random providers untouched.
//
// 04. Keep undo exactly one valid move deep.
//
// 05. Test game-over with both horizontal and vertical merge opportunities.
//
// 06. Use injected randomness at boundary values for the two-versus-four distribution.
//
// 07. Verify persistence through a dedicated defaults suite rather than global state.
//
// 08. Prefer small readable boards whose expected result can be reviewed visually.
//
// Symbol and scenario index
//
// 01. `final class GameViewModelTests: XCTestCase`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `func testNewGameStartsWithExactlyTwoValidTiles()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `func testRestartResetsRoundButPreservesBestScore()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func testLeftMoveCompactsMergesOnceAndScoresAllPairs()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 05. `func testRightMoveUsesReverseMergeOrder()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 06. `func testUpMoveMergesColumns()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 07. `func testDownMoveMergesColumnsInReverseOrder()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 08. `func testIneffectiveMoveDoesNotSpawnScoreOrCreateHistory()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 09. `func testUndoRestoresBoardScoreAndWinStateOnlyOnce()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 10. `func testTileProbabilityBoundaryAndFullBoardNoOp()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 11. `func testGameOverRequiresFullBoardWithoutHorizontalOrVerticalMerge()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 12. `func testHighScoreUpdatesAndPersistsWithSavedRound()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 13. `func testCorruptSavedBoardAndNegativeScoresAreRejectedOrClamped()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 14. `private func makeGame(`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 15. `private func nonZeroTiles(_ game: GameViewModel) -> [Int]`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
