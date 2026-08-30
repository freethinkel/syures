# Getting started

syures is a launcher for macOS in the Raycast style. It has no window, no dock icon and no menu bar item. A global hotkey opens a floating card, you type, you press Enter.

Out of the box it launches apps. Everything else, from "open this URL" to a GitHub search, is a line in a config file.

## Build

There is no release yet. Build it with Xcode 16 or later:

```sh
git clone https://github.com/freethinkel/syures
cd syures
xcodebuild -scheme syures -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/syures-*/Build/Products/Release/syures.app
```

The `-destination` flag matters. Without it xcodebuild picks another SDK and the build fails.

## First run

Press Option+Space. The card opens. Start typing an app name, press Enter.

On first launch syures writes two files:

- `~/.config/syures/config.jsonc`, a commented template you edit
- `~/.config/syures/config.schema.json`, regenerated on every launch so your editor gets completion and type checks

You do not need to restart after editing the config. It is re-read every time the card opens. The hotkey is the one exception, see [Configuration](02-configuration.md).

## Keys

| Key | Does |
|---|---|
| Option+Space | open / close (configurable) |
| ↑ ↓, Ctrl+N / Ctrl+P | move the selection |
| Enter | launch, or open a submenu |
| Esc | step out of a submenu, or close |
| Backspace on an empty query | step out of a submenu |

The card can be dragged by its header. Drop it near its home position and it snaps back; anywhere else and it stays there until you snap it home again.

## Apps

syures scans these folders once at launch:

```
/Applications
/Applications/Utilities
/System/Applications
/System/Applications/Utilities
~/Applications
```

An app you install while syures is running shows up after a restart.
