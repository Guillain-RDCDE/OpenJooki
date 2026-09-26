-- adapters.host: the four functions the C host gives us, with safe fallbacks
-- so the same core runs on the bench (where they do not exist).
local host = {}

local G = _G

function host.set_volume(percent)
  local v = math.floor(tonumber(percent) or 0)
  if v < 0 then v = 0 elseif v > 100 then v = 100 end
  if G.c_alsa_set_volume then
    local rc = G.c_alsa_set_volume(v, 0)
    return rc == 0, rc
  end
  host._last_volume = v
  return true, 0
end

function host.syslog(severity, line)
  if G.c_syslog then G.c_syslog(severity, line) end
end

function host.terminating()
  if G.c_isTerminating then return G.c_isTerminating() and true or false end
  return host._terminating == true
end

function host.ready()
  if G.c_sd_notify then G.c_sd_notify() end
  host._ready = true
end

function host.available()
  return G.c_alsa_set_volume ~= nil
end

return host
