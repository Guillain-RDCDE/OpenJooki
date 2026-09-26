-- adapters.clock: the only source of time.
--   now()  -> seconds since boot (monotonic; /proc/uptime on the device)
--   wall() -> os.time() (UTC seconds; only bedtime's window uses it)
-- Reading /proc/uptime is a procfs read (no flash, no process). When it is
-- not available (bench on a non-Linux host), socket.gettime is used.
local clock = {}

local reader = function()
  local f = io.open("/proc/uptime", "r")
  if not f then return nil end
  local line = f:read("*l")
  f:close()
  return line and tonumber(line:match("^(%S+)"))
end

local fallback_origin

function clock.now()
  local up = reader()
  if up then return up end
  local ok, socket = pcall(require, "socket")
  local t = ok and socket.gettime() or os.time()
  fallback_origin = fallback_origin or t
  return t - fallback_origin
end

function clock.wall() return os.time() end

--- Tests inject their own reader.
function clock._set_reader(fn) reader = fn end

return clock
