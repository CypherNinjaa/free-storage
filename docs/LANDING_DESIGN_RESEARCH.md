# Ambry — Landing Page Design Research & Creative Direction

> **Date:** 2026-11-22  
> **Scope:** Research synthesis, brand tokens, typography, layout system, motion language, and visual strategy for the Ambry public landing page (`website/`, deployed to GitHub Pages).

---

## 1. Visual Reference Analysis

| Reference | What Makes It Effective | Patterns Adopted for Ambry | Patterns Deliberately Avoided |
|---|---|---|---|
| **Ente Photos** (`ente.photos`) | Leads with human-first privacy storytelling rather than fear-mongering. Balances clear client-side encryption explanations with clean alternating product frames and open-source verifiability. | Honest, plain-language encryption breakdown; clear distinction between what is protected and what is not; open-source GitHub transparency; zero-hype trust posture. | Cold clinical green/slate palette; claiming "multi-location underground vaults" or "zero-knowledge across every config" (Ambry's encryption is optional and Telegram provides storage). |
| **Immich** (`immich.app`) | Celebrates photography and the actual mobile experience (timeline, albums, map, viewer) with crisp phone mockups and clear capability walkthroughs without burying the gallery under server jargon. | Large, tactile mobile UI showcases for Timeline, Albums, Backup, and Viewer; crisp visual hierarchy for gallery features; clean comparison of backup models. | Indigo/blue developer-dashboard palette; showcasing server-only features (web UI, partner sharing, face clusters, CLIP search). |
| **Proton Drive** (`proton.me/drive/photo-storage`) | Translates cryptographic architecture (chunking, per-file keys, metadata handling) into calm, scannable diagrams and transparent tables that non-technical readers understand immediately. | Simple 4-step pipeline diagram (`Phone → On-device processing & encryption → Private Telegram channels`); transparent side-by-side explanation of encrypted vs unencrypted mode; expandable technical transparency drawer. | Corporate purple gradients; implying Telegram offers end-to-end encrypted channel storage or enterprise SLAs. |
| **Apple iCloud / Photos** (`apple.com/icloud/`) | Treats backup as an emotional continuity story (*your life, kept intact*) rather than raw gigabytes. Extreme typographic scale contrast, generous whitespace, warm photographic storytelling, and disciplined modular grids. | Editorial pacing starting from personal memories ("Your camera roll holds more than photographs"), layered photography with subtle parallax depth, calm asymmetrical spreads, generous breathing room. | Pure sterile `#FFFFFF` clinical glare; glossy glassmorphism; hiding technical trade-offs behind vague marketing claims. |
| **Godly / Awwwards / Land-book / Lapa Ninja / SaaSFrame** | Contemporary top-tier consumer pages pair expressive editorial serifs (*Instrument Serif*) with crisp geometric sans (*Inter*), tactile warm paper palettes (`#F8F5EF` / `#24231F`), hairline dividers (`1px`), restrained amber sunlight lighting, and scroll-triggered typography reveals. | Warm editorial print-meets-mobile aesthetic; architectural arch motif echoed from the Ambry sunrise-alcove icon; restrained subtle paper grain and warm amber radial light; crisp interactive state switches. | Heavy 3D WebGL bloat, scroll-jacking, blocking splash preloaders, floating neon blobs, fake testimonials, or invented metrics. |

---

## 2. Brand Identity & Color System

**Concept:** *"An intimate home for your digital memories."*  
Anchored directly to the actual Ambry mark (`keepsake/branding/ambry-logo.svg`): a cream architectural alcove framing a warm amber sunrise (`#FDB44B` → `#F08A2E` → `#B8540F`) over two quiet hills.

| Role | Token | Hex | Usage |
|---|---|---|---|
| Warm Ivory (Canvas) | `--bg-ivory` | `#F8F5EF` | Primary editorial page canvas |
| Soft Paper (Elevated) | `--bg-paper` | `#F1ECE3` | Subtle alternating sections & calm cards |
| Soft Sand (Border / Tonal) | `--bg-sand` | `#E9DFD0` | Tonal fills, pill badges, arch frames |
| Deep Charcoal (Ink) | `--ink-primary` | `#24231F` | Headlines & primary body copy (14.4:1 on Ivory) |
| Espresso (Dark Surface) | `--bg-espresso` | `#241C16` | Privacy & dark-canvas immersion bands |
| Deep Espresso (Accent Ink) | `--ink-espresso` | `#30251D` | High-emphasis buttons & dark framing |
| Muted Warm Gray | `--ink-muted` | `#6E685F` | Secondary copy, metadata, captions (5.2:1 on Ivory — AA+) |
| Hairline Border | `--border-subtle` | `rgba(48, 37, 29, 0.12)` | Print-like dividers and card strokes |
| Brand Amber (Primary) | `--amber-deep` | `#B8540F` | Restrained interactive accent & light-mode text accent (5.0:1 on Ivory) |
| Sunrise Amber (Warm Glow) | `--amber-sun` | `#D99536` | Alcove light glow, badges, highlight rules |
| Golden Sun (Dark Mode Accent) | `--amber-gold` | `#FDB44B` | Accent on dark espresso/obsidian bands (10.6:1 on `#241C16`) |
| Vault Sage (Verified State) | `--sage-bg` / `--sage-ink` | `#E4EFE6` / `#1D4B2B` | Calm "Protected / Enabled by default" status pills |

---

## 3. Typography System

- **Display / Editorial Serif:** `Instrument Serif` (Regular 400 + Italic 400) — tight tracking (`-0.02em`), poised line height (`1.04–1.12`), italic emphasis words for warmth and human resonance.
- **UI & Body Sans:** `Inter` (400, 500, 600) — neutral, crystal-clear legibility for explanations, tables, technical details, and in-device mockups.
- **Technical / Code Mono:** `JetBrains Mono` (400, 500) — for recovery kit indices (`01`–`24`), cipher format names (`AES-256-GCM`, `Argon2id`), and technical disclosure snippets.
- **Fluid Scale (`clamp`):**
  - Hero `h1`: `clamp(3.1rem, 6.4vw, 5.5rem)`
  - Section `h2`: `clamp(2.25rem, 4.2vw, 3.6rem)`
  - Lead copy: `clamp(1.0625rem, 1.3vw, 1.25rem)`
  - Body: `1rem` (`16px`), line-height `1.65`, measure `≤ 62ch`

---

## 4. Layout, Hero & Product Visual Strategy

- **Architectural Arch Motif:** Subtle SVG arch masks and rounded-top (`border-radius: 999px 999px 24px 24px`) frames echo the Ambry alcove logo across the Hero, Emotional Memories strip, and Final CTA.
- **Hero Concept:** Split-balanced editorial composition with massive *Instrument Serif* headline (*"Your memories deserve a private home."*), concise honest supporting copy, primary CTA (*"Explore on GitHub"* / release status) + secondary CTA (*"Discover how it works"*), beside a luminous warm amber arch framing a high-fidelity Android device mockup showing Ambry's actual **Sunlit Alcove** photo timeline, orbited by 3 softly layered warm memory photographs with subtle scroll parallax.
- **Product Visual Strategy (Honest & Representative):**
  - **Zero personal user photos:** All gallery photography uses bespoke warm 35mm-style film photographs bundled locally in `public/photos/`.
  - **Accurate Ambry UI mockups:** Every device screen (Photos Timeline, Vault Backup Hub with `Encrypt before upload`, Albums 1:1 grid, Full Photo Viewer with Vault Status pill, and 24-Word Recovery Kit restore view) mirrors the verified Ambry v1.0.0 Flutter/Sunlit Alcove UI we implemented, clearly captioned as representative UI previews of Ambry for Android.
- **Dedicated Privacy Policy Page:** `/privacy/` renders the full, verbatim policy from `docs/PRIVACY_POLICY.md` in Ambry's editorial typography, linked from Navigation, Privacy section, FAQ, and Footer.

---

## 5. Motion Direction

- **Library:** Lightweight **GSAP 3 + ScrollTrigger** (~28 KB gzipped) + pure CSS transitions for accordions and interactive tabs.
- **Choreography:**
  - Crisp, non-blocking Hero staggered reveal (`0.65s`, `power3.out`, no splash gate).
  - Subtle scroll-linked parallax on the floating hero photographs and emotional gallery frames (`scrub: 0.6`).
  - Staggered section & card reveals (`y: 24 → 0`, `opacity: 0 → 1`, triggered once at `top 84%`).
  - Interactive flow step highlighter + subtle traveling light pulse along the `Phone → Local Processing → Private Telegram Channels` SVG path.
  - Smooth height/opacity transitions on expandable Technical Transparency cards and FAQ accordions.
- **Accessibility:** Global `prefers-reduced-motion: reduce` media query + GSAP `gsap.matchMedia()` completely disable parallax and reveal movement for motion-sensitive users.
