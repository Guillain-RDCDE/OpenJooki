-- kernel.timers: periodic and one-shot timers, delivered as events.
-- The kernel asks `due(now)` on every turn of the loop and `next_due(now)` to
-- know how long it may sleep. A timer never calls anything: it only produces
-- events { type = "timer", name = ..., now = ... } that the dispatcher routes
-- like any other event.
local timers = {}

local list = {}      -- name -> { period, at, once }

function timers.reset() list = {} end

--- every(name, seconds, now): fire every `seconds`, first time at now + seconds.
function timers.every(name, seconds, now)
  assert(seconds > 0, "period must be positive")
  list[name] = { period = seconds, at = (now or 0) + seconds }
end

--- once(name, seconds, now): fire one time, `seconds` from now (replaces a pending one).
function timers.once(name, seconds, now)
  list[name] = { period = nil, at = (now or 0) + seconds, once = true }
end

function timers.cancel(name) list[name] = nil end
function timers.pending(name) return list[name] ~= nil end

--- Seconds until the earliest timer, or nil when none is set.
function timers.next_due(now)
  local best
  for _, t in pairs(list) do
    local d = t.at - now
    if best == nil or d < best then best = d end
  end
  if best and best < 0 then best = 0 end
  return best
end

--- Events for every timer whose time has come, in a stable order (by due time, then name).
function timers.due(now)
  local fired = {}
  for name, t in pairs(list) do
    if t.at <= now then fired[#fired + 1] = { name = name, at = t.at } end
  end
  table.sort(fired, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return a.name < b.name
  end)
  local events = {}
  for _, f in ipairs(fired) do
    local t = list[f.name]
    if t.once then
      list[f.name] = nil
    else
      -- keep the cadence but never fire twice in a row for a missed period
      repeat t.at = t.at + t.period until t.at > now
    end
    events[#events + 1] = { type = "timer", name = f.name, now = now }
  end
  return events
end

return timers
