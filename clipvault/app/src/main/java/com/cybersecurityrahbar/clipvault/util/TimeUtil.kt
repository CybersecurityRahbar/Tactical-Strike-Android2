package com.cybersecurityrahbar.clipvault.util

import android.text.format.DateUtils
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

object TimeUtil {

    /** "الأحد، 14 نوفمبر 2026 • 20:42:10" — day name, date and time with seconds. */
    fun dateTime(millis: Long): String {
        val zoned = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault())
        val locale = Locale.getDefault()
        val date = zoned.format(DateTimeFormatter.ofPattern("EEEE، d MMMM yyyy", locale))
        val time = zoned.format(DateTimeFormatter.ofPattern("HH:mm:ss", locale))
        return "$date • $time"
    }

    fun relative(millis: Long): CharSequence =
        DateUtils.getRelativeTimeSpanString(millis, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS)

    fun fileStamp(): String =
        Instant.now().atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("yyyy-MM-dd-HHmm", Locale.US))

    fun humanSize(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val units = arrayOf("KB", "MB", "GB")
        var value = bytes / 1024.0
        var unit = 0
        while (value >= 1024 && unit < units.size - 1) {
            value /= 1024
            unit++
        }
        return String.format(Locale.US, "%.1f %s", value, units[unit])
    }
}
