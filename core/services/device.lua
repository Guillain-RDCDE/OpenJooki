-- services.device: the Jooki as a physical object.
-- Volume and its limits, headphones and the amplifier, the ESP32's boot orders, the clock from the
-- page, disk usage, the name on the network. The rest of the object lives in four sub-modules this
-- one installs and whose handlers it re-exports under their old names (api.v1 reaches them here):
--   services.device.lights    the ring and the side dots, the Wi-Fi chase, the event pulses, the party
--   services.device.power     battery, cable, charging, heat, inactivity, the power-off sequence
--   services.device.radio     toy-safe, the radios, airplane mode and its boot restore, the system tags
--   services.device.buttons   presses, long presses, the tick that runs while a button is held
-- Owns:
--   state.audiocfg = { volume, headphones_en, shuffle_mode, random_start, repeat_mode, heart_press?, knob_mode?, hp_boost, upnp, toy_safe_maxvol }
--   state.limits   = { maxvol, fade, dim }   (set by bedtime; device applies them)
--   state.volume_int = { knob, pending, skipped } (physical position and ordered volume acknowledgments; private)
--   state.hp_int   = { mux, fresh, pending }  (wired headphones: usb_mux as last written, a reading to skip, a change waiting for its second reading; private)
--   state.device.esp32_up, state.device.diskUsage, state.device.hostname, state.device.ip, ...
-- (state.power and state.activity are power's, state.device.toy_safe / airplane and state.flags radio's.)
local util = require("services.util")
local lights = require("services.device.lights")
local power = require("services.device.power")
local radio = require("services.device.radio")
local buttons = require("services.device.buttons")
local volume_test = require("services.device.volume_test")
local device = {}
local DEFAULT_KIDS_MAX = 56 -- factory speaker ceiling on the shared 0–100 curve

local copy, emit, err = util.copy, util.emit, util.err
local function cfg(doc, key, default)
  local c = doc.config or {}
  if c[key] ~= nil then return c[key] end
  return default
end

-- ------------------------------------------------------------------ volume
local function clamp(v) v = math.floor(tonumber(v) or 0) if v < 0 then return 0 elseif v > 100 then return 100 end return v end

--- Requested volume through the kids/night ceilings, mute and the fade.
function device.effective_volume(doc, requested)
  local test = doc.volume_test_int or {}
  if test.active and test.phase ~= "restoring" then requested = test.phase == "pausing" and 0 or test.requested end
  if (doc.poweroff_int or {}).step then return 0 end
  local v = clamp(requested)
  local find = (doc.streaming_int or {}).find
  if (doc.upnp or {}).muted or (find and (find.skips or 0) > 0) then return 0 end
  if (doc.streaming_int or {}).random_start then return 0 end
  local lim = doc.limits or {}
  -- Older firmware still applies its fixed kids attenuation in the sound chip.
  -- Its percentages cannot also be capped on the new global scale.
  if (doc.device or {}).volume_api == 2 and (doc.device or {}).toy_safe ~= false then
    v = math.min(v, (doc.audiocfg or {}).toy_safe_maxvol or DEFAULT_KIDS_MAX)
  end
  if lim.maxvol and lim.maxvol < 100 and v > lim.maxvol then v = lim.maxvol end
  if lim.fade and lim.fade < 1 then v = math.floor(v * lim.fade + 0.5) end
  return v
end

-- The Linux mixer's level for this volume (docs/30). Wired headphones have no other control: the
-- level is the volume. The speaker's real level is set by the ESP32: from the dial on today's firmware,
-- so the mixer only takes off what is asked below the dial; from the volume itself with API 2.
-- One step of the mixer and of the dial is the same 0.4 dB.
local function mixer_level(doc, percent)
  if percent == 0 or (doc.audiocfg or {}).headphones_en == true then return percent end
  if (doc.device or {}).volume_api == 2 then return 100 end
  local knob = (doc.volume_int or {}).knob or 100    -- not read yet: the lower level, for that first second
  if percent >= knob then return 100 end
  return 100 - (knob - percent)
end

-- One route for every volume write, including temporary silence and output switches.
function device.volume_command(doc, percent)
  local global = (doc.device or {}).volume_api == 2
  return { kind = "host.volume", percent = percent, mixer = mixer_level(doc, percent), esp32 = global, global_volume = global,
           toy_safe = (doc.device or {}).toy_safe ~= false,
           maximum = percent == 0 and 0 or device.effective_volume(doc, 100) }
end

local function audiocfg_of(doc)
  local a = copy(doc.audiocfg or {})
  a.volume = a.volume or 40
  a.headphones_en = a.headphones_en == true
  a.shuffle_mode = a.shuffle_mode == true
  a.random_start = a.random_start == true
  a.continue_on_token_removal = a.continue_on_token_removal == true
  a.hp_boost = a.hp_boost == true
  a.upnp = a.upnp == true
  local max = a.toy_safe_maxvol
  a.toy_safe_maxvol = type(max) == "number" and max >= 0 and max <= 100 and max % 1 == 0 and max or DEFAULT_KIDS_MAX
  a.lights_off = a.lights_off == true
  a.repeat_mode = a.repeat_mode or 1
  return a
end
device.audiocfg_of = audiocfg_of   -- power (the cable, the power-off save) and buttons (the volume steps) read it here

local function audiocfg_path(doc) return util.data_dir(doc) .. "/audiocfg.json" end
device.audiocfg_path = audiocfg_path

-- Today's firmware cannot raise the speaker above its dial: the highest volume true to what is heard.
local function speaker_ceiling(doc)
  if (doc.device or {}).volume_api == 2 or (doc.audiocfg or {}).headphones_en == true then return nil end
  return (doc.volume_int or {}).knob
end

local function set_volume(doc, requested, persist)
  local a = audiocfg_of(doc)
  a.volume = clamp(requested)
  local ceiling = speaker_ceiling(doc)
  if ceiling and a.volume > ceiling then a.volume = ceiling end
  local state, after = { audiocfg = a }, doc
  -- A new volume from the page / a moved dial unmutes, as before. Limit and
  -- fade reapplications use on_apply_volume instead and preserve mute.
  if (doc.upnp or {}).muted then
    state.upnp = copy(doc.upnp); state.upnp.muted = nil
    after = copy(doc); after.upnp = state.upnp
  end
  local cmds = { device.volume_command(after, device.effective_volume(after, a.volume)) }
  if persist ~= false then cmds[#cmds + 1] = { kind = "files.write", path = audiocfg_path(doc), doc = a, version = 1 } end
  return { state = state, commands = cmds }
end
set_volume = volume_test.wrap(set_volume)
device.set_volume = set_volume

local HEART_PRESS = { none = true, next = true, pause = true }
local KNOB_MODE = { song = true, both = true, wind = true, start = true }

-- Shuffle and repeat arrive three ways: v2 device.set_config (schema-checked: a boolean and an integer
-- 0-2), v1 SET_CFG (the page sends booleans; repeat_mode may be a boolean -- true = all, false = none --
-- or a number, perhaps as a string) and the Spotify daemon's set_cfg (device.set_config_request: numbers,
-- perhaps as strings). One updater, with the union of the coercions those paths accepted: shuffle_mode is
-- on only when exactly true; repeat_mode: true -> 1, false -> 0, else tonumber, and an unreadable value
-- keeps the current mode (v2's values pass through unchanged by construction). `changes` keeps the
-- caller's raw values, which travel as they are in the audiocfg.changed event (streaming forwards the
-- change to the active service). The daemon's own report (opts.silent) raises no event: it would go
-- straight back to it. (v1 used to copy audiocfg without audiocfg_of's defaults; since boot always
-- stores a normalised audiocfg, the written file is the same.)
function device.update_config(doc, changes, opts)
  if changes.random_start ~= nil and type(changes.random_start) ~= "boolean" then
    return nil, err("invalid_argument", "random_start", "expected a boolean")
  end
  if changes.toy_safe_maxvol ~= nil then
    local v = changes.toy_safe_maxvol
    if type(v) ~= "number" or v < 0 or v > 100 or v % 1 ~= 0 then
      return nil, err("invalid_argument", "toy_safe_maxvol", "expected an integer from 0 to 100")
    end
  end
  if changes.lights_off ~= nil and type(changes.lights_off) ~= "boolean" then
    return nil, err("invalid_argument", "lights_off", "expected a boolean")
  end
  local a = audiocfg_of(doc)
  if changes.shuffle_mode ~= nil then a.shuffle_mode = changes.shuffle_mode == true end
  if changes.random_start ~= nil then a.random_start = changes.random_start end
  if type(changes.continue_on_token_removal) == "boolean" then a.continue_on_token_removal = changes.continue_on_token_removal end
  if changes.repeat_mode ~= nil then
    local m = changes.repeat_mode
    if m == true then m = 1 elseif m == false then m = 0 end
    a.repeat_mode = tonumber(m) or a.repeat_mode
  end
  -- the heart's short press (services.device.buttons); an unknown value keeps the current one
  if HEART_PRESS[changes.heart_press] then a.heart_press = changes.heart_press end
  -- and the track knob's (song / both / wind), the same way
  if KNOB_MODE[changes.knob_mode] then a.knob_mode = changes.knob_mode end
  local cmds = { { kind = "files.write", path = audiocfg_path(doc), doc = a, version = 1 } }
  -- louder headphones (util.hp_gain): only a real boolean, applied at once (kids mode still wins)
  if type(changes.hp_boost) == "boolean" and changes.hp_boost ~= audiocfg_of(doc).hp_boost then
    a.hp_boost = changes.hp_boost
    cmds[#cmds + 1] = util.hp_gain(a.hp_boost, (doc.device or {}).toy_safe ~= false)
  end
  -- play from other apps (services.upnp, adapters.upnp): only a real boolean
  if type(changes.upnp) == "boolean" then a.upnp = changes.upnp end
  if changes.toy_safe_maxvol ~= nil and changes.toy_safe_maxvol ~= a.toy_safe_maxvol then
    a.toy_safe_maxvol = changes.toy_safe_maxvol
    cmds[#cmds + 1] = emit("volume.apply", {})
  end
  if changes.toy_safe_maxvol ~= nil then a.toy_safe_maxvol_global = true end
  if changes.lights_off ~= nil and changes.lights_off ~= a.lights_off then
    a.lights_off = changes.lights_off
    cmds[#cmds + 1] = emit("lights.apply", {})
  end
  if not (opts and opts.silent) then
    cmds[#cmds + 1] = emit("audiocfg.changed", { shuffle_mode = changes.shuffle_mode, repeat_mode = changes.repeat_mode })
  end
  return { state = { audiocfg = a }, commands = cmds }
end

--- limits changed (bedtime): re-apply the current volume through the new chain.
function device.on_apply_volume(doc, ev)
  local a = audiocfg_of(doc)
  local c = device.volume_command(doc, device.effective_volume(doc, a.volume))
  c.force_mode = ev and ev.force == true
  return { commands = { c } }
end

-- Route the sound and, crucially, ENABLE THE AMPLIFIER. `/sys/kernel/htdrv/amp_en` = 1 for the
-- speaker, 0 for headphones (1.x did exactly this). It must be set at boot AND on a headphones
-- change: without the boot write, a Jooki that starts with no headphones plugged never turns its
-- amplifier on, so nothing comes out of the speaker (tokens and Spotify look like they play, in
-- silence) until some headphones transition happens to write it. 1.x set it at start-up; we must too.
-- Wired headphones go through the USB-C port (a passive USB-C to jack adapter); config
-- headphone_jack = false turns the detection off and keeps the speaker.
local function has_jack(doc) return cfg(doc, "headphone_jack", true) == true end
local function output_commands(doc, headphones)
  headphones = headphones and has_jack(doc) or false
  local dev = headphones and "headphones" or "speaker"
  return {
    { kind = "bus.publish", topic = "/j/audio/out/set_output_device", payload = dev },
    { kind = "bus.publish", topic = "/j/spotify/output/set_output_device", payload = dev },
    { kind = "files.write_text", path = "/sys/kernel/htdrv/amp_en", text = headphones and "0" or "1" },
  }
end

-- Controller replies contain only a result. Match them in publish order so
-- an older successful volume reply cannot acknowledge a newer mute request.
function device.on_volume_sent(doc, ev)
  local v = copy(doc.volume_int or {})
  v.pending = v.pending or {}; v.pending[#v.pending + 1] = ev.percent
  if #v.pending > 128 then table.remove(v.pending, 1); v.skipped = (v.skipped or 0) + 1 end
  return { state = { volume_int = v } }
end
function device.on_volume_ack(doc, ev)
  local v = copy(doc.volume_int or {})
  if (v.skipped or 0) > 0 then v.skipped = v.skipped - 1; return { state = { volume_int = v } } end
  if not v.pending or #v.pending == 0 then return nil end
  local p = table.remove(v.pending, 1)
  return { state = { volume_int = v }, commands = { emit("volume.confirmed", { percent = p, ok = ev.result == 0 }) } }
end

function device.on_gpio_volume(doc, ev)
  if ev.percent == nil then return nil end
  local position = clamp(ev.percent)
  local previous = (doc.volume_int or {}).knob
  local seen = copy(doc); seen.volume_int = copy(doc.volume_int or {}); seen.volume_int.knob = position
  local volume = audiocfg_of(doc).volume
  local ceiling = speaker_ceiling(seen)
  if previous == position then
    -- unchanged: a saved request stands, unless it shows more than the speaker can play
    if ceiling and volume > ceiling then return set_volume(seen, position) end
    return nil
  end
  local r
  if previous ~= nil then r = set_volume(seen, position)                     -- the dial moved: it takes over
  elseif ceiling and volume > ceiling then r = set_volume(seen, position)    -- first reading, below the saved volume
  elseif ceiling then r = { state = {}, commands = { device.volume_command(seen, device.effective_volume(seen, volume)) } }
  else r = { state = {} } end
  r.state.volume_int = seen.volume_int
  return r
end

-- Wired headphones, as Muuselabs' player.lua (on_knobs_state, pwr_plug) does it. The ESP32 reads the
-- detection line on the USB-C port, and only usb_mux pulls that line up: on battery, with usb_mux at
-- 0, it reads "plugged" with nothing there (what made 2.1.3 switch the detection off). So on battery
-- usb_mux is set to 1 first and the reading after it is skipped (the line needs 0.5 s to settle). A
-- charger in the port reads "plugged" too, so with the charger in the reading can only take the sound
-- off headphones, never put it on them (charging and headphones do not mix on this port anyway,
-- docs/24-hardware-and-lights.md). A charger that comes in just as the headphones were switched on,
-- or while a reading says they are out, is what the readings saw: services.device.power marks the
-- state (drop) and the next reading goes back to the speaker. Headphones that have played for a while
-- stay on (a splitter). A change is made only when two readings in a row agree,
-- which also covers the cable and the headphones coming out together. Muuselabs polled every
-- second; here a reading that wants a change asks for the next one 1 s later (device.hp_check), and
-- the ESP32's own plug event (hp_plugged) asks for one too.
local HP_CHECK_S = 1
local function hp_check() return { kind = "timer.once", name = "device.hp_check", seconds = HP_CHECK_S } end

local function headphones_reading(doc, a, seen, cmds)
  local hp = copy(doc.hp_int or {})
  local before = copy(hp)
  local switch = nil
  if not (doc.power or {}).connected and hp.mux ~= "1" then
    cmds[#cmds + 1] = { kind = "files.write_text", path = "/sys/kernel/htdrv/usb_mux", text = "1" }
    hp.mux, hp.fresh, hp.pending = "1", true, nil
    cmds[#cmds + 1] = hp_check()
  elseif hp.drop then
    hp.drop, hp.fresh, hp.pending, hp.new_on = nil, nil, nil, nil
    if a.headphones_en then switch = false end
  elseif hp.fresh then
    hp.fresh = nil
    cmds[#cmds + 1] = hp_check()
  elseif seen == a.headphones_en then
    hp.pending, hp.new_on = nil, nil
  elseif seen and (doc.power or {}).connected then
    hp.pending = nil
  elseif hp.pending == seen then
    hp.pending, switch = nil, seen
    hp.new_on = seen or nil
  else
    hp.pending = seen
    cmds[#cmds + 1] = hp_check()
  end
  local changed = hp.mux ~= before.mux or hp.fresh ~= before.fresh or hp.pending ~= before.pending
    or hp.new_on ~= before.new_on or hp.drop ~= before.drop
  return switch, changed and hp or nil
end

-- the sound to the headphones or the speaker: silent while it switches, then the volume again (1.x)
local function switch_output(doc, headphones, cmds)
  cmds[#cmds + 1] = device.volume_command(doc, 0)
  for _, c in ipairs(output_commands(doc, headphones)) do cmds[#cmds + 1] = c end   -- 1.x: Spotify follows too
  cmds[#cmds + 1] = device.volume_command(doc, device.effective_volume(doc, audiocfg_of(doc).volume))
  cmds[#cmds + 1] = { kind = "log", level = "info", key = "device.headphones", fields = { on = headphones } }
end

--- The ESP32's plug event: read the knobs again soon instead of at the next slow poll.
function device.on_hp_event(doc, ev)
  if ev.button ~= "hp_plugged" or not has_jack(doc) then return nil end
  return { commands = { hp_check() } }
end

--- The ESP32's knob report (polled slowly): volume position and headphones.
function device.on_knobs(doc, ev)
  local a = audiocfg_of(doc)
  local r = { state = {}, commands = {} }
  -- a knobs answer proves esp32_ctrl listens (and got the boot orders sent before the question)
  if not (doc.device or {}).esp32_up then
    local d = copy(doc.device or {}); d.esp32_up = true
    r.state.device = d
  end
  -- The original controller omits the capability; a valid legacy reading must
  -- also revoke a previously advertised global policy after a controller restart.
  local api = ev.volume_api
  if api == nil and ev.volume ~= nil then api = 0 end
  local changed = api ~= nil and (doc.device or {}).volume_api ~= api
  if changed then
    local d = r.state.device or copy(doc.device or {}); d.volume_api = api
    r.state.device = d
  end
  -- Reassert on every capable answer too: an ESP32 restart can leave the Linux
  -- broker connected while the chip has forgotten its host volume and ceiling.
  if api == 2 or changed then
    r.commands[#r.commands + 1] = emit("volume.apply", { force = changed })
  end
  local observed = copy(doc); observed.device = r.state.device or doc.device
  local s = device.on_gpio_volume(observed, { percent = ev.volume })
  if s then
    for k, v in pairs(s.state) do r.state[k] = v end
    for _, c in ipairs(s.commands or {}) do r.commands[#r.commands + 1] = c end
  end
  if has_jack(doc) and ev.headphones ~= nil then
    local switch, hp = headphones_reading(doc, a, ev.headphones, r.commands)
    if hp then r.state.hp_int = hp end
    if switch ~= nil then
      local a2 = r.state.audiocfg or a
      a2.headphones_en = switch
      r.state.audiocfg = a2
      local after = copy(doc); after.audiocfg = a2; after.device = r.state.device or doc.device
      switch_output(after, switch, r.commands)
    end
  end
  if not next(r.state) and #r.commands == 0 then return nil end
  return r
end

-- ------------------------------------------------------------------ the time, from the page
-- The Jooki has no clock of its own (no RTC): it takes the time from the Internet (ntpd). Away
-- from the Internet (holiday Wi-Fi without Internet, a phone's hotspot) it starts in 1970, and
-- night mode cannot tell night from day. The page gives it the phone's time at every connection;
-- the Jooki takes it only while its own clock is unset, so a correct clock (ntpd) is never moved.
local CLOCK_MIN, CLOCK_MAX = 1704067200, 4102444800     -- 2024-01-01, 2100-01-01 (UTC)
device.CLOCK_MIN = CLOCK_MIN

--- device.clock { utc = seconds }
function device.on_clock(_, p, ev)
  local utc = tonumber(p.utc)
  if not utc or utc < CLOCK_MIN or utc >= CLOCK_MAX then
    return nil, err("invalid_argument", "utc", "invalid utc")
  end
  local wall = tonumber(ev.wall) or os.time()
  if wall >= CLOCK_MIN then return {} end
  utc = math.floor(utc)
  return { commands = { { kind = "shell", action = "set_clock", args = { utc = utc } },
                        { kind = "log", level = "info", key = "device.clock_set", fields = { from = wall, to = utc } },
                        emit("clock.set", {}) } }
end

-- A Jooki 2 learns a Wi-Fi network only over Bluetooth (docs/wifi.html): the original
-- wifi_add_network.sh is the Jooki 1's (wpa_supplicant, absent here) and never reaches the chip,
-- and `esp32_cmd add_ap` crashes it (docs/20). Said plainly instead of pretending.
device.WIFI_OVER_BLUETOOTH = err("unavailable", "ssid", "WIFI_OVER_BLUETOOTH")

-- ------------------------------------------------------------------ disk usage (after uploads and at boot)
function device.on_disk_request(doc)
  return { commands = { { kind = "shell", action = "df", args = { dir = util.data_dir(doc) }, reply = "device.df" } } }
end

--- df -k output -> diskUsage { used, available (minus a 10 MB reserve), total, usedPercent } in KiB, like 1.x
function device.on_df(doc, ev)
  if ev.rc ~= 0 or not ev.out then return nil end
  local used, avail = tostring(ev.out):match("%s+(%d+)%s+(%d+)%s+%d+%%")
  used, avail = tonumber(used), tonumber(avail)
  if not used or not avail then return nil end
  local d = copy(doc.device or {})
  d.diskUsage = { used = used, available = math.max(avail - 10 * 1024, 0), total = used + avail, usedPercent = math.ceil(100 * used / math.max(used + avail, 1)) }
  return { state = { device = d } }
end

--- The bus is back (a reconnect, or the broker started again by adapters.broker_watch): the
--- ESP32's controller may have been restarted with it and knows nothing (NFC reader off: tokens
--- deaf). Say the boot orders again, until it answers; they are idempotent.
local on_bus_up   -- defined with the boot orders below

-- ------------------------------------------------------------------ boot / api
-- What the ESP32 must hear at boot: every notification once, the NFC reader on, the knobs.
-- All three are idempotent. The core may start before esp32_ctrl listens (the original start
-- script waited 1 s for it), so they are said again a little later, until the ESP32 side has
-- answered once (device.esp32_up, set by the knobs answer): tokens must never stay deaf.
local ESP32_RESEND_S = { 1, 3 }
local function esp32_init()
  return {
    { kind = "bus.publish", topic = "/j/esp32/output/device/send_all_notifications", payload = "" },
    { kind = "bus.publish", topic = "/j/esp32/output/nfc/mode/set", payload = "1" },
    { kind = "bus.publish", topic = "/j/esp32/output/knobs/state", payload = "" },
  }
end
on_bus_up = function(doc)
  local d = copy(doc.device or {})
  d.esp32_up = false
  d.volume_api = nil
  local cmds = esp32_init()
  cmds[#cmds + 1] = emit("volume.apply", { force = true })
  for i, s in ipairs({ 2, 5, 9 }) do cmds[#cmds + 1] = { kind = "timer.once", name = "device.esp32_init." .. i, seconds = s } end
  return { state = { device = d, volume_int = {} }, commands = cmds }
end
device.on_bus_up = function(doc) return on_bus_up(doc) end

--- Boot: the saved volume through the chain, the sound routed and the amplifier on, the ESP32's
--- orders, the knobs poll, the ready chime. (The sub-modules have their own boot handlers: the
--- flags and the airplane restore are radio's, the charger and the inactivity timer power's, the
--- Wi-Fi chase lights'; the long-press tick, device.tick, starts with the first button held.)
function device.on_boot(doc, ev)
  local a = audiocfg_of({ audiocfg = ev.audiocfg })
  local migrated = not (ev.audiocfg or {}).toy_safe_maxvol_global
  if migrated then
    -- Earlier trial builds expressed this extra ceiling inside the fixed kids
    -- attenuation. Convert its peak down to the common curve, never above it.
    local old = (ev.audiocfg or {}).toy_safe_maxvol
    if type(old) ~= "number" or old < 0 or old > 100 or old % 1 ~= 0 then old = 100 end
    local gain = old == 0 and 0 or (old == 1 and 0.005 or 10 ^ ((old - 100) / 50))
    gain = gain * (0.2 / 1.5)
    a.toy_safe_maxvol = gain < 0.005 and 0 or math.max(1, math.floor(100 + 50 * math.log10(gain)))
    a.toy_safe_maxvol_global = true
  end
  local after = copy(doc); after.audiocfg = a; after.device = copy(doc.device or {})
  after.device.toy_safe = not (ev.flags or {}).TOY_SAFE_OFF
  local cmds = { device.volume_command(after, device.effective_volume(after, a.volume)) }
  if migrated then cmds[#cmds + 1] = { kind = "files.write", path = audiocfg_path(doc), doc = a, version = 1 } end
  -- route the sound and turn the amplifier on at boot; without this the speaker stays silent until a
  -- headphones toggle (see output_commands). Always the speaker first, as 1.x did: headphones still
  -- plugged in are found again by the knobs within seconds, a stale "headphones on" never mutes it.
  a.headphones_en = false
  for _, c in ipairs(output_commands(doc, a.headphones_en)) do cmds[#cmds + 1] = c end
  -- the headphones gain, always said at boot: the factory start script restores whatever was stored
  cmds[#cmds + 1] = util.hp_gain(a.hp_boost, not (ev.flags or {}).TOY_SAFE_OFF)
  for _, c in ipairs(esp32_init()) do cmds[#cmds + 1] = c end
  for i, s in ipairs(ESP32_RESEND_S) do cmds[#cmds + 1] = { kind = "timer.once", name = "device.esp32_init." .. i, seconds = s } end
  cmds[#cmds + 1] = { kind = "timer.every", name = "device.knobs", seconds = 10 }
  if ev.quiet_boot then
    -- restarted by the Wi-Fi watchdog (services.network): no chime, maybe in the middle of the night
    cmds[#cmds + 1] = { kind = "files.remove", path = cfg(doc, "quiet_boot_file", "/data/openjooki/quiet_boot") }
    cmds[#cmds + 1] = { kind = "log", level = "info", key = "device.quiet_boot" }
  else
    cmds[#cmds + 1] = emit("system.event", { name = "Evt.Jooki.Ready" })
  end
  return { state = { audiocfg = a, volume_int = {}, limits = { maxvol = 100, fade = 1, dim = false } }, commands = cmds }
end

--- The Jooki's name on the network (name.local). web_ctrl, closed, serves only the system's own
--- name and sends any other one to Muuselabs' dead setup site: so the name is changed, not aliased.
--- "" goes back to the factory name (jooki2-XXXXXX, which stays the device id in /etc/hostname).
function device.normalize_name(raw)
  local n = tostring(raw or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.local$", "")
  return n
end
-- same rule as the shell action set_name (which checks again): a-z, 0-9, inner hyphens, 1-32
local function valid_name(s) return #s <= 32 and (s:match("^[a-z0-9]$") or s:match("^[a-z0-9][a-z0-9%-]*[a-z0-9]$")) ~= nil end
function device.on_set_name(doc, raw)
  local n = device.normalize_name(raw)
  if n == "localhost" or not (n == "" or valid_name(n)) then
    return nil, err("invalid_argument", "name", "invalid name (a-z, 0-9, -, 1 to 32 characters)")
  end
  local d = copy(doc.device or {})
  local effective = n ~= "" and n or tostring(d.id or ""):lower()
  if effective == "" then return nil, err("unavailable", "name", "factory name unknown") end
  d.hostname = effective .. ".local"
  local net = copy(doc.net or {})
  net.name = d.hostname
  return { state = { device = d, net = net },
           commands = { { kind = "shell", action = "set_name", args = { name = n } },
                        { kind = "log", level = "info", key = "device.name", fields = { name = effective } } } }
end

-- the boot orders said again (timers device.esp32_init.N), until esp32_ctrl has answered once
local function esp32_resend(doc)
  if (doc.device or {}).esp32_up then return nil end
  return { commands = esp32_init() }
end

-- the facade's own timers, each handler on its own name (kernel.dispatch on_timer)
local TIMERS = {
  ["device.knobs"] = function() return { commands = { { kind = "bus.publish", topic = "/j/esp32/output/knobs/state", payload = "" } } } end,
  ["device.hp_check"] = function() return { commands = { { kind = "bus.publish", topic = "/j/esp32/output/knobs/state", payload = "" } } } end,
  ["device.esp32_init.1"] = esp32_resend, ["device.esp32_init.2"] = esp32_resend, ["device.esp32_init.3"] = esp32_resend,
}
device.TIMERS = TIMERS

--- Any of the device's timers, by name, the sub-modules' included (the specs drive this one; the
--- kernel routes each name itself).
function device.on_timer(doc, ev)
  local fn = TIMERS[ev.name] or lights.TIMERS[ev.name] or power.TIMERS[ev.name] or radio.TIMERS[ev.name] or buttons.TIMERS[ev.name]
  if not fn then return nil end
  return fn(doc, ev)
end

-- the sub-modules' handlers under their old names (api.v1 and the other services reach them here)
device.on_lights_refresh, device.on_lights_event, device.on_wifi_anim = lights.on_lights_refresh, lights.on_lights_event, lights.on_wifi_anim
device.on_party, device.on_party_frame, device.on_party_end, device.wheel = lights.on_party, lights.on_party_frame, lights.on_party_end, lights.wheel
device.on_battery, device.on_plugged, device.on_charging = power.on_battery, power.on_plugged, power.on_charging
device.on_inactivity, device.on_activity = power.on_inactivity, power.on_activity
device.on_off_request, device.on_shutdown_request = power.on_off_request, power.on_shutdown_request
device.on_toy_safe, device.on_radio, device.on_airplane, device.on_airplane_end = radio.on_toy_safe, radio.on_radio, radio.on_airplane, radio.on_airplane_end
device.on_button, device.on_tick = buttons.on_button, buttons.on_tick

local S = {}
S.volume = { type = "object", required = { "percent" }, properties = { percent = { type = "integer", minimum = 0, maximum = 100 } }, additionalProperties = false }
S.config = { type = "object", properties = { shuffle_mode = { type = "boolean" }, random_start = { type = "boolean" }, repeat_mode = { type = "integer", minimum = 0, maximum = 2 },
                                              heart_press = { type = "string", enum = { "none", "next", "pause" } },
                                              knob_mode = { type = "string", enum = { "song", "both", "wind", "start" } },
                                              continue_on_token_removal = { type = "boolean" }, hp_boost = { type = "boolean" },
                                              upnp = { type = "boolean" }, toy_safe_maxvol = { type = "integer", minimum = 0, maximum = 100 }, lights_off = { type = "boolean" } }, additionalProperties = false }
S.name = { type = "object", required = { "name" }, properties = { name = { type = "string", maxLength = 40 } }, additionalProperties = false }
S.wifi = { type = "object", required = { "ssid" }, properties = { ssid = { type = "string", minLength = 1, maxLength = 32 }, password = { type = "string", maxLength = 63 } }, additionalProperties = false }
S.clock = { type = "object", required = { "utc" }, properties = { utc = { type = "integer" } }, additionalProperties = false }
S.enable, S.airplane = radio.schemas.enable, radio.schemas.airplane
device.schemas = S

function device.install(api, dispatch)
  volume_test.install(api, dispatch)
  dispatch.on("boot", "device", device.on_boot)
  dispatch.on("bus.up", "device", device.on_bus_up)
  for name, fn in pairs(TIMERS) do dispatch.on_timer(name, "device", fn) end
  dispatch.on("gpio.volume", "device", device.on_gpio_volume)
  dispatch.on("knobs", "device", device.on_knobs)
  dispatch.on("gpio.button", "device", device.on_hp_event)
  dispatch.on("volume.sent", "device", device.on_volume_sent)
  dispatch.on("volume.ack", "device", device.on_volume_ack)
  dispatch.on("volume.apply", "device", device.on_apply_volume)
  dispatch.on("limits.changed", "device", device.on_apply_volume)   -- then lights repaints (installed below)
  dispatch.on("upload.done", "device", device.on_disk_request)
  dispatch.on("boot", "device.disk", device.on_disk_request)
  dispatch.on("device.df", "device", device.on_df)
  api.command("device.set_volume", S.volume, function(doc, p) return set_volume(doc, p.percent) end)
  api.command("device.set_config", S.config, function(doc, p) return device.update_config(doc, p) end)
  -- the Spotify daemon reporting its own shuffle/repeat (services.streaming): saved, not echoed back
  dispatch.on("device.set_config_request", "device", function(doc, ev)
    return device.update_config(doc, { shuffle_mode = ev.shuffle_mode, repeat_mode = ev.repeat_mode }, { silent = true })
  end)
  api.command("device.set_name", S.name, function(doc, p) return device.on_set_name(doc, p.name) end)
  api.command("device.set_wifi", S.wifi, function() return nil, device.WIFI_OVER_BLUETOOTH end)
  api.command("device.clock", S.clock, function(doc, p, ev) return device.on_clock(doc, p, ev) end)
  api.command("device.speak_info", nil, function() return { commands = { { kind = "shell", action = "speak_info" }, emit("playback.pause_request", { source = "speak_info" }) } } end)
  -- the rest of the object, each part with its own handlers and timers
  lights.install(api, dispatch)
  power.install(api, dispatch)
  radio.install(api, dispatch)
  buttons.install(api, dispatch)
end

return device
