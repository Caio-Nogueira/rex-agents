-- rex-agents: finds the agents and sessions on one Rex server. Shared by
-- collect.lua (this server) and remote.lua (remote hosts).

local M = {}

local TERMINAL = "com.superlogical.terminal"
M.PANEL_LABEL = "agents"

-- api is rex for this server, or rex.server(label) for a remote host.
function M.method(api, sid, bid, name)
  return api.call("block.method", { session_id = sid, block_id = bid, method = name, args = {} })
end

local attached = {} -- server label ("" here) -> session id -> true

-- Every session, attached first: a script isn't attached to any, and session
-- calls fail with "stream is not attached to session". With strict, a failed
-- list raises, so an unreachable host isn't mistaken for one with no sessions.
function M.sessions(api, server, strict)
  server = server or ""
  attached[server] = attached[server] or {}
  local list, err = api.call("session.list")
  if err ~= nil then
    if strict then error(err, 0) end
    return {}
  end
  for _, s in ipairs(list.sessions) do
    if not attached[server][s.session_id] then
      local _, attach_err = api.session.attach{ session_id = s.session_id }
      if attach_err == nil then attached[server][s.session_id] = true end
    end
  end
  return list.sessions
end

function M.forget(server, session_id)
  if attached[server or ""] then attached[server or ""][session_id] = nil end
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
-- focused pane. server is the remote host's label, nil here. With session_rows,
-- also adds a row per session there. strict is passed to M.sessions.
function M.scan(api, server, rows, panels, session_rows, strict)
  for _, s in ipairs(M.sessions(api, server, strict)) do
    local view = api.session.view{ session_id = s.session_id }
    if not view then M.forget(server, s.session_id) end -- attach again next time
    if session_rows and view then
      session_rows[#session_rows + 1] = {
        server     = server,
        session_id = s.session_id,
        window_id  = view.active_window_id,
        session    = view.label or s.label or s.session_id,
        windows    = #(view.windows or {}),
      }
    end
    for _, w in ipairs(view and view.windows or {}) do
      for _, layer in ipairs(w.layers) do
        for _, b in ipairs(layer.blocks) do
          if b.label == M.PANEL_LABEL then
            panels[b.block_id] = w.window_id
          elseif b.creator_name == TERMINAL then
            local status = M.method(api, s.session_id, b.block_id, "program_status")
            local root
            for _, r in ipairs(status and status.records or {}) do
              if r.id == nil then root = r end
            end
            local proc = M.method(api, s.session_id, b.block_id, "process")
            local fg = proc and proc.foreground or {}
            local app = root and (root.effective_app or root.app or "?") or agent_app(fg)
            if app then
              local title = M.method(api, s.session_id, b.block_id, "title")
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

return M
