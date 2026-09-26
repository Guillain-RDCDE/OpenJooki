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
  -- bus
  mqtt_host = "127.0.0.1",
  mqtt_port = 1883,
  mqtt_client_id = "openjooki-core",
  mqtt_keepalive_s = 30,
  mqtt_reconnect_min_s = 1,
  mqtt_reconnect_max_s = 30,
  -- loop
  tick_s = 0.5,                               -- longest wait when nothing is due
  state_publish_min_interval_s = 0.25,        -- coalescing window for state patches
  state_full_interval_s = 60,                 -- full state re-sent to subscribed pages
  error_budget_per_minute = 20,               -- a handler over budget is disabled
  -- files
  save_interval_s = 1,                        -- dirty files flushed at most once a second
  sync_min_interval_s = 5,                    -- "sync" process at most every 5 s, and at shutdown
  -- power (from the original program, docs/22 §3.6)
  inactivity_warn_s = 14 * 60,
  inactivity_off_s = 15 * 60,
  battery_warn_percent = 20,
  battery_off_percent = 10,
  overheat_mc = 80000,
  -- streaming module (ADR-0009)
  streaming_enabled = true,
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
