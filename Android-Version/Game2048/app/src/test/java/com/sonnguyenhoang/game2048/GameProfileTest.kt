package com.sonnguyenhoang.game2048

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guest and account profiles.
 *
 * The property under test is separation: two rounds live on one device and
 * neither can reach the other. Signing in must not hand a guest board to an
 * account, and signing out must return the guest board untouched.
 */
class GameProfileTest {
    private val zeros = listOf(0, 0, 0, 0)

    private class Slots {
        val preferences = FakeSharedPreferences()
        val guest = SharedPreferencesGameStorage(preferences)
        val account = SharedPreferencesGameStorage(preferences, SharedPreferencesGameStorage.ACCOUNT_PREFIX)
    }

    private fun game(slots: Slots) = GameViewModel(
        storage = slots.guest,
        accountStorage = slots.account,
        randomIndex = { 0 },
        randomUnit = { 0.0 }
    )

    /** Plays until the round has a score worth protecting. */
    private fun playUntilScored(game: GameViewModel): SavedGame {
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), listOf(4, 4, 0, 0), zeros, zeros))
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))
        assertTrue(game.score > 0)
        return SavedGame(game.grid, game.score, game.highScore, game.hasWon, game.moves)
    }

    @Test
    fun `a round starts on the guest profile`() {
        val game = game(Slots())
        assertEquals(GameViewModel.Profile.GUEST, game.profile)
        assertFalse(game.hasProgress)
    }

    @Test
    fun `progress is anything a player would mind losing`() {
        val game = game(Slots())
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros))
        assertFalse(game.hasProgress)
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))
        assertTrue(game.hasProgress)
    }

    @Test
    fun `starting an account session parks the guest round untouched`() {
        val slots = Slots()
        val game = game(slots)
        val guest = playUntilScored(game)

        assertEquals(GameViewModel.SessionStart.FRESH, game.beginAccountSession(fresh = true))

        assertEquals(GameViewModel.Profile.ACCOUNT, game.profile)
        assertEquals("the account starts on a clean board", 0, game.score)
        assertEquals("and with no best score borrowed from the device", 0, game.highScore)
        assertEquals(guest, slots.guest.load())
    }

    @Test
    fun `playing signed in never writes to the guest profile`() {
        val slots = Slots()
        val game = game(slots)
        val guest = playUntilScored(game)

        game.beginAccountSession(fresh = true)
        game.setGameForTesting(listOf(listOf(8, 8, 0, 0), listOf(16, 16, 0, 0), zeros, zeros))
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))

        assertEquals(guest, slots.guest.load())
        assertEquals(guest.best, slots.guest.loadBest())
        assertNotNull(slots.account.load())
        assertEquals(game.highScore, slots.account.loadBest())
    }

    @Test
    fun `ending an account session restores the guest round exactly`() {
        val slots = Slots()
        val game = game(slots)
        val guest = playUntilScored(game)

        game.beginAccountSession(fresh = true)
        game.setGameForTesting(listOf(listOf(8, 8, 0, 0), zeros, zeros, zeros))
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))
        assertNotEquals(guest.grid, game.grid)

        assertTrue(game.endAccountSession())

        assertEquals(GameViewModel.Profile.GUEST, game.profile)
        assertEquals(guest.grid, game.grid)
        assertEquals(guest.score, game.score)
        assertEquals(guest.best, game.highScore)
        assertEquals(guest.moves, game.moves)
        assertNull("the cached account round does not outlive the session", slots.account.load())
    }

    @Test
    fun `a session started twice is reported as already active`() {
        val game = game(Slots())
        assertEquals(GameViewModel.SessionStart.FRESH, game.beginAccountSession(fresh = true))
        assertEquals(GameViewModel.SessionStart.ACTIVE, game.beginAccountSession())
        assertEquals(GameViewModel.Profile.ACCOUNT, game.profile)
    }

    @Test
    fun `ending a session that never started changes nothing`() {
        val game = game(Slots())
        val before = game.grid
        assertFalse(game.endAccountSession())
        assertEquals(before, game.grid)
        assertEquals(GameViewModel.Profile.GUEST, game.profile)
    }

    @Test
    fun `a cached account round is restored rather than replaced`() {
        val slots = Slots()
        slots.account.save(SavedGame(List(4) { List(4) { 0 } }.let {
            listOf(listOf(512, 256, 0, 0), zeros, zeros, zeros)
        }, score = 4000, best = 6000, hasWon = false, moves = 77))
        val game = game(slots)

        assertEquals(GameViewModel.SessionStart.RESTORED, game.beginAccountSession())

        assertEquals(4000, game.score)
        assertEquals(6000, game.highScore)
        assertEquals(77, game.moves)
    }

    @Test
    fun `a fresh sign-in discards whatever was cached for an account`() {
        val slots = Slots()
        slots.account.save(SavedGame(listOf(listOf(512, 256, 0, 0), zeros, zeros, zeros), 4000, 6000, false, 77))
        val game = game(slots)

        assertEquals(GameViewModel.SessionStart.FRESH, game.beginAccountSession(fresh = true))

        assertEquals("the previous occupant's board is not this account's", 0, game.score)
    }

    @Test
    fun `a profile switch is announced separately from a new game`() {
        val game = game(Slots())
        val changes = mutableListOf<GameViewModel.RoundChange>()
        game.onRoundChanged = { changes += it }

        game.beginAccountSession(fresh = true)
        game.endAccountSession()

        assertEquals(
            listOf(GameViewModel.RoundChange.PROFILE_CHANGED, GameViewModel.RoundChange.PROFILE_CHANGED),
            changes
        )
    }

    @Test
    fun `a best score earned signed in stays with the account`() {
        val slots = Slots()
        val game = game(slots)
        playUntilScored(game)
        val guestBest = game.highScore

        game.beginAccountSession(fresh = true)
        game.setGameForTesting(listOf(listOf(512, 512, 0, 0), zeros, zeros, zeros))
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))
        assertTrue(game.highScore > guestBest)

        game.endAccountSession()
        assertEquals("a signed-in score is not the device's own best", guestBest, game.highScore)
    }

    @Test
    fun `a view model with no account slot still switches without losing the guest round`() {
        // The Compose preview and the UI tests build a view model with no
        // storage at all; a profile switch must degrade, not crash.
        val game = GameViewModel(randomIndex = { 0 }, randomUnit = { 0.0 })
        game.setGameForTesting(listOf(listOf(2, 2, 0, 0), zeros, zeros, zeros))
        assertTrue(game.swipe(GameViewModel.Direction.LEFT))

        assertEquals(GameViewModel.SessionStart.FRESH, game.beginAccountSession(fresh = true))
        assertEquals(0, game.score)
        assertTrue(game.endAccountSession())
        assertEquals(GameViewModel.Profile.GUEST, game.profile)
    }

    @Test
    fun `the account's career best seeds the signed-in best card`() {
        val slots = Slots()
        val game = game(slots)
        playUntilScored(game)
        val guestBest = game.highScore

        game.beginAccountSession(fresh = true)
        assertEquals("an account starts with nothing borrowed from the device", 0, game.highScore)

        assertTrue(game.adoptCareerBest(9100))
        assertEquals(9100, game.highScore)
        assertEquals(9100, slots.account.loadBest())

        // Never downwards.
        assertFalse(game.adoptCareerBest(40))
        assertEquals(9100, game.highScore)

        game.endAccountSession()
        assertEquals("and none of it reaches the device's own best", guestBest, game.highScore)
    }

    @Test
    fun `a career best is refused while playing as a guest`() {
        val game = game(Slots())
        assertFalse(game.adoptCareerBest(9100))
        assertEquals(0, game.highScore)
    }
}
