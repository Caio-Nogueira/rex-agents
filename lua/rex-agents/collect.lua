-- rex-agents collector. The agents_panel action runs one copy with:
--
--   rex do --all collect.lua panel=<path to bin/rex-agents> columns=<width> rex=<path to rex>
--     [orbit=<rex-orbit command as JSON> orbit_height=<share of the panel's height>]
--
-- Keeps an "agents" pane on the right edge of every tab, including tabs
-- created later, and writes every pane whose program reports status to
-- STATE as JSON whenever something changes. bin/rex-agents, which runs in
-- each of those panes, only reads that file.
--
-- Agents on remote hosts (rex hosts) are listed too, along with each host's
-- sessions. Their events don't reach this server, so every REMOTE_EVERY
-- seconds remote.lua is run to poll them, on a fresh connection each time.
--
-- Exits once the last agents pane is closed.

local DIR = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/")
local scan = dofile(DIR .. "/scan.lua")
local REMOTE = DIR .. "/remote.lua"

local PANEL_LABEL = scan.PANEL_LABEL
local PANEL_COMMAND = rex.args.panel
local PANEL_COLUMNS = tonumber(rex.args.columns) or 29
local REX = rex.args.rex or "rex"
local ORBIT_LABEL = "agents-orbit"
-- rex do decodes a JSON value given as key=value, so orbit arrives as a table.
local ORBIT_COMMAND = rex.args.orbit
if type(ORBIT_COMMAND) == "string" then ORBIT_COMMAND = rex.json.decode(ORBIT_COMMAND) end
local ORBIT_HEIGHT = math.min(math.max(tonumber(rex.args.orbit_height) or 0.3, 0.1), 0.9)
local STATE_DIR = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/rex-agents"
local STATE = STATE_DIR .. "/state.json"

if not PANEL_COMMAND then
  rex.log("error", "rex-agents: collect.lua needs panel=<path to bin/rex-agents>")
  rex.stop(1)
end

-- One collector at a time: each one claims OWNER when it starts, and an
-- older one that finds the claim taken exits. Otherwise every copy adds a
-- panel to each new tab, and they take turns writing STATE.
local OWNER = STATE_DIR .. "/collector.owner"
local TOKEN = string.format("%d-%s-%.6f", os.time(), tostring({}):match("0x%x+") or "", os.clock())

local function owner()
  local f = io.open(OWNER, "r")
  if not f then return nil end
  local token = f:read("*l")
  f:close()
  return token
end

local REMOTE_EVERY = 3    -- seconds between polls of the remote hosts
local REMOTE_TIMEOUT = 8  -- seconds a poll may take before it's stopped
local REMOTE_RETRY = 30   -- seconds to leave out a host that failed to answer

local dirty = true

local function has_block(window, label)
  for _, layer in ipairs(window.layers) do
    for _, b in ipairs(layer.blocks) do
      if b.label == label then return b end
    end
  end
end

local function has_panel(window) return has_block(window, PANEL_LABEL) ~= nil end

local function any_panel()
  for _, s in ipairs(scan.sessions(rex)) do
    local view = rex.session.view{ session_id = s.session_id }
    for _, w in ipairs(view and view.windows or {}) do
      if has_panel(w) then return true end
    end
  end
  return false
end

-- The share of a tab's width that leaves PANEL_COLUMNS for the panel, worked
-- out from any pane's size in columns and its share of the tab.
local function panel_ratio(sid, layout)
  local node = layout
  while node.split do node = node.split.before end
  local size = scan.method(rex, sid, node.block_id, "size")
  local share = node.rect and node.rect[3] or 0
  if not (size and size.columns and share > 0) then return 0.85 end
  local total = size.columns / share
  return math.min(math.max(1 - PANEL_COLUMNS / total, 0.5), 0.95)
end

local function add_panel(sid, window)
  if has_panel(window) then return end
  for _, layer in ipairs(window.layers) do
    if layer.kind == "tiled" and layer.layout then
      -- Anchor on the layout's root so the panel spans the full right edge.
      -- With the app's "balance splits on creation" on, the app overrides this
      -- ratio, and rex-agents corrects the width once it starts.
      local root = layer.layout.split and layer.layout.split.split_id or layer.layout.block_id
      local layout = {
        block = {
          flavor  = "com.superlogical.terminal.shell",
          label   = PANEL_LABEL,
          options = { command = { PANEL_COMMAND, "--columns", tostring(PANEL_COLUMNS), "--state", STATE } },
        },
      }
      if ORBIT_COMMAND then
        -- rex-orbit's bots under the list, in the same column.
        layout = {
          split = {
            direction = "vertical",
            ratio     = 1 - ORBIT_HEIGHT,
            before    = layout,
            after     = {
              block = {
                flavor  = "com.superlogical.terminal.shell",
                label   = ORBIT_LABEL,
                options = { command = ORBIT_COMMAND },
              },
            },
          },
        }
      end
      local _, err = rex.session.new_split{
        session_id = sid,
        anchor_id  = root,
        direction  = "horizontal",
        side       = "after",
        ratio      = panel_ratio(sid, layer.layout),
        focus      = false,
        layout     = layout,
      }
      if err ~= nil then rex.log("warn", "agents panel: " .. tostring(err)) end
      return
    end
  end
end

local remote = {}   -- host label -> { reachable, agents, sessions } from the last poll
local retry_at = {} -- host label -> when to poll a host that failed again

local function poll_remotes()
  local skip = {}
  for label, at in pairs(retry_at) do
    if os.time() < at then skip[#skip + 1] = label else retry_at[label] = nil end
  end
  local r = rex.exec({ REX, "do", REMOTE, "skip=" .. table.concat(skip, ",") }, { timeout = REMOTE_TIMEOUT })
  if not (r and r.ok) then
    rex.log("warn", "rex-agents: polling remote hosts failed: " .. tostring(r and (r.timed_out and "timed out" or r.stderr)))
    return
  end
  local ok, hosts = pcall(rex.json.decode, r.stdout)
  if not ok then return end
  local fresh = {}
  for _, label in ipairs(skip) do fresh[label] = remote[label] end -- keep what we last knew
  for _, host in ipairs(hosts) do
    fresh[host.label] = host
    if not host.reachable then
      rex.log("warn", "rex-agents: " .. host.label .. ": " .. tostring(host.error))
      retry_at[host.label] = os.time() + REMOTE_RETRY
    end
  end
  remote = fresh
  dirty = true
end

local function snapshot()
  local rows, panels, hosts = {}, {}, {}
  scan.scan(rex, nil, rows, panels)
  for label, host in pairs(remote) do
    for _, row in ipairs(host.agents or {}) do rows[#rows + 1] = row end
    hosts[#hosts + 1] = { label = label, reachable = host.reachable, sessions = host.sessions or {} }
  end
  table.sort(hosts, function(a, b) return a.label < b.label end)
  return rows, panels, hosts
end

local last_written

local function write_state(rows, panels, hosts)
  local json = rex.json.encode({ agents = rows, panels = panels, hosts = hosts })
  if json == last_written then return end -- remote polls mostly change nothing
  local tmp = STATE .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return end
  f:write(json)
  f:close()
  last_written = json
  os.rename(tmp, STATE) -- atomic, so readers never see half a file
end

local function mark() dirty = true end

for _, name in ipairs{
  "terminal.program_status_changed", "terminal.program_status_removed",
  "terminal.process_changed", "terminal.title_changed", "session_label_changed",
  "session_created", "session_destroyed",
  "session_view_changed", -- also fires when focus moves to another pane
} do
  rex.on(name, mark)
end

rex.on("session_destroyed", function(ctx, ev) scan.forget(nil, ev.session_id) end)

rex.on("window_created", function(ctx, ev)
  if owner() ~= TOKEN then return end -- a newer collector adds the panel
  local view = rex.session.view{ session_id = ctx.session_id }
  for _, w in ipairs(view and view.windows or {}) do
    if w.window_id == ev.window_id then add_panel(ctx.session_id, w) end
  end
end)

-- An orbit pane goes with its tab's panel, as when q closes the panel.
local function close_lone_orbits()
  for _, s in ipairs(scan.sessions(rex)) do
    local view = rex.session.view{ session_id = s.session_id }
    for _, w in ipairs(view and view.windows or {}) do
      local orbit = has_block(w, ORBIT_LABEL)
      if orbit and not has_panel(w) then
        rex.call("block.close", { session_id = s.session_id, block_id = orbit.block_id })
      end
    end
  end
end

rex.on("block_closed", function()
  mark()
  close_lone_orbits()
  if not any_panel() then rex.stop() end
end)

-- Coalesce bursts of events into at most one write per quarter second.
rex.every(0.25, function()
  if owner() ~= TOKEN then
    rex.log("info", "rex-agents: a newer collector took over")
    rex.stop()
    return
  end
  if not dirty then return end
  dirty = false
  write_state(snapshot())
end)

-- Safety net for anything the events above miss.
rex.every(15, mark)

rex.every(REMOTE_EVERY, poll_remotes)

rex.exec({ "mkdir", "-p", STATE_DIR })
do
  local f = assert(io.open(OWNER, "w"))
  f:write(TOKEN, "\n")
  f:close()
end
poll_remotes()
for _, s in ipairs(scan.sessions(rex)) do
  local view = rex.session.view{ session_id = s.session_id }
  for _, w in ipairs(view and view.windows or {}) do
    add_panel(s.session_id, w)
  end
end
