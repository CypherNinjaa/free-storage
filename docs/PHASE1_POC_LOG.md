# Phase 1 PoC — Test App & Measurement Log

> **Tracks:** [ARCHITECTURE_SERVERLESS_ANDROID.md](ARCHITECTURE_SERVERLESS_ANDROID.md) §11 (Phase 1) & [TELEGRAM_API_ANALYSIS.md](TELEGRAM_API_ANALYSIS.md) §6 (U1–U8).
> **App location:** `../poc-android/` (Kotlin + Jetpack Compose + TDLib 1.8.65 `libtdjson.so` + Media3 ExoPlayer + WorkManager). Removed on 2026-11-27 because the Ambry app replaced it; this log keeps its results.
> **Device tested:** Physical Android (`arm64-v8a`, `NNQSKRL7AI7LOF65`), non-Premium dedicated Telegram account, channel `-1004310008988`.
> **Test date:** 2026-11-21.
> **Verdict:** **GO for Phase 2.** Every core technical hypothesis passed on a real Android phone.

---

## 1. Build & Binary Size Measurements

### TDLib 1.8.65 Native Libraries (`libtdjson.so`, uncompressed)
| ABI | `libtdjson.so` Size |
|---|---|
| `arm64-v8a` | 30.47 MB |
| `armeabi-v7a` | 19.85 MB |
| `x86_64` | 29.76 MB |
| `x86` | 32.45 MB |

### Built APK Sizes (debug, `useLegacyPackaging = false`)
| Artifact | Size | Notes |
|---|---|---|
| `app-arm64-v8a-debug.apk` | **46.75 MB** (49,021,030 B) | Primary target for modern Android phones |
| `app-armeabi-v7a-debug.apk` | **35.74 MB** (37,473,018 B) | Legacy 32-bit ARM |
| `app-x86_64-debug.apk` | **46.01 MB** (48,245,242 B) | Emulator |
| `app-universal-debug.apk` | **98.48 MB** (103,263,342 B) | All 3 ABIs combined |

---

## 2. Phase 1 Checklist & Measured Unknowns (U1–U8)

| ID | Test / Unknown | Status | Measured Result |
|---|---|---|---|
| Setup | TDLib 1.8.65 login (dedicated account) | ✅ Passed | Logged in cleanly; session persisted across reinstalls |
| Setup | Create private channel (`createNewSupergroupChat(is_channel=true)`) | ✅ Passed | Created private channel `-1004310008988` automatically |
| Setup | Argon2id master key + 1 MiB AES-256-GCM segmented encryption | ✅ Passed | Unit test passed (`SegmentedCryptoTest`). On-device Argon2id (64 MiB, t=3, p=2): **2.27–2.64 s**. Encryption throughput: **171.8–178.0 MB/s** (1.90 GiB encrypted in **11.06 s**) |
| **U1** | Max documents/min before `FLOOD_WAIT` | ✅ Measured (burst) | **25/25 docs in 7.0 s (213.5 msg/min), 0 floods.** 10× higher than the conservative 20 msg/min bot estimate. Still pace sustained multi-thousand uploads gently and honour `retry_after` |
| **U2** | Sustained upload/download MB/s & `FLOOD_PREMIUM_WAIT` | ✅ Measured (up to ~2 GB) | `1 KB`: 372 ms · `1 MB`: **1.00 MB/s** · `10 MB`: **8.30 MB/s** · `50 MB`: **11.15 MB/s** · `1900 MiB`: **11.07 MB/s** (171.6 s). Zero `FLOOD_PREMIUM_WAIT` over ~2 GB total uploaded (multi-tens-of-GB soak still open for Phase 10) |
| **U3** | Delete channel messages as owner (`deleteMessages`) | ✅ Passed (short age) | Deleted msgs `2097152` (101 s), `3145728` (115 s), `4194304` (409 s) — all `deletedOk=true`. Re-verify one message in `-1004310008988` after **>48 h** to confirm no 48 h cap for channel owners |
| **U4** | `getMessages` read-only verification & file handle stability | ✅ Passed | Every uploaded object (1 KB through 1.90 GiB) verified `size` via `getMessages` (`verify=true`). Multi-month persistence to be monitored passively on `-1004310008988` |
| **U5** | Large file upload (~1.90 GiB) | ✅ Passed | **1,992,324,864 B (1900.03 MiB encrypted)** uploaded in a single message (`msgId=36700160`) at **11.07 MB/s**, `verify=true`. Safe v1 split threshold confirmed at **1.95 GiB** (leaves ample margin for 16 B/MiB GCM tag overhead under the 2000 MiB limit) |
| **U6** | TDLib cache growth & `optimizeStorage` cleanup | ✅ Passed | `4312 KB (3 files) -> 0 KB (0 files)` cleanly via `optimizeStorage(size=0, ttl=0)`. Subsequent cold read of `IMG-20261120-WA0018.jpg` transparently re-downloaded & decrypted in **258 ms** |
| **U7** | `getChatHistory` scan & `searchChatMessages` caption search | ✅ Passed | Scanned 32 msgs & decoded 31 `IMTG1:` encrypted recovery captions in **12 ms**. `searchChatMessages("IMTG1:<assetId>")` found exact message in **115–167 ms** |
| **U8** | New/dedicated account restriction risk | ✅ Observed OK | Zero warnings, restrictions, or flood waits across ~38 messages and ~2.0 GB uploaded in one session |
| Stream | Ranged download + decrypt + video playback via `127.0.0.1` | ✅ Passed | Real MP4 (`3.15 MB`, 4 × 1 MiB segments) streamed cold in **1510 ms** (warm **24 ms**); real JPEG (`207 KB`) cold in **258–327 ms** (warm **4–8 ms**); single 1 MiB segment downloaded & GCM-verified in **701 ms** |
| Bg | Background run under `WorkManager` (`dataSync` foreground service) | ✅ Passed | `PocBackupWorker` (Android 14/15 `FOREGROUND_SERVICE_TYPE_DATA_SYNC`) encrypted, uploaded, and verified 1 MB in **593–594 ms** (`msgId=34603008`, `35651584`) |

---

## 3. Critical Engineering Findings for Phases 3–7

1. **TDLib 1.8.65 `inputMessageDocument` schema change:**
   - In TDLib 1.8.65, `inputMessageDocument.document` is an **`inputDocument`** object wrapping `inputFileLocal` and `disable_content_type_detection` (not a raw `InputFile` directly). Passing `inputFileLocal` directly returns `400: InputFile is not specified`.
2. **TDLib `getChatHistory` pagination quirk (important for Phase 7 rebuild-from-history):**
   - `getChatHistory(limit=100)` may return fewer than 100 messages (e.g., 2 or 32) when local cache and remote fetches split a batch. Pagination loops MUST continue calling `getChatHistory(from_message_id = lastId)` until `messages.length == 0`, **never** breaking early on `arr.length < limit`.
3. **Channel creation service message (`msgId=1048576`):**
   - Cannot be deleted; deletion/scan logic must filter for `content["@type"] == "messageDocument"`.
4. **Encryption is not a bottleneck:**
   - At **171–178 MB/s** on device (15× faster than the ~11 MB/s upload rate), streaming AES-256-GCM encryption adds negligible latency and battery overhead.
