-- The entry point of the core. On the device the C host runs this chunk; on the
-- bench, `lua5.1 build/harness.lua build/core.lua` does (same 4 stubs).
-- Wiring only: adapters, kernel, api, services, boot. No behaviour lives here.
local config = require("kernel.config")
local log = require("kernel.log")
local state = require("kernel.state")
local timers = require("kernel.timers")
local dispatch = require("kernel.dispatch")
local loop = require("kernel.loop")
local api = require("api.v2")
local v1 = require("api.v1")
local bus_events = require("api.bus_events")
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
local mdns = require("adapters.mdns").new()
local adapters = { bus = bus, files = files, clock = clock, host = host, shell = shell, mdns = mdns }

log.configure({
  level = env("JOOKI_LOG_LEVEL", "info") == "debug" and "debug" or (env("OPENJOOKI_LOG", "info")),
  clock = clock.now,
  sinks = { log.stdout_sink, function(line, _, severity) host.syslog(severity, line) end },
})

-- state document: what every module expects to exist before boot
local data_dir = config.get("data_dir")
state.reset({
  config = config.all(),
  device = {
    id = env("id", "jooki"), hostname = (env("hostname", "jooki.local"):gsub("%.local$", "")),
    wifi_mac = env("wifi_mac", nil), machine = env("machine", "bench"), firmware = env("firmware", "bench"),
    core = VERSION, openjooki = files.read_text(config.get("version_file")) and files.read_text(config.get("version_file")):match("%S+") or nil,
  },
  health = { degraded = false },
  userMessages = {},
})

-- api + services
dispatch.reset({ budget = config.get("error_budget_per_minute"), clock = clock.now })
api.reset()
api.install_builtin(VERSION)
dispatch.on("api.cmd", "api", api.handle)
require("services.library").install(api, dispatch)
require("services.tokens").install(api, dispatch)
require("services.playback").install(api, dispatch)
require("services.device").install(api, dispatch)
require("services.uploads").install(api, dispatch)
require("services.bedtime").install(api, dispatch)
require("services.update").install(api, dispatch)
v1.install(dispatch)

require("services.network").install(api, dispatch)

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

-- every event carries the wall clock too (bedtime, ids)
local translate = bus_events.chain(api.translate, bus_events.translate)
local function translate_with_time(topic, payload)
  local e = translate(topic, payload)
  if e then e.wall = clock.wall() end
  return e
end

-- state publication: v2 patches + v1 partials from the same dirty keys
local function publisher(doc, keys)
  local cmds = api.publisher(doc, keys)
  local p, first = v1.partial(doc, keys)
  if first then cmds[#cmds + 1] = first end
  if p then cmds[#cmds + 1] = p end
  return cmds
end

loop.init(adapters, { translate = translate_with_time, publisher = publisher,
  each_turn = function(doc)   -- the name on the network, answered from the loop (no handler involved)
    if mdns:available() and doc.net then
      if doc.net.name and not mdns.names[doc.net.name] then mdns:set_names({ doc.net.name }) end
      mdns:serve(doc.net.ip)
    end
  end })
timers.every("health", 60, clock.now())

-- boot: scratch directory, the web server's directories, then the family's files
pcall(function() local lfs = require("lfs"); if not lfs.attributes(config.get("scratch_dir")) then lfs.mkdir(config.get("scratch_dir")) end end)
do
  local out, rc = shell.run("setup_web_dirs", { data = data_dir })
  if rc ~= 0 then log.error("boot.web_dirs_failed", { rc = rc, out = tostring(out) }) end
end
local function read_or_empty(path)
  local doc, note = files.read(path, 1)
  if not doc then
    if note ~= "empty" then log.error("boot.file_unreadable", { path = path, why = tostring(note) }) end
    return {}
  end
  return doc
end
local system_tracks = read_or_empty(config.get("system_dir") .. "/tracks.json")
local flags = {}
for _, name in ipairs({ "STAY_ON", "TOY_SAFE_OFF", "WIFI_OFF", "BT_OFF", "FACTORY", "LOG_BUTTONS" }) do
  if files.exists(files.FLAG_DIR .. "/" .. name) then flags[name] = true end
end
loop.emit({
  type = "boot", now = clock.now(), wall = clock.wall(),
  library = { playlists = read_or_empty(data_dir .. "/playlists.json"), tracks = read_or_empty(data_dir .. "/tracks.json"),
              tokens = read_or_empty(data_dir .. "/tokens.json") },
  audiocfg = read_or_empty(data_dir .. "/audiocfg.json"),
  resume = read_or_empty(data_dir .. "/resume.json"),
  bedtime = read_or_empty(data_dir .. "/bedtime.json"),
  system = { tracks = system_tracks },
  flags = flags,
})

log.info("core.start", { version = VERSION, host = host.available() and "device" or "bench" })
host.ready()
loop.run()
