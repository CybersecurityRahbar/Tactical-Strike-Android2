package com.cybersecurityrahbar.clipvault.ime

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.inputmethodservice.InputMethodService
import android.inputmethodservice.Keyboard
import android.inputmethodservice.KeyboardView
import android.os.Build
import android.text.TextUtils
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.cybersecurityrahbar.clipvault.R
import com.cybersecurityrahbar.clipvault.data.ClipStore
import com.cybersecurityrahbar.clipvault.service.ClipboardWatchService
import com.cybersecurityrahbar.clipvault.ui.MainActivity
import com.cybersecurityrahbar.clipvault.util.ClipboardUtil

private enum class Page { LATIN, ARABIC, SYMBOLS }

class ClipVaultImeService : InputMethodService(), KeyboardView.OnKeyboardActionListener {

    private var keyboardView: KeyboardView? = null
    private var strip: LinearLayout? = null
    private var pageButton: TextView? = null
    private var clipboardManager: ClipboardManager? = null

    private var page = Page.LATIN
    private var lettersPage = Page.LATIN
    private var shift = false

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        val text = ClipboardUtil.readText(this)
        if (!text.isNullOrBlank()) ClipStore.save(this, text, "keyboard")
        refreshStrip()
    }

    override fun onCreate() {
        super.onCreate()
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        ClipboardWatchService.start(this)
    }

    override fun onCreateInputView(): View {
        val root = layoutInflater.inflate(R.layout.ime_clipvault, null)
        val view = root.findViewById<KeyboardView>(R.id.keyboard_view)
        keyboardView = view
        view.setOnKeyboardActionListener(this)
        view.setPreviewEnabled(false)

        strip = root.findViewById(R.id.history_strip)
        pageButton = root.findViewById(R.id.btn_page)

        root.findViewById<View>(R.id.btn_open_vault).setOnClickListener { openVault() }
        root.findViewById<View>(R.id.btn_paste).setOnClickListener { pasteClipboard() }
        pageButton?.setOnClickListener { toggleLanguage() }

        applyPage(defaultPage())
        return root
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        ClipboardWatchService.start(this)
        try {
            clipboardManager?.addPrimaryClipChangedListener(clipListener)
        } catch (_: Throwable) {
        }
        val text = ClipboardUtil.readText(this)
        if (!text.isNullOrBlank()) ClipStore.save(this, text, "keyboard")
        refreshStrip()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        try {
            clipboardManager?.removePrimaryClipChangedListener(clipListener)
        } catch (_: Throwable) {
        }
        super.onFinishInputView(finishingInput)
    }

    private fun defaultPage(): Page {
        val language = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            resources.configuration.locales[0].language
        } else {
            resources.configuration.locale.language
        }
        return if (language.startsWith("ar")) Page.ARABIC else Page.LATIN
    }

    private fun applyPage(target: Page) {
        page = target
        if (target != Page.SYMBOLS) lettersPage = target
        shift = false
        val layout = when (target) {
            Page.LATIN -> R.xml.keyboard_latin
            Page.ARABIC -> R.xml.keyboard_arabic
            Page.SYMBOLS -> R.xml.keyboard_symbols
        }
        val keyboard = Keyboard(this, layout)
        keyboardView?.keyboard = keyboard
        updateKeyLabels()
        keyboardView?.invalidateAllKeys()
        pageButton?.text = if (lettersPage == Page.ARABIC) {
            getString(R.string.ime_latin)
        } else {
            getString(R.string.ime_arabic)
        }
    }

    private fun toggleLanguage() {
        applyPage(if (lettersPage == Page.ARABIC) Page.LATIN else Page.ARABIC)
    }

    private fun updateKeyLabels() {
        val keyboard = keyboardView?.keyboard ?: return
        for (key in keyboard.keys) {
            val codes = key.codes ?: continue
            if (codes.isEmpty()) continue
            val code = codes[0]
            if (code in 'a'.code..'z'.code) {
                val letter = code.toChar()
                key.label = if (shift) letter.uppercaseChar().toString() else letter.toString()
            }
        }
        keyboard.setShifted(shift)
    }

    override fun onKey(primaryCode: Int, keyCodes: IntArray?) {
        when (primaryCode) {
            CODE_SHIFT -> {
                shift = !shift
                updateKeyLabels()
                keyboardView?.invalidateAllKeys()
            }
            CODE_BACKSPACE -> backspace()
            CODE_ENTER -> sendEnter()
            CODE_SYMBOLS -> applyPage(Page.SYMBOLS)
            CODE_LETTERS -> applyPage(lettersPage)
            CODE_LANG -> toggleLanguage()
            CODE_VAULT -> openVault()
            CODE_PASTE -> pasteClipboard()
            else -> {
                var character = primaryCode.toChar()
                if (shift && character in 'a'..'z') {
                    character = character.uppercaseChar()
                    shift = false
                    updateKeyLabels()
                }
                commit(character.toString())
            }
        }
    }

    private fun backspace() {
        val connection = currentInputConnection ?: return
        val selected = connection.getSelectedText(0)
        if (selected.isNullOrEmpty()) {
            connection.deleteSurroundingText(1, 0)
        } else {
            connection.commitText("", 1)
        }
    }

    private fun sendEnter() {
        val connection = currentInputConnection ?: return
        val action = currentInputEditorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION) ?: EditorInfo.IME_ACTION_NONE
        if (action != EditorInfo.IME_ACTION_NONE && sendDefaultEditorAction(true)) return
        connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
        connection.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
    }

    private fun commit(text: CharSequence) {
        currentInputConnection?.commitText(text, 1)
    }

    private fun pasteClipboard() {
        val text = ClipboardUtil.readText(this)
        if (text.isNullOrBlank()) return
        commit(text)
        ClipStore.save(this, text, "paste")
    }

    private fun openVault() {
        try {
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Throwable) {
        }
    }

    private fun refreshStrip() {
        val container = strip ?: return
        container.removeAllViews()
        val clips = ClipStore.recent(this, 24)
        if (clips.isEmpty()) {
            container.addView(
                TextView(this).apply {
                    text = getString(R.string.ime_empty)
                    setTextColor(ContextCompat.getColor(this@ClipVaultImeService, R.color.text_secondary))
                    textSize = 12f
                    setPadding(dp(10), dp(8), dp(10), dp(8))
                }
            )
            return
        }
        for (clip in clips) {
            val chip = TextView(this).apply {
                text = clip.text.replace('\n', ' ')
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                maxWidth = dp(230)
                textSize = 13f
                setTextColor(ContextCompat.getColor(this@ClipVaultImeService, R.color.text))
                setBackgroundResource(R.drawable.chip_bg)
                setPadding(dp(14), dp(8), dp(14), dp(8))
                isClickable = true
                setOnClickListener { commit(clip.text) }
                setOnLongClickListener {
                    openVault()
                    true
                }
            }
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            params.marginEnd = dp(8)
            container.addView(chip, params)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onPress(primaryCode: Int) {}

    override fun onRelease(primaryCode: Int) {}

    override fun onText(text: CharSequence?) {
        if (!text.isNullOrEmpty()) commit(text)
    }

    override fun swipeLeft() {}

    override fun swipeRight() {}

    override fun swipeUp() {}

    override fun swipeDown() {
        requestHideSelf(0)
    }

    companion object {
        private const val CODE_SHIFT = 1001
        private const val CODE_SYMBOLS = 1002
        private const val CODE_LETTERS = 1003
        private const val CODE_ENTER = 1004
        private const val CODE_BACKSPACE = 1005
        private const val CODE_VAULT = 1006
        private const val CODE_PASTE = 1007
        private const val CODE_LANG = 1008
    }
}
