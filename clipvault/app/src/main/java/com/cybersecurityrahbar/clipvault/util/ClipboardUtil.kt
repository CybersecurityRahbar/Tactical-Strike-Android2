package com.cybersecurityrahbar.clipvault.util

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.provider.Settings
import android.view.inputmethod.InputMethodManager

object ClipboardUtil {

    /**
     * Reads the current clipboard text. Returns null when the clipboard is empty or when
     * Android denies the read (the caller is neither focused nor the default IME).
     */
    fun readText(context: Context): String? {
        val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return null
        return try {
            if (!manager.hasPrimaryClip()) {
                null
            } else {
                val clip = manager.primaryClip
                if (clip == null || clip.itemCount == 0) {
                    null
                } else {
                    clip.getItemAt(0).coerceToText(context)?.toString()
                }
            }
        } catch (t: Throwable) {
            null
        }
    }

    fun writeText(context: Context, text: String) {
        val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        try {
            manager.setPrimaryClip(ClipData.newPlainText("ClipVault", text))
        } catch (_: Throwable) {
            // Ignored: reading apps can still paste from their own state.
        }
    }

    /** True when ClipVault is the keyboard Android allows to read the clipboard in background. */
    fun isDefaultIme(context: Context): Boolean {
        val id = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.DEFAULT_INPUT_METHOD
        ) ?: return false
        return id.startsWith(context.packageName)
    }

    fun isImeEnabled(context: Context): Boolean {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return false
        return imm.enabledInputMethodList.any { it.packageName == context.packageName }
    }

    fun showImePicker(context: Context): Boolean {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return false
        return try {
            imm.showInputMethodPicker()
            true
        } catch (t: Throwable) {
            false
        }
    }
}
