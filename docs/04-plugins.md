# Plugins

A plugin is a folder under `~/.config/syures/plugins/`. Installing one is making that folder — usually with `git clone` — and removing one is deleting it. There is no registry and no SDK; the whole contract is one file:

```
~/.config/syures/plugins/<name>/
  plugin.jsonc     the manifest: a JSON array of commands
  …                whatever else the plugin needs — scripts run from this folder
```

The manifest has the same shape a `menu` script prints, with the same three keys per command: `run`, `commands`, `menu`. `config.schema.json` describes both. On the first run syures writes `plugins/starter/` — a working manifest with `install`/`update` commands and examples to steal.

```sh
# install
git clone https://github.com/you/your-plugin ~/.config/syures/plugins/your-plugin
# update them all
for d in ~/.config/syures/plugins/*/; do git -C "$d" pull; done
```

The starter plugin wraps both of those as commands, so `install <url>` from the launcher itself works too. A cloned plugin is code that runs as you — read it first, the schema validates shape, not intent.

## A minimal plugin

```sh
#!/bin/sh
# ~/.config/syures/plugins/projects/projects
ls -d "$1"/*/ | sed 's|/$||' | while read -r dir; do
  printf '{ "name": "%s", "run": "open \\"%s\\"" },' "$(basename "$dir")" "$dir"
done | sed 's/^/[/; s/,$/]/'
```

```jsonc
// ~/.config/syures/plugins/projects/plugin.jsonc
[{ "name": "Projects", "icon": "folder", "menu": "./projects ~/Developer" }]
```

The argument goes in the `menu` string. Or it comes from the user through `prefix`, covered in [Commands](03-commands.md#prefix).

For anything past a `printf`, use a language with a JSON library. The bundled `plugins/gh-search` uses `gh`'s own `--jq` flag to build the array, so it needs no extra dependency.

## When it runs

A plain `menu` runs once, on Enter. Typing afterwards filters the list it returned, syures does not run it again. That fits a plugin that lists things, like projects or windows.

A `menu` with a `prefix` is a search plugin. Its level opens as soon as you type the prefix, and the script runs for every edit of the argument, debounced by 300 ms. The script does the filtering, so make it fast and make it handle an empty `$1`. `gh-search` prints `[]` for an empty argument rather than searching for nothing.

Either way the level is on screen with a spinner in the field while the script runs. If you keep typing, or press Esc, before it finishes, its output is dropped.

## Error handling

If the script fails to start or prints something that is not a command array, the submenu stays empty and syures logs the reason. Check it with:

```sh
log stream --predicate 'process == "syures"' --style compact
```

A friendlier pattern is to print the error as a command, the way `gh-search` does when `gh` is missing:

```json
[{ "name": "Install the gh CLI", "icon": "exclamationmark.triangle", "run": "open https://cli.github.com" }]
```

The user sees the problem and Enter fixes it.

## Installing the bundled example

```sh
cp -pR plugins/gh-search ~/.config/syures/plugins/
```

`-p` keeps the executable bit; a `git clone` of a plugin repo works the same way. Its `plugin.jsonc` already declares the `gh ` prefix — type `gh swift` and get the top twenty repos.
