# Phase 5 — Motion & Interaction Specification

> **Target Frame Budget:** `≤ 8.33 ms/frame` at **120 Hz** (via `FlutterDisplayMode.setHighRefreshRate()`, `lib/main.dart:88`) and `≤ 16.67 ms/frame` at **60 Hz** on Impeller (mid-range Android hardware).
> **Motion Identity:** M3 Expressive **Standard** physics scheme (`ζ = 0.9` spatial, `ζ = 1.0` effects)—tactile, decisive, zero rubbery bounce competing with photography.

---

## 1. Motion Philosophy & `AmbryMotion` Token Specification

Add a concise motion specification directly inside `packages/ui/` (`packages/ui/lib/src/motion.dart`, exported by `packages/ui/lib/immich_ui.dart`) complementing `ImmichDuration` (`packages/ui/lib/src/constants.dart:80-100`):

```dart
abstract final class AmbryMotion {
  // M3 Expressive Standard Scheme — Spatial Springs (movement, scale, bounds)
  static const SpringDescription fastSpatial = SpringDescription(mass: 1.0, stiffness: 1400.0, damping: 0.9 * 2 * 37.4166); // ζ = 0.9
  static const SpringDescription defaultSpatial = SpringDescription(mass: 1.0, stiffness: 700.0, damping: 0.9 * 2 * 26.4575); // ζ = 0.9
  static const SpringDescription slowSpatial = SpringDescription(mass: 1.0, stiffness: 300.0, damping: 0.9 * 2 * 17.3205); // ζ = 0.9

  // M3 Expressive Effects Springs (opacity, color — critically damped ζ = 1.0, zero overshoot)
  // Expressed as clean Duration + Curve approximations for standard Flutter implicit/explicit widgets:
  static const Duration dFast = Duration(milliseconds: 140);     // image crossfade, micro-feedback
  static const Duration dStandard = Duration(milliseconds: 180); // tabs, chrome fades, multi-select, header checks
  static const Duration dModerate = Duration(milliseconds: 220); // step switchers, sheets, search expand
  static const Duration dRoute = Duration(milliseconds: 260);    // viewer backdrop fade & Hero flight
  static const Duration dShimmer = Duration(milliseconds: 1200); // shared skeleton phase

  static const Curve easeSpatial = Curves.easeOutCubic;
  static const Curve easeEffects = Curves.easeOut;
  static const Curve easeEmphasized = Curves.fastOutSlowIn;

  static Duration durationOf(BuildContext context, Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;

  static bool isReduced(BuildContext context) => MediaQuery.disableAnimationsOf(context);
}
```

*(Implementation note: `SpringDescription.withDampingRatio(mass: 1.0, stiffness: ..., ratio: 0.9)` is built into Flutter's `package:flutter/physics.dart` and avoids manual $2\sqrt{mk}$ math.)*

### Dependency Decision: Do NOT Add `animations` Package
- **Verified:** `animations` is **not** in `keepsake/mobile/pubspec.yaml`.
- **Decision:** Keep zero new packages. Material `animations` (`OpenContainer`, `SharedAxisTransition`) wraps extra `OverlayEntry` / offstage measurement trees and clips shapes differently from `SliverSegmentedList` + `Hero` + `PhotoView`. Native Flutter primitives (`Hero` with custom `flightShuttleBuilder`, `PageRouteBuilder`, `SpringSimulation`, `AnimatedSwitcher`, `AnimatedSlide`/`AnimatedOpacity`, `DraggableScrollableSheet`, `SliverAppBar`) deliver 100% of this specification with lower memory overhead and zero dependency churn.

---

## 2. Choreography Matrix (All 12 Required Interactions)

| # | Interaction | Trigger | Timing / Spring | Curve / Physics | What Moves | Flutter Approach | Haptic (`hapticFeedbackProvider`) | Reduced-Motion Fallback (`disableAnimations`) |
|---|---|---|---|---|---|---|---|---|
| 1 | **App Launch → Onboarding → First Sync** | Cold launch / auth complete / step Next/Back | Launch fade `220ms`; step transition `220ms` | `easeSpatial` (`easeOutCubic`) | Splash icon stays anchored on `#FFF6E6`/`#1C140D`; onboarding step fades + slides `12dp` horizontally (`±0.04`); progress bar width interpolates | `SplashScreenPage` matching native bg (`#FFF6E6`/`#1C140D`) + `PageRouteBuilder` `220ms` fade; `LoginPage` `AnimatedSwitcher` + `TweenAnimationBuilder` progress | `selectionClick()` on step advance; `mediumImpact()` on vault unlock/create success | Instant `Duration.zero` swap; zero `12dp` slide |
| 2 | **Grid → Photo Viewer (Open & Close)** | Tap thumbnail tile / Back or drag dismiss | `260ms` flight (`dRoute`); chrome `180ms` | `defaultSpatial` / `easeSpatial` | Tile image expands seamlessly to `BoxFit.contain` viewer bounds via `ClipRRect` (`0dp` ↔ `0dp`); tile overlays fade out (`150ms`); black `#000000` backdrop fades in behind; viewer chrome arrives after flight settles | Preserve `Hero(tag: '${asset.heroTag}_$heroIndex')` + add `flightShuttleBuilder` interpolating `ClipRRect` / `BoxFit` between `from` tile and `to` photo; `AssetViewerRoute` `PageRouteBuilder(opaque: false, transitionDuration: 260ms)` | None on open (light feel); `selectionClick()` on close via drag threshold | Instant `Duration.zero` fade; no `Hero` scale flight |
| 3 | **Swipe Between Photos** | Horizontal drag on `AssetViewer` `PageView` | Physics-driven (`FastClampingScrollPhysics`) | `mass: 1, k: 1601.25, c: 80` (existing Android spring) | Horizontal viewport page tracks finger 1:1; settles cleanly; commits asset change only on `ScrollEndNotification(depth: 0)` | Keep existing `FastClampingScrollPhysics` + `ScrollEndNotification`; **fix `_isZoomed` to include `PhotoViewScaleState.originalSize`**; reset `isPlayingMotionVideoProvider` on change | None during swipe (keep continuous feel crisp) | Same 1:1 direct-manipulation physics; reduced tap-navigate jumps directly |
| 4 | **Drag-to-Dismiss** | Vertical drag down (`dy > 0`) when `!showingDetails && !isZoomed` | 1:1 gesture tracking; snap-back `defaultSpatial` (~`220ms`) | Linear 1:1 drag; `defaultSpatial` spring on cancel | Photo translates by `delta` and scales `1.0 → 0.84` over `0..35%` screen height; `#000000` backdrop fades `1.0 → 0.0` smoothly over `0..35%` height; chrome fades `0.0` immediately on drag start | Fix `AssetPage`: clamp upward drag (`delta.dy.clamp(0, ∞)`), pop if `dy > 80dp || primaryVelocity > 650 px/s`, pass `setOpacity(1.0)` **without forcing `showingControls = true`** | **`selectionClick()` once** when crossing `80dp` dismiss threshold (`_crossedDismissThreshold` latch) | Translate vertically with opacity fade (`1.0 → 0.3`), skip image shrink (`scale = 1.0`), instant snap-back |
| 5 | **Pinch & Double-Tap Zoom** | Pinch gesture or double-tap on `PhotoView` | Double-tap `240ms` spring; pinch bounce-back `defaultSpatial` | `defaultSpatial` (`ζ = 0.9`) | Pinch tracks 1:1 (`min: contained * 0.85`, bounces to `1.0`; `max: contained * 6.0`). Double-tap zooms **around tap focal point** (`contained` → `max(covering, 2.2 × contained)` → `contained`) | Update `PhotoViewCore` double-tap position calculation from `Offset.zero` to focal offset clamped to bounds; set `minScale: PhotoViewComputedScale.contained * 0.85`, `maxScale: PhotoViewComputedScale.contained * 6.0` | `selectionClick()` when hitting zoom bounds (`contained` reset or max) | Instant `Duration.zero` scale jump to tap-centered target |
| 6 | **Tab Switches (`TabShellPage`)** | Tap `NavigationBar` / `NavigationRail` destination | **`180ms`** (`dStandard`) replacing `600ms` | `easeEffects` (`Curves.easeOut`) | Outgoing tab fades cleanly into incoming tab; indicator pill slides/morphs (`M3 NavigationBar`) | `AutoTabsRouter(duration: AmbryMotion.durationOf(context, AmbryMotion.dStandard))` + `FadeTransition` | `selectionClick()` (existing `:131`) | `Duration.zero` instant tab switch |
| 7 | **Album Open & Parallax Scroll** | Tap album card in `AlbumsPage` / scroll `RemoteAlbumPage` | Route `240ms`; scroll 1:1 | `easeSpatial` | Material shared-axis / standard Android push; hero image scales `1.25 → 1.0` & fades smoothly into solid AppBar on scroll | Standard `RouteType.material()`; refactor `RemoteAlbumSliverAppBar` & `MesmerizingSliverAppBar` to read `FlexibleSpaceBarSettings` / `ValueNotifier<double>` **without `addPostFrameCallback(() => setState(...))`** | None on tap; `selectionClick()` on sort change | Instant route fade; static collapsed AppBar title without parallax scale |
| 8 | **Selection Mode Enter & Exit** | Long-press tile or tap Done / Close / Back | **`180ms`** (`dStandard`) | `easeSpatial` | Tile thumbnail shrinks `6dp` inside `primaryContainer` + clips to `12dp` radius; header bulk-select circles fade + scale `0.6 → 1.0`; top `ImmichSliverAppBar` crossfades out; portrait `NavigationBar` & landscape `NavigationRail` slide/fade out; `BaseBottomSheet` rises | Tune `_RenderSelectionFrame` to `180ms` `easeOutCubic`; wrap header checkboxes in `AnimatedOpacity` + `AnimatedScale`; wrap `_BottomNavigationBar` & landscape `NavigationRail` in `AnimatedSlide` + `AnimatedOpacity` | **`mediumImpact()`** on entering multi-select; `selectionClick()` on toggling tiles/buckets | Immediate `Duration.zero` frame swap and visibility toggle |
| 9 | **Bottom Sheet Open & Close** | Enter multi-select / tap Account / tap Filter chip | `240ms` enter / `200ms` exit (`defaultSpatial`) | `easeEmphasized` (`fastOutSlowIn`) | Sheet slides up from bottom edge over `scrim @ 0.45`; `BaseBottomSheet` snaps between `[min, 0.45, 0.85]`; keyboard focus animates sheet to `0.85` (`220ms`) | `DraggableScrollableSheet(snap: true, snapSizes: [min, 0.45, 0.85])`, clean `dispose()` on internal controller; `showModalBottomSheet` using theme `surfaceContainerLow` & `xl (20dp)` top radius | None (avoid noisy sheet pop haptics) | Instant show/hide (`Duration.zero`) |
| 10 | **Backup Progress & "Backup Complete"** | Toggle Backup / active upload / `remainder` hits `0` | State morph `200ms`; progress bar `250ms`; complete `280ms` | `easeSpatial` (bar) & `easeEffects` (state tint) | Remove dead 8s gradient loop in `BackupToggleButton`; card morphs `surfaceContainerLow` ↔ `primaryContainer`; linear bar glides smoothly (`TweenAnimationBuilder`); when `remainder` transitions `>0 → 0`, bar resolves and badge swaps smoothly to `Icons.check_circle_rounded` (`success`) | `AnimatedContainer` (`200ms`) + `AnimatedSwitcher` (`280ms`, `FadeTransition` + subtle `ScaleTransition` `0.85→1.0`) on `VaultSummaryCard` status chip | `selectionClick()` on toggle switch & on live "All backed up" transition | Instant color/icon swap; determinate bar snaps cleanly |
| 11 | **Pull-to-Refresh** | Overscroll pull on Timeline / Albums / Search | System `RefreshIndicator` physics; settle `200ms` | `easeEffects` | Circular tonal refresh indicator (`color: primary`, `backgroundColor: surfaceContainerHigh`) drops cleanly below `ImmichSliverAppBar` (`edgeOffset`) | M3 `RefreshIndicator` with tonal surface & `onRefresh` returning when sync completes | `selectionClick()` when pull threshold arms; subtle confirm on finish | Standard M3 indicator without excess stretch |
| 12 | **Skeleton-to-Image Reveal** | Thumbnail loads from local disk, `ThumbnailStore`, or Telegram | Shimmer `1200ms` loop; image fade **`140ms`** | Linear sweep (`1200ms`), `easeEffects` fade-in (`140ms`) | Warm gradient shimmer sweeps across uncached tiles via **one shared controller**; decoded image fades smoothly `0 → 1` (`140ms`) when loaded asynchronously (`0ms` if synchronous RAM hit); error reveals subtle retry icon | `AmbryShimmerScope` (`InheritedWidget` sharing 1 `AnimationController` across subtree) + `_ThumbnailRenderBox` fade `140ms` (`Curves.easeOut`) | None (silent visual polish) | Disable shimmer (`solid surfaceContainer`); `0ms` instant image swap |

---

## 3. Specific Motion Fixes for Existing Code Bugs

1. **`Hero` Aspect-Ratio & Corner-Radius Interpolation:** In `ThumbnailTile` (`thumbnail_tile.widget.dart:91-107`), `flightShuttleBuilder` returns raw `to.widget` on pop (a square-cropped tile), snapping non-square photos abruptly at pop end. Return an `AnimatedBuilder` clipping `from.widget` (during push) or `to.widget` (during pop) smoothly without re-decoding the image!
2. **`Scrubber` Zero-SetState Tracking (`scrubber.widget.dart:182`):** Currently `ScrubberState` calls `setState(() => _thumbTopOffset = _currentOffset)` on **every** `ScrollUpdateNotification`, rebuilding the entire `Stack` + `RepaintBoundary` tree at 120Hz! Move `_thumbTopOffset` into a `ValueNotifier<double>` consumed only by a `ValueListenableBuilder` around the `PositionedDirectional` thumb.
3. **Header Parallax Without `addPostFrameCallback(() => setState)`:** Both `RemoteAlbumSliverAppBar` (`:114-120`) and `MesmerizingSliverAppBar` (`:72-78`) schedule `setState` every scroll frame via post-frame callback—causing 1-frame lag and extra builds. Derive scroll progress directly inside `LayoutBuilder` from `constraints.maxHeight` or `context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()`!
4. **Drop `ImageFilter.blur(sigmaX: 30, sigmaY: 30)` Fallback in `MemoryCard`:** Because `thumbHash` is always `null` in Ambry, `MemoryCard._BlurredBackdrop` (`memory_card.widget.dart:111-122`) allocates an expensive full-screen blur pass on Impeller on every slide. Replace the non-thumbhash fallback with a crisp `#000000` canvas + soft radial vignette (`#181512` center → `#000000` edge).

---

## 4. 60/120 fps Performance Budget (Impeller on Mid-Range Android)

| Budget Category | Strict Guardrail | How Verified in Codebase / Design |
|---|---|---|
| **Frame Time** | `< 8.33 ms` (120Hz) / `< 16.67 ms` (60Hz) | Zero per-tile `AnimationController`s; `AmbryShimmerScope` shares **1** controller only when visible placeholders exist (pauses automatically when zero placeholders are painted). |
| **Zero Extra Image Decoding During Transitions** | `0` new `ImageDecoder` / `Thumb` decodes during Hero or tab animations | `Hero` `flightShuttleBuilder` reuses `from`/`to` rendered widgets; `RemoteFullImageProvider` feeds `initialImage` directly from `_small` RAM cache (`CustomImageCache`); `Thumbnail.fromAsset` keeps `decodeSize` / `kThumbnailResolution (320×320)`. |
| **10,000-Photo Timeline Scroll** | Zero GC spikes or raster stalls | Preserve `SliverSegmentedList` + `RenderFixedRow` + `_ThumbnailRenderBox(isRepaintBoundary: true)` + `_DeferredRowLoader` (`100ms` debounce). Keep `scrollCacheExtent: maxHeight * 2`. Zero `BoxShadow`, zero `BackdropFilter`, zero `Opacity` widgets over grid rows (only inside `_ThumbnailRenderBox` canvas paint). |
| **Telegram Bandwidth Protection** | Avoid saturating TDLib during rapid swipes | `AssetPreloader` (`asset_preloader.dart`) should preload **preview** (`1440px`) for `index ± 1` after `400ms` dwell rather than queuing multiple full-resolution Telegram downloads in parallel when `loadOriginal == true`. |
| **Device Profiling Plan (For Next Implementation Run)** | Real device verification (not run now) | Verify Impeller raster + UI thread frame times (`< 8.3ms` P95) via Flutter DevTools Timeline while flinging a 1,000+ item timeline, entering multi-select, and dragging `AssetViewer` back to grid. |
