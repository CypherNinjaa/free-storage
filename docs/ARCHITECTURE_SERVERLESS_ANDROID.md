# Architecture Revision 3 — No server: Immich app code + Telegram API = Android app

> **Owner direction (2026-11-18):** "We don't have any server, and a server needs to be paid for. Find a way where we just use Immich + Telegram API = Android app."
> **Status:** proposed for approval. No code written.
> **Supersedes** the earlier server-based and S3-based designs. Those docs were removed from this folder on 2026-11-21.
> **Evidence tags:** **[SRC]** Immich source `f005e0c` · **[DOC]** official Telegram/TDLib docs (snapshots in `../sources/`) · **[3P]** third party · **[ASSUMPTION]** · **[PoC]** must be measured.

---

## 1. The idea in one picture

```
┌──────────────────────── Android phone (the only computer in the system) ────────────────────────┐
│ App = fork of Immich `mobile/` (Flutter) + Immich `native/` (Rust codecs)                        │
│                                                                                                  │
│  Immich UI (timeline, viewer, albums, people, map, search, backup pages)          ← reused       │
│  Domain services: timeline, local sync, hashing, albums, memories                 ← reused/adapted│
│  Drift (SQLite) DB: becomes the MASTER INDEX of the whole library                ← schema reused │
│  NEW  LibraryService: on-device processing (EXIF, thumbnails, faces, labels)      ← replaces server│
│  NEW  TelegramStore: TDLib (Telegram's official client library) via a Kotlin plugin               │
│  NEW  Crypto: per-file keys, passphrase-derived master key, recovery kit                           │
│  NEW  Local media endpoint (127.0.0.1): decrypted Range streaming for the video player             │
│  WorkManager background backup (existing Immich Android workers)                  ← reused       │
└───────────────────────────────────────────┬──────────────────────────────────────────────────────┘
                                            │ MTProto (TDLib)
                       ┌────────────────────▼────────────────────┐
                       │ Telegram (free)                          │
                       │  🔒 private channel "Library"   originals (encrypted), thumbnail packs │
                       │  🔒 private channel "System"    encrypted index snapshots, 📌 pinned    │
                       └──────────────────────────────────────────┘
```

**No server, no hosting bill.** The phone does what the Immich server did: hashing, metadata, thumbnails, face detection, search indexing. Telegram stores the encrypted files and the encrypted index backup.

---

## 2. How can a phone talk to Telegram? (three options, verified)

| | **A. Bot API over HTTPS** (`api.telegram.org`) | **B. TDLib logged in as a bot** | **C. TDLib logged in as a Telegram account** ✅ |
|---|---|---|---|
| What it is | Plain HTTPS calls with a bot token | Telegram's official client library on the phone, authenticating with a bot token (`checkAuthenticationBotToken` **[DOC]**) | Same library, logging in with phone number + code (like any Telegram app) |
| Max file | Upload 50 MB, **download 20 MB** **[DOC]**, so every file must be split into ~19 MB pieces (the approach of the open-source app *Ulap* **[3P]**) | 2000 MiB (4000 parts × 512 KiB **[DOC]**) | 2000 MiB; **4000 MiB with Premium** **[DOC]** |
| Partial (Range) download | Only per piece | ✅ `downloadFile(offset, limit)` **[DOC]** | ✅ |
| Fetch a message by ID | ❌ | ✅ `getMessages` | ✅ |
| **List/search channel history** | ❌ | ❌ (`messages.getHistory`: "Only users can use this method" **[DOC]**) | ✅ `getChatHistory`, `searchChatMessages` **[DOC]** |
| **Create the storage channel automatically** | ❌ (no Bot API method) | ❌ | ✅ `createNewSupergroupChat(is_channel=true)` **[DOC]** |
| Delete old messages | ⚠️ 48 h ambiguity for bots **[DOC]** | ⚠️ same | ✅ the channel owner can delete its channel's messages **[INFER — PoC]** |
| Setup for the user | Create bot (BotFather) + create channel + add bot as admin | Same + nothing else | **Log in once**; the app creates everything |
| Needs `api_id`/`api_hash` | No | Yes (embedded in the app, from my.telegram.org) | Yes |
| Native library in the APK | No | TDLib (≈ 10–30 MB per CPU architecture **[ASSUMPTION/PoC]**) | Same |
| **Which Telegram terms apply** | Bot Developer Terms: **§5.2(e)** names "cloud storage sites" as a prohibited use of bots with external apps | Same (§5.2(e)) | **API Terms of Service for client apps**: own `api_id`; tell users the app uses the Telegram API; no "Telegram" in the app name; no Telegram logo **[DOC]**. Storing your own files in your own chats is ordinary Telegram use (FAQ: keep "all your media in the cloud") **[DOC]** |
| Main risk | Bot ban; chunking overhead | Bot ban | **The account** can be rate-limited or restricted for unusual automated activity **[PoC]** → use a **dedicated Telegram account**, not your personal one |

### Recommendation: **Option C** (TDLib with a dedicated Telegram account)
- It is the only option that is **fully capable without any server**:
  - 2 GB files;
  - streaming;
  - deletion;
  - creating its own channel;
  - and, crucially, **rebuilding the index from Telegram alone**, because it can read history.
- It avoids the bot rule that explicitly names "cloud storage".
- It is how third-party Telegram apps work.

The dedicated account (a second phone number, e.g. a cheap prepaid SIM) protects your personal Telegram account if Telegram restricts the storage account.

Option A remains a fallback "lite mode" with no native library. It is not recommended: everything over 19 MB must be split, bot terms apply, and history cannot be listed.

---

## 3. What the server did, and who does it now

| Immich server job (verified in `server/`) | Serverless replacement (on the phone) |
|---|---|
| Receive upload, SHA-1 dedupe (`asset-media.service.ts`) | **Already on phone**: native SHA-1 hashing (`MessagesImplBase.kt:447-466`) + local index lookup by checksum |
| Store originals (`upload/`, `library/`) | **Telegram "Library" channel**: encrypted document per asset |
| EXIF/metadata (exiftool) | Android `MediaStore` columns + `ExifInterface` (GPS needs `ACCESS_MEDIA_LOCATION`, already requested **[SRC]**) |
| Thumbnails/previews (libvips) | Android thumbnail APIs + Immich `native/` Rust decoders (AVIF/JXL) **[SRC]**; stored in app storage + encrypted **thumbnail packs** in Telegram |
| Video transcoding (ffmpeg) | **None.** Stream originals from Telegram with Range reads (no CPU-heavy transcoding on phones) |
| Faces + People (ML server) | On-device ML (MediaPipe/LiteRT, §7), clustering on device, written to the existing People tables |
| Smart search (CLIP), OCR | v1: metadata search + on-device labels/OCR in SQLite full-text search; CLIP later (large models) |
| Reverse geocoding (place names) | Offline city dataset bundled (e.g. GeoNames cities, a few MB) or Android `Geocoder` |
| Map tiles (`tiles.immich.cloud` style URLs **[SRC]**) | A free tile provider (e.g. OpenFreeMap) **[3P — verify terms]** |
| Memories ("On this day") | Computed locally from dates |
| DB + backups (`pg_dump`) | Drift DB on the phone + **encrypted snapshot to the "System" channel, pinned** |
| Sync between devices (`/sync/stream`) | v1: one main device + full restore on a new device. v2: encrypted change journal in the System channel |
| Sharing, partners, shared links, web app, multi-user | **Not available** without a server. Optional later: "share to a Telegram chat" |

---

## 4. Immich code reuse (measured)

The app has **621** hand-written Dart files. Only **54 (≈ 9 %)** import the server API client **[SRC]**. The main seams are already isolated:

| Seam | File(s) **[SRC]** | Serverless change |
|---|---|---|
| Login gate | `lib/routing/auth_guard.dart` (needs `ApiService`) | Replace with an "onboarding complete" guard (Telegram login + passphrase) |
| Server sync | `lib/infrastructure/repositories/sync_stream.repository.dart`, `sync_api.repository.dart`, `lib/domain/services/sync_stream.service.dart` | Replace with **LibraryService** writing the same Drift tables (`remote_asset`, `remote_exif`, `remote_album*`, `person`, `asset_face`, `memory*`) |
| Image/video URLs | `lib/utils/image_url_builder.dart` (4 functions build server URLs) | Point to the on-device media endpoint (`http://127.0.0.1:<port>/…`) backed by the thumbnail store + TDLib |
| Remote image loading | `android/.../images/RemoteImagesImpl.kt` (OkHttp/Cronet + 1 GiB cache) | Works unchanged against the local endpoint, or read files directly |
| Uploads | `lib/repositories/upload.repository.dart`, `lib/services/foreground_upload.service.dart`, `background_upload.service.dart` | Replace the HTTP multipart upload with a **TelegramStore upload queue** (TDLib resumes interrupted uploads internally **[INFER — PoC]**) |
| Search | `lib/infrastructure/repositories/search_api.repository.dart` (server) | Local Drift queries + SQLite FTS |
| Map style | `lib/providers/server_info.provider.dart`, `providers/map/map_state.provider.dart` | Local setting |
| Background work | `android/.../background/*.kt` (MediaStore triggers, periodic worker, foreground dataSync) | **Keep**; call the new uploader |
| Device media access, local albums, hashing | `android/.../sync/*.kt`, `lib/domain/services/local_sync.service.dart`, `hash.service.dart` | **Keep** |
| Timeline, viewer, albums, people, map UI, settings | `lib/presentation/**` | **Keep** (they read Drift) |

**Estimate [ASSUMPTION]:**

| Area | Reused |
|---|---|
| UI | ≈ 75–85 % |
| Data and sync layer | ≈ 30–40 % (the server-facing parts are rewritten) |
| Android native code | ≈ 80 % |

Server-only screens (partner sharing, shared links, activities, OAuth, server settings) are hidden.

---

## 5. Telegram layout and data format

| Item | Design |
|---|---|
| Account | **Dedicated Telegram account** logged into the app via TDLib (phone + code + 2FA password). Optional Premium on that account: 4 GB files and no speed limits **[DOC]**. Not required |
| Library channel | Private channel created by the app (`createNewSupergroupChat`). One message per asset: an **encrypted document** (`inputMessageDocument`, `disable_content_type_detection = true` **[DOC]**) named `<assetId>.bin` |
| Caption (per message) | Encrypted **recovery record**: asset id, SHA-1, capture date, size, type, wrapped file key. Lets the app **rebuild the whole library from Telegram alone** by scanning history |
| Thumbnail packs | Every ~500 new thumbnails → one encrypted pack document (≈ 7.5 MB at ~15 KB per thumbnail **[ASSUMPTION]**). A new phone downloads the packs and shows the full timeline in minutes, without fetching originals |
| System channel | Encrypted Drift DB snapshots (nightly, or after N changes). The newest is **pinned**. v2: change journal for multi-device |
| Large files > ~1.95 GiB | v1: split into parts (each part a document; per-part checksum). With Premium on the storage account: one file up to ~3.9 GiB |
| Privacy | Telegram channels are not end-to-end encrypted ("server-client encryption" for cloud chats **[DOC]**), so **everything is encrypted on the phone before upload**. Telegram never sees photos, thumbnails, names or dates |

---

## 6. Keys, encryption and recovery (no server = the phone holds the keys)

- **Master key** = Argon2id(passphrase, salt). A random per-file key encrypts each file (AES-256-GCM in 1 MiB segments, so videos can be streamed and seeked). The per-file key is wrapped with the master key and stored in the caption and the DB.
- **Recovery kit:** the passphrase (or a printed 24-word key) plus the storage account's phone number. Lose the phone? Install the app, log in to the storage account, enter the passphrase:
  1. Download the pinned DB snapshot and the thumbnail packs. The timeline is back.
  2. Originals are fetched on demand.
  3. If the snapshot is missing or old, the app scans the channel history and rebuilds the index from the captions.
- **Lose the passphrase = lose the library.** Make this unmistakable during onboarding.
- **Delete:** remove the Telegram message (the owner can delete **[PoC]**) and wipe the key from the DB.

---

## 7. On-device processing and faces (the original "lightweight ML" question)

| Task | On-phone choice | Notes |
|---|---|---|
| Face detection | **MediaPipe Face Detector** (BlazeFace, ≈ 224 KB model **[3P]**, Apache-2.0) | Fast, small |
| Face recognition (embeddings) | A small face-embedding model via **LiteRT** or **ONNX Runtime Mobile** (MobileFaceNet/SFace class) **[PoC: pick a licence-clean model]** | InsightFace weights (`buffalo_*`) are non-commercial-research only **[3P]** |
| Grouping into People | Incremental clustering on device (cosine distance, like Immich's server settings) → existing `person`/`asset_face` tables → **existing People UI** | Run while charging and idle (WorkManager constraints already exist) |
| Labels / text in photos | ML Kit labeling/OCR is free but **proprietary**. Prefer open models for an AGPL app **[INFER]** | Feeds SQLite full-text search |
| face-api.js | **No** (JavaScript, unmaintained) | — |

The processing budget is in the phone's idle and charging time. A 10k-photo library might take several charging sessions for faces **[ASSUMPTION — PoC]**.

---

## 8. Background backup flow on Android

```
MediaStore change ─► MediaObserver (existing) ─► BackgroundWorker (existing, foreground dataSync)
  ─► hash (existing native SHA-1) ─► already in index? skip
  ─► extract metadata + thumbnail ─► encrypt (streaming) ─► TDLib sendMessage(inputMessageDocument)
  ─► on success: store (chat_id, message_id, file_unique_id), mark "uploaded"
  ─► verify: getMessages + compare size; optional read-back of first/last segment ─► "Protected in Telegram ✓"
  ─► thumbnail pack / DB snapshot when thresholds are reached
```

Android limits that still apply:
- Battery-optimisation exemption is needed for long backups (the existing app logic).
- Android 15 caps background **dataSync** foreground services at **6 h per 24 h** **[DOC]**. A first backup of a big library therefore spans several days unless the app is kept in the foreground.
- Wi-Fi-only, charging-only and per-type cellular settings already exist **[SRC]**.

---

## 9. Realistic limits and timings

| Item | Value |
|---|---|
| Cost | **$0 infrastructure.** Optional Telegram Premium for the storage account (faster, 4 GB files) |
| Max single file | 2000 MiB (4000 MiB with Premium) before splitting **[DOC]** |
| Upload speed | Your phone's upload bandwidth (e.g. 20–100 Mbps on Wi-Fi), and Telegram's per-account speed limits for non-Premium users after "tens of gigabytes" **[DOC]** **[PoC]** |
| Message rate | Account flood limits are undocumented for channel posting **[PoC]**. Plan conservatively (≈ 20/min → 100k photos ≈ 3.5 days) until measured |
| Phone storage used | Index DB (~10–20 KB/asset incl. faces **[ASSUMPTION]**) + thumbnails (~15 KB/asset) + TDLib cache (capped) ≈ **3 GB per 100k assets**, plus temporary space for uploads |
| Opening an original | Photo ≈ 1 s; video starts streaming after the first segments **[ASSUMPTION — PoC]** |
| Durability | Telegram only. No SLA. A ban of the storage account = loss of access. Phones keep originals until "Free up space" is used |

---

## 10. What you lose without a server (honest list)

- **One person per app install.** Family members each run their own app and storage account. No shared albums, partner sharing or public links between users.
- **No web app or desktop access.** Viewing is on the Android app only. v2 could add a second device via the journal.
- **Face recognition and search are weaker** than Immich's server models (phone-sized models, CPU and battery budget).
- **Everything depends on one Telegram account and your passphrase.**
- **Upstream Immich updates are harder to merge.** The fork rewrites the app's data layer, so expect conflicts in the replaced files.

---

## 11. Roadmap for the serverless app [ASSUMPTION: one senior Flutter/Android engineer]

| Phase | Goal | Weeks |
|---|---|---|
| 1 | **PoC** in a tiny Android test app. TDLib (official Java/JNI build, or a maintained Flutter binding such as `handy_tdlib_next` **[3P]**) logs into a dedicated account, creates a channel, uploads encrypted 1 KB–1.9 GiB files, measures speed and flood limits, ranged download + decrypt + video seek via a local endpoint, history scan + caption search, delete of old messages, background run under WorkManager, APK size | 2–3 |
| 2 | **Fork skeleton**: rebrand; replace the login guard with onboarding (Telegram login + passphrase + recovery kit); hide server-only screens; local timeline working | 2 |
| 3 | **TelegramStore plugin** (Kotlin + TDLib, exposed via pigeon like the app's other native APIs) + crypto | 3–4 |
| 4 | **Local index**: Drift additions (Telegram refs, upload state, keys); Telegram-stored assets as `remote_asset` rows so the timeline merges them; local media endpoint for thumbnails/originals | 3 |
| 5 | **Backup pipeline**: observer → hash → metadata/thumbnail → encrypt → upload → verify → "Protected" badge; gated "Free up space" | 3–4 |
| 6 | **Viewing and restore**: open originals, video streaming, save back to gallery, share | 2–3 |
| 7 | **Index backup and new-phone restore**: pinned DB snapshots, thumbnail packs, rebuild-from-history fallback | 2–3 |
| — | **MVP milestone**: backup, browse, view, restore on a new phone (≈ 4–5 months) | |
| 8 | Metadata search, places (offline geocoder), memories, albums polish | 2–3 |
| 9 | Faces/People and labels on device | 3–4 |
| 10 | Hardening: 100k-asset libraries, battery, Android 15 limits, flood handling, splitting > 2 GiB, optional second-account mirror | 3–4 |
| | **Full v1** ≈ 7–10 months | |

---

## 12. Decisions needed before Phase 1

| Question | Proposed default |
|---|---|
| Telegram access | **Option C**: TDLib + dedicated Telegram account |
| Encryption | Always on; passphrase + printed recovery key |
| Users | One user per install (family members install separately) |
| Large videos | Split into ≤ 1.95 GiB parts (or Premium on the storage account) |
| Faces/search in v1? | After the MVP (Phases 8–9) |
| Second device | Restore-only in v1; live multi-device sync in v2 |

> **Needed from you for the Phase 1 PoC:**
> - an `api_id`/`api_hash` from my.telegram.org;
> - a spare phone number for the dedicated storage account;
> - an Android phone for testing.
