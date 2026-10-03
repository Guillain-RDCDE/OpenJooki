-- kernel.config: every tunable in one place, with its default and its meaning.
-- Values can be overridden by a table (the bench) or by a JSON file on the
-- device (/jooki/external/jooki/core.json), never by code elsewhere.
local config = {}

config.defaults = {
  -- paths
  data_dir = "/jooki/external/jooki",         -- family data (playlists, tracks, tokens...)
  system_dir = "/jooki/app/system",           -- event sounds shipped with the firmware
  scratch_dir = "/run/openjooki",             -- tmpfs scratch (never the flash)
  version_file = "/etc/openjooki-version",
  plugged_file = "/sys/kernel/htdrv/plugged",  -- "1" when the charger is in (read once at boot, like 1.x)
  wifi_watchdog_file = "/data/openjooki/wifi_watchdog",   -- restarts in a row made by the Wi-Fi watchdog
  quiet_boot_file = "/data/openjooki/quiet_boot",         -- present: the next start plays no "ready" chime
  -- bus
  mqtt_host = "127.0.0.1",
  mqtt_port = 1883,
  mqtt_client_id = "openjooki-core",
  mqtt_keepalive_s = 30,
  mqtt_reconnect_min_s = 1,
  mqtt_reconnect_max_s = 30,
  broker_watch_s = 20,                        -- broker unreachable this long -> start it again (0 = never)
  -- Wi-Fi watchdog (services.network): offline this long, radios on, nothing playing -> restart the Jooki
  wifi_watchdog_s = 10 * 60,                  -- 0 = never
  wifi_watchdog_max = 2,                      -- restarts in a row without Wi-Fi, then it stops trying
  -- our own web server (adapters.httpd): serves the page and /upload so web_ctrl (with /ll and
  -- /cmd) can stop (ADR-0007). 0 = off (the bench smoke, or to fall back to web_ctrl).
  http_port = 80,
  web_public_dir = "/tmp/web_ctrl_dirs/public",   -- what web_ctrl served, rebuilt at boot
  -- The Jooki v2 has NO wired headphone jack. Its ESP32 still reports an `hp_state` in the knob
  -- message, and it can read as "plugged" with nothing there -- which used to route the sound to a
  -- jack that does not exist and switch the speaker amplifier off, leaving the Jooki silent with no
  -- way to hear anything. So wired-headphone detection is off by default; Bluetooth is separate.
  headphone_jack = false,
  -- the start-up "waiting for Wi-Fi" side-dot chase (services.device): interval between frames.
  -- 0 = off. Off the real Jooki (bench, smoke) it is set to 0 so it adds no idle bus traffic.
  wifi_anim_s = 0.45,
  -- loop
  tick_s = 0.5,                               -- longest wait when nothing is due
  state_publish_min_interval_s = 0.25,        -- coalescing window for state patches
  error_budget_per_minute = 20,               -- a handler over budget is disabled
  -- power (from the original program, docs/22 §3.6)
  inactivity_warn_s = 14 * 60,
  inactivity_off_s = 15 * 60,
  battery_warn_percent = 20,
  battery_off_percent = 10,
  overheat_mc = 80000,
  -- streaming module (ADR-0009)
  streaming_enabled = true,
  -- OpenJooki updates (services.update): where the Jooki reads the newest version and the installer.
  -- The bench points both at its own web server (adapters.shell only accepts GitHub or 127.0.0.1).
  update_manifest_url = "https://github.com/Guillain-RDCDE/OpenJooki/releases/latest/download/version.json",
  update_script_url = "https://guillain-rdcde.github.io/OpenJooki/o.sh",
}

local current = {}

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

--- Build the effective configuration: defaults, then overrides (unknown keys are refused).
function config.load(overrides)
  current = copy(config.defaults)
  for k, v in pairs(overrides or {}) do
    if config.defaults[k] == nil then error("unknown config key: " .. tostring(k)) end
    if type(v) ~= type(config.defaults[k]) then
      error("config " .. k .. ": expected " .. type(config.defaults[k]) .. ", got " .. type(v))
    end
    current[k] = v
  end
  return current
end

function config.get(key)
  local v = current[key]
  if v == nil then
    if config.defaults[key] == nil then error("unknown config key: " .. tostring(key)) end
    return config.defaults[key]
  end
  return v
end

function config.all() return copy(current) end

config.load({})
return config
