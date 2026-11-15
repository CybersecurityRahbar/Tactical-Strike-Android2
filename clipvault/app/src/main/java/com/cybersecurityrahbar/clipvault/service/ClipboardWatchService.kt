package com.cybersecurityrahbar.clipvault.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.cybersecurityrahbar.clipvault.R
import com.cybersecurityrahbar.clipvault.data.ClipStore
import com.cybersecurityrahbar.clipvault.data.Prefs
import com.cybersecurityrahbar.clipvault.ui.MainActivity
import com.cybersecurityrahbar.clipvault.util.AccessibilityUtil
import com.cybersecurityrahbar.clipvault.util.ClipboardUtil

/**
 * Permanent background capture.
 *
 * Android 10+ only lets the focused app or the default IME read the clipboard, so this
 * service works fully once ClipVault is the default keyboard; ClipVault's package then
 * always has clipboard access and the poll below returns the real content. When the app is
 * not the default keyboard the same service still runs and captures whenever ClipVault is
 * on screen, without ever showing a UI.
 */
class ClipboardWatchService : Service() {

    private lateinit var handler: Handler
    private var thread: HandlerThread? = null
    private var running = false
    private var screenOn = true
    private var lastHash: String? = null
    private var blockedStreak = 0
    private var lastNotificationAt = 0L
    private var lastCount = -1

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    screenOn = true
                    wakeUp()
                }
                Intent.ACTION_SCREEN_OFF -> screenOn = false
            }
        }
    }

    private val poller = object : Runnable {
        override fun run() {
            if (!running) return
            try {
                tick()
            } catch (_: Throwable) {
                // Never let one bad read kill the permanent capture loop.
            }
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val worker = HandlerThread("clipvault-watch")
        worker.start()
        thread = worker
        handler = Handler(worker.looper)
        screenOn = true
        ContextCompat.registerReceiver(
            this,
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        if (!running) {
            // Whatever sits in the clipboard before the watcher starts was not copied now;
            // remember it instead of giving it a false timestamp.
            primeLastHash()
            running = true
            handler.post(poller)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Throwable) {
        }
        thread?.quitSafely()
        thread = null
        super.onDestroy()
    }

    private fun tick() {
        val prefs = Prefs(this)
        if (!prefs.autoCapture) {
            stopSelf()
            return
        }
        if (!screenOn) return

        val text = ClipboardUtil.readText(this)
        if (text.isNullOrBlank()) {
            blockedStreak++
            if (blockedStreak == 6) {
                val blocked = !ClipboardUtil.isDefaultIme(this) && !AccessibilityUtil.isCaptureServiceEnabled(this)
                if (prefs.captureBlocked != blocked) {
                    prefs.captureBlocked = blocked
                    refreshNotification(true)
                }
            }
            return
        }

        blockedStreak = 0
        val currentHash = ClipStore.hash(text)
        if (currentHash == lastHash) return
        lastHash = currentHash

        if (ClipStore.save(this, text, "watch")) {
            if (prefs.captureBlocked) prefs.captureBlocked = false
            refreshNotification(true)
        }
    }

    private fun primeLastHash() {
        val text = ClipboardUtil.readText(this)
        lastHash = if (text.isNullOrBlank()) null else ClipStore.hash(text)
    }

    private fun wakeUp() {
        if (!running) return
        handler.removeCallbacks(poller)
        handler.postDelayed(poller, 250L)
    }

    private fun startAsForeground() {
        createChannel(this)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(ClipStore.count(this)), type)
            lastNotificationAt = System.currentTimeMillis()
        } catch (_: Throwable) {
            // If the OS refuses the foreground start we simply retry on the next trigger.
        }
    }

    private fun buildNotification(count: Int): Notification {
        val body = if (ClipboardUtil.isDefaultIme(this) || AccessibilityUtil.isCaptureServiceEnabled(this)) {
            getString(R.string.notif_auto, count)
        } else {
            getString(R.string.notif_blocked)
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.notif_title))
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun refreshNotification(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!force && now - lastNotificationAt < 4000L) return
        val count = ClipStore.count(this)
        if (!force && count == lastCount) return
        lastCount = count
        lastNotificationAt = now
        try {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, buildNotification(count))
        } catch (_: Throwable) {
        }
    }

    companion object {
        private const val CHANNEL_ID = "clipvault_capture"
        private const val NOTIFICATION_ID = 1001
        private const val POLL_INTERVAL_MS = 1200L

        fun createChannel(context: Context) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.notif_channel),
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description = context.getString(R.string.notif_channel_desc)
                channel.setShowBadge(false)
                manager.createNotificationChannel(channel)
            }
        }

        fun start(context: Context) {
            if (!Prefs(context).autoCapture) return
            try {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, ClipboardWatchService::class.java)
                )
            } catch (_: Throwable) {
                // Background start restrictions (Android 12+) can refuse this; capture still
                // resumes when the app or the keyboard is next opened.
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, ClipboardWatchService::class.java))
            } catch (_: Throwable) {
            }
        }
    }
}
