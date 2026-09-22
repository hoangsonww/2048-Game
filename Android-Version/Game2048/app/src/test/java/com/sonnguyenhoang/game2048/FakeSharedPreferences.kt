package com.sonnguyenhoang.game2048

import android.content.SharedPreferences

/**
 * A minimal in-memory [SharedPreferences], shared by the storage and profile
 * tests.
 *
 * Implemented directly rather than mocked so the whole persistence layer —
 * including the key prefixes that keep the guest and signed-in rounds apart —
 * is provable without an Android runtime. Only the accessors the app actually
 * calls carry behaviour; the rest satisfy the interface.
 */
class FakeSharedPreferences : SharedPreferences {
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

    override fun edit(): SharedPreferences.Editor = Editor(this)
    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener
    ) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener
    ) = Unit

    /** Writes straight through, so `apply()` is observable immediately. */
    private class Editor(private val preferences: FakeSharedPreferences) : SharedPreferences.Editor {
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
