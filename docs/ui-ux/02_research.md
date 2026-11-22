# Phase 2 — Competitive Benchmarks, Guidelines & Pattern Synthesis

> **Purpose:** Ground Ambry's redesign in real product patterns, official platform guidelines, and empirical accessibility standards—with explicit citations for every opened source.

---

## 1. Research Scope & Access Transparency

- **Paywalled / Login-Gated Libraries:**
  - **Mobbin** (`https://mobbin.com/`): Free accounts heavily restrict app views and block AI/text search, full user flows, and motion/animation recordings behind a Pro paywall.
  - **Page Flows** (which absorbed **Screenlane**, `https://pageflows.com/`): Annotated user-journey video recordings require a paid subscription/trial; only limited previews are public.
  - **Pttrns**: Categorized mobile pattern archives are largely paywalled.
- **Public Sources Actually Used:** Official design guidelines (`m3.material.io`, `developer.android.com`, `developer.apple.com`, `w3.org`), official product support/engineering/announcement pages (Google Photos, Apple Photos, Samsung, Ente, Immich, Amazon Photos, OneDrive, Proton Drive), authoritative Android/Apple coverage (`9to5google.com`), Evan Wallace's `thumbhash` spec, and public design community portals (Dribbble, Behance, Figma Community, Pinterest). **Zero observations were guessed or fabricated behind paywalls.**

---

## 2. Competitor Product Benchmarks

### 2.1 Google Photos (Android Reference Standard)
- **Sources:** [Google Photos Material 3 Expressive backup indicator (9to5Google)](https://9to5google.com/2025/08/05/google-photos-material-3-expressive-backup-indicator/), [Google Photos Collections tab redesign (9to5Google)](https://9to5google.com/2026/10/26/google-photos-collections-tab-redesign/), [Manage backup & photos help](https://support.google.com/photos/answer/6193316), [Grid & date navigation](https://support.google.com/photos/answer/9315511), [Collections / library organization](https://support.google.com/photos/answer/10694389).
- **Verified Patterns:**
  - **Wall-of-images grid + floating date pill:** Maximizes photography per viewport with tight gutters; replaces verbose headers during fast scroll with a crisp floating date capsule. Note the **documented UX tradeoff**: removing clear day/month headers altogether frustrated users scanning short ranges—keeping compact date headers *plus* a high-precision scrubber beats pure headerless walls.
  - **M3 Expressive persistent backup indicator:** Replaces subtle avatar rings with an unambiguous dynamic status pill (`"Preparing backup"` → `"Backing up N items"` with wavy M3 Expressive progress → `"Backup complete"`) that expands on tap into a live queue/action sheet.
  - **Customizable Collections hub (formerly Library):** Groups utilities (Favorites, Archive, Trash) cleanly at top with structured cards below, plus user control over clutter.

### 2.2 Apple Photos (Editorial Craft & Immersion)
- **Sources:** [iOS 18 announcement (Apple Newsroom, Jun 2024)](https://www.apple.com/in/newsroom/2024/06/10/ios-18-makes-iphone-more-personal-capable-and-intelligent-than-ever/), [iOS 18 release (Apple Newsroom, Sep 2024)](https://www.apple.com/in/newsroom/2024/09/ios-18-is-available-today-making-iphone-more-personal-and-capable-than-ever/), [Get started with Photos on iPhone (Apple Support)](https://support.apple.com/en-us/121115).
- **Verified Patterns & Cautionary Lesson:**
  - **Single-scroll vs. Tabs Lesson:** iOS 18 replaced the classic bottom tab bar with a unified vertical canvas (grid above, collections below) and tested an auto-rotating top Carousel in beta. **Heavy user pushback** forced Apple to delete the erratic Carousel before release and add deep customization/pinning in point updates. **Takeaway for Ambry:** Preserve the fast, predictable 4-tab muscle memory (`Photos / Search / Albums / Library`), and never put a restless auto-rotating hero above the grid.
  - **Content Deference & Editorial Covers:** Neutral chrome lets color come exclusively from photos; full-bleed covers use **bottom-only** gradient scrims (leaving the upper photo untouched); true-black media canvas with auto-hiding edge bars and matched swipe-down return to the grid slot.

### 2.3 Samsung Gallery (One UI 7 / One UI 8)
- **Sources:** [Samsung One UI 7 security, privacy & UX news](https://news.samsung.com/global/samsung-one-ui-7-enhances-security-and-privacy-in-the-age-of-ai-giving-users-greater-transparency-and-choice).
- **Verified Patterns:**
  - **One-handed reachability & rounded geometry:** Keeps primary navigation and utility pills (`Favorites`, `Trash`, `Archive`, `Videos`) balanced and symmetric inside rounded tonal containers (`One UI 7/8` visual language).
  - **Fluid pinch-to-zoom grid transitions:** Smoothly bridges day/month/year density levels without jarring frame jumps.

### 2.4 Ente Photos (Zero-Knowledge E2EE Benchmark)
- **Sources:** [Ente Architecture](https://ente.com/architecture/), [Ente Photos Features](https://help.ente.io/photos/features/), [Ente Recovery Key Guide](https://help.ente.io/photos/security/recovery-key/).
- **Verified Patterns:**
  - **Uncompromised Recovery Key Onboarding:** Generates a **24-word recovery phrase** immediately after account login, explains plainly that there is no server password reset, and pairs the phrase with explicit Copy/Save actions and mandatory confirmation before entering the gallery.
  - **Calm Privacy-First Gallery:** Proves zero-knowledge E2EE can feel warm and consumer-friendly—caching decrypted thumbnails securely on-device for instant grid scroll, running search/indexing locally, and surfacing backup/encryption confidence without alarmist jargon.

### 2.5 Immich (Ambry's Architectural Baseline)
- **Sources:** [Immich Architecture Overview](https://immich.app/docs/overview/architecture/), [ThumbHash Specification (Evan Wallace)](https://github.com/evanw/thumbhash).
- **Verified Patterns:**
  - Virtualized `SliverSegmentedList` + `FixedSegmentBuilder` + cancellable viewport image requests keep 10,000+ photo timelines smooth.
  - Upstream Immich embeds 21–28 byte **ThumbHash** placeholders in metadata (`github.com/evanw/thumbhash`) for instant aspect-ratio-preserving blur-up before network decode; **Ambry currently omits ThumbHash**, making perceived-performance placeholders during cold Telegram restores even more critical.

### 2.6 Amazon Photos
- **Sources:** [Amazon Photos new memory-centric look (About Amazon)](https://aboutamazon.com/news/devices/amazon-photos-has-a-new-look-built-around-memory).
- **Verified Patterns:**
  - Pairs memory/On-This-Day resurfacing cleanly at the top of the stream with simplified bottom navigation and persistent header backup status so users immediately know whether recent shots are safe.

### 2.7 OneDrive Photos
- **Sources:** [Microsoft Support — Photos & Camera Backup](https://support.microsoft.com/).
- **Verified Patterns:**
  - Account-hub drawer/sheet surfaces exact backup health and quota/sync state at a glance; clear per-device-folder backup selector (`Camera`, `Screenshots`, etc.) separates device folders from timeline streams.

### 2.8 Proton Drive Photos
- **Sources:** [How to enable Proton Drive Android photo backup](https://proton.me/support/drive-android-photo-backup), [Are my photos encrypted when using photo backup?](https://proton.me/support/are-photos-encrypted-photo-backup), [Proton Drive Android photo backup announcement](https://proton.me/blog/proton-drive-android-photo-backup), [Proton Drive Google Play listing](https://play.google.com/store/apps/details?id=me.proton.android.drive).
- **Verified Patterns:**
  - **Permission Priming & Clear Backup CTA:** Explains background E2EE backup plainly before requesting Android media permissions; lets users pick device folders explicitly.
  - **Honest Cryptographic Transparency:** Clearly communicates what stays encrypted (image/video bytes, filenames) vs. what enables chronological sorting (timestamps)—directly inspiring how Ambry should explain encrypted vs. plain-upload mode and local-only index encryption.
  - **Queue & Stall Counters:** Persistent item-count progress bar (`"Preparing"` vs. `"Remaining"`) reassures users during client-side hashing and encryption.

---

## 3. Official Platform & Accessibility Guidelines

### 3.1 Material Design 3 & M3 Expressive
- **Sources:** [M3 Motion Overview](https://m3.material.io/styles/motion/overview), [M3 Color Roles](https://m3.material.io/styles/color/the-color-system/color-roles), [M3 Type Scale Tokens](https://m3.material.io/styles/typography/type-scale-tokens), [M3 Corner Radius Scale](https://m3.material.io/styles/shape/corner-radius-scale), [M3 Elevation Overview](https://m3.material.io/styles/elevation/overview), [Navigation Bar](https://m3.material.io/components/navigation-bar), [Bottom Sheets](https://m3.material.io/components/bottom-sheets), [Search](https://m3.material.io/components/search), [Chips](https://m3.material.io/components/chips).
- **Key Rules Applied:**
  - **Tonal Containment Over Shadows:** Use the 5-tier surface hierarchy (`surfaceContainerLowest` → `surfaceContainerHighest`) rather than heavy outlines or drop shadows: `surface` for canvas, `surfaceContainerLow` for bottom sheets & grouped cards, `surfaceContainer` for navigation bar/dialogs, `surfaceContainerHigh`/`Highest` for interactive chips, inputs, and tracks.
  - **M3 Expressive Physics Springs:** Replaces fixed durations with two spring classes (**Spatial** for position/size/corners; **Effects** for opacity/color, critically damped `ζ = 1.0` with **zero overshoot**):

| Token Role | Standard Scheme Stiffness ($k$) | Standard Damping ($\zeta$) | Expressive Scheme ($k$ / $\zeta$) | Ambry Usage |
|---|---|---|---|---|
| **Fast Spatial** | `1400` | `0.9` | `800` / `0.6–0.8` | Selection tile inset, chip morph, checkmarks |
| **Default Spatial** | `700` | `0.9` | `380` / `0.6–0.8` | Bottom sheets, Hero photo flights, dismiss spring-back |
| **Slow Spatial** | `300` | `0.9` | `200` / `0.6–0.8` | Full-viewport layout expansions |
| **Fast Effects** | `3800` | `1.0` (no bounce) | `3800` / `1.0` | Viewer chrome fade, icon color transitions, image crossfade |
| **Default Effects** | `1600` | `1.0` (no bounce) | `1600` / `1.0` | Tab crossfades, onboarding step transitions |
| **Slow Effects** | `800` | `1.0` (no bounce) | `800` / `1.0` | Backdrop scrim fade during route transitions |

### 3.2 Android Design & Accessibility
- **Sources:** [Android Mobile Design](https://developer.android.com/design), [Edge-to-Edge Design](https://developer.android.com/design/ui/mobile/edge-to-edge), [Android Accessibility](https://developer.android.com/design/ui/mobile/accessibility).
- **Key Rules Applied:** Render media edge-to-edge beneath system bars with `WindowInsets` / `SafeArea` padding on controls; enforce **48 × 48 dp** minimum touch targets on every icon button, footer link, and tile badge; pair tactile state changes (selection, scrubber ticks, dismiss threshold) with subtle system haptics; supply explicit `Semantics` labels and predictable focus traversal.

### 3.3 Apple Human Interface Guidelines & WCAG 2.1
- **Sources:** [Apple HIG Root](https://developer.apple.com/design/human-interface-guidelines/), [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [Playing Haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Images](https://developer.apple.com/design/human-interface-guidelines/images); [WCAG 2.1](https://www.w3.org/TR/WCAG21/), [SC 1.4.3 Contrast (Minimum)](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html), [SC 1.4.11 Non-text Contrast](https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html).
- **Key Rules Applied:** Deference to content (chrome fades on tap); dynamic type layouts that wrap gracefully up to 2.0x without fixed-height clipping; `MediaQuery.disableAnimationsOf(context)` reduces spatial travel to instant fades; **WCAG AA** (`≥ 4.5:1` normal text, `≥ 3.0:1` large text & UI borders/icons) across **all** surfaces and photo scrims.

### 3.4 Public Design Portals (Dribbble, Behance, Figma Community, Pinterest)
- **Sources:** [Figma Learn — Photo Gallery Prototype](https://help.figma.com/hc/en-us/articles/25316886617495-Create-a-photo-gallery-prototype), [Figma Photo Sharing UI Kit](https://www.figma.com/file/jKrTKKXtPBuAsMAYePaKF7/Photo-Sharing-App-UI?node-id=0%3A1), [Behance Mobile Photo Gallery Projects](https://www.behance.net/search/projects?search=mobile%20app%20photo%20gallery), [Pinterest Photo Gallery UI Boards](https://www.pinterest.com/search/pins/?q=mobile%20app%20ui%20design%20photo%20gallery), [Dribbble](https://dribbble.com).
- **Critical Evaluation:** Public shots demonstrate strong editorial bento ratios, clean 1:1 album typography without card borders, and generous margin rhythm—**but** frequently rely on heavy multi-layer drop shadows, translucent glass blurs (costly in Flutter/Android at 120fps), and idealize 6-photo happy paths while ignoring 10,000-asset scrolling, offline Telegram latency, and empty/error states.

---

## 4. Pattern Synthesis Matrix (15 Core Patterns for Ambry)

| # | Pattern | What Makes It Work | Best-in-Class Product | Ambry Adaptation (Not Copied) | Flutter Cost & Mechanism |
|---|---|---|---|---|---|
| 1 | **Onboarding & First-Run** | Progressive disclosure: separate account connect from vault creation vs. restore; prime permissions before OS dialog; clear recovery safety. | **Ente Photos** + **Proton Drive** | Adaptive 2-step (restore/unlock) vs. 3-step (new vault) + dedicated Permission Priming step; 2×12 `GoogleSansCode` grid; Telegram account switch & copy/paste fix. | **M** (`LoginPage` refactor + `AnimatedSwitcher` + `pinput`) |
| 2 | **Timeline Grid & Date Grouping** | Tight 2dp gutters let photos breathe together; compact sticky/inline date headers preserve temporal landmarks without wasting vertical space. | **Google Photos** + **Immich** | Preserve `SliverSegmentedList` + `RenderFixedRow` + 4-column default; tighten `TimelineHeader` (`48/56/84dp`) fixing +6px overlap; reveal checkmarks only in multi-select. | **S** (`constants.dart`, `header.widget.dart`, `segment_builder.dart`) |
| 3 | **Fast Scrubbing** | Instant jump across years with clear year anchors and crisp month/year feedback + subtle tick haptics. | **Google Photos** | Tonal capsule thumb (`surfaceContainerHighest` + `outlineVariant`), centered double-arrows, `ValueListenableBuilder` thumb offset (no per-frame `setState`), accessible `inverseSurface` date pill. | **S** (`scrubber.widget.dart`) |
| 4 | **Albums** | Borderless square covers directly on canvas with quiet title + item count below let photography define the visual rhythm. | **Apple Photos** | Remove `1px` card outlines, `0.7` tall cards, and `"• Owned"`; adopt `1:1` `r=16dp` covers + 2-line title + item count; add `"Create album"` empty CTA. | **S–M** (`album_selector.widget.dart`, `album_tile.dart`, `remote_album.page.dart`) |
| 5 | **Full-Screen Viewer** | True `#000000` canvas, matched Hero geometry, focal double-tap zoom, smooth dismiss drag, and unobtrusive metadata sheet. | **Apple Photos** | Fix `originalSize` zoom-lock bug, smooth dismiss over 35% height + velocity fling, 4-stop AA edge scrims, subtle Telegram upgrade/offline pill preserving preview & zoom, `Vault Status` row in `AssetDetails`. | **M–L** (`asset_page.widget.dart`, `viewer_*`, `asset_details.widget.dart`, `photo_view_core.dart`) |
| 6 | **Video Controls** | Thin, uncluttered scrubber bar, crisp tabular duration, and immediate feedback while streaming starts. | **Apple Photos** + **Samsung Gallery** | Scoped `SliderTheme` (`3.5dp` track, `6dp` thumb), known `asset.duration` shown right away, frosted `"Streaming from Telegram…"` pill after `350ms` (replacing 1.6s blind wait), explicit error/retry state + mute toggle. | **M** (`video_controls.dart`, `video_viewer.widget.dart`, `video_player_provider.dart`) |
| 7 | **Search & Filters** | Single calm search pill, instant filter chips, stateful tab memory, and purposeful zero-query shortcuts instead of generic stock art. | **Google Photos** + **Samsung Gallery** | Neutral `AmbrySearchBar` with clear `X`, tonal `rPill` filter chips (`InkWell`), 2×2 tonal quick-collection grid (no polaroid/gradients), `maintainState: true`, fix `"Not in album"`, pagination loop, `YearFilter`, `CameraPicker`. | **M** (`search.page.dart`, `paginated_search.provider.dart`, `local_search.repository.dart`) |
| 8 | **Multi-Select** | Unmistakable inset/check feedback on tiles, animated bar swap, and snap-able action tray within thumb reach. | **Immich** + **Google Photos** | Preserve zero-allocation `_RenderSelectionFrame` tuned to `180ms` + `12dp` inner radius; animate bottom nav / landscape rail out; snap points + `SafeArea` on `BaseBottomSheet`; remove broken `StackAction`. | **S–M** (`thumbnail_tile.widget.dart`, `tab_shell.page.dart`, `base_bottom_sheet.widget.dart`) |
| 9 | **Bottom Sheets & Menus** | Tonal `surfaceContainerLow` grounding, 36×4dp drag handle, predictable snap points, and unified M3 menus/dialogs. | **Material Design 3** | Migrate `ImmichAppBarDialog` from cramped top `Dialog` to structured Modal Bottom Sheet; unify `ImmichConfirmDialog` (neutral Cancel, semantic destructive OK) + `ImmichMenu`. | **M** (`app_bar_dialog.dart`, `confirm_dialog.dart`, `packages/ui`) |
| 10 | **Empty / Loading / Error / Offline States** | Never leave a blank grid or dead spinner; communicate what happened (local vs. Telegram offline) with one-tap recovery. | **Ente Photos** + **Proton Drive** | Reusable `AmbryEmptyState`, `AmbryErrorState`, shared `AmbryShimmerScope` (single controller!), tile retry on fail, offline notice on Map/Viewer/Backup, permission-denied banner on Timeline & Local Albums. | **M** (`packages/ui`, `thumbnail.widget.dart`, `timeline.widget.dart`, sub-collections) |
| 11 | **Backup Status Communication** | Put live vault health, pause warnings, and master switches **above the fold**; never hide active-device conflicts or battery kills. | **Google Photos** + **Proton Drive** | Single unified Vault Summary Card + prominent `AmbryBanner` for active-phone pause (`claimVault`) & ColorOS battery warning + clean tonal Backup/Encryption cards + calm `"All backed up"` state. | **M** (`backup.page.dart`, `backup_toggle_button.widget.dart`, `encrypt_uploads_tile.widget.dart`) |
| 12 | **Light & Dark Themes** | Warm gallery paper light mode and deep obsidian dark mode keep chrome calm and preserve color accuracy; viewer stays `#000000`. | **Apple Photos** + **Material 3** | Sunlit Paper (`#FAF9F7`) & Obsidian Alcove (`#0C0C0E`) surface scales; accessible light amber text `#9E450A`; remove orange AppBars/Settings/SnackBars. | **S–M** (`theme_data.dart`, `color_scheme.dart`, `packages/ui/lib/src/theme.dart`) |
| 13 | **Typography & Iconography** | Clear editorial scale, `tabularFigures()` for counts/time, monospace for cryptographic keys, consistent rounded icon family. | **Material 3** + **Apple HIG** | Fix inverted `TextTheme` using `GoogleSans` + `GoogleSansCode`; standardize `Icons.*_rounded` / `*_outlined` (remove `*_ios*`, `*_sharp`); ensure Dynamic Type 2.0x resilience. | **S** (`theme_data.dart` + callsite cleanup) |
| 14 | **Haptics** | Tactile punctuation at threshold crossings (long-press select, scrubber year ticks, dismiss pop threshold, toggles)—never spam. | **Apple HIG** + **Android** | Route all triggers through existing `hapticFeedbackProvider`: `heavyImpact` on multi-select/delete confirm, `mediumImpact` on memory change, `selectionClick` on tabs, scrubber labels, dismiss threshold, switches. | **S** (`haptic_feedback.provider.dart` + widgets) |
| 15 | **Transitions & Micro-Interactions** | Physics-consistent springs (`ζ = 0.9` spatial, `ζ = 1.0` effects), fast 180–260ms choreography, strict 120fps Impeller budget & Reduce Motion parity. | **M3 Expressive** + **Apple Photos** | `AmbryMotion` spring/duration utility respecting `MediaQuery.disableAnimationsOf(context)`; `180ms` tab crossfade; focal double-tap & Hero corner-radius interpolation; zero per-tile animations. | **M** (`packages/ui/lib/src/motion.dart`, `router.dart`, `asset_page.widget.dart`) |

---

## 5. Sources List

### Official Design & Accessibility Guidelines
- Material Design 3 Root & M3 Expressive: `https://m3.material.io/`
- M3 Motion Overview & Physics Springs: `https://m3.material.io/styles/motion/overview`
- M3 Color System & Roles: `https://m3.material.io/styles/color/the-color-system/color-roles`
- M3 Typography Scale Tokens: `https://m3.material.io/styles/typography/type-scale-tokens`
- M3 Corner Radius Scale: `https://m3.material.io/styles/shape/corner-radius-scale`
- M3 Elevation Overview: `https://m3.material.io/styles/elevation/overview`
- M3 Components — Navigation Bar, Bottom Sheets, Search, Chips: `https://m3.material.io/components/navigation-bar`, `https://m3.material.io/components/bottom-sheets`, `https://m3.material.io/components/search`, `https://m3.material.io/components/chips`
- Android Design Portal: `https://developer.android.com/design`
- Android Edge-to-Edge Design: `https://developer.android.com/design/ui/mobile/edge-to-edge`
- Android Mobile Accessibility: `https://developer.android.com/design/ui/mobile/accessibility`
- Apple Human Interface Guidelines: `https://developer.apple.com/design/human-interface-guidelines/`
- Apple HIG — Dark Mode, Motion, Playing Haptics, Typography, Images: `https://developer.apple.com/design/human-interface-guidelines/dark-mode`, `https://developer.apple.com/design/human-interface-guidelines/motion`, `https://developer.apple.com/design/human-interface-guidelines/playing-haptics`, `https://developer.apple.com/design/human-interface-guidelines/typography`, `https://developer.apple.com/design/human-interface-guidelines/images`
- W3C WCAG 2.1 Normative & Contrast Understanding Docs: `https://www.w3.org/TR/WCAG21/`, `https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html`, `https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html`

### Product Benchmarks & Engineering Docs
- Google Photos — M3 Expressive Backup Indicator: `https://9to5google.com/2025/08/05/google-photos-material-3-expressive-backup-indicator/`
- Google Photos — Collections Tab Redesign: `https://9to5google.com/2026/10/26/google-photos-collections-tab-redesign/`
- Google Photos Support — Backup, Navigation & Collections: `https://support.google.com/photos/answer/6193316`, `https://support.google.com/photos/answer/9315511`, `https://support.google.com/photos/answer/10694389`
- Apple Photos — iOS 18 Announcement & Release & Support: `https://www.apple.com/in/newsroom/2024/06/10/ios-18-makes-iphone-more-personal-capable-and-intelligent-than-ever/`, `https://www.apple.com/in/newsroom/2024/09/ios-18-is-available-today-making-iphone-more-personal-and-capable-than-ever/`, `https://support.apple.com/en-us/121115`
- Samsung Gallery / One UI 7: `https://news.samsung.com/global/samsung-one-ui-7-enhances-security-and-privacy-in-the-age-of-ai-giving-users-greater-transparency-and-choice`
- Ente Photos — Architecture, Features & Recovery Key: `https://ente.com/architecture/`, `https://help.ente.io/photos/features/`, `https://help.ente.io/photos/security/recovery-key/`
- Immich Architecture & ThumbHash: `https://immich.app/docs/overview/architecture/`, `https://github.com/evanw/thumbhash`
- Amazon Photos Redesign: `https://aboutamazon.com/news/devices/amazon-photos-has-a-new-look-built-around-memory`
- OneDrive Photos Support: `https://support.microsoft.com/`
- Proton Drive Photos — Android Backup & Encryption: `https://proton.me/support/drive-android-photo-backup`, `https://proton.me/support/are-photos-encrypted-photo-backup`, `https://proton.me/blog/proton-drive-android-photo-backup`, `https://play.google.com/store/apps/details?id=me.proton.android.drive`

### Public Inspiration & Paywall Verification
- Dribbble: `https://dribbble.com`
- Behance Mobile Gallery Projects: `https://www.behance.net/search/projects?search=mobile%20app%20photo%20gallery`
- Figma Learn Photo Gallery Prototype & Community File: `https://help.figma.com/hc/en-us/articles/25316886617495-Create-a-photo-gallery-prototype`, `https://www.figma.com/file/jKrTKKXtPBuAsMAYePaKF7/Photo-Sharing-App-UI?node-id=0%3A1`
- Pinterest Mobile Photo Gallery UI: `https://www.pinterest.com/search/pins/?q=mobile%20app%20ui%20design%20photo%20gallery`
- Gated / Login-Restricted Reference Libraries (not scraped behind paywalls): `https://mobbin.com/`, `https://pageflows.com/` (incorporating former Screenlane), Pttrns.
