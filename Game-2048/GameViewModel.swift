import Foundation

final class GameViewModel: ObservableObject {
    enum Direction { case up, down, left, right }

    private struct Snapshot {
        let grid: [[Int]]
        let score: Int
        let hasWon: Bool
    }

    /// Where a round is kept.
    ///
    /// Two complete, independent rounds live on this device: the one played
    /// signed out and the one played signed in. They never touch. Signing in
    /// does not hand a guest board to an account, and signing out returns the
    /// guest board exactly as it was left, best score included. See
    /// ARCHITECTURE.md, "Guest and account profiles".
    enum Profile { case guest, account }

    /// What happened when a profile was adopted.
    enum SessionStart { case active, restored, fresh }

    private struct Keys {
        let grid: String
        let score: String
        let highScore: String
        let hasWon: String
        let moves: String

        static let guest = Keys(
            grid: "savedGridV2",
            score: "savedScoreV2",
            highScore: "highScore",
            hasWon: "savedHasWonV2",
            moves: "savedMovesV2"
        )
        static let account = Keys(
            grid: "accountSavedGridV1",
            score: "accountSavedScoreV1",
            highScore: "accountHighScoreV1",
            hasWon: "accountSavedHasWonV1",
            moves: "accountSavedMovesV1"
        )

        var all: [String] { [grid, score, highScore, hasWon, moves] }
    }

    /// What just happened to the round. The optional cloud layer observes
    /// these; the rules engine knows nothing about the observer.
    enum RoundChange { case move, undo, newGame, gameOver, restored, profileChanged }

    let gridSize = 4
    @Published var grid: [[Int]]
    @Published var score: Int
    @Published private(set) var highScore: Int
    @Published var hasWon: Bool
    @Published private(set) var canUndo = false

    /// Moves played in this round. It feeds the cloud sync's "which device got
    /// further" comparison and is deliberately *not* rewound by undo: a number
    /// a player can lower by pressing a button is not a measurement.
    @Published private(set) var moves = 0

    /// Which storage profile the visible round belongs to.
    @Published private(set) var profile: Profile = .guest

    /// Whether the visible round is something a player would mind losing.
    var hasProgress: Bool { score > 0 || moves > 0 }

    private var keys: Keys { profile == .guest ? .guest : .account }

    /// Set by the cloud layer. A closure rather than a dependency so the rules
    /// engine keeps compiling, and keeps being testable, with no cloud present.
    var onRoundChanged: ((RoundChange) -> Void)?

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
        self.highScore = max(0, defaults.integer(forKey: Keys.guest.highScore))
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
        moves += 1
        addNewNumber()
        updateGameStatus()
        updateHighScore()
        persist()
        notify(isGameOver() ? .gameOver : .move)
        return true
    }

    func restartGame() {
        resetRound()
        notify(.newGame)
    }

    /// A fresh board with no observer notification, for callers that send
    /// their own — a profile switch is not a new game the cloud should upload.
    private func resetRound() {
        grid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
        score = 0
        hasWon = false
        previous = nil
        canUndo = false
        moves = 0
        addNewNumber()
        addNewNumber()
        persist()
    }

    // MARK: - Profiles

    /// Parks the guest round and switches to the signed-in one.
    ///
    /// The guest round is written to its own keys first and then left alone
    /// for the whole session, so signing out restores it exactly. Nothing
    /// from it is carried across: not the board, not the score, and not the
    /// best score.
    ///
    /// - Parameter fresh: true for a new sign-in, which discards whatever this
    ///   device last cached for an account — it is not necessarily *this*
    ///   account's, and uploading it would overwrite the real round.
    @discardableResult
    func beginAccountSession(fresh: Bool = false) -> SessionStart {
        guard profile == .guest else { return .active }
        persist()
        if fresh { clear(Keys.account) }
        profile = .account
        return adoptProfile()
    }

    /// Discards the signed-in round and restores the guest one.
    ///
    /// The account's round lives on the server; the copy here is a cache, and
    /// keeping it would hand the next person to sign in on this device
    /// someone else's board.
    @discardableResult
    func endAccountSession() -> Bool {
        guard profile == .account else { return false }
        clear(Keys.account)
        profile = .guest
        _ = adoptProfile()
        return true
    }

    /**
     Raises the signed-in profile's best score to the account's career best.

     An account whose saved round is gone still has a history, and showing
     "Best 0" to a player with nine thousand points behind them is the same
     class of wrong number as showing a guest's best on a brand-new account —
     just in the other direction.
     */
    @discardableResult
    func adoptCareerBest(_ best: Int) -> Bool {
        guard profile == .account, best > highScore else { return false }
        highScore = best
        defaults.set(highScore, forKey: keys.highScore)
        persist()
        return true
    }

    private func adoptProfile() -> SessionStart {
        highScore = max(0, defaults.integer(forKey: keys.highScore))
        previous = nil
        canUndo = false
        let restored = restoreSavedGame()
        if restored == false { resetRound() }
        notify(.profileChanged)
        return restored ? .restored : .fresh
    }

    private func clear(_ keys: Keys) {
        for key in keys.all { defaults.removeObject(forKey: key) }
    }

    func undo() {
        guard let previous else { return }
        grid = previous.grid
        score = previous.score
        hasWon = previous.hasWon
        self.previous = nil
        canUndo = false
        persist()
        notify(.undo)
    }

    // MARK: - Cloud bridge

    /// The round in the shape every client exchanges with the API. The board
    /// travels as flat cells because that is what the service stores; the
    /// conversion happens here and nowhere else.
    func cloudSave() -> CloudSave {
        CloudSave(
            board: grid.flatMap { $0 },
            score: score,
            bestScore: highScore,
            won: hasWon,
            gameOver: isGameOver(),
            moves: moves
        )
    }

    /// Replaces the round with one that came from another device.
    ///
    /// Validated with the same predicate that guards a corrupt `UserDefaults`
    /// entry: a payload from the network is no more trustworthy than one from
    /// disk, and is refused the same way rather than half-applied.
    @discardableResult
    func applyCloudSave(_ save: CloudSave) -> Bool {
        guard save.board.count == gridSize * gridSize, save.board.allSatisfy(isValidTile) else { return false }

        grid = stride(from: 0, to: save.board.count, by: gridSize).map { Array(save.board[$0..<$0 + gridSize]) }
        score = max(0, save.score)
        highScore = max(highScore, max(0, save.bestScore), score)
        hasWon = save.won || grid.joined().contains { $0 >= 2048 }
        moves = max(0, save.moves)
        previous = nil
        canUndo = false
        defaults.set(highScore, forKey: keys.highScore)
        persist()
        notify(.restored)
        return true
    }

    private func notify(_ change: RoundChange) {
        onRoundChanged?(change)
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
        defaults.set(highScore, forKey: keys.highScore)
    }

    private func persist() {
        guard savesProgress else { return }
        defaults.set(grid.flatMap { $0 }, forKey: keys.grid)
        defaults.set(score, forKey: keys.score)
        defaults.set(hasWon, forKey: keys.hasWon)
        defaults.set(moves, forKey: keys.moves)
        defaults.set(highScore, forKey: keys.highScore)
    }

    private func restoreSavedGame() -> Bool {
        guard savesProgress,
              let values = defaults.array(forKey: keys.grid) as? [Int],
              values.count == gridSize * gridSize,
              values.allSatisfy(isValidTile) else { return false }
        grid = stride(from: 0, to: values.count, by: gridSize).map { Array(values[$0..<$0 + gridSize]) }
        score = max(0, defaults.integer(forKey: keys.score))
        hasWon = defaults.bool(forKey: keys.hasWon)
        moves = max(0, defaults.integer(forKey: keys.moves))
        return true
    }

    private func isValid(grid: [[Int]]) -> Bool {
        grid.count == gridSize && grid.allSatisfy { $0.count == gridSize && $0.allSatisfy(isValidTile) }
    }

    private func isValidTile(_ value: Int) -> Bool {
        value >= 0 && (value == 0 || value.nonzeroBitCount == 1)
    }
}
