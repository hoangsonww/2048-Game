package com.sonnguyenhoang.game2048.cloud

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The device-local half of the cloud layer.
 *
 * A mistake here signs a player out on every launch or, worse, leaves a token
 * behind after they asked to be signed out. The fake implements
 * [SharedPreferences] directly rather than mocking it, so the test needs no
 * Android runtime — the same approach `SharedPreferencesGameStorageTest` uses.
 */
class CloudStorageTest {

    private fun store() = SharedPreferencesCloudStore(FakePreferences())

    @Test
    fun `a token pair is written and read back exactly`() {
        val store = store()
        store.write(CloudTokens("access-1", "refresh-1"))

        assertEquals(CloudTokens("access-1", "refresh-1"), store.read())
        assertTrue(store.hasTokens)
    }

    @Test
    fun `nothing stored means no session`() {
        val store = store()
        assertNull(store.read())
        assertFalse(store.hasTokens)
    }

    @Test
    fun `signing out removes both halves of the pair`() {
        val store = store()
        store.write(CloudTokens("access-1", "refresh-1"))

        store.write(null)

        assertNull(store.read())
        assertFalse(store.hasTokens)
    }

    @Test
    fun `a half-written entry is treated as no session at all`() {
        // An access token with no refresh alongside it cannot be renewed, so
        // reporting it as a session would strand the player on a token that
        // expires and never recovers.
        val preferences = FakePreferences()
        preferences.strings["cloud_access_token_v1"] = "access-only"
        val store = SharedPreferencesCloudStore(preferences)

        assertNull(store.read())
    }

    @Test
    fun `an empty token string is not a session`() {
        val preferences = FakePreferences()
        preferences.strings["cloud_access_token_v1"] = ""
        preferences.strings["cloud_refresh_token_v1"] = ""

        assertNull(SharedPreferencesCloudStore(preferences).read())
    }

    @Test
    fun `the dismissal survives a relaunch`() {
        val preferences = FakePreferences()
        SharedPreferencesCloudStore(preferences).promptDismissed = true

        assertTrue(SharedPreferencesCloudStore(preferences).promptDismissed)
    }

    @Test
    fun `the prompt starts undismissed`() {
        assertFalse(store().promptDismissed)
    }

    @Test
    fun `a known revision is remembered across relaunches`() {
        val preferences = FakePreferences()
        SharedPreferencesCloudStore(preferences).knownRevision = 7

        assertEquals(7, SharedPreferencesCloudStore(preferences).knownRevision)
    }

    @Test
    fun `clearing the known revision removes it`() {
        val store = store()
        store.knownRevision = 3
        store.knownRevision = null

        assertNull(store.knownRevision)
    }

    private class FakePreferences : SharedPreferences {
        val strings = mutableMapOf<String, String?>()
        val booleans = mutableMapOf<String, Boolean>()
        val ints = mutableMapOf<String, Int>()

        override fun getAll(): MutableMap<String, *> = (strings + booleans + ints).toMutableMap()
        override fun getString(key: String, defValue: String?): String? = strings[key] ?: defValue
        override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String, defValue: Int): Int = ints[key] ?: defValue
        override fun getLong(key: String, defValue: Long): Long = defValue
        override fun getFloat(key: String, defValue: Float): Float = defValue
        override fun getBoolean(key: String, defValue: Boolean): Boolean = booleans[key] ?: defValue
        override fun contains(key: String): Boolean = strings.containsKey(key) || booleans.containsKey(key) || ints.containsKey(key)
        override fun edit(): SharedPreferences.Editor = FakeEditor(this)
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) = Unit
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) = Unit
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
            preferences.booleans.remove(key)
            preferences.ints.remove(key)
        }

        override fun clear() = apply {
            preferences.strings.clear()
            preferences.booleans.clear()
            preferences.ints.clear()
        }

        override fun commit(): Boolean = true
        override fun apply() = Unit
    }
}
