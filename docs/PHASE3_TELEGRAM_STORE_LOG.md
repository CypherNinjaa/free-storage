# Phase 3 — Telegram Store Plugin + Vault Crypto Log

> **Tracks:** [ARCHITECTURE_SERVERLESS_ANDROID.md](ARCHITECTURE_SERVERLESS_ANDROID.md) §2, §5, §6, §11 (Phase 3). Builds on [PHASE1_POC_LOG.md](PHASE1_POC_LOG.md) (TDLib 1.8.65 proven on device) and [PHASE2_FORK_LOG.md](PHASE2_FORK_LOG.md).
> **Source:** `../keepsake/mobile/` and `../keepsake/native/`.
> **Date:** 2026-11-21.

---

## 1. Phase 2 review (against the plan)

| Plan item (§11 Phase 2) | Status |
|---|---|
| Rebrand (no "Telegram" in name, no logo; API disclosure) | ✅ Matches plan and Telegram API ToS §2.2–2.4 |
| Login guard replaced by local onboarding | ✅ |
| Hide server-only screens | ✅ |
| Local timeline (MediaStore sync + hashing) | ✅ |
| Passphrase + 24-word recovery kit | ⚠️ Shown to the user but **never turned into a key**: only a SHA-256 "fingerprint" was stored, so the 24 words could not recover anything. **Fixed in Phase 3** (vault key, §3) |
| Build | ❌ **Startup crash**: `libnative_core_ffi.so` missing because the `native_core` dependency was removed. **Fixed** (§2) |

## 2. Fix: `UnsatisfiedLinkError: libnative_core_ffi.so`

| Cause | Fix |
|---|---|
| `native_core` (Immich's Rust image core) was removed as "unused". It is loaded by Kotlin at startup (`NativeBuffer.kt` ← `HttpClientManager`) | Copied `immich/native` → `keepsake/native`; restored `native_core: path: ../native/native_core`; restored `integration_test/native_core_test.dart` |
| The hook needs **rustup** (`rustup target add …`, `rustup run 1.99.1 cargo build`). This PC only had a standalone Rust 1.94 | Installed rustup (official installer, user-level) + toolchain **1.99.1** with target `aarch64-linux-android` |

Verified: the rebuilt APK contains `lib/arm64-v8a/libnative_core_ffi.so` (4.1 MB).

### Build command (updated)

```powershell
cd D:\immich-telegram-research\keepsake\mobile
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-21.0.8.9-hotspot"
$env:PATH = "$env:USERPROFILE\.cargo\bin;C:\flutter\bin;$env:JAVA_HOME\bin;$env:PATH"
flutter build apk --debug --target-platform android-arm64 --android-skip-build-dependency-validation
```

## 3. What Phase 3 adds

### 3.1 Native layer (`android/app/src/main/kotlin/app/alextran/immich/keepsake/`)

| File | Role |
|---|---|
| `cpp/td_bridge.c` + `cpp/CMakeLists.txt` | JNI bridge to `libtdjson.so` (from the PoC). Passes **raw UTF-8 bytes** both ways: JNI "modified UTF-8" corrupts emoji in Telegram names and can abort debug builds |
| `TdJsonBridge.kt`, `TdClient.kt` | TDLib client ported from the PoC: auth state machine, `@extra` request matching, upload tracking (fixes a PoC race where a fast upload's result could arrive before it was awaited), ranged download, history/search/delete, channel creation. **TDLib database is now encrypted** with a random key protected by the Android Keystore (PoC used an empty key) |
| `VaultCrypto.kt` | Argon2id (64 MiB, t=3, p=2 — PoC-measured ≈2.3–2.6 s), HKDF-SHA256, AES-256-GCM seal/open |
| `VaultStore.kt` | **Key hierarchy:** random 256-bit *vault key*, wrapped twice: by Argon2id(passphrase) **and** by HKDF(24-word entropy). Either secret unlocks. Changing the passphrase later only re-wraps one blob. The unlocked key is cached under an Android Keystore key, so background backup works without prompting. Locking deletes the cache |
| `SegmentedCipher.kt` | PoC file format kept (`IMTG` v1: 64-byte header, 1 MiB AES-GCM segments, header + index as AAD), now JVM-testable |
| `VaultCaption.kt` | Encrypted recovery caption `IMTG2:<assetId> <sealed>`, keyed by HKDF(vault key, "caption") instead of the passphrase key; bound to the asset id; file names capped at 120 chars to stay under Telegram's 1024-char caption limit |
| `TelegramVault.kt` | Creates/reuses the private **Library** and **System** channels (state saved after each creation, so a crash cannot duplicate channels). **On-device self-test**: encrypt 1.25 MiB → upload to System channel → verify size → `getMessages` → caption search → decrypt caption → delete local copies → range-download both segments from Telegram → decrypt → SHA-1 compare → delete test message |
| `KeepsakeApiImpl.kt`, `KeepsakeServices.kt` | Pigeon host APIs (`KeepsakeTelegramApi`, `KeepsakeVaultApi`); one process-wide TDLib client; errors mapped to codes (`WRONG_SECRET`, `VAULT_LOCKED`, `TELEGRAM_<code>`, `TIMEOUT`) |
| `MainActivity.registerPlugins` | Registers both APIs (also used by the background worker engine) |
| `jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/libtdjson.so` | TDLib 1.8.65 from the PoC |

### 3.2 Flutter layer

| File | Change |
|---|---|
| `pigeon/keepsake_api.dart` → `lib/platform/keepsake_api.g.dart` | API definition + generated client |
| `lib/pages/login/login.page.dart` | Step 1 is now a **real Telegram login** (phone → code → 2FA password). Finishing creates the vault from passphrase + recovery words, then the two channels. If the phone already has a vault (e.g. after sign-out), it asks for that vault's passphrase instead of creating a new one |
| `lib/domain/utils/recovery_kit.dart` | `toEntropy`/`fromEntropy`/`isWord`: 24 words ↔ 24 bytes (192 bits). Fingerprint removed |
| `lib/domain/models/store.model.dart`, `lib/routing/auth_guard.dart`, `lib/providers/auth.provider.dart` | `keepsakeVaultVersion` gate (Phase 2 installs are sent back through onboarding once). Sign-out **locks the vault** |
| `lib/widgets/common/app_bar_dialog/app_bar_dialog.dart` | **"Run vault self-test"** action |
| `android/app/build.gradle`, `gradle/libs.versions.toml` | Telegram `api_id`/`api_hash` read from `../.env` (or `KEEPSAKE_TELEGRAM_API_ID/HASH` env vars) into `BuildConfig`; CMake for the bridge; BouncyCastle 1.78.1; JUnit 4.13.2 |

## 4. Verification

| Check | Result |
|---|---|
| Native-library fix: APK contents | ✅ `lib/arm64-v8a/libnative_core_ffi.so` (4.1 MB) present after restoring `native_core` |
| Kotlin unit tests (`gradlew :app:testDebugUnitTest --tests "app.alextran.immich.keepsake.*"`) | ✅ **21/21 passed**:<br>• `SegmentedCipherTest` 6/6 (round trips at 0, 1, 1 MiB±1 and 3 MiB+17 bytes; single-segment range decrypt; tamper, swap, truncation and bad-header rejection)<br>• `VaultCryptoTest` 7/7 (RFC 5869 HKDF test cases 1 and 3, AEAD key/AAD binding, fresh nonces, Argon2id determinism)<br>• `VaultStoreTest` 8/8 (passphrase **and** recovery words unlock the same vault key; wrong secrets rejected; device cache until lock; captions round-trip and are bound to their asset id) |
| Dart unit test (`flutter test test/domain/utils/recovery_kit_test.dart`) | ✅ 5/5 (24 words ↔ 24 bytes, case/space tolerance, all 256 words reachable, invalid input rejected) |
| `flutter analyze` on all changed Dart files | ✅ No errors or warnings (only the upstream-wide `material.dart` deprecation notice) |
| Full debug APK build | ✅ Built (arm64 debug). Contains `libnative_core_ffi.so`, `libtdjson.so` and `libkeepsake_tdbridge.so` (CMake-built bridge) |
| On-device startup (phone `NNQSKRL7AI7LOF65`) | ✅ Installed over the Phase 2 build. Logcat: `libnative_core_ffi.so … ok`, `libtdjson.so … ok`, `libkeepsake_tdbridge.so … ok`; no `UnsatisfiedLinkError`, no crash. Splash logged *"No Keepsake vault session found; starting onboarding"* (vault gate working) |
| TDLib inside Keepsake | ✅ Onboarding reached the **phone-number step**, which is only shown after TDLib starts and reports `authorizationStateWaitPhoneNumber` |
| Telegram login → vault creation → channels → self-test | ⏳ Needs the login code sent to the dedicated account: run §6 on the phone and record the self-test report here |

## 5. Security notes and open items

| Item | Status / next step |
|---|---|
| **TDLib binary provenance** | The `libtdjson.so` files came from `poc-android/tdlib-jniLibs.tar.gz`; their origin is not recorded. They will hold the Telegram session. **Before real photos are stored, rebuild TDLib 1.8.65 from the official source** (github.com/tdlib/td) and compare. SHA-256 of the current files: arm64-v8a `1ddfd787…5d9e4`… see §5.1 |
| `api_hash` inside the APK | Unavoidable for a Telegram client app; never commit `.env` |
| Recovery words on the clipboard | Still copied in plain text (Flutter cannot mark clipboard data sensitive). Consider removing the copy button or clearing the clipboard after 60 s |
| Sign-out keeps the Telegram session | Intentional for now (re-onboarding then needs no SMS code). "Remove vault from this phone" comes with Phase 7 (restore) |
| New-phone restore | Phase 7: vault descriptor + DB snapshot to the System channel, pinned |

### 5.1 TDLib file hashes (SHA-256)

```
1ddfd787422d81247a1e64160f92dbe8c8cd62b67822e620162e54ce114b9eb9  arm64-v8a/libtdjson.so
bf154402a5e29768571349c044a9976256bf7a18fb740f1e9cfb92f7905e359c  armeabi-v7a/libtdjson.so
6f9fe7694131d15f326ff8b80e07e617b02694f9a72d75e3a7e7b2720515d9e4  x86_64/libtdjson.so
```

## 6. How to test Phase 3 on the phone

1. Install the debug APK (`adb install -r build\app\outputs\flutter-apk\app-debug.apk`).
2. The app opens onboarding (a Phase 2 install is sent through it once).
3. Step 1: enter the dedicated account's number → enter the code Telegram sends → (2FA password if set) → "Telegram connected".
4. Step 2–3: passphrase, save the 24 words, "Create Vault & Open Timeline". Two private channels appear in the dedicated account: *Keepsake Library · …* and *Keepsake System · …*.
5. Tap the profile avatar → **Run vault self-test** → every step should show ✓.
