# Phase 2 — Keepsake Fork Skeleton Log

> **Tracks:** [ARCHITECTURE_SERVERLESS_ANDROID.md](ARCHITECTURE_SERVERLESS_ANDROID.md) §4 & §11 (Phase 2).
> **App Name:** **Keepsake** (`app.keepsake.photos` / debug `app.keepsake.photos.debug`).
> **Telegram API ToS Compliance:** No "Telegram" in app name; no Telegram logo; explicit Telegram API disclosure on onboarding Step 1 and in the account dialog.
> **Source location:** `../keepsake/mobile/` (copied from `../immich/mobile/` @ `f005e0c`; `../immich/` remains untouched).

---

## 1. Phase 2 Deliverables Completed

| Deliverable | Files Modified / Created | Status |
|---|---|---|
| Fork & Rebrand (`Keepsake`, `app.keepsake.photos`) | `android/app/build.gradle`, `lib/main.dart`, `lib/widgets/common/immich_title_text.dart`, `lib/widgets/common/immich_sliver_app_bar.dart` | ✅ Done |
| Replace `AuthGuard` with local onboarding guard | `lib/routing/auth_guard.dart` | ✅ Done |
| 3-step Serverless Onboarding (Dedicated Telegram Account + Passphrase + 24-Word Recovery Kit) | `lib/pages/login/login.page.dart`, `lib/domain/utils/recovery_kit.dart`, `lib/providers/auth.provider.dart`, `lib/services/auth.service.dart` | ✅ Done |
| Serverless Splash, Lifecycle & ServerInfo (zero remote server calls, OpenFreeMap tiles) | `lib/pages/common/splash_screen.page.dart`, `lib/providers/app_life_cycle.provider.dart`, `lib/providers/server_info.provider.dart` | ✅ Done |
| Hide server-only screens (Shared Links, Partners, Networking, Passkeys, Server Info) | `lib/presentation/pages/library.page.dart`, `lib/pages/common/settings.page.dart`, `lib/widgets/common/app_bar_dialog/app_bar_dialog.dart` | ✅ Done |
| Full Immich codegen + AGP 9.1.1 / Gradle 9.3.1 / Flutter 3.50.1 build | `android/settings.gradle`, `android/build.gradle`, `android/gradle.properties`, `android/gradle/libs.versions.toml`, `android/gradle/wrapper/gradle-wrapper.properties` | ✅ Built & installed |

---

## 2. Build Command (Reproducible)

```powershell
cd D:\immich-telegram-research\keepsake\mobile
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-21.0.8.9-hotspot"
$env:PATH = "C:\flutter\bin;$env:JAVA_HOME\bin;$env:PATH"
flutter build apk --debug --target-platform android-arm64 --android-skip-build-dependency-validation
```

### Build Notes (Flutter 3.50.1 + AGP 9.1.1)
- `flutter` constraint in `pubspec.yaml` relaxed from `3.47.9` to `>=3.47.0`; unused `native_core` path dependency removed (was only imported by `integration_test/native_core_test.dart`).
- Upgraded Gradle wrapper to `9.3.1`, AGP to `9.1.1`, Kotlin to `2.4.10`, KSP to `2.3.14` (keeping `kotlin.plugin.serialization` at `2.1.0` for `background_downloader-9.5.6`).
- Added `resValues true` in `android/app/build.gradle` (opt-in under AGP 9).
- Added `kotlin.incremental=false` + `kotlin.compiler.execution.strategy=in-process` in `gradle.properties` to avoid a Windows Kotlin 2.4.10 incremental `.tab` cache lock bug.
- Added targeted hooks in `android/build.gradle` for `:maplibre_gl` (applies `org.jetbrains.kotlin.android` under `android.builtInKotlin=false`) and `LibraryAndroidComponentsExtension.finalizeDsl` to ensure older plugins (`:bonsoir_android`) compile against API 36.
- Generated `lib/data/db/main/database.steps.dart` via `dart run drift_dev schema steps drift_schemas/main/ lib/data/db/main/database.steps.dart`.

## 3. Correction (2026-11-21, during Phase 3)

- **The `native_core` dependency is not unused.**
  - Its Flutter build hook compiles Immich's Rust crates into `libnative_core_ffi.so`.
  - `android/.../NativeBuffer.kt` loads that library at startup, via `HttpClientManager` → `NetworkRepository.init`.
  - Removing the dependency caused `UnsatisfiedLinkError: dlopen failed: library "libnative_core_ffi.so" not found` on launch.
- **Fixed in Phase 3:**
  - `../native/` was copied into `keepsake/native/`, and the `native_core` path dependency was restored, together with `integration_test/native_core_test.dart`.
  - The build machine needs **rustup**: the hook runs `rustup target add` and `rustup run 1.99.1 cargo build`, so a standalone Rust install cannot build it.
  - Install rustup once, then build with `%USERPROFILE%\.cargo\bin` on `PATH` (see `PHASE3_TELEGRAM_STORE_LOG.md`).
