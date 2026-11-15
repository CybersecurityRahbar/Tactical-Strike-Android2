# ClipVault — خزانة النصوص

A permanent, searchable, fully offline clipboard vault for Android. It never prunes the
oldest clip, stamps every entry with the full date and time, supports instant search and
pinning, and can export a complete JSON backup or the raw SQLite database.

Package: `com.cybersecurityrahbar.clipvault` · minSdk 26 · targetSdk 34 · Kotlin, SQLite,
classic Android views. **No `INTERNET` permission** is declared anywhere, and cloud backup
is disabled on purpose.

## How automatic capture works

Android 10 and later forbid background apps from reading the clipboard; only the app with
input focus or the **default input method** may read it. ClipVault therefore ships three
capture engines:

1. **Accessibility engine (no keyboard change needed).** `ClipboardAccessibilityService`
   observes only `TYPE_VIEW_CLICKED` events to notice Copy actions, then creates a 1×1
   transparent `TYPE_ACCESSIBILITY_OVERLAY` window for ~120 ms. Holding input focus is what
   makes `getPrimaryClip()` legal, so the window is opened, the clipboard is read and the
   window is removed. The focus grab is skipped whenever a text field has input focus, so
   typing is never interrupted. No screen content is stored or transmitted: node text is only
   compared against copy-button keywords.
2. **Keyboard engine (strongest).** `ClipVaultImeService` is a working Arabic/English/symbol
   keyboard with a strip of recent clips above the keys. While it is the default keyboard the
   package always has clipboard access, so capture works in every app with zero focus tricks.
3. **Fallbacks.** `ClipboardWatchService` (foreground polling, 1.2 s while the screen is on),
   an optional Quick Settings tile, the system share sheet, and capture on app open.

Permanent mode is a Service + `BOOT_COMPLETED` receiver + `specialUse` foreground service,
so capture resumes after a reboot without any further interaction.

## Build

```bash
cd clipvault
./gradlew :app:assembleRelease     # signed with keystore.properties when present
./gradlew :app:assembleDebug
```

Requires JDK 17 and an Android SDK with platform 34 and build-tools 34.0.0. Point
`local.properties` at the SDK or export `ANDROID_SDK_ROOT`.

GitHub Actions builds the APK on every push to `clipvault-app` and uploads it as an artifact
(`.github/workflows/clipvault-android.yml`).

## Shared signing certificate

Updates only install over the existing app when every build uses the same certificate, so
signing is configured once through `keystore.properties` (never committed):

```
storeFile=keystore/clipvault-signing.jks
storePassword=...
keyAlias=...
keyPassword=...
```

`app/build.gradle.kts` uses that keystore for both debug and release variants when the file
exists. To make CI produce installable updates, add four repository secrets:

| Secret | Meaning |
| --- | --- |
| `CLIPVAULT_KEYSTORE_BASE64` | `base64 -w0 keystore/clipvault-signing.jks` |
| `CLIPVAULT_STORE_PASSWORD` | keystore password |
| `CLIPVAULT_KEY_ALIAS` | key alias |
| `CLIPVAULT_KEY_PASSWORD` | key password |

Without those secrets the workflow still builds, but the artifact is debug-signed and cannot
update an installed release build.

## Data

SQLite table `clips` in `clipvault.db` (`id`, `text`, `hash`, `copied_at`, `pinned`, `source`)
with a unique hash index that de-duplicates repeats. Exports: JSON (menu → تصدير JSON), raw
database (menu → تصدير قاعدة البيانات) and import (menu → استيراد JSON).
