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
- **Jump anywhere:** `1`–`9`, or `↑`/`↓` then `Enter`, focuses that agent's pane, in any session, tab or host.
- **Remote hosts too:** each of your other Rex servers (`rex hosts`) gets its own section below a divider, with its agents and its sessions, or "unreachable" when it doesn't answer. Jumping to a row opens that host's session. Another key opens a new session on a remote host. See [Remote hosts](#remote-hosts).
- **Go to the waiting agent:** one key jumps straight there when one agent is waiting, or opens a small floating switcher when several are.
- **Usage at the bottom:** plan limits (5-hour and weekly) as bars that turn yellow then red, and today's tokens, for Claude Code and Codex. Read from the files those tools keep, like [ai-usage](https://github.com/trishtzy/ai-usage), with no API keys.
- **Cheap:** one collector script listens to Rex events and writes the list to a file; each tab's panel only watches that file.

Agents appear when they report their status with Rex's [program status protocol](https://www.superlogical.com/rex/docs/build/program-status) (OSC 7501). Claude Code and Codex do this out of the box. A pane that runs `claude`, `codex`, `opencode` or `pi` but reports no status is still listed: Claude Code's state is read from its title (`✳` idle, a spinner while working), others show as idle. Such agents can't show as waiting.

## Requirements

- Rex (beta) on macOS or Linux
- Python 3 on the machine running the Rex server (on each host, for panels there)
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

`remote_session` takes optional `host`, `label` and `command` arguments, so you can bind a key per host or one that starts an agent there. See [Remote sessions](#remote-sessions) for more.

```lua
rex.bind("ctrl+cmd+c", "remote_session", { host = "studio", command = { "claude" } })
```

From a shell, the same actions:

```sh
rex do agents_panel                      # toggle the panel in every tab
rex do agents_waiting                    # go to the waiting agent
rex do remote_session host=studio        # new session on studio
```

In the panel:

| Key | Does |
| --- | --- |
| `1`–`9` | Jump to that row: an agent's pane, or a remote session |
| `↑` `↓` / `j` `k` | Move the selection |
| `Enter` | Jump to the selected row |
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
| `orbit` | none | Path to a clone of [rex-orbit](https://github.com/benhid/rex-orbit), or a command as a list, to show its bots under the list. See [Orbit](#orbit). |
| `orbit_height` | `0.3` | The orbit pane's share of the column's height. |
| `orbit_fps` | `12` | rex-orbit's frame rate, when `orbit` is a path. |
| `node_bin` | found automatically | Path to `node`, for `orbit`. |

## Orbit

[rex-orbit](https://github.com/benhid/rex-orbit) by benhid draws each Claude Code session as a small pixel bot that hops and shows `!` when it needs you. With the `orbit` option, every agents panel gets a rex-orbit pane below it, in the same column. It needs Node.js 20 or newer.

```sh
git clone https://github.com/benhid/rex-orbit ~/.local/share/rex/plugins/benhid/rex-orbit
```

```lua
agents.setup{
  panel_key = "cmd+l",
  orbit     = os.getenv("HOME") .. "/.local/share/rex/plugins/benhid/rex-orbit",
}
```

Or give the whole command, to pass rex-orbit's own flags:

```lua
orbit = { "/opt/homebrew/bin/node", os.getenv("HOME") .. "/.local/share/rex/plugins/benhid/rex-orbit/bin/rex-orbit.mjs", "--fps", "8", "--no-dino" },
```

The orbit pane opens and closes with its tab's panel, including when `q` closes the panel. Each tab runs its own copy, which takes about 3% of a core and 120 MB at 12 frames a second, so lower `orbit_fps` or leave out the dinosaur (`--no-dino`) with many tabs. rex-orbit shows this machine's Claude Code sessions only.

## Remote hosts

The panel lists every host in `rex hosts` on the machine it runs on, each in its own section below a `⇄` divider. To add one:

```sh
rex hosts add studio https://studio-rex.example.ts.net
rex hosts check
```

The panel picks it up within a few seconds. Remove it with `rex hosts remove studio`.

A host's section shows its agents first, then every session on it:

```
── ⇄ studio ──────────────
4 🔴 ✻ data-pipeline         ← an agent on studio, waiting
    needs approval: Bash: d…
5 ⏳ ✻ etl-backfill
    Loading partitions…
6 ▫ data-pipeline            ← studio's sessions, by name
7 ▫ etl-backfill
8 ▫ scratch

── ⇄ mini ────────────────
  unreachable                ← didn't answer; tried again in 30s

── ⇄ build ───────────────
  no sessions
```

### Remote sessions

**Jump to one.** Press its number, or select it and press `Enter`. The app switches to that session on the host, in the tab it last showed. Jumping to a remote agent's row goes to its pane.

**Open a new one** with `remote_key` (the `remote_session` action). It creates a session on the host and switches to it. With no arguments it uses `remote_host`, or the first host in `rex hosts`.

```lua
local agents = dofile(os.getenv("HOME") .. "/.local/share/rex/plugins/irfn/rex-agents/lua/rex-agents/init.lua")
agents.setup{
  panel_key   = "cmd+l",
  waiting_key = "cmd+e",
  remote_key  = "ctrl+cmd+n",  -- new session on remote_host
  remote_host = "studio",
}

-- A key per host
rex.bind("ctrl+cmd+m", "remote_session", { host = "mini" })

-- Start an agent on a host, in a session with a name
rex.bind("ctrl+cmd+c", "remote_session", { host = "studio", label = "review", command = { "claude" } })
rex.bind("ctrl+cmd+x", "remote_session", { host = "studio", command = { "codex" } })
```

| Argument | Meaning |
| --- | --- |
| `host` | The host's label in `rex hosts`. Default: `remote_host`, else the first host. |
| `label` | Name for the new session. Default: Rex picks one. |
| `command` | Program to run in its first pane, as a list. Default: the host's shell. |

The new session shows up in the panel on the next poll, within 3 seconds.

**Keys inside a remote session.** Rex runs a key's action on your machine even while the app shows a remote session, so the actions look up which host owns the session and act there:

- `panel_key` toggles that host's own panels (see below), not yours.
- `waiting_key` goes to the first waiting agent across all hosts, since the switcher is a pane on your machine and can't be shown in a remote tab.
- `remote_key` works the same anywhere.

### Panels in a remote session's tabs

A pane runs on the server that owns its tab, so a panel in a remote session's tabs needs rex-agents installed on that host too. Install it there [by hand](#by-hand), then reload and open the panel on that machine (Rex only reloads the configuration from the machine itself):

```sh
# on the host
git clone https://github.com/irfn/rex-agents ~/.local/share/rex/plugins/irfn/rex-agents
# add the dofile(...).setup{...} line to ~/.config/rex/init.lua, then:
rex config reload
rex do agents_panel
```

Afterwards `panel_key` in that host's sessions works from your machine. That host's panel lists its own agents, and another machine's only if that machine is in its `rex hosts`.

To update it later, `git -C ~/.local/share/rex/plugins/irfn/rex-agents pull`, then `rex config reload` on the host.

### Example: a laptop and a Mac mini over Tailscale

Each machine's Rex server has to be reachable from the other for each to list the other.

1. In Rex for Mac on both, turn on Tailscale serving in Settings. Each server gets its own tailnet name, such as `laptop-rex.<tailnet>.ts.net` and `mini-rex.<tailnet>.ts.net`.
2. If the machines are on different tailnets, a shared machine is reachable only from the tailnet it's shared into. Share each machine's Rex node with the other's tailnet, or put both on one.
3. Add each to the other's hosts:

   ```sh
   # on the laptop
   rex hosts add mini https://mini-rex.<tailnet>.ts.net
   # on the mini
   rex hosts add laptop https://laptop-rex.<tailnet>.ts.net
   rex hosts check
   ```

   If the first connection times out during the TLS handshake, try again once the certificate has been issued.
4. Install rex-agents on the mini as above, and open the panel on both.

Now the laptop's panel shows the mini's agents and sessions under `⇄ mini`, `ctrl+cmd+n` opens a session on the mini, and `cmd+l` in a mini session toggles the mini's panels.

### Notes

**Jumping from a host's panel.** Rex doesn't say which app a key came from, and a host can have several apps connected (each machine's own, say). So a jump switches every app showing the panel's session, all at once.

**Width.** The panel's width is a share of its tab, and apps with different window sizes can show the same tab. The panel resizes itself to `panel_columns` whenever the app driving the tab's size changes, such as when you click into a tab another app was showing.

**Sleep and network changes.** Each poll of a host uses a fresh connection, so a host comes back by itself after your machine wakes or changes networks.

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

- `lua/rex-agents/init.lua` defines the three actions.
- Turning the panel on starts `lua/rex-agents/collect.lua` with `rex do --all`. It adds a panel to every tab (and to tabs created later), listens for status, title, process and layout events, and writes the agent list to `$XDG_CACHE_HOME/rex-agents/state.json` (default `~/.cache`). It exits once the last panel closes.
- Remote hosts send no events to this server, so every 3 seconds the collector runs `lua/rex-agents/remote.lua` with `rex do` to poll them. Each poll gets a fresh connection, so the list recovers by itself after the machine sleeps or the network changes. A host that doesn't answer shows as unreachable and is tried again after 30 seconds. `lua/rex-agents/scan.lua` holds the scanning code both share.
- Lua actions in `init.lua` can't reach other hosts, so `agents_waiting` and `remote_session` do that part through the `rex` CLI (`lua/rex-agents/waiting.lua`).
- Each panel runs `bin/rex-agents`, which redraws whenever that file changes. Every 30 seconds one panel (whichever takes the lock) rereads usage into `usage.json` beside it.

## Limitations

- Panels are added to tabs on this machine's server only. For panels in a remote session's tabs, install rex-agents on that host too.
- A remote agent's row has no git branch line, since git runs on this machine.
- Remote rows update every 3 seconds instead of instantly. While a host is slow to answer, local updates wait too, for up to 8 seconds; then the host is skipped for 30.
- A panel lives in one tab; Rex has no pane that spans tabs, so each tab gets its own.
- Rex can't exempt a single pane from "Fade inactive panes".

## License

MIT
