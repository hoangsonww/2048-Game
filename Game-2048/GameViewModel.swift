import Foundation

class GameViewModel: ObservableObject {
    @Published var grid: [[Int]]
    @Published var score: Int = 0
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")
    let gridSize: Int = 4
    @Published var hasWon: Bool = false

    init() {
        grid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
        addNewNumber()
        addNewNumber()
    }
    
    func updateGameStatus() {
        if grid.flatMap({ $0 }).contains(2048) {
            hasWon = true
        }
    }

    func addNewNumber() {
        var emptyPositions = [(Int, Int)]()
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                if grid[i][j] == 0 {
                    emptyPositions.append((i, j))
                }
            }
        }
        if let position = emptyPositions.randomElement() {
            grid[position.0][position.1] = Int.random(in: 1...2) * 2
        }
    }

    private func moveAndMergeRow(_ row: [Int]) -> [Int] {
        let nonZero = row.filter { $0 != 0 }
        var merged = [Int]()
        var index = 0

        while index < nonZero.count {
            if index + 1 < nonZero.count && nonZero[index] == nonZero[index + 1] {
                merged.append(nonZero[index] * 2)
                score += nonZero[index] * 2
                index += 2
            } else {
                merged.append(nonZero[index])
                index += 1
            }
        }

        return merged + Array(repeating: 0, count: gridSize - merged.count)
    }

    func swipe(direction: Direction) {
        var oldGrid = grid
        switch direction {
        case .up:
            for i in 0..<gridSize {
                var column = (0..<gridSize).map { grid[$0][i] }
                column = moveAndMergeRow(column)
                for j in 0..<gridSize {
                    grid[j][i] = column[j]
                }
            }
        case .down:
            for i in 0..<gridSize {
                var column = (0..<gridSize).map { grid[$0][i] }
                column = moveAndMergeRow(column.reversed()).reversed()
                for j in 0..<gridSize {
                    grid[j][i] = column[j]
                }
            }
        case .left:
            grid = grid.map { moveAndMergeRow($0) }
        case .right:
            grid = grid.map { moveAndMergeRow($0.reversed()).reversed() }
        }

        if oldGrid != grid {
            addNewNumber()
        }

        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "highScore")
        }
        
        updateGameStatus()
    }

    enum Direction {
        case up, down, left, right
    }
    
    func isGameOver() -> Bool {
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                let current = grid[i][j]
                if current == 0 {
                    return false
                }

                if i > 0 && grid[i - 1][j] == current { return false }
                if j > 0 && grid[i][j - 1] == current { return false }
                if i < gridSize - 1 && grid[i + 1][j] == current { return false }
                if j < gridSize - 1 && grid[i][j + 1] == current { return false }
            }
        }
        return true
    }
}
