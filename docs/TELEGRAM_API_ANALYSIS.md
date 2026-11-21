# Telegram API Analysis — Can Telegram channels act as photo/video storage?

> **Snapshot:** Bot API **10.4** (changelog entry dated 2026-11-09), pages fetched **2026-11-18**. Raw copies are in `../sources/<name>/`; they are untrusted HTML snapshots, kept for traceability.
> **Role in the project:** verified Telegram reference for the current plan, `ARCHITECTURE_SERVERLESS_ANDROID.md`. That plan uses TDLib on the phone with a dedicated Telegram account: no server, no bot.
> **Evidence tags:** **[DOC]** official Telegram documentation · **[SRC]** `tdlib/telegram-bot-api` source (master, fetched 2026-11-18) · **[3P]** third party · **[PoC]** undocumented; must be measured · **[INFER]** reasoned inference, not documented.

Primary sources:

| Source | URL | Local copy |
|---|---|---|
| Bot API reference | https://core.telegram.org/bots/api | `sources/tg-bot-api/` |
| Bot FAQ | https://core.telegram.org/bots/faq | `sources/tg-bot-faq/` |
| Bot features | https://core.telegram.org/bots/features | `sources/tg-bot-features/` |
| Bot API changelog | https://core.telegram.org/bots/api-changelog | `sources/tg-bot-api-changelog/` |
| Local Bot API server README + source | https://github.com/tdlib/telegram-bot-api | `sources/tg-local-server-readme/`, `sources/tg-bot-api-src-*` |
| MTProto files | https://core.telegram.org/api/files | `sources/tg-api-files/` |
| MTProto file references | https://core.telegram.org/api/file-references | `sources/tg-api-file-references/` |
| MTProto client config | https://core.telegram.org/api/config | `sources/tg-api-config/` |
| `channels.getMessages`, `upload.getFile`, `messages.getHistory` | https://core.telegram.org/method/… | `sources/tg-method-*` |
| TDLib `downloadFile`, `checkAuthenticationBotToken` | https://core.telegram.org/tdlib/docs/ | `sources/tdlib-*` |
| Bot Platform Developer Terms | https://telegram.org/tos/bot-developers | `sources/tg-tos-bot-dev/` |
| Telegram ToS | https://telegram.org/tos | `sources/tg-tos/` |
| API ToS | https://core.telegram.org/api/terms | `sources/tg-api-terms/` |
| Telegram FAQ | https://telegram.org/faq | `sources/tg-faq/` |

---

## 1. The layers you must not conflate

| Layer | What it is | Who enforces limits | Relevant limits |
|---|---|---|---|
| **A. Cloud Bot API** (`api.telegram.org`) | Telegram-hosted HTTP gateway | Telegram | Upload 50 MB (photos 10 MB); **download 20 MB** |
| **B. Local Bot API server** (`telegram-bot-api --local`) | Same HTTP API, self-hosted, built on TDLib; needs your `api_id`/`api_hash` | You (process) + Telegram (MTProto backend) | Upload **2000 MB**; download **no size limit**; whole-file `getFile` |
| **C. MTProto as a bot** (TDLib / GramJS / Telethon logged in with a bot token) | Native protocol | Telegram | 4000 parts × 512 KiB ≈ **2000 MiB**; ranged downloads; `channels.getMessages` allowed; **no history listing** |
| **D. MTProto as a user account** | A real (or dedicated) user session | Telegram | 2000 MiB, or 4000 MiB with Premium; can create channels and list history; **account-ban and ToS risk** for automation |
| **E. Channel/platform policy** | ToS, Bot Developer Terms, privacy rules | Telegram, unilaterally | §5.2(e) "cloud storage sites"; §5.2(f) rate-limit circumvention; §6.3 no data guarantees |

---

## 2. Answers to the 20 research questions

### Q1. Can a bot create or manage a private channel?
- **Create: No.** The Bot API's `create*` methods are only `createChatInviteLink`, `createChatSubscriptionInviteLink`, `createForumTopic`, `createInvoiceLink`, `createNewStickerSet`. There is no channel or group creation **[DOC]**. A human (or an MTProto **user** session, layer D) must create the channel.
- **Manage: Yes, once admin.** The bot can post, edit and delete messages, create invite links, change title/photo, pin, and promote/restrict (rights permitting). See `promoteChatMember` and `ChatAdministratorRights` **[DOC]**.

### Q2. How can a bot become an administrator of a channel?
- **Manually:** the channel owner adds the bot in the Telegram app under Administrators and grants rights.
- **Guided (best UX):** the bot sends a reply keyboard with `KeyboardButtonRequestChat{ chat_is_channel: true, chat_is_created: true, user_administrator_rights: {...}, bot_administrator_rights: {can_post_messages, can_edit_messages, can_delete_messages}, bot_is_member: true }`.
  - The user picks a channel they own. The docs say: *"The bot will be granted requested rights in the chat if appropriate."* **[DOC]**
  - The bot receives the chat id in `ChatShared` and a `my_chat_member` update **[DOC]**.
- **Managed bots (Bot API 9.6, 2026-04-03):**
  - A "manager" bot can have users create bots it manages, via `KeyboardButtonRequestManagedBot` or `t.me/newbot/{manager}/{suggested}` links.
  - It can then read their tokens with `getManagedBotToken` and rotate them with `replaceManagedBotToken` **[DOC]**.
  - This removes the "copy a token from BotFather" step. But it centralises every user's bot token in one operator, which is relevant to Bot Developer Terms §5.2(f) (Q20).

### Q3. Can a bot upload photos and videos to a channel?
Yes: `sendPhoto`, `sendVideo`, `sendDocument` and `sendMediaGroup` (2-10 items; documents can be grouped only with documents) to the channel's `chat_id` **[DOC]**. The bot needs `can_post_messages`.

### Q4. Can it upload as a document to preserve original quality?
- **Yes, use `sendDocument`.** "Bots can currently send files of any type of up to 50 MB in size" on the cloud API **[DOC]**.
- Pass `disable_content_type_detection=true` to stop server-side type detection **[DOC]**.
- **Do not use `sendPhoto` for originals:**
  - limits are 10 MB, `width + height ≤ 10000`, aspect ratio ≤ 20 **[DOC]**;
  - Telegram returns **multiple `PhotoSize` renditions** ("Resending a photo by file_id will send all of its sizes") **[DOC]**;
  - the docs give no guarantee that your original bytes are kept **[INFER]**.
- `sendVideo` would make Telegram treat the file as a playable video. With encryption (`ARCHITECTURE_SERVERLESS_ANDROID.md` §6), everything is an opaque document anyway.

### Q5. Can the bot retrieve uploaded media later?
- **Cloud API:**
  - `getFile` returns a `File` with `file_path`; download from `https://api.telegram.org/file/bot<token>/<file_path>`.
  - The link is "guaranteed … valid for at least 1 hour".
  - **"For the moment, bots can download files of up to 20MB in size."** **[DOC]**
  - The source constant is `MAX_DOWNLOAD_FILE_SIZE = 20 << 20` (20,971,520 bytes) in `Client.h:72`; it is enforced only when not in local mode (`Client.cpp`, `do_get_file`) **[SRC]**.
- **Local server (`--local`):** "Download files without a size limit" and "Receive the absolute local path as a value of the file_path field" **[DOC]**.
  - The server first downloads the **whole file** into its working directory: `td_api::downloadFile(file_id, 1, 0, 0, false)` = offset 0, limit 0 **[SRC]**.
- **MTProto:** `upload.getFile(location, offset, limit)` — "Both users and bots can use this method" **[DOC]**.

### Q6. How do `file_id` and `file_unique_id` work? **[DOC]**
- `file_id`: *"Identifier for this file, which can be used to download or reuse the file."*
  - *"file_id is unique for each individual bot and can't be transferred from one bot to another."*
  - *"file_id uniquely identifies a file, but a file can have different valid file_ids even for the same bot."*
- `file_unique_id`: *"Unique identifier for this file, which is supposed to be the same over time and for different bots. Can't be used to download or reuse the file."*
- `file_size`: may exceed 2^31, but has at most 52 significant bits → store as `bigint`.

**Design consequence:**

| Field | Role |
|---|---|
| `file_unique_id` | **Identity / dedupe key** |
| `file_id` | **Cached access handle** for one bot |
| `(chat_id, message_id)` | **Durable locator** used to re-derive handles |

### Q7. Can `file_id` be reused for downloading and sending?
Yes, for both `getFile` and re-sending: "There are no limits for files sent this way" **[DOC]**. Restrictions:
- you cannot change the type (document ↔ video ↔ photo);
- thumbnails cannot be re-sent;
- a `file_id` only works for the bot that received it **[DOC]**.

### Q8. Are file IDs persistent?
- **The docs say yes, the terms say "don't rely on it":**
  - Bot FAQ: *"Can I count on file_ids to be persistent? Yes, file_ids can be treated as persistent."* **[DOC]**
  - Bot Developer Terms §6.3: Telegram "makes no guarantee that any data it stores in connection with your TPA … will remain available", and you "should not assume that the availability of any such data from Telegram will be perpetual or for a specific duration, **even if otherwise stated in the relevant documentation or source code**" **[DOC]**.
- Underneath, MTProto `file_reference`s **expire** and must be refreshed from their source object (e.g. the message) **[DOC]**. The Bot API server/TDLib does this for you.
- **Design:** persist `(chat_id, message_id, file_unique_id)` and treat `file_id` as refreshable.

### Q9. What happens if the bot is removed from a channel?
- The bot receives a `my_chat_member` update (status `left`/`kicked`). Subsequent sends and edits to that chat fail **[DOC]**.
- The **messages stay in the channel**; they belong to the channel, not the bot. Re-adding the bot restores access, and `message_id`s are unchanged **[INFER]**.
- **Unknown:** whether previously obtained `file_id`s still download after removal. Access checks happen when the file reference is refreshed **[PoC — test explicitly]**.

### Q10. Can a channel contain millions of media messages?
- **No documented per-channel message-count or storage cap was found** in the Bot API, FAQ, MTProto config or ToS pages **[DOC: absence]**.
- `message_id` is an `Integer`. In specific cases (e.g. a video sent to a big chat) Telegram may **schedule** a message, return `message_id = 0` and leave the message "unusable until it is actually sent" **[DOC]**. Handle `0` as "pending".
- Consumer marketing says "unlimited cloud storage" (Telegram ToS, Premium section) and "unlimited number of photos, videos and files … of up to 2 GB each" (FAQ) **[DOC]**. That is a statement about the consumer messenger, not an SLA for bot-driven storage. See Q20.
- **[PoC]** Behaviour at 10^5-10^6 messages per channel (latency, `getMessages`, export size) is unmeasured.
- **Practical guidance:** "seal" a channel after N objects or N TB (e.g. 250k messages or 2 TB) and roll to a new one. That limits blast radius and export size; it is not for throughput (see Q12/Q20).

### Q11. Actual upload and download size limits

| Path | Upload | Download | Source |
|---|---|---|---|
| Cloud Bot API, multipart | **10 MB photos, 50 MB other** | **20 MB** | Bot API "Sending files", `getFile`, `File` **[DOC]** |
| Cloud Bot API, by URL | 5 MB photos, 20 MB other (`sendDocument` by URL: only PDF/ZIP) | — | **[DOC]** |
| Cloud Bot API, by `file_id` | no limit (re-send) | — | **[DOC]** |
| Local Bot API server `--local` | **2000 MB** | **no size limit** (whole-file) | README + Bot API "Using a Local Bot API Server" **[DOC]** |
| MTProto (bot or non-Premium user) | `upload_max_fileparts_default = 4000` × max part 512 KiB = **2,097,152,000 bytes (2000 MiB)** | unlimited (chunked) | `/api/files`, `/api/config` **[DOC]** |
| MTProto, Premium user | `upload_max_fileparts_premium = 8000` → ≈ **4000 MiB** | unlimited | **[DOC]** |

Notes:
- The cloud download limit is 20 MiB = 20,971,520 bytes **[SRC]**.
- "2000 MB" in the local-server docs matches 4000 × 512 KiB. **[PoC]** Test the exact boundary bytes.
- Bots cannot be Premium **[INFER]**, so plan for ≈ 2000 MiB per message.

### Q12. Bot API rate limits **[DOC]** (Bot FAQ "My bot is hitting limits")
- *"In a single chat, avoid sending more than one message per second. We may allow short bursts … eventually you'll begin receiving 429 errors."*
- *"In a group, bots are not be able to send more than 20 messages per minute."*
- *"For bulk notifications, bots are not able to broadcast more than about 30 messages per second, unless they enable paid broadcasts."*
  - Paid broadcasts allow up to 1000 msg/s at 0.1 Stars per message, but need **≥ 100,000 Stars and ≥ 100,000 monthly active users**. Not applicable to a storage bot.
- **Channels are not named explicitly.** **[PoC]** Plan for **20 msg/min per channel** and treat 60/min ("one per second per chat") as an optimistic upper bound. Each `sendMediaGroup` item may count as one message.
- **Download (`getFile`) and edit rate limits are undocumented.** **[PoC]**
- Errors carry `parameters.retry_after` (`ResponseParameters`); honour it exactly **[DOC]**.
- **MTProto adds speed throttling for non-Premium accounts:** `FLOOD_PREMIUM_WAIT_X` means the upload or download speed is being limited "because the current account does not have a Premium subscription". For uploads, "this error can only be received when the user has uploaded tens of gigabytes or more" **[DOC]**. Premium ToS §7.5 describes Premium as "removal of all relevant speed limits" **[DOC]**.
  - **[PoC]** Whether and how this applies to bot accounts. It is the single most important throughput unknown for multi-terabyte libraries.

### Q13. Can multiple bots be used?
- **Technically yes.** Each bot has its own token, its own limits and its own `file_id` namespace. Several bots can be admins of one channel.
- A second bot cannot use the first bot's `file_id`s **[DOC]**. It must re-derive its own by forwarding or `getMessages` on the `message_id`.
- **Policy:**
  - Using extra bots **to multiply throughput** is "circumventing rate limits" → prohibited (Bot Dev Terms §5.2(f)) **[DOC]**.
  - A standby admin bot for **recovery** (token compromise, rotation) is a reasonable, non-circumventing use.

### Q14. Can multiple private channels be used?
- Yes. A bot can be an admin of many channels.
- The human owner's account is capped by `channels_limit_default = 500` channel/supergroup memberships (1000 with Premium) **[DOC: /api/config]**.
- Use multiple channels for **sealing, sharding by time or user, and blast-radius control**. Do not use them to multiply message rates.

### Q15. Can we use a self-hosted Bot API server?
- **Yes.** `tdlib/telegram-bot-api`, Boost Software License 1.0 **[DOC]**.
- **Requirements:**
  - `--api-id` and `--api-hash` from my.telegram.org (your app credentials; API ToS §2.1 "You must obtain your own api_id");
  - call `logOut` on the cloud API first (you cannot log back into the cloud for 10 minutes);
  - HTTP only (needs a TLS-terminating proxy if remote);
  - default port 8081 **[DOC]**.
- **Flags of note:** `--local`, `--dir` (working directory), `--files-dir`, `--temp-dir`, `--max-webhook-connections`, `--http-ip-address`, `--max-connections`, `--proxy` **[SRC: telegram-bot-api.cpp]**.

### Q16. Restrictions of the local Bot API server
1. Telegram's server-side limits still apply: 2000 MB upload, per-chat rate limits, ToS.
2. **`getFile` is whole-file.** The answer comes only after `is_downloading_completed_`. There are no partial reads **[SRC]**.
3. In `--local` mode `file_path` is an **absolute path on the bot server's filesystem**, so Immich must share that volume (or the bot server must run on the same host).
4. **Cache growth.** Downloaded files accumulate in the working directory. The README documents no eviction **[PoC: TDLib storage optimizer behaviour; plan an external cleaner]**.
5. A bot must be logged in on **one** server at a time, or updates may be lost. Moving servers means `deleteWebhook` → `close` → move the bot's sub-directory (by bot user id) **[DOC]**.
6. `close` returns `429` during the first 10 minutes after launch **[DOC]**.
7. Single-instance per bot. HA means a warm standby, not active/active **[INFER]**.
8. `api_id`/`api_hash` are confidential credentials. Actions taken with them "will be deemed as taken by you" (Bot Dev Terms §4.5) **[DOC]**.
9. No `getMessage` and no history listing (same Bot API surface).

### Q17. Can Telegram media be streamed without downloading the whole file?
- **Bot API (cloud or local): No.** `getFile` is whole-file; only after that can you serve Ranges from local disk **[SRC]**. (`supports_streaming` on `sendVideo` affects Telegram clients only.)
- **MTProto/TDLib: Yes.**
  - `upload.getFile(offset, limit)` rules: `offset` divisible by 4 KB, `limit` divisible by 4 KB, `1048576 % limit == 0`, and each request must stay inside one 1 MB chunk. With `precise`: 1 KB alignment, `limit ≤ 1 MB` **[DOC]**.
  - TDLib `downloadFile(file_id, priority, offset, limit, synchronous)`: "limit — Number of bytes which need to be downloaded starting from the offset position…; use 0 to download without a limit" **[DOC]**.
- Encrypted content stays streamable if it is encrypted in independent 1 MiB segments (`ARCHITECTURE_SERVERLESS_ANDROID.md` §6).

### Q18. Can media be retrieved by message ID?
- **Bot API: no direct method.** There is no `getMessage(s)` for chats (method list checked) **[DOC]**. Workarounds:
  - `forwardMessage(from_chat_id, message_id)` to a private scratch chat **returns the full `Message`**, including a fresh `document.file_id`. It costs one send (rate-limited) plus a cleanup delete **[DOC]**.
  - `editMessageCaption`/`editMessageReplyMarkup` on the bot's own channel post returns the edited `Message` **[DOC]**. It is also a write.
  - `copyMessage` returns only a `MessageId`, which is useless here **[DOC]**.
- **MTProto: yes.** `channels.getMessages` — "Both users and bots can use this method" **[DOC]**.
- **Listing history: bots cannot.** `messages.getHistory` — "Only users can use this method" **[DOC]**.
  - **Consequence: your database is the only index.** If it is lost, rebuilding needs a user session or a Telegram Desktop export.

### Q19. What happens when a media message is deleted?
- The message disappears. Whether the underlying file stays reachable via an old `file_id` is **undocumented**, and §6.3 says not to rely on availability **[PoC — assume lost]**.
- **`deleteMessage` limitations are self-contradictory for this case** **[DOC]**:
  - *"A message can only be deleted if it was sent less than 48 hours ago."*
  - **and** *"If the bot has can_delete_messages administrator right in a supergroup or a channel, it can delete any message there."*
  - **[PoC]** Whether a bot can delete its own channel posts older than 48 h. Your "delete from library" feature depends on it.
  - Mitigations: crypto-shredding (wipe the file's key, `ARCHITECTURE_SERVERLESS_ANDROID.md` §6), or `editMessageMedia` to replace the document with a 1-byte file. A user account that owns the channel is not bound by this bot rule **[PoC U3]**.
- `deleteMessages` takes 1-100 IDs and *"If some of the specified messages can't be found, they are skipped"* **[DOC]**.

### Q20. Terms of Service and policy restrictions relevant to this use case

**This is the most important finding of the study.**

| Clause | Text (abridged, quoted) | Impact |
|---|---|---|
| **Bot Developer Terms §5.2(e)** | *"You must not leverage your TPA and, by extension, Bot Platform in conjunction with external interfaces (i.e., frontends), frameworks or tools, to develop external services or applications that diverge significantly from the intended use cases of Bot Platform **(e.g., cloud storage sites)**."* | **Directly names this use case.** An Immich frontend using a bot as its storage backend is an external application using Bot Platform as cloud storage |
| §5.2(f) | *"must not attempt to circumvent or otherwise undermine Telegram rate limits … must not operate by proxy (i.e., using Bot API credentials supplied by other users) in an attempt to circumvent bans or content moderation."* | Rules out multi-bot sharding for throughput. Makes "users paste their bot tokens into our hosted service" a risky pattern |
| §6.3 | *"Telegram may delete or make inaccessible whole chats, messages, media and files sent to and from your TPA at any time … makes no guarantee … will remain available, uncorrupted …"*; design so as to "nullify the impact of partially or fully losing any data"; "if you delete, compromise or otherwise lose access to [the owning] account … all TPA it created may be terminated" | Telegram cannot be the **only** copy |
| §4.2 | Delete user data on request, when no longer needed, on cessation, or on lawful request | Deletion must work (Q19) |
| §4.4 | *"Make sure user data is always encrypted at rest and stored separately from its encryption key"* | Matches the envelope-encryption design |
| §4.5 | Credentials (API ID, hash, tokens) must not be made public; misuse is attributed to you | Secret management |
| §10, §10.1, §12.3 | Termination for non-compliance; unilateral discontinuation; "as is", no uptime or availability commitment | No SLA |
| API ToS §1.5, §2.1 | No use of Telegram data to train AI/ML models; must use your own `api_id` | Training is not in scope (inference on the user's own photos), but keep ML **off** data fetched from Telegram where possible: run ML on local previews (already the case) |
| Telegram ToS | Spam, scams, illegal content on public channels prohibited; "Failure to comply … may result in a temporary or a permanent ban" | Standard |
| Telegram FAQ (security) | Cloud chats use **server-client** encryption; only Secret Chats are end-to-end | Telegram can technically read channel content → **encrypt before upload** |
| Telegram FAQ (accounts) | Inactive accounts self-destruct (default **18 months**); deleting the account leaves channels "orphaned … admins retain their rights" | Ownership/continuity risk |

**Bottom line:** using Telegram as primary storage for a **public or commercial** photo-backup product is explicitly prohibited by §5.2(e) and structurally discouraged by §6.3. A **personal, self-hosted** experiment is still an "external application … (e.g., cloud storage sites)" use. It carries termination risk, though it is less exposed than a service. Nothing in the official material supports calling it "unlimited storage".

**For the current plan:** these Bot Platform clauses govern **bots**. The chosen design uses a dedicated **user account** through TDLib, which falls under the API Terms of Service for client apps instead (`ARCHITECTURE_SERVERLESS_ANDROID.md` §2). The absence of any availability guarantee still applies in practice.

---

## 3. Rate-limit-aware design implications

- **One upload queue on the phone.** Pace posts per channel (start at ~20/min until U1 is measured) and pause exactly as long as `FLOOD_WAIT_X` / `retry_after` says.
- **One message per object.** Do not batch albums until the PoC shows whether they count as one message or as N.
- **Throughput expectations at 20 posts/min:**

  | Assets | Upload time |
  |---|---|
  | 10,000 | 8.3 h |
  | 100,000 | 3.5 days |
  | 1,000,000 | 34.7 days |

  Photo-heavy libraries are **message-rate bound, not bandwidth bound** (`ARCHITECTURE_SERVERLESS_ANDROID.md` §9).
- **Verification must not cost posts.** Use TDLib `getMessages` (read-only) rather than forwards or edits.

## 4. Transport comparison and recommendation

| Criterion | Cloud Bot API | Local Bot API server | TDLib/MTProto (bot) | MTProto (user) |
|---|---|---|---|---|
| Max object | 50 MB | 2000 MB | 2000 MiB | 2000/4000 MiB |
| Restore any original | ❌ (>20 MB) | ✅ | ✅ | ✅ |
| Range/streaming | ❌ | ❌ | ✅ | ✅ |
| Lookup by `message_id` | ❌ (workarounds) | ❌ (workarounds) | ✅ | ✅ |
| History listing | ❌ | ❌ | ❌ | ✅ |
| Android integration | plain HTTPS | n/a (needs a server) | TDLib native library (official Java/JNI build or a Flutter binding) | same |
| Credentials | bot token | bot token + `api_id`/`api_hash` | bot token + `api_id`/`api_hash` | phone login + `api_id`/`api_hash` |
| Policy exposure | §5.2(e) | §5.2(e) | §5.2(e) + API ToS | §5.2(e) N/A, but API ToS + account-ban risk for automation |
| Fit for the no-server plan | Fallback "lite mode" only (files cut into ~19 MB pieces) | ❌ needs a server | Possible, but bot terms §5.2(e) apply and history cannot be listed | ✅ **Chosen**: TDLib on the phone with a dedicated account |

## 5. Usage profile for the chosen design

The project uses **TDLib on the phone, logged into a dedicated Telegram account**. Data layout, encryption and recovery are in `ARCHITECTURE_SERVERLESS_ANDROID.md` §5–§6. The Telegram rules that design relies on:

1. Upload originals as **documents** with automatic type detection off (`inputMessageDocument.disable_content_type_detection` **[DOC]**). Always encrypted. Private channel with no username and no invite links.
2. Keep each object ≤ 2000 MiB including encryption overhead (4000 MiB if the storage account has Premium **[DOC]**). Split larger files into parts.
3. Store `chat_id`, `message_id`, `file_unique_id`, size and checksums in the phone's index. Re-fetch file handles with `getMessages` when needed **[DOC]**.
4. Put an encrypted recovery record in every caption, so the index can be rebuilt by reading the channel history (`getChatHistory`, user accounts only **[DOC]**).
5. Honour flood waits (`FLOOD_WAIT_X`) exactly. Never use extra accounts to go faster.

## 6. Unknowns that the Phase-1 PoC must measure

| # | Question | Why it matters |
|---|---|---|
| U1 | How many documents a dedicated user account can post to its own channel per minute/day before `FLOOD_WAIT` | First-backup duration |
| U2 | Sustained upload/download MB/s from a phone via TDLib, and when `FLOOD_PREMIUM_WAIT` speed limits start for non-Premium accounts ("tens of gigabytes" **[DOC]**) | Backup and restore time |
| U3 | Deleting old channel posts as the channel owner (expected to work, unlike the bot 48 h rule) | Delete feature, privacy |
| U4 | Stability of message ids and file handles over months; re-fetch via `getMessages` | Index durability |
| U5 | Exact max upload bytes (boundary test at 2,097,152,000 ± 1) | Size policy, splitting |
| U6 | TDLib cache growth on the phone and safe cleanup | Phone storage |
| U7 | `getChatHistory` / `searchChatMessages` speed on channels with 10^5–10^6 messages | Index rebuild time |
| U8 | Whether Telegram restricts a new account that uploads heavily from day one | Account safety |
