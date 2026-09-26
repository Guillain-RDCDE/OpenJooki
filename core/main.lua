-- The entry point of the core. On the device the C host runs this chunk; on the
-- bench, `lua5.1 build/core.lua` does (with the same 4 stubs as run.lua).
-- Wiring only: adapters, kernel, api, services. No behaviour lives here.
local config = require("kernel.config")
local log = require("kernel.log")
local state = require("kernel.state")
local timers = require("kernel.timers")
local dispatch = require("kernel.dispatch")
local loop = require("kernel.loop")
local api = require("api.v2")
local json = require("vendor.json")

local VERSION = _G._OPENJOOKI_CORE or "dev"

local function env(name, default)
  local v = os.getenv(name)
  if v == nil or v == "" then return default end
  return v
end

-- configuration: defaults, then an optional JSON file (bench or device tuning)
local overrides = {}
local cfg_path = env("OPENJOOKI_CONFIG", nil)
if cfg_path then
  local f = io.open(cfg_path, "r")
  if f then
    local ok, t = pcall(json.decode, f:read("*a"))
    f:close()
    if ok and type(t) == "table" then overrides = t end
  end
end
config.load(overrides)

-- adapters
local host = require("adapters.host")
local clock = require("adapters.clock")
local files = require("adapters.files")
local shell = require("adapters.shell")
local bus = require("adapters.bus").new({
  host = config.get("mqtt_host"), port = config.get("mqtt_port"),
  client_id = config.get("mqtt_client_id"), keepalive = config.get("mqtt_keepalive_s"),
  min_backoff = config.get("mqtt_reconnect_min_s"), max_backoff = config.get("mqtt_reconnect_max_s"),
  topics = { api.TOPIC_CMD, "/j/web/input/#", "/j/audio/input/#", "/j/nfc/input/#", "/j/gpio/input/#",
             "/j/power/input/#", "/j/esp32/input/#", "/j/net/dhcp/#", "/j/event", "/j/mender", "/j/mender/shutdown_app" },
})
local adapters = { bus = bus, files = files, clock = clock, host = host, shell = shell }

log.configure({
  level = env("JOOKI_LOG_LEVEL", "info") == "debug" and "debug" or (env("OPENJOOKI_LOG", "info")),
  clock = clock.now,
  sinks = { log.stdout_sink, function(line, _, severity) host.syslog(severity, line) end },
})

-- state document: the sub-trees every module expects to exist
state.reset({
  device = {
    id = env("id", "jooki"), hostname = (env("hostname", "jooki.local"):gsub("%.local$", "")),
    machine = env("machine", "bench"), firmware = env("firmware", "bench"), core = VERSION,
  },
  health = { degraded = false },
})

-- api and services
dispatch.reset({ budget = config.get("error_budget_per_minute"), clock = clock.now })
api.reset()
api.install_builtin(VERSION)
dispatch.on("api.cmd", "api", api.handle)

-- health: every 60 s, memory and bus statistics into the state
dispatch.on("timer", "health", function(doc, ev)
  if ev.name ~= "health" then return nil end
  local rss
  local f = io.open("/proc/self/status", "r")
  if f then
    for line in f:lines() do rss = rss or tonumber(line:match("^VmRSS:%s+(%d+)")) end
    f:close()
  end
  return { state = { health = { degraded = doc.health and doc.health.degraded or false, rss_kb = rss,
                                uptime_s = math.floor(ev.now), bus = bus.stats, shell_calls = shell.count } } }
end)

loop.init(adapters, { translate = api.translate, publisher = api.publisher })
timers.every("health", 60, clock.now())
log.info("core.start", { version = VERSION, host = host.available() and "device" or "bench" })
host.ready()
loop.run()
