# Plugins

A plugin is any program that prints a JSON array of commands. Point a `menu` at it and its output is a submenu. Nothing to register, no SDK, no manifest.

The output has the same shape as the `commands` array in your config, with the same three keys: `run`, `commands`, `menu`. So a plugin's output can itself contain submenus and further `menu` scripts. `config.schema.json` describes both the config and plugin output, since they are the same thing.

## A minimal plugin

```sh
#!/bin/sh
# ~/.config/syures/plugins/projects
ls -d "$1"/*/ | sed 's|/$||' | while read -r dir; do
  printf '{ "name": "%s", "run": "open \\"%s\\"" },' "$(basename "$dir")" "$dir"
done | sed 's/^/[/; s/,$/]/'
```

```jsonc
{ "name": "Projects", "icon": "folder", "menu": "./plugins/projects ~/Developer" },
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
cp -pR plugins ~/.config/syures/
```

`-p` keeps the executable bit. Then add to `commands`:

```jsonc
{ "name": "GitHub", "prefix": "gh ", "icon": "globe", "menu": "./plugins/gh-search \"$1\"" },
```

Type `gh swift`, press Enter, get the top twenty repos.
