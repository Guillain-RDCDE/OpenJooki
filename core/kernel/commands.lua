-- kernel.commands: executes the commands returned by handlers, through the
-- adapters. This is the only place in the core where adapters are called
-- with the result of business logic. Each command kind has a strict shape;
-- an unknown or malformed command is logged, never executed.
--   { kind = "bus.publish", topic = "...", payload = "..." | table (encoded as JSON) }
--   { kind = "files.write", path = "...", doc = table, version = n }
--   { kind = "files.remove", path = "..." }
--   { kind = "host.volume", percent = n }
--   { kind = "shell", action = "...", args = table, reply = "event.type"? }
--       with `reply`, the output comes back as an event { type = reply, out, rc, ref = c.ref }
--   { kind = "files.read_text", path = "...", reply = "event.type", ref = any }
--       -> event { type = reply, path, text (nil when missing), ref }
--   { kind = "timer.every" | "timer.once", name = "...", seconds = n }
--   { kind = "timer.cancel", name = "..." }
--   { kind = "emit", event = table }                -- an internal event for the next turn
--   { kind = "log", level = "...", key = "...", fields = table }
--   { kind = "shutdown", reason = "..." }
local json = require("vendor.json")
local log = require("kernel.log")
local timers = require("kernel.timers")
local commands = {}

local function check(cond, what) if not cond then error(what, 0) end end

local executors = {
  ["bus.publish"] = function(a, c)
    check(type(c.topic) == "string" and c.topic ~= "", "bus.publish needs a topic")
    local payload = c.payload
    if type(payload) == "table" then payload = json.encode(payload) end
    check(payload == nil or type(payload) == "string", "bus.publish payload must be string or table")
    local ok, err = a.bus:publish(c.topic, payload or "")
    if not ok then log.warn("commands.publish_failed", { topic = c.topic, err = tostring(err) }) end
  end,
  ["files.write"] = function(a, c)
    check(type(c.path) == "string" and type(c.doc) == "table", "files.write needs path and doc")
    local ok, err = a.files.write(c.path, c.doc, c.version or 1)
    if not ok then log.error("commands.write_failed", { path = c.path, err = tostring(err) }) end
  end,
  ["files.remove"] = function(a, c)
    check(type(c.path) == "string", "files.remove needs a path")
    a.files.remove(c.path)
  end,
  ["host.volume"] = function(a, c)
    check(type(c.percent) == "number", "host.volume needs a percent")
    a.host.set_volume(c.percent)
  end,
  ["shell"] = function(a, c, ctx)
    check(type(c.action) == "string", "shell needs an action")
    local out, rc = a.shell.run(c.action, c.args or {})
    if out == nil then
      log.error("commands.shell_refused", { action = c.action, err = tostring(rc) })
      rc = -1
    end
    if c.reply then
      ctx.emitted[#ctx.emitted + 1] = { type = c.reply, action = c.action, out = out, rc = rc, ref = c.ref }
    end
  end,
  ["files.read_text"] = function(a, c, ctx)
    check(type(c.path) == "string" and type(c.reply) == "string", "files.read_text needs path and reply")
    ctx.emitted[#ctx.emitted + 1] = { type = c.reply, path = c.path, text = a.files.read_text(c.path), ref = c.ref }
  end,
  ["timer.every"] = function(a, c) timers.every(c.name, c.seconds, a.clock.now()) end,
  ["timer.once"] = function(a, c) timers.once(c.name, c.seconds, a.clock.now()) end,
  ["timer.cancel"] = function(_, c) timers.cancel(c.name) end,
  ["emit"] = function(_, c, ctx)
    check(type(c.event) == "table" and type(c.event.type) == "string", "emit needs an event with a type")
    ctx.emitted[#ctx.emitted + 1] = c.event
  end,
  ["log"] = function(_, c)
    local fn = log[c.level or "info"]
    check(fn ~= nil, "unknown log level")
    fn(c.key or "handler", c.fields)
  end,
  ["shutdown"] = function(_, c, ctx) ctx.shutdown = c.reason or "requested" end,
}

--- Execute a list of commands. Returns { emitted = {events}, shutdown = reason|nil, failed = n }.
function commands.execute(adapters, list)
  local ctx = { emitted = {}, shutdown = nil, failed = 0 }
  for _, c in ipairs(list or {}) do
    local ex = type(c) == "table" and executors[c.kind]
    if not ex then
      ctx.failed = ctx.failed + 1
      log.error("commands.unknown", { kind = type(c) == "table" and tostring(c.kind) or type(c) })
    else
      local ok, err = pcall(ex, adapters, c, ctx)
      if not ok then
        ctx.failed = ctx.failed + 1
        log.error("commands.failed", { kind = c.kind, err = tostring(err) })
      end
    end
  end
  return ctx
end

commands.KINDS = {}
for k in pairs(executors) do commands.KINDS[#commands.KINDS + 1] = k end
table.sort(commands.KINDS)

return commands
