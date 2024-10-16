import XCTest
@testable import Game_2048

final class GameViewModelTests: XCTestCase {

    var gameViewModel: GameViewModel!

    override func setUpWithError() throws {
        // Initialize GameViewModel before each test
        gameViewModel = GameViewModel()
    }

    override func tearDownWithError() throws {
        // Clean up after each test
        gameViewModel = nil
    }

    func testInitialGridSetup() throws {
        // Test if grid is initialized correctly
        let nonZeroTiles = gameViewModel.grid.flatMap { $0 }.filter { $0 != 0 }
        XCTAssertEqual(nonZeroTiles.count, 2, "Grid should start with exactly 2 non-zero tiles.")
        XCTAssertTrue(nonZeroTiles.allSatisfy { $0 == 2 || $0 == 4 }, "Initial tiles should be 2 or 4.")
    }

    func testSwipeLeftMergesCorrectly() throws {
        // Set a custom grid where merging is expected when swiping left
        gameViewModel.grid = [
            [2, 2, 4, 0],
            [0, 4, 4, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
        ]

        gameViewModel.swipe(direction: .left)

        let expectedGrid = [
            [4, 4, 0, 0],
            [8, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
        ]

        XCTAssertEqual(gameViewModel.grid, expectedGrid, "Swiping left should correctly merge tiles.")
    }

    func testAddNewNumberAfterValidMove() throws {
        // Set a grid with a valid move, swipe left, and ensure a new number is added
        gameViewModel.grid = [
            [2, 2, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
        ]

        let oldGrid = gameViewModel.grid
        gameViewModel.swipe(direction: .left)

        let nonZeroTilesOld = oldGrid.flatMap { $0 }.filter { $0 != 0 }.count
        let nonZeroTilesNew = gameViewModel.grid.flatMap { $0 }.filter { $0 != 0 }.count

        XCTAssertGreaterThan(nonZeroTilesNew, nonZeroTilesOld, "A new number should be added after a valid swipe.")
    }

    func testGameOverDetection() throws {
        // Set a grid where no moves are left and verify game over
        gameViewModel.grid = [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 2]
        ]

        XCTAssertTrue(gameViewModel.isGameOver(), "The game should detect a game-over state when no moves are left.")
    }

    func testGameWinDetection() throws {
        // Set a grid with the winning tile 2048 and verify the game detects a win
        gameViewModel.grid = [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 2048, 2, 4],
            [4, 2, 4, 2]
        ]

        gameViewModel.updateGameStatus()

        XCTAssertTrue(gameViewModel.hasWon, "The game should detect a win when a 2048 tile appears.")
    }

    func testPerformanceExample() throws {
        // Performance test case example
        measure {
            for _ in 0..<1000 {
                gameViewModel.swipe(direction: .left)
            }
        }
    }
}
