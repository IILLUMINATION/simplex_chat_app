# TangleX Design System

Source of truth for the visual language and UI implementation rules of the
TangleX app.

If a piece of UI code disagrees with this document, the code is wrong.

---

## 1. Philosophy

- **Dark only.** TangleX ships with a single, carefully-tuned dark theme.
  No runtime theme switcher, no Material dynamic color. Light mode may be
  added later as a separate parallel tokens file; until then `ThemeMode.dark`
  is hardcoded in `lib/main.dart`.
- **Telegram-inspired, not a Telegram clone.** We borrow the UX vocabulary
  (right/left bubbles, swipe-to-reply, pinned bar, attach sheet) and the
  accent blue, but the typography, layout grid and tokens are our own.
- **Tokens are the API.** All colors, spacing, radii, durations and font
  styles come from `lib/src/ui/design/`. Direct `Color(0xFF…)`,
  `EdgeInsets.all(7)`, `BorderRadius.circular(13)` and inline `TextStyle`
  literals in feature code are bugs.
- **No placeholders.** If a feature is not implemented in the service layer
  it does not appear in the UI. We do not ship buttons that show
  "coming soon" snackbars.

---

## 2. Files

```
lib/src/ui/design/
  tokens.dart         AppColors, AppSpacing, AppRadius, AppDuration,
                      AppIconSize, AppAvatarSize
  typography.dart     AppText + TextTheme builder
  theme.dart          buildAppTheme(): ThemeData (the only one)
  components/         Reusable visual building blocks
    app_avatar.dart
    app_button.dart
    app_sheet.dart
    app_dialog.dart
    app_snackbar.dart
    app_divider.dart
    app_empty_state.dart
    app_skeleton.dart
```

---

## 3. Color tokens

All colors are defined in `AppColors`. Names are semantic, not literal.

### Surfaces (the "surface ladder")

| Token       | Hex        | Use                                                |
|-------------|------------|----------------------------------------------------|
| `bg`        | `#0E0E10`  | Scaffold background, chat list, message list       |
| `surface1`  | `#15161A`  | AppBar, compose bar, bottom sheets                 |
| `surface2`  | `#1C1D22`  | Cards, dialogs, incoming bubbles                   |
| `surface3`  | `#23252B`  | Hover/pressed, emphasised tiles, code background   |

### Lines

| Token     | Hex        | Use                                |
|-----------|------------|------------------------------------|
| `divider` | `#2A2C32`  | Hair-line separators               |
| `border`  | `#2A2C32`  | Borders on cards, input fields     |

### Text

| Token            | Hex        | Use                              |
|------------------|------------|----------------------------------|
| `textPrimary`    | `#ECECEC`  | Body, titles                     |
| `textSecondary`  | `#9098A3`  | Subtitles, hints, timestamps     |
| `textDisabled`   | `#5E646D`  | Disabled labels                  |
| `textOnAccent`   | `#FFFFFF`  | Text on `accent` background      |

### Accents

| Token           | Hex        | Use                                          |
|-----------------|------------|----------------------------------------------|
| `accent`        | `#2AABEE`  | Primary actions, links, outgoing bubble fill |
| `accentPressed` | `#1E96D4`  | Pressed state of accent surfaces             |
| `accentMuted`   | `#1A4C6B`  | Disabled/secondary accent, slider overlay    |

### Bubbles

| Token                       | Hex        | Use                              |
|-----------------------------|------------|----------------------------------|
| `outgoingBubble`            | `#2AABEE`  | Background of outgoing text/file |
| `outgoingBubbleText`        | `#FFFFFF`  | Foreground in outgoing bubble    |
| `outgoingBubbleSecondary`   | `#CDE8FA`  | Timestamps/icons in outgoing     |
| `incomingBubble`            | `#1C1D22`  | Background of incoming           |
| `incomingBubbleText`        | `#ECECEC`  | Foreground in incoming           |
| `incomingBubbleSecondary`   | `#9098A3`  | Timestamps/icons in incoming     |

### Replies / quoted

| Token          | Hex        | Use                                          |
|----------------|------------|----------------------------------------------|
| `quotedAccent` | `#2AABEE`  | 2 px vertical bar marking the quoted block   |
| `quotedBg`     | `#23252B`  | Container background of the quoted block     |

### Status

| Token     | Hex        | Use                                |
|-----------|------------|------------------------------------|
| `error`   | `#E5484D`  | Errors, destructive actions        |
| `success` | `#46A758`  | Success, online dot                |
| `warning` | `#F5A623`  | Warnings                           |
| `online`  | `#46A758`  | Presence indicator                 |

### Avatar palette

8 deterministic colors. `AppColors.avatarColorFor(name)` returns one
based on a stable hash of the name. Order: blue, green, amber, red,
violet, teal, pink, orange.

### Code blocks

| Token            | Hex        |
|------------------|------------|
| `codeBg`         | `#181A1F`  |
| `codeBorder`     | `#2A2C32`  |
| `codeInlineBg`   | `#23252B`  |

---

## 4. Spacing scale (`AppSpacing`)

A strict 4-point grid. Only these values are allowed.

```
s0 = 0   s1 = 4   s2 = 8   s3 = 12   s4 = 16
s5 = 20  s6 = 24  s8 = 32  s10 = 40  s12 = 48
```

If you find yourself wanting `EdgeInsets.all(14)` — pick `s3` or `s4`.

---

## 5. Radius scale (`AppRadius`)

| Token   | Px  | Use                                              |
|---------|-----|--------------------------------------------------|
| `rs`    | 8   | Inputs, badges, chips, icon containers           |
| `rm`    | 12  | Cards, dialogs, media tiles                      |
| `rl`    | 16  | Message bubbles, large cards                     |
| `rxl`   | 24  | Top corners of bottom sheets                     |
| `rfull` | 999 | Avatars, FAB, round buttons                      |

Bubble corners are asymmetric (see `bubbleIncoming` / `bubbleOutgoing`):
the corner facing the conversation partner uses `rs`, others use `rl`.
This produces the "tail" effect without drawing tails.

---

## 6. Typography (`AppText`)

Platform default font — Roboto on Android, SF on iOS. No bundled assets.

| Token          | Size / weight | Use                                       |
|----------------|---------------|-------------------------------------------|
| `display`      | 24 / 700      | Large headings (Profile name)             |
| `title`        | 18 / 600      | AppBar title, screen titles               |
| `titleSmall`   | 16 / 600      | List tile titles, dialog titles           |
| `body`         | 16 / 400      | Bubble text, primary content              |
| `bodyEmph`     | 16 / 500      | Emphasised body                           |
| `caption`      | 14 / 400      | Subtitles, hints, list tile previews      |
| `captionEmph`  | 14 / 500      | Button labels, emphasised secondary text  |
| `meta`         | 12 / 400      | Timestamps, file sizes, date chips        |
| `metaEmph`     | 12 / 500      | Emphasised meta                           |
| `code`         | 14 / 400 mono | Code blocks, link previews                |

Line-height is baked in (`1.25`–`1.4` depending on size). Don't override.

---

## 7. Elevation, blur, scrim

- **AppBar.** Background `surface1`, no shadow, no scrolled elevation.
  Where a blurred translucent header is desired (chat screen),
  wrap in `BackdropFilter(ImageFilter.blur(sigmaX: 18, sigmaY: 18))` and
  paint `surface1.withValues(alpha: 0.78)`.
- **Bottom sheets.** `surface1`, top corners `rxl`, drag-handle
  36×3 px coloured `surface3`, centered, 6 px below the top edge.
- **Dialogs.** `surface2`, radius `rm`, no surface tint.
- **Scrim.** `0x99000000` (`AppColors.scrim`).

---

## 8. Bubble anatomy

```
[avatar?]  ┌────────────────────────────┐
           │ optional reply preview     │   <- quotedAccent bar 2px
           │ body text…………………………………… │
           │                      12:34│   <- meta in *Secondary color
           └────────────────────────────┘
```

- **Incoming**: left-aligned, `incomingBubble`, `bubbleIncoming` radius.
  Group avatars on left, contact-chat avatars hidden.
- **Outgoing**: right-aligned, `outgoingBubble`, `bubbleOutgoing` radius.
  No avatar.
- **Time** is always inside the bubble, bottom-right of the text block,
  with a leading `s2` space.
- **Reply preview** (when this message replies to another) appears inside
  the bubble, above the body: a 2 px `quotedAccent` bar on the left,
  sender name in `captionEmph`, single-line message in `caption`.

### Media bubbles

Stickers, photos, videos, voice circles **do not have a bubble background**.
They are simply aligned left or right inside the message row. A caption,
if present, sits in a small bubble *under* the media, with the appropriate
incoming/outgoing fill.

Audio and file attachments **do** use the bubble fill (outgoing = accent
blue with white play / waveform / icon; incoming = `incomingBubble`).

---

## 9. Avatars

`AppAvatar` is the only widget that produces avatars.

| Variant   | Size   | Use                            |
|-----------|--------|--------------------------------|
| `tiny`    | 24 px  | Reply preview, inline mentions |
| `small`   | 28 px  | Inline lists                   |
| `medium`  | 36 px  | AppBar header                  |
| `large`   | 50 px  | Chat list tile                 |
| `xlarge`  | 96 px  | Profile screen                 |

Rules:

- If image bytes are provided → draw the image.
- Else → solid circle of `AppColors.avatarColorFor(name)` with up to
  two-letter initials in `bodyEmph` colored `textOnAccent`.
- Group chats → `people_outline_rounded` icon on top of the same colored
  circle.
- Online dot: 12 px, `online` color, 2 px `bg` border, bottom-right corner.

---

## 10. Iconography

- Prefer `Icons.*_rounded`. Fall back to `_outlined` if rounded is missing.
  Never use filled, except `send_rounded` and `mic_rounded`.
- Sizes: `AppIconSize.small` (20), `regular` (24), `large` (28).
- All icons take `AppColors.textPrimary` unless they are inside an accent
  surface (then `textOnAccent`) or carry a status meaning.

---

## 11. Motion

- Page transitions: `CupertinoPageRoute` (slide). No custom
  `PageRouteBuilder` except where a fade is specifically required.
- Color transitions: `AppDuration.fast` (150 ms), curve `Curves.easeOut`.
- Sheet open / dismiss: framework default.
- Bubble appearance: no animation.

---

## 12. Code patterns

```dart
// BAD
Container(
  color: const Color(0xFF15161A),
  padding: const EdgeInsets.all(16),
  child: Text('Hi', style: TextStyle(fontSize: 14, color: Color(0xFFE8E8E8))),
)

// GOOD
Container(
  color: AppColors.surface1,
  padding: const EdgeInsets.all(AppSpacing.s4),
  child: const Text('Hi', style: AppText.caption),
)
```

```dart
// BAD
final color = Theme.of(context).colorScheme.primary == Brightness.dark
  ? const Color(0xFF111111)
  : Colors.white;

// GOOD
const color = AppColors.surface1; // dark-only app
```

```dart
// BAD
borderRadius: BorderRadius.circular(13)

// GOOD
borderRadius: AppRadius.brm
```

---

## 13. Review checklist

For every PR touching UI:

- [ ] No `Color(0xFF…)` outside `tokens.dart`
- [ ] No raw paddings / radii — only `AppSpacing.*` / `AppRadius.*`
- [ ] No inline `TextStyle(...)` — use `AppText.*` or `textTheme`
- [ ] All user-facing strings go through `AppLocalizations`
- [ ] No placeholder buttons for features that don't work
- [ ] All async ops use `mounted` guards
- [ ] All controllers/streams disposed in `dispose`
- [ ] `flutter analyze` clean (0 errors, 0 warnings)
- [ ] `flutter build apk --debug` succeeds
