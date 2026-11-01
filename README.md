# rex-agents

A herdr-style agent list for [Rex](https://www.superlogical.com/rex). It puts a narrow panel on the right of every tab with one row per coding agent across all your sessions and remote hosts, and adds a key that jumps to whichever agent is waiting on you.

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

── ⇄ studio ──────────────   ← a remote host
4 ⏳ ✻ data-pipeline
    etl
5 ▫ data-pipeline            ← its sessions
6 ▫ scratch

── usage ─────────────────
✻ 5h ▰▰▰▰▱▱▱▱▱▱  42% 2h      ← plan limits, with time to reset
  7d ▰▰▱▱▱▱▱▱▱▱  18% 4d
  today 12.4M tok
```

## Features

- **One row per agent, not per tab.** Two agents split side by side in one tab get two rows.
- **Sorted by what needs you:** 🔴 waiting, ❌ failed, ✅ done, ⏳ working, 💤 idle.
- **Waiting agents stand out** with a gold bar, why they're waiting ("needs approval", "has a question", "needs a login") and the agent's own message. The count shows at the top of the panel and in its pane title.
- **Names from the agent:** Claude Code's `/rename` name (read from the terminal title), falling back to the Rex session name.
- **Git branch and state** for each agent's directory: changed files `●N`, ahead `↑N`, behind `↓N`, or `✓` when clean.
- **Follows you:** `▶` marks the agent in the focused pane, and the selection moves there when focus moves.
- **Jump anywhere:** `1`–`9`, or `↑`/`↓` then `Enter`, focuses that agent's pane, in any session or tab.
- **Remote hosts too:** each of your other Rex servers (`rex hosts`) gets its own section below a divider, with its agents and its sessions, or "unreachable" when it doesn't answer. Jumping to a row opens that host's session. Another key opens a new session on a remote host.
- **Go to the waiting agent:** one key jumps straight there when one agent is waiting, or opens a small floating switcher when several are.
- **Usage at the bottom:** plan limits (5-hour and weekly) as bars that turn yellow then red, and today's tokens, for Claude Code and Codex. Read from the files those tools keep, like [ai-usage](https://github.com/trishtzy/ai-usage), with no API keys.
- **Cheap:** one collector script listens to Rex events and writes the list to a file; each tab's panel only watches that file.

Agents appear when they report their status with Rex's [program status protocol](https://www.superlogical.com/rex/docs/build/program-status) (OSC 7501). Claude Code and Codex do this out of the box. A pane that runs `claude`, `codex`, `opencode` or `pi` but reports no status is still listed: Claude Code's state is read from its title (`✳` idle, a spinner while working), others show as idle. Such agents can't show as waiting.

## Requirements

- Rex (beta) on macOS or Linux
- Python 3 on the machine running the Rex server
- `git`, for the branch line
- `jq`, only for saving Claude Code's plan limits (see [Usage section](#usage-section))

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
| `remote_key` | `remote_session` | Open a new session on a remote host and go there. |

The actions are also in the command palette ("Toggle Agents Panel", "Go to Waiting Agent", "New Session on Remote Host") and can be run with `rex do agents_panel`.

`remote_session` takes optional `host`, `label` and `command` arguments, so you can bind a key per host or one that starts an agent there:

```lua
rex.bind("ctrl+cmd+c", "remote_session", { host = "studio", command = { "claude" } })
```

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
| `remote_key` | none | Key for `remote_session`. Without it, no key is bound. |
| `remote_host` | first host | The host `remote_session` uses when not given one. |
| `panel_columns` | `29` | Width of the panel, in columns. |
| `rex_bin` | found automatically | Path to the `rex` binary, if it isn't found. |

## Usage section

Today's tokens need no setup: they're read incrementally from Claude Code's logs (`~/.claude/projects`) and Codex's sessions (`~/.codex/sessions`). Codex's plan limits come from its session files too.

Claude Code hands its plan limits only to its status line command, so for the Claude bars, save them from there. Add this at the start of your `statusLine` command in `~/.claude/settings.json`, after it reads its input into `$input`:

```sh
d="${XDG_CACHE_HOME:-$HOME/.cache}/rex-agents"; mkdir -p "$d"; printf '%s' "$input" | jq -ce 'select(.rate_limits) | {rate_limits}' > "$d/claude-limits.json.tmp" && mv "$d/claude-limits.json.tmp" "$d/claude-limits.json";
```

If you have no status line yet, this one does only that:

```json
"statusLine": {
  "type": "command",
  "command": "input=$(cat); d=\"${XDG_CACHE_HOME:-$HOME/.cache}/rex-agents\"; mkdir -p \"$d\"; printf '%s' \"$input\" | jq -ce 'select(.rate_limits) | {rate_limits}' > \"$d/claude-limits.json.tmp\" && mv \"$d/claude-limits.json.tmp\" \"$d/claude-limits.json\""
}
```

Claude Code sends plan limits on subscription plans; a window shows once Claude has reported it. Until then the panel says "plan limits: see README".

## Recommended Rex settings

- **Turn off Autobalance splits** (command palette: "Disable Autobalance Splits"). With it on, Rex briefly gives the new panel an equal share of the tab before the panel shrinks itself, which looks jumpy.
- **Fade inactive panes** dims the panel's text too, since the panel is rarely focused. The waiting row and selection use solid bars so they stay visible either way. Setting the fade to "surfaces" keeps all text at full brightness.

## How it works

- `lua/rex-agents/init.lua` defines the two actions.
- Turning the panel on starts `lua/rex-agents/collect.lua` with `rex do --all`. It adds a panel to every tab (and to tabs created later), listens for status, title, process and layout events, and writes the agent list to `$XDG_CACHE_HOME/rex-agents/state.json` (default `~/.cache`). It exits once the last panel closes.
- Remote hosts send no events to this server, so the collector polls each one every 3 seconds, and waits 30 seconds before trying a host that didn't answer. Lua actions in `init.lua` can't reach other hosts, so `agents_waiting` and `remote_session` do that part through the `rex` CLI (`lua/rex-agents/waiting.lua`).
- Each panel runs `bin/rex-agents`, which redraws whenever that file changes. Every 30 seconds one panel (whichever takes the lock) rereads usage into `usage.json` beside it.

## Limitations

- Panels are added to tabs on this machine's server only. Remote agents show in them, but a remote session's tabs get no panel.
- A remote agent's row has no git branch line, since git runs on this machine.
- A panel lives in one tab; Rex has no pane that spans tabs, so each tab gets its own.
- Rex can't exempt a single pane from "Fade inactive panes".

## License

MIT
