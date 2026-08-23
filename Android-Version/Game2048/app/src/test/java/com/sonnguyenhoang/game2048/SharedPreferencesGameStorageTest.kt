package com.sonnguyenhoang.game2048

import android.content.SharedPreferences
import org.junit.Assert.*
import org.junit.Test

/**
 * Coverage for the only piece of the Android app that touches storage.
 *
 * [GameViewModelTest] and [GameViewModelEdgeCaseTest] both run against an
 * in-memory [GameStorage], so the real serialisation — a comma-separated grid
 * in a preferences string — has nothing else proving it. A mistake here loses a
 * player's round on the next launch, which is exactly the failure the local-only
 * design is supposed to make impossible.
 *
 * The fake below implements [SharedPreferences] directly rather than mocking
 * it, so the test needs no Android runtime.
 */
class SharedPreferencesGameStorageTest {
    @Test
    fun aSavedRoundIsReadBackExactly() {
        val preferences = FakePreferences()
        val storage = SharedPreferencesGameStorage(preferences)
        val saved = SavedGame(
            grid = listOf(
                listOf(2, 4, 8, 16),
                listOf(32, 64, 128, 256),
                listOf(512, 1024, 2048, 0),
                listOf(0, 0, 0, 2)
            ),
            score = 12_345,
            best = 20_000,
            hasWon = true
        )

        storage.save(saved)
        assertEquals(saved, storage.load())
    }

    @Test
    fun anEmptyStoreHasNothingToRestore() {
        val storage = SharedPreferencesGameStorage(FakePreferences())
        assertNull(storage.load())
        assertEquals(0, storage.loadBest())
    }

    @Test
    fun theBestScoreIsReadableWithoutASavedRound() {
        val preferences = FakePreferences()
        val storage = SharedPreferencesGameStorage(preferences)
        storage.save(SavedGame(grid = fullGrid(), score = 10, best = 999, hasWon = false))

        assertEquals(999, storage.loadBest())
    }

    @Test
    fun aGridOfTheWrongLengthIsRejected() {
        val preferences = FakePreferences()
        // Fifteen cells: a truncated write, or a save from an older layout.
        preferences.strings["saved_grid_v2"] = List(15) { "0" }.joinToString(",")

        assertNull(SharedPreferencesGameStorage(preferences).load())
    }

    @Test
    fun aGridWithUnparseableCellsIsRejectedRatherThanSilentlyShrunk() {
        val preferences = FakePreferences()
        // Non-numeric cells are dropped while parsing, which leaves fewer than
        // sixteen values — the length check is what turns that into a rejection
        // instead of a short, misaligned board.
        preferences.strings["saved_grid_v2"] = (List(14) { "2" } + listOf("x", "")).joinToString(",")

        assertNull(SharedPreferencesGameStorage(preferences).load())
    }

    @Test
    fun anEmptyGridStringIsRejected() {
        val preferences = FakePreferences()
        preferences.strings["saved_grid_v2"] = ""

        assertNull(SharedPreferencesGameStorage(preferences).load())
    }

    @Test
    fun aGridIsRestoredAsFourRowsOfFour() {
        val preferences = FakePreferences()
        preferences.strings["saved_grid_v2"] = (1..16).joinToString(",")

        val loaded = requireNotNull(SharedPreferencesGameStorage(preferences).load())
        assertEquals(4, loaded.grid.size)
        assertTrue(loaded.grid.all { it.size == 4 })
        assertEquals(listOf(1, 2, 3, 4), loaded.grid[0])
        assertEquals(listOf(13, 14, 15, 16), loaded.grid[3])
    }

    @Test
    fun savingTwiceKeepsOnlyTheLatestRound() {
        val storage = SharedPreferencesGameStorage(FakePreferences())
        storage.save(SavedGame(grid = fullGrid(2), score = 1, best = 1, hasWon = false))
        storage.save(SavedGame(grid = fullGrid(4), score = 2, best = 2, hasWon = true))

        val loaded = requireNotNull(storage.load())
        assertEquals(fullGrid(4), loaded.grid)
        assertEquals(2, loaded.score)
        assertTrue(loaded.hasWon)
    }

    @Test
    fun scoresAndWinStateFallBackToZeroWhenOnlyAGridWasStored() {
        val preferences = FakePreferences()
        preferences.strings["saved_grid_v2"] = List(16) { "0" }.joinToString(",")

        val loaded = requireNotNull(SharedPreferencesGameStorage(preferences).load())
        assertEquals(0, loaded.score)
        assertEquals(0, loaded.best)
        assertFalse(loaded.hasWon)
    }

    private fun fullGrid(value: Int = 2) = List(4) { List(4) { value } }

    /**
     * A minimal in-memory [SharedPreferences]. Only the accessors the storage
     * actually calls carry behaviour; the rest satisfy the interface.
     */
    private class FakePreferences : SharedPreferences {
        val strings = mutableMapOf<String, String?>()
        val ints = mutableMapOf<String, Int>()
        val booleans = mutableMapOf<String, Boolean>()

        override fun getAll(): MutableMap<String, *> = (strings + ints + booleans).toMutableMap()
        override fun getString(key: String, defValue: String?): String? = strings[key] ?: defValue
        override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String, defValue: Int): Int = ints[key] ?: defValue
        override fun getLong(key: String, defValue: Long): Long = defValue
        override fun getFloat(key: String, defValue: Float): Float = defValue
        override fun getBoolean(key: String, defValue: Boolean): Boolean = booleans[key] ?: defValue
        override fun contains(key: String): Boolean =
            strings.containsKey(key) || ints.containsKey(key) || booleans.containsKey(key)

        override fun edit(): SharedPreferences.Editor = FakeEditor(this)
        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener
        ) = Unit

        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener
        ) = Unit
    }

    /** Writes straight through, so `apply()` is observable immediately. */
    private class FakeEditor(private val preferences: FakePreferences) : SharedPreferences.Editor {
        override fun putString(key: String, value: String?) = apply { preferences.strings[key] = value }
        override fun putStringSet(key: String, values: MutableSet<String>?) = this
        override fun putInt(key: String, value: Int) = apply { preferences.ints[key] = value }
        override fun putLong(key: String, value: Long) = this
        override fun putFloat(key: String, value: Float) = this
        override fun putBoolean(key: String, value: Boolean) = apply { preferences.booleans[key] = value }
        override fun remove(key: String) = apply {
            preferences.strings.remove(key)
            preferences.ints.remove(key)
            preferences.booleans.remove(key)
        }

        override fun clear() = apply {
            preferences.strings.clear()
            preferences.ints.clear()
            preferences.booleans.clear()
        }

        override fun commit(): Boolean = true
        override fun apply() = Unit
    }
}
