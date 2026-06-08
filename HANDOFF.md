# TangleX — Clean-slate UI handoff

Date: 2026-06-08
Branch: `feat/clean-slate-ui`
Author of this doc: previous Claude session

If you are reading this, you are picking up TangleX after a deliberate
demolition of the old UI layer. The Flutter "core" — FFI bindings, the
SimpleX-backed service, data parsers, models, providers, localization —
is intact and proven; only the UI was scrapped. Your job is to write a
new UI from scratch, against the contract documented below.

**Do not skim. Read every section once before touching a single file.**

---

## 1. Why this happened

The previous UI (~6 500 lines spread across `lib/src/ui/`) had grown into
an entangled monolith that was actively slowing iteration:

- `chat_screen.dart` alone was 1 832 lines mixing data loading, event
  handling, sending, audio playback, scroll logic and three different
  bottom-sheet flows.
- Two failed attempts at incremental cleanup (`feat/chat-screen-rewrite`,
  `feat/design-system`) shipped style regressions, missing features, and
  inconsistent visual language. Both were rejected by the user.
- Design language was hand-rolled (~6 hardcoded palettes, ~10 random
  border-radius values, ~3 "almost the same" accent blues). The user
  prefers Material 3 (see § 9) — none of the previous code aligned with
  that.

After the third dead-end the user said: "remove the client, keep the
core, write from scratch". That is what this branch is.

### Other branches in origin

- `main` — last stable code with the old UI (the demolition baseline).
  Use this for "how did the old chat behave" reference only.
- `feat/design-system` — abandoned design-token attempt. **Ignore.**
- `feat/chat-screen-rewrite` — abandoned chat-screen rewrite. **Ignore.**

---

## 2. Current state of the repo

```
lib/
  main.dart                                 minimal bootstrap (see § 3)
  src/
    data/
      audio_player_holder.dart              singleton AudioPlayer (just_audio)
      chat_message_parser.dart              parseChatItem() + media utils
      pin_store.dart                        local-only message pins
    domain/
      chat_models.dart                      UiMessage / UiImage / AudioItem / …
    ffi/
      tanglex_bindings.dart                 ffigen-generated C bindings
      tanglex_native.dart                   typed Dart wrapper
    localization/
      app_localizations.dart                en + ru dictionaries (~290 keys)
    providers/
      locale_provider.dart                  AppLocale enum + StateNotifier
      persistent_store.dart                 profile + ChatPreview models
    service/
      tanglex_service.dart                  THE service: 1 405 lines, public API
    stickers/
      sticker_store.dart                    sticker pack IO

android/                                    gradle, NDK 28.2.13676358,
                                            manifest, signing config
simplex-chat/                               git submodule, compiled .so files
local_plugins/image_gallery_saver/          patched plugin
pubspec.yaml                                deps locked, do not bump in this branch
HANDOFF.md                                  this file
README.md                                   user-facing project description
DISCLAIMER.md                               legal
LICENSE
test/widget_test.dart                       placeholder, no real tests yet
```

There is **no** `lib/src/ui/` directory. That is intentional.

---

## 3. What the bootstrap shows today

`lib/main.dart` boots the core and renders a single placeholder screen:

- A `MaterialApp` with `useMaterial3: true`, `ThemeMode.dark`, and a
  `ColorScheme.fromSeed(seedColor: #2AABEE, brightness: dark)` — pure
  Material 3 generated palette, no custom tokens.
- A `BootstrapScreen` that calls `TanglexService.initialize()` and
  surfaces the result as a status chip:
    - `Core initializing…` → `secondaryContainer`
    - `Core ready` → `primaryContainer`
    - `Core failed: <msg>` → `errorContainer` + Retry button
- `flutter_localizations` is wired in for `DateFormat` / Material
  defaults; locale comes from `localeNotifierProvider`.

**Everything in `BootstrapScreen` is throwaway.** Replace it. Do not
build the new UI on top of it.

---

## 4. The contract: `TanglexService` public API

`lib/src/service/tanglex_service.dart` — single class `TanglexService`
backed by FFI into the SimpleX chat library. Surface methods (signatures
verbatim, side effects in prose):

### Lifecycle
- `Future<void> initialize()` — must be awaited before any other call;
  spins up FFI, migrates DB if needed, starts event loop in a `ReceivePort`.
- `bool get isInitialized`
- `Future<void> dispose()` — cancels event subscription, closes streams.
- `Stream<Map<String, dynamic>> get eventStream` — every JSON-decoded
  event from the core (see § 6).
- `ValueNotifier<List<String>> logs` — rolling 200-line buffer (FFI +
  events). Subscribe for a Debug screen.

### Reading
- `Future<List<ChatPreview>> getChats({int limit = 50})`
- `Future<List<Map<String, dynamic>>> getChatMessages(String chatRef, {int limit, …})`
- `Future<List<ContactRequestPreview>> getContactRequests({int limit = 50})`
- `Future<bool?> getContactMessagingReady(String chatRef)` — true when
  it's safe to send to a contact (handshake complete). For groups: just
  treat as true.
- `Future<Map<String, dynamic>?> getUser()`
- `Future<List<Map<String, dynamic>>> getUsers()`

### Sending
- `Future<SendMessageResult> sendMessage(String chatRef, String text, {int? quotedItemId})`
- `Future<bool> sendImages(String chatRef, List<ImagePayload>, {int? quotedItemId})`
- `Future<SendResult> sendFile({required chatRef, required filePath, String text = '', int? quotedItemId})`
- `Future<SendResult> sendVideo({required chatRef, required filePath, required previewBytes, required durationSec, bool isCircle = false, int? quotedItemId})`
- `Future<SendResult> sendVoice({required chatRef, required filePath, required durationSec, int? quotedItemId})`
- `Future<SendResult> sendSticker({required chatRef, required filePath, required previewBytes, required previewMime, String? packId, String? stickerId})`
- `Future<bool> receiveFile(int fileId, {bool approvedRelays = true, bool? inline, bool encrypt = true, String? filePath})`

### Profiles / users
- `Future<Map<String, dynamic>?> createUserProfile({required displayName, String fullName = '', String? shortDescr})`
- `Future<bool> setActiveUser(int userId)`
- `Future<bool> deleteUser(int userId, {bool deleteSmpQueues = false})`

### Connections / contact requests
- `Future<String?> createConnectionLink()` — returns an SMP link to share.
- `Future<bool> connectViaLink(String link)`
- `Future<bool> acceptContactRequest(int contactRequestId)`
- `Future<bool> rejectContactRequest(int contactRequestId)`

### Raw / debug
- `Future<String?> sendCommand(String cmd)` — raw FFI command, returns
  decoded JSON string. Use only in a Debug screen.

### Result / error / exception types

| Class | Where | Fields |
|---|---|---|
| `SendMessageResult` | `service/tanglex_service.dart` | `bool ok`, `String? errorType`, `String? detail` |
| `SendResult` | `service/tanglex_service.dart` | `bool ok`, `String? error` |
| `ImagePayload` | `service/tanglex_service.dart` | `String filePath`, `Uint8List previewBytes`, `String previewMime` |
| `TanglexInitException` | `service/tanglex_service.dart` | wraps init failures |
| `MigrateInitKeyResult` | `ffi/tanglex_native.dart` | `String response`, `bool ok` |

`SendMessageResult.errorType` is one of:
`contactNotReady`, `contactNotActive`, `noResponse`, `parseError`, or
`null` (success). Show a localized error when not null.

---

## 5. Domain models (`lib/src/domain/chat_models.dart`)

| Class | Purpose |
|---|---|
| `UiMessage` | Parsed chat item. Fields: `key`, `text`, `fromMe`, `timeStr`, `status`, `isSystem`, `images`, `time`, `audio`, `fileName`, `fileSize`, `filePath`, `fileId`, `fileStatusType`, `transferProgress`, `transferTotal`, `quoted`, `itemId`. |
| `UiImage` | One media item. Fields: `bytes`, `filePath`, `isVideo`, `isCircle`, `isSticker`, `durationSec`, `transferProgress`. |
| `AudioItem` | Voice / audio attachment with `filePath`, `durationSec`. |
| `AudioNowPlaying` | Currently-playing audio (for a mini-player). |
| `QuotedMessage` | The "replied-to" preview embedded into `UiMessage`. |
| `PreviewPayload` | `bytes` + `mime` for image previews. |
| `CircleVideoResult` | Output of the circle recorder (path + duration + preview). |
| **`SendResult`** | ⚠ **Duplicate of the one in `tanglex_service.dart`.** Legacy technical debt — remove on sight. Use the service-side one. |

`persistent_store.dart` also defines:

| Class | Purpose |
|---|---|
| `ProfileData` | Cached user profile (displayName, fullName, shortDescr, userId, agentUserId, userContactId, localDisplayName). |
| `ChatPreview` | One row in the chats list. Important booleans: `isMessagingReady`, `needsAcceptFromDirectRow`, `isConnectingWithoutRequest`, plus `embeddedContactRequestId` for contacts that carry a pending request inline. |
| `ContactRequestPreview` | A standalone incoming contact request. |
| `ThemeConfigData` / `AppLocaleData` | Persisted preferences (theme is unused — app is dark-only). |

There is also `ContactInfo` (a partial helper struct).

---

## 6. Events from the core (`eventStream`)

The service forwards every JSON-decoded message from the FFI loop. `event['result']['type']` is the discriminator. Types worth reacting to for a chat-list UI:

| Type | Meaning | UI should… |
|---|---|---|
| `receivedContactRequest` | Someone wants to connect. | Append to requests section. |
| `acceptingContactRequest` | We just accepted; core is handshaking. | Refresh chats. |
| `contactRequestRejected` | We or peer rejected. | Remove from requests list. |
| `chatStarted` | Core finished `/_start`. | Refresh chats. |
| `activeUser` | Active user changed (profile switch). | Bump fetch nonce, reload. |
| `contactConnection` | A "pcc"-style pending connection appeared. | Refresh chats. |
| `contact` | Contact metadata changed. | Refresh chats. |
| `contactSndReady` | Handshake done, you can now send. | Refresh contact's `messagingReady`. |
| `contactConnecting` | Connection initialized. | Refresh chats. |
| `chatItem` / `chatItemNew` / `newChatItems` | New message arrived. | Append to the open chat; bump unread for closed chats. |
| `chatItemUpdated` | Message status changed (delivered, read, transfer progress). | Patch that item in place. |
| `chatItemsDeleted` / `groupChatItemsDeleted` | Items were removed. | Remove from chat. |
| `chatItemsStatusesUpdated` | Bulk status update. | Patch many items. |

**Recommended pattern**: a Riverpod `StreamProvider` (or `StateNotifier`)
that owns the chats list, debounces refreshes by ~250 ms, and rebuilds
on the events above.

---

## 7. The parser (`lib/src/data/chat_message_parser.dart`)

Entry point:

```dart
UiMessage? parseChatItem(Map<String, dynamic> msg, {String? filesBaseDir})
```

- Returns `null` for items that should not appear in the UI.
- For images/videos, resolves relative `filePath`s against `filesBaseDir`
  if you pass it.
- Decodes `image` base64 previews and verifies magic bytes (skips garbage).
- Sets `isSystem: true` for unsupported content types so the UI can render
  a system bubble.

Supported `msgType` values: `text`, `image`, `video`, `voice`, `file`,
`link`, `report`, `chat`, `sticker`, `unknown`.

### Inter-TangleX recognition rules

TangleX adds two non-standard concepts on top of SimpleX: stickers and
"video circles" (like Telegram's round videos). They're encoded as
ordinary image/video/file messages plus filename conventions and a text
marker. **The new UI must respect these or peers will see weird stuff:**

- **Stickers**:
  - filename starts with `st__`, OR
  - `msgType == 'sticker'`, OR
  - text starts with `/sticker`, OR
  - image/video with `.webp` / `.webm` and empty text.
  - `/sticker` is a sentinel — the parser already strips it from
    `display`. **The UI must never render `/sticker` as text** (it
    would leak to non-TangleX peers, but in our UI we hide it).
- **Circles**: filename starts with `circle_` (and `isVideo: true`).

Other parser utilities exported from the same file (used to be in a
"utils" namespace, now top-level functions):

- `makePreview(Uint8List bytes) → PreviewPayload` — resize to ≤ 64 KB.
- `prepareCirclePreview(String path) → Future<PreviewPayload>`
- `prepareStickerPreview(String path) → Future<PreviewPayload>`
- `compressPreview(Uint8List bytes, {int maxBytes = 64 * 1024})`
- `tinyPreview(Uint8List bytes)` — for chat-list thumbnails.
- `chatRefFromInfo(Map info) → String?` — extract `@id`/`#id`.
- `slugify(String s)`
- `initials(String name)`
- `formatDuration(int seconds)`

---

## 8. Critical FFI / DB facts you must respect

1. **DB passphrase** is a random 256-bit string stored in
   `SharedPreferences` under key `tanglex_db_passphrase_v1`. **Never**
   regenerate it; the DB won't open. `TanglexService` generates it
   lazily on first init.
2. **Legacy fallback**: if `chat_ctrl_init` returns
   `errorNotADatabase`, the service automatically retries with
   `Tanglex_Strong_Password_12345!!!` (the old hardcoded passphrase used
   in versions before ~April 2026). This is the migration path for
   existing users. **Do not delete this branch.**
3. **Boot order** (in `initialize()`): create chat_ctrl → migrate init
   key → set app file paths → ensure active user → `/_start` →
   `ReceivePort` event loop. If any of these fails the service throws
   `TanglexInitException` and `isInitialized` stays false.
4. **`messagingReady`**: contact chats reject sends until the handshake
   completes. Compose box should be locked (and show a hint) until
   either `chat.isMessagingReady == true` or you observe a
   `contactSndReady` event.
5. **Auto-receive images** ≤ 522 240 bytes by convention (the old UI
   did this with a 300 ms throttle). The new UI may keep or drop this
   feature; nothing in the service does it for you.
6. **Pin sentinel**: messages starting with `/pin ` or `/p ` were
   treated as "pin the message" by the old UI: the text was sent
   unchanged (peers see the literal `/pin foo`), and the local
   `PinStore` was updated to remember the pin. The prefix was then
   stripped before display. If you reuse this, be consistent on both
   send and receive paths.
7. **Webm stickers**: render the first frame as a still image. The old
   UI tried to play them, which stole Android audio focus and
   silenced the user's music. Do **not** attempt to play `.webm` files
   that look like stickers; treat as images.
8. **Video circles**: when playing, call
   `controller.setVolume(0)` by default. They're meant to be ambient;
   stealing audio focus is rude.

---

## 9. Design language

The user prefers **Material Design 3 (Material You)** as the foundation.

### Hard rules

- `useMaterial3: true` everywhere.
- Colors come from `ColorScheme.fromSeed(...)` (or generated via
  Material Theme Builder). **No hardcoded `Color(0xFF...)` in widgets.**
  If you find a literal hex, file it as a bug.
- Typography uses `Theme.of(context).textTheme` roles
  (`displayLarge` … `labelSmall`). **No inline `TextStyle(fontSize: 13.5)`.**
- Shapes use Material 3 shape tokens
  (`Theme.of(context).extension<...>()` or default Material shapes).
  Buttons: full radius. Cards: medium (12dp). Dialogs / bottom sheets:
  extra-large (28dp top corners).
- Elevation is **tonal** (handled by Material 3 automatically). Do not
  add custom `boxShadow` unless you have a documented reason.
- Use semantic color roles: `primaryContainer / onPrimaryContainer`,
  `secondaryContainer / onSecondaryContainer`, `errorContainer / onErrorContainer`,
  `surface / onSurface`, `surfaceVariant / onSurfaceVariant`,
  `outline` (text-field borders), `outlineVariant` (dividers).
  Never pair `primary` with `onSurface` etc.
- Dark only for now. Light may come later — design for both by relying
  on the `ColorScheme`.
- Rounded icons (`Icons.*_rounded`) preferred; outlined variants OK
  for inactive states.
- All user-facing strings go through
  `AppLocalizations.of(context).translate('key')`. Add new keys to
  `lib/src/localization/app_localizations.dart` in **both** `_ru` and
  `_en` maps.

### The "user-supplied DESIGN.md"

The user said they will hand you a **separate `DESIGN.md` file** with
their specific palette / typography / component decisions. **Wait for
it** before doing significant visual work. The seed color in
`main.dart` (#2AABEE) is a placeholder.

If/when `DESIGN.md` appears in repo root, treat its contents as the
authority and update `main.dart`'s `seedColor` / `ThemeData` to match.

### Anti-patterns (don't do these)

- Mixing custom tokens with Material 3 tokens. Pick one (Material 3).
- Shipping placeholder buttons that show "coming soon" — **features that
  don't exist in the service do not exist in the UI**.
- Building a new "design system" file with its own palette duplicating
  Material's. There is one source of truth: the `ColorScheme`.
- Hardcoding `EdgeInsets.all(13)` etc. Stick to the 4-point grid
  (`4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48`).

---

## 10. Recommended new-UI architecture

You have a clean slate. Aim for clear layers:

```
lib/src/ui/
  app/
    app.dart                    MaterialApp + theme + router host
    theme.dart                  ColorScheme.fromSeed + ThemeData (only one)
  features/
    chats/
      chats_screen.dart         list of chats
      chats_controller.dart     state notifier; owns ChatPreview[]
    chat/
      chat_screen.dart          one conversation
      chat_controller.dart      messages + send + reply + pin state
      widgets/
        message_bubble.dart
        compose_bar.dart
        reply_preview.dart
        pinned_bar.dart
        attach_sheet.dart
        message_actions_sheet.dart
        media_grid.dart
        video_circle.dart
        sticker_view.dart
        audio_bubble.dart
        audio_mini_player.dart
    profile/
      profile_screen.dart
      profile_controller.dart
    settings/
      settings_screen.dart
    debug/
      debug_screen.dart
  shared/
    avatar.dart                 ONE avatar widget for the whole app
    empty_state.dart
    skeleton.dart
```

**Hard limits:**

- Each file ≤ 300 lines. If you cross 300, split.
- ChatScreen-the-widget itself ≤ 200 lines. The rest goes into the
  controller and into widgets/.
- One widget per file (except trivially-coupled private helpers).
- Controllers are Riverpod `StateNotifier`s. Views are
  `ConsumerWidget`s that read state and dispatch intents.
- No global mutable state outside the documented singletons
  (`AudioPlayerHolder.player`, `PinStore.instance`,
  `StickerStore.instance`).
- All async ops in a `State` use `mounted` guards before `setState`.
  All controllers/streams disposed in `dispose`.

---

## 11. Localization

`lib/src/localization/app_localizations.dart` ships ~290 keys in `_ru`
and `_en`. Many are scoped to the old UI's screens (Profile, Chats,
Chat, Debug, …) — you can reuse most of them as-is. Examples:

- `no_chats_yet`, `no_messages_yet`
- `message_pin`, `message_unpin`, `message_copy`, `message_reply`,
  `message_copied`
- `today`, `yesterday`, `you_label`
- `chat_type_group`, `chat_type_contact`
- `send_error_contact_not_ready`, `send_error_contact_not_active`,
  `send_error_no_response`, `send_error_parse`
- `pinned_label`, `file_open_failed`, `file_open_no_app`
- `viewer_save_to_gallery`, `viewer_share`, `viewer_copy_path`
- `attach_tooltip`, `more_tooltip`, `media_placeholder`

Open the file and grep before inventing a new key. Add to **both** ru
and en maps if you must.

**Known small TODO**: `persistent_store.dart` returns emoji glyphs
(📷 🎬 🎤 🖼️ 📎 🔗 ⚠️ 💬) for "last message preview" because the parser
has no `BuildContext` to translate. If you set up a translation
function-style approach (return a typed enum, translate in the UI
layer), fix this. Otherwise leave it; emoji are language-agnostic.

---

## 12. Singletons and other globals

- **`AudioPlayerHolder.player`** (`lib/src/data/audio_player_holder.dart`)
  — single `just_audio.AudioPlayer` for the entire app. Use it for
  every voice/audio playback. Never create a second `AudioPlayer`.
- **`PinStore.instance`** (`lib/src/data/pin_store.dart`) — local-only
  pin store. Call `await PinStore.instance.load()` once at startup.
  Writes are serialized internally.
- **`StickerStore.instance`** (`lib/src/stickers/sticker_store.dart`) —
  sticker pack registry. Call `await StickerStore.instance.ensureLoaded()`
  once at startup.
- **`tanglexServiceProvider`** (`lib/main.dart`) — Riverpod `Provider`
  that holds the singleton `TanglexService`. Disposed automatically
  with the `ProviderScope`.
- **`localeNotifierProvider`** (`lib/src/providers/locale_provider.dart`)
  — Riverpod `StateNotifierProvider` for the selected `AppLocale`.
- **`persistedProfileProvider`** (`lib/src/providers/persistent_store.dart`)
  — Riverpod `FutureProvider<ProfileData?>` that loads the cached
  profile.

---

## 13. Build / run / push workflow

- Flutter: `^3.11.1` (see `pubspec.yaml` `environment.sdk`).
- Android: `compileSdk = 36`, `targetSdk = 36`, `minSdk = 24`,
  `ndkVersion = 28.2.13676358`. Don't change without a real reason.
- Build: `flutter build apk --debug` (release needs `android/key.properties`).
- Tests: `flutter test`.
- Analyze: `flutter analyze` should be 0 errors / 0 warnings before
  every commit. Info-level lints are tolerated.

### Git push

The repo has a `.git/hooks/pre-push` that requires `git-lfs`, which is
not installed on the build machine. To push without touching that:

```bash
mv .git/hooks/pre-push .git/hooks/pre-push.disabled
git push origin <branch>
mv .git/hooks/pre-push.disabled .git/hooks/pre-push
```

Remote: `git@github.com:IILLUMINATION/simplex_chat_app.git`

---

## 14. Known issues / tech debt to fix incidentally

- **`SendResult` duplication**: defined in both
  `lib/src/service/tanglex_service.dart` (canonical) and
  `lib/src/domain/chat_models.dart` (orphan, no callers). Remove the
  orphan when you next touch that file.
- **KGP warning** from `camera_android_camerax` during build is
  non-blocking and out of our control.
- **Persistent-store emoji placeholders** for last-message previews
  (see § 11).
- **`stickers/sticker_store.dart`** imports `archive` directly but the
  dep is only listed under `dependency_overrides`. `flutter analyze`
  warns once. Either add `archive` to real deps or refactor away.
- **No proper test suite**. `test/widget_test.dart` is a placeholder.

---

## 15. What is NOT implemented in the service (don't add UI for it)

- Edit message
- Delete message (locally or remotely)
- Forward message
- Reactions
- Full-text search
- Online status / typing indicators
- Group creation / member management

If the user asks for one of these, the right answer is "we'd have to
build it in the service first" — not "I'll fake it in the UI".

---

## 16. Checklist for your first session

1. Read this file end-to-end.
2. Skim `lib/src/service/tanglex_service.dart` — at least the public
   method signatures and the `_handleEvent` flow.
3. Skim `lib/src/data/chat_message_parser.dart` — at least `parseChatItem`
   and the sticker/circle recognition block.
4. Skim `lib/src/domain/chat_models.dart` — all of it.
5. Ask the user for their `DESIGN.md`. Don't begin visual work without it.
6. Together with the user, pick the MVP scope. A reasonable first pass:
   - Chats list (read-only).
   - Open one chat → see messages (text only).
   - Send a text message.
   - Profile screen (read-only).
   Bigger features (media, voice, stickers, pins) come after the MVP is
   visually stable.
7. Build inside `lib/src/ui/features/<feature>/` per the layout in § 10.
   No single mega-screen. No design tokens file duplicating Material 3.
8. Every commit: `flutter analyze` clean + `flutter build apk --debug`
   succeeds. Push only after both pass.

Welcome aboard. Keep the discipline; the user is paying close attention
to architecture this time around.
