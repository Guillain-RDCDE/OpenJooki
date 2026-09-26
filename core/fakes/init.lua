-- fakes: in-memory stand-ins for every adapter, used by the specs and by the
-- simulator. Same interface as the real adapters, plus inspection helpers.
local fakes = {}

--- Clock: now() advances only when the test says so.
function fakes.clock(start)
  local t = start or 0
  local wall = 1758898800   -- 2026-09-26 15:00:00 UTC
  return {
    now = function() return t end,
    wall = function() return wall + t end,
    advance = function(dt) t = t + dt end,
    set = function(v) t = v end,
  }
end

--- Bus: published messages are recorded; incoming ones are queued by the test.
function fakes.bus()
  local b = { published = {}, incoming = {}, up = true, transitions = {} }
  function b:maintain(_)
    local tr = table.remove(self.transitions, 1)
    if tr then self.up = (tr == "up") end
    return tr
  end
  function b:poll() local out = self.incoming; self.incoming = {}; return out end
  function b:publish(topic, payload)
    if not self.up then return nil, "not connected" end
    self.published[#self.published + 1] = { topic = topic, payload = payload }
    return true
  end
  function b.socket() return nil end
  function b:connected() return self.up end
  function b:close() self.up = false end
  -- helpers
  function b:receive(topic, payload) self.incoming[#self.incoming + 1] = { topic = topic, payload = payload } end
  function b:last(topic)
    for i = #self.published, 1, -1 do if self.published[i].topic == topic then return self.published[i].payload end end
  end
  function b:count(topic)
    local n = 0
    for _, m in ipairs(self.published) do if m.topic == topic then n = n + 1 end end
    return n
  end
  function b:clear() self.published = {} end
  return b
end

--- Files: an in-memory filesystem with the real adapter's semantics.
function fakes.files()
  local store = {}
  local f = { store = store, writes = 0 }
  function f.read(path, min_version)
    local d = store[path]
    if d == nil then return nil, "empty" end
    if min_version and d.version < min_version then return nil, "version too low" end
    return require("kernel.state").deep_copy(d.doc), d.version
  end
  function f.write(path, t, version)
    f.writes = f.writes + 1
    store[path] = { doc = require("kernel.state").deep_copy(t), version = version or 1 }
    return true
  end
  function f.exists(path) return store[path] ~= nil end
  function f.remove(path) store[path] = nil return true end
  function f.read_text(path) return store[path] and store[path].text end
  function f.write_text(path, text) store[path] = { text = text } return true end
  function f.stat(path)
    local d = store[path]
    if not d then return false, nil end
    return true, d.size or (d.text and #d.text) or 0
  end
  function f.rename(from, to)
    if not store[from] then return nil, "no such file" end
    store[to] = store[from]; store[from] = nil
    return true, nil, f.stat(to) and select(2, f.stat(to))
  end
  f.flags = {}
  function f.flag(name, set) f.flags[name] = set or nil return true end
  return f
end

--- Host: records the volume and the readiness.
function fakes.host()
  local h = { volumes = {}, is_terminating = false, ready_called = false, syslog_lines = {} }
  function h.set_volume(v) h.volumes[#h.volumes + 1] = v return true, 0 end
  function h.syslog(sev, line) h.syslog_lines[#h.syslog_lines + 1] = { sev, line } end
  function h.terminating() return h.is_terminating end
  function h.ready() h.ready_called = true end
  function h.available() return false end
  function h.last_volume() return h.volumes[#h.volumes] end
  return h
end

--- Shell: records every action; results can be scripted per action name.
function fakes.shell()
  local s = { calls = {}, results = {}, count = 0 }
  local actions = require("adapters.shell").ACTIONS
  function s.run(name, args)
    if not actions[name] then return nil, "unknown action: " .. tostring(name) end
    s.count = s.count + 1
    s.calls[#s.calls + 1] = { name = name, args = args }
    local r = s.results[name]
    if type(r) == "function" then return r(args) end
    if r then return r[1], r[2] end
    return "", 0
  end
  return s
end

return fakes
