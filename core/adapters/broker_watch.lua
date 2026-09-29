-- adapters.broker_watch: the broker (mosquitto) carries everything on the Jooki (tokens, knobs,
-- the page), and nothing on the original system restarts it if it fails to start or stops.
-- The core notices it cannot reach it and starts it again: after `after_s` without the bus, then
-- at most every `every_s`. Only a broker that is not running is started: one that runs but does
-- not answer is left alone and logged (killing it would cut the closed daemons too).
--   local w = require("adapters.broker_watch").new({ shell = shell, after_s = 20, every_s = 60 })
--   w:check(bus:connected(), now)   -- once per loop turn; returns "restart" when it acted
local log = require("kernel.log")
local watch = {}
watch.__index = watch

function watch.new(opts)
  opts = opts or {}
  return setmetatable({ shell = opts.shell, after_s = opts.after_s or 20, every_s = opts.every_s or 60,
                        down_since = nil, last_try = nil, tries = 0 }, watch)
end

function watch:check(up, now)
  if up then
    if self.down_since and self.tries > 0 then
      log.info("broker.back", { down_s = math.floor(now - self.down_since), tries = self.tries })
    end
    self.down_since, self.last_try, self.tries = nil, nil, 0
    return nil
  end
  self.down_since = self.down_since or now
  if now - self.down_since < self.after_s then return nil end
  if self.last_try and now - self.last_try < self.every_s then return nil end
  self.last_try, self.tries = now, self.tries + 1
  local out = self.shell and self.shell.run("broker_start", {}) or ""
  log.warn("broker.start", { down_s = math.floor(now - self.down_since), try = self.tries,
                             result = (tostring(out):gsub("%s+$", ""):sub(1, 60)) })
  return "restart"
end

return watch
