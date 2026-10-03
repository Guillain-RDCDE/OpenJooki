-- services.security: the owner-facing security switches (docs/adr/0007), all off
-- by default. Owns state.maintenance = { ssh, ssh_until, mqtt_lan, parent }.
--   * ssh: a maintenance SSH access (dropbear on 2222) that turns itself off after
--     one hour, for us the tinkerers;
--   * mqtt_lan: MQTT exposed on the LAN for home automation (Home Assistant), with
--     the per-Jooki password; a boot script rebuilds the broker config;
--   * parent: whether a parent code is set (the code itself never reaches the page;
--     the gate that checks it is security.gate, asked by api.v1 and api.v2).
local util = require("services.util")
local security = {}
local err = util.err

local SSH_SECONDS = 60 * 60           -- maintenance SSH lifetime: one hour
local PARENT_FILE = "/data/openjooki/parent_code"
local LAN_FLAG = "/data/openjooki/mqtt_lan"
local KEYS_FILE = "/data/openjooki/authorized_keys"
-- what main reads at boot (handlers do no I/O): the boot event carries their content, see on_boot
security.FILES = { parent = PARENT_FILE, lan = LAN_FLAG, keys = KEYS_FILE }

--- An SSH public key on one line: its type, the base64 blob, an optional plain comment.
--- The one definition: on_ssh_key checks the key, and adapters.shell checks it again before ssh_key_add.
function security.is_pubkey(s)
  if type(s) ~= "string" or #s > 1000 then return false end
  local kind, blob, rest = s:match("^(%S+) ([A-Za-z0-9+/]+=?=?)(.*)$")
  if not (kind == "ssh-ed25519" or kind == "ssh-rsa" or (kind and kind:match("^ecdsa%-sha2%-nistp%d+$"))) then return false end
  if #blob < 60 then return false end
  return rest == "" or rest:match("^ [%w@%.%-_]+$") ~= nil
end

-- the parent code, kept in memory only (never published in the state document).
-- Loaded from PARENT_FILE at boot; set/cleared by the commands below.
local parent_code = nil
function security._parent_code() return parent_code end          -- tests only
function security._set_parent_code(v) parent_code = v end          -- tests only

-- The v2 commands a parent code protects (docs/adr/0007): what changes the Jooki's content or its
-- set-up. Playing music, the volume and the sleep timer stay open for the children. api.v1 keeps its
-- own list of message names; both ask security.gate.
security.PROTECTED_V2 = {
  ["playlist.new"] = true, ["playlist.delete"] = true, ["playlist.update"] = true,
  ["playlist.add_track"] = true, ["playlist.add_stream"] = true, ["upload.add"] = true,
  ["token.edit"] = true, ["token.forget"] = true,
  ["device.set_config"] = true, ["device.toy_safe"] = true, ["device.set_wifi"] = true,
  ["device.power_off"] = true, ["device.set_name"] = true, ["device.airplane"] = true,
  ["bedtime.set"] = true, ["update.check"] = true, ["update.start"] = true,
  ["spotify.new_playlist"] = true, ["deezer.get_playlists"] = true, ["deezer.set_config"] = true,
}

--- The parent-code gate: nil when `name` may run, else the typed error to answer with.
--- `protected` is the set of names the code covers; `code` is what the caller sent.
function security.gate(protected, name, code)
  if not (parent_code and parent_code ~= "" and protected[name]) then return nil end
  if tostring(code or "") == parent_code then return nil end
  return err("forbidden", "code", "PARENT_CODE_REQUIRED")
end

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

--- A public key for the maintenance access, kept on /data so that updates no longer lose it
--- (they rewrite /home). Only while the access is open (the owner opened it in the last hour),
--- and behind the parent code when one is set (api.v1). { key } adds one, { clear = true } forgets all.
local KEYS_MAX = 5
-- the saved keys, in memory like the file (loaded at boot): the count the page shows is the file's
local ssh_keys = {}
function security._set_ssh_keys(list) ssh_keys = list or {} end   -- tests only
function security.on_ssh_key(doc, ev)
  local m = maint(doc)
  if not m.ssh then
    return nil, err("forbidden", "", "SSH_CLOSED")
  end
  if ev.clear then
    ssh_keys = {}
    m.ssh_keys = 0
    return { state = { maintenance = m }, commands = {
      { kind = "shell", action = "ssh_key_clear" }, { kind = "log", level = "info", key = "security.ssh_keys_cleared" } } }
  end
  local key = type(ev.key) == "string" and ev.key:gsub("^%s+", ""):gsub("%s+$", "") or nil
  if not security.is_pubkey(key) then
    return nil, err("invalid_argument", "key", "SSH_KEY_INVALID")
  end
  -- same rule as the shell action: once each, the last five kept
  local kept = {}
  for _, k in ipairs(ssh_keys) do if k ~= key then kept[#kept + 1] = k end end
  kept[#kept + 1] = key
  while #kept > KEYS_MAX do table.remove(kept, 1) end
  ssh_keys = kept
  m.ssh_keys = #kept
  return { state = { maintenance = m }, commands = {
    { kind = "shell", action = "ssh_key_add", args = { key = key } },
    { kind = "log", level = "info", key = "security.ssh_key_added", fields = { kind = key:match("^(%S+)") } } } }
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
    return nil, err("invalid_argument", "code", "a 4-digit code is required")
  end
  if parent_code and parent_code ~= "" and ev.current ~= parent_code then
    return nil, err("forbidden", "current", "wrong current code")
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
    return nil, err("forbidden", "current", "wrong current code")
  end
  parent_code = nil
  local m = maint(doc); m.parent = false
  local cmds = { { kind = "files.remove", path = PARENT_FILE },
                 { kind = "log", level = "info", key = "security.parent_clear" } }
  if ev.physical then
    -- a confirmation the child/owner can hear (docs/adr/0007: whoever holds the Jooki is allowed)
    cmds[#cmds + 1] = util.emit("system.event", { name = "Evt.Factory.Disable" })
  end
  return { state = { maintenance = m }, commands = cmds }
end

-- ---------------------------------------------------------------- boot
--- boot: ev.security = { mqtt_lan = the LAN flag is present, authorized_keys = the keys file's
--- text (or nil), parent_code = the code file's text (or nil) }, read by main like the other files.
function security.on_boot(doc, ev)
  local s = (ev and ev.security) or {}
  local m = maint(doc)
  m.ssh = false            -- dropbear on 2222 never survives a reboot
  m.ssh_until = nil
  m.mqtt_lan = s.mqtt_lan == true
  ssh_keys = {}
  for line in (s.authorized_keys or ""):gmatch("[^\n]+") do
    if line:match("%S") then ssh_keys[#ssh_keys + 1] = line end
  end
  m.ssh_keys = #ssh_keys
  local code = s.parent_code
  parent_code = code and code:match("^(%d%d%d%d)") or nil
  m.parent = parent_code ~= nil
  return { state = { maintenance = m } }
end

--- The hour is up (timer security.ssh_off): the maintenance access closes by itself.
function security.on_ssh_off(doc) return security.on_ssh(doc, { on = false }) end

--- The timer by name (the specs drive this one; the kernel routes the name itself).
function security.on_timer(doc, ev)
  if ev.name ~= "security.ssh_off" then return nil end
  return security.on_ssh_off(doc)
end

local S = {}
S.ssh = { type = "object", required = { "on" }, properties = { on = { type = "boolean" } }, additionalProperties = false }
S.parent = { type = "object", required = { "code" }, properties = { code = { type = "string" }, current = { type = "string" } }, additionalProperties = false }
security.schemas = S

function security.install(_, dispatch)
  dispatch.on("boot", "security", security.on_boot)
  dispatch.on_timer("security.ssh_off", "security", security.on_ssh_off)
  -- the page's switches arrive through api.v1, which calls the handlers above directly;
  -- only the physical reset (services.device) comes as an event
  dispatch.on("security.parent_clear", "security", security.on_parent_clear)
end

return security
