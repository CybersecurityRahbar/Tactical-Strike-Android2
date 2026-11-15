package com.cybersecurityrahbar.clipvault.data

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class ClipDb private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, NAME, null, VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE clips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                text TEXT NOT NULL,
                hash TEXT NOT NULL,
                copied_at INTEGER NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                source TEXT NOT NULL DEFAULT 'clipboard'
            )
            """.trimIndent()
        )
        db.execSQL("CREATE UNIQUE INDEX idx_clips_hash ON clips(hash)")
        db.execSQL("CREATE INDEX idx_clips_copied ON clips(copied_at DESC)")
        db.execSQL("CREATE INDEX idx_clips_pinned ON clips(pinned, copied_at DESC)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Version 1 is the first schema. History is never dropped on upgrade.
    }

    companion object {
        const val NAME = "clipvault.db"
        const val VERSION = 1

        @Volatile
        private var instance: ClipDb? = null

        fun get(context: Context): ClipDb =
            instance ?: synchronized(this) {
                instance ?: ClipDb(context).also { instance = it }
            }
    }
}
