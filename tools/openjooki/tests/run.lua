-- Bench runner: C stubs normally provided by the player binary.
function c_syslog(level, msg) io.stdout:write("[syslog "..tostring(level).."] "..tostring(msg).."\n") end
function c_alsa_set_volume(v, x)  -- hardware volume: logged for the bedtime tests
  local f = io.open('/tmp/bench_vol.log', 'a') if f then f:write(tostring(v) .. '\n') f:close() end
  return 0
end
function c_isTerminating() return false end
function c_sd_notify() end
local src = assert(io.open(arg[1])):read('*a')
local f = assert(loadstring(src, '=player'))
f()
