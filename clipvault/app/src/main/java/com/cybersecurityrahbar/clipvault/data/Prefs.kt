package com.cybersecurityrahbar.clipvault.data

import android.content.Context

class Prefs(context: Context) {

    private val sp = context.applicationContext
        .getSharedPreferences("clipvault_prefs", Context.MODE_PRIVATE)

    var autoCapture: Boolean
        get() = sp.getBoolean("auto_capture", true)
        set(value) {
            sp.edit().putBoolean("auto_capture", value).apply()
        }

    var minLength: Int
        get() = sp.getInt("min_length", 1)
        set(value) {
            sp.edit().putInt("min_length", value).apply()
        }

    var lastCaptureAt: Long
        get() = sp.getLong("last_capture_at", 0L)
        set(value) {
            sp.edit().putLong("last_capture_at", value).apply()
        }

    var captureBlocked: Boolean
        get() = sp.getBoolean("capture_blocked", false)
        set(value) {
            sp.edit().putBoolean("capture_blocked", value).apply()
        }
}
