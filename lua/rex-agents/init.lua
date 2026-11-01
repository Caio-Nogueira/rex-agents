-- rex-agents: a herdr-style agent list for Rex.
--
-- Adds three actions:
--   agents_panel    Toggle an "agents" pane on the right of every tab, one row
--                   per coding agent across all sessions and remote hosts.
--   agents_waiting  Go to an agent that's waiting on you: straight there when
--                   there's one, otherwise a small floating switcher.
--   remote_session  Open a new session on a remote host (rex hosts) and go there.
--
-- Agents show up when they report their status with the program status
-- protocol (OSC 7501), as Claude Code and Codex do.
--
-- Actions can't reach other hosts themselves (rex.servers() is empty in
-- init.lua), so the parts that do run through the rex CLI.

local M = {}

-- This file is <root>/lua/rex-agents/init.lua; everything else is found from <root>.
local ROOT = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/lua/rex%-agents/init%.lua$")
local PANEL_BIN = ROOT .. "/bin/rex-agents"
local COLLECTOR = ROOT .. "/lua/rex-agents/collect.lua"
local WAITING = ROOT .. "/lua/rex-agents/waiting.lua"

local PANEL_LABEL = "agents"
local PICKER_LABEL = "agents-waiting"
local SHELL = "com.superlogical.terminal.shell"

local function exists(path)
  local f = path and io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- Actions run inside the Rex server, whose PATH may not include rex, so look
-- for the binary where Rex installs it.
local function find_rex(configured)
  local home = os.getenv("HOME") or ""
  local bin_dir = os.getenv("REX_BIN_DIR")
  local candidates = {
    configured or false, -- false, not nil, so ipairs doesn't stop here
    bin_dir and (bin_dir .. "/rex") or false,
    home .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex",
    "/usr/bin/rex", "/usr/local/bin/rex", "/opt/homebrew/bin/rex",
  }
  for _, path in ipairs(candidates) do
    if path and exists(path) then return path end
  end
  return "rex"
end

-- Runs the rex CLI, raising its error message if it fails.
local function run_rex(opts, argv)
  local cmd = { find_rex(opts.rex_bin) }
  for _, a in ipairs(argv) do cmd[#cmd + 1] = a end
  local r, err = rex.exec(cmd, { timeout = 20 })
  if not r then error(err, 0) end
  if not r.ok then error((r.stderr ~= "" and r.stderr or r.stdout):gsub("%s+$", ""), 0) end
  return r.stdout
end

local function rex_json(opts, argv)
  return rex.json.decode(run_rex(opts, argv))
end

function M.setup(opts)
  opts = opts or {}
  local columns = opts.panel_columns or 29

  rex.action{
    name        = "agents_panel",
    title       = "Toggle Agents Panel",
    description = "Show or hide the agent list on the right of every tab.",
    run         = function(ctx, args)
      local panels = {}
      local list, err = rex.call("session.list")
      if err ~= nil then error(err, 0) end
      for _, s in ipairs(list.sessions) do
        local view = rex.session.view{ session_id = s.session_id }
        for _, w in ipairs(view and view.windows or {}) do
          for _, layer in ipairs(w.layers) do
            for _, b in ipairs(layer.blocks) do
              if b.label == PANEL_LABEL then
                panels[#panels + 1] = { session_id = s.session_id, block_id = b.block_id }
              end
            end
          end
        end
      end

      if #panels > 0 then
        -- The collector exits on its own once the last panel is gone.
        for _, p in ipairs(panels) do rex.call("block.close", p) end
        return
      end

      local rex_bin = find_rex(opts.rex_bin)
      local _, err2 = rex.exec.start(
        { rex_bin, "do", "--all", COLLECTOR, "panel=" .. PANEL_BIN, "columns=" .. columns, "rex=" .. rex_bin },
        { detach = true, stdout = false, stderr = false })
      if err2 ~= nil then error(err2, 0) end
    end,
  }

  rex.action{
    name        = "agents_waiting",
    title       = "Go to Waiting Agent",
    description = "Jump to the agent waiting on you, or pick one when several are.",
    run         = function(ctx, args)
      local waiting = rex_json(opts, { "do", WAITING })

      if #waiting == 1 then
        local a = waiting[1]
        if a.server then
          run_rex(opts, { "-S", a.server, "focus", "-s", a.session_id, a.block_id })
        else
          rex.session.focus_block{ session_id = a.session_id, block_id = a.block_id }
        end
        rex.client.queue("session.select", { session_id = a.session_id, window_id = a.window_id })
        return
      end

      local _, err = rex.session.new_layer{
        bounds = { 0.3, 0.2, 0.4, math.min(0.15 + 0.07 * #waiting, 0.6) },
        focus  = true,
        layout = {
          block = {
            flavor  = SHELL,
            label   = PICKER_LABEL,
            options = { command = { PANEL_BIN, "--pick", rex.json.encode(waiting) } },
          },
        },
      }
      if err ~= nil then error(err, 0) end
    end,
  }

  rex.action{
    name        = "remote_session",
    title       = "New Session on Remote Host",
    description = "Open a new session on a remote host and go there.",
    args        = { host = "string?", label = "string?", command = "array?" },
    run         = function(ctx, args)
      args = args or {}
      local host = args.host or opts.remote_host
      if not host then
        local hosts = rex_json(opts, { "hosts", "list", "--json" }).hosts or {}
        host = hosts[1] and hosts[1].host.label
      end
      if not host then error("no remote hosts; add one with: rex hosts add", 0) end
      local argv = { "-S", host, "new", "--json" }
      if args.label then argv[#argv + 1] = args.label end
      if args.command then
        argv[#argv + 1] = "--"
        for _, a in ipairs(args.command) do argv[#argv + 1] = a end
      end
      local session = rex_json(opts, argv)
      -- The app is connected to every host, so it can show the new session.
      rex.client.queue("session.select", { session_id = session.session_id })
      return session
    end,
  }

  if opts.panel_key then rex.bind(opts.panel_key, "agents_panel") end
  if opts.waiting_key then rex.bind(opts.waiting_key, "agents_waiting") end
  if opts.remote_key then rex.bind(opts.remote_key, "remote_session") end
end

return M
