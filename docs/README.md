# Immich + Telegram Android App — Project Docs

**Project:** an Android photo/video backup app built from Immich's mobile code, storing everything in Telegram, with **no server**.
**Code baseline:** `immich-app/immich` @ `f005e0ce44ed3c3d9a18bc8b6dbb15a22af29205`, cloned read-only at `../immich/`.
**Telegram baseline:** Bot API 10.4 / TDLib docs, official pages snapshotted to `../sources/` (2026-11-18).

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

## Decision log

| Date | Decision |
|---|---|
| 2026-11-18 | Telegram is the only storage (no S3 or other cloud) |
| 2026-11-18 | The Android app is built only from Immich code |
| 2026-11-18 | **No server**: Immich app code + Telegram API = Android app |
| 2026-11-21 | Docs for the dropped server-based and S3-based designs removed. Six files are in the Windows Recycle Bin (D: drive) if ever needed |

## Evidence tags used in the docs

| Tag | Meaning |
|---|---|
| **[SRC]** | Verified in Immich source at the commit above |
| **[DOC]** | Verified in official documentation (copies in `../sources/`) |
| **[3P]** | Third-party source; verify before relying on it |
| **[ASSUMPTION]** | Planning estimate |
| **[PoC]** | Unknown until measured in Phase 1 |
| **[INFER]** | Reasoned inference, not documented |

## Folder layout

```
D:\immich-telegram-research\
├── immich\    read-only clone of immich-app/immich (unmodified)
├── sources\   official Telegram / TDLib page snapshots (evidence)
└── docs\      this folder
```
