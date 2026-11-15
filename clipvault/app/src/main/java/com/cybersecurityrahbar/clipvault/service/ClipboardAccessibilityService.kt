package com.cybersecurityrahbar.clipvault.service

import android.accessibilityservice.AccessibilityService
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.cybersecurityrahbar.clipvault.data.ClipStore
import com.cybersecurityrahbar.clipvault.util.ClipboardUtil

/**
 * Automatic capture without changing the keyboard.
 *
 * Android only lets the focused app (or the default IME) read the clipboard, so this service
 * asks the window manager for input focus for a few milliseconds using a 1x1 transparent
 * accessibility overlay, reads the clipboard, and removes the overlay again. The focus grab is
 * skipped entirely while a text field has input focus, so typing is never interrupted; it only
 * happens after the user pressed something that looks like a Copy action, or on a slow poll
 * while no editor is focused.
 *
 * The service never stores or transmits on-screen content: node text is only compared against
 * copy-button keywords, and the whole app has no INTERNET permission.
 */
class ClipboardAccessibilityService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlay: View? = null
    private var running = false
    private var lastAttemptAt = 0L

    private val poller = object : Runnable {
        override fun run() {
            if (!running) return
            requestRead(allowWhileTyping = false)
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    private val readRunnable = Runnable { readWithFocus(allowWhileTyping = false) }

    override fun onServiceConnected() {
        super.onServiceConnected()
        windowManager = getSystemService(WINDOW_SERVICE) as? WindowManager
        running = true
        handler.postDelayed(poller, POLL_INTERVAL_MS)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_VIEW_CLICKED) return
        if (!looksLikeCopyAction(event)) return
        requestRead(allowWhileTyping = true, delayMs = COPY_SETTLE_MS)
    }

    override fun onInterrupt() {
        removeOverlay()
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        running = false
        handler.removeCallbacksAndMessages(null)
        removeOverlay()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        removeOverlay()
        super.onDestroy()
    }

    private fun requestRead(allowWhileTyping: Boolean, delayMs: Long = 0L) {
        val now = SystemClock.uptimeMillis()
        if (now - lastAttemptAt < MIN_INTERVAL_MS) return
        lastAttemptAt = now
        handler.removeCallbacks(readRunnable)
        handler.postDelayed({ readWithFocus(allowWhileTyping) }, delayMs)
    }

    private fun readWithFocus(allowWhileTyping: Boolean) {
        if (!running || overlay != null) return
        if (!isInteractive()) return

        if (ClipboardUtil.isDefaultIme(this)) {
            capture()
            return
        }
        if (!allowWhileTyping && isTextInputFocused()) return

        val manager = windowManager ?: return
        val view = View(this)
        val params = WindowManager.LayoutParams(
            1,
            1,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSPARENT
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = 0
        params.y = 0
        params.setTitle("ClipVault clipboard probe")

        try {
            manager.addView(view, params)
            overlay = view
        } catch (_: Throwable) {
            overlay = null
            return
        }

        handler.postDelayed({
            capture()
            removeOverlay()
        }, FOCUS_SETTLE_MS)
    }

    private fun capture() {
        val text = ClipboardUtil.readText(this)
        if (!text.isNullOrBlank()) ClipStore.save(this, text, "accessibility")
    }

    private fun removeOverlay() {
        val view = overlay ?: return
        overlay = null
        try {
            windowManager?.removeViewImmediate(view)
        } catch (_: Throwable) {
        }
    }

    private fun isInteractive(): Boolean {
        val power = getSystemService(POWER_SERVICE) as? PowerManager ?: return true
        return power.isInteractive
    }

    private fun isTextInputFocused(): Boolean {
        val root: AccessibilityNodeInfo = rootInActiveWindow ?: return false
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        return focused.isEditable || focused.className?.toString()?.contains("EditText") == true
    }

    private fun looksLikeCopyAction(event: AccessibilityEvent): Boolean {
        val haystack = StringBuilder()
        for (piece in event.text) haystack.append(piece).append(' ')
        event.contentDescription?.let { haystack.append(it).append(' ') }
        val source = event.source
        if (source != null) {
            source.viewIdResourceName?.let { haystack.append(it).append(' ') }
            source.contentDescription?.let { haystack.append(it).append(' ') }
        }
        val value = haystack.toString().lowercase()
        if (value.isBlank()) return false
        return COPY_MARKERS.any { value.contains(it) }
    }

    companion object {
        private const val POLL_INTERVAL_MS = 2000L
        private const val MIN_INTERVAL_MS = 900L
        private const val FOCUS_SETTLE_MS = 120L
        private const val COPY_SETTLE_MS = 260L

        private val COPY_MARKERS = listOf(
            "copy",
            "نسخ",
            "clipboard",
            "الحافظة",
            "kopieren",
            "copiar",
            "copier"
        )
    }
}
