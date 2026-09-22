package com.sonnguyenhoang.game2048.cloud

import android.content.SharedPreferences

/**
 * The device-local half of the cloud layer: two tokens and one dismissal.
 *
 * `SharedPreferences` is private to the app, which is the same protection the
 * saved round already relies on. Deliberately *not* EncryptedSharedPreferences:
 * that would add the androidx.security dependency and a keystore round trip to
 * protect a token whose worst case is an attacker who already has the device
 * unlocked seeing someone's 2048 scores.
 */
class SharedPreferencesCloudStore(private val preferences: SharedPreferences) : TokenStore, CloudPreferences {

    override fun read(): CloudTokens? {
        val access = preferences.getString(KEY_ACCESS, null) ?: return null
        val refresh = preferences.getString(KEY_REFRESH, null) ?: return null
        if (access.isEmpty() || refresh.isEmpty()) return null
        return CloudTokens(access, refresh)
    }

    override fun write(tokens: CloudTokens?) {
        val editor = preferences.edit()
        if (tokens == null) {
            editor.remove(KEY_ACCESS).remove(KEY_REFRESH)
        } else {
            editor.putString(KEY_ACCESS, tokens.accessToken).putString(KEY_REFRESH, tokens.refreshToken)
        }
        editor.apply()
    }

    override var promptDismissed: Boolean
        get() = preferences.getBoolean(KEY_PROMPT, false)
        set(value) {
            preferences.edit().putBoolean(KEY_PROMPT, value).apply()
        }

    override var knownRevision: Int?
        get() {
            if (!preferences.contains(KEY_REVISION)) return null
            val value = preferences.getInt(KEY_REVISION, 0)
            return if (value > 0) value else null
        }
        set(value) {
            val editor = preferences.edit()
            if (value != null && value > 0) editor.putInt(KEY_REVISION, value) else editor.remove(KEY_REVISION)
            editor.apply()
        }

    override val hasTokens: Boolean get() = read() != null

    private companion object {
        const val KEY_ACCESS = "cloud_access_token_v1"
        const val KEY_REFRESH = "cloud_refresh_token_v1"
        const val KEY_PROMPT = "cloud_prompt_dismissed_v1"
        const val KEY_REVISION = "cloud_known_revision_v1"
    }
}
