package com.sonnguyenhoang.game2048

import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import kotlin.random.Random

class GameViewModel : ViewModel() {
    val gridSize = 4
    var grid by mutableStateOf(Array(gridSize) { IntArray(gridSize) })
    var score by mutableStateOf(0)
    var highScore by mutableStateOf(0)

    init {
        initializeGame()
    }

    fun initializeGame() {
        grid = Array(gridSize) { IntArray(gridSize) }
        score = 0
        addNewNumber()
        addNewNumber()
    }

    fun addNewNumber() {
        val emptyCells = mutableListOf<Pair<Int, Int>>()
        for (i in grid.indices) {
            for (j in grid[i].indices) {
                if (grid[i][j] == 0) {
                    emptyCells.add(i to j)
                }
            }
        }

        if (emptyCells.isNotEmpty()) {
            val (x, y) = emptyCells[Random.nextInt(emptyCells.size)]
            grid[x][y] = if (Random.nextDouble() < 0.9) 2 else 4
        }
    }

    fun swipe(direction: Direction) {
        val oldGrid = grid.map { it.clone() }
        when (direction) {
            Direction.UP -> swipeUp()
            Direction.DOWN -> swipeDown()
            Direction.LEFT -> swipeLeft()
            Direction.RIGHT -> swipeRight()
        }
        if (gridChanged(oldGrid)) {
            addNewNumber()
        }
    }

    private fun gridChanged(oldGrid: List<IntArray>): Boolean {
        return oldGrid.indices.any { !oldGrid[it].contentEquals(grid[it]) }
    }

    private fun swipeLeft() {
        for (i in grid.indices) {
            val newRow = mergeRow(grid[i].filter { it != 0 })
            for (j in newRow.indices) {
                grid[i][j] = newRow[j]
            }
            for (j in newRow.size until gridSize) {
                grid[i][j] = 0
            }
        }
    }

    private fun swipeRight() {
        for (i in grid.indices) {
            val newRow = mergeRow(grid[i].filter { it != 0 }).reversed()
            for (j in newRow.indices) {
                grid[i][gridSize - j - 1] = newRow[j]
            }
            for (j in 0 until gridSize - newRow.size) {
                grid[i][j] = 0
            }
        }
    }

    private fun swipeUp() {
        for (j in 0 until gridSize) {
            val column = List(gridSize) { i -> grid[i][j] }.filter { it != 0 }
            val merged = mergeRow(column)
            for (i in merged.indices) {
                grid[i][j] = merged[i]
            }
            for (i in merged.size until gridSize) {
                grid[i][j] = 0
            }
        }
    }

    private fun swipeDown() {
        for (j in 0 until gridSize) {
            val column = List(gridSize) { i -> grid[i][j] }.filter { it != 0 }
            val merged = mergeRow(column).reversed()
            for (i in 0 until gridSize - merged.size) {
                grid[i][j] = 0
            }
            for (i in gridSize - merged.size until gridSize) {
                grid[i][j] = merged[i + merged.size - gridSize]
            }
        }
    }

    private fun mergeRow(row: List<Int>): List<Int> {
        val mergedRow = mutableListOf<Int>()
        var i = 0
        while (i < row.size) {
            if (i + 1 < row.size && row[i] == row[i + 1]) {
                val newValue = row[i] * 2
                mergedRow.add(newValue)
                score += newValue
                i += 2
            } else {
                mergedRow.add(row[i])
                i++
            }
        }
        return mergedRow + List(gridSize - mergedRow.size) { 0 }
    }

    enum class Direction {
        UP, DOWN, LEFT, RIGHT
    }
}
