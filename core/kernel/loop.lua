-- kernel.loop: the one loop.
-- Every turn: keep the bus alive, collect events (bus messages, due timers,
-- emitted events, host signals), dispatch them one by one, apply state
-- changes, execute commands, publish state patches (coalesced), then sleep
-- until the next timer or the next bus message. `step()` runs one turn and is
-- what the tests drive; `run()` calls it forever until shutdown.
local log = require("kernel.log")
local state = require("kernel.state")
local timers = require("kernel.timers")
local dispatch = require("kernel.dispatch")
local commands = require("kernel.commands")
local config = require("kernel.config")
local loop = {}

local A                      -- adapters { bus, files, clock, host, shell }
local translate              -- function(topic, payload) -> event | nil  (the api sets it)
local publisher              -- function(doc, dirty_keys) -> commands   (the api sets it)
local each_turn              -- optional function(doc) run once per turn (adapters that need polling)
local pending = {}           -- events queued for the next turn
local last_publish = -1
local dirty_pending = {}
local stopped = nil
local turns = 0

function loop.init(adapters, opts)
  A = adapters
  opts = opts or {}
  translate = opts.translate or function() return nil end
  publisher = opts.publisher or function() return {} end
  each_turn = opts.each_turn
  pending, dirty_pending, stopped, turns, last_publish = {}, {}, nil, 0, -1
end

function loop.emit(event) pending[#pending + 1] = event end
function loop.stopped() return stopped end
function loop.turns() return turns end

local function merge_dirty(keys)
  for _, k in ipairs(keys) do dirty_pending[k] = true end
end

local function dirty_list()
  local keys = {}
  for k in pairs(dirty_pending) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function handle_one(event)
  local changes, cmds, errors = dispatch.handle(state.doc(), event)
  local changed = state.apply(changes)
  merge_dirty(changed)
  for _, e in ipairs(errors) do
    if e.disabled then
      state.set("health", { degraded = true, module = e.module })
      merge_dirty({ "health" })
    end
  end
  local ctx = commands.execute(A, cmds)
  for _, e in ipairs(ctx.emitted) do pending[#pending + 1] = e end
  if ctx.shutdown then stopped = ctx.shutdown end
end

--- One turn of the loop. `wait` = max seconds to wait for bus data (default: until next timer).
function loop.step(wait)
  turns = turns + 1
  local now = A.clock.now()
  local transition = A.bus:maintain(now)
  if transition then pending[#pending + 1] = { type = "bus." .. transition, now = now } end

  -- events of this turn: queued first, then timers, then the bus
  local events = pending
  pending = {}
  for _, e in ipairs(timers.due(now)) do events[#events + 1] = e end
  local timeout = wait
  if timeout == nil then
    local due = timers.next_due(now)
    timeout = math.min(due or config.get("tick_s"), config.get("tick_s"))
    if #events > 0 then timeout = 0 end
  end
  local msgs = A.bus:poll(timeout, now)
  for _, m in ipairs(msgs) do
    local e = translate(m.topic, m.payload)
    if e then events[#events + 1] = e end
  end
  if A.host.terminating() and not stopped then events[#events + 1] = { type = "host.terminating", now = now } end
  if each_turn then
    local ok, err = pcall(each_turn, state.doc())
    if not ok then log.warn("loop.each_turn_failed", { err = tostring(err) }) end
  end

  for _, e in ipairs(events) do
    e.now = e.now or now
    handle_one(e)
  end

  -- state publication, coalesced
  local keys = dirty_list()
  if #keys > 0 and (now - last_publish) >= config.get("state_publish_min_interval_s") then
    local cmds = publisher(state.doc(), keys)
    commands.execute(A, cmds)
    dirty_pending = {}
    last_publish = now
  end
  return #events
end

function loop.run()
  log.info("loop.start", { tick_s = config.get("tick_s") })
  while not stopped do
    local ok, err = pcall(loop.step)
    if not ok then log.error("loop.turn_failed", { err = tostring(err) }) end
  end
  log.info("loop.stop", { reason = stopped })
  return stopped
end

return loop
