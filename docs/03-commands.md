# Commands

A command is an entry in the `commands` array. It has a `name`, optionally a `subtitle` and an `icon`, and exactly one of three things it does.

## run

A shell one-liner. It goes to `/bin/sh -c` with `~/.config/syures` as the working directory, so `open` and `./script.sh` both work as written.

```jsonc
{ "name": "GitHub", "icon": "globe", "run": "open https://github.com" },
{ "name": "Sleep", "icon": "moon.fill", "run": "pmset sleepnow" },
{ "name": "Files", "icon": "", "run": "open ~" },
```

There is no separate "open URL" key. `open` is the key.

## commands

A submenu written out in place.

```jsonc
{ "name": "Theme", "icon": "paintpalette", "commands": [
  { "name": "System",   "run": "sed -i '' 's/\"theme\": \".*\"/\"theme\": \"system\"/' config.jsonc" },
  { "name": "Midnight", "run": "sed -i '' 's/\"theme\": \".*\"/\"theme\": \"midnight\"/' config.jsonc" },
]},
```

Enter opens it. The search field shows a chip with the submenu's name and icon in place of the search icon, and typing filters inside that level. Esc or Backspace on an empty query steps back out. With an empty query a submenu lists its entries in the order you wrote them.

Submenus nest as deep as you like.

## menu

A shell one-liner whose standard output is a JSON array of commands. That array becomes the submenu. This is the plugin mechanism, see [Plugins](04-plugins.md).

```jsonc
{ "name": "Projects", "menu": "./plugins/projects ~" },
```

## prefix

`prefix` is an addition to `run` or `menu`, not a fourth kind. When the query starts with the prefix, fuzzy search steps aside and whatever follows the prefix goes to the one-liner as `$1`.

With `run`, the card shows that one command and Enter runs it:

```jsonc
{ "name": "Google", "prefix": "g ", "icon": "globe", "run": "open \"https://google.com/search?q=$1\"" },
```

With `menu`, the prefix is a search command. Typing `gh ` opens the GitHub level at once, and from there the field is the argument. Every edit re-runs the script, debounced by 300 ms, with a spinner in the field while it runs. Arrows and Enter pick a result.

```jsonc
{ "name": "GitHub", "prefix": "gh ", "icon": "globe", "menu": "./plugins/gh-search \"$1\"" },
```

Typing `gh swift` runs `./plugins/gh-search "swift"` and lists what it printed.

Two details worth knowing. `$1` is a real shell parameter, not text pasted into the command, so a query with spaces, quotes or a `;` in it stays one argument and never runs as code. And because the one-liner is what receives `$1`, a script of your own only sees the argument if you pass it on, hence the `"$1"` in the example.

The trailing space in `"gh "` is deliberate. Without it `ghost` would match. If two prefixes both match, the longer one wins, so `"g"` and `"gh "` can coexist.

A `prefix` only works at the root, and it cannot go on a `commands` entry, since there is no script to hand the argument to. The schema rejects that combination.

## Frecency

Results are ranked by how well they match. Frecency, how often and how recently you launched something, only breaks ties. It never lifts a worse match above a better one. Counts halve every two weeks.
