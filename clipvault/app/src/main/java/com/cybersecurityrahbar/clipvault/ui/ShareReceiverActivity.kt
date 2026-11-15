package com.cybersecurityrahbar.clipvault.ui

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.cybersecurityrahbar.clipvault.R
import com.cybersecurityrahbar.clipvault.data.ClipStore

class ShareReceiverActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == Intent.ACTION_SEND) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
            val saved = ClipStore.save(this, text, "share")
            Toast.makeText(
                this,
                if (saved) getString(R.string.saved_one) else getString(R.string.error_generic),
                Toast.LENGTH_SHORT
            ).show()
        }
        finish()
    }
}
