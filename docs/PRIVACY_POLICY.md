# Ambry Privacy Policy

_Last updated: 22 November 2026_

Ambry is a photo and video backup app. It stores your library in **your own Telegram account**, in private channels that the app creates for you. Ambry has **no servers**: the developer never receives, stores or can access your photos, videos, account details or usage data.

## What Ambry accesses on your phone

| What | Why |
|---|---|
| Photos and videos you choose to back up | To upload them to your private Telegram channels and to show them in the app |
| Location stored inside your photos (EXIF/GPS) | To show photos on the map and keep their metadata in your backup |
| Your location (only if you tap "show my location" on the map) | To centre the map on you. It is not stored or sent anywhere |
| Notifications | To show backup progress |
| Network access | To talk to Telegram |

## Your Telegram account

You sign in with a Telegram phone number inside the app (we recommend a dedicated account). The sign-in uses Telegram's official library (TDLib) directly between your phone and Telegram. Your phone number, login code and two-step password go only to Telegram. The Telegram session is stored on your phone, encrypted with a key held in the Android Keystore.

Ambry is an independent app and is not affiliated with Telegram. Telegram's own privacy policy applies to data stored in your Telegram account: <https://telegram.org/privacy>.

## Where your photos go

- Photos, videos and the app's library index are uploaded **only** to private Telegram channels owned by your account.
- **Encryption on (default):** files are encrypted on your phone before upload (AES-256-GCM). Only someone with your vault passphrase or 24-word recovery kit can open them. Telegram and the developer cannot.
- **Encryption off (your choice):** new uploads are stored as ordinary files, which you can open in Telegram. Anyone with access to your Telegram account, and Telegram itself, can see them. The library index and album names stay encrypted.

## What the developer collects

Nothing. Ambry has no analytics, no advertising, no crash reporting to the developer and no accounts with the developer. The app's diagnostic log stays on your phone; you can choose to share it yourself.

## Map tiles

When you open the map, map images are downloaded from OpenFreeMap (<https://openfreemap.org>). Like any website, that service sees your IP address and which map area you view. No photos or personal data are sent.

## Deleting your data

- Delete photos from your vault inside the app (they go to the trash for 30 days, then are deleted from Telegram).
- Uninstalling Ambry removes all app data from the phone. Your backup stays in your Telegram channels until you delete those channels in Telegram.

## Children

Ambry is not directed at children under 13.

## Changes

Changes to this policy are published at this page with a new date.

## Contact

Ambry is developed by **CypherNinjaa**. Questions about this policy or your data: open an issue at <https://github.com/CypherNinjaa/free-storage/issues>.

Source code: <https://github.com/CypherNinjaa/free-storage> (GNU AGPL v3).
