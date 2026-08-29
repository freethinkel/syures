# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`syures` — a Raycast-style macOS launcher. Menu-bar-less agent app (`.accessory` activation
policy): no window, no dock icon, only a global hotkey that toggles a floating panel.

No tests, no package manager, no dependencies — a plain Xcode project with 6 Swift files.

## Build & run

```sh
xcodebuild -scheme syures -destination 'platform=macOS' build
xcodebuild -scheme syures -destination 'platform=macOS' -configuration Debug   # dev build
open ~/Library/Developer/Xcode/DerivedData/syures-*/Build/Products/Debug/syures.app
```

`SDKROOT = auto`, so `-destination 'platform=macOS'` is required or xcodebuild picks another SDK.
`GENERATE_INFOPLIST_FILE = YES` — there is no Info.plist to edit; add keys via build settings
(`INFOPLIST_KEY_*`) in `project.pbxproj`.

## Architecture

Ownership chain: `SyuresApp` → `AppDelegate` → `LauncherPanel` → `Launcher` (model) + `LauncherView`.

- **SyuresApp.swift** — the `App` scene is an empty `Settings {}`; everything real happens in
  `AppDelegate.applicationDidFinishLaunching`: activation policy, default-config write, hotkey
  registration.
- **HotKey.swift** — Carbon `RegisterEventHotKey`, deliberately *not* an `NSEvent` global monitor,
  because Carbon needs no Accessibility permission. A single static C handler dispatches to
  instance closures by ID. Registration is one-shot at launch, so a hotkey change in the config
  needs a restart.
- **LauncherPanel.swift** — borderless `.nonactivatingPanel` at `.modalPanel` level. Dragging the
  card's header moves the window (`sendEvent` swallows the drag so the field does not select text);
  it snaps to the home position with guides on a screen-wide click-through overlay and an alignment
  haptic. A dragged-away position lives in UserDefaults; snapping home again clears it. The window is
  a fixed, transparent, oversized rect (max card size + a 48pt shadow margin); the SwiftUI card
  sizes itself inside it. `show()` avoids `NSApp.activate()` so the user's frontmost app keeps
  focus. `resignKey()` auto-hides.
- **Launcher.swift** — `@Observable` model. Apps are scanned once at launch from a fixed list of
  `/Applications`-style paths. Search is a fuzzy match over config commands + apps: a
  Smith-Waterman-style DP (`fuzzyScore`) scoring contiguous runs, word starts and camelCase, with
  one typo tolerated, sorted by score — the full list is shown, the card scrolls. Setting `query`
  triggers `search()` via `didSet`. `fuzzySelfCheck()` (DEBUG only, called from `AppDelegate`)
  asserts the ranking rules.
- **LauncherView.swift** — the whole UI, driven entirely by `launcher.config.appearance`. Never
  hardcode sizes/colors here; add a config key instead. The card is the scroll view itself: the
  field floats over it as a ZStack sibling (an overlay would be capped by the card's height, which
  is derived from the field), room is made with `contentMargins`, and a mask dissolves rows as they
  pass under it. Card width must be set before `CardSurface` draws, or the card is as wide as its
  longest row. Re-focus of the search field is driven by
  the `launcher.activation` counter, not by visibility.
- **Config.swift** — `~/.config/syures/config.jsonc` — JSONC (comments + trailing commas). The decoder keeps
  `allowsJSON5`, so looser files still parse; the written template stays strict JSONC.

## Config is the extension point

A `Config.Command` does exactly one of three things, and the schema enforces the `oneOf`:

- `run` — shell one-liner sent to `/bin/sh -c` with the config folder as its working directory, so
  `open https://…` and `./script.sh` both work. No separate "open a URL" key is needed.
- `commands` — a submenu written out in place.
- `menu` — a shell one-liner whose stdout is a JSON array of `Command`. **The plugin contract is the
  config schema**: plugin output nests further with the same three keys, `config.schema.json`
  validates both, and `Config.selfCheck()` covers both in one test.

Submenus live in `Launcher.stack`, so Esc/Backspace step back without the plugin emitting a `..`
entry (rofi's script mode has to). A plugin argument goes inside the `menu` string itself, which is
why there is no `ROFI_INFO`-style sideband. Inside a submenu an empty query lists the level in
authored order; at the root an empty query shows nothing.

`menu` scripts run on Enter, never per keystroke — that is what keeps them free of debounce,
cancellation and races. A per-keystroke provider (calculator, clipboard) would need all three.

Adding user-facing customization means adding a key to `Config.Appearance`/`Config.Command`, not
new UI.

Every config key decodes through `KeyedDecodingContainer.value(_:or:)` so a malformed or missing
key falls back to a default instead of failing the whole file — keep that property when adding
keys, and mirror any new key in `Config.template` (the self-documenting file written on first run).

Themes are overlays on `appearance`: `theme` names one, and it comes either from the inline
`themes` map or from `themes/*.jsonc` next to the config (that folder is how a theme is imported).
An overlay lists only the keys it changes — it decodes on top of `appearance` through
`decoder.userInfo[.appearanceBase]`, which is why `Config.load()` parses the file twice.

The config is reloaded on every `activate()`, so appearance and commands are live; the hotkey is
not.
