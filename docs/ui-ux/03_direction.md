# Phase 3 — Design Direction

---

## 1. Brand & Technical Constraints

- **Etymology & Visual Mark:** An *ambry* is a recessed wall cabinet used to safeguard precious things. Its mark (`keepsake/branding/ambry-logo.svg`) depicts a warm sunrise seen through an arched cream alcove (`#FFF6E6` arch, `#F9A825` sun, `#F08A2E` / `#B8540F` hills on `#FDB44B → #EE7F22` amber).
- **Functional Reality:** Serverless Android photo/video vault backed by private Telegram channels, client-side AES-256-GCM encryption + Argon2id passphrase + 24-word recovery kit, and an on-device loopback media server (`docs/PRODUCTION_READINESS.md`).
- **Hard Product Constraints:**
  1. **Photography is the hero:** Zero decorative gradients, heavy drop shadows, neon glows, or visual clutter competing with images.
  2. **Slower-than-CDN remote media:** Cold Telegram thumbnails and 4-second remote video starts demand calm, informative loading and resilient offline/retry states.
  3. **High-stakes cryptographic trust:** Passphrase loss is unrecoverable; active-phone locks, encryption off-switches, and ColorOS background freezes must be crystal-clear without fear-mongering or manipulative copy.
  4. **120fps Android Impeller performance:** Zero expensive blurs/shadows on scroll containers or per-tile animations over 10,000+ photos.

---

## 2. Three Candidate Directions Compared

### Direction A — "Swiss Lightbox" (Clinical Ultra-Minimalism)
- **Aesthetic:** Pure `#FFFFFF` / `#000000` canvas, 1px `#E5E5E5` hairlines, cold grays, strictly utility typography, zero surface warmth.
- **Strengths:** Completely neutral around photography; sharp grid alignment; trivial performance.
- **Weaknesses:** Feels indistinguishable from a bare file manager; fights Ambry's warm amber sunrise mark (`#B8540F` looks jarring on stark cold gray `#F9F9F9` and `#FFFFFF`); lacks emotional warmth for personal memories or reassuring warmth during security onboarding.

### Direction B — "Editorial Monograph" (Immersive Magazine Photography)
- **Aesthetic:** Large expressive serif/display headlines, frosted glass floating navigation bars, full-bleed asymmetrical cards, and rich `ImageFilter.blur` backdrops behind media.
- **Strengths:** Visually dramatic in Dribbble/Behance showcases; feels like a coffee-table photobook.
- **Weaknesses:** **Hostile to Ambry's constraints**—real-time Gaussian blurs (`BackdropFilter`/`ImageFilter.blur`) burn GPU frame time on mid-range Android devices at 120Hz, large display titles steal vertical viewport from the photo grid, and floating translucent overlays degrade WCAG contrast over bright photos.

### Direction C — "Sunlit Alcove" (Warm Gallery Minimalism + M3 Expressive Precision + Obsidian Media Stage)
- **Aesthetic:** Gallery-grade warm neutral surfaces (*Sunlit Paper* `#FAF9F7` light / *Obsidian Alcove* `#0C0C0E` dark) paired with M3 tonal containment (`surfaceContainerLowest`..`Highest`), pure `#000000` full-screen media stage, restrained amber accents reserved strictly for **intent, active selection, and vault-protection trust**, and M3 Expressive **Standard** spring motion.
- **Strengths:** Honors both *ambry* ("warm recessed alcove") and *photography is the hero*; eliminates cold gray clashes with `#B8540F`/`#FDB44B`; replaces borders/shadows/gradients with fast tonal fills; feels unmistakably Android-native (Material 3) while matching Apple Photos' visual calm.
- **Weaknesses:** Requires disciplined accent restraint so amber never creeps back onto AppBar titles, settings lists, or error/success states.

---

## 3. Weighted Decision Matrix

Scoring `1–5` (5 = best fit for Ambry's brand, UX, and Flutter/Android constraints):

| Criterion (Weight) | A: Swiss Lightbox | B: Editorial Monograph | C: Sunlit Alcove |
|---|---|---|---|
| **Photography Deference** (25%) | 4.5 (1.13) | 3.5 (0.88) | **5.0 (1.25)** |
| **Brand Fit (Ambry / Alcove)** (15%) | 2.5 (0.38) | 4.0 (0.60) | **5.0 (0.75)** |
| **Zero-Knowledge Trust & Clarity** (20%) | 4.0 (0.80) | 3.0 (0.60) | **5.0 (1.00)** |
| **Telegram Latency & Error Resilience** (15%) | 4.0 (0.60) | 3.0 (0.45) | **4.5 (0.68)** |
| **120fps Mid-Range Impeller Budget** (10%) | 5.0 (0.50) | 2.0 (0.20) | **4.5 (0.45)** |
| **WCAG AA Contrast & Dynamic Type** (10%) | 4.5 (0.45) | 2.5 (0.25) | **5.0 (0.50)** |
| **Android / M3 Idiom & Flutter Reuse** (5%) | 3.5 (0.18) | 2.5 (0.13) | **5.0 (0.25)** |
| **Weighted Total (Max 5.00)** | **4.04** | **3.11** | **4.88 (Winner)** |

---

## 4. Chosen Direction: **Sunlit Alcove**

> **Thesis (Two Sentences):** **Sunlit Alcove** pairs calm, gallery-grade warm neutrals (*Sunlit Paper* in light mode and *Obsidian Alcove* in dark mode, shifting to true `#000000` in the full-screen viewer) with disciplined amber accents reserved strictly for user intent, active selection, and vault protection. Every decorative gradient, shadow, and legacy clutter pattern is replaced by Material 3 tonal containment, WCAG AA legibility over any photograph, and crisp, physics-grounded motion tuned for 60/120 fps on Android.

### Explicit Design & Usability Justification for Every Choice
1. **Warm Neutrals Over Cold Gray (`#FAF9F7` light / `#0C0C0E` dark):** Gallery walls in daylight use warm archival rag rather than sterile hospital blue-white (`#F9F9F9`), harmonizing naturally with Ambry's warm amber mark (`#B8540F` / `#FDB44B`) while letting skin tones, landscapes, and shadows look true to color.
2. **True `#000000` Full-Screen Media Canvas:** When inspecting a photo, playing a video, or watching a Memory, surrounding chrome must disappear completely into OLED black so zero bezel tint alters color perception or eye comfort.
3. **Disciplined Amber Restraint (`#B8540F` / `#FDB44B`, plus accessible `#9E450A` light text accent):** Today's app paints every AppBar title, Settings heading, SnackBar message, search background, and even the Free Up Space *success* checkmark bright orange—causing visual fatigue and breaking semantic color signaling. Reserving amber strictly for **primary CTAs, active nav pills, tile selection, and vault-protection shields** restores clarity and calm.
4. **Tonal Surface Hierarchy Over Outlines & Shadows:** Replacing 1px borders (`_GridAlbumCard`, `BackupPage` cards), drop shadows (`MemoryLane`, `BackupToggleButton`, `AssetDetails`), and primary-tinted gradients (`SearchPage`, `AlbumSelector`, `LibraryPage`, `LanguageSettings`) with M3 `surfaceContainerLow`/`surfaceContainer` fills reduces visual noise and eliminates expensive shadow/blur passes during scroll.
5. **Bottom-Only Editorial Scrims & `rgba(0,0,0,0.58)` Overlay Pills:** Removing the flat 20% darken on `MemoryLane` / `MemoryListPage` restores photo vibrancy across 75%+ of the frame while keeping bottom titles at **7.81:1 AAA** contrast, and frosted `0.58` black capsules guarantee **5.33:1 AA** legibility for video durations even over pure white snow.
6. **Clean 4-Tier Corner Radius System (`8 / 12 / 16 / 20 + full`):** Collapsing 11 inconsistent hardcoded radii (`4, 5, 8, 10, 12, 15, 16, 18, 18.5, 20, 24, 25`) onto existing `ImmichRadius` tokens creates instant architectural cohesion across sheets, album covers, chips, and tiles.
7. **M3 Expressive Standard Motion (`ζ = 0.9` spatial, `ζ = 1.0` effects):** Photos carry emotional weight; playful rubbery bounce (`ζ = 0.6`) feels cheap in a vault app, whereas crisp critically/near-critically damped springs (`180–260ms`) feel immediate, solid, and respectful of user intent.
8. **Honest, Non-Manipulative Trust Language:** Clear warnings when turning off encryption or freeing space on Android <12, honest offline/Telegram error explanations with one-tap retry, and calm `"All backed up"` confirmation—never guilt copy, streaks, or urgent badges.

---

## 5. Five Non-Negotiable Anti-Patterns to Eliminate

1. **Zero decorative gradients or glow borders** on cards, search bars, buttons, or spinners (`SearchPage`, `AlbumSelector`, `LibraryPage`, `LanguageSettings`, `BackupToggleButton`, `ImmichLoadingIndicator`).
2. **Zero amber text on passive headings or semantic alerts** (no orange `AppBar` titles, Settings row titles, `SnackBar` body copy, Cancel buttons, or success icons).
3. **Zero bare white text/icons over raw photographs** without a contrast-verified dark pill or multi-stop gradient scrim.
4. **Zero broken symmetry or dead serverless leftovers** (no stretched 100% Trash pill, 2+1 Library grid hole, redundant `"• Owned"`, leaked `StackAction`, leaked partner toggles, or `Colors.indigo` map buttons).
5. **Zero silent failures or manipulative trust friction** (no infinite buffering spinners, stuck completed downloads, blank permission-denied screens, or misleading `"Move to device trash"` copy when permanently deleting).
