package com.cybersecurityrahbar.clipvault.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/**
 * The whole vault lives in one local SQLite table. Nothing is ever pruned: there is no
 * maximum entry count, so old clips are never silently discarded.
 */
object ClipStore {

    private const val MAX_TEXT = 2_000_000
    private val lock = Any()

    fun hash(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
        val out = StringBuilder(digest.size * 2)
        for (b in digest) out.append(String.format("%02x", b))
        return out.toString()
    }

    /**
     * Saves text coming from the clipboard (or from an explicit capture action).
     * Returns true when the vault changed.
     */
    fun save(context: Context, rawText: String?, source: String): Boolean {
        if (rawText == null) return false
        val text = rawText.trimEnd()
        if (text.isBlank()) return false
        if (text.length > MAX_TEXT) return false

        val prefs = Prefs(context)
        if (text.length < prefs.minLength) return false

        synchronized(lock) {
            val db = ClipDb.get(context).writableDatabase
            val h = hash(text)

            // The watcher re-reads the clipboard on a timer. If this exact text is still the
            // newest row we must not rewrite its timestamp over and over.
            db.rawQuery("SELECT hash FROM clips ORDER BY copied_at DESC LIMIT 1", null).use { c ->
                if (c.moveToFirst() && c.getString(0) == h) return false
            }

            val changed = insertOrUpdate(db, text, h, System.currentTimeMillis(), false, source)
            if (changed) prefs.lastCaptureAt = System.currentTimeMillis()
            return changed
        }
    }

    private fun insertOrUpdate(
        db: SQLiteDatabase,
        text: String,
        h: String,
        copiedAt: Long,
        pinned: Boolean,
        source: String
    ): Boolean {
        db.beginTransaction()
        try {
            var existingId = -1L
            db.rawQuery("SELECT id FROM clips WHERE hash = ?", arrayOf(h)).use { c ->
                if (c.moveToFirst()) existingId = c.getLong(0)
            }

            if (existingId == -1L) {
                val values = ContentValues().apply {
                    put("text", text)
                    put("hash", h)
                    put("copied_at", copiedAt)
                    put("pinned", if (pinned) 1 else 0)
                    put("source", source)
                }
                db.insertOrThrow("clips", null, values)
            } else {
                val values = ContentValues().apply {
                    put("copied_at", copiedAt)
                    put("source", source)
                    if (pinned) put("pinned", 1)
                }
                db.update("clips", values, "id = ?", arrayOf(existingId.toString()))
            }
            db.setTransactionSuccessful()
            return true
        } catch (t: Throwable) {
            return false
        } finally {
            db.endTransaction()
        }
    }

    fun list(context: Context, query: String? = null, limit: Int = 200_000): List<Clip> {
        val db = ClipDb.get(context).readableDatabase
        val sql: String
        val args: Array<String>?
        if (query.isNullOrBlank()) {
            sql = "SELECT id, text, hash, copied_at, pinned, source FROM clips " +
                "ORDER BY pinned DESC, copied_at DESC LIMIT $limit"
            args = null
        } else {
            sql = "SELECT id, text, hash, copied_at, pinned, source FROM clips " +
                "WHERE text LIKE ? ESCAPE '\\' ORDER BY pinned DESC, copied_at DESC LIMIT $limit"
            args = arrayOf("%${escapeLike(query.trim())}%")
        }
        val out = ArrayList<Clip>()
        db.rawQuery(sql, args).use { c ->
            while (c.moveToNext()) {
                out.add(
                    Clip(
                        id = c.getLong(0),
                        text = c.getString(1),
                        hash = c.getString(2),
                        copiedAt = c.getLong(3),
                        pinned = c.getInt(4) != 0,
                        source = c.getString(5)
                    )
                )
            }
        }
        return out
    }

    fun recent(context: Context, limit: Int): List<Clip> {
        val db = ClipDb.get(context).readableDatabase
        val out = ArrayList<Clip>()
        db.rawQuery(
            "SELECT id, text, hash, copied_at, pinned, source FROM clips ORDER BY copied_at DESC LIMIT $limit",
            null
        ).use { c ->
            while (c.moveToNext()) {
                out.add(
                    Clip(
                        id = c.getLong(0),
                        text = c.getString(1),
                        hash = c.getString(2),
                        copiedAt = c.getLong(3),
                        pinned = c.getInt(4) != 0,
                        source = c.getString(5)
                    )
                )
            }
        }
        return out
    }

    fun count(context: Context): Int = try {
        ClipDb.get(context).readableDatabase.rawQuery("SELECT COUNT(*) FROM clips", null).use { c ->
            if (c.moveToFirst()) c.getInt(0) else 0
        }
    } catch (t: Throwable) {
        0
    }

    fun setPinned(context: Context, id: Long, pinned: Boolean) {
        val values = ContentValues().apply { put("pinned", if (pinned) 1 else 0) }
        ClipDb.get(context).writableDatabase.update("clips", values, "id = ?", arrayOf(id.toString()))
    }

    fun delete(context: Context, id: Long) {
        ClipDb.get(context).writableDatabase.delete("clips", "id = ?", arrayOf(id.toString()))
    }

    fun restore(context: Context, clip: Clip) {
        synchronized(lock) {
            insertOrUpdate(ClipDb.get(context).writableDatabase, clip.text, clip.hash, clip.copiedAt, clip.pinned, clip.source)
        }
    }

    fun deleteAllUnpinned(context: Context) {
        ClipDb.get(context).writableDatabase.delete("clips", "pinned = 0", null)
    }

    fun databaseSize(context: Context): Long {
        val base = context.getDatabasePath(ClipDb.NAME)
        var size = if (base.exists()) base.length() else 0L
        for (suffix in listOf("-wal", "-shm")) {
            val extra = File(base.path + suffix)
            if (extra.exists()) size += extra.length()
        }
        return size
    }

    fun exportJson(context: Context, out: OutputStream): Int {
        val clips = list(context)
        val root = JSONObject()
        root.put("app", "ClipVault")
        root.put("format", 1)
        root.put("exportedAt", System.currentTimeMillis())
        root.put("count", clips.size)
        val array = JSONArray()
        for (clip in clips) {
            array.put(
                JSONObject().apply {
                    put("text", clip.text)
                    put("copiedAt", clip.copiedAt)
                    put("pinned", clip.pinned)
                    put("source", clip.source)
                }
            )
        }
        root.put("clips", array)
        out.write(root.toString(2).toByteArray(Charsets.UTF_8))
        out.flush()
        return clips.size
    }

    fun importJson(context: Context, input: InputStream): Int {
        val raw = input.readBytes().toString(Charsets.UTF_8).trim()
        require(raw.isNotEmpty()) { "empty file" }
        val array = if (raw.startsWith("[")) {
            JSONArray(raw)
        } else {
            JSONObject(raw).optJSONArray("clips") ?: throw IllegalArgumentException("missing clips array")
        }

        var imported = 0
        val db = ClipDb.get(context).writableDatabase
        synchronized(lock) {
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                val text = item.optString("text", "")
                if (text.isBlank()) continue
                val copiedAt = item.optLong("copiedAt", System.currentTimeMillis())
                val pinned = item.optBoolean("pinned", false)
                val source = item.optString("source", "import")
                insertOrUpdate(db, text, hash(text), copiedAt, pinned, source)
                imported++
            }
        }
        if (imported > 0) Prefs(context).lastCaptureAt = System.currentTimeMillis()
        return imported
    }

    /** Exports the raw .db file so it can be opened with any SQLite tool on a computer. */
    fun exportDatabase(context: Context, out: OutputStream) {
        val db = ClipDb.get(context).writableDatabase
        try {
            db.rawQuery("PRAGMA wal_checkpoint(FULL)", null).use { it.moveToFirst() }
        } catch (_: Throwable) {
            // Not in WAL mode; the file copy below is already consistent.
        }
        val file = context.getDatabasePath(ClipDb.NAME)
        FileInputStream(file).use { input -> input.copyTo(out) }
        out.flush()
    }

    private fun escapeLike(value: String): String =
        value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
}
