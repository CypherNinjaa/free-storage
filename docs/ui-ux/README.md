# Ambry — UI/UX Research, Design System & Implementation Plan

> **Scope:** Read-only UI/UX audit, competitor & guideline research, design direction, implementation-ready design system, motion specification, screen blueprints, and prioritized backlog for **Ambry** (`D:\immich-telegram-research\keepsake\mobile`). **Zero code, assets, or settings were modified in this run.**
> **Core Principle:** *Photography is the hero.* Preserve 100% of Ambry's working serverless TDLib vault, AES-256-GCM encryption, Drift index, MediaStore sync, and loopback streaming while making every touchpoint feel calm, fast, trustworthy, and deliberately crafted—with zero manipulative patterns.

---

## Chosen Design Direction — **Sunlit Alcove**

**Sunlit Alcove** pairs warm, gallery-grade neutral surfaces (*Sunlit Paper* `#FAF9F7` in light mode and *Obsidian Alcove* `#0C0C0E` in dark mode, dropping to pure `#000000` in the full-screen viewer) with disciplined amber accents (`#B8540F` / `#9E450A` light text, `#FDB44B` dark) reserved strictly for user intent, active selection, and vault protection. Every decorative gradient, drop shadow, and leftover server-app artifact is replaced by Material 3 tonal containment, WCAG AA contrast across surfaces and photo scrims, and M3 Expressive Standard physics motion (`140–260ms`, 120Hz Impeller-safe).

---

## Document Map

| Document | Phase & Focus | Summary |
|---|---|---|
| [`01_audit.md`](01_audit.md) | **Phase 1 — Verified Audit** | Complete screen, state, image-pipeline, trust-moment, and server-leak inventory with exact `file:line` references and draft corrections. |
| [`02_research.md`](02_research.md) | **Phase 2 — Research** | Benchmarked patterns from 8 photo products + M3 Expressive, Android, Apple HIG, WCAG 2.1, and public inspiration portals with canonical URLs. |
| [`03_direction.md`](03_direction.md) | **Phase 3 — Design Direction** | 3-direction comparison (*Swiss Lightbox*, *Editorial Monograph*, *Sunlit Alcove*) via weighted decision matrix and 5 anti-patterns to ban. |
| [`04_design_system.md`](04_design_system.md) | **Phase 4 — Design System** | Implementation-ready Light/Dark palette, WCAG AA contrast ratios, normalized `GoogleSans`/`GoogleSansCode` scale, 4-tier radii, and 16 component specs mapped onto `lib/theme/` & `immich_ui`. |
| [`05_motion_spec.md`](05_motion_spec.md) | **Phase 5 — Motion & Interaction Spec** | `AmbryMotion` spring/duration tokens, detailed choreography + haptics + reduced-motion fallbacks for 12 interactions, and 120Hz Impeller budget. |
| [`06_screens.md`](06_screens.md) | **Phase 6 — Screen Blueprints** | Screen-by-screen ASCII wireframes, states (loading/empty/error/offline/permission), interactions, accessibility notes, and exact files to edit. |
| [`07_implementation_plan.md`](07_implementation_plan.md) | **Phase 7 — Implementation Plan** | 4-milestone prioritized backlog with effort (`S/M/L`), dependencies, phone-verifiable acceptance criteria, and native data flags. |

---

## Top 10 Changes Ranked by User Impact

1. **Unified "Sunlit Alcove" Tokens, WCAG AA Contrast & Calm Neutral Chrome (`M1.1`):** Fix inverted `TextTheme` & bright orange AppBars/Settings/SnackBars; warm up Light/Dark neutrals; consolidate 11 hardcoded radii onto `ImmichRadius`; add `AmbryBrandMark` (`ambry-logo.png`), `AmbrySearchBar`, `AmbryBanner`, `AmbryEmptyState`, and `ImmichConfirmDialog`.
2. **Seamless Grid↔Viewer Experience & Telegram Streaming / Offline Resilience (`M1.4`):** Smooth `260ms` Hero corner/fit transition, 4-stop AA edge scrims, `3.5dp` scoped video scrubber, immediate known video duration + `350ms` `"Streaming from Telegram…"` pill (replacing 1.6s blind wait & infinite spinner), non-destructive photo offline retry keeping preview zoomable, focal double-tap zoom, `originalSize` zoom-lock fix, `ExifMap` pin fix, and Vault Status row.
3. **High-Trust Onboarding Redesign & Bug Fixes (`M1.2`):** Match native splash colors (`#FFF6E6`/`#1C140D`), adaptive 2-step unlock vs 3-step setup, fix the **critical 24-word copy/paste parser mismatch**, add `telegramApi.logOut()` account switcher + Change Phone, 2×12 `GoogleSansCode` recovery grid, passphrase strength meter, half-vault retry recovery, and permission priming.
4. **Above-the-Fold `BackupPage` with Active-Phone & Battery Banners (`M2.1`):** Collapse 3 passive stat cards into one Vault Summary Card, promote **Active-Phone Pause (`claimVault`)** and **ColorOS Battery Warning** banners, clean up `BackupToggleButton` (remove dead 8s gradient/shadow), add `"All backed up"` calm state, and clarify `EncryptUploadsTile` OFF warnings.
5. **Structured Vault & Account Hub Modal Bottom Sheet (`M2.3`):** Convert cramped top `Dialog` into a clean `surfaceContainerLow` Modal Bottom Sheet with live Vault Health, Primary Actions (`Free up space`, `Settings`) above collapsible Diagnostics, honest vault-lock sign-out confirmation, and 48dp footer links.
6. **Balanced `LibraryPage` & Working Places Entry (`M3.1` + `M3.4`):** Replace stretched 100% Trash pill & 2+1 grid hole with a symmetric **3-column quick bar + 1+2 Bento** (hero Places map linking directly to `MapRoute` until reverse geocoding exists), fix `MapPage` hardcoded `Colors.indigo`, fix frozen `MapSettingsSheet` toggles, and add `AmbryEmptyState` across all 9 collection pages.
7. **Editorial Borderless Albums & Bug-Free Search (`M3.2` + `M3.3`):** Move to clean 1:1 `r=16` album covers removing `"• Owned"`, separate loading vs empty (`"Create album"` CTA) vs search-miss states, fix `RemoteAlbumPage` delete back-stack & `CreateAlbumPage` overflow, preserve Search tab state, replace polaroid/gradient art with a 2×2 tonal grid, and fix `"Not in album"`, 100-item pagination loop, and `YearFilter` overshoot.
8. **Snappy `180ms` Shell, Tight Timeline Headers & Shared Shimmer (`M1.3`):** Cut tab crossfade from `600ms` to `180ms`, hide landscape `NavigationRail` during multi-select, fix `TimelineHeader` +6px overlap & hide bulk-select circles until selecting, add single-controller `AmbryShimmerScope` + `0.58` opacity AA video pills, and smooth bottom-only `MemoryLane` scrims.
9. **Free Up Space Honesty & Gallery Permission States (`M2.4` + `M4.2`):** Surface reclaimable MB/GB on Step 3 + confirm dialog, use honest `"Permanently delete"` copy on Android `< 12` (vs trash on `12+`), handle bin-prompt denial safely, fix `DevicePermissionService` media-location bug, and add a visible Gallery Permission Denied / Limited Access banner on Timeline & Local Albums.
10. **Eliminate Broken Serverless Leaks & Stuck Feedback (`M1.3`, `M2.2`, `M3.4`, `M4.1`–`M4.3`):** Hide leaking `StackAction` (which throws `UnsupportedError`) and Map `"Include partner assets"`, unstick completed/failed tasks in `DownloadInfoPage`, fix `SlideshowPage` controller leaks & slow-video skips, fix `ShareIntentPage` silent errors, and clean up `Immich_log_*` / `immich_export_*` / `discord.immich.app` leaks.

---

## Key Engineering Flags for the Next Run

- **Zero new dependencies required** (`animations` package unneeded; `pinput` & `immich_ui` are already bundled).
- **Deferred native/data enhancements flagged in [`07_implementation_plan.md`](07_implementation_plan.md):** (1) ThumbHash column & generation (`KeepsakeIndex.kt` + `LocalMediaReader.kt`), (2) per-byte TDLib upload progress stream, (3) dark vector map style JSON URL, (4) offline city reverse geocoding, (5) reviewing Cronet's 1 GiB plaintext disk cache (`MediaServer.kt:106` `immutable`), and (6) deciding whether `ShareIntentPage` gets native upload or drops `ACTION_SEND` from `AndroidManifest.xml`.
