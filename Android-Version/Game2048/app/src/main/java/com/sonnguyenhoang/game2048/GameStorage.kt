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

    /** Forgets everything this slot holds, leaving no trace for the next round. */
    fun clear()
}

/**
 * One slot of saved progress.
 *
 * The [prefix] is what gives the guest and the signed-in round completely
 * separate storage in the same preferences file. Two instances with different
 * prefixes cannot read or overwrite each other, which is the mechanism behind
 * "signing out restores exactly what you were playing".
 */
internal class SharedPreferencesGameStorage(
    private val preferences: SharedPreferences,
    private val prefix: String = ""
) : GameStorage {
    private val gridKey = prefix + KEY_GRID
    private val scoreKey = prefix + KEY_SCORE
    private val bestKey = prefix + KEY_BEST
    private val wonKey = prefix + KEY_WON
    private val movesKey = prefix + KEY_MOVES

    override fun load(): SavedGame? {
        val values = preferences.getString(gridKey, null)?.split(",")?.mapNotNull(String::toIntOrNull) ?: return null
        if (values.size != 16) return null
        return SavedGame(
            grid = values.chunked(4),
            score = preferences.getInt(scoreKey, 0),
            best = preferences.getInt(bestKey, 0),
            hasWon = preferences.getBoolean(wonKey, false),
            moves = preferences.getInt(movesKey, 0)
        )
    }

    override fun loadBest(): Int = preferences.getInt(bestKey, 0)

    override fun save(game: SavedGame) {
        preferences.edit()
            .putString(gridKey, game.grid.flatten().joinToString(","))
            .putInt(scoreKey, game.score)
            .putInt(bestKey, game.best)
            .putBoolean(wonKey, game.hasWon)
            .putInt(movesKey, game.moves)
            .apply()
    }

    override fun clear() {
        preferences.edit()
            .remove(gridKey)
            .remove(scoreKey)
            .remove(bestKey)
            .remove(wonKey)
            .remove(movesKey)
            .apply()
    }

    internal companion object {
        /** Where a round played signed in is kept, away from the guest one. */
        const val ACCOUNT_PREFIX = "account_"

        const val KEY_GRID = "saved_grid_v2"
        const val KEY_SCORE = "saved_score_v2"
        const val KEY_BEST = "high_score"
        const val KEY_WON = "saved_won_v2"
        const val KEY_MOVES = "saved_moves_v2"
    }
}
