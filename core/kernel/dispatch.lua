-- kernel.dispatch: routes one event to its handlers, safely.
-- A handler is registered as on(event_type, module_name, fn). It receives
-- (doc, event) where doc is a read-only view of the state document, and
-- returns nil or a result table:
--   { state = { key = value, ... },   -- sub-trees to replace
--     commands = { cmd, ... } }       -- side effects for the kernel to execute
-- Every call is protected. A handler that fails more than `budget` times in a
-- minute is disabled until restart, and the failure is reported as a command
-- so the page can show it. The dispatcher never raises.
local log = require("kernel.log")
local dispatch = {}

local handlers = {}    -- event_type -> list of { module, fn }
local failures = {}    -- module -> { window_start, count, disabled }
local budget = 20
local clock = function() return 0 end

function dispatch.reset(opts)
  handlers, failures = {}, {}
  opts = opts or {}
  budget = opts.budget or 20
  clock = opts.clock or clock
end

function dispatch.on(event_type, module, fn)
  assert(type(fn) == "function", "handler must be a function")
  handlers[event_type] = handlers[event_type] or {}
  table.insert(handlers[event_type], { module = module, fn = fn })
end

function dispatch.disabled(module)
  local f = failures[module]
  return f ~= nil and f.disabled == true
end

local function note_failure(module, event, err)
  local now = clock()
  local f = failures[module]
  if not f or now - f.window_start >= 60 then
    f = { window_start = now, count = 0, disabled = false }
    failures[module] = f
  end
  f.count = f.count + 1
  log.error("dispatch.handler_failed", { module = module, event = event.type, err = tostring(err), count = f.count })
  if f.count > budget then
    f.disabled = true
    log.error("dispatch.handler_disabled", { module = module, event = event.type })
    return true
  end
  return false
end

--- Run every handler of the event. Returns the merged state changes and the
--- ordered list of commands, plus the list of failures { module, err }.
function dispatch.handle(doc, event)
  local changes, commands, errors = {}, {}, {}
  local list = handlers[event.type]
  if not list then return changes, commands, errors end
  for _, h in ipairs(list) do
    if not dispatch.disabled(h.module) then
      local ok, result = pcall(h.fn, doc, event)
      if not ok then
        local disabled = note_failure(h.module, event, result)
        errors[#errors + 1] = { module = h.module, err = tostring(result), disabled = disabled }
      elseif result ~= nil then
        if type(result) ~= "table" then
          note_failure(h.module, event, "handler returned " .. type(result))
          errors[#errors + 1] = { module = h.module, err = "bad result type" }
        else
          for k, v in pairs(result.state or {}) do changes[k] = v end
          for _, c in ipairs(result.commands or {}) do commands[#commands + 1] = c end
        end
      end
    end
  end
  return changes, commands, errors
end

--- The list of event types with at least one handler (for the bus subscription and tests).
function dispatch.event_types()
  local out = {}
  for t in pairs(handlers) do out[#out + 1] = t end
  table.sort(out)
  return out
end

return dispatch
