# rex-agents

A herdr-style agent list for [Rex](https://www.superlogical.com/rex). It puts a narrow panel on the right of every tab with one row per coding agent across all your sessions, and adds a key that jumps to whichever agent is waiting on you.

```
 🔴 1 waiting  ↑↓ · q

1 🔴 ✻ deploy-check          ← gold bar: waiting on you
    needs approval: Bash: k…
    ⎇ main ●2
▶ ⏳ ✻ api-refactor          ← ▶ the agent in the focused pane
    Running the test suite…
    ⎇ main ↑4
3 ✅ ✻ docs-site
    docs
    ⎇ feature/search-page ✓
```

## Features

- **One row per agent, not per tab.** Two agents split side by side in one tab get two rows.
- **Sorted by what needs you:** 🔴 waiting, ❌ failed, ✅ done, ⏳ working, 💤 idle.
- **Waiting agents stand out** with a gold bar, why they're waiting ("needs approval", "has a question", "needs a login") and the agent's own message. The count shows at the top of the panel and in its pane title.
- **Names from the agent:** Claude Code's `/rename` name (read from the terminal title), falling back to the Rex session name.
- **Git branch and state** for each agent's directory: changed files `●N`, ahead `↑N`, behind `↓N`, or `✓` when clean.
- **Follows you:** `▶` marks the agent in the focused pane, and the selection moves there when focus moves.
- **Jump anywhere:** `1`–`9`, or `↑`/`↓` then `Enter`, focuses that agent's pane, in any session or tab.
- **Go to the waiting agent:** one key jumps straight there when one agent is waiting, or opens a small floating switcher when several are.
- **Cheap:** one collector script listens to Rex events and writes the list to a file; each tab's panel only watches that file.

Agents appear when they report their status with Rex's [program status protocol](https://www.superlogical.com/rex/docs/build/program-status) (OSC 7501). Claude Code and Codex do this out of the box.

## Requirements

- Rex (beta) on macOS or Linux
- Python 3 on the machine running the Rex server
- `git`, for the branch line

## Install

### With Amber

With the [Amber](https://github.com/rawnly/amber) plugin manager, add the plugin to your `init.lua`:

```lua
amber.setup({
  plugins = {
    { "irfn/rex-agents", opts = { panel_key = "cmd+l", waiting_key = "cmd+e" } },
  },
})
```

Then install and reload:

```sh
rex config reload
rex do amber_install
rex config reload
```

### By hand

Clone it anywhere on the machine running the Rex server:

```sh
git clone https://github.com/irfn/rex-agents ~/.local/share/rex/plugins/irfn/rex-agents
```

Load it from `~/.config/rex/init.lua`:

```lua
dofile(os.getenv("HOME") .. "/.local/share/rex/plugins/irfn/rex-agents/lua/rex-agents/init.lua").setup{
  panel_key   = "cmd+l",
  waiting_key = "cmd+e",
}
```

Then run `rex config reload`.

## Usage

| Key | Action | What it does |
| --- | --- | --- |
| `panel_key` | `agents_panel` | Show or hide the panel in every tab. New tabs get one too while it's on. |
| `waiting_key` | `agents_waiting` | Go to the agent waiting on you. With several, pick one from a switcher. |

Both actions are also in the command palette ("Toggle Agents Panel", "Go to Waiting Agent") and can be run with `rex do agents_panel`.

In the panel:

| Key | Does |
| --- | --- |
| `1`–`9` | Jump to that agent |
| `↑` `↓` / `j` `k` | Move the selection |
| `Enter` | Jump to the selected agent |
| `q` | Close this tab's panel |

In the switcher, `Esc` closes it.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `panel_key` | none | Key for `agents_panel`. Without it, no key is bound. |
| `waiting_key` | none | Key for `agents_waiting`. Without it, no key is bound. |
| `panel_columns` | `29` | Width of the panel, in columns. |
| `rex_bin` | found automatically | Path to the `rex` binary, if it isn't found. |

## Recommended Rex settings

- **Turn off Autobalance splits** (command palette: "Disable Autobalance Splits"). With it on, Rex briefly gives the new panel an equal share of the tab before the panel shrinks itself, which looks jumpy.
- **Fade inactive panes** dims the panel's text too, since the panel is rarely focused. The waiting row and selection use solid bars so they stay visible either way. Setting the fade to "surfaces" keeps all text at full brightness.

## How it works

- `lua/rex-agents/init.lua` defines the two actions.
- Turning the panel on starts `lua/rex-agents/collect.lua` with `rex do --all`. It adds a panel to every tab (and to tabs created later), listens for status, title, process and layout events, and writes the agent list to `$XDG_CACHE_HOME/rex-agents/state.json` (default `~/.cache`). It exits once the last panel closes.
- Each panel runs `bin/rex-agents`, which redraws whenever that file changes.

## Limitations

- Only agents on the local Rex server are listed, not ones on remote hosts.
- A panel lives in one tab; Rex has no pane that spans tabs, so each tab gets its own.
- Rex can't exempt a single pane from "Fade inactive panes".

## License

MIT
