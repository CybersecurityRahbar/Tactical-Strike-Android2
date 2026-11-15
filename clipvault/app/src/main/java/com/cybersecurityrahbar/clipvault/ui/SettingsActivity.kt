package com.cybersecurityrahbar.clipvault.ui

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.cybersecurityrahbar.clipvault.R
import com.cybersecurityrahbar.clipvault.data.Prefs
import com.cybersecurityrahbar.clipvault.service.ClipboardWatchService
import com.cybersecurityrahbar.clipvault.util.AccessibilityUtil
import com.cybersecurityrahbar.clipvault.util.ClipboardUtil
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.materialswitch.MaterialSwitch

class SettingsActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        val prefs = Prefs(this)

        val autoSwitch = findViewById<MaterialSwitch>(R.id.sw_auto)
        autoSwitch.isChecked = prefs.autoCapture
        autoSwitch.setOnCheckedChangeListener { _, checked ->
            prefs.autoCapture = checked
            if (checked) {
                ClipboardWatchService.start(this)
            } else {
                ClipboardWatchService.stop(this)
            }
        }

        val shortSwitch = findViewById<MaterialSwitch>(R.id.sw_short)
        shortSwitch.isChecked = prefs.minLength >= 3
        shortSwitch.setOnCheckedChangeListener { _, checked ->
            prefs.minLength = if (checked) 3 else 1
        }

        findViewById<android.view.View>(R.id.btn_ime_settings).setOnClickListener {
            try {
                startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
            } catch (_: Throwable) {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            }
        }

        findViewById<android.view.View>(R.id.btn_pick_ime).setOnClickListener {
            ClipboardUtil.showImePicker(this)
        }

        findViewById<android.view.View>(R.id.btn_accessibility).setOnClickListener {
            AccessibilityUtil.openSettings(this)
        }

        findViewById<TextView>(R.id.how_body).text = getString(R.string.settings_how_body)
    }

    override fun onResume() {
        super.onResume()
        val enabled = AccessibilityUtil.isCaptureServiceEnabled(this)
        findViewById<TextView>(R.id.accessibility_state).text = getString(
            if (enabled) R.string.settings_accessibility_on else R.string.settings_accessibility_off
        )
    }
}
