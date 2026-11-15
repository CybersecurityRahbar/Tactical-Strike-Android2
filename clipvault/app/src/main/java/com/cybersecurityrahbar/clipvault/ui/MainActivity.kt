package com.cybersecurityrahbar.clipvault.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.Editable
import android.text.TextWatcher
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.cybersecurityrahbar.clipvault.R
import com.cybersecurityrahbar.clipvault.data.Clip
import com.cybersecurityrahbar.clipvault.data.ClipStore
import com.cybersecurityrahbar.clipvault.data.Prefs
import com.cybersecurityrahbar.clipvault.service.ClipboardWatchService
import com.cybersecurityrahbar.clipvault.util.AccessibilityUtil
import com.cybersecurityrahbar.clipvault.util.ClipboardUtil
import com.cybersecurityrahbar.clipvault.util.TimeUtil
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.snackbar.Snackbar

class MainActivity : AppCompatActivity() {

    private lateinit var adapter: ClipAdapter
    private lateinit var recycler: RecyclerView
    private lateinit var emptyView: View
    private lateinit var setupCard: View
    private lateinit var searchInput: EditText
    private lateinit var statusText: TextView

    private val handler = Handler(Looper.getMainLooper())
    private var query = ""
    private var pendingSearch: Runnable? = null

    private val exportJsonLauncher =
        registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
            if (uri != null) exportJson(uri)
        }

    private val exportDbLauncher =
        registerForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
            if (uri != null) exportDatabase(uri)
        }

    private val importLauncher =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) importJson(uri)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)

        setupCard = findViewById(R.id.setup_card)
        searchInput = findViewById(R.id.search_input)
        statusText = findViewById(R.id.status_text)
        recycler = findViewById(R.id.clip_list)
        emptyView = findViewById(R.id.empty_view)

        recycler.layoutManager = LinearLayoutManager(this)
        adapter = ClipAdapter(
            onCopy = { copyClip(it) },
            onPin = { togglePin(it) },
            onShare = { shareClip(it) },
            onDelete = { deleteClip(it) }
        )
        recycler.adapter = adapter

        findViewById<View>(R.id.btn_setup_auto).setOnClickListener { onAutoCaptureClicked() }
        findViewById<View>(R.id.btn_setup_ime).setOnClickListener { onKeyboardSetupClicked() }

        searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                scheduleSearch(s?.toString().orEmpty())
            }
        })

        askForNotificationPermission()
    }

    override fun onResume() {
        super.onResume()
        ClipboardWatchService.start(this)
        val text = ClipboardUtil.readText(this)
        if (!text.isNullOrBlank()) ClipStore.save(this, text, "app")
        updateSetupCard()
        loadClips()
        updateStatus()
    }

    override fun onDestroy() {
        pendingSearch?.let { handler.removeCallbacks(it) }
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.menu_main, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean = when (item.itemId) {
        R.id.action_export -> {
            exportJsonLauncher.launch("clipvault-${TimeUtil.fileStamp()}.json")
            true
        }
        R.id.action_import -> {
            importLauncher.launch(arrayOf("application/json", "text/plain", "application/octet-stream"))
            true
        }
        R.id.action_export_db -> {
            exportDbLauncher.launch("clipvault-${TimeUtil.fileStamp()}.db")
            true
        }
        R.id.action_settings -> {
            startActivity(Intent(this, SettingsActivity::class.java))
            true
        }
        R.id.action_clear -> {
            confirmClear()
            true
        }
        R.id.action_about -> {
            showAbout()
            true
        }
        else -> super.onOptionsItemSelected(item)
    }

    private fun loadClips() {
        val clips = ClipStore.list(this, query.ifBlank { null })
        adapter.submit(clips)
        val empty = clips.isEmpty()
        emptyView.visibility = if (empty) View.VISIBLE else View.GONE
        recycler.visibility = if (empty) View.GONE else View.VISIBLE
    }

    private fun updateStatus() {
        val count = ClipStore.count(this)
        val prefs = Prefs(this)
        val headline = when {
            AccessibilityUtil.isCaptureServiceEnabled(this) -> getString(R.string.status_accessibility, count)
            ClipboardUtil.isDefaultIme(this) -> getString(R.string.status_keyboard, count)
            else -> getString(R.string.status_limited, count)
        }
        val last = if (prefs.lastCaptureAt > 0L) {
            TimeUtil.dateTime(prefs.lastCaptureAt)
        } else {
            getString(R.string.never)
        }
        val size = TimeUtil.humanSize(ClipStore.databaseSize(this))
        statusText.text = headline + "\n" + getString(R.string.last_capture, last) +
            "  •  " + getString(R.string.db_info, size)
    }

    private fun updateSetupCard() {
        val ready = AccessibilityUtil.isCaptureServiceEnabled(this) || ClipboardUtil.isDefaultIme(this)
        setupCard.visibility = if (ready) View.GONE else View.VISIBLE
    }

    private fun scheduleSearch(value: String) {
        query = value
        pendingSearch?.let { handler.removeCallbacks(it) }
        val runnable = Runnable { loadClips() }
        pendingSearch = runnable
        handler.postDelayed(runnable, 200L)
    }

    private fun onAutoCaptureClicked() {
        if (AccessibilityUtil.isCaptureServiceEnabled(this)) {
            toast(getString(R.string.status_accessibility, ClipStore.count(this)))
            return
        }
        toast(getString(R.string.accessibility_opened))
        AccessibilityUtil.openSettings(this)
    }

    private fun onKeyboardSetupClicked() {
        if (!ClipboardUtil.isImeEnabled(this)) {
            toast(getString(R.string.setup_enable_ime))
            try {
                startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
            } catch (_: Throwable) {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            }
        } else if (!ClipboardUtil.showImePicker(this)) {
            toast(getString(R.string.setup_pick_ime))
        }
    }

    private fun copyClip(clip: Clip) {
        ClipboardUtil.writeText(this, clip.text)
        toast(getString(R.string.copied))
    }

    private fun togglePin(clip: Clip) {
        ClipStore.setPinned(this, clip.id, !clip.pinned)
        loadClips()
    }

    private fun shareClip(clip: Clip) {
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, clip.text)
        startActivity(Intent.createChooser(intent, getString(R.string.share)))
    }

    private fun deleteClip(clip: Clip) {
        ClipStore.delete(this, clip.id)
        loadClips()
        updateStatus()
        Snackbar.make(findViewById(android.R.id.content), getString(R.string.deleted), Snackbar.LENGTH_LONG)
            .setAction(getString(R.string.undo)) {
                ClipStore.restore(this, clip)
                loadClips()
                updateStatus()
            }
            .show()
    }

    private fun exportJson(uri: Uri) {
        try {
            val count = contentResolver.openOutputStream(uri)?.use { ClipStore.exportJson(this, it) } ?: 0
            toast(getString(R.string.export_done, count))
        } catch (_: Throwable) {
            toast(getString(R.string.export_failed))
        }
    }

    private fun exportDatabase(uri: Uri) {
        try {
            contentResolver.openOutputStream(uri)?.use { ClipStore.exportDatabase(this, it) }
                ?: throw IllegalStateException("stream")
            toast(getString(R.string.export_db_done))
        } catch (_: Throwable) {
            toast(getString(R.string.export_failed))
        }
    }

    private fun importJson(uri: Uri) {
        try {
            val count = contentResolver.openInputStream(uri)?.use { ClipStore.importJson(this, it) } ?: 0
            loadClips()
            updateStatus()
            toast(getString(R.string.import_done, count))
        } catch (_: Throwable) {
            toast(getString(R.string.import_failed))
        }
    }

    private fun confirmClear() {
        AlertDialog.Builder(this)
            .setTitle(R.string.confirm_clear_title)
            .setMessage(R.string.confirm_clear_body)
            .setPositiveButton(R.string.confirm) { _, _ ->
                ClipStore.deleteAllUnpinned(this)
                loadClips()
                updateStatus()
            }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    private fun showAbout() {
        AlertDialog.Builder(this)
            .setTitle(R.string.about_title)
            .setMessage(R.string.about_body)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun askForNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATIONS
            )
        }
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    companion object {
        private const val REQUEST_NOTIFICATIONS = 42
    }
}
