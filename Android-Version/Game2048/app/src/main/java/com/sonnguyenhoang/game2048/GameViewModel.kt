package com.sonnguyenhoang.game2048

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.sonnguyenhoang.game2048.cloud.CloudSave
import kotlin.random.Random

class GameViewModel(
    private val storage: GameStorage? = null,
    private val randomIndex: (Int) -> Int = { Random.nextInt(it) },
    private val randomUnit: () -> Double = { Random.nextDouble() }
) : ViewModel() {
    enum class Direction { UP, DOWN, LEFT, RIGHT }

    private data class Snapshot(val grid: List<List<Int>>, val score: Int, val hasWon: Boolean)

    val gridSize = 4
    var grid by mutableStateOf(emptyGrid())
        private set
    var score by mutableStateOf(0)
        private set
    var highScore by mutableStateOf((storage?.loadBest() ?: 0).coerceAtLeast(0))
        private set
    var hasWon by mutableStateOf(false)
        private set
    var canUndo by mutableStateOf(false)
        private set

    /**
     * Moves played in this round. It feeds the cloud sync's "which device got
     * further" comparison and is deliberately *not* rewound by undo: a number
     * a player can lower by pressing a button is not a measurement.
     */
    var moves by mutableStateOf(0)
        private set

    private var previous: Snapshot? = null

    /**
     * The optional cloud layer observes the round through this. It is a
     * nullable callback rather than a dependency so the rules engine keeps
     * compiling, and keeps being testable, with no cloud code present at all.
     */
    var onRoundChanged: ((RoundChange) -> Unit)? = null

    enum class RoundChange { MOVE, UNDO, NEW_GAME, GAME_OVER, RESTORED }

    init {
        if (!restore()) restartGame()
    }

    fun restartGame() {
        var next = emptyGrid()
        next = addNewNumber(next)
        next = addNewNumber(next)
        grid = next
        score = 0
        hasWon = false
        previous = null
        canUndo = false
        moves = 0
        persist()
        notify(RoundChange.NEW_GAME)
    }

    fun swipe(direction: Direction): Boolean {
        val original = grid.map { it.toList() }
        val originalScore = score
        val originalWin = hasWon
        var gained = 0

        val moved = when (direction) {
            Direction.LEFT -> original.map { line -> mergeLine(line).also { gained += it.second }.first }
            Direction.RIGHT -> original.map { line -> mergeLine(line.reversed()).also { gained += it.second }.first.reversed() }
            Direction.UP, Direction.DOWN -> {
                val output = MutableList(gridSize) { MutableList(gridSize) { 0 } }
                for (column in 0 until gridSize) {
                    val values = (0 until gridSize).map { row -> original[row][column] }
                    val input = if (direction == Direction.DOWN) values.reversed() else values
                    val result = mergeLine(input)
                    gained += result.second
                    val finalColumn = if (direction == Direction.DOWN) result.first.reversed() else result.first
                    for (row in 0 until gridSize) output[row][column] = finalColumn[row]
                }
                output.map { it.toList() }
            }
        }

        if (moved == original) return false
        previous = Snapshot(original, originalScore, originalWin)
        canUndo = true
        score += gained
        grid = addNewNumber(moved)
        moves += 1
        hasWon = hasWon || grid.flatten().any { it >= 2048 }
        if (score > highScore) highScore = score
        persist()
        notify(if (isGameOver()) RoundChange.GAME_OVER else RoundChange.MOVE)
        return true
    }

    fun undo() {
        val snapshot = previous ?: return
        grid = snapshot.grid
        score = snapshot.score
        hasWon = snapshot.hasWon
        previous = null
        canUndo = false
        persist()
        notify(RoundChange.UNDO)
    }

    /**
     * The round in the shape every client exchanges with the API. The board
     * travels as flat cells because that is what the service stores; the
     * conversion happens here and nowhere else.
     */
    fun cloudSave(): CloudSave = CloudSave(
        board = grid.flatten(),
        score = score,
        bestScore = highScore,
        won = hasWon,
        gameOver = isGameOver(),
        moves = moves
    )

    /**
     * Replaces the round with one that came from another device.
     *
     * Validated with the same predicate that guards a corrupt
     * `SharedPreferences` entry: a payload from the network is no more
     * trustworthy than one from disk, and is refused the same way rather than
     * half-applied.
     */
    fun applyCloudSave(save: CloudSave): Boolean {
        if (save.board.size != gridSize * gridSize) return false
        val restored = save.board.chunked(gridSize)
        if (!isValidGrid(restored)) return false

        grid = restored
        score = save.score.coerceAtLeast(0)
        highScore = maxOf(highScore, save.bestScore.coerceAtLeast(0), score)
        hasWon = save.won || restored.flatten().any { it >= 2048 }
        moves = save.moves.coerceAtLeast(0)
        previous = null
        canUndo = false
        persist()
        notify(RoundChange.RESTORED)
        return true
    }

    private fun notify(change: RoundChange) {
        // A cloud layer with a bug in it must degrade to "no sync", never to
        // "the board stopped responding".
        runCatching { onRoundChanged?.invoke(change) }
    }

    fun isGameOver(): Boolean {
        if (grid.flatten().any { it == 0 }) return false
        for (row in 0 until gridSize) {
            for (column in 0 until gridSize) {
                val value = grid[row][column]
                if (column < gridSize - 1 && value == grid[row][column + 1]) return false
                if (row < gridSize - 1 && value == grid[row + 1][column]) return false
            }
        }
        return true
    }

    internal fun setGameForTesting(values: List<List<Int>>, newScore: Int = 0, won: Boolean? = null) {
        require(isValidGrid(values)) { "Test grid must be a valid 4x4 2048 board." }
        grid = values.map { it.toList() }
        score = newScore.coerceAtLeast(0)
        hasWon = won ?: values.flatten().any { it >= 2048 }
        previous = null
        canUndo = false
    }

    private fun mergeLine(values: List<Int>): Pair<List<Int>, Int> {
        val compact = values.filter { it != 0 }
        val result = mutableListOf<Int>()
        var gained = 0
        var index = 0
        while (index < compact.size) {
            if (index + 1 < compact.size && compact[index] == compact[index + 1]) {
                val merged = compact[index] * 2
                result += merged
                gained += merged
                index += 2
            } else {
                result += compact[index]
                index += 1
            }
        }
        return (result + List(gridSize - result.size) { 0 }) to gained
    }

    private fun addNewNumber(board: List<List<Int>>): List<List<Int>> {
        val empty = board.indices.flatMap { row -> board[row].indices.mapNotNull { column -> if (board[row][column] == 0) row to column else null } }
        if (empty.isEmpty()) return board
        val selected = randomIndex(empty.size).coerceIn(0, empty.lastIndex)
        val (row, column) = empty[selected]
        return board.mapIndexed { rowIndex, values -> values.mapIndexed { columnIndex, value -> if (rowIndex == row && columnIndex == column) if (randomUnit() < 0.9) 2 else 4 else value } }
    }

    private fun persist() {
        storage?.save(SavedGame(grid, score, highScore, hasWon, moves))
    }

    private fun restore(): Boolean {
        val saved = storage?.load() ?: return false
        if (!isValidGrid(saved.grid)) return false
        grid = saved.grid.map { it.toList() }
        score = saved.score.coerceAtLeast(0)
        highScore = maxOf(highScore, saved.best.coerceAtLeast(0), score)
        hasWon = saved.hasWon || grid.flatten().any { it >= 2048 }
        moves = saved.moves.coerceAtLeast(0)
        return true
    }

    private fun emptyGrid() = List(gridSize) { List(gridSize) { 0 } }

    private fun isValidGrid(values: List<List<Int>>): Boolean {
        return values.size == gridSize && values.all { row ->
            row.size == gridSize && row.all { value -> value >= 0 && (value == 0 || value.countOneBits() == 1) }
        }
    }
}
