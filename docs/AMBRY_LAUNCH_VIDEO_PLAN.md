# Ambry — Launch Video Production Plan

> **Product:** Ambry: Private Photo Backup (Android, Google Play). App ID `io.github.cypherninjaa.ambry`
> **Website:** https://ambry.vikashin.tech · **Repo:** https://github.com/CypherNinjaa/free-storage
> **Plan date:** 22 Nov 2026
> **Main tool:** Remotion (React → MP4) with Remotion Agent Skills in Claude Code. HyperFrames is the HTML/GSAP backup.

---

## 0. TL;DR

| What | Decision |
|---|---|
| **Hero film** | 60 s, 16:9, 1920×1080, text-led and works muted, optional VO. Goes in the Play Store "Preview video" field via YouTube |
| **Cutdowns** | 30 s (paid/social), 15 s teaser, 6 s bumper, and 9:16 versions of all three for Reels / Shorts / Stories |
| **Second film** | 45 s "Builder's cut" for devs on X, Reddit, Product Hunt and Hacker News: architecture, open source, no server |
| **Concept** | **"A private home for your memories."** An *ambry* is a recessed alcove for keeping precious things. The film is built around the arch from the logo |
| **Tone** | Calm, warm, honest. Apple-level restraint, no fear-mongering, no hype claims |
| **Stack** | Remotion 4 + `remotion-dev/skills` · scrcpy for real screen captures · ElevenLabs (VO + Eleven Music) or a licensed music library · ffmpeg for loudness and encoding |
| **Timeline** | About 6 working days from capture to upload |

---

## 1. What the video must say: product truths taken from the repo

Every claim in the film has to be true and checkable. These come from `docs/PLAY_RELEASE.md`, `docs/PRODUCTION_READINESS.md`, `docs/ui-ux/*` and the website.

### 1.1 Claims you can make

| Claim | Source in repo | Use in film as |
|---|---|---|
| Backs up photos and videos to private channels in **your own Telegram account** | PLAY_RELEASE §2 | "Stored in your own Telegram." |
| **No Ambry server**, no subscription, $0 infrastructure | docs/README, PLAY_RELEASE | "No Ambry server. No subscription." |
| **Encrypted on your phone first**: AES-256-GCM, Argon2id passphrase | 03_direction, website | "Encrypted on your phone. AES-256." |
| **24-word recovery kit** | 03_direction | "Only you hold the key." |
| Encryption is **on by default** and can be turned off for new uploads | decision log 2026-11-22 | Show the toggle in the ON state only |
| Full gallery: timeline, albums, favorites, archive, trash, search, map, "On this day" memories | PLAY_RELEASE §2 | Fast feature montage |
| **Free up space**: remove backed-up photos from the phone and keep them in the vault | PLAY_RELEASE §2 | "Free up space. Keep everything." |
| Stream videos and download originals even after deleting them from the phone | PLAY_RELEASE §2 | Supporting beat |
| Restore on a new phone with the same Telegram account plus passphrase or recovery words | PLAY_RELEASE §2 | ⚠️ See 1.3 |
| **Free and open source** (GNU AGPL v3), based on Immich | PLAY_RELEASE §2 | End card |
| No ads, analytics or crash reporting | PLAY_RELEASE §3 | "No ads. No tracking." |

### 1.2 Claims you must NOT make

| Don't say | Why |
|---|---|
| "Unlimited storage" | Telegram doesn't promise it, and files over 1.95 GB are refused (PRODUCTION_READINESS blocker 7) |
| "End-to-end encrypted by Telegram" / "Telegram can't see anything" | Telegram channels aren't E2E. **Ambry's** on-device encryption is the protection, and it can be turned off |
| "Instant" / "as fast as Google Photos" | Remote thumbnails are cold and remote video takes about 4 s to start (03_direction constraint 2) |
| "#1", "Best", "Award-winning", "Editor's choice" | Breaks Google Play's Store Listing policy on ranking or performance text |
| Showing the **Telegram logo**, paper plane or blue brand colour as if it were Ambry's | Telegram API terms ban impersonation. Ambry is independent. Say "your Telegram account" in plain text and add the disclaimer on the end card |
| Naming or mocking Google Photos, iCloud and so on | Not needed, it invites policy and legal trouble, and it goes against Ambry's honest tone |

### 1.3 Pre-shoot blockers

- **New-phone restore hasn't been run end to end on a device yet** (PRODUCTION_READINESS blocker 5). Don't film or claim the restore scene until it has passed. The script marks it as optional (Scene 6b).
- Film **only on the release build** with the final name and icon. Some "Keepsake" or Immich strings may still be left in older builds; check every frame for them.
- Use a **demo Telegram account** and a **seeded demo library**: the 7 film photos in `website/public/photos/` plus more photos you own or have licensed. Never show real personal photos, phone numbers or account names.

---

## 2. What Apple and Google do, and what Ambry takes from it

| Lesson | Where it's from | How Ambry uses it |
|---|---|---|
| **Lead with human benefit, not specs.** Apple's product stories seldom open with technical data; they open with lifestyle | Apple launch analysis (PrintWeek) | Open on memories (photos in arches), not "AES-256". The specs come in at second 25 or later, one line at a time |
| **Privacy can be shown, not spoken.** An Apple privacy spot ran with no dialogue and only the tagline "Privacy. That's iPhone." | Apple "Privacy. That's iPhone" (TechCrunch) | Default cut is **text-led with no VO**, ending on one tagline. It works muted in feeds and in any language |
| **Map every story beat to a real feature.** In "Data Auction", each piece of data sold off has a matching iPhone privacy feature | Apple "Data Auction" (Fast Company) | Every scene in the product act is one real Ambry screen and one real feature. No abstract filler |
| **Tell a simple story through the product's own UI.** "Loretta" opens with a typed search box and tells a love story through Google's products and photos | Google "Loretta" (The Drum, Adweek) | The phone screen is the stage. Real Ambry UI carries the story: grid → backup → lock → vault |
| **Use real people, not celebrities** | Loretta was inspired by a Googler's grandfather, who did the voice | If you add VO, use a real person (you, or a friend or family member) instead of a stock "ad voice". Indie authenticity is an asset |
| **Feature as punchline, with a friendly personality** | Google #BestPhonesForever: a running, light-hearted series that ends on a Pixel feature | For the 15 s social shorts: one line of set-up, then the Ambry feature as the payoff |
| **Craft beats synthetic polish.** Apple's 2025 holiday ad deliberately went handmade while an AI-generated rival was mocked for visual errors | Apple holiday film coverage | **Don't use AI-generated footage of people or photos.** Use real screen captures, real photos and hand-tuned motion. AI is fine for code, music and VO |
| **Restraint plus repetition makes a brand.** "Shot on iPhone" turned real user output into the ad | Adweek, MacRumors | Make the user's own photos the hero. Later, run a "Kept in Ambry" UGC series |
| **Keynote edit tricks**: match cuts, objects that morph between scenes, type that lands on the beat | 9to5Mac, Adam Grasso breakdown | Arch → app icon morph; grid tile → full-screen photo match cut; lock icon → recovery words |

---

## 3. Creative concept: "A private home for your memories"

**Core idea:** An *ambry* is a small arched alcove set into a wall, where people keep precious things. The logo is a sunrise seen through that arch. The film uses **the arch as a window**: memories appear inside arches, the arch becomes the app icon, the app becomes the alcove, and at the end the sun rises.

**Tagline options** (pick one and use it everywhere):
1. **"Your memories deserve a private home."** (already the website hero, so it's consistent) ← recommended
2. "Your photos. Your Telegram. Your key."
3. "Keep everything. Share nothing."

**Emotional arc:** Warmth (memories) → gentle question (where do they actually live?) → relief (Ambry: yours, encrypted, no server) → confidence (only you hold the key) → sunrise end card.

---

## 4. Scripts

### 4.1 Hero film: 60 s, 16:9, 30 fps (1800 frames)

Text-led by default. The VO column is optional; record it only if you'll do it well.

| # | Time | Visual | On-screen text | Optional VO | Sound / music |
|---|---|---|---|---|---|
| 1 | 0:00–0:04 | Black `#0C0C0E`. A thin amber line (`#D99536`) draws a single arch in the centre with an eased stroke | *Some things are worth keeping.* (Instrument Serif, italic on "keeping") | "Some things are worth keeping." | Silence → one soft felt-piano note |
| 2 | 0:04–0:14 | The arch fills with a photo (memory-morning). It slides left as new arches open: trail, dinner, coast, family, flowers, city. Slow parallax, a little film grain. Corner counter in JetBrains Mono rolls `1 → 12,408 photos` | — | "The first steps. The long dinners. The coast, that one summer." | Music enters (warm piano + soft pulse, about 92 BPM). A shutter tick on each arch |
| 3 | 0:14–0:20 | The arches pull back into a phone silhouette. A real Android "Storage almost full" style notification slides in (rebuilt in Remotion, generic, no brand). The photos drain to 30 % saturation | *But where do they live?* | "But where do they actually live?" | Music thins to one held chord |
| 4 | 0:20–0:25 | **Match cut:** the centre arch becomes the **Ambry icon**: the cream alcove with the sun rising (spring, no bounce). Colour comes back to the photos | **Ambry** · *Private photo backup* | "Meet Ambry." | Full chord + soft swell |
| 5 | 0:25–0:29 | Phone (frameless, warm ivory background `#F8F5EF`). **Real capture:** timeline scrolling, tap → photo opens full screen on true black | *A full gallery.* | "A full gallery…" | Music rhythm kicks in. Cuts land on the beat |
| 6 | 0:29–0:34 | **Real capture:** Backup screen. "Encrypt before upload" toggle **ON**. A lock glyph draws, and the file tiles flip into abstract ciphertext blocks | *Encrypted on your phone. AES-256.* | "…encrypted on your phone before anything leaves it…" | Soft "lock" click SFX |
| 7 | 0:34–0:40 | Motion-graphic flow (from the website diagram): **Phone → 🔒 → "Your Telegram" (2 private channels)**. A dashed box marked "Ambry server" fades in, gets crossed out and dissolves | *Stored in your own Telegram account.* / *No Ambry server. No subscription.* | "…and stored in your own Telegram account. There's no Ambry server in between." | Light whoosh along the path |
| 8 | 0:40–0:44 | **Real capture:** Free up space → "All backed up" check. The phone's storage bar drops | *Free up space. Keep everything.* | "Free up space, and keep everything." | Satisfying soft "done" tone |
| 9 | 0:44–0:48 | Fast 4-up grid of real captures, 1 s each: Albums · Search · Map · On this day | *Albums · Search · Map · Memories* | — | Four hits on the beat |
| 10 | 0:48–0:54 | Black stage. 24 recovery-word chips (`01`–`24`, JetBrains Mono) cascade into a neat grid, then fold into a single key icon. Use **fake demo words**, never a real kit | *Only you hold the key.* | "Only you hold the key." | Music drops to piano |
| 11 | 0:54–1:00 | End card. Ivory background, arch logo, the sun rises behind it. Tagline, "Get it on Google Play" badge, URL. Small print: *Free & open source (AGPL v3). Independent app; not affiliated with Telegram.* | **Your memories deserve a private home.** | "Ambry. Your memories deserve a private home." | Final resolving chord, tail out by 59.5 s |

**Optional 6b (insert only after restore is verified on a device):** 3 s of a new phone, sign in, unlock → library reappears. Text: *New phone? Everything comes back.* Shorten scene 9 to fit.

### 4.2 30 s cut (social / paid)
Scenes 1 (2 s) → 2 (4 s) → 4 (3 s) → 6 (4 s) → 7 (5 s) → 8 (4 s) → 10 (3 s) → 11 (5 s). Skip the "storage full" beat; open straight on warmth.

### 4.3 15 s teaser
| Time | Visual | Text |
|---|---|---|
| 0–3 s | Arch fills with a photo | *Your photos.* |
| 3–6 s | Photo flows into a lock | *Your key.* |
| 6–10 s | Phone → "Your Telegram". The "Ambry server" box gets crossed out | *Your Telegram. No server in between.* |
| 10–15 s | Icon sunrise, Play badge | **Ambry** · Private photo backup |

### 4.4 6 s bumper
Arch draws → icon sunrise → *Ambry. Private photo backup on your own Telegram.* → Play badge.

### 4.5 Builder's cut: 45 s, for X / Reddit / Product Hunt / HN
Kinetic typography + architecture. A developer voice is fine here.

| Time | Visual | Text |
|---|---|---|
| 0–5 s | Terminal-style type | *What if your photo backup had no server at all?* |
| 5–12 s | Diagram builds: Immich mobile app → Ambry fork. The server icon falls away | *We took Immich's app… and deleted the server.* |
| 12–22 s | On-device stages light up one by one: hashing (SHA-1 dedupe), EXIF, thumbnails, SQLite index, AES-256-GCM 1 MiB segments, Argon2id | *The phone does the server's job.* |
| 22–30 s | TDLib → two private channels. The encrypted index is pinned in the system channel | *Storage: your own Telegram account via TDLib.* |
| 30–38 s | Real UI montage | *A real gallery, not a file dump.* |
| 38–45 s | GitHub repo card, AGPL v3 badge, Play badge | *$0 infra. Open source. Live on Google Play.* |

Note: "deleted the server" is a figure of speech for the dev audience only. Keep Immich credit visible (AGPL requirement + goodwill).

---

## 5. Visual direction

All of this comes straight from the repo's design system ("Sunlit Alcove" in the app, editorial warm print on the website), so the film, site and app read as one brand.

### 5.1 Palette (use these exact tokens in a `theme.ts`)

| Role | Hex | Use in film |
|---|---|---|
| Warm Ivory canvas | `#F8F5EF` | Product scenes, end card |
| Soft Paper | `#F1ECE3` | Secondary panels |
| Sand | `#E9DFD0` | Arch frames, pills |
| Ink | `#24231F` | Headlines on light backgrounds |
| Obsidian Alcove | `#0C0C0E` | Opening, recovery-kit scene |
| True black | `#000000` | Full-screen photo moments only |
| Espresso | `#241C16` | Dark bands, flow diagram background |
| Brand Amber | `#B8540F` | Accent text on light backgrounds (sparingly) |
| Sunrise Amber | `#D99536` | Arch stroke, highlight rules |
| Golden Sun | `#FDB44B` | Accents on dark backgrounds, the sun |
| Logo arch / sun / hills | `#FFF6E6` / `#F9A825` / `#F08A2E`, `#B8540F` | Icon animation |
| Vault Sage | `#E4EFE6` / `#1D4B2B` | "Protected" / "All backed up" pills |

**Amber discipline** (from 03_direction): amber means *intent, selection, protection*. Never use it on body text, never as a background wash, and never as a neon glow.

### 5.2 Typography
- **Display:** Instrument Serif 400, with italics for emotional words ("*keeping*", "*home*"), tracking −2 %.
- **UI/Body:** Inter 400/500/600.
- **Technical:** JetBrains Mono for counters, recovery-word indices `01–24`, and cipher names.
- Load via `@remotion/google-fonts` so renders are deterministic.
- Safe area: keep text inside 90 % of the frame. On the Play listing the video sits behind the feature graphic, and on mobile it plays small, so headlines should be at least 64 px at 1080p.

### 5.3 Motion language
- **Critically damped springs, no rubbery bounce.** The app's motion spec uses ζ 0.9–1.0 and bans bounce because "playful bounce feels cheap in a vault app". In Remotion use `spring({ frame, fps, config: { damping: 200 } })` for no overshoot, or `mass 1, stiffness 120, damping 22` for a hint of life.
- Durations: micro 140–180 ms, standard 220–260 ms, scene moves 600–900 ms. Hold every text card for at least 1.5 s of reading time.
- **The arch is the transition device:** arch masks reveal photos, arch wipes between scenes, and the arch morphs into the icon.
- Parallax on photos: 3–6 % drift, never more.
- Match cuts: grid tile → full-screen photo (same position), lock glyph → key → recovery grid, centre arch → app icon.
- Texture: subtle film grain (2–3 % opacity) and a warm radial "sunlight" vignette on the ivory scenes. **No** blur glass, neon, 3D chrome, lens flares, glitch effects or particle storms.

### 5.4 Photography rules
- The photos are the hero: warm, 35 mm film feel, everyday life (morning light, a trail, dinner, the coast, family, flowers, the city), matching `website/public/photos/`.
- No faces you don't have releases for. No children's faces unless they're your own family and you're comfortable publishing them.
- Inside the app UI: seeded demo library only.

### 5.5 Device presentation
- **Frameless phone**: a rounded rectangle (radius about 9 % of width) with a thin `#24231F` bezel built in code. Don't use photo-real Pixel or Samsung renders (brand IP, and they date quickly).
- Phone angle: straight-on for UI clarity. Only the hero shot (scene 5) gets a slow 6° tilt-in.
- Show taps with a soft amber 24 px circle and ripple added in Remotion. Turn Android's own "show taps" off while recording.

### 5.6 Sound
- **Music:** warm felt piano + soft synth pad + light pulse, 88–96 BPM, building gently, with a clean ending and no fade-out at 60 s. Should feel like: morning light, nostalgic, hopeful, uncluttered.
  - Eleven Music prompt: *"Warm minimal felt piano with soft analog pad and gentle heartbeat pulse, 92 BPM, hopeful and nostalgic, sparse first 15 seconds, builds at 20 seconds, resolves cleanly at 58 seconds, no vocals, no drums fills, cinematic tech product launch."*
- **SFX:** shutter tick, soft lock click, a light whoosh on the flow path, a "done" chime. Keep them quiet (−24 to −18 dB under the music).
- **VO (if used):** close-mic, natural and unhurried, about 130 wpm. Indian English is a strength for your launch market. Consider a Hindi version with Hindi captions for India.
- **Mix:** −14 LUFS integrated, −1 dBTP true peak (YouTube loudness target).

---

## 6. Tools and skills

### 6.1 Core stack

| Tool | Role | Notes / cost |
|---|---|---|
| **Remotion 4** | Builds the whole film in React/TypeScript | Free for individuals and companies of up to 3 people, all features included. Company licence above that |
| **Remotion Agent Skills** (`remotion-dev/skills`) | Teaches Claude Code Remotion's rules for timing, sequences, media and fonts | `npx skills add remotion-dev/skills` (or `npx remotion skills add` inside the project). Released Jan 2026 |
| **Claude Code** | Writes the compositions from this plan | Run it from the Remotion project folder so it picks up the skills |
| **@remotion/transitions** | `TransitionSeries`, custom arch-wipe presentation | |
| **@remotion/google-fonts** | Instrument Serif, Inter, JetBrains Mono | |
| **@remotion/captions** + Whisper (`@remotion/install-whisper-cpp`) | Burned-in captions for the VO cut | Captions are essential: most social views are muted |
| **`<OffthreadVideo>`** | Puts the scrcpy captures inside the phone frame | Frame-accurate |
| **@remotion/lottie** (optional) | If you animate the logo in After Effects or LottieFiles | |
| **scrcpy** | Lossless real-device screen recording over USB | Free, open source |
| **adb demo mode** | Clean status bar (9:41-style fixed clock, full battery, no notifications) | See 7.2 |
| **ElevenLabs** | VO (if AI VO is used) + **Eleven Music** | Commercial rights on paid plans, but they vary by plan and use, so check the tier before publishing |
| *Alt music:* Artlist / Epidemic Sound / Musicbed | Licensed human-composed tracks | Safer for YouTube Content ID |
| **ffmpeg** | Loudness normalisation, final encodes, 9:16 checks | |
| **DaVinci Resolve (free)** *(optional)* | Final colour pass / VO mix if you prefer a timeline | |
| **Figma** *(optional)* | Storyboard frames, end card, thumbnail | |

### 6.2 Alternative: HyperFrames (HTML/GSAP)
HyperFrames (by HeyGen, Apache 2.0) turns HTML, CSS and seekable animations into deterministic MP4s and has its own agent skills (`npx skills add heygen-com/hyperframes`), including a website-to-video pipeline. **Why it might suit Ambry:** your landing page is already HTML + GSAP, so its hero, flow diagram and arch motifs could be reused almost as they are. **Why Remotion is still the default:** a more mature ecosystem, captions and transitions packages, and you already work in TypeScript. Good split: build the hero film in Remotion, and if you want a quick "website-to-video" teaser, try HyperFrames on `ambry.vikashin.tech`.

### 6.3 Claude skills to use in this workflow
- **Remotion Agent Skills** (best practices, plus studio / render commands): main build.
- **anthropic-skills:video-making**: video planning and craft checks.
- **frontend-design / design-excellence**: for the end card, thumbnail and type layout so nothing looks templated.
- **HyperFrames skills** (optional): website → teaser.

### 6.4 Not recommended
- Text-to-video AI (Sora/Veo/Kling style) for people or "memories": the uncanny results hurt trust in a privacy product. At most, use it for abstract light or texture plates.
- Template marketplaces (generic "app promo" packs): they look like everyone else's.
- Stock "hacker" imagery: hoodies, padlocks over binary, matrix rain.

---

## 7. Production workflow

### 7.1 Remotion project setup
```bash
npx create-video@latest ambry-launch --blank
cd ambry-launch
npx skills add remotion-dev/skills          # or: npx remotion skills add
npm i @remotion/transitions @remotion/google-fonts @remotion/captions @remotion/media-utils
npm run dev                                  # Remotion Studio preview
claude                                       # start Claude Code in this folder
```

Suggested structure:
```
ambry-launch/
├── public/
│   ├── photos/            # copy of website/public/photos/*.jpg (+ more you own)
│   ├── captures/          # scrcpy recordings (timeline.mp4, backup.mp4, …)
│   ├── brand/             # ambry-logo.svg, ambry-icon-1024.png, play-badge.svg
│   └── audio/             # music.wav, vo.wav, sfx/*.wav
├── src/
│   ├── theme.ts           # palette + fonts + spring presets (section 5)
│   ├── components/        # Arch, ArchMask, Phone, TapRipple, Counter, KineticText, PlayBadge, FlowDiagram, RecoveryGrid
│   ├── scenes/            # S01_Line … S11_EndCard (one file per script row)
│   ├── compositions/      # Hero60, Cut30, Teaser15, Bumper6, Builder45 (+ *_Vertical)
│   └── Root.tsx
└── remotion.config.ts
```

Copy the brand assets from the repo:
```bash
cp ../free-storage/keepsake/branding/ambry-logo.svg public/brand/
cp ../free-storage/keepsake/branding/ambry-icon-1024.png public/brand/
cp ../free-storage/website/public/photos/*.jpg public/photos/
```

### 7.2 Screen capture (real device, release build)
```bash
# Clean status bar (Android demo mode)
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command enter
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e mobile hide
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false

# Record (one clip per scene, 5–10 s each, slow deliberate gestures)
scrcpy --no-audio --max-fps=60 --video-bit-rate=20M --record=public/captures/timeline.mp4

# Exit demo mode afterwards
adb shell am broadcast -a com.android.systemui.demo -e command exit
```
Capture list: `timeline.mp4` (scroll + open photo), `backup.mp4` (encrypt toggle ON, progress → All backed up), `freeup.mp4`, `albums.mp4`, `search.mp4`, `map.mp4`, `memories.mp4`, and later `restore.mp4` once it's verified.
Tips: set dark/light mode to match each scene, warm up the thumbnail cache before recording (that's fine as long as the film never claims "instant"), turn on 120 Hz, and record each gesture 3 times so you can pick the smoothest take.

### 7.3 Master prompt for Claude Code
Paste this after the project is set up (and keep this .md in the project root):

> Read `AMBRY_LAUNCH_VIDEO_PLAN.md`. Using the Remotion skills, build composition `Hero60` (1920×1080, 30 fps, 1800 frames) that follows the scene table in §4.1 exactly. First create `src/theme.ts` with the palette, fonts and spring presets in §5. Build reusable components: `Arch` (SVG stroke draw-on), `ArchMask` (arch-shaped clip for images), `Phone` (frameless device with `<OffthreadVideo>` inside), `TapRipple`, `Counter`, `KineticText` (Instrument Serif, word-by-word reveal, italic emphasis support), `FlowDiagram`, `RecoveryGrid`, `PlayBadge`. One file per scene in `src/scenes/`. Use `TransitionSeries` with a custom arch-wipe presentation. Springs must not overshoot (`damping: 200`). No gradients except the warm radial vignette, no glows, no blur. Use placeholder videos where captures are missing. Then create `Cut30`, `Teaser15` and `Bumper6` by re-sequencing the same scenes, and `_Vertical` (1080×1920) versions that restack the layout with `useVideoConfig()`. Make every text string a prop so I can localise it.

Then iterate scene by scene in Remotion Studio ("Scene 2 photos drift too fast, cut parallax to 4 %", and so on).

### 7.4 Render and encode
```bash
npx remotion render Hero60   out/ambry-hero-60.mp4   --codec=h264 --crf=16
npx remotion render Cut30    out/ambry-30.mp4        --codec=h264 --crf=18
npx remotion render Teaser15 out/ambry-15.mp4        --codec=h264 --crf=18
npx remotion render Hero60_Vertical out/ambry-hero-60-vertical.mp4 --codec=h264 --crf=18

# Loudness check / normalise to YouTube's −14 LUFS
ffmpeg -i out/ambry-hero-60.mp4 -af loudnorm=I=-14:TP=-1:LRA=11 -c:v copy -c:a aac -b:a 320k out/ambry-hero-60-final.mp4
```
Specs: H.264 High, yuv420p, 30 fps (60 fps only if the screen captures really need it), AAC 48 kHz 320 kbps, 1080p (render 4K only if you want extra sharpness on YouTube).

---

## 8. Google Play and YouTube requirements

| Requirement | Detail |
|---|---|
| How it's attached | Play Console → Main store listing → Graphics → **Preview video**: a **YouTube URL**, not a file upload |
| URL format | Full `https://www.youtube.com/watch?v=ID`, not youtu.be, not a playlist or channel |
| YouTube settings | **Public** (or unlisted where allowed), **monetisation off** (no ads before your video), **embeddable**, **not age-restricted**, **not a Short** |
| Orientation | **Landscape 16:9** for the Play preview |
| Length | 30 s – 2 min is the usual guidance. 60 s hero is the sweet spot |
| Feature graphic | **Required** for the video to appear: 1024×500, already in `docs/store-assets/feature-graphic-1024x500.png`. The play button overlays it, so keep the centre clear and make the graphic match the film's first frame |
| First 5 seconds | Most viewers drop off early. Scene 1–2 must show *warmth + a phone photo gallery* immediately. Consider opening the Play version on scene 2 and cutting scene 1 to 1.5 s |
| Text policy | No "#1/best/top/award" text, no misleading claims, no other brands' logos |
| Testing | Use **Store listing experiments** to A/B test the hero vs. the 30 s cut later |
| YouTube metadata | Title: `Ambry: Private Photo Backup on Your Own Telegram (Android)`. Description: short description + Play link + GitHub link + "Independent app, not affiliated with Telegram." Custom thumbnail = end card with the arch |

---

## 9. Distribution plan

| Channel | Asset | Angle |
|---|---|---|
| Google Play listing | Hero 60 (16:9) | Benefit + trust |
| YouTube | Hero 60 + Builder 45 | Search: "private photo backup Android", "Telegram photo backup" |
| Instagram Reels / YouTube Shorts | Hero 60 vertical, Teaser 15 vertical | Warm memories → privacy |
| X / Threads / LinkedIn | Builder 45 + 15 s teaser | "No server, $0 infra, open source" |
| Reddit (r/androidapps, r/selfhosted, r/privacy, r/opensource, r/IndiaTech) | Builder 45 + a GIF of the flow diagram | Read each sub's self-promo rules first. Be transparent that you're the developer |
| Product Hunt | Builder 45 + gallery stills from the film | Launch day: pin the video as the first media |
| Hacker News "Show HN" | Link to repo; the video goes in the README | Technical honesty (limits section!) wins there |
| GitHub README | 10 s silent loop (MP4 or GIF) of scenes 6–7 at the top | |

**Launch sequence:** Day −3 teaser 15 s ("Coming to Google Play") → Day 0 hero + Play link everywhere → Day +2 Builder's cut for dev communities → Day +7 a "how it works" 2-minute walkthrough (screen capture + VO).

---

## 10. Schedule (about 6 working days)

| Day | Work |
|---|---|
| 1 | Lock the script and tagline. Seed the demo library and demo Telegram account. Capture all screen recordings |
| 2 | Remotion setup, theme, core components (Arch, ArchMask, Phone, KineticText) |
| 3 | Scenes 1–6 |
| 4 | Scenes 7–11, music edit to picture, SFX |
| 5 | Cutdowns + vertical versions, captions, optional VO record and mix |
| 6 | QA (checklist below), renders, YouTube upload, Play Console link, feature-graphic match |

---

## 11. QA checklist before publishing

- [ ] Every claim is in section 1.1. Nothing from 1.2 appears
- [ ] No Telegram logo or brand styling. Disclaimer is on the end card
- [ ] No real personal photos, phone numbers, usernames or recovery words visible
- [ ] App name and icon are "Ambry" in every frame (no "Keepsake" or Immich leftovers)
- [ ] Restore scene only included if restore was verified on a device
- [ ] Text is readable on a phone at 360 px wide (watch the mobile preview)
- [ ] Works muted: the story is clear from text alone
- [ ] Captions burned in for VO versions; spelling checked
- [ ] Audio −14 LUFS / −1 dBTP; music licence saved (plan tier + download receipt)
- [ ] YouTube: public/embeddable, monetisation off, not age-restricted, full URL pasted in Play Console
- [ ] Feature graphic is uploaded and visually matches the opening frame
- [ ] Remotion licence: still within the free tier (team of 3 or fewer)

---

## Sources

- Remotion licence and pricing: https://www.remotion.dev/docs/license/pricing · FAQ: https://www.remotion.dev/docs/license/faq
- Remotion Agent Skills: https://remotion.dev/skills · launch coverage: https://www.ngram.com/industry-news/remotion-skills-sh-ai-video-creation · https://aihola.com/article/remotion-agent-skills-video-creation
- HyperFrames: https://github.com/heygen-com/hyperframes · https://hyperframes.heygen.com/guides/hyperframes-vs-remotion
- Google Play preview video specs: https://support.grip.events/transfer-your-app-to-another-ios-developer-account (mirrors Google's help text) · https://appradar.com/academy/google-play-app-store-optimization/promo-video · Store listing policy: https://support.google.com/googleplay/android-developer/answer/13393723
- Apple launch storytelling: https://www.printweek.in/news/apples-launch-design-as-spectacle-story-and-strategy-60992?amp=1 · keynote editing: https://9to5mac.com/2023/06/21/apple-keynote-videos-transitions-and-editing/
- Apple privacy ads: https://techcrunch.com/?p=1797454 · https://www.fastcompany.com/90753303/apple-privacy-ad-may-2022 · https://lbbonline.com/news/apple-holds-an-auction-for-your-data-in-privacy-policy-push
- Apple handmade holiday film: https://techtrendske.co.ke/2025/11/27/apple-holiday-ad-handmade-craft-vs-coke-ai-approach/ · Shot on iPhone: https://www.adweek.com/agencies/how-apple-elevated-product-demos-into-artvertising/
- Google "Loretta": https://www.thedrum.com/creative-works/project/google-loretta · https://www.adweek.com/brand-marketing/google-returns-super-bowl-love-story/
- Google #BestPhonesForever: https://androidauthority.com/best-phone-forever-ad-3446794
- AI music licensing: https://elevenlabs.io/blog/elevenlabs-vs-suno · https://jackrighteous.com/en-us/blogs/ai-creator-tools/ai-music-commercial-rights-report-2026
- Ambry repo docs: `docs/PLAY_RELEASE.md`, `docs/PRODUCTION_READINESS.md`, `docs/LANDING_DESIGN_RESEARCH.md`, `docs/ui-ux/03_direction.md`, `docs/ui-ux/05_motion_spec.md`
