# Vone Feature Roadmap — parity with paid notch apps

Status: **planning** · Owner: Vone · Basis: review of Droppy (getdroppy.app) docs + public feature set, cross-checked against Vone `main`.

---

## 1. Purpose

Make Vone the best free notch app by closing the feature gap against paid competitors,
starting with **Droppy** (getdroppy.app, one-time paid, closed source). "Parity" means
**equivalent user-facing capability implemented independently** — not copied code.

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
   user-facing toggles live in Settings.

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

## 4. Gap analysis — Droppy capabilities Vone lacks

Priority: **P0** flagship/user-visible differentiators · **P1** high value · **P2** nice-to-have.
Effort: S ≤ 1 day · M ≤ 3 days · L ≤ 1 week · XL > 1 week.

### 4.1 Core surfaces

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 1 | **Basket** — floating tray at the cursor | Shake while dragging (or instant/hotkey) summons a floating tray; single & multi-basket; basket switcher; carries Quick Actions | ❌ none (Shelf is notch-bound only) | **P0** | M |
| 2 | **Quick Action tiles** | Drop a file on a tile → AirDrop / share link / Mail / convert, without dropping elsewhere first | 🟡 partial (`AirDropView`, `QuickShareService`) | **P0** | S–M |
| 3 | **Ring** — radial action picker | Hold a shortcut, choose from a ring of actions around the pointer | ❌ none | **P0** | S |
| 4 | **Shelf widgets** | Any extension can place a widget on the shelf, alone or beside another | 🟡 Shelf exists, widget slots unverified | P1 | M |
| 5 | **Non-notch mode** | Floating shelf + menu-bar-only on notch-less Macs and external displays | 🟡 unverified (`MenuBarLayout`, `NotchSpaceManager`) | P1 | M |

### 4.2 File & capture tools

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 6 | **OCR** | Extract text from screen/images/PDF; OCR text is indexed into clipboard search | ❌ user-facing tool (Vision is only used inside Screen Assistant) | **P0** | S–M |
| 7 | **Element Capture** | Pick a single UI element and capture it | ❌ | P1 | M |
| 8 | **Converters** | Local file conversion (images/docs); PDF compression; video "target size" compression | ❌ | P1 | M–L |
| 9 | **AI background removal** | Remove image background via an external runtime | 🟡 unclear/partial | P1 | M |
| 10 | **Voice transcribe** | Record voice, on-device transcription, live status in notch | ❌ | P1 | M |
| 11 | **Finder Services** | Right-click → "Add to Vone" in Finder | ❌ (no Finder Sync extension) | P1 | M |
| 12 | **Alfred workflow** | Keyboard-first file management into the shelf | ❌ | P2 | S |

### 4.3 Windows, input & menus

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 13 | **Window Snap** | Pointer + keyboard window management (snap/half/quarter) | ❌ none (Accessibility API not used for windows) | **P0** | M |
| 14 | **Emoji Picker** | Global shortcut opens an emoji panel that inserts into the front app | ❌ | **P0** | S |
| 15 | **Thaw** — menu bar item manager | Hide/arrange menu bar items | 🟡 `MenuBarLayout` only | P1 | M |
| 16 | **LiquidMouse** | Smooth scrolling + reverse direction | ❌ | P2 | S |
| 17 | **Mechey** | Mechanical keyboard sound effects | 🟡 caps-lock click only | P2 | S |
| 18 | **Mac Duo** | Lock/unlock animation styled like an iPhone Duo | ❌ | P2 | S |

### 4.4 Communication & presence

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 19 | **Notifications in the notch** | Mirror macOS notifications into the notch | ❌ | **P0** | M |
| 20 | **Inline reply** | Reply to WhatsApp/iMessage from the notch | ❌ | P1 | L |
| 21 | **Meetings** | Mute / camera / share controls during a call | ❌ (calendar events only) | P1 | M |
| 22 | **Quick notes → Apple Notes** | Note editor in notch that syncs to Apple Notes | ✅ mostly (`AppleNotesSyncManager`) | — | S (polish) |
| 23 | **Teleprompter** | Script reader under the camera | ❌ | P2 | S |

### 4.5 Agents, sharing & ecosystem

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 24 | **Cloud share links** | Upload → short private link, auto-expiry, active-share list | 🟡 `FileShareView`/`QuickShareService` = LAN/quick share only | P1 | L–XL |
| 25 | **Agents** | Live Claude / Codex / Cursor / Antigravity / OpenCode progress | 🟡 `LLMUsage` covers Claude/Codex/Antigravity; **Cursor + OpenCode missing** | P1 | M |
| 26 | **Extension Store UX** | Browse catalogue, on/off per extension, per-extension settings page | 🟡 Extensions exist, no browse/install store UI | P1 | M |
| 27 | **Droplet surfaces** | Each extension can expose shelf widget / live activity / lock screen / shortcut / menu-bar item | 🟡 extension kit exists; surface coverage unverified | P1 | M |
| 28 | **LocalSend** | Device-to-device transfer, no cloud | ✅ present (`LocalSendService`) | — | — |
| 29 | **VPN live status** | VPN state + session timer in notch | 🟡 `NetworkConnectivityManager` unclear | P2 | S |
| 30 | **Play Next queue / output picker** | Up-next queue and audio output picker in the player | 🟡 AirPlay/route managers exist, queue unverified | P2 | S |
| 31 | **Motion art in shelf** | Animated art in the shelf | 🟡 `AnimatedArtworkManager` + Lottie present | P2 | S |
| 32 | **Obsidian vault on shelf** | Live vault widget | ❌ | P2 | M |
| 33 | **Droppy for iPhone + E2E sync** | Companion iOS app, encrypted sync | ❌ | P2 | XL (separate repo) |
| 34 | **Playground app + SDK** | Sandbox app to preview third-party extensions | 🟡 `AtollExtensionKit` SDK exists | P2 | M |

## 5. Architecture & integration plan

All new work follows existing Vone patterns:

- **Managers** live in `DynamicIsland/managers/` as `ObservableObject` singletons
  (`static let shared`), owned/wired in `DynamicIslandApp.swift` or
  `DynamicIslandViewCoordinator.swift`.
- **Floating surfaces** use the existing borderless-panel pattern
  (`FlyoutWindowPresenter`, `ScreenAssistantPanelManager`, `ColorPickerManager`):
  `NSPanel`, `.nonactivatingPanel`, `.canJoinAllSpaces`, level above `.mainMenu`.
- **Shake-to-summon** reuses the drag-detection approach already implicit in the Shelf;
  add a global `NSGestureRecognizer`-free mouse-monitor based shaker (`MouseTracker.swift`
  exists) so it works over any app.
- **Clipboard OCR indexing** extends `ClipboardManager` entries with an `ocrText` field
  and a search index, instead of a new store.
- **Window Snap / Element Capture** use the **Accessibility API** (`AXUIElement`) and
  **ScreenCaptureKit**; no new entitlement beyond existing Accessibility + Screen Recording.
- **Emoji Picker / Ring / Teleprompter** are self-contained panels; insertion via
  `CGEvent` unicode injection into the focused app.
- **Sharing**: "cloud link" is implemented as *bring-your-own* (user-configured WebDAV /
  S3-compatible endpoint) so we need no hosted backend; LocalSend remains the zero-config
  path.
- **Extension surfaces**: extend `AtollExtensionKit`-facing descriptors one surface at a
  time (shelf widget → live activity → lock screen → menu bar).

## 6. Milestones

**M1 — Flagship surfaces (P0)**
Basket · Quick Action tiles · Ring · Emoji Picker · Window Snap · OCR · Notifications in notch.

**M2 — Capture & comms (P1)**
Element Capture · Voice Transcribe · Meetings · Finder Services · Agent coverage (Cursor, OpenCode) · Extension Store UX · Converters.

**M3 — Depth (P1/P2)**
Non-notch mode · Shelf widgets · Thaw · Inline reply · Cloud share links · VPN status · Play Next queue · Motion art.

**M4 — Long tail (P2)**
Alfred · LiquidMouse · Mechey · Mac Duo · Teleprompter · Obsidian · Playground app · iOS companion (separate repo).

## 7. Detailed specs — M1

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
- A tile is `{ id, title, systemImage, accepts: [UTType], perform: ([DropItem]) -> Void }`.
- Built-ins: AirDrop, LocalSend, Mail, Copy path, Reveal in Finder, Open with…,
  OCR (→ clipboard), Convert (→ 7.5), Share link (→ 7.7), Trash.
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

### 7.7 Converters & share links (P1, listed for dependency clarity)
- Converters: `sips`/ImageIO for images, PDFKit for PDF, AVFoundation for video sizing.
- Share link: user-configured WebDAV/S3-compatible target; no hosted service.

## 8. Explicit non-goals

- Copying Droppy code, copy, icons or other assets.
- Running a hosted upload backend on our side.
- Bundling non-GPL-compatible converters (e.g. Ghostscript) — use system frameworks.
- Reimplementing anything already listed in §3.

## 9. Progress tracker

| Feature | Status |
|---|---|
| Basket | planned |
| Quick Action tiles | planned |
| Ring | planned |
| Emoji Picker | planned |
| OCR | planned |
| Window Snap | planned |
| Notifications in notch | planned |

_Sources reviewed: getdroppy.app home, /compare, /docs, /docs/droplets, /docs/shelf,
/docs/basket, /docs/clipboard, /docs/cloud, and the notch-capabilities blog post.
Vone inventory taken from `main` at commit `f6ddba4`._
