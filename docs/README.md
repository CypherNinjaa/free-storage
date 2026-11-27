# Ambry (Immich + Telegram Android App) — Project Docs

**Project:** **Ambry**, an Android photo/video backup app built from Immich's mobile code, storing everything in Telegram, with **no server**. (Working name until 2026-11-22: "Keepsake".)
**Code baseline:** `immich-app/immich` @ `f005e0ce44ed3c3d9a18bc8b6dbb15a22af29205`. The local read-only clone (`../immich/`) was removed on 2026-11-27; to compare with upstream, clone github.com/immich-app/immich and check out that commit.
**Telegram baseline:** Bot API 10.4 / TDLib docs (2026-11-18). The page snapshots in `../sources/` were removed on 2026-11-27; the source URLs are listed in [TELEGRAM_API_ANALYSIS.md](TELEGRAM_API_ANALYSIS.md).

## Current plan

**[ARCHITECTURE_SERVERLESS_ANDROID.md](ARCHITECTURE_SERVERLESS_ANDROID.md)** (proposed, awaiting approval). In short:

- **App:** a fork of Immich's Flutter app. The phone does the server's former work (hashing, metadata, thumbnails, faces, search index).
- **Telegram access:** TDLib (Telegram's official client library) logged into a **dedicated Telegram account**. The app creates its own private channels.
- **Privacy:** everything is encrypted on the phone (passphrase + recovery kit).
- **Recovery:** the library index is backed up and pinned in a private System channel, so a new phone can restore everything.
- **Cost:** $0 infrastructure.

## Documents

| Document | Purpose |
|---|---|
| [ARCHITECTURE_SERVERLESS_ANDROID.md](ARCHITECTURE_SERVERLESS_ANDROID.md) | The plan: options compared, chosen design, Immich code reuse and the exact files to replace, Telegram layout, encryption and recovery, on-device ML, backup flow, limits, what is lost without a server, phased roadmap, decisions needed |
| [TELEGRAM_API_ANALYSIS.md](TELEGRAM_API_ANALYSIS.md) | Verified Telegram reference behind the plan: file size limits, file IDs, rate limits, history access, deletion rules, TDLib capabilities, Terms of Service, unknowns for the Phase 1 test |
| [PHASE1_POC_LOG.md](PHASE1_POC_LOG.md) | Phase 1: TDLib on Android proof of concept |
| [PHASE2_FORK_LOG.md](PHASE2_FORK_LOG.md) | Phase 2: Immich app fork, rebrand, local onboarding |
| [PHASE3_TELEGRAM_STORE_LOG.md](PHASE3_TELEGRAM_STORE_LOG.md) | Phase 3: Telegram store, vault key, encryption format |
| [PHASE4_8_LIBRARY_LOG.md](PHASE4_8_LIBRARY_LOG.md) | Phases 4–8: vault index, backup to Telegram, viewing and streaming, new-phone restore, local search and memories; device verification and bugs fixed |
| [PRIVACY_POLICY.md](PRIVACY_POLICY.md) | Ambry's privacy policy (the public URL used for Google Play and linked in the app) |
| [PLAY_RELEASE.md](PLAY_RELEASE.md) | Google Play release guide: steps, store listing text, Data safety answers, permission declarations |
| [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) | Production readiness review: new name (Ambry) and logo, on-device albums, encryption on/off, tests of all four screens, vault-only streaming/download, background upload, release build; bugs fixed and blockers before a public launch |

## Decision log

| Date | Decision |
|---|---|
| 2026-11-18 | Telegram is the only storage (no S3 or other cloud) |
| 2026-11-18 | The Android app is built only from Immich code |
| 2026-11-18 | **No server**: Immich app code + Telegram API = Android app |
| 2026-11-21 | Docs for the dropped server-based and S3-based designs removed. Six files are in the Windows Recycle Bin (D: drive) if ever needed |
| 2026-11-22 | App named **Ambry** (Keepsake was one letter from the Keepsafe photo vault); amber "sunrise in an arched alcove" logo |
| 2026-11-22 | Encryption becomes a setting (on by default); files uploaded with it off are plain files viewable in Telegram |
| 2026-11-22 | Idea "one supergroup, every album a topic" reviewed and dropped: it exposes album names, ties album deletion to photo deletion and slows album edits; albums stay in the encrypted index |
| 2026-11-27 | Project folder cleaned: build caches deleted; `poc-android/`, the `immich/` clone and `sources/` moved to the Recycle Bin; Immich's Play store listing (`android/metadata`, `android/fastlane`) removed from the repo |
| 2026-11-27 | Phase 10: large files are split into parts (encrypted above 512 MiB into 256 MiB parts, plain above 1.95 GiB); uploads resume per part; WorkManager 2.10.5 for Android 15's background limit. The optional second-account mirror is not built. Details: [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) §8 |

## Evidence tags used in the docs

| Tag | Meaning |
|---|---|
| **[SRC]** | Verified in Immich source at the commit above |
| **[DOC]** | Verified in official documentation (the local copies in `../sources/` were removed on 2026-11-27) |
| **[3P]** | Third-party source; verify before relying on it |
| **[ASSUMPTION]** | Planning estimate |
| **[PoC]** | Unknown until measured in Phase 1 |
| **[INFER]** | Reasoned inference, not documented |

## Folder layout

```
D:\immich-telegram-research\
├── keepsake\      the Ambry app: mobile\ (Flutter + Kotlin), native\, i18n\, branding\, open-api\
├── website\       landing page (ambry.vikashin.tech) and privacy page
├── docs\          this folder (store-assets\, ui-ux\)
└── ambry-launch\  launch video project (not in git)
```
