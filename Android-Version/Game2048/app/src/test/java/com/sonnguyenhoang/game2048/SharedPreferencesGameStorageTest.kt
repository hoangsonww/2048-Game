package com.sonnguyenhoang.game2048

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
 * [FakeSharedPreferences] implements the platform interface directly rather
 * than mocking it, so the test needs no Android runtime.
 */
class SharedPreferencesGameStorageTest {
    @Test
    fun aSavedRoundIsReadBackExactly() {
        val preferences = FakeSharedPreferences()
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
        val storage = SharedPreferencesGameStorage(FakeSharedPreferences())
        assertNull(storage.load())
        assertEquals(0, storage.loadBest())
    }

    @Test
    fun theBestScoreIsReadableWithoutASavedRound() {
        val preferences = FakeSharedPreferences()
        val storage = SharedPreferencesGameStorage(preferences)
        storage.save(SavedGame(grid = fullGrid(), score = 10, best = 999, hasWon = false))

        assertEquals(999, storage.loadBest())
    }

    @Test
    fun aGridOfTheWrongLengthIsRejected() {
        val preferences = FakeSharedPreferences()
        // Fifteen cells: a truncated write, or a save from an older layout.
        preferences.strings["saved_grid_v2"] = List(15) { "0" }.joinToString(",")

        assertNull(SharedPreferencesGameStorage(preferences).load())
    }

    @Test
    fun aGridWithUnparseableCellsIsRejectedRatherThanSilentlyShrunk() {
        val preferences = FakeSharedPreferences()
        // Non-numeric cells are dropped while parsing, which leaves fewer than
        // sixteen values — the length check is what turns that into a rejection
        // instead of a short, misaligned board.
        preferences.strings["saved_grid_v2"] = (List(14) { "2" } + listOf("x", "")).joinToString(",")

        assertNull(SharedPreferencesGameStorage(preferences).load())
    }

    @Test
    fun anEmptyGridStringIsRejected() {
        val preferences = FakeSharedPreferences()
        preferences.strings["saved_grid_v2"] = ""

        assertNull(SharedPreferencesGameStorage(preferences).load())
    }

    @Test
    fun aGridIsRestoredAsFourRowsOfFour() {
        val preferences = FakeSharedPreferences()
        preferences.strings["saved_grid_v2"] = (1..16).joinToString(",")

        val loaded = requireNotNull(SharedPreferencesGameStorage(preferences).load())
        assertEquals(4, loaded.grid.size)
        assertTrue(loaded.grid.all { it.size == 4 })
        assertEquals(listOf(1, 2, 3, 4), loaded.grid[0])
        assertEquals(listOf(13, 14, 15, 16), loaded.grid[3])
    }

    @Test
    fun savingTwiceKeepsOnlyTheLatestRound() {
        val storage = SharedPreferencesGameStorage(FakeSharedPreferences())
        storage.save(SavedGame(grid = fullGrid(2), score = 1, best = 1, hasWon = false))
        storage.save(SavedGame(grid = fullGrid(4), score = 2, best = 2, hasWon = true))

        val loaded = requireNotNull(storage.load())
        assertEquals(fullGrid(4), loaded.grid)
        assertEquals(2, loaded.score)
        assertTrue(loaded.hasWon)
    }

    @Test
    fun scoresAndWinStateFallBackToZeroWhenOnlyAGridWasStored() {
        val preferences = FakeSharedPreferences()
        preferences.strings["saved_grid_v2"] = List(16) { "0" }.joinToString(",")

        val loaded = requireNotNull(SharedPreferencesGameStorage(preferences).load())
        assertEquals(0, loaded.score)
        assertEquals(0, loaded.best)
        assertFalse(loaded.hasWon)
    }

    @Test
    fun twoPrefixedSlotsCannotSeeEachOther() {
        // This is the whole mechanism behind "signing out restores exactly
        // what you were playing": the guest and signed-in rounds share a
        // preferences file and nothing else.
        val preferences = FakeSharedPreferences()
        val guest = SharedPreferencesGameStorage(preferences)
        val account = SharedPreferencesGameStorage(preferences, SharedPreferencesGameStorage.ACCOUNT_PREFIX)

        guest.save(SavedGame(grid = fullGrid(2), score = 10, best = 100, hasWon = false, moves = 3))
        account.save(SavedGame(grid = fullGrid(8), score = 900, best = 900, hasWon = true, moves = 40))

        assertEquals(10, requireNotNull(guest.load()).score)
        assertEquals(100, guest.loadBest())
        assertEquals(900, requireNotNull(account.load()).score)
        assertEquals(900, account.loadBest())
    }

    @Test
    fun clearingOneSlotLeavesTheOtherIntact() {
        val preferences = FakeSharedPreferences()
        val guest = SharedPreferencesGameStorage(preferences)
        val account = SharedPreferencesGameStorage(preferences, SharedPreferencesGameStorage.ACCOUNT_PREFIX)
        guest.save(SavedGame(grid = fullGrid(2), score = 10, best = 100, hasWon = false, moves = 3))
        account.save(SavedGame(grid = fullGrid(8), score = 900, best = 900, hasWon = true, moves = 40))

        account.clear()

        assertNull(account.load())
        assertEquals(0, account.loadBest())
        assertEquals(10, requireNotNull(guest.load()).score)
        assertEquals(100, guest.loadBest())
    }

    private fun fullGrid(value: Int = 2) = List(4) { List(4) { value } }
}
