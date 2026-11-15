package com.cybersecurityrahbar.clipvault.service

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService
import android.widget.Toast
import com.cybersecurityrahbar.clipvault.R
import com.cybersecurityrahbar.clipvault.data.ClipStore
import com.cybersecurityrahbar.clipvault.ui.MainActivity
import com.cybersecurityrahbar.clipvault.util.ClipboardUtil

class SaveTileService : TileService() {

    override fun onClick() {
        super.onClick()
        val text = ClipboardUtil.readText(this)
        val saved = text != null && text.isNotBlank() && ClipStore.save(this, text, "tile")
        if (saved) {
            Toast.makeText(this, getString(R.string.tile_saved), Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, getString(R.string.tile_blocked), Toast.LENGTH_LONG).show()
            openApp()
        }
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
