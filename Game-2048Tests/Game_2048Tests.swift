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
            [2, 2, 0, 0],
            [4, 4, 2, 0]
        ]

        gameViewModel.swipe(direction: .left)

        let expectedGrid = [
            [4, 4],
            [8],
            [4],
            [8,2]
        ]
        
        for (rowIndex, expectedRow) in expectedGrid.enumerated() {
            let actualRowLeftSide = Array(gameViewModel.grid[rowIndex][0..<expectedRow.count])
            XCTAssertEqual(actualRowLeftSide, expectedRow, "Swiping left should correctly merge tiles.")
        }
    }

    func testAddNewNumberAfterValidMove() throws {
        // Set a grid with a valid move, swipe, and ensure a new number is added
        gameViewModel.grid = [
            [2, 2, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
        ]

        let oldGrid = gameViewModel.grid
        
        // Make sure swipe action not merging tiles. We can’t predict the result if the swipe merges tiles.
        gameViewModel.swipe(direction: .down)

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
    
    func testGameUndoRestoresPreviousGridAfterValidMove() throws {
        // Set a grid
        gameViewModel.grid = [
            [2, 2, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
        ]
        

        let oldGrid = gameViewModel.grid
        
        // Valid move
        gameViewModel.swipe(direction: .left)

        let newGrid = gameViewModel.grid
        
        // Undo the move
        gameViewModel.undo()
        
        let undoGrid = gameViewModel.grid

        // Check
        XCTAssertTrue(undoGrid == oldGrid && newGrid != undoGrid, "Undo should restore the grid to its previous state after a valid move.")
    }
    
    func testGameUndoRevertsHighScoreAfterValidMove() throws {
        UserDefaults.standard.set(0, forKey: "highScore")
        gameViewModel.highScore = 0
        gameViewModel.grid = [
            [2, 2, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
        ]
        
        // Perform a valid move (2 + 2 = 4 points)
        gameViewModel.swipe(direction: .left)
        
        // Move should add 4 points to the score
        let highScore = gameViewModel.highScore
        
        // Undo the move
        gameViewModel.undo()
        let undoHighScore = gameViewModel.highScore
        
        XCTAssertTrue(highScore == 4 && undoHighScore == 0, "Undo should revert high score to its previous value if it changed due to the undone move.")
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
