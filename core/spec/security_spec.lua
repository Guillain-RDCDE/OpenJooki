local security = require("services.security")
local v1 = require("api.v1")

local function find(cmds, kind, key, val)
  for _, c in ipairs(cmds or {}) do
    if c.kind == kind and (key == nil or c[key] == val) then return c end
  end
  return nil
end
local function has_shell(cmds, action) return find(cmds, "shell", "action", action) ~= nil end

describe("services.security", function()
  before_each(function()
    security._set_parent_code(nil)
    security._set_ssh_keys({})
    security._files = nil
  end)

  it("SSH on: shell, one-hour timer, state with an end time", function()
    local r = security.on_ssh({}, { on = true, wall = 1000 })
    assert_true(r.state.maintenance.ssh)
    assert_eq(r.state.maintenance.ssh_until, 1000 + 3600)
    assert_true(has_shell(r.commands, "ssh_on"))
    local tmr = find(r.commands, "timer.once")
    assert_eq(tmr.name, "security.ssh_off"); assert_eq(tmr.seconds, 3600)
  end)

  it("SSH off: shell, cancel the timer, cleared state", function()
    local r = security.on_ssh({}, { on = false })
    assert_false(r.state.maintenance.ssh)
    assert_nil(r.state.maintenance.ssh_until)
    assert_true(has_shell(r.commands, "ssh_off"))
    assert_eq(find(r.commands, "timer.cancel").name, "security.ssh_off")
  end)

  it("an SSH public key is accepted only while the access is open, and only a real one", function()
    local KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGq7T1kq0rQw0Yl2m1nV4p9ZxKqvB0cVd7mH3sJk2LtR owner@mac.local"
    local _, err = security.on_ssh_key({ maintenance = { ssh = false } }, { key = KEY })
    assert_eq(err.message, "SSH_CLOSED")
    local open = { maintenance = { ssh = true, ssh_keys = 0 } }
    for _, bad in ipairs({ "hello", "ssh-ed25519 short", "ssh-rsa AAAA; rm -rf /", KEY .. "\nssh-rsa AAAA", "ssh-dss " .. KEY:sub(13), KEY .. " 'quoted'" }) do
      local _, e = security.on_ssh_key(open, { key = bad })
      assert_eq(e and e.message, "SSH_KEY_INVALID", bad)
    end
    local r = security.on_ssh_key(open, { key = "  " .. KEY .. "\n" })
    local c = find(r.commands, "shell", "action", "ssh_key_add")
    assert_eq(c.args.key, KEY); assert_eq(r.state.maintenance.ssh_keys, 1)
    -- the same key again: still one (the page shows the file's count)
    assert_eq(security.on_ssh_key(open, { key = KEY }).state.maintenance.ssh_keys, 1)
    for i = 1, 6 do security.on_ssh_key(open, { key = "ssh-ed25519 " .. string.rep("B", 60 + i) }) end
    assert_eq(security.on_ssh_key(open, { key = KEY }).state.maintenance.ssh_keys, 5)
    assert_true(require("adapters.shell").is_pubkey("ssh-rsa " .. string.rep("A", 300) .. "== guillain@Mac-mini.local"))
    r = security.on_ssh_key({ maintenance = { ssh = true, ssh_keys = 2 } }, { clear = true })
    assert_true(has_shell(r.commands, "ssh_key_clear")); assert_eq(r.state.maintenance.ssh_keys, 0)
    -- the shell action gets the key as one argument, never inside the script text
    local argv = require("adapters.shell")._argv("ssh_key_add", { key = KEY })
    assert_eq(argv[#argv], KEY); assert_nil(argv[3]:find(KEY, 1, true))
  end)

  it("the one-hour timer turns SSH off", function()
    local r = security.on_timer({}, { name = "security.ssh_off" })
    assert_false(r.state.maintenance.ssh)
    assert_true(has_shell(r.commands, "ssh_off"))
    assert_nil(security.on_timer({}, { name = "other" }))
  end)

  it("MQTT on the LAN: state and the boot-script shell action with on/off", function()
    local r = security.on_mqtt_lan({}, { on = true })
    assert_true(r.state.maintenance.mqtt_lan)
    assert_eq(find(r.commands, "shell", "action", "mqtt_lan").args.on, true)
    local r2 = security.on_mqtt_lan({}, { on = false })
    assert_false(r2.state.maintenance.mqtt_lan)
    assert_eq(find(r2.commands, "shell", "action", "mqtt_lan").args.on, false)
  end)

  it("parent code: set the first time, persisted, marks it enabled", function()
    local r = security.on_parent_set({}, { code = "1234" })
    assert_true(r.state.maintenance.parent)
    assert_eq(security._parent_code(), "1234")
    local w = find(r.commands, "files.write_text")
    assert_match(w.path, "parent_code"); assert_match(w.text, "1234")
  end)

  it("parent code: only four digits", function()
    local _, e1 = security.on_parent_set({}, { code = "12" }); assert_eq(e1.code, "invalid_argument")
    local _, e2 = security.on_parent_set({}, { code = "abcd" }); assert_eq(e2.code, "invalid_argument")
  end)

  it("parent code: changing needs the current code", function()
    security._set_parent_code("1111")
    local _, e = security.on_parent_set({}, { code = "2222", current = "0000" })
    assert_eq(e.code, "forbidden")
    assert_eq(security._parent_code(), "1111")
    local r = security.on_parent_set({}, { code = "2222", current = "1111" })
    assert_true(r.state.maintenance.parent)
    assert_eq(security._parent_code(), "2222")
  end)

  it("parent code: clearing needs the current code, or a physical reset", function()
    security._set_parent_code("4321")
    local _, e = security.on_parent_clear({}, { current = "0000" })
    assert_eq(e.code, "forbidden")
    assert_eq(security._parent_code(), "4321")
    local r = security.on_parent_clear({}, { physical = true })
    assert_false(r.state.maintenance.parent)
    assert_nil(security._parent_code())
    assert_true(find(r.commands, "files.remove") ~= nil)
    -- a sound confirms the physical reset
    assert_true(find(r.commands, "emit") ~= nil)
  end)

  it("boot: reads the parent code from disk, the LAN flag, SSH always off", function()
    security._files = {
      exists = function(p) return p == "/data/openjooki/mqtt_lan" end,
      read_text = function(p) return p:find("parent_code") and "9876\n" or nil end,
    }
    local r = security.on_boot({})
    assert_false(r.state.maintenance.ssh)
    assert_true(r.state.maintenance.mqtt_lan)
    assert_true(r.state.maintenance.parent)
    assert_eq(security._parent_code(), "9876")
  end)
end)

describe("api.v1 parent gate", function()
  local function cmd(name, payload)
    return v1.on_cmd({}, { name = name, raw = require("vendor.json").encode(payload or {}), wall = 1 })
  end
  local function is_code_required(r)
    for _, c in ipairs(r.commands or {}) do
      if c.kind == "bus.publish" and c.topic == v1.TOPIC_ERROR and c.payload and c.payload.msg == "PARENT_CODE_REQUIRED" then return true end
    end
    return false
  end
  before_each(function() security._set_parent_code(nil) end)

  it("no gate when no parent code is set", function()
    assert_false(is_code_required(cmd("PLAYLIST_DELETE", { playlistId = "x" })))
  end)

  it("a protected command without the code is refused", function()
    security._set_parent_code("1234")
    assert_true(is_code_required(cmd("PLAYLIST_DELETE", { playlistId = "x" })))
    assert_true(is_code_required(cmd("OJ_SSH_ON", {})))
    assert_true(is_code_required(cmd("SET_WIFI", { ssid = "x" })))
  end)

  it("a protected command with the right code passes the gate", function()
    security._set_parent_code("1234")
    assert_false(is_code_required(cmd("PLAYLIST_DELETE", { playlistId = "x", code = "1234" })))
  end)

  it("playing music is never gated", function()
    security._set_parent_code("1234")
    assert_false(is_code_required(cmd("DO_PLAY", {})))
    assert_false(is_code_required(cmd("PLAYLIST_PLAY", { playlistId = "x" })))
    assert_false(is_code_required(cmd("SET_VOL", { vol = 30 })))
  end)

  it("the phone's time is never gated (the page sends it on its own, without the code)", function()
    security._set_parent_code("1234")
    local r = cmd("OJ_TIME", { utc = 1790780000 })       -- cmd() says wall = 1: the clock is unset
    assert_false(is_code_required(r))
    local set
    for _, c in ipairs(r.commands) do if c.kind == "shell" and c.action == "set_clock" then set = c.args.utc end end
    assert_eq(set, 1790780000)
  end)

  it("SET_WIFI says the Wi-Fi goes over Bluetooth, and runs nothing", function()
    local r = cmd("SET_WIFI", { ssid = "Home", password = "pass1234" })
    assert_eq(#r.commands, 1)
    assert_eq(r.commands[1].topic, v1.TOPIC_ERROR); assert_eq(r.commands[1].payload.msg, "WIFI_OVER_BLUETOOTH")
    assert_nil(r.commands[1].payload.info)       -- the password is never sent back to the pages
  end)
end)

-- the parent code lives in a module-local: clear it so it never leaks into other spec files
security._set_parent_code(nil)
