# Phases 4–8 — Telegram Library, Backup, Viewing, Restore, Local Search Log

> **Tracks:** [ARCHITECTURE_SERVERLESS_ANDROID.md](ARCHITECTURE_SERVERLESS_ANDROID.md) §5–§8, §11 (Phases 4–8). Builds on [PHASE3_TELEGRAM_STORE_LOG.md](PHASE3_TELEGRAM_STORE_LOG.md).
> **Source:** `../keepsake/mobile/`.
> **Date:** 2026-11-21. **Next:** [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) (2026-11-22) adds on-device albums, the encryption switch, the Ambry name, and closes several items in §4 below.

---

## 1. Design in one picture

```
 MediaStore photo ──hash (existing Immich hasher)──► Drift local_asset (checksum)
        │
        ▼  ForegroundUploadService.uploadSingleAsset  (foreground pool of 2, or background worker)
 KeepsakeLibraryApi.backupLocalAsset  ──pigeon──►  KeepsakeLibrary.backup (Kotlin)
        read original (setRequireOriginal) → AES-GCM segments (IMTG v1) → sendDocument to Library channel
        → verify size + getMessages → render thumbnail/preview → encrypt into ThumbnailStore
        → row in the on-device index (SQLite, keepsake-index.db, change sequence + tombstones)
        │
        ▼  KeepsakeLibrarySyncService (Dart) — replaces the server sync stream
 changesSince(seq) → SyncAssetV2 / SyncAssetExifV1 / SyncAssetDeleteV1 → existing SyncStreamRepository
        → Drift remote_asset / remote_exif  →  Immich timeline merges local + remote by checksum ("backed up" badge)
        │
        ▼  Immich image, original, video and share URLs  =  Store.serverEndpoint + /assets/{id}/…
 MediaServer (Kotlin, 127.0.0.1:47819/<random token>) decrypts thumbnails, previews and originals,
        streams videos with HTTP Range from Telegram 1 MiB segments (24 MiB segment cache)
```

The **on-device index is the source of truth**; Drift is a projection of it. Every projection write is an idempotent upsert, so overlapping passes (foreground app and background worker) are safe.

## 2. What was built

### 2.1 Native (Kotlin, `android/app/src/main/kotlin/app/alextran/immich/keepsake/`)

| File | Role |
|---|---|
| `KeepsakeIndex.kt` | SQLite index: one row per stored asset (checksum, Telegram chat/message/file ids, wrapped per-file key, metadata, favorite, visibility, trash, description, rating). Monotonic change `seq`, tombstones for deletes, schema v2 with upgrade, consistent export for snapshots |
| `LocalMediaReader.kt` | MediaStore lookup, original bytes (same URI as Immich's hasher, so checksums match), EXIF / video metadata, thumbnail (320 px short side) and preview (1440 px long side) rendering |
| `ThumbnailStore.kt` | Thumbnails and previews encrypted at rest with the vault's `thumbnail` subkey |
| `RemoteAssetReader.kt` | Opens a stored asset: unwraps its key, reads the IMTG header, fetches and decrypts 1 MiB segments by range, refreshes stale Telegram file ids |
| `KeepsakeLibrary.kt` | Backup, trash/restore/permanent delete (deletes the Telegram messages), 30-day trash purge, metadata updates, thumbnail regeneration from Telegram, vault discovery record, index snapshots, restore and history reconcile, flood-wait retry |
| `MediaServer.kt` | Loopback HTTP server with a random per-install path token; routes `thumbnail?size=thumbnail|preview|fullsize`, `original`, `video/playback`; Range/206, HEAD |
| `KeepsakeApiImpl.kt` | `KeepsakeLibraryApi` pigeon implementation (plus the Phase 3 Telegram and vault APIs); registered for the app engine and the background worker engine |

### 2.2 Telegram layout additions

| Message | Channel | Purpose |
|---|---|---|
| `IMTG2:<assetId> <sealed recovery record>` caption on each encrypted document | Library | Lets a new phone rebuild the index from history alone (asset id, SHA-1, date, size, MIME, name, per-file key — all sealed with the vault key) |
| `KSVAULT1 <descriptor> <libraryChatId> <systemChatId> <name>` text, pinned | System | Vault discovery on a new phone. The descriptor holds only the passphrase- and recovery-wrapped vault key |
| `KSIDX1:<snapshotId> <sealed manifest>` document | System | Encrypted copy of the index (newest 3 kept). Taken after backup runs when 6 h passed or 200 changes piled up, every 250 uploads in long runs, or on demand |

### 2.3 Dart (Immich app)

| Change | Where |
|---|---|
| Library projection service (index → Drift, owner user rows, "On this day" memories) | `lib/domain/services/keepsake_library_sync.service.dart` |
| `SyncStreamService.sync()` delegates to the projection (no server version call) | `lib/domain/services/sync_stream.service.dart` |
| Backup to Telegram instead of HTTP; 2 parallel uploads; snapshot when due | `lib/services/foreground_upload.service.dart` |
| Trash, restore, empty trash, permanent delete, favorite/archive/hidden, date, location, description, rating go to the index; stacks and edits report "not available yet" | `lib/repositories/asset_api.repository.dart` |
| Media server started at login and app start; its URL becomes `Store.serverEndpoint` | `lib/providers/auth.provider.dart` |
| Onboarding: discover an existing vault, unlock with passphrase **or 24 recovery words**, restore the index (snapshot + history reconcile) | `lib/pages/login/login.page.dart` |
| Vault item count and "Back up library index now" in the account sheet | `lib/widgets/common/app_bar_dialog/app_bar_dialog.dart` |
| On-device metadata search (file name, description, camera, date, type, favorites, archive, rating) | `lib/infrastructure/repositories/local_search.repository.dart`, `lib/domain/services/search.service.dart` |
| Linked-album sync (server albums) disabled; Folders, Locked folder and People hidden | `sync_linked_album.service.dart`, `library.page.dart` |
| Store keys `keepsakeIndexSeq` (2002), `keepsakeMemoriesDay` (2003), `keepsakeProjectionVersion` (2004); seq cleared on sign-out and for a new vault user | `store.model.dart`, `auth.service.dart` |
| Startup and resume: device sync + vault sync, hashing, then the foreground backup resumes when enabled | `splash_screen.page.dart`, `app_life_cycle.provider.dart` |

## 3. Restore on a new phone (Phase 7)

1. Sign in to the same dedicated Telegram account.
2. The app finds the System channel, reads the pinned `KSVAULT1` record and adopts the vault descriptor and channel ids.
3. Unlock with the passphrase or the 24 recovery words.
4. The newest `KSIDX1` snapshot is downloaded and decrypted into the index; then the whole Library channel is walked: assets added after the snapshot are decoded from their captions, deleted ones are dropped, Telegram file ids are refreshed.
5. The projection fills the timeline. Thumbnails of restored assets are generated on first view from the encrypted originals.

## 4. Not done yet / known limits

| Item | Plan phase | Notes |
|---|---|---|
| Thumbnail packs | 7 | Restored assets render thumbnails lazily by downloading originals (slow for large libraries on first scroll) |
| Upload progress per byte | 5 | Progress jumps 0 → 100 % per file |
| Albums (remote), stacks, edits, shared links, partners | 8 | Edit and Share Link are hidden; "Add to album" still shows and will fail until albums exist on device |
| App name in the debug build | — | Android still labels the debug app "Immich-Debug" (seen in the move-to-bin prompt) |
| Places names (reverse geocoding), smart (CLIP) search, OCR, tags | 8 | Search falls back to text matching on file name, description and camera |
| Faces / People | 9 | Hidden |
| Files over 1.95 GiB | 10 | Rejected with a clear error (no splitting yet) |
| Share-into-app uploads | 10 | Report "not available yet" |
| Multi-device live sync | — | Each phone owns its index; a second phone sees the library as of its last restore |

## 5. Verification (2026-11-21, RMX3785, Android 15)

| Check | Result |
|---|---|
| Kotlin compiles (`:app:compileDebugKotlin`), arm64 debug APK builds | ✅ |
| Dart unit tests: index → timeline mapping + recovery kit | ✅ (final count below) |
| App starts on the phone, no crashes; server version / folder calls gone from the log | ✅ |
| Media server listens on 127.0.0.1:47819 and returns 404 without the per-install token | ✅ |
| "Back up library index now": encrypted snapshot uploaded to the System channel; index meta shows `last_snapshot_at` and `vault_record_published_at` (pinned discovery record) | ✅ |
| Index schema v2 (description, rating) created on device | ✅ |
| Bug found and fixed: onboarding never requested photo/video/media-location permission, so no albums were visible. Now requested at onboarding and at startup; on device the prompt appeared and all four permissions are granted; 30 albums visible | ✅ |
| **Real backup**: the Camera album (574 items) backing up to Telegram; 505 stored at the last check (351 photos ≈ 0.9 GB, 154 videos ≈ 8.7 GB), every one verified on Telegram and shown with the "backed up" badge as soon as it finished | ✅ |
| Automatic index snapshot during a long run (taken at the 250-upload mark) | ✅ |
| Media server against the whole vault: 1010/1010 thumbnails and previews are valid JPEGs | ✅ |
| Round trip Telegram → phone: 3 photos and 2 videos (24 MB, 50 MB) downloaded, decrypted and **byte-identical** to the originals (SHA-1) | ✅ |
| Video seeking: `Range` request returns `206` with the exact bytes of the file on the phone | ✅ |
| Manual "Upload" of selected photos (synthetic test images): stored, checksums equal the source files | ✅ |
| Favorite, Trash (with Android's move-to-bin prompt), Trash page, Restore — all reflected in the vault index | ✅ |
| Vault-only photo (phone copy in the bin): timeline thumbnail, full-size viewer and Share (Android share sheet, cancelled) all served from Telegram | ✅ |
| Kotlin unit tests (vault crypto 7, segmented cipher 6, vault store 8) and Dart mapping/recovery-kit tests (7 + 5) | ✅ 21/21 and 12/12 |
| New-phone restore | ⏳ Not run: needs a second phone or wiping the app, which means signing in to Telegram again with a login code |

### Bugs found on the phone and fixed

| Bug | Cause | Fix |
|---|---|---|
| Originals and videos failed with "Not a Keepsake encrypted file" after an app restart | The index stored TDLib's numeric `file_id`; TDLib renumbers files every session, so old ids named other files | File ids are resolved from the Telegram message once per session (`RemoteAssetReader`); headers are checked against the stored encrypted size and re-resolved on mismatch |
| Possible wrong bytes when two ranges of one file are read at once | A synchronous `downloadFile` returns early when another range of the same file is requested | Range downloads of one file are serialized and TDLib's `getFileDownloadedPrefixSize` is checked before reading (`TdClient.downloadRange`); a stale local copy is dropped with `deleteFile` |
| Temporary encrypted files left in the cache after a killed upload | Process killed mid-upload | Cleared once per process before any Keepsake work starts |
| Backup did not resume on app start or resume | Phase 2 removed the remote sync and "resume backup" steps; the splash also lost them because it navigated away before they ran | Startup and resume run device sync + vault sync, hashing, then the foreground backup, using values captured before navigation |
| Capture times shown in UTC (e.g. 3:08 PM instead of 8:38 PM) | Immich shows EXIF time in the EXIF time zone and falls back to UTC | The projection writes each item's offset at capture (`UTC+05:30`); a projection version forces one full re-projection |
| "Share Link" and "Edit" offered for vault photos | Both need an Immich server | Hidden |

Not caused by Keepsake: three video-thumbnail decode errors come from Immich's own local loader (`LocalImagesImpl.decodeVideoThumbnail`).
