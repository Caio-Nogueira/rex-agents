-- rex-agents collector. The agents_panel action runs one copy with:
--
--   rex do --all collect.lua panel=<path to bin/rex-agents> columns=<width>
--
-- Keeps an "agents" pane on the right edge of every tab, including tabs
-- created later, and writes every pane whose program reports status to
-- STATE as JSON whenever something changes. bin/rex-agents, which runs in
-- each of those panes, only reads that file.
--
-- Agents on remote hosts (rex hosts) are listed too. Their events don't reach
-- this server, so each host is polled every REMOTE_EVERY seconds.
--
-- Exits once the last agents pane is closed.

local TERMINAL = "com.superlogical.terminal"
local PANEL_LABEL = "agents"
local PANEL_COMMAND = rex.args.panel
local PANEL_COLUMNS = tonumber(rex.args.columns) or 29
local STATE_DIR = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/rex-agents"
local STATE = STATE_DIR .. "/state.json"

if not PANEL_COMMAND then
  rex.log("error", "rex-agents: collect.lua needs panel=<path to bin/rex-agents>")
  rex.stop(1)
end

local REMOTE_EVERY = 3  -- seconds between polls of each remote host
local REMOTE_RETRY = 30 -- seconds to wait after a host fails to answer

local dirty = true

-- api is rex for this server, or rex.server(label) for a remote host.
local function method(api, sid, bid, name)
  return api.call("block.method", { session_id = sid, block_id = bid, method = name, args = {} })
end

local attached = {} -- server label ("" here) -> session id -> true

-- Every session, attached first: when the server starts this script (from the
-- agents_panel action) it isn't attached to any, and session calls fail with
-- "stream is not attached to session".
local function sessions(api, server)
  server = server or ""
  attached[server] = attached[server] or {}
  local list = api.call("session.list") or { sessions = {} }
  for _, s in ipairs(list.sessions) do
    if not attached[server][s.session_id] then
      local _, err = api.session.attach{ session_id = s.session_id }
      if err == nil then attached[server][s.session_id] = true end
    end
  end
  return list.sessions
end

local function has_panel(window)
  for _, layer in ipairs(window.layers) do
    for _, b in ipairs(layer.blocks) do
      if b.label == PANEL_LABEL then return true end
    end
  end
  return false
end

local function any_panel()
  for _, s in ipairs(sessions(rex)) do
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
  local size = method(rex, sid, node.block_id, "size")
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
      local _, err = rex.session.new_split{
        session_id = sid,
        anchor_id  = root,
        direction  = "horizontal",
        side       = "after",
        ratio      = panel_ratio(sid, layer.layout),
        focus      = false,
        layout     = {
          block = {
            flavor  = "com.superlogical.terminal.shell",
            label   = PANEL_LABEL,
            options = { command = { PANEL_COMMAND, "--columns", tostring(PANEL_COLUMNS), "--state", STATE } },
          },
        },
      }
      if err ~= nil then rex.log("warn", "agents panel: " .. tostring(err)) end
      return
    end
  end
end

-- Agents by executable name, for panes running one that has no status
-- record: Rex drops a done record once it's been seen, and the agent doesn't
-- report again until its next turn.
local AGENTS = { claude = "claude-code", codex = "codex", opencode = "opencode", pi = "pi" }

local function agent_app(fg)
  for _, n in ipairs({ fg.argv0 or false, fg.name or false, fg.invoked_path or false }) do
    local app = n and AGENTS[n:match("([^/]+)$")]
    if app then return app end
  end
end

-- Without a status record, guess from the title: Claude Code puts ✳ in front
-- of it when idle and a spinner glyph while working.
local function title_state(title)
  local head = (title or ""):match("^(%S+) ")
  if not head or head:find("[%w%p]") then return "idle" end
  return head == "✳" and "idle" or "working"
end

-- Adds the agent rows of one server to rows, and for each agents pane the tab
-- it sits in to panels, so each panel can mark the agent in its own tab's
-- focused pane. server is the remote host's label, nil here.
local function scan(api, server, rows, panels)
  for _, s in ipairs(sessions(api, server)) do
    local view = api.session.view{ session_id = s.session_id }
    for _, w in ipairs(view and view.windows or {}) do
      for _, layer in ipairs(w.layers) do
        for _, b in ipairs(layer.blocks) do
          if b.label == PANEL_LABEL then
            panels[b.block_id] = w.window_id
          elseif b.creator_name == TERMINAL then
            local status = method(api, s.session_id, b.block_id, "program_status")
            local root
            for _, r in ipairs(status and status.records or {}) do
              if r.id == nil then root = r end
            end
            local proc = method(api, s.session_id, b.block_id, "process")
            local fg = proc and proc.foreground or {}
            local app = root and (root.effective_app or root.app or "?") or agent_app(fg)
            if app then
              local title = method(api, s.session_id, b.block_id, "title")
              root = root or { state = app == "claude-code" and title_state(title and title.title) or "idle" }
              rows[#rows + 1] = {
                server     = server,
                session_id = s.session_id,
                window_id  = w.window_id,
                block_id   = b.block_id,
                session    = view.label or s.session_id,
                title      = title and title.title or "",
                state      = root.state or "idle",
                kind       = root.kind or "",
                app        = app,
                msg        = root.msg or "",
                cwd        = fg.cwd or "",
                updated    = root.updated_at or "",
                focused    = w.focused_block_id == b.block_id,
              }
            end
          end
        end
      end
    end
  end
end

local remote_rows = {} -- host label -> its rows from the last poll
local retry_at = {}    -- host label -> when to try a host that failed again

local function poll_remotes()
  local ok, labels = pcall(rex.servers)
  local seen = {}
  for _, label in ipairs(ok and labels or {}) do
    seen[label] = true
    if os.time() >= (retry_at[label] or 0) then
      local rows = {}
      local polled, err = pcall(scan, rex.server(label), label, rows, {})
      if polled then
        retry_at[label] = nil
      else
        rex.log("warn", "rex-agents: " .. label .. ": " .. tostring(err))
        rows, retry_at[label], attached[label] = {}, os.time() + REMOTE_RETRY, nil
      end
      remote_rows[label] = rows
      dirty = true
    end
  end
  for label in pairs(remote_rows) do
    if not seen[label] then remote_rows[label] = nil end
  end
end

local function snapshot()
  local rows, panels = {}, {}
  scan(rex, nil, rows, panels)
  for _, host_rows in pairs(remote_rows) do
    for _, row in ipairs(host_rows) do rows[#rows + 1] = row end
  end
  return rows, panels
end

local last_written

local function write_state(rows, panels)
  local json = rex.json.encode({ agents = rows, panels = panels })
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

rex.on("session_destroyed", function(ctx, ev) attached[""][ev.session_id] = nil end)

rex.on("window_created", function(ctx, ev)
  local view = rex.session.view{ session_id = ctx.session_id }
  for _, w in ipairs(view and view.windows or {}) do
    if w.window_id == ev.window_id then add_panel(ctx.session_id, w) end
  end
end)

rex.on("block_closed", function()
  mark()
  if not any_panel() then rex.stop() end
end)

-- Coalesce bursts of events into at most one write per quarter second.
rex.every(0.25, function()
  if not dirty then return end
  dirty = false
  write_state(snapshot())
end)

-- Safety net for anything the events above miss.
rex.every(15, mark)

rex.every(REMOTE_EVERY, poll_remotes)

rex.exec({ "mkdir", "-p", STATE_DIR })
poll_remotes()
for _, s in ipairs(sessions(rex)) do
  local view = rex.session.view{ session_id = s.session_id }
  for _, w in ipairs(view and view.windows or {}) do
    add_panel(s.session_id, w)
  end
end
