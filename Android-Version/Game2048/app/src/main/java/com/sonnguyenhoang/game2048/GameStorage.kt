package com.sonnguyenhoang.game2048

import android.content.SharedPreferences

data class SavedGame(
    val grid: List<List<Int>>,
    val score: Int,
    val best: Int,
    val hasWon: Boolean,
    /**
     * Moves played in this round. Persisted so the count survives a relaunch
     * and so a cloud sync can tell which of two devices got further. Older
     * saves predate the field and restore as zero, which is why it is
     * defaulted rather than required.
     */
    val moves: Int = 0
)

interface GameStorage {
    fun load(): SavedGame?
    fun loadBest(): Int
    fun save(game: SavedGame)
}

internal class SharedPreferencesGameStorage(private val preferences: SharedPreferences) : GameStorage {
    override fun load(): SavedGame? {
        val values = preferences.getString(KEY_GRID, null)?.split(",")?.mapNotNull(String::toIntOrNull) ?: return null
        if (values.size != 16) return null
        return SavedGame(
            grid = values.chunked(4),
            score = preferences.getInt(KEY_SCORE, 0),
            best = preferences.getInt(KEY_BEST, 0),
            hasWon = preferences.getBoolean(KEY_WON, false),
            moves = preferences.getInt(KEY_MOVES, 0)
        )
    }

    override fun loadBest(): Int = preferences.getInt(KEY_BEST, 0)

    override fun save(game: SavedGame) {
        preferences.edit()
            .putString(KEY_GRID, game.grid.flatten().joinToString(","))
            .putInt(KEY_SCORE, game.score)
            .putInt(KEY_BEST, game.best)
            .putBoolean(KEY_WON, game.hasWon)
            .putInt(KEY_MOVES, game.moves)
            .apply()
    }

    private companion object {
        const val KEY_GRID = "saved_grid_v2"
        const val KEY_SCORE = "saved_score_v2"
        const val KEY_BEST = "high_score"
        const val KEY_WON = "saved_won_v2"
        const val KEY_MOVES = "saved_moves_v2"
    }
}
