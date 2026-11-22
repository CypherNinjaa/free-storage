# Phase 4 — Implementation-Ready Design System

> **Reuse Mandate:** Map every token onto Ambry's existing theme & UI layers—`lib/constants/colors.dart`, `lib/theme/color_scheme.dart`, `lib/theme/theme_data.dart`, and `packages/ui/lib/src/{constants.dart,theme.dart,snackbar.dart,components/**}` (`immich_ui`)—rather than creating duplicate token classes.

---

## 1. Color System

### 1.1 Core `ColorScheme` Tokens (Light *Sunlit Paper* & Dark *Obsidian Alcove*)
Replaces the generated blue-gray/lavender M3 seed neutrals on `ImmichColorPreset.indigo` (`lib/theme/color_scheme.dart:6-14`) and updates `decolorizeSurfaces` (`lib/theme/theme_data.dart:122-153`) to use the same warm-neutral scale. Note that `colorfulInterface` remains `true` by default so user presets (`DeepPurple`, `DynamicTheme`, etc.) still harmonize gracefully when explicitly chosen in Preferences.

| `ColorScheme` Property | Light (*Sunlit Paper*) | Dark (*Obsidian Alcove*) | Semantic Role |
|---|---|---|---|
| `brightness` | `Brightness.light` | `Brightness.dark` | Theme mode |
| `surface` | `#FAF9F7` | `#0C0C0E` | Primary scaffold, timeline & page background |
| `surfaceContainerLowest` | `#FFFFFF` | `#060607` | Crisp elevated cards / inner previews |
| `surfaceContainerLow` | `#F4F2EE` | `#141417` | Grouped cards, settings rows, search pill, modal bottom sheets |
| `surfaceContainer` | `#ECE9E3` | `#1C1C20` | Bottom `NavigationBar`, dialogs, menus, placeholder base |
| `surfaceContainerHigh` | `#E4E0D8` | `#25252A` | Filter chips, active input fill, shimmer highlight |
| `surfaceContainerHighest` | `#DBD6CC` | `#2F2F36` | Progress tracks, scrubber thumb, recovery word cells |
| `surfaceDim` | `#EAE6DE` | `#09090B` | Dimmed backdrops |
| `surfaceBright` | `#FFFFFF` | `#232328` | Bright surface container |
| `onSurface` | `#181715` | `#F2F0EC` | Primary headings, AppBar titles, list titles, body text |
| `onSurfaceVariant` | `#5E5952` | `#A4A098` | Subtitles, counts, date subheaders, inactive nav icons |
| `outline` | `#7B766E` | `#8E8A82` | Focused input borders, interactive control strokes |
| `outlineVariant` | `#E2DDD5` | `#2B2B31` | Subtle 1dp dividers, drag handles, hairline separators |
| `primary` | `#B8540F` | `#FDB44B` | Primary filled CTAs, selection checkmarks, active switches, vault shield |
| `onPrimary` | `#FFFFFF` | `#261400` | Text/icons inside `primary` buttons & active toggles |
| `primaryContainer` | `#FCE8D5` | `#462A08` | Active nav pill, selected filter chip, selection tile frame, trust badges |
| `onPrimaryContainer` | `#4A1F00` | `#FFE0B5` | Text/icons inside `primaryContainer` |
| `secondary` | `#6E5B47` | `#D6C2AC` | Secondary tonal emphasis (warm bronze) |
| `onSecondary` | `#FFFFFF` | `#3B2D1E` | Text/icons on `secondary` |
| `secondaryContainer` | `#F1E4D4` | `#4C3E2F` | Secondary chips, tonal action buttons |
| `onSecondaryContainer` | `#261A0C` | `#F1E4D4` | Text/icons inside `secondaryContainer` |
| `error` | `#BA1A1A` | `#FFB4AB` | Destructive CTAs, upload failure, battery/vault-lock alerts |
| `onError` | `#FFFFFF` | `#690005` | Text/icons on `error` |
| `errorContainer` | `#FFDAD6` | `#5C1111` | Error banners (ColorOS battery pause, active-phone pause, zero-knowledge warning) |
| `onErrorContainer` | `#410002` | `#FFDAD6` | Text/icons inside `errorContainer` |
| `inverseSurface` | `#2B2926` | `#EBE8E2` | Floating scrubber date pill, snackbars, tooltips |
| `onInverseSurface` | `#F5F3EF` | `#1C1B19` | Text inside `inverseSurface` pills & snackbars |
| `scrim` | `#000000` | `#000000` | Modal backdrop (`@ 0.45`) & full-screen viewer canvas |

### 1.2 Extended Semantic & Media Tokens (`ImmichColors` Extension)
Extend existing `ImmichColors` in `packages/ui/lib/src/theme.dart:46-103` (keeping `ImmichColors.harmonized(scheme)` fallback for dynamic/custom color presets, while passing exact Ambry values on the default theme):

| Token (`ImmichColors` field) | Light Value | Dark Value | Usage |
|---|---|---|---|
| `primaryText` | `#9E450A` | `#FDB44B` | Small clickable amber links/labels on `surfaceContainer*` (fixes `#B8540F` 4.02:1 shortfall on `surfaceContainer`) |
| `success` / `successContainer` / `onSuccessContainer` | `#1B6B3A` / `#D5F2DF` / `#0B3B1E` | `#7AD89A` / `#123B22` / `#C4F5D3` | Backup complete, self-test pass, cleanup complete |
| `warning` / `warningContainer` / `onWarningContainer` | `#8F4D00` / `#FCE5C4` / `#3A1E00` | `#FFCC80` / `#4A2C06` / `#FFE6BF` | Encryption-off warning, limited gallery access, cellular pause |
| `info` / `infoContainer` / `onInfoContainer` | `#1C5B99` / `#D8EAFC` / `#0A2C52` | `#8FC5FF` / `#133254` / `#D6EAFF` | Telegram API disclosure, local-only/sync notices |
| `mediaCanvas` | `#000000` | `#000000` | `AssetViewer`, `MemoryPage`, `SlideshowPage` background |
| `scrimPill` | `rgba(0,0,0,0.58)` | `rgba(0,0,0,0.58)` | Video duration badge, viewer "Streaming from Telegram…" pill, floating back button |
| `scrimEditorial` | `transparent → 0.08 → 0.36 → 0.68` black | `transparent → 0.08 → 0.36 → 0.68` black | Bottom-only cover scrim on `MemoryLane`, `MemoryCard`, `MemoryListPage`, `RemoteAlbumSliverAppBar` |
| `scrimViewer` | `0.62 → 0.32 → 0.08 → transparent` black | `0.62 → 0.32 → 0.08 → transparent` black | Top and bottom edge scrims in `ViewerTopAppBar` / `ViewerBottomBar` |

### 1.3 Verified WCAG 2.1 Contrast Table
All ratios computed using WCAG relative luminance $L$:

| Foreground on Background Pair | Hex Pair | Ratio | WCAG 2.1 Rating |
|---|---|---|---|
| **Light `onSurface` on `surface`** | `#181715` on `#FAF9F7` | **17.03:1** | AAA (Normal & Large) |
| **Light `onSurface` on `surfaceContainerLow`** | `#181715` on `#F4F2EE` | **16.02:1** | AAA |
| **Light `onSurface` on `surfaceContainerHigh`** | `#181715` on `#E4E0D8` | **13.61:1** | AAA |
| **Light `onSurfaceVariant` on `surface`** | `#5E5952` on `#FAF9F7` | **6.59:1** | AA (Normal & Large) |
| **Light `onSurfaceVariant` on `surfaceContainerLow`** | `#5E5952` on `#F4F2EE` | **6.21:1** | AA |
| **Light `onSurfaceVariant` on `surfaceContainerHigh`** | `#5E5952` on `#E4E0D8` | **5.27:1** | AA *(tuned from `#635F58`)* |
| **Light `onPrimary` on `primary`** | `#FFFFFF` on `#B8540F` | **4.87:1** | AA |
| **Light `primary` on `surface`** | `#B8540F` on `#FAF9F7` | **4.63:1** | AA |
| **Light `primaryText` on `surfaceContainer`** | `#9E450A` on `#ECE9E3` | **5.24:1** | AA *(use for small links on containers)* |
| **Light `onPrimaryContainer` on `primaryContainer`** | `#4A1F00` on `#FCE8D5` | **11.86:1** | AAA |
| **Light `onErrorContainer` on `errorContainer`** | `#410002` on `#FFDAD6` | **13.26:1** | AAA |
| **Light `onSuccessContainer` on `successContainer`** | `#0B3B1E` on `#D5F2DF` | **10.61:1** | AAA |
| **Light `onWarningContainer` on `warningContainer`** | `#3A1E00` on `#FCE5C4` | **12.55:1** | AAA |
| **Light `onInfoContainer` on `infoContainer`** | `#0A2C52` on `#D8EAFC` | **11.43:1** | AAA |
| **Light `outline` on `surfaceContainerLow`** | `#7B766E` on `#F4F2EE` | **4.03:1** | AA Non-text UI (`≥3.0:1`) |
| **Dark `onSurface` on `surface`** | `#F2F0EC` on `#0C0C0E` | **17.17:1** | AAA |
| **Dark `onSurface` on `surfaceContainerHigh`** | `#F2F0EC` on `#25252A` | **13.40:1** | AAA |
| **Dark `onSurfaceVariant` on `surface`** | `#A4A098` on `#0C0C0E` | **7.50:1** | AAA |
| **Dark `onSurfaceVariant` on `surfaceContainerHigh`** | `#A4A098` on `#25252A` | **5.85:1** | AA |
| **Dark `primary` on `surface`** | `#FDB44B` on `#0C0C0E` | **10.99:1** | AAA |
| **Dark `onPrimary` on `primary`** | `#261400` on `#FDB44B` | **9.98:1** | AAA |
| **Dark `onPrimaryContainer` on `primaryContainer`** | `#FFE0B5` on `#462A08` | **10.40:1** | AAA |
| **Dark `onErrorContainer` on `errorContainer`** | `#FFDAD6` on `#5C1111` | **10.53:1** | AAA |
| **Dark `onSuccessContainer` on `successContainer`** | `#C4F5D3` on `#123B22` | **10.36:1** | AAA |
| **Dark `outline` on `surfaceContainerLow`** | `#8E8A82` on `#141417` | **5.35:1** | AA |
| **White overlay text on `scrimPill` over `#FFFFFF` photo** | `#FFFFFF` on `black@0.58` over `#FFFFFF` (`#6B6B6B`) | **5.33:1** | AA *(vs. 2.84:1 FAIL on old `red[300]`)* |
| **White title on `scrimEditorial` max stop over `#FFFFFF` photo** | `#FFFFFF` on `black@0.68` over `#FFFFFF` (`#525252`) | **7.81:1** | AAA |

### 1.4 Amber Restraint Rule
- **Allowed:** Filled primary buttons (`Continue`, `Create Vault`, `Allow access`), active bottom-nav icon inside `primaryContainer` pill, active toggle switches, photo/album selection checkmarks, vault-protection shield icon (`verified_user_rounded` when encrypted), active progress bar fill.
- **Forbidden:** AppBar titles & icons (`AppBarTheme`), Settings card titles/subtitles, SnackBar content text, search bar fills/gradients, card outlines, Cancel buttons, and Success/Error indicators.

---

## 2. Typography (`GoogleSans` & `GoogleSansCode`)

Normalizes the inverted `TextTheme` in `lib/theme/theme_data.dart:49-56` while preserving bundled font families (`pubspec.yaml:131-151`).

| Flutter `TextTheme` Role | Font Family | Size / Line Height | Weight | Tracking | Primary Usage |
|---|---|---|---|---|---|
| `displayLarge` | `GoogleSans` | `36sp / 44sp` (`1.22`) | `w600` | `-0.5` | Reserved for rare hero metrics (e.g., reclaimable GB) |
| `displayMedium` | `GoogleSans` | `28sp / 36sp` (`1.29`) | `w600` | `-0.4` | Album detail expanded hero title |
| `displaySmall` | `GoogleSans` | `24sp / 32sp` (`1.33`) | `w600` | `-0.3` | Reserved display sub-hero |
| `headlineMedium` | `GoogleSans` | `24sp / 32sp` (`1.33`) | `w600` | `-0.4` | Onboarding titles, Memory fullscreen title, empty-state hero |
| `headlineSmall` | `GoogleSans` | `20sp / 28sp` (`1.40`) | `w600` | `-0.25` | Month timeline headers, section titles, bottom sheet headers |
| `titleLarge` | `GoogleSans` | `20sp / 26sp` (`1.30`) | `w600` | `-0.2` | `Ambry` brand wordmark & AppBar page titles (`onSurface`) |
| `titleMedium` | `GoogleSans` | `16sp / 22sp` (`1.38`) | `w600` | `-0.1` | Settings card titles, Backup card titles, Dialog titles |
| `titleSmall` | `GoogleSans` | `14sp / 20sp` (`1.43`) | `w600` | `0.0` | Day timeline subheaders, album grid titles, quick tiles |
| `bodyLarge` | `GoogleSans` | `15sp / 22sp` (`1.47`) | `w400` | `0.0` | Primary body copy, disclosures, dialog descriptions |
| `bodyMedium` | `GoogleSans` | `14sp / 20sp` (`1.43`) | `w400` | `0.1` | Settings subtitles, helper copy, alert banner text |
| `bodySmall` | `GoogleSans` | `12.5sp / 18sp` (`1.44`) | `w400` | `0.15` | Disclaimers, secondary EXIF metadata, legal footer |
| `labelLarge` | `GoogleSans` | `14sp / 20sp` (`1.43`) | `w600` | `0.1` | Button labels, filter chip labels, active tab labels |
| `labelMedium` | `GoogleSans` | `12sp / 16sp` (`1.33`) | `w500` | `0.2` | Nav bar labels, viewer timestamps, album item counts (`tabularFigures`) |
| `labelSmall` | `GoogleSans` | `11sp / 14sp` (`1.27`) | `w600` | `0.25` | Video duration pills, tiny status badges (`tabularFigures`) |
| **Monospace Style** | `GoogleSansCode` | `13–14sp / 18–20sp` | `w500–w600` | `0.0` | 24-word recovery grid & index numbers (`01`–`24`), scrubber year markers, EXIF specs, log stack traces, app version |

- **Tabular Numerals Mandate:** Apply `fontFeatures: [FontFeature.tabularFigures()]` on every numeric counter (`Total`/`Backed up`/`Remaining`), video scrubber clock (`0:04 / 0:30`), viewer date/time header, download percentages, and MB/GB reclaim totals so text never jitters during live updates.
- **Dynamic Type (`TextScaler` up to 2.0×):** Never wrap text inside fixed-height `SizedBox` containers (`CreateAlbumPage` 200px `PreferredSize`, `TimelineHeader` overflow). Use `ConstrainedBox(minHeight: ...)` and allow multi-line wrap with `Flexible`/`Expanded`.
- **Mandatory Callsite Migration:** Updating `displayMedium`/`displaySmall` from `14px`/`12px` to M3 sizes (`28px`/`24px`) **must** simultaneously migrate `ScaffoldErrorBody` (`scaffold_error_body.dart:20,37` → `titleMedium` / `bodyMedium`) and `MemoryEpilogue` (`memory_epilogue.dart:61` → `labelLarge` / `titleSmall`), and update `MultiSelectStatusButton` (`height: 2.5` hack removed).

---

## 3. Spacing, Radii, Elevation & Iconography

### 3.1 Spacing Scale (`packages/ui/lib/src/constants.dart` `ImmichSpacing`)
Reuse `ImmichSpacing` verbatim plus `kTimelineSpacing = 2.0`:
- `kTimelineSpacing = 2.0`: Photo grid gutter (`MainTimelinePage`, search results, album photos).
- `ImmichSpacing.xs = 4.0`: Inline icon/badge gaps, tight pill padding.
- `ImmichSpacing.sm = 8.0`: Chip gaps, card grid gaps, list vertical gaps.
- `ImmichSpacing.md = 12.0`: Card internal element spacing, section micro-gaps.
- `ImmichSpacing.lg = 16.0`: **Standard screen horizontal margin**, card padding, bottom sheet horizontal inset.
- `ImmichSpacing.xl = 24.0`: Vertical section spacing, dialog padding, onboarding step gaps.
- `ImmichSpacing.xxl = 32.0`: Bottom scroll breathing room, empty state inner padding.
- `ImmichSpacing.xxxl = 48.0`: Minimum touch target & hero vertical anchors.

### 3.2 Consolidated Corner Radii (`packages/ui/lib/src/constants.dart` `ImmichRadius`)
Eliminate all 11 ad-hoc radii (`4, 5, 8, 10, 12, 15, 16, 18, 18.5, 20, 24, 25`) into **4 primary tiers + progress hairline**:

| Tier | Token (`ImmichRadius`) | Value | Exact Mapping |
|---|---|---|---|
| Hairline Track | `ImmichRadius.xs` | `4.0` | Linear progress bars, upload queue tracks, slider track caps |
| Compact | `ImmichRadius.sm` | `8.0` | Recovery-word cells, compact status pills, snackbars, `26dp` logo clip (`6.0` optional or `sm`) |
| Input & Tile | `ImmichRadius.md` | `12.0` | Text fields (`ImmichThemeProvider` default), list thumbnails (`64×64`), dropdown menus, selected photo inset (`12.0`), skeleton rows |
| Media & Card | `ImmichRadius.lg` | `16.0` | `1:1` Album grid covers, `MemoryLane` / `MemoryListPage` covers, `AmbryBanner`, `SettingsCard`, `ExifMap`, `LibraryPage` bento cards |
| Sheet & Dialog | `ImmichRadius.xl` | `20.0` | Modal bottom sheets (top corners), `BaseBottomSheet` (top corners), `ConfirmDialog`/`AlertDialog`, unified Vault Summary card |
| Full Pill | `ImmichRadius.full` (`999`) | Pill / Circle | `AmbrySearchBar`, `SearchFilterChip`, `ImmichTextButton`, video duration `scrimPill`, drag handle (`36×4`), floating viewer back button |

### 3.3 Elevation (`ImmichElevation`)
- `ImmichElevation.none (0.0)`: **Default** for all cards, tiles, sheets, banners, and AppBars at rest (separated via tonal `surfaceContainer*` contrast instead of shadows or `1px` borders).
- `ImmichElevation.xs (1.0)`: Scrolled `SliverAppBar` subtle tonal separation (`scrolledUnderElevation: 1.0`, `surfaceTintColor: Colors.transparent`, relying on `surfaceContainerLow` shift).
- `ImmichElevation.sm (2.0)`: Floating menus (`MenuAnchor`), `Scrubber` capsule thumb and floating date pill.
- **Zero colored drop shadows** anywhere (`BackupToggleButton` shadow removed; `AssetDetails` shadow replaced by `surfaceContainerLow` tone).

### 3.4 Iconography
- **Family:** Standard Material Rounded (`Icons.*_rounded` filled for active/selected/trust anchors; `Icons.*_outlined` or non-filled `*_rounded` for default/inactive chrome).
- **Eliminate:** All iOS-specific icons (`arrow_back_ios_rounded`, `arrow_back_ios_new_rounded`, `arrow_forward_ios`) and mismatched `*_sharp` icons (`MemoryEpilogue`).
- **Sizing (`ImmichIconSize`):** `xs (16)` inside duration/status badges & inline meta; `sm (20)` trailing chevrons, input prefixes, sheet list tiles; `md (24)` standard AppBar/NavBar/button icons; `lg (32)` feature/empty-state inner badge icons inside `64dp` tonal circles.

---

## 4. Component Specifications

| # | Component & File Target | Visual Tokens & Geometry | States & Behavior | Accessibility |
|---|---|---|---|---|
| 1 | **App Bars** (`ImmichSliverAppBar`, `AppBarTheme`, `SelectionSliverAppBar`, `RemoteAlbumSliverAppBar`, `MesmerizingSliverAppBar`) | `backgroundColor: surface`, `foregroundColor: onSurface`, **0px corner radius** (remove `5px` shape!). Leading brand: `AmbryBrandMark` (`26dp` `ambry-logo.png` + `titleLarge` `'Ambry'` in `onSurface`). Trailing: sync spinner (`onSurfaceVariant`), compact tonal backup pill (`surfaceContainer` + status icon / error badge), `34dp` avatar. | Multi-select: `SliverAnimatedOpacity` (`180ms`) fades AppBar out cleanly; `SelectionSliverAppBar` uses `surfaceContainer` (`0px` corners), neutral close, primary `Done` enabled only when `count > 0`. | All icon buttons `48×48dp` with explicit `tooltip`/`Semantics`; `centerTitle: false` for root tabs and subpages. |
| 2 | **Bottom Navigation & Rail** (`lib/pages/common/tab_shell.page.dart`) | Portrait `NavigationBar`: height `68dp` (+ bottom inset), `backgroundColor: surfaceContainer`, top `1dp` `outlineVariant` divider, `indicatorColor: primaryContainer`, selected icon `onPrimaryContainer`, unselected `onSurfaceVariant`, `labelMedium` (`12sp w500` active/inactive). Landscape `NavigationRail` on `surfaceContainer`. | **Animated hide on multi-select** (`AnimatedSlide` + `AnimatedOpacity`, `180ms`) for **both** portrait bar and landscape rail. `PopScope` updates `tabProvider`. | `NavigationDestination` labels never ellipsize abruptly at 1.3× scale (`NavigationBarThemeData` wraps cleanly). |
| 3 | **Bottom Sheets** (`BaseBottomSheet`, modal sheets) | `backgroundColor: surfaceContainerLow`, `shape: RoundedRectangleBorder(top: ImmichRadius.xl (20))`, `elevation: 0`, top drag handle `36×4dp` `outlineVariant` (`rPill`, `12dp` top/bottom margin), mandatory bottom `SafeArea(top: false)`. | `DraggableScrollableSheet(snap: true, snapSizes: [min, 0.45, 0.85])`, disposes internal controller cleanly, auto-expands when search focuses, auto-collapses (`min`) when scrolling timeline. | `Semantics(label: 'Drag handle')` + tap-accessible collapse/close; modal sheets dim backdrop with `scrim @ 0.45`. |
| 4 | **Dialogs** (`ImmichConfirmDialog` in `packages/ui`) | `backgroundColor: surfaceContainer`, `ImmichRadius.xl (20)`, `elevation: 0`, title `titleMedium`, content `bodyMedium` (`onSurfaceVariant`). | `Cancel`: ghost `ImmichTextButton` (`onSurfaceVariant`, **never red/orange**). Confirm: `filled` `primary` (standard) or `error` (`onError` on `error`, destructive). Awaits async `Future<void> Function()` with inline loading spinner before popping. | Barrier dismissible only when `!isLoading`; clear action verbs (`"Turn off"`, `"Delete"`, `"Lock & sign out"`). |
| 5 | **Chips** (`SearchFilterChip`, status chips) | Height `36dp` visual inside `48dp` touch target (`MaterialTapTargetSize.padded`), `rPill`, `padding: h14 v6`, `18dp` icon + `6dp` gap + `labelLarge`. Default: `surfaceContainerLow` + `1dp` `outlineVariant`. Active: `primaryContainer` + `onPrimaryContainer` (no border). | Built with `InkWell` (ripple!) instead of `GestureDetector`; active value ellipsis-truncated (`maxWidth: 180dp`). | `Semantics(button: true, selected: isActive, label: ...)`; AA contrast `11.86:1` light / `10.40:1` dark. |
| 6 | **Search Bar** (`AmbrySearchBar` in `packages/ui`, replacing `SearchField` & 3 gradient bars) | `rPill`, `surfaceContainerLow` fill (no gradient, no orange wash), `outlineVariant` `1dp` stroke at rest → `outline` `1.5dp` on focus, `16dp` horizontal padding, `onSurfaceVariant` search icon, built-in `Icons.clear_rounded` button when `text.isNotEmpty`. | `TextInputAction.search`; optional trailing mode menu button (`MenuAnchor`). | `48dp` minimum height, `48×48dp` clear button target, screen-reader hint matches active mode. |
| 7 | **Buttons** (`ImmichTextButton` in `packages/ui`) | Variants: `filled` (`primary`/`onPrimary`), `tonal` (`primaryContainer`/`onPrimaryContainer`), `outlined` (`transparent` + `outline`), `ghost` (`transparent`, `primaryText` / `onSurfaceVariant`), `destructive` (`error`/`onError`). Shape `rPill`, min height `48dp`. | Built-in `isLoading` disables taps and renders `18dp` `CircularProgressIndicator(strokeWidth: 2)` matching exact `foregroundColor` (fixing invisible spinners!). | Never clips multi-word labels at 2.0× `TextScaler` (`Flexible` + `padding: v12 h20`). |
| 8 | **Photo Tile** (`ThumbnailTile`) | Tight `2dp` grid gutter (`kTimelineSpacing`), `RepaintBoundary`, `BoxFit.cover`, `AmbrySkeletonBox` shimmer placeholder while loading. | `140ms` `Curves.easeOutCubic` reveal when async; instant on RAM hit. Storage badge (bottom-right, when enabled) & Favorite heart (bottom-left) use `14dp` white icon with soft dark halo (`Shadow(blurRadius: 6, black@0.7)`). Error tile shows `cloud_off` / `broken_image` + tap-to-retry. | `Semantics(image: true, label: '${asset.type} from ${date}, ${storageState}')`. |
| 9 | **Video Tile** (`ThumbnailTile` video overlay) | Top-right or bottom-right capsule (`scrimPill` `rgba(0,0,0,0.58)`, `rPill`, padding `h6 v2`), `12dp` `play_arrow_rounded` + `labelSmall` (`11sp w600 white`, `tabularFigures()`). | Hides cleanly during Hero flight (`_Fade` `150ms`); respects `MediaQuery.textScaler` cleanly up to 1.5× inside capsule. | Combined in tile semantics (`"Video, duration 0:30"`). |
| 10 | **Date Header** (`TimelineHeader`) | Tightened heights (no `Padding(top: 8)` overflow!): `day = 48dp` (`titleSmall` `onSurfaceVariant`), `month = 56dp` (`headlineSmall` `onSurface`), `monthAndDay = 84dp`. Horizontal padding `lg (16dp)`. | Bulk-select `check_circle_outline_rounded` **hidden at rest**; animates in (`180ms` opacity + scale) ONLY when `multiSelectProvider.isEnabled`! Long-pressing header still enters multi-select. | Header exposes `"Select all items for <date>"` action in TalkBack. |
| 11 | **Selection State** (`_RenderSelectionFrame`) | Tile deflates `6dp` on all sides inside `primaryContainer` backing, inner clip radius `ImmichRadius.md (12)`, `22dp` top-left `check_circle_rounded` (`primary` check on `primaryContainer` halo). | `180ms` `Curves.easeOutCubic` shrink/radius animation; `mediumImpact` haptic on first long-press entry, `selectionClick` on subsequent toggles. | `Semantics(selected: isSelected)`. |
| 12 | **Album Card** (`_GridAlbumCard`, `AlbumTile`) | **Grid:** Borderless `1:1` square cover (`ImmichRadius.lg = 16`, `surfaceContainer` fallback + `photo_album_outlined`), `8dp` gap below to `titleSmall` (max 2 lines) + `labelMedium` (`onSurfaceVariant` `"573 items"`, **NO `"• Owned"`**). **List:** `64×64` rounded (`12dp`) cover, title + count, subtle trailing `chevron_right_rounded`. | Wrapped in `InkWell(borderRadius: 16)` (grid) or `ListTile` (list) with `onLongPress` quick actions (rename / delete) matching swipe-to-delete parity. | Combined `Semantics(button: true, label: '$name, $count items')`. |
| 13 | **Skeleton / Shimmer** (`AmbryShimmerScope` + `AmbrySkeletonBox` in `packages/ui`) | Base `surfaceContainerLow` → highlight `surfaceContainerHigh`, rounded via caller radius (`0` for grid tiles, `12`/`16` for cards). | **Single shared `AnimationController`** (`1200ms` linear repeat) in `AmbryShimmerScope` passed via `InheritedWidget`—zero per-tile tickers! Static `surfaceContainer` when `MediaQuery.disableAnimationsOf(context)` is true. | `ExcludeSemantics` on decorative skeleton boxes. |
| 14 | **Empty & Error States** (`AmbryEmptyState`, `AmbryErrorState` in `packages/ui`) | Centered column (`padding: xxl 32`), `64dp` tonal circle (`surfaceContainerHigh` or `errorContainer`), `32dp` icon (`onSurfaceVariant` or `error`), `titleMedium` title, `bodyMedium` concise explanation, primary or outlined `48dp` CTA (`"Create album"`, `"Retry"`, `"Open settings"`). | Replaces bare `ScaffoldErrorBody`, blank timelines, raw stack traces (`LocalAlbumsPage`, `PlacePage`), and misleading `"No albums yet"` when loading/error. | Scroll-safe (`SingleChildScrollView`) so 2.0× dynamic text never overflows. |
| 15 | **Banner / Warning Card** (`AmbryBanner` in `packages/ui`) | Variants: `info`, `warning`, `error`, `success` using `ImmichColors.*Container` / `on*Container`, `ImmichRadius.lg (16)`, padding `md/lg`, leading `24dp` icon + `titleSmall` + `bodySmall` + aligned action row (`TextButton`/`Tonal`). | Used for Active-Phone Pause (`error`), ColorOS Battery Pause (`error`), Encryption OFF (`warning`), Limited Gallery Access (`warning`), Free Up Space notices (`info`). | Full semantic region; avoids low-contrast tinted glass or raw `Colors.orange`. |
| 16 | **Progress Indicators** (Backup queue, Telegram streaming, Video scrubber) | **Backup bar:** `4dp` tall `LinearProgressIndicator(borderRadius: xs (4), color: primary, backgroundColor: surfaceContainerHighest)`. **Video scrubber (scoped in `VideoControls`):** `trackHeight: 3.5`, `thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6)`, `overlayShape: RoundSliderOverlayShape(overlayRadius: 16)`, active `Colors.white`, inactive `Colors.white38`, thumb `Colors.white`. **Telegram streaming pill:** `scrimPill` `rgba(0,0,0,0.58)` `rPill` capsule with `14dp` white spinner + `"Streaming from Telegram…"` (`labelMedium`, white). | Smooth determinate updates via `TweenAnimationBuilder` (`250ms`); clear error swap when stream fails. | `Semantics(value: ...)` on progress bars; video slider supports TalkBack seek increments. |
