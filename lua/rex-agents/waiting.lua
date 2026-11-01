-- rex-agents: prints the agents waiting on you, on this server and every
-- remote host that answers, as a JSON list. The agents_waiting action runs it
-- with "rex do": only scripts the CLI runs can reach other hosts.

local PANEL_LABEL = "agents"
local TERMINAL = "com.superlogical.terminal"

local function method(api, sid, bid, name)
  return api.call("block.method", { session_id = sid, block_id = bid, method = name, args = {} })
end

local waiting = {}

-- server is the remote host's label, nil here; api is rex or rex.server(label).
local function scan(api, server)
  local list, err = api.call("session.list")
  if err ~= nil then error(err, 0) end
  for _, s in ipairs(list.sessions) do
    api.session.attach{ session_id = s.session_id }
    local view = api.session.view{ session_id = s.session_id }
    for _, w in ipairs(view and view.windows or {}) do
      for _, layer in ipairs(w.layers) do
        for _, b in ipairs(layer.blocks) do
          if b.label ~= PANEL_LABEL and b.creator_name == TERMINAL then
            local status = method(api, s.session_id, b.block_id, "program_status")
            for _, r in ipairs(status and status.records or {}) do
              if r.id == nil and r.state == "blocked" then
                local title = method(api, s.session_id, b.block_id, "title")
                waiting[#waiting + 1] = {
                  server     = server,
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
          end
        end
      end
    end
  end
end

scan(rex, nil)
for _, label in ipairs(rex.servers()) do
  local ok, err = pcall(scan, rex.server(label), label)
  if not ok then io.stderr:write("rex-agents: " .. label .. ": " .. tostring(err) .. "\n") end
end
io.write(rex.json.encode(waiting))
