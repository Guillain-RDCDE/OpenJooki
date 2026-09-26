-- kernel.log: structured, leveled, rate-limited logging.
-- A log line is one call: log.info("playback.play", { playlist = id, ms = 42 }).
-- The first argument is a stable event key (module.what); fields are a flat
-- table. Repeated lines with the same key and level are rate-limited: after
-- `burst` lines within `window` seconds, only one line per window is written,
-- with the number of suppressed lines. Nothing here ever exits the process.
local log = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local SEVERITY = { debug = 7, info = 6, warn = 4, error = 3 }   -- syslog severities

local level = LEVELS.info
local sinks = {}               -- functions (line, level_name, severity)
local clock = function() return 0 end
local window, burst = 60, 5
local buckets = {}             -- key -> { start, count, suppressed }

local function format_value(v)
  local t = type(v)
  if t == "string" then
    if v:find("[%s\"=]") then return string.format("%q", v) end
    return v
  elseif t == "table" then
    return "table"
  end
  return tostring(v)
end

local function format_fields(fields)
  if not fields then return "" end
  local keys = {}
  for k in pairs(fields) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. format_value(fields[k]) end
  return " " .. table.concat(parts, " ")
end

local function emit(name, key, fields)
  local now = clock()
  local b = buckets[key .. "/" .. name]
  if not b or now - b.start >= window then
    if b and b.suppressed > 0 then
      local line = string.format("%-5s %s suppressed=%d", name, key, b.suppressed)
      for _, s in ipairs(sinks) do s(line, name, SEVERITY[name]) end
    end
    b = { start = now, count = 0, suppressed = 0 }
    buckets[key .. "/" .. name] = b
  end
  b.count = b.count + 1
  if b.count > burst then
    b.suppressed = b.suppressed + 1
    return false
  end
  local line = string.format("%-5s %s%s", name, key, format_fields(fields))
  for _, s in ipairs(sinks) do s(line, name, SEVERITY[name]) end
  return true
end

for name, n in pairs(LEVELS) do
  log[name] = function(key, fields)
    if n < level then return false end
    return emit(name, key, fields)
  end
end

--- Configure: { level = "info", sinks = { fn... }, clock = fn, window = 60, burst = 5 }
function log.configure(opts)
  opts = opts or {}
  if opts.level then
    assert(LEVELS[opts.level], "unknown log level " .. tostring(opts.level))
    level = LEVELS[opts.level]
  end
  if opts.sinks then sinks = opts.sinks end
  if opts.clock then clock = opts.clock end
  if opts.window then window = opts.window end
  if opts.burst then burst = opts.burst end
  buckets = {}
end

--- A sink that writes to stdout (one line per call).
function log.stdout_sink(line) io.write(line, "\n") end

log.LEVELS = LEVELS
log.SEVERITY = SEVERITY
return log
