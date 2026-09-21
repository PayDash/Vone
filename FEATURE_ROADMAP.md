# Vone Feature Roadmap — parity with paid notch apps

Status: **M1 built, unreleased · M2/M3 scoped** · Owner: Vone · Basis: review of Droppy (getdroppy.app) docs + public feature set, cross-checked against Vone `main`.

---

## 1. Purpose

Make Vone the best free notch app by closing the feature gap against paid competitors,
starting with **Droppy** (getdroppy.app, one-time paid, closed source). "Parity" means
**equivalent user-facing capability implemented independently** — not copied code.

The scope is what §4 and §6 list. Anything else — including anything that was once
considered and set aside — is out of scope for this roadmap.

## 2. Ground rules (read before writing any code)

1. **Clean-room.** Droppy is closed source. We do not copy, decompile, or port its code,
   and we do not copy its documentation, marketing copy, icons, illustrations or other
   creative assets. Features, workflows and interaction *ideas* are not copyrightable;
   their specific expression is. Write our own implementation and our own strings.
2. **Licence discipline.** Vone is GPLv3. Any dependency we add must be
   GPL-compatible. Prefer system frameworks (Vision, Speech, AVFoundation, Accessibility,
   ScreenCaptureKit) and already-vendored packages.
3. **No new required server.** Droppy Cloud is a hosted service. We ship an
   *equivalent capability* using the user's own storage/transport (see §5), or make the
   hosted part strictly optional and bring-your-own.
4. **Reuse before adding.** Vone already has a large surface (§3). Extend existing
   managers/views instead of building parallel ones.
5. **Settings + localisation + license header** are part of "done" for every feature:
   new keys go in both `Localizable.xcstrings` files, new files carry the GPL header, and
   user-facing toggles live in Settings. Only `DynamicIsland/Localizable.xcstrings` is a
   build input (the `DynamicIsland` folder is a synchronized group); the copy at the
   repository root belongs to no target and is kept in step by hand. A string handed to
   a parameter typed `String` is never extracted, so anything displayed from a `String`
   has to be wrapped in `String(localized:)` — `Text("…")` alone does not cover a
   `String`-returning property. See §10.3 for the refresh command.

## 3. What Vone already has (do not rebuild these)

Verified present in `DynamicIsland/`:

| Area | Evidence |
|---|---|
| Media: Spotify, Apple Music, YouTube Music, Cider, Tidal, Amazon, generic Now Playing | `MediaControllers/`, `managers/MusicManager.swift` |
| Lyrics (LRC, NetEase, pinned, unsynced) | `LRCParser.swift`, `NetEaseLyrics.swift`, `LyricsMetadata.swift` |
| Per-app volume + audio device routing + AirPlay | `PerAppVolumeManager.swift`, `AudioRouteManager.swift`, `AppleMusicAirPlayManager.swift` |
| Shelf (file tray, tray pages, QuickLook, AirDrop, LocalSend, drag-out) | `components/Shelf/**` |
| Clipboard history (list, persistence, panel) | `ClipboardManager.swift`, `ClipboardPanelManager.swift`, `components/Clipboard/` |
| Live activities: media, Focus, recording, privacy indicators, downloads, battery | `components/Live activities/`, managers |
| Lock screen: media, timers, reminders, weather, widgets | `managers/LockScreen*`, `components/LockScreen/` |
| System stats (CPU/GPU/mem/network/disk/SMC/IOReport) | `StatsManager.swift`, `utils/SMC.swift`, `utils/IOReportBridging.swift` |
| Timers + Apple Clock bridge | `TimerManager.swift`, `SystemTimerBridge.swift` |
| Calendar + reminders + live activity | `CalendarManager.swift`, `ReminderLiveActivityManager.swift` |
| Weather (Open-Meteo) | `LockScreenWeatherManager.swift`, `LockScreenWeatherPanelManager.swift` |
| System HUDs (volume/brightness/keyboard backlight, OSD) | `SystemHUDManager.swift`, `SystemOSDManager.swift`, `SystemKeyboardBacklightController.swift` |
| Caffeinate / keep-awake | `CaffeinateManager.swift` |
| Camera preview, microphone + privacy monitors | `WebcamManager.swift`, `MicrophoneMonitor.swift`, `PrivacyIndicatorManager.swift` |
| Screen capture / snipping tool | `ScreenRecordingManager.swift`, `components/ScreenAssistant/` |
| On-device Apple Notes sync | `AppleNotesSyncManager.swift` |
| Terminal in notch | `TerminalManager.swift` (SwiftTerm tab) |
| LLM usage (Claude, Codex, Antigravity, new-api) | `managers/LLMUsage/**` |
| Extension ecosystem + RPC + XPC host | `services/Extensions/**`, `AtollExtensionKit` |
| Colour picker, network monitor, battery, Bluetooth/AirPods battery, Do Not Disturb, Siri monitor, Lunar brightness, BetterDisplay, display controls | various managers |
| Idle animations, Lottie, parallax, gestures, KeyboardShortcuts | `components/`, `animations/` |
| Image processing: background removal, conversion, PDF creation | `components/Shelf/Services/ImageProcessingService.swift` (`VNGenerateForegroundInstanceMaskRequest` for the cut-out) |

## 4. Gap analysis — Droppy capabilities Vone lacks

Priority: **P0** flagship/user-visible differentiators · **P1** high value · **P2** nice-to-have.
Effort: S ≤ 1 day · M ≤ 3 days · L ≤ 1 week · XL > 1 week.

### 4.1 Core surfaces

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 1 | **Basket** — floating tray at the cursor | Shake while dragging (or instant/hotkey) summons a floating tray; single & multi-basket; basket switcher; carries Quick Actions | ✅ built (`BasketManager`, `BasketView`, `BasketSettingsSection`) | **P0** | M |
| 2 | **Quick Action tiles** | Drop a file on a tile → AirDrop / share link / Mail / convert, without dropping elsewhere first | ✅ built, Basket only (`QuickActionRegistry`, `QuickActionsStrip`) | **P0** | S–M |
| 3 | **Ring** — radial action picker | Hold a shortcut, choose from a ring of actions around the pointer | ✅ built (`RingActionManager`) | **P0** | S |
| 4 | **Shelf widgets** | Any extension can place a widget on the shelf, alone or beside another | 🟡 Shelf exists, widget slots unverified | P1 | M |
| 5 | **Non-notch mode** | Floating shelf + menu-bar-only on notch-less Macs and external displays | 🟡 unverified (`MenuBarLayout`, `NotchSpaceManager`) | P1 | M |

### 4.2 File & capture tools

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 6 | **OCR** | Extract text from screen/images/PDF; OCR text is indexed into clipboard search | ✅ built (`OCRService`); clipboard indexing still missing | **P0** | S–M |
| 7 | **Converters** | Local file conversion (images/docs); PDF compression; video "target size" compression | 🟡 `ImageProcessingService` does the image half inside the Shelf; documents, PDF compression and video sizing are missing | P1 | M–L |

Background removal left this table: it is already built (§3), using Vision's foreground
mask on device. It is covered by the Shelf's image processing, not by this roadmap.

### 4.3 Windows, input & menus

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 8 | **Window Snap** | Pointer + keyboard window management (snap/half/quarter) | ✅ built (`WindowSnapManager`); hotkeys only | **P0** | M |
| 9 | **Emoji Picker** | Global shortcut opens an emoji panel that inserts into the front app | ✅ built (`EmojiPickerManager`) | **P0** | S |
| 10 | **Thaw** — menu bar item manager | Hide/arrange menu bar items | 🟡 `MenuBarLayout` only | P1 | M |

### 4.4 Communication & presence

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 11 | **Quick notes → Apple Notes** | Note editor in notch that syncs to Apple Notes | ✅ mostly (`AppleNotesSyncManager`) | — | S (polish) |

### 4.5 Agents, sharing & ecosystem

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 12 | **Agents** | Live Claude / Codex / Cursor / Antigravity / OpenCode progress | 🟡 `LLMUsage` covers Claude/Codex/Antigravity; **Cursor + OpenCode missing** | P1 | M |
| 13 | **Droplet surfaces** | Each extension can expose shelf widget / live activity / lock screen / shortcut / menu-bar item | 🟡 extension kit exists; surface coverage unverified | P1 | M |
| 14 | **LocalSend** | Device-to-device transfer, no cloud | ✅ present (`LocalSendService`) | — | — |
| 15 | **Play Next queue / output picker** | Up-next queue and audio output picker in the player | 🟡 AirPlay/route managers exist, queue unverified | P2 | S |
| 16 | **Motion art in shelf** | Animated art in the shelf | 🟡 `AnimatedArtworkManager` + Lottie present | P2 | S |

## 5. Architecture & integration plan

All new work follows existing Vone patterns:

- **Managers** live in `DynamicIsland/managers/` as `ObservableObject` singletons
  (`static let shared`), owned/wired in `DynamicIslandApp.swift` or
  `DynamicIslandViewCoordinator.swift`.
- **Floating surfaces** use the existing borderless-panel pattern
  (`FlyoutWindowPresenter`, `ScreenAssistantPanelManager`, `ColorPickerManager`):
  `NSPanel`, `.nonactivatingPanel`, `.canJoinAllSpaces`, level above `.mainMenu`.
- **Shake-to-summon** is a global `NSEvent` mouse monitor (`BasketManager`), so it works
  over any app; the reversal counting lives in `BasketShakeTracker` so it can be tested
  without a mouse.
- **Clipboard OCR indexing** extends `ClipboardManager` entries with an `ocrText` field
  and a search index, instead of a new store.
- **Window Snap** uses the **Accessibility API** (`AXUIElement`); no new entitlement
  beyond the Accessibility permission already asked for.
- **Emoji Picker / Ring** are self-contained panels; insertion via `CGEvent` unicode
  injection into the focused app.
- **Extension surfaces**: extend `AtollExtensionKit`-facing descriptors one surface at a
  time (shelf widget → live activity → lock screen → menu bar).

## 6. Milestones

**M1 — Flagship surfaces (P0) — built**
Basket · Quick Action tiles · Ring · Emoji Picker · Window Snap · OCR.
Notifications in the notch is not being built; §10.1 records why.

**M2 — File tools (P1)**
Agent coverage (Cursor, OpenCode) · Converters (§4.2 — the image half already exists in
`ImageProcessingService`).

**M3 — Depth (P1/P2)**
Non-notch mode · Shelf widgets · Droplet surfaces (§4.5, kept beside shelf widgets — it is
the same surface work) · Thaw · Play Next queue + output picker · Motion art.

**M1 remainder (carry-over)**
The gaps §10.2 records for what has shipped, listed here so they are not lost when M2
starts:

- Quick Action tiles on the **Shelf**, not just the Basket. The registry and strip are
  written for both already.
- **OCR text indexed into clipboard search** (`ClipboardManager` integration).
- The Ring's **hold-and-release** interaction, if the Ring is kept as it is.

## 7. Detailed specs — M1

> **Implementation status (M1):** built and compiling — Basket, Quick Action tiles,
> Ring, Emoji Picker, OCR, Window Snap, a Tools settings page for the four
> pointer tools, and the Basket Settings UI. Not built: Notifications in the notch
> (§10.1). Remaining gaps for the shipped features are listed in §10.

### 7.1 Basket (P0)
- `BasketWindowManager`: one `NSPanel` per basket, positioned near the pointer; follows
  the pointer while visible.
- Reveal triggers: shake-while-dragging (sensitivity: low/medium/high/very high),
  instant-on-drag, or hold-a-shortcut; mutually exclusive, matching the documented model.
- `Single` vs `Multi` basket mode; a Basket Switcher lists open baskets.
- Reuses `TrayDrop.shared` / `TrayDrop.DropItem` and the Shelf drop pipeline so a basket
  is a *second view* onto the same tray, not a second store.
- Carries the same Quick Action tiles as the Shelf (7.2).
- Settings page: reveal mode, sensitivity, appear/hide delay, single/multi, shortcut.

### 7.2 Quick Action tiles (P0)
- A tile is `{ id, title, systemImage, accepts: [UTType], consumesItems, perform: ([URL]) -> Void }`.
  A tile is offered only when the whole selection conforms to `accepts`.
- Built-ins: AirDrop, Mail, Messages, LocalSend, Copy path, Reveal in Finder,
  Open with…, OCR (→ clipboard), Trash.
- **Deferred:** Convert (→ 7.7) is not built. A tile is only worth showing once the
  engine behind it exists — a converter tile with no converter is a control that
  cannot do what it says.
- Rendered as a horizontal strip in the Shelf (Files page) and in every Basket.
- Registry (`QuickActionRegistry`) so extensions can contribute tiles later.

### 7.3 Ring (P0)
- Global shortcut held → translucent radial menu at pointer; release on a sector to fire.
- Actions from a user-ordered list seeded with: OCR, Emoji, Timer, Clipboard, Shelf,
  Window Snap, New Note.
- Pure `NSWindow` + SwiftUI, no new permissions (Accessibility already granted for
  window snap).

### 7.4 Emoji Picker (P0)
- Global shortcut → panel: search, recents, categories.
- Emoji table generated at build time into a Swift file (no bundled third-party data).
- Insert via `CGEvent` unicode into the frontmost app.

### 7.5 OCR (P0)
- `OCRService` wrapping Vision `VNRecognizeTextRequest` (on-device).
- Inputs: screen region (ScreenCaptureKit), image file, PDF page, or clipboard image.
- Output: text to clipboard + optional "open in editor".
- Clipboard integration: OCR runs on new image entries; result stored in `ocrText` and
  made searchable.

### 7.6 Window Snap (P0)
- `AXUIElement` window discovery; move/resize to halves, quarters, thirds, maximise,
  centre, next-display.
- Snap by pointer-drag to screen edge + hotkeys (recorded via `KeyboardShortcuts`).
- Requires Accessibility (Vone already requests it).

### 7.7 Converters (P1, listed for dependency clarity)
- `sips`/ImageIO for images, PDFKit for PDF, AVFoundation for video sizing. The image
  half is already in `ImageProcessingService`; the Quick Action tile waits on the rest.

## 8. Explicit non-goals

- Copying Droppy code, copy, icons or other assets.
- Running a hosted upload backend on our side.
- Bundling non-GPL-compatible converters (e.g. Ghostscript) — use system frameworks.
- Reimplementing anything already listed in §3.

## 9. Progress tracker

| Feature | State |
|---|---|
| Basket | built — `BasketManager`, `BasketView` |
| Basket Settings UI | built — `BasketSettingsSection` |
| Quick Action tiles | built (Basket only) — `QuickActionRegistry`, `QuickActionsStrip` |
| Ring | built — `RingActionManager` |
| Emoji Picker | built — `EmojiPickerManager`, `EmojiCatalog`, `EmojiPickerView` |
| OCR | built — `OCRService` |
| Window Snap | built — `WindowSnapManager` |
| Tools settings page | built — `ToolsSettingsView` (toggles for emoji, ring, snap, OCR) |
| Unit tests | built — `WindowSnapGeometryTests`, `BasketShakeTrackerTests` |
| Localisation catalogues | refreshed — 1782 keys, every M1 string present and extraction-stable (§10.2) |
| Notifications in notch | **not built — see §10.1** |

Everything above is in the working tree of `main` and has not been released; the M1
set is uncommitted apart from the first Basket commit.

## 10. Open items (deferred)

### 10.1 Notifications in the notch — dropped, and why

This was the one M1 item that could never start, so it was dropped rather than carried.
The research is kept so the next person to ask gets the same answer without redoing it:
macOS exposes **no public API for observing other apps' notifications**. The only
routes were:

1. Read the Notification Center database — needs Full Disk Access and a private,
   undocumented store Apple changes between releases. Fragile.
2. Accessibility-scrape the Notification Center window — breaks on UI changes and
   depends on window position.
3. Scoped version — mirror only Vone's own notifications plus publicly observable
   system events via `NSDistributedNotificationCenter`. Real, but far narrower, and
   partly duplicates the existing live activities.

(1) and (2) carry real privacy and maintenance costs, and even the honest version is
a worse copy of the live activities Vone already has, so none of the three was worth
taking.

### 10.2 Gaps in what shipped

| Area | Missing |
|---|---|
| OCR | Results are copied to the clipboard but not **indexed into clipboard search**. Needs `ClipboardManager` integration. A PDF is read 50 pages at a time; a longer document has its tail skipped, deliberately, rather than holding the recognition queue for minutes. |
| Quick Actions | Present on the **Basket only**; not wired into the Shelf view yet. The Convert tile waits on §7.7. |
| Basket | Nothing outstanding in M1 scope: shortcut reveal, the switcher, cursor following, appear/hide delays and the Escape/outside-click dismissal are all in. |
| Ring | Fires on click rather than **hold-and-release** on a sector. No user-ordered actions or extension contributions yet. |
| Window Snap | Hotkeys only — no pointer-drag-to-edge snapping. No thirds or next-display positions. |
| Emoji Picker | Catalogue is a curated ~200 entries; no skin-tone variants or generated full set. Its entry names and keywords stay English on purpose: they are the search index and double as tile tooltips, so translating one without moving the other would leave the picker searching in English while reading in another language. |
| All | **Done.** Both catalogues now carry every M1 string, `Send to Shelf` and `Enable Keep Awake` included. The pass also turned up strings that could never have been translated whatever the catalogue held: the Quick Action tile titles, the basket footer, the reveal-mode and shake-sensitivity names, the snap position names, the emoji category names and the OCR result panel were plain `String` values. They go through `String(localized:)` now, the Shortcuts page names each snap position from `SnapPosition` instead of repeating the words, and `SettingsPermissionCallout`'s title and button labels — which the Tools page shows — are localizable too. |

### 10.3 Refreshing the catalogues

The string catalogues are not updated by an ordinary `xcodebuild build`. The command
that extracts the code and rewrites `DynamicIsland/Localizable.xcstrings` in place is:

```
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -exportLocalizations -localizationPath /tmp/vone-loc -exportLanguage en
```

It writes an `en.xcloc` at that path and leaves the catalogue in Xcode's normalised
form, which reorders every entry — expect a large diff that is nonetheless additive.
New keys land as empty entries (`"Key" : {}`): the key *is* the English text, so they
read correctly in the source language and fall back to it everywhere else until someone
translates them. After a refresh, `Localizable.xcstrings` at the repository root needs
the same keys added by hand (§2 rule 5).

### 10.4 Test coverage

The two most valuable pieces of M1 logic are now covered: `WindowSnapManager`
geometry and coordinate conversion (`WindowSnapGeometryTests`) and the basket's
shake detection (`BasketShakeTrackerTests`, which drives `BasketShakeTracker` —
the reversal counting was pulled out of `BasketManager` so a test can drive it
without a real mouse).

Still uncovered: `RingActionManager`, `EmojiPickerManager`/`EmojiCatalog`,
`OCRService` and `QuickActionRegistry`.

Note that CI builds the app but does not run the Swift test bundle, so these run
locally via `xcodebuild test -scheme DynamicIsland`.

### 10.5 Packaging note

Local test builds need ad-hoc signing because the project expects upstream's team
(`DEVELOPMENT_TEAM = 9Y64TRM77N`) and no matching identity exists locally. Ad-hoc
signing requires dropping `com.apple.security.mach-services`, which disables the
extension XPC service at runtime. See §2 rule 3 for the general constraint.

_Sources reviewed: getdroppy.app home, /compare, /docs, /docs/droplets, /docs/shelf,
/docs/basket, /docs/clipboard, /docs/cloud, and the notch-capabilities blog post.
Vone inventory taken from `main` at commit `f6ddba4`._
