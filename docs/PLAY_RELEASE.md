# Ambry — Google Play Release Guide

> Everything needed to publish Ambry on Google Play: the steps in order, the store listing text, the Data safety answers and the permission declarations Google asks for. Status of the app itself: [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).

## 1. Release steps

| # | Step | Command / where | Notes |
|---|---|---|---|
| 1 | Choose the permanent application ID | `keepsake/mobile/android/app/build.gradle` → `applicationId` | Today `app.keepsake.photos`. Recommended: `io.github.cypherninjaa.ambry` (a namespace you control through GitHub). **Cannot change after the first upload** |
| 2 | Create the upload key (keep it and its password safe; losing it means asking Google for a key reset) | `keytool -genkeypair -v -keystore keepsake/mobile/android/key.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload` | `key.jks` and `key.properties` are git-ignored. `key.properties` holds `storePassword`, `keyPassword`, `keyAlias=upload`, `storeFile=../key.jks` |
| 3 | Provide the Telegram API credentials to the build | `.env` (`api_id`, `api_hash`) or `KEEPSAKE_TELEGRAM_API_ID` / `KEEPSAKE_TELEGRAM_API_HASH` | Register the app at <https://my.telegram.org> under the name Ambry |
| 4 | Build the App Bundle | `flutter build appbundle --release` (in `keepsake/mobile`) | Output: `build/app/outputs/bundle/release/app-release.aab` (verified 2026-11-22: 184 MB bundle, about 119 MB download on an arm64 phone). Without `key.jks` the build falls back to the debug key, which Play rejects |
| 5 | Create the app in Play Console | play.google.com/console | Enrol in **Play App Signing** (default) |
| 6 | Store listing | §2 below | Screenshots: 2–8 phone screenshots (Photos, Albums, Backup screen, viewer) |
| 7 | Privacy policy URL | <https://github.com/CypherNinjaa/free-storage/blob/main/docs/PRIVACY_POLICY.md> | Also linked in the app (account sheet → Privacy) |
| 8 | App content: Data safety, permissions, ads (none), content rating, target audience (18+ or 13+) | §3 and §4 below | |
| 9 | Closed testing track first | Play Console → Testing → Closed testing | Run the new-phone restore test on a tester's phone before production |
| 10 | Production rollout | Staged rollout (for example 20 %) | |

## 2. Store listing

**App name** (30 max): `Ambry: Private Photo Backup`

**Short description** (80 max):
`Back up photos and videos to your own Telegram account, encrypted. No servers.`

**Full description:**

```
Ambry backs up your photos and videos to private channels in your own Telegram account. There is no Ambry server and no subscription: your library lives in your Telegram, and only you hold the key.

WHY AMBRY
• Your storage, not ours: everything goes to private channels in your own Telegram account
• Encrypted on your phone first (AES-256), unlocked only with your passphrase or 24-word recovery kit
• Prefer to open your photos in Telegram too? Turn encryption off for new uploads
• Free up space: remove backed-up photos from your phone, keep them in your vault

A FULL GALLERY
• Timeline, albums, favorites, archive and trash
• Search by file name, camera, date and type
• Map of your photos, "On this day" memories
• Stream videos and download originals even after deleting them from your phone

RESTORE ON A NEW PHONE
Sign in to the same Telegram account, unlock with your passphrase or recovery words, and your library and albums come back.

GOOD TO KNOW
• Use a dedicated Telegram account for your backups
• Files larger than 1.95 GB are not backed up yet
• Some phones pause apps in the background: allow background activity for Ambry so new photos back up while it is closed

Ambry is free and open source (GNU AGPL v3), based on the Immich mobile app. It is an independent app that uses the Telegram API and is not affiliated with Telegram.
```

**Category:** Photography. **Tags:** Photo backup, Gallery. **Website:** <https://github.com/CypherNinjaa/free-storage>. **Contact email:** required by Play Console (shown on the store page).

## 3. Data safety answers (recommended)

Ambry sends data only to the user's own Telegram account, at the user's request; the developer receives nothing.

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** (transmitted off the device to the user's Telegram account) |
| Is all collected data encrypted in transit? | **Yes** (Telegram's MTProto; files are also encrypted on the device by default) |
| Can users request that data is deleted? | **Yes**: delete in the app (trash → permanent delete removes it from Telegram) or delete the channels in Telegram |
| **Photos and videos** | Collected · not shared · required · purpose: App functionality (backup) |
| **Personal info → Phone number** | Collected · not shared · required · purpose: Account management (Telegram sign-in) |
| **Location → Precise location** | Collected (GPS inside photo metadata is backed up with the photo) · not shared · optional · purpose: App functionality |
| **App activity, device IDs, diagnostics, financial info** | Not collected (no analytics, ads or crash reporting) |

## 4. Permission declarations Play Console asks for

| Permission | Declaration |
|---|---|
| `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO` (Photo and video permissions policy) | Core functionality: Ambry is a gallery and backup app that needs ongoing access to all photos and videos to back them up; the photo picker cannot do that |
| `FOREGROUND_SERVICE_DATA_SYNC` | Uploading photos and videos to the user's Telegram account; the user starts backups and sees a notification while they run |
| `MANAGE_MEDIA` | Optional: lets "Free up space" and trash move items to the device trash without a prompt per item |
| `ACCESS_MEDIA_LOCATION` | Keeps the GPS location inside backed-up photos (shown on the map) |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | Only when the user taps "show my location" on the map |
| `POST_NOTIFICATIONS` | Backup progress notifications |
