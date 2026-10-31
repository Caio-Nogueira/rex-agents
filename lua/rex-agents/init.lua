-- rex-agents: a herdr-style agent list for Rex.
--
-- Adds two actions:
--   agents_panel    Toggle an "agents" pane on the right of every tab, one row
--                   per coding agent across all sessions.
--   agents_waiting  Go to an agent that's waiting on you: straight there when
--                   there's one, otherwise a small floating switcher.
--
-- Agents show up when they report their status with the program status
-- protocol (OSC 7501), as Claude Code and Codex do.

local M = {}

-- This file is <root>/lua/rex-agents/init.lua; everything else is found from <root>.
local ROOT = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/lua/rex%-agents/init%.lua$")
local PANEL_BIN = ROOT .. "/bin/rex-agents"
local COLLECTOR = ROOT .. "/lua/rex-agents/collect.lua"

local PANEL_LABEL = "agents"
local PICKER_LABEL = "agents-waiting"
local TERMINAL = "com.superlogical.terminal"
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

-- Every terminal block in every session, with its session, view and window.
local function each_block(fn)
  local list, err = rex.call("session.list")
  if err ~= nil then error(err, 0) end
  for _, s in ipairs(list.sessions) do
    local view = rex.session.view{ session_id = s.session_id }
    for _, w in ipairs(view and view.windows or {}) do
      for _, layer in ipairs(w.layers) do
        for _, b in ipairs(layer.blocks) do
          fn(s, view, w, b)
        end
      end
    end
  end
end

local function method(sid, bid, name)
  return rex.call("block.method", { session_id = sid, block_id = bid, method = name, args = {} })
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
      each_block(function(s, _, _, b)
        if b.label == PANEL_LABEL then
          panels[#panels + 1] = { session_id = s.session_id, block_id = b.block_id }
        end
      end)

      if #panels > 0 then
        -- The collector exits on its own once the last panel is gone.
        for _, p in ipairs(panels) do rex.call("block.close", p) end
        return
      end

      local _, err = rex.exec.start(
        { find_rex(opts.rex_bin), "do", "--all", COLLECTOR, "panel=" .. PANEL_BIN, "columns=" .. columns },
        { detach = true, stdout = false, stderr = false })
      if err ~= nil then error(err, 0) end
    end,
  }

  rex.action{
    name        = "agents_waiting",
    title       = "Go to Waiting Agent",
    description = "Jump to the agent waiting on you, or pick one when several are.",
    run         = function(ctx, args)
      local waiting = {}
      each_block(function(s, view, w, b)
        if b.label == PANEL_LABEL or b.creator_name ~= TERMINAL then return end
        local status = method(s.session_id, b.block_id, "program_status")
        for _, r in ipairs(status and status.records or {}) do
          if r.id == nil and r.state == "blocked" then
            local title = method(s.session_id, b.block_id, "title")
            waiting[#waiting + 1] = {
              session_id = s.session_id,
              window_id  = w.window_id,
              block_id   = b.block_id,
              session    = view.label or s.session_id,
              title      = title and title.title or "",
              app        = r.effective_app or r.app or "?",
              kind       = r.kind or "",
              msg        = r.msg or "",
              state      = "blocked",
            }
          end
        end
      end)

      if #waiting == 1 then
        local a = waiting[1]
        rex.session.focus_block{ session_id = a.session_id, block_id = a.block_id }
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

  if opts.panel_key then rex.bind(opts.panel_key, "agents_panel") end
  if opts.waiting_key then rex.bind(opts.waiting_key, "agents_waiting") end
end

return M
