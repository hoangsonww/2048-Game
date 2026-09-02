import Foundation

final class GameViewModel: ObservableObject {
    enum Direction { case up, down, left, right }

    private struct Snapshot {
        let grid: [[Int]]
        let score: Int
        let hasWon: Bool
    }

    private enum Storage {
        static let grid = "savedGridV2"
        static let score = "savedScoreV2"
        static let highScore = "highScore"
        static let hasWon = "savedHasWonV2"
    }

    let gridSize = 4
    @Published var grid: [[Int]]
    @Published var score: Int
    @Published private(set) var highScore: Int
    @Published var hasWon: Bool
    @Published private(set) var canUndo = false

    private var previous: Snapshot?
    private let defaults: UserDefaults
    private let savesProgress: Bool
    private let randomIndex: (Int) -> Int
    private let randomUnit: () -> Double

    init(
        loadSavedGame: Bool = true,
        defaults: UserDefaults = .standard,
        randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) },
        randomUnit: @escaping () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.defaults = defaults
        self.savesProgress = loadSavedGame
        self.randomIndex = randomIndex
        self.randomUnit = randomUnit
        self.highScore = max(0, defaults.integer(forKey: Storage.highScore))
        self.score = 0
        self.hasWon = false
        self.grid = Array(repeating: Array(repeating: 0, count: 4), count: 4)

        if loadSavedGame, restoreSavedGame() == false {
            restartGame()
        } else if loadSavedGame == false {
            restartGame()
        }
    }

    @discardableResult
    func swipe(direction: Direction) -> Bool {
        let oldGrid = grid
        let oldScore = score
        let oldWinState = hasWon

        switch direction {
        case .up: moveColumns(reversed: false)
        case .down: moveColumns(reversed: true)
        case .left: grid = grid.map { mergeLine($0).line }
        case .right: grid = grid.map { Array(mergeLine(Array($0.reversed())).line.reversed()) }
        }

        guard oldGrid != grid else {
            score = oldScore
            return false
        }

        previous = Snapshot(grid: oldGrid, score: oldScore, hasWon: oldWinState)
        canUndo = true
        addNewNumber()
        updateGameStatus()
        updateHighScore()
        persist()
        return true
    }

    func restartGame() {
        grid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
        score = 0
        hasWon = false
        previous = nil
        canUndo = false
        addNewNumber()
        addNewNumber()
        persist()
    }

    func undo() {
        guard let previous else { return }
        grid = previous.grid
        score = previous.score
        hasWon = previous.hasWon
        self.previous = nil
        canUndo = false
        persist()
    }

    func addNewNumber() {
        let emptyPositions = grid.indices.flatMap { row in
            grid[row].indices.compactMap { column in grid[row][column] == 0 ? (row, column) : nil }
        }
        guard emptyPositions.isEmpty == false else { return }
        let selected = min(max(randomIndex(emptyPositions.count), 0), emptyPositions.count - 1)
        let position = emptyPositions[selected]
        grid[position.0][position.1] = randomUnit() < 0.9 ? 2 : 4
    }

    func updateGameStatus() {
        if grid.joined().contains(where: { $0 >= 2048 }) { hasWon = true }
    }

    func isGameOver() -> Bool {
        guard grid.joined().allSatisfy({ $0 != 0 }) else { return false }
        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let value = grid[row][column]
                if column < gridSize - 1, value == grid[row][column + 1] { return false }
                if row < gridSize - 1, value == grid[row + 1][column] { return false }
            }
        }
        return true
    }

    func setGameForTesting(grid: [[Int]], score: Int = 0, hasWon: Bool? = nil) {
        precondition(isValid(grid: grid), "Test grid must be a valid 4×4 2048 board.")
        self.grid = grid
        self.score = max(0, score)
        self.hasWon = hasWon ?? grid.joined().contains(where: { $0 >= 2048 })
        previous = nil
        canUndo = false
    }

    private func moveColumns(reversed: Bool) {
        for column in 0..<gridSize {
            let values = (0..<gridSize).map { grid[$0][column] }
            let input = reversed ? Array(values.reversed()) : values
            let merged = mergeLine(input).line
            let output = reversed ? Array(merged.reversed()) : merged
            for row in 0..<gridSize { grid[row][column] = output[row] }
        }
    }

    private func mergeLine(_ values: [Int]) -> (line: [Int], gained: Int) {
        let compact = values.filter { $0 != 0 }
        var result: [Int] = []
        var gained = 0
        var index = 0
        while index < compact.count {
            if index + 1 < compact.count, compact[index] == compact[index + 1] {
                let merged = compact[index] * 2
                result.append(merged)
                gained += merged
                index += 2
            } else {
                result.append(compact[index])
                index += 1
            }
        }
        score += gained
        return (result + Array(repeating: 0, count: gridSize - result.count), gained)
    }

    private func updateHighScore() {
        guard score > highScore else { return }
        highScore = score
        defaults.set(highScore, forKey: Storage.highScore)
    }

    private func persist() {
        guard savesProgress else { return }
        defaults.set(grid.flatMap { $0 }, forKey: Storage.grid)
        defaults.set(score, forKey: Storage.score)
        defaults.set(hasWon, forKey: Storage.hasWon)
    }

    private func restoreSavedGame() -> Bool {
        guard let values = defaults.array(forKey: Storage.grid) as? [Int],
              values.count == gridSize * gridSize,
              values.allSatisfy(isValidTile) else { return false }
        grid = stride(from: 0, to: values.count, by: gridSize).map { Array(values[$0..<$0 + gridSize]) }
        score = max(0, defaults.integer(forKey: Storage.score))
        hasWon = defaults.bool(forKey: Storage.hasWon)
        return true
    }

    private func isValid(grid: [[Int]]) -> Bool {
        grid.count == gridSize && grid.allSatisfy { $0.count == gridSize && $0.allSatisfy(isValidTile) }
    }

    private func isValidTile(_ value: Int) -> Bool {
        value >= 0 && (value == 0 || value.nonzeroBitCount == 1)
    }
}
