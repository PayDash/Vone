# Vone Feature Roadmap — parity with paid notch apps

Status: **M1 complete · M2/M3/M4 scoped** · Owner: Vone · Basis: review of Droppy
(getdroppy.app) docs + public feature set, cross-checked against Vone `main`, plus
DockFlow and Stash for M4 (§10).

M1 is not tracked here any more. `CHANGELOG.md` is the record of what shipped, and the
same changelog is readable inside the app (Settings ▸ Changelog), so this document now
holds only the work that is left plus the reference material that outlives it.

---

## 1. Purpose

Make Vone the best free notch app by closing the feature gap against paid competitors,
starting with **Droppy** (getdroppy.app, one-time paid, closed source). "Parity" means
**equivalent user-facing capability implemented independently** — not copied code.

The scope is what §4, §6 and §10 list. Anything else — including anything that was once
considered and set aside — is out of scope for this roadmap.

*(One page shipped outside that scope because it was asked for rather than because a
competitor has it: the changelog under Settings ▸ About. It is recorded in
`CHANGELOG.md` and deliberately not tracked here.)*

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
   `String`-returning property. See §9.3 for the refresh command.

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
| Basket, Quick Action tiles, Action Ring, Emoji Picker, Window Snap, on-device OCR, Tools settings | `BasketManager`, `QuickActionRegistry`, `RingActionManager`, `EmojiPickerManager`, `WindowSnapManager`, `OCRService` — shipped in M1 |

## 4. What Droppy has that Vone still lacks

Priority: **P0** flagship/user-visible differentiators · **P1** high value · **P2** nice-to-have.
Effort: S ≤ 1 day · M ≤ 3 days · L ≤ 1 week · XL > 1 week.

The P0 surfaces — Basket, Quick Action tiles, Ring, Emoji Picker, Window Snap, OCR —
shipped in M1 and have left this list. What remains:

| # | Feature | What Droppy does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 1 | **Shelf widgets** | Any extension can place a widget on the shelf, alone or beside another | 🟡 Shelf exists, widget slots unverified | P1 | M |
| 2 | **Non-notch mode** | Floating shelf + menu-bar-only on notch-less Macs and external displays | 🟡 unverified (`MenuBarLayout`, `NotchSpaceManager`) | P1 | M |
| 3 | **Converters** | Local file conversion (images/docs); PDF compression; video "target size" compression | 🟡 `ImageProcessingService` does the image half inside the Shelf; documents, PDF compression and video sizing are missing (§7) | P1 | M–L |
| 4 | **Thaw** — menu bar item manager | Hide/arrange menu bar items | 🟡 `MenuBarLayout` only | P1 | M |
| 5 | **Agents** | Live Claude / Codex / Cursor / Antigravity / OpenCode progress | 🟡 `LLMUsage` covers Claude/Codex/Antigravity; **Cursor + OpenCode missing** | P1 | M |
| 6 | **Droplet surfaces** | Each extension can expose shelf widget / live activity / lock screen / shortcut / menu-bar item | 🟡 extension kit exists; surface coverage unverified | P1 | M |
| 7 | **Play Next queue / output picker** | Up-next queue and audio output picker in the player | 🟡 AirPlay/route managers exist, queue unverified | P2 | S |
| 8 | **Motion art in shelf** | Animated art in the shelf | 🟡 `AnimatedArtworkManager` + Lottie present | P2 | S |

Background removal is not on this list: it is already built (§3), using Vision's
foreground mask on device, and is covered by the Shelf's image processing.

Gaps inside features that have already shipped — pointer-drag window snapping, OCR
indexed into clipboard search, the Ring's hold-and-release — are listed in §9.2 rather
than repeated here.

## 5. Architecture & integration plan

All new work follows existing Vone patterns:

- **Managers** live in `DynamicIsland/managers/` as `ObservableObject` singletons
  (`static let shared`), owned/wired in `DynamicIslandApp.swift` or
  `DynamicIslandViewCoordinator.swift`.
- **Floating surfaces** use the existing borderless-panel pattern
  (`FlyoutWindowPresenter`, `ScreenAssistantPanelManager`, `ColorPickerManager`):
  `NSPanel`, `.nonactivatingPanel`, `.canJoinAllSpaces`, level above `.mainMenu`.
- **Global input** is a global `NSEvent` monitor rather than an event tap, the way
  `BasketManager`'s shake detection works; anything with logic worth testing is pulled
  out of the manager so a test can drive it without a mouse (`BasketShakeTracker`).
- **Clipboard OCR indexing** is an `ocrText` field on `ClipboardItem` plus one
  `matches(_:)`, not a second store — the same shape to reach for the next field that
  should be searchable.
- **Window Snap** uses the **Accessibility API** (`AXUIElement`); no new entitlement
  beyond the Accessibility permission already asked for.
- **Extension surfaces**: extend `AtollExtensionKit`-facing descriptors one surface at a
  time (shelf widget → live activity → lock screen → menu bar).
- **Bundled documents** are referenced from the repository root into the target's
  Resources phase rather than copied into `DynamicIsland/`, so there is one file to keep
  current (`CHANGELOG.md` is the worked example).

## 6. Milestones — what is left

**M2 — File tools (P1)**
Agent coverage (Cursor, OpenCode) · Converters (§4 row 3, §7 — the image half already
exists in `ImageProcessingService`).

**M3 — Depth (P1/P2)**
Non-notch mode · Shelf widgets · Droplet surfaces (§4 rows 1 and 6, kept together — it is
the same surface work) · Thaw · Play Next queue + output picker · Motion art.

**M4 — Workspace, Dock and edge controls (P1/P2, added at the owner's request)**
Dock presets (§10.1) · Edge sliders, corner dials, hidden dock and app profiles (§10.2).
Neither app is Droppy, so neither is parity work; both were asked for on their own
merits, and both are closed source under the same clean-room terms as §2.

**M1 carry-over — closed.** The three open items were finished: the Quick Action tiles
now sit on the Shelf as well as in the Basket, copied images are indexed for clipboard
search, and the Ring chooses a sector by holding and releasing rather than by the click
landing. What is left inside those features is in §9.2, listed as gaps rather than as
carry-over.

## 7. Detailed spec — Converters (M2)

The only remaining spec worth writing down before it is built; everything else in M2/M3
is either a small addition to an existing surface or has its shape dictated by the
extension kit.

`sips`/ImageIO for images, PDFKit for PDF, AVFoundation for video sizing. The image half
is already in `ImageProcessingService`; the Quick Action tile waits on the rest — a
converter tile with no converter behind it is a control that cannot do what it says, so
it is deliberately not offered yet. Ghostscript and friends stay out (§8).

## 8. Explicit non-goals

- Copying Droppy code, copy, icons or other assets.
- Running a hosted upload backend on our side.
- Bundling non-GPL-compatible converters (e.g. Ghostscript) — use system frameworks.
- Reimplementing anything already listed in §3.

## 9. Open items

### 9.1 Notifications in the notch — dropped, and why

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

### 9.2 Gaps in what shipped

| Area | Missing |
|---|---|
| OCR | Copied images are indexed into clipboard search now (Vision, in the background, gated on the recognition setting). A PDF is still read 50 pages at a time; a longer document has its tail skipped, deliberately, rather than holding the recognition queue for minutes. |
| Quick Actions | On the **Basket and the Shelf** now. The Convert tile waits on §7. |
| Ring | A sector is chosen by **hold-and-release**, and a release that lands off the sector leaves the ring open. No user-ordered actions or extension contributions yet, and the four actions are still the built-in set. |
| Window Snap | Hotkeys only — no pointer-drag-to-edge snapping. No thirds or next-display positions. |
| Emoji Picker | Catalogue is a curated ~200 entries; no skin-tone variants or generated full set. Its entry names and keywords stay English on purpose: they are the search index and double as tile tooltips, so translating one without moving the other would leave the picker searching in English while reading in another language. |
| Changelog | Reads the `CHANGELOG.md` the build shipped with, so a release published after this build is not listed until the app updates. The document itself is English; only the page around it is translated. |
| Localisation | Catalogues are current as of M1 (see §9.3 for how to keep them that way). The rest of the app still holds user-facing strings that were never localisable — `SettingsPermissionCallout`'s **call sites** pass their message as a plain `String`, and the wider sweep in #789 did not reach every file. Counted at ~580 candidate literals across ~90 files when M1 was finished, most of them diagnostics rather than UI. |

### 9.3 Refreshing the string catalogues

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

### 9.4 Test coverage

Covered: `WindowSnapManager` geometry and coordinate conversion
(`WindowSnapGeometryTests`), the basket's shake detection (`BasketShakeTrackerTests`),
and the changelog parser including the document the app ships
(`ChangelogParserTests`).

Also covered: clipboard search, including the recognised text of an image and a
stored history written before that field existed (`ClipboardSearchTests`).

Still uncovered: `RingActionManager`, `EmojiPickerManager`/`EmojiCatalog`,
`OCRService`, `QuickActionRegistry`, and the shelf's new height rule
(`shelfAdjustedNotchSize` — one branch, but it decides whether the tiles are visible).

Two suites are **timing-sensitive and flake under load** —
`ClipboardHistoryPersistenceTests` and `AppleMusicControllerTests` both wait on
asynchronous publishing with short timeouts, and each has been seen to fail in a full
run while passing alone. They are worth widening before anyone trusts a red run; CI
does not run the Swift test bundle at all, so a failure here is only ever seen locally
via `xcodebuild test -scheme DynamicIsland`.

### 9.5 Packaging and local builds

Local test builds need ad-hoc signing because the project expects upstream's team
(`DEVELOPMENT_TEAM = 9Y64TRM77N`) and no matching identity exists locally. Ad-hoc
signing requires dropping `com.apple.security.mach-services`, which disables the
extension XPC service at runtime (§2 rule 3) — without dropping it, `amfid` kills the
app on launch. `build/vone-adhoc.entitlements` is the tracked entitlements file minus
that key.

Note that CI's attempt to strip it does not work: `plutil -remove
com.apple.security.mach-services` reads the dots as a **key path**, so it looks for a
nested `com ▸ apple ▸ security ▸ mach-services` and reports "No value to remove", which
the workflow accepts as "already absent". The entitlement is still in the built app.

## 10. Beyond Droppy — two paid utilities worth taking capability from

Added at the owner's request. Neither app is Droppy and neither is closed to us in any
way the §2 ground rules do not already cover: features and workflows are fair to
reimplement, code, copy, icons and illustrations are not. Priorities and efforts use the
§4 scale.

**Stash Deck — the iPhone companion app — is out of scope.** Stash without it is a
local utility; this roadmap takes the local half only. No remote control of the Mac from
another device, no pairing, no account.

### 10.1 DockFlow (dockflowapp.io) — Dock presets

One-time purchase (€29.99–€69.99). Keeps the **native** Dock and switches its contents:
a preset is a saved Dock, and switching one closes the apps of the old layout and opens
the apps of the new one. No permission is needed for the core switching; only its
"lock Dock to a display" feature asks for Accessibility.

| # | Feature | What it does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 1 | **Dock presets** | Save the current Dock as a named preset; switch between them in one click | ❌ nothing reads or writes the Dock's contents today | P1 | M |
| 2 | **Per-preset hotkeys** | Single key, key sequence, or multi-press to switch | 🟡 `KeyboardShortcuts` is already a dependency and the Shortcuts page rebinds keys — this is one more row per preset | P1 | S |
| 3 | **Folders, files and links in a preset** | A preset holds more than apps | ❌ falls out of #1: `persistent-others` carries any file URL | P1 | S |
| 4 | **Dock spacers** | Named spacers that break the Dock into visual groups | ❌ `tile-type` spacer entries, written by hand into the preset | P2 | S |
| 5 | **App actions on switch** | Launch with arguments — an IDE opens its project, a browser opens a profile | ❌ `NSWorkspace.open(_:configuration:)` per app, stored per preset | P2 | M |
| 6 | **Apple Shortcuts** | Presets as actions in Shortcuts | 🟡 Vone already ships a Shortcuts surface; presets become intents on it | P1 | S |
| 7 | **Focus-mode switching** | Switching Focus switches the Dock | 🟡 `DoNotDisturbManager` already observes Focus; presets append to it | P2 | S |
| 8 | **Lock Dock to a display** | The Dock stops following the pointer between displays | ❌ Accessibility-driven; Vone asks for Accessibility already (Window Snap, menu-bar measurement) | P2 | M |
| 9 | **Export / import presets as JSON** | Backup and migration, one preset or all | ❌ trivially local, and worth having before #1 has users | P2 | S |
| 10 | DockShare — preset sharing | A hosted place to trade presets | — | — | — |

Notes that decide how #1 is built:

- **Presets are the Dock's own preference domain** (`com.apple.dock`: `persistent-apps`,
  `persistent-others`, `tile-type` for spacers) applied by writing the domain and
  restarting Dock. That is what every Dock utility does, needs no entitlement, and is the
  one place where being an app that writes another process's preferences is expected.
  A failed write must leave the previous preset in place — the Dock is the user's
  launcher, and half-applying a preset is worse than not switching.
- **Closing apps on switch is a destructive step**, so it belongs behind its own switch,
  off by default, with unsaved work respected (`NSRunningApplication.terminate()` rather
  than a kill, and never for the app in front).
- **DockShare is not a non-goal we have to argue about** — §2 rule 3 already rules out
  running a hosted service, so #9's local JSON is the whole of that feature.
- **Vone lives in the notch, and so does this setting.** Presets want a menu-bar or
  Settings surface; the notch's own menu-bar clearance logic (`MenuBarLayout`) is what
  keeps the two from overlapping.

### 10.2 Stash (stashformac.com) — hidden controls at the screen's edges

Lifetime unlock ($7.99 one Mac). Controls that stay out of sight at the edges and
corners of the screen until the pointer reaches for them, with detents felt through the
trackpad and a small sound. Its own site notes it needs **macOS Tahoe**, where Vone
targets macOS 14.6 — so the surfaces below have to hold on the older systems Vone
supports, not just on Apple's newest.

| # | Feature | What it does | Vone status | Pri | Effort |
|---|---|---|---|---|---|
| 1 | **Edge sliders** | The left or right screen edge is a slider for volume, brightness or appearance | 🟡 `SystemHUDManager` and the OSD helpers already own those values and their read-back; the surface is new | P1 | M |
| 2 | **Corner dials** | A dial in a screen corner for volume, brightness, keyboard backlight or audio output | 🟡 `SystemKeyboardBacklightController` and `AudioRouteManager` are the engines; the surface is new | P1 | M |
| 3 | **Hidden dock** | Up to eight apps hidden at an edge that slides out on approach, alongside the real Dock | ❌ nearest thing is the Shelf, which holds files rather than apps | P1 | M |
| 4 | **App profiles** | Hidden dock, sliders and dials change with the app in front | ❌ per-app settings exist for volume only; the trigger is a frontmost-app observer either way | P2 | M |
| 5 | **Detents, sound, animation** | Every step is felt and heard | 🟡 `NSHapticFeedbackManager` is already used (the Ring announces itself with it) | P2 | S |
| 6 | **Stash Deck (iPhone)** | Control the Mac from the phone | — | — | — |

Notes that decide how these are built:

- **All four surfaces are the same kind of object**: a borderless, non-activating panel
  at a screen edge, revealed by pointer proximity, which is the pattern §5 already
  records (`FlyoutWindowPresenter`, `ScreenAssistantPanelManager`). One reveal engine
  with four contents beats four panels.
- **Proximity, not hotkeys.** These are reached by moving the pointer to an edge, so the
  tracking has to be cheap: a screen-edge band checked from the existing pointer monitor
  rather than a timer per panel.
- **The notch is in the way at the top.** An edge slider or dial on a notched display
  must yield the menu-bar strip to Vone's own notch, the same strip `MenuBarLayout`
  measures, or the two will fight over the same pixels.
- **Appearance as a slider** means the system appearance: one write to the global domain,
  not a per-app override, or the slider lies about what it changed.
- **Hidden dock vs. the real Dock.** The value is apps that are *not* in the Dock; it
  must not try to mirror or hide the system one.

---

_Sources reviewed: getdroppy.app home, /compare, /docs, /docs/droplets, /docs/shelf,
/docs/basket, /docs/clipboard, /docs/cloud, and the notch-capabilities blog post;
dockflowapp.io home and /uses/mac-dock-replacement; stashformac.com home and FAQ.
Vone inventory taken from `main` at commit `f6ddba4`, gaps re-checked at M1 close._
