-- services.security: the owner-facing security switches (docs/adr/0007), all off
-- by default. Owns state.maintenance = { ssh, ssh_until, mqtt_lan, parent }.
--   * ssh: a maintenance SSH access (dropbear on 2222) that turns itself off after
--     one hour, for us the tinkerers;
--   * mqtt_lan: MQTT exposed on the LAN for home automation (Home Assistant), with
--     the per-Jooki password; a boot script rebuilds the broker config;
--   * parent: whether a parent code is set (the code itself never reaches the page;
--     the gate that checks it lives in api.v1).
local security = {}

local SSH_SECONDS = 60 * 60           -- maintenance SSH lifetime: one hour
local PARENT_FILE = "/data/openjooki/parent_code"
local LAN_FLAG = "/data/openjooki/mqtt_lan"

-- the parent code, kept in memory only (never published in the state document).
-- Loaded from PARENT_FILE at boot; set/cleared by the commands below.
local parent_code = nil
function security._parent_code() return parent_code end          -- for api.v1's gate and tests
function security._set_parent_code(v) parent_code = v end          -- tests only

local function maint(doc)
  local m = {}
  for k, v in pairs(doc.maintenance or {}) do m[k] = v end
  return m
end

-- ---------------------------------------------------------------- SSH (one hour)
function security.on_ssh(doc, ev)
  local m = maint(doc)
  if ev.on then
    m.ssh = true
    m.ssh_until = (ev.wall or 0) + SSH_SECONDS
    return { state = { maintenance = m }, commands = {
      { kind = "shell", action = "ssh_on" },
      { kind = "timer.once", name = "security.ssh_off", seconds = SSH_SECONDS },
      { kind = "log", level = "info", key = "security.ssh_on" } } }
  end
  m.ssh = false
  m.ssh_until = nil
  return { state = { maintenance = m }, commands = {
    { kind = "shell", action = "ssh_off" },
    { kind = "timer.cancel", name = "security.ssh_off" },
    { kind = "log", level = "info", key = "security.ssh_off" } } }
end

-- ---------------------------------------------------------------- MQTT on the LAN
function security.on_mqtt_lan(doc, ev)
  local m = maint(doc)
  m.mqtt_lan = ev.on == true
  -- the boot script writes/removes the flag, rebuilds the broker config and, since
  -- the broker is already running, restarts it (adds/removes the LAN listener).
  return { state = { maintenance = m }, commands = {
    { kind = "shell", action = "mqtt_lan", args = { on = m.mqtt_lan } },
    { kind = "log", level = "info", key = m.mqtt_lan and "security.mqtt_lan_on" or "security.mqtt_lan_off" } } }
end

-- ---------------------------------------------------------------- parent code
local function is_code(s) return type(s) == "string" and s:match("^%d%d%d%d$") ~= nil end

--- set or change the 4-digit parent code. When one is already set, the current one
--- is required (the page sends it); the physical reset clears it without a code.
function security.on_parent_set(doc, ev)
  if not is_code(ev.code) then
    return nil, { code = "invalid_argument", field = "code", message = "a 4-digit code is required" }
  end
  if parent_code and parent_code ~= "" and ev.current ~= parent_code then
    return nil, { code = "forbidden", field = "current", message = "wrong current code" }
  end
  parent_code = ev.code
  local m = maint(doc); m.parent = true
  return { state = { maintenance = m }, commands = {
    { kind = "files.write_text", path = PARENT_FILE, text = ev.code .. "\n" },
    { kind = "log", level = "info", key = "security.parent_set" } } }
end

--- clear the parent code (from the page, with the current code; or from the buttons).
function security.on_parent_clear(doc, ev)
  if parent_code and parent_code ~= "" and not (ev.physical or ev.current == parent_code) then
    return nil, { code = "forbidden", field = "current", message = "wrong current code" }
  end
  parent_code = nil
  local m = maint(doc); m.parent = false
  local cmds = { { kind = "files.remove", path = PARENT_FILE },
                 { kind = "log", level = "info", key = "security.parent_clear" } }
  if ev.physical then
    -- a confirmation the child/owner can hear (docs/adr/0007: whoever holds the Jooki is allowed)
    cmds[#cmds + 1] = { kind = "emit", event = { type = "system.event", name = "Evt.Factory.Disable" } }
  end
  return { state = { maintenance = m }, commands = cmds }
end

-- ---------------------------------------------------------------- boot
function security.on_boot(doc)
  local files = security._files
  local m = maint(doc)
  m.ssh = false            -- dropbear on 2222 never survives a reboot
  m.ssh_until = nil
  m.mqtt_lan = files and files.exists(LAN_FLAG) or false
  local code = files and files.read_text and files.read_text(PARENT_FILE) or nil
  parent_code = code and code:match("^(%d%d%d%d)") or nil
  m.parent = parent_code ~= nil
  return { state = { maintenance = m } }
end

function security.on_timer(doc, ev)
  if ev.name ~= "security.ssh_off" then return nil end
  return security.on_ssh(doc, { on = false })
end

local S = {}
S.ssh = { type = "object", required = { "on" }, properties = { on = { type = "boolean" } }, additionalProperties = false }
S.parent = { type = "object", required = { "code" }, properties = { code = { type = "string" }, current = { type = "string" } }, additionalProperties = false }
security.schemas = S

function security.install(_, dispatch)
  security._files = require("adapters.files")
  dispatch.on("boot", "security", security.on_boot)
  dispatch.on("timer", "security", security.on_timer)
  dispatch.on("security.ssh", "security", security.on_ssh)
  dispatch.on("security.mqtt_lan", "security", security.on_mqtt_lan)
  dispatch.on("security.parent_set", "security", security.on_parent_set)
  dispatch.on("security.parent_clear", "security", security.on_parent_clear)
end

return security
