# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`syures` — a Raycast-style macOS launcher. Menu-bar-less agent app (`.accessory` activation
policy): no window, no dock icon, only a global hotkey that toggles a floating panel.

No tests, no package manager, no dependencies — a plain Xcode project, a dozen-odd Swift
files in `syures/`, with `Config/` and `Providers/` the two folders that grow.

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
- **Launcher.swift** — `@Observable` model. It owns the query, the submenu stack and the ordering,
  and nothing else: the rows come from the providers (see below). Matching is a Smith-Waterman-style
  DP (`fuzzyScore`) scoring contiguous runs, word starts and camelCase, with one typo tolerated —
  the full list is shown, the card scrolls. Frecency (launch counts in UserDefaults, halved every
  two weeks) is the tiebreaker, never a bonus added to the score: the gaps between a better and a
  worse match are as small as 2 points, so any bonus large enough to matter would overturn them.
  Setting `query` triggers `search()` via `didSet`. `selfCheck()` (DEBUG only, called from
  `AppDelegate`) asserts the ranking rules and `merge`, on rows made up in the check rather than
  whatever this machine has installed; `Calculator.selfCheck()` covers the arithmetic.
- **LauncherView.swift** — the whole UI, driven entirely by `launcher.config.appearance`. Never
  hardcode sizes/colors here; add a config key instead. The card is the scroll view itself: the
  field floats over it as a ZStack sibling (an overlay would be capped by the card's height, which
  is derived from the field), room is made with `contentMargins`, and a mask dissolves rows as they
  pass under it. Card width must be set before `CardSurface` draws, or the card is as wide as its
  longest row. Re-focus of the search field is driven by
  the `launcher.activation` counter, not by visibility.
- **Config/** — `~/.config/syures/config.jsonc` — JSONC (comments + trailing commas), split into
  `Config` (loading, schema, self-check), `Appearance`, `Color`, `Command` and `Template`. Every
  read goes through `Config.decoder(over:)` — the one decoder in the app, so a plugin's stdout and
  the config file are provably read the same way. It keeps `allowsJSON5`, so looser files still
  parse; the written template stays strict JSONC.

## Plugins are the extension point

Commands come from plugins, not the config: a plugin is a folder under `plugins/` next to the
config — usually a `git clone` — whose `plugin.jsonc` is a manifest: an object with one key today, `commands` — see
`Config.Manifest`, where a future key is an addition rather than a format break. The folder is
the working directory its scripts run from, so `./script.sh` in a manifest means the plugin's own
script. Installing is cloning, updating is `git pull`, removing is deleting the folder; the
starter plugin (written on first run, `Config.starterPlugin`) wraps install/update as commands.
A broken manifest skips that one plugin and logs, never the rest.

A `Config.Command` does exactly one of three things, and the schema enforces the `oneOf`:

- `run` — shell one-liner sent to `/bin/sh -c` with the plugin folder as its working directory, so
  `open https://…` and `./script.sh` both work. No separate "open a URL" key is needed.
- `commands` — a submenu written out in place.
- `menu` — a shell one-liner whose stdout is a JSON array of `Command` — the same shape as a
  manifest, so `menu` output nests further with the same three keys, `config.schema.json`
  validates config, manifest and `menu` output alike, and `Config.selfCheck()` covers them in one
  test.

`plugins/gh-search` is the worked example of all this — a folder with a manifest and a script,
installed by copying (`cp -p` keeps the executable bit) or cloning it into `plugins/`.

A `prefix` ("gh ") is the exception to fuzzy search: at the root it takes the query over and the
rest of it goes to the command's `run`/`menu` one-liner as a real `sh` positional parameter, `$1`,
never spliced into the script text. The one-liner is the shell command, so a plugin script of its
own gets the argument only if the one-liner forwards it: `./plugins/gh-search "$1"`. The longest
matching prefix wins. With `run` that happens on Enter. With `menu` the prefix opens the level at
once and the query *is* the argument: the script re-runs on every edit, debounced 300ms, and a
run the query or the level has outpaced drops its output (`Launcher.generation`). That is the one
per-keystroke path — an unprefixed `menu` still runs once, on Enter, and the query filters its
output locally.

Submenus live in `Launcher.stack`, so Esc/Backspace step back without the plugin emitting a `..`
entry (rofi's script mode has to). A plugin argument goes inside the `menu` string itself, or comes from `prefix`, which is
why there is no `ROFI_INFO`-style sideband. Inside a submenu an empty query lists the level in
authored order; at the root an empty query shows nothing.

Cancellation only skips a debounced run that has not started; a process already running goes to
the end and its output is dropped.

A `menu` needs a `prefix` to recompute per keystroke, and pays for it with debounce, cancellation
and generation checks.

Everything that fills the list is a `Provider` (`syures/Providers/`, one file each), and the
protocol is one method — `search(_:) -> [Entry]`. It takes the query because a source's answer
need not be in any list: a calculator reads `2+2` and builds the row for it, while a list-backed
source ignores the query here and lets the rows do the matching.

`Entry` is that row, and it is a class the providers subclass: `AppEntry`, `CommandEntry`,
`AnswerEntry`. It knows its own `name`, `subtitle`, `icon`, `frecencyID` (`nil` when there is no
history worth keeping), how well it fits a query
(`score`, one matcher for all so their numbers stay comparable, over a UTF-8 match key built
lazily — a row that is rebuilt on every keystroke and never matched, like an answer, never pays
for one)
and what to do when picked (`run(in:)` — the pasteboard, `NSWorkspace`, or a submenu). So there is
no enum of result kinds and `Launcher` never switches over what a row happens to be: it scores,
sorts, and calls `run`.

`exclusive` is an answer to the query rather than a match for it — one in the list and only those
are shown, which is how `2+2` shows the sum instead of apps whose names resemble it. `AnswerEntry`
also overrides `score` to a constant, since the matcher would never find "4" in the `2+2` it came
from. `merge` orders by score, then frecency, then the provider's place in `Launcher.allProviders`,
then the name — that array is the registry, and adding a provider is adding a file next to it plus a word in it.
A Swift type cannot be registered at runtime, which is what `menu` scripts are for.

Opening a submenu is the exception to "the entry does the work": it is a state the card goes into,
so `CommandEntry.run` hands back to `Launcher.open`, which owns the stack.

`syures/Config/` splits the same way: `Config` (loading, schema, self-check), `Appearance`,
`Color`, `Command`, and `Template` — the file written on first run, which is also the
documentation of every key.

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
