# Configuration

Everything lives in `~/.config/syures/config.jsonc`. JSONC means comments and trailing commas are allowed. The first-run template is the reference, this page is the short version.

A key that is missing or malformed falls back to its default. A broken value never takes the whole file down with it.

## hotkey

```jsonc
"hotkey": "opt+space"
```

Modifiers: `cmd`, `opt` (or `alt`), `ctrl`, `shift`, joined with `+`. Keys: letters, digits, `space`, `return`, `tab`, `escape`. So `cmd+shift+k` works, `f1` does not.

This is the one key that needs a restart. The hotkey registers once at launch through Carbon, which is what lets syures work without the Accessibility permission.

## appearance

| Key | Default | Notes |
|---|---|---|
| `width` | `680` | card width in points |
| `cornerRadius` | `16` | |
| `queryFontSize` | `26` | the search field |
| `rowFontSize` | `14` | result rows; subtitles are 3 points smaller |
| `topOffset` | `0.2` | how far down the screen the card sits, as a fraction of screen height |
| `font` | system | a font family name, e.g. `"JetBrainsMono Nerd Font"`. Unknown names fall back to the system font |
| `searchIcon` | `"magnifyingglass"` | SF Symbol name, or any text. `""` hides it |
| `placeholder` | `"Search apps…"` | |
| `colorScheme` | follows the system | `"light"` or `"dark"` |
| `accent` | system | hex color, `#RRGGBB` or `#RRGGBBAA` |
| `background` | black in dark mode, window background in light | tints the wash over the card, opaque at the top and gone by the bottom. `#00000000` turns it off |
| `foreground` | system | text color |

Icons everywhere, `searchIcon` and a command's `icon`, take an SF Symbol name first. If the text is not a symbol it is drawn as is, so an emoji or a Nerd Font glyph works too.

## theme and themes

A theme is an overlay on `appearance`. It lists only the keys it changes.

```jsonc
"theme": "midnight",
"themes": {
  "system": {},
  "midnight": { "colorScheme": "dark", "background": "#000000", "accent": "#7C6CF0" },
  "paper": { "colorScheme": "light", "background": "#FFFFFF", "accent": "#0A84FF" },
},
```

A theme can also be a file. Drop `themes/nord.jsonc` next to the config, with the same shape as one entry above, and `"theme": "nord"` picks it up. That is how the template's "Import Theme" command works: it downloads a URL from the clipboard into `themes/`.

Switching themes is a command that rewrites one line of the config with `sed`. The template ships three. Since the config reloads when the card opens, the switch is visible the next time you press the hotkey.

## commands

The list of things you can launch besides apps. Each entry is a `Command`, covered on the next page.
