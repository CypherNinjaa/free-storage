# Phase 6 — Screen-by-Screen Blueprints

> Every screen below maps directly to verified routes, widgets, and providers in `keepsake/mobile/lib/`. Server-only features (People, Locked Folder, Shared Links, Partners, Folders, Activities, Album Options, Edit Image, Passkeys, Networking, What's New) stay excluded.

---

## 1. Splash & Bootstrap (`SplashScreenPage`, `BootstrapErrorWidget`)

- **Files:** `lib/pages/common/splash_screen.page.dart`, `lib/main.dart`, `flutter_native_splash.yaml`
- **Layout & Continuity:** Set `SplashScreenPage` `Scaffold.backgroundColor` to `#FFF6E6` (light) / `#1C140D` (dark)—matching `flutter_native_splash.yaml` and `values-v31/styles.xml` so cold launch has **zero background flash**. Render `assets/ambry-logo.png` centered at `96dp` (`ImmichRadius.xl` corners) with a quiet `bodySmall` status line below only if startup/media-server init takes `> 600ms` (`"Opening your vault…"`).
- **States:**
  - *Media server startup failure:* Show `AmbryErrorState` (`"Could not start local media server"`, `"Retry"` + `"View logs"`) instead of silently falling back to broken `'http://127.0.0.1'` (`auth.provider.dart:209-221`).
  - *Bootstrap error (`BootstrapErrorWidget`):* Fix leaked links (`:167-179`) to Ambry's GitHub (`https://github.com/CypherNinjaa/free-storage/issues`); add snackbar + `selectionClick()` on `"Copy error"`; show error banner if `_clearDatabase` fails; disable `debugShowCheckedModeBanner` in release builds (`false` or `kDebugMode`).
- **Accessibility:** `Semantics(label: 'Ambry starting up')`; dynamic text-safe centered column.

---

## 2. Onboarding & Restore (`LoginPage`)

- **File:** `lib/pages/login/login.page.dart` (remove dead `login_form.dart` / `change_password.page.dart` references in a later cleanup)
- **Adaptive Flow Structure:**
  - **New Vault (3 steps + permission priming):** `1. Connect Telegram` → `2. Create Passphrase` → `3. Save 24-Word Recovery Kit` → `Permission Priming`
  - **Existing / Discovered Vault (2 steps + permission priming):** `1. Connect Telegram` → `2. Unlock Vault` → `Permission Priming`
  - **Ask `Vault Name` ONLY when creating a new vault** (Step 2B), never before Telegram auth & vault discovery (`:370`).

```text
┌────────────────────────────────────────────────────────┐
│ [56dp Ambry Logo]                        [Logs] button │
│  Welcome to Ambry                                      │
│  Your private photos, encrypted in your Telegram vault │
│  ━━━━━━━━━━━━━━░░░░░░░░░░░░  Step 1 of 3 · Telegram    │
├────────────────────────────────────────────────────────┤
│  ┌─ infoContainer Banner ───────────────────────────┐  │
│  │ ⓘ Dedicated account recommended                  │  │
│  │ Uses the official Telegram API (TDLib). Not      │  │
│  │ affiliated with Telegram. Use a separate account.│  │
│  └──────────────────────────────────────────────────┘  │
│                                                        │
│  [ +91 98765 43210                              ]      │
│                                                        │
│  [            Send login code (48dp)            ]      │
│  ────────────────────────────────────────────────────  │
│  (On waitCode):  [ _ ] [ _ ] [ _ ] [ _ ] [ _ ] (pinput)│
│                  "Change phone number" text button     │
│  (On ready):     ✓ Connected as @handle                │
│                  [ Continue ]   [ Switch account ]     │
└────────────────────────────────────────────────────────┘

Step 3 (New Vault) — 24-Word Recovery Kit Grid:
┌────────────────────────────────────────────────────────┐
│  Save Your 24-Word Recovery Kit                        │
│  Write these down with your Telegram phone number.     │
│  ┌──────────────────────┬──────────────────────┐       │
│  │ 01  acorn            │ 13  harbor           │       │
│  │ 02  alder            │ 14  hazel            │       │
│  │ ...                  │ ...                  │       │
│  │ 12  grain            │ 24  juniper          │       │
│  └──────────────────────┴──────────────────────┘       │
│  [ Copy 24 Words ]  (Clipboard notice: clear after use)│
│  [✓] I saved my passphrase & recovery kit safely.      │
│  [ Back ]    [       Create Vault & Continue       ]   │
└────────────────────────────────────────────────────────┘
```

- **Key Interactions & Fixes:**
  1. **Switch Telegram Account:** On `TelegramAuthStep.ready`, provide `"Use another account"` calling `telegramApi.logOut()`. On `waitCode`/`waitPassword`, provide `"Change phone number"` + visibility toggle on 2FA (`hintText` hidden when empty) and `pinput` OTP entry (`pubspec.yaml:64`).
  2. **Copy/Paste Recovery Kit Bug Fix (`:597` vs `:172`):** Update `unlockVaultAndFinish()` parser to strip numbered prefixes (`RegExp(r'\b\d{1,2}[.)]\s*')` or extract alphabetic words `[a-z]+`) so pasting `"1. acorn\n2. alder..."` works 100% of the time!
  3. **Passphrase Strength Meter:** Subtle 4-segment progress strip (`Weak` / `Fair` / `Good` / `Strong` via length + character diversity) beneath `Passphrase` field + `errorContainer` banner (`"Lose your passphrase and recovery kit = lose your library"`). Confirm field gets its own show/hide toggle.
  4. **Half-Created Vault Recovery:** Check `vaultApi.getStatus()` before calling `createVault()` in `createVaultAndFinish()`, or unlock with the entered passphrase if `vault.json` already exists from an interrupted `ensureVaultChannels()` attempt!
  5. **Permission Priming Card:** After vault setup/unlock and before calling `requestGalleryPermission()`, render a clear calm card explaining why Ambry needs Photos, Videos, and Media Location access (`"Grant access"` → `requestGalleryPermission()` → `TabShellRoute`).
- **States:** Inline top-of-card `AmbryBanner` error translating `PlatformException` codes (`TIMEOUT` → network retry prompt, `WRONG_SECRET` → passphrase mismatch, `TELEGRAM_400` → invalid phone/code) + `"Retry"` on `starting`/`closed`; `FilledButton` spinner uses `onPrimary` color.
- **Motion & A11y:** `AnimatedSwitcher` (`220ms`, `easeSpatial`, `12dp` slide) between steps; `AutofillHints` + `TextInputAction.next/done` on all fields; `GoogleSansCode` tabular indices `01`–`24` in 2-column × 12-row layout wrapping cleanly at 2.0× scale.

---

## 3. Navigation Shell & Top App Bar (`TabShellPage`, `ImmichSliverAppBar`)

- **Files:** `lib/pages/common/tab_shell.page.dart`, `lib/widgets/common/immich_sliver_app_bar.dart`
- **Layout:**
  - **Top Bar:** `ImmichSliverAppBar` (`0px` corner radius, `surface`, `scrolledUnderElevation: 1`), leading **`AmbryBrandMark`** (`26dp` rounded `ambry-logo.png` + `8dp` gap + `Ambry` in `titleLarge` `onSurface`, **removing `Icons.shield_outlined`**), trailing `_SyncStatusIndicator` (`onSurfaceVariant`) + compact tonal `_BackupIndicator` pill (`surfaceContainer` icon button showing warning/pause dot on `errorCount > 0` **OR** active-phone pause!) + `34dp` `UserCircleAvatar`.
  - **Bottom Nav (`NavigationBar`):** `68dp` height on `surfaceContainer` + `1dp` `outlineVariant` top hairline, `primaryContainer` indicator pill (`onPrimaryContainer` icon, `onSurfaceVariant` inactive), `12sp` labels (`Photos · Search · Albums · Library`).
- **Interactions & Fixes:**
  - Tab switch duration **`180ms`** (`AmbryMotion.dStandard`) `FadeTransition` (`0ms` if reduced motion).
  - Multi-select hides **both** portrait `_BottomNavigationBar` and landscape `NavigationRail` via `AnimatedSlide` + `AnimatedOpacity` (`180ms`).
  - `PopScope` (`:85-87`) updates `tabProvider.notifier.state = TabEnum.home` alongside `tabsRouter.setActiveIndex(0)`.
  - Remove `ref.invalidate(memoryLaneProvider)` on every Photos tab tap (`:113-115`)—only invalidate when day rolls over or pull-to-refresh runs.
  - Read-only mode: show subtle dismissible `AmbryBanner` (`"Read-only preview active — tap to exit"`) when active instead of silently greying out 3 tabs.

---

## 4. Photos Timeline (`MainTimelinePage`, `Timeline`, `MemoryLane`, `TimelineHeader`, `Scrubber`, `BaseBottomSheet`)

- **Files:** `main_timeline.page.dart`, `timeline.widget.dart`, `header.widget.dart`, `constants.dart`, `thumbnail_tile.widget.dart`, `thumbnail.widget.dart`, `scrubber.widget.dart`, `memory_lane.widget.dart`, `multi_select_status_button.widget.dart`, `base_bottom_sheet.widget.dart`, `stack.action.dart`

```text
┌────────────────────────────────────────────────────────┐
│ [Logo] Ambry                         (↻)  [☁✓]   (V)  │  <- ImmichSliverAppBar
├────────────────────────────────────────────────────────┤
│  ┌──────────────┐ ┌──────────────┐ ┌────────────┐      │
│  │  3 years ago │ │  5 years ago │ │ On this... │      │  <- MemoryLane (16dp edge pad,
│  │  [scrim AAA] │ │  [scrim AAA] │ │            │      │     bottom-only scrim!)
│  └──────────────┘ └──────────────┘ └────────────┘      │
│  November 2026                                         │  <- 56dp header (no check circle)
│  Sat, Nov 22                                           │  <- 48dp header
│  ┌────────┐┌────────┐┌────────┐┌────────┐              │
│  │        ││   0:30 ││        ││   [♡]  │              │  <- 2dp gutter, 0.58 scrim pill
│  │        ││ [▶0:30]││  ░░░░  ││   [☁]  │              │     shared shimmer ░░░░ on cold tile
│  └────────┘└────────┘└────────┘└────────┘     [ Nov ]═ │  <- Scrubber tonal pill + thumb
├────────────────────────────────────────────────────────┤
│   [ Photos ]     Search        Albums       Library    │  <- 68dp NavigationBar
└────────────────────────────────────────────────────────┘
```

- **Layout & Visual Refinements:**
  - **MemoryLane:** `16dp` outer horizontal padding, `10dp` spacing, `16dp` (`ImmichRadius.lg`) corners, **remove flat 20% `ColorFiltered` darken**, apply `scrimEditorial` bottom-only 4-stop gradient (`0 → 0.68`) so top 70% of cover photo is full brightness.
  - **TimelineHeader:** Eliminate `Padding(top: 8)` +6px overlap bug; tighten extents (`day = 48dp`, `month = 56dp`, `monthAndDay = 84dp`); month text `headlineSmall` `onSurface`, day text `titleSmall` `onSurfaceVariant`; **hide bulk-select circle until multi-select is active** (`AnimatedOpacity` + `AnimatedScale` `180ms`), while retaining tap/long-press on header to select bucket. Fix operator precedence on `topSliverWidgetHeight ?? 0 + appBarExpandedHeight` (`timeline.widget.dart:468`).
  - **Thumbnail & ThumbnailTile:** Use shared `AmbryShimmerScope` placeholder; fix `didUpdateWidget` clearing stale `_providerImage`; **error tile** shows subtle cloud-off / retry tap handler; video duration pill `rgba(0,0,0,0.58)` `rPill` + `11sp` tabular white text + `play_arrow_rounded`; storage & favorite icons backed by subtle dark halo (`blurRadius: 6`).
  - **Scrubber:** Tonal capsule thumb (`surfaceContainerHighest` + `outlineVariant` border, centered arrows fixing `_ArrowPainter` offset), `inverseSurface`/`onInverseSurface` floating date pill (`GoogleSansCode` year markers, `tabularFigures()`), `ValueNotifier` thumb offset (zero per-frame `setState`).
  - **Multi-Select Sheet (`BaseBottomSheet`):** Top radius `xl (20)`, `surfaceContainerLow`, `snap: true` (`[min, 0.45, 0.85]`), bottom `SafeArea`, dispose controller cleanly, **remove `StackAction` from all 4 sheets** (`stack.action.dart` gated `_serverless = true`). Fix `MultiSelectStatusButton` (`Directional`, remove `height: 2.5`, gate strictly on `isMultiSelectEnabled`).
- **States:**
  - *Gallery Permission Denied / Limited Banner:* Dismissible `AmbryBanner(warning)` pinned cleanly below `ImmichSliverAppBar` when `galleryPermissionNotifier` is `denied` / `permanentlyDenied` (`"Photo access is off — Ambry shows only backed-up vault photos. [Allow access]"`) or `limited` (`"Ambry can access selected photos only [Manage]"`). Also fix `DevicePermissionService._gallery` so denied `ACCESS_MEDIA_LOCATION` does **not** report full gallery denial!
  - *Empty Timeline:* `AmbryEmptyState` (`Icons.photo_library_outlined`, `"Your timeline is empty"`, `"Back up photos or grant device library access to get started"`, `"Open Backup"` CTA).
  - *Loading / Error:* Shared shimmer grid rows while buckets load; `AmbryErrorState` with `"Retry"` if segment `loadAssets` errors (fixing `snapshot.requireData` crash).

---

## 5. Photo & Video Viewer + Details Sheet (`AssetViewerPage`, `AssetPage`, `VideoControls`, `AssetDetails`)

- **Files:** `asset_viewer.page.dart`, `asset_page.widget.dart`, `viewer_top_app_bar.widget.dart`, `viewer_bottom_app_bar.widget.dart`, `bottom_bar.widget.dart`, `video_viewer.widget.dart`, `video_controls.dart`, `asset_details.widget.dart`, `asset_details/*.dart`, `exif_map.dart`, `map_thumbnail.dart`, `photo_view_core.dart`, `add_action_button.widget.dart`
- **Layout & Visual Refinements:**
  - **Canvas & Scrims:** True `#000000` canvas. Replace thin `black45 → black12` chrome scrims with smooth 4-stop `scrimViewer` (`0.62 → 0.32 → 0.08 → 0.0`) so white controls read at `>6:1` over snow/sky.
  - **Top Bar:** Circular `40dp` frosted `scrimPill` back button (inside `48dp` target; becomes `surfaceContainerHigh` circle when `showingDetails`), centered date + `tabularFigures()` time, Favorite + Motion + Kebab.
  - **Bottom Bar:** Unify `AddActionButton` onto `ImmichColumnButton` (replacing mismatched legacy `BaseActionButton`). Hide `DownloadStatusFloatingButton` when `showingDetails == true`.
  - **Video Controls:** Scope `SliderTheme` locally inside `VideoControls` (`trackHeight: 3.5`, `thumbRadius: 6`, `activeTrackColor: Colors.white`, `inactiveTrackColor: Colors.white38`), show known `asset.duration` immediately (`0:00 / 0:30` before player reports duration), add compact Mute/Unmute icon button, and show `Icons.play_arrow` / `Icons.pause` properly while buffering.
  - **Telegram Streaming & Error Feedback (Photos + Videos):**
    - *Remote photo upgrading:* Show quiet top-center `scrimPill` (`"Loading full resolution…"` with 12dp white spinner) only if upgrade takes `> 400ms` (keeps full zoomable thumbnail/preview visible underneath!).
    - *Remote photo offline / error:* **Keep loaded preview/thumbnail interactive & zoomable**; show subtle dismissible `scrimPill` banner (`"Offline — showing preview" [Retry]`), instead of `asset_page.widget.dart:393` wiping zoom with a bare icon!
    - *Remote video 4s Telegram start & error:* Immediately after `350ms` (replacing 1.2–1.6s dead silence), show a centered `scrimPill` (`"Streaming from Telegram…"` + spinner); add `VideoPlaybackStatus.error` + native error callback → show `"Could not stream video"` + `"Retry"` button instead of an infinite spinner.
  - **Details Sheet (`AssetDetails`):** `surfaceContainerLow`, top radius `xl (20)`, `36×4` `outlineVariant` drag handle, remove `BoxShadow` & double bottom inset, fix `SheetAssetDescription` controller/focus `dispose()`, **add Vault Status tile** (`"Encrypted in Telegram vault"` / `"Unencrypted in Telegram"` / `"On device only"`), **fix `ExifMap` pin bug** (`map_thumbnail.dart:102` drop `&& assetThumbhash != null` guard!), show `RatingDetails` locally (`KeepsakeLibrary` supports it!), surface `LocalAsset` GPS coordinates when present, and hide `"Add a location"` if read-only.
- **Gestures & Motion Fixes:** Include `PhotoViewScaleState.originalSize` in `_isZoomed` (`asset_page.widget.dart:300`); focal-point double-tap zoom; upward-clamped drag-to-dismiss preserving `showingControls` on cancel + `selectionClick()` at `80dp` / `650px/s` fling; reset `isPlayingMotionVideoProvider` on page change.

---

## 6. Slideshow, Download Info & Asset Troubleshoot

- **`SlideshowPage` (`slideshow.page.dart`, `slideshow_slide.widget.dart`, `slideshow_controller.dart`, `slideshow_progress_bar.widget.dart`):**
  - Use dark theme overlay for `AppBar` (`#0C0C0E` / white icons—no white flash in light mode); fix `PhotoViewController()` leak (`:68`), `SlideshowProgressBar` div-by-zero (`:23`), unmounted `setState` (`:226`), and wait for `VideoPlaybackStatus != buffering` before starting the 5s slide countdown so Telegram videos aren't skipped before frame 1!
- **`DownloadInfoPage` (`download_info.page.dart`, `download_task_tile.dart`, `download_status_floating_button.widget.dart`):**
  - Fix `cancelDownload` so completed & failed tasks remove cleanly from `taskProgress`; fix FAB spinning on failed tasks (`status == running || enqueued`); show photo vs video icon based on filename/type; use unique `ValueKey(taskId)`; add `AmbryEmptyState` (`"No active downloads"`) and `"Retry"` on failed downloads.
- **`AssetTroubleshootPage` (`asset_troubleshoot.page.dart`):**
  - Cache DB futures in `useMemoized`, add `"Copy summary"` icon button, use readable byte units, and surface Ambry vault status (Telegram message presence, encryption mode, `.t`/`.p` cache state).

---

## 7. Search (`SearchPage` + Pickers)

- **Files:** `lib/presentation/pages/search/search.page.dart`, `paginated_search.provider.dart`, `local_search.repository.dart`, `lib/widgets/search/**`, `lib/routing/router.dart:126`
- **Layout:**
  - Top bar: Unified `AmbrySearchBar` (`rPill`, `surfaceContainerLow`, built-in clear `X` button) + clean text-mode chip/menu (`Filename`, `Description` — immediately re-runs search when toggled!).
  - Horizontal filter row (`16dp` padding, `8dp` gap): `Camera`, `Date`, `Media type`, `Star rating` (enable locally!), `Display options` + trailing `"Clear all"` pill when any filter is active. Each uses `SearchFilterChip` (`InkWell`, `rPill`, `primaryContainer` active).
  - **Zero-State Suggestions (Replacing Polaroid & Gradients):** Clean **2×2 Tonal Quick-Access Bento** (`Recently taken`, `Recently added`, `Videos`, `Favorites` on `surfaceContainerLow`, `r=16`, icon + label) + quiet caption explaining local search (`"Search filenames, descriptions, camera models, dates, and media types stored in your encrypted index"`).
- **Critical Bug & State Fixes:**
  - Set `maintainState: true` on `SearchRoute` (`router.dart:126`) so tab switches preserve results.
  - Fix `"Not in album"` SQL filter (`NOT EXISTS` on `remote_album_asset_entity`), pagination infinite loop on 100-item multiples (`nextPage: null` when `result == null`), `YearFilter` +23h59m59s overshoot (`search.page.dart:315`), `CameraPicker` loading/error/empty states & model reset.
  - Add `SearchState.error` → `AmbryErrorState` (`"Retry"`) and `AmbryEmptyState` (`"No matching photos"`, `"Clear filters"` CTA) + shared shimmer loading state.

---

## 8. Albums, Album Detail & Create Album (`AlbumsPage`, `RemoteAlbumPage`, `CreateAlbumPage`)

- **Files:** `album.page.dart`, `album_selector.widget.dart`, `album_tile.dart`, `remote_album.page.dart`, `remote_album_sliver_app_bar.dart`, `create_album.page.dart`, `new_album_name_modal.widget.dart`, `album_action_filled_button.dart`
- **Layout (`AlbumsPage` / `AlbumSelector`):**
  - `AmbrySearchBar` (`"Search albums"`) at top; Sort capsule (`_SortButton` with `InkWell`, no invisible `Icons.abc` dummy spacer) + labeled grid/list toggle icon with `Tooltip`.
  - **Editorial Grid (`_GridAlbumCard`):** Remove 1px border, `Card` box, and `0.7` aspect ratio! Render a **borderless `1:1` square rounded cover (`ImmichRadius.lg = 16`)** directly on `surface` (`surfaceContainer` placeholder with `photo_album_outlined`), followed below (`8dp` gap) by `titleSmall` album title (max 2 lines) + `labelMedium` `onSurfaceVariant` count (`"573 items"` — **eliminating `"• Owned"`!**). Add `bottom: 80` grid padding + `InkWell` + `onLongPress` quick menu (Rename / Delete).
  - **List Mode (`AlbumTile`):** `64×64` rounded (`12dp`) cover, clean title + item count (no `"• Owned"`), subtle trailing `chevron_right_rounded`, rounded (`12dp`) swipe-delete background + `try/catch` error snackbar. Cache thumbnail asset lookup outside `build()`.
- **States:** Distinguish initial loading (shimmer album cards), **0 albums empty state** (`AmbryEmptyState` `"No albums yet"` + `"Create album"` filled CTA), **search-no-match state** (`AmbryEmptyState` `"No albums match '$query'"` + `"Clear search"`), and error state.
- **Album Detail & Create Album Fixes:**
  - `RemoteAlbumPage`: fix `deleteAlbum` navigation (`pop()` instead of `pushRoute(AlbumsRoute())`!), fix stray `" • 0 items"` dot (`remote_album_sliver_app_bar.dart:232`), add body `AmbryEmptyState` (`"This album is empty"` + `"Add photos"` CTA), replace scroll `addPostFrameCallback(() => setState)`.
  - `CreateAlbumPage`: remove stacked duplicate `SliverAppBar` (`create_album.page.dart:58-81`), use normal scrolling form layout (zero 200px overflow!), add removable `×` chip badge on selected photo thumbnails, stop auto-filling `"Untitled"` on keyboard blur, add loading spinner on Create button, validate non-empty name in `NewAlbumNameModal`.

---

## 9. Library & Sub-Collections (`LibraryPage`, `Favorite/Archive/Trash/Recent/Video/Memory/LocalAlbums`)

- **Files:** `library.page.dart`, `{favorite,archive,trash,recently_taken,recently_added,video,memory_list,memory,local_album,local_timeline,asset_selection_timeline}.page.dart`, `memory_card.widget.dart`, `memory_epilogue.dart`, `memory_progress_indicator.dart`

```text
┌────────────────────────────────────────────────────────┐
│ [Logo] Ambry                         (↻)  [☁✓]   (V)  │  <- ImmichSliverAppBar
├────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  ♡          │  │  ▤          │  │  🗑          │     │  <- Balanced 3-Column Utility Bar
│  │  Favorites  │  │  Archived   │  │  Trash      │     │     (surfaceContainerLow, r=16)
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  [ Map preview centered on latest geotag / area ] │  │  <- Hero 160dp Places Card (r=16)
│  │  [📍 Places · View photo map ───────────────────] │  │     (taps straight to MapRoute!)
│  └──────────────────────────────────────────────────┘  │
│  ┌───────────────────────┐  ┌───────────────────────┐  │
│  │  ┌───────┬───────┐    │  │  ┌───────┬───────┐    │  │  <- Symmetric 2-Column Bento Row
│  │  │       │       │    │  │  │       │       │    │  │     (surfaceContainerLow, r=16;
│  │  ├───────┼───────┤    │  │  ├───────┼───────┤    │  │      inner r=12, no gradients!)
│  │  │       │       │    │  │  │       │       │    │  │
│  │  └───────┴───────┘    │  │  └───────┴───────┘    │  │
│  │  On this device       │  │  Memories             │  │
│  └───────────────────────┘  └───────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

- **Library Layout Fixes:**
  - **Balanced 3-Column Utility Row:** Favorites · Archived · Trash side-by-side (`Expanded`, `8dp` gap, `surfaceContainerLow`, `ImmichRadius.lg = 16`, icon stacked neatly above single-line `labelLarge`—wrapping gracefully at 2.0× scale). Eliminates stretched full-width Trash pill!
  - **1+2 Editorial Bento Grid:** Full-width **Places** card (`160dp` tall, `r=16`, centered on user's latest geotagged asset rather than hardcoded Oahu, Hawaii; graceful offline tile fallback; **routes directly to `MapRoute`** while `PlacePage` lacks city reverse geocoding!) + symmetric 2-column **On This Device** & **Memories** below using `LayoutBuilder` `constraints.maxWidth` (fixing landscape `NavigationRail` collapse!), `surfaceContainerLow` fill (no primary gradients!), uniform inner `12dp` thumbnail corners, `InkWell` ripple, safe `assets.firstOrNull`, and proper empty/error/permission states. Remove dead `sharedWithPartnerProvider` subscription (`:429`).
- **Sub-Collection Fixes:**
  - **Unified `AmbryEmptyState`** across `FavoritePage`, `ArchivePage`, `TrashPage`, `RecentlyTakenPage`, `RecentlyAddedPage`, `VideoPage`, `MemoryListPage`, `LocalAlbumsPage`, `LocalTimelinePage`, and clean fallback icon on empty `MesmerizingSliverAppBar`.
  - `TrashPage`: fix `topSliverWidgetHeight` (`72dp` / dynamic), disable Empty/Restore-all when empty.
  - `LocalAlbumsPage`: check `galleryPermissionNotifier` and render `"Allow photo access"` CTA when denied instead of `"No albums yet"`; replace raw stack trace (`:41`) with `AmbryErrorState`.
  - `MemoryPage` / `MemoryListPage`: fix hooks-in-loop (`:48`), repeated `build()` precache, `MemoryProgressIndicator` zero-tick crash, `MemoryEpilogue` unused curve & `displayMedium` button style, replace `ColorFiltered` with bottom `scrimEditorial` and expensive blur backdrop with obsidian radial scrim.

---

## 10. Places & Map (`MapPage`, `MapSettingsSheet`, `MapLocationPickerPage`)

- **Files:** `map.page.dart`, `place.page.dart`, `place_detail.page.dart`, `map_settings_sheet.dart`, `map.state.dart`, `map_location_picker.page.dart`, `map_bottom_sheet.widget.dart`, `server_info.provider.dart`
- **Fixes:**
  - **`MapPage`:** Replace hardcoded `Colors.indigo` floating buttons (`:42,57`) with tonal `surfaceContainer` / `onSurface` `IconButton.filledTonal` (wrapped in `SafeArea`, removing hardcoded `top: 70`).
  - **`MapSettingsSheet` & `MapState`:** Fix `MapState.operator ==` (`map.state.dart:33-35`) to include theme/favorite/archive/date fields so toggles actually rebuild UI; **remove leaked `"Include partner assets"` switch** (`map_settings_sheet.dart:68-72`).
  - **Offline & Dark Map:** Detect offline/load timeout cleanly and display a calm `scrimPill` `"Map tiles unavailable offline"` overlay; provide distinct dark vector style URL when dark theme is toggled (`server_info.provider.dart:25-26`, flagged in Phase 7).
  - **`MapLocationPickerPage`:** Update marker symbol when `"My location"` moves camera (`:43-53`), wrap top bar in `SafeArea` (`:103`), add tooltips. Fix `TimelineRepository._watchPlaceBucket` `GroupAssetsBy.none` crash (`place_detail.page.dart`).

---

## 11. Backup Hub & Sub-Pages (`BackupPage`, `BackupAlbumSelectionPage`, `BackupOptionsPage`, `UploadDetailPage`, `BackupAssetDetailPage`)

- **Files:** `backup.page.dart`, `backup_toggle_button.widget.dart`, `encrypt_uploads_tile.widget.dart`, `backup_info_card.dart`, `backup_album_selection.page.dart`, `album_info_list_tile.dart`, `backup_options.page.dart`, `backup_asset_detail.page.dart`, `upload_detail.page.dart`, `backup_settings.dart`

```text
┌────────────────────────────────────────────────────────┐
│ [←]  Back up                                      [⚙] │
├────────────────────────────────────────────────────────┤
│  [!] Active-Phone Banner (ONLY if another phone owns)  │  <- errorContainer + [Use this phone]
│  [!] Battery Optimization Banner (ColorOS / restricted)│  <- errorContainer + [Open settings]
│                                                        │
│  ┌─ Vault Summary Card (r=20, surfaceContainerLow) ──┐ │
│  │  Vault backup                    98% · All caught │ │
│  │  █████████████████████████████████████░           │ │  <- 4dp rounded bar
│  │  ───────────────────────────────────────────────  │ │
│  │     576          │      568       │       8       │ │  <- 3-column tabular figures
│  │    Total         │   Backed up    │   Remaining   │ │
│  │  ───────────────────────────────────────────────  │ │
│  │  Preparing 2 · Ready 6           View queue ›     │ │
│  └───────────────────────────────────────────────────┘ │
│                                                        │
│  VAULT PROTECTION & SOURCE (grouped surfaceContainerLow)│
│  ┌───────────────────────────────────────────────────┐ │
│  │ [☁] Back up to Telegram                   ( ●═══) │ │  <- Tonal active tint; Retry if error
│  │ ───────────────────────────────────────────────── │ │
│  │ [🔒] Encrypt before upload                 ( ●═══) │ │  <- Warning banner tint when OFF
│  │ ───────────────────────────────────────────────── │ │
│  │ [📁] Albums to back up · Camera         [ Select ]│ │
│  └───────────────────────────────────────────────────┘ │
│                                                        │
│  [i] Live uploads & queue                 View details ›│
└────────────────────────────────────────────────────────┘
```

- **Critical Structural & Trust Upgrades (`BackupPage`):**
  1. **Everything Key Sits Above the Fold:** Collapse the 3 stacked cards (`_TotalCard`, `_BackupCard`, `_RemainderCard`) into **one unified Vault Summary Card** (`ImmichRadius.xl = 20`, `surfaceContainerLow`, 4dp linear bar, 3-column `tabularFigures()` counters, live preparing sub-row only when hashing, `"View queue ›"` footer).
  2. **Calm `"All backed up"` State:** When `remainderCount == 0 && backupCount > 0`, show `successContainer` checkmark pill `"All backed up"` (no anxiety, no dead numbers).
  3. **Active-Phone Ownership Awareness (`getActiveDevice` + `claimVault`):** Fetch `activeDevice` on `BackupPage` too; if `!isThisDevice`, surface `AmbryBanner(error)` at top (`"Backups paused on this phone — active on <device>"` + `"Use this phone"` CTA) and disable `BackupToggleButton` cleanly until claimed.
  4. **ColorOS Battery Warning Fix:** Guard against `AsyncLoading` (`valueOrNull == null`) so it never flickers on unrestricted devices; place near top whenever `backupEnabled` is ON and unrestricted is OFF; offer direct `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` / App Info guidance; localize all strings; fix `showPermissionsDialog` `ctx.pop()` bug (`:227`).
  5. **Clean `BackupToggleButton` & `EncryptUploadsTile`:** Remove dead 8s controller, gradient border, and shadow from `BackupToggleButton`; sync switch directly from `ref.watch(appConfigProvider)` (never stale `_isEnabled`); tapping error subtitle opens `UploadDetailRoute` + offer `"Retry failed"` CTA. Show `EncryptUploadsTile` even before albums are picked; show loading state while `_encrypt == null`; shift card tint to `warningContainer` when OFF; make `"Turn off"` button in confirmation dialog `destructive` (`error`) and `"Keep encryption"` primary/tonal. Keep `WakelockPlus` active only while actively uploading!
- **Backup Sub-Pages:**
  - `UploadDetailPage`: Remove hardcoded 3rd dead skeleton slot (`childCount: 3` → actual `uploadItems.length`); display honest status instead of `"1 B • ..."`; surface `uploadStatus.error` inside `FileDetailDialog` + Retry; show `AmbryEmptyState` when idle.
  - `BackupAlbumSelectionPage`: Fix `PopScope` `user == null` trap (`:99-111`), add Close button to Info dialog (`:231`), add explicit overflow menu (`Include / Exclude / Clear`) on `AlbumInfoListTile` alongside double-tap, replace hardcoded `Colors.red[300]` & broken English toast string.
  - `BackupOptionsPage`: Make stateful (`ConsumerStatefulWidget` / `useRef`) so `"Network requirements changed"` queue-restart logic (`:21-69`) actually executes!
  - `BackupAssetDetailPage`: Add `AmbryEmptyState`, center spinner, cache filename futures, format friendly dates.

---

## 12. Vault & Account Hub (`ImmichAppBarDialog` → Modal Bottom Sheet)

- **File:** `lib/widgets/common/app_bar_dialog/app_bar_dialog.dart`, `app_bar_profile_info.dart`
- **Redesign:** Replace the cramped top-anchored `Dialog` + conflicting `Dismissible(down)` with a structured **Modal Bottom Sheet** (`surfaceContainerLow`, top `xl=20` corners, `36×4` drag handle, `SafeArea`):
  1. **Header Row:** `AmbryBrandMark` (`24dp` logo + `'Ambry'`) + muted `GoogleSansCode` version badge (`v1.0.0`) + `48×48dp` Close icon.
  2. **Vault Health Card (`surfaceContainer`, `r=16`):** `AppBarProfileInfoBox` (vault name in `onSurface`, Telegram handle in `onSurfaceVariant`), divider, and live **Vault Status**:
     - `"576 items in your private Telegram vault"` (with skeleton loader while fetching)
     - `"Library index backed up 2 h ago · up to date"` (`success` check) or `"Index changes waiting for daily backup"`
     - Explicit error/offline row if `activeDevice` check fails (no silent `onError: (_) => null` swallow!).
  3. **Active-Phone Banner (conditional):** `AmbryBanner(error)` with inline loading spinner on `"Use this phone"`.
  4. **Primary Actions Card:** `Free up space` (`cleaning_services_outlined`) & `Settings` (`settings_outlined`)—promoted **above** diagnostics!
  5. **Vault Maintenance & Diagnostics (Cleanly Separated / Collapsible `ExpansionTile`):** `Back up library index now`, `Run vault self-test` (structured pass/fail dialog), `App logs`, plus explicit `Read-only preview` switch (replacing hidden avatar long-press!).
  6. **Sign Out & Footer:** Calm `Sign out` row opening `ImmichConfirmDialog` explaining clearly that signing out **locks the encrypted vault on this phone** (requiring your passphrase or 24-word recovery kit to reopen) while keeping the Telegram session unless changed; awaits `logout()` with spinner then `replaceAll([LoginRoute()])`. Footer links (`Licenses · Source code · Privacy`) get `48dp` touch targets via `TextButton` / padded `InkWell`.

---

## 13. Free Up Space (`FreeUpSpaceSettings`, `CleanupPreviewPage`)

- **Files:** `lib/widgets/settings/free_up_space_settings.dart`, `lib/presentation/pages/cleanup_preview.page.dart`, `lib/providers/cleanup.provider.dart`, `lib/repositories/asset_media.repository.dart`
- **Layout & Trust Upgrades (3-Step + Keep Card):**
  - Keep collapsible `"Keep on device"` card (`surfaceContainerLow`, `r=16`, neutral icon/title—not orange!) + 3-step stepper (`Select cutoff` → `Scan` → `Review & remove`).
  - **Step 2 & 3:** Fix Keep-toggle step jump bug (`:115-120` only jump if `selectedDate != null`); show `"Scanning your library…"` label while scanning; surface **reclaimable byte total (`1.42 GB`)** prominently inside Step 3 summary AND `_DeleteConfirmationDialog`! Hide Step 3's red border container when collapsed.
  - **Honest Platform Copy (Android < 12 / SDK < 31):** Detect Android SDK level (`device_info_plus` already in `pubspec.yaml:20`); on SDK ≥ 31 show `"Move to device trash"` (`Icons.delete_outline_rounded`, noting 30-day Android bin recovery); on SDK < 31 be 100% honest: `"Permanently delete from phone"` (`Icons.delete_forever_rounded`, explaining copies remain in your Telegram vault).
  - **Error & Cancel Handling:** Wrap `_scanAssets()` and `_deleteAssets()` in `try/catch` (`AmbryErrorState` / snackbar on failure); if user denies the Android bin confirmation prompt (`deleted == 0`), preserve `assetsToDelete` and show a calm `"No phone copies were removed"` notice instead of wiping state silently (`cleanup.provider.dart:151`)!
  - **Success Dialog & Preview:** Use `ImmichColors.success` checkmark in `_DeleteSuccessDialog` (not orange!), pop cleanly back to `Backup` / `Settings` (avoid jarring `popUntilRoot`), and add a reclaimable-size header bar to `CleanupPreviewPage`.

---

## 14. Settings, Sync Status, App Logs & Share Intent

- **Settings (`lib/pages/common/settings.page.dart`, `packages/ui/lib/src/components/settings/settings_card.dart`, `lib/widgets/settings/**`):**
  - Update `SettingsCard`: `surfaceContainerLow` fill, `ImmichRadius.lg (16)`, `40×40` tonal badge (`surfaceContainerHigh` + `primary` icon), **`onSurface` title (never orange!)**, `onSurfaceVariant` subtitle, subtle trailing `chevron_right_rounded`.
  - Order sections intentionally by user frequency: `Backup`, `Free up space`, `Photo grid`, `Asset viewer`, `Preferences`, `Notifications`, `Language`, `Sync status`, `Advanced`.
  - Fix `PrimaryColorSetting` sheet (`StatefulBuilder` / `Consumer` so toggles update live, drag handle, `SafeArea`, accessible swatch `Semantics`), `LanguageSettings` (replace gradient search bar with `AmbrySearchBar`), `SyncStatusAndActions` (cache `loadCounts()` outside `build()`, export `'ambry_export_$ts.sqlite'`, remove `Icons.arrow_back_ios_rounded` on `SyncStatusPage`), `BackupSettings` (use `SettingsSwitchListTile` / `SettingsSliderListTile`, fix nested `ListView`), `SettingsSliderListTile` (wire dead `enabled` param), and unify Haptics preference onto Drift `settingsProvider`.
- **App Logs (`app_log.page.dart`, `app_log_detail.page.dart`):**
  - Standard Material AppBar, search + level filter chips (`All`, `Warning`, `Error`), loading shimmer, `AmbryEmptyState`, confirm dialog + awaited `clearLogs()` fix, export `'Ambry_log_$ts.log'`, full-width detail cards with timestamp, level badge, and copyable source info.
- **Share Intent (`share_intent.page.dart`, `share_intent_upload.provider.dart`):**
  - Replace leaked `telegram://keepsake` subtitle (`:63`) with `"Share to Ambry Vault"`; fix light-mode white video icon (`:95`) and disabled empty selection (`:132`).
  - Surface actual `errorMessage` cleanly via `AmbryBanner` (`ShareIntentUploadStateNotifier` `:75` currently drops it!)—and flag in Phase 7 whether to implement native vault upload for shared files or remove the `ACTION_SEND` intent filter from `AndroidManifest.xml` until supported.
