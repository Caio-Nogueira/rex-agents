-- rex-agents: prints the agents and sessions of every remote host (rex hosts)
-- as JSON. collect.lua runs it with "rex do" on each poll, so every poll gets
-- a fresh connection: a long-lived one doesn't recover after the machine
-- sleeps or the network changes.
--
--   rex do remote.lua [skip=<label>,<label>]
--
-- Hosts in skip are left out, for hosts that failed recently.

local DIR = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*)/")
local scan = dofile(DIR .. "/scan.lua")

local skip = {}
for label in (rex.args.skip or ""):gmatch("[^,]+") do skip[label] = true end

local hosts = {}
for _, label in ipairs(rex.servers()) do
  if not skip[label] then
    local rows, sessions = {}, {}
    local ok, err = pcall(scan.scan, rex.server(label), label, rows, {}, sessions, true)
    hosts[#hosts + 1] = {
      label     = label,
      reachable = ok,
      error     = not ok and tostring(err) or nil,
      agents    = ok and rows or {},
      sessions  = ok and sessions or {},
    }
  end
end
io.write(rex.json.encode(hosts))
