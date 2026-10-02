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

-- seconds since the kernel started (nil off Linux): the boot timeline is measured on this clock
local function kernel_uptime()
  local f = io.open("/proc/uptime", "r")
  if not f then return nil end
  local s = f:read("*l")
  f:close()
  local v = s and tonumber(s:match("^(%S+)"))
  return v and math.floor(v * 100 + 0.5) / 100 or nil
end
local BOOT = { start_s = kernel_uptime(), marks = {} }
-- a step of the boot, on the same clock ("name=seconds"), kept in health.boot.marks
local function mark(name) BOOT.marks[#BOOT.marks + 1] = name .. "=" .. tostring(kernel_uptime()) end

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
-- a real Jooki (its hardware driver), not the bench: the bench harness gives the C host's four
-- functions too, so they do not tell. The two watchdogs act on the machine: never off a Jooki,
-- unless a test sets them on purpose.
local ON_JOOKI = (function() local f = io.open("/sys/kernel/htdrv/mac", "r") if f then f:close() return true end return false end)()
if not ON_JOOKI then
  if overrides.wifi_watchdog_s == nil then overrides.wifi_watchdog_s = 0 end
  if overrides.broker_watch_s == nil then overrides.broker_watch_s = 0 end
  -- the side-dot chase would otherwise publish LED frames forever on the bench (no Wi-Fi to end it)
  if overrides.wifi_anim_s == nil then overrides.wifi_anim_s = 0 end
end
-- bench convenience: run the web server on an unprivileged port (no root, no clash with the emulator)
local hp = os.getenv("OJ_HTTP_PORT")
if hp and hp ~= "" then overrides.http_port = tonumber(hp) or 0 end
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
             "/j/power/input/#", "/j/esp32/input/#", "/j/net/dhcp/#", "/j/event", "/j/mender", "/j/mender/shutdown_app",
             "/j/spotify/input/#", "/j/deezer/input/#" },
})
local mdns = require("adapters.mdns").new()
-- the broker has no other keeper (on a Jooki; on the bench only when a test asks for it)
local broker_watch = config.get("broker_watch_s") > 0
  and require("adapters.broker_watch").new({ shell = shell, after_s = config.get("broker_watch_s") }) or nil
local adapters = { bus = bus, files = files, clock = clock, host = host, shell = shell, mdns = mdns }
mark("adapters")

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
require("services.security").install(api, dispatch)
-- optional (ADR-0009): disabled by configuration, or absent from a `--without services.streaming` build
if config.get("streaming_enabled") and package.preload["services.streaming"] then
  require("services.streaming").install(api, dispatch)
end
v1.install(dispatch)

require("services.network").install(api, dispatch)
require("services.bluetooth").install(api, dispatch)
mark("services")

-- health: every 60 s, memory and bus statistics into the state
dispatch.on("timer", "health", function(doc, ev)
  if ev.name ~= "health" then return nil end
  local rss
  local f = io.open("/proc/self/status", "r")
  if f then
    for line in f:lines() do rss = rss or tonumber(line:match("^VmRSS:%s+(%d+)")) end
    f:close()
  end
  -- syslog-ng starts throttled and drops what is logged in the first seconds: say the boot times here
  if not BOOT.logged and BOOT.ready_s then
    BOOT.logged = true
    log.info("core.boot", { start_s = BOOT.start_s, ready_s = BOOT.ready_s, marks = BOOT.marks_text })
  end
  return { state = { health = { degraded = doc.health and doc.health.degraded or false, rss_kb = rss,
                                uptime_s = math.floor(ev.now), bus = bus.stats, shell_calls = shell.count,
                                boot = { start_s = BOOT.start_s, ready_s = BOOT.ready_s, marks = BOOT.marks_text } } } }
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

-- our own web server: serves the page and /upload so web_ctrl (with /ll and /cmd) can stop (ADR-0007).
-- Its own name, for the rebinding guard, comes from the live state (net.name). Failure to bind (the
-- port still held by the core before this one, or not root on the bench) is not fatal: the core runs
-- on and the server tries again by itself (httpd:tick). Without LuaSocket there is no server at all.
local httpd = nil
if config.get("http_port") > 0 then
  httpd = require("adapters.httpd").new({
    port = config.get("http_port"),
    docroot = config.get("web_public_dir"),
    uploads_dir = data_dir .. "/uploads",
    name = function() local d = state.doc(); return d.net and d.net.name end,
    log = function(key, fields) log.info(key, fields) end,
    on_upload = function(n) log.info("httpd.upload", { parts = n }) end,
  })
  local ok, err = httpd:start()
  if not ok then
    log.warn("httpd.start_failed", { err = tostring(err) })
    if httpd.socket_lib then httpd:retry_later(clock.now()) else httpd = nil end
  end
end

loop.init(adapters, { translate = translate_with_time, publisher = publisher,
  io_sources = httpd and function() return httpd:read_socks(), httpd:write_socks() end or nil,
  io_ready = httpd and function(rr, wr, now) httpd:service_read(rr, now); httpd:service_write(wr, now) end or nil,
  each_turn = function(doc)   -- the name on the network, answered from the loop (no handler involved)
    if httpd then httpd:tick(clock.now()) end
    if broker_watch then broker_watch:check(bus:connected(), clock.now()) end
    if mdns:available() and doc.net then
      -- only its own name: web_ctrl (closed) redirects any other Host, jooki.local included, to
      -- Muuselabs' dead setup site (docs/20). Names are kept lower case by the adapter.
      if doc.net.name and not mdns.names[doc.net.name:lower()] then mdns:set_names({ doc.net.name }) end
      mdns:serve(doc.net.ip, clock.now())
    end
  end })
timers.every("health", 60, clock.now())

-- boot: scratch directory, the web server's directories, then the family's files
pcall(function() local lfs = require("lfs"); if not lfs.attributes(config.get("scratch_dir")) then lfs.mkdir(config.get("scratch_dir")) end end)
-- (in the background: 0.8 s on the device, and web_ctrl only starts 5 s after the core)
do
  local out, rc = shell.run("setup_web_dirs", { data = data_dir })
  if rc ~= 0 then log.error("boot.web_dirs_failed", { rc = rc, out = tostring(out) }) end
end
mark("web_dirs")
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
for _, name in ipairs({ "STAY_ON", "TOY_SAFE_OFF", "WIFI_OFF", "BT_OFF", "FACTORY", "LOG_BUTTONS", "OJ_AIRPLANE" }) do
  if files.exists(files.FLAG_DIR .. "/" .. name) then flags[name] = true end
end
local boot_event = {
  type = "boot", now = clock.now(), wall = clock.wall(),
  library = { playlists = read_or_empty(data_dir .. "/playlists.json"), tracks = read_or_empty(data_dir .. "/tracks.json"),
              tokens = read_or_empty(data_dir .. "/tokens.json") },
  audiocfg = read_or_empty(data_dir .. "/audiocfg.json"),
  resume = read_or_empty(data_dir .. "/resume.json"),
  bedtime = read_or_empty(data_dir .. "/bedtime.json"),
  system = { tracks = system_tracks },
  flags = flags,
  -- the power controller only reports a cable change: without this a Jooki plugged in at boot
  -- would believe it runs on battery and power itself off after 15 min of silence
  plugged = (files.read_text(config.get("plugged_file")) or ""):match("^%s*([01])"),
  -- the Wi-Fi watchdog (services.network): restarts it already made in a row, and a silent start after one
  wifi_watchdog = files.read_text(config.get("wifi_watchdog_file")),
  quiet_boot = files.exists(config.get("quiet_boot_file")),
}
mark("files")
loop.emit(boot_event)
mark("boot_event")

log.info("core.start", { version = VERSION, host = host.available() and "device" or "bench" })
host.ready()
BOOT.ready_s = kernel_uptime()
BOOT.marks_text = table.concat(BOOT.marks, " ")
state.set("health", { degraded = (state.get("health") or {}).degraded or false,
                      boot = { start_s = BOOT.start_s, ready_s = BOOT.ready_s, marks = BOOT.marks_text } })
loop.run()
