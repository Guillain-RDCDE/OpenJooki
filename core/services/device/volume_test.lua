-- A short, explicit audition of a settings ceiling, including before night starts.
-- aplay uses the same ALSA route as audio_ctrl without replacing its paused file/radio.
-- Nothing is saved: the requested music volume and audiobook position stay intact.
local util = require("services.util")
local test = {}
local copy, emit, err = util.copy, util.emit, util.err
local function device() return require("services.device") end
local function playback() return require("services.playback") end
local function active(doc) return (doc.volume_test_int or {}).active == true end
local function merged(doc, state)
  local d = copy(doc)
  for k, v in pairs(state or {}) do d[k] = v end
  return d
end
local function status(v, error)
  return { active = v.active == true, target = v.target, percent = v.percent, error = error }
end
local function result(v, commands, error)
  return { state = { volume_test_int = v, volume_test = status(v, error) }, commands = commands }
end
local function same_track(doc, v)
  local n = (doc.playback or {}).now or {}
  local old = v.track or {}
  return n.uri == old.uri and n.track == old.track and n.playlist == old.playlist and n.service == old.service
end
local function stop(v)
  return { kind = "shell", action = "volume_test_stop", args = { id = v.id } }
end

-- User transport/volume actions take over immediately, ahead of their commands.
-- Wrapped handlers see a document without the temporary volume override.
function test.interrupt(doc, fn, ...)
  if not active(doc) then return fn(doc, ...) end
  local r = test.cancel(doc, false)
  local next_result, failure = fn(merged(doc, r.state), ...)
  if failure then return nil, failure end
  for k, v in pairs((next_result or {}).state or {}) do r.state[k] = v end
  for _, c in ipairs((next_result or {}).commands or {}) do
    if c.kind == "host.volume" then
      for i = #r.commands, 1, -1 do if r.commands[i].kind == "host.volume" then table.remove(r.commands, i) end end
      break
    end
  end
  for _, c in ipairs((next_result or {}).commands or {}) do r.commands[#r.commands + 1] = c end
  return r
end
function test.wrap(fn)
  return function(doc, ...) return test.interrupt(doc, fn, ...) end
end

function test.cancel(doc, resume, error)
  local v = copy(doc.volume_test_int or {})
  if not v.active then return nil end
  v.active = false
  local d = copy(doc); d.volume_test_int = v
  local cmds = { stop(v), { kind = "timer.cancel", name = "volume_test.poll" },
    device().volume_command(d, device().effective_volume(d, (d.audiocfg or {}).volume or 40)) }
  if resume and v.resume and same_track(doc, v) and (doc.playback or {}).state == "paused" then
    local svc = (v.track or {}).service
    if svc == "SPOTIFY" or svc == "DEEZER" then
      for _, c in ipairs(require("services.streaming").transport(svc, "resume")) do cmds[#cmds + 1] = c end
    else
      -- Continue the still-loaded stream, without the audiobook's normal pause rewind.
      cmds[#cmds + 1] = playback().cmd_audio("cont", playback().MUSIC)
    end
  end
  return result(v, cmds, error)
end

local function play(doc, v)
  v.phase, v.ticks, v.deadline = "playing", 0, nil
  return result(v, { { kind = "shell", action = "volume_test_start", args = {
    id = v.id, file = ((doc.config or {}).web_public_dir or "/tmp/web_ctrl_dirs/public") .. "/volume-test.wav",
    output = v.headphones and "headphones" or "speaker" }, reply = "volume_test.started", ref = v.id } })
end
local function set_level(doc, v)
  v.phase, v.ticks, v.deadline = "setting", 0, nil
  local d = copy(doc); d.volume_test_int = v
  local wanted = v.requested
  -- Stock firmware cannot raise a speaker above its dial. Show the actual ceiling.
  if (doc.device or {}).volume_api ~= 2 and not v.headphones then wanted = math.min(wanted, (doc.volume_int or {}).knob or wanted) end
  v.requested = wanted
  v.percent = device().effective_volume(d, wanted)
  local cmds = { device().volume_command(d, v.percent) }
  if not v.api2 then cmds[#cmds + 1] = emit("volume_test.ready", { id = v.id }) end
  return result(v, cmds)
end
local function ready(doc, v)
  if not v.muted then return nil end
  if v.resume and (doc.playback or {}).state ~= "paused" then return nil end
  return set_level(doc, v)
end

local function restore(doc, error)
  local v = copy(doc.volume_test_int)
  v.phase, v.ticks, v.error, v.deadline = "restoring", 0, error, nil
  local d = copy(doc); d.volume_test_int = v
  v.restore_percent = device().effective_volume(d, (doc.audiocfg or {}).volume or 40)
  local cmds = { stop(v), device().volume_command(d, v.restore_percent) }
  if not v.api2 then cmds[#cmds + 1] = emit("volume_test.restored", { id = v.id }) end
  return result(v, cmds)
end

function test.on_restored(doc, ev)
  if not active(doc) or doc.volume_test_int.phase ~= "restoring" or (ev and ev.id ~= doc.volume_test_int.id) then return nil end
  return test.cancel(doc, true, doc.volume_test_int.error)
end

function test.on_request(doc, p)
  if p.target ~= "kids" and p.target ~= "night" then return nil, err("invalid_argument", "target", "expected kids or night") end
  if active(doc) or (doc.playback_int or {}).sys or (doc.poweroff_int or {}).step
      or (doc.streaming_int or {}).random_start or (doc.streaming_int or {}).find
      or (doc.playback or {}).state == "starting" then return nil, err("conflict", "", "VOLUME_TEST_BUSY") end
  if (doc.upnp or {}).muted then return nil, err("conflict", "", "VOLUME_TEST_MUTED") end
  local a, d = doc.audiocfg or {}, doc.device or {}
  if p.target == "kids" and (d.volume_api ~= 2 or d.toy_safe == false) then
    return nil, err("unavailable", "target", "VOLUME_TEST_UNAVAILABLE")
  end
  local requested = p.target == "kids" and a.toy_safe_maxvol or ((doc.bedtime or {}).cfg or {}).maxvol
  if type(requested) ~= "number" then return nil, err("unavailable", "target", "VOLUME_TEST_UNAVAILABLE") end
  local prior = doc.volume_test_int or {}
  local v = { active = true, id = (prior.id or 0) + 1, target = p.target, requested = requested,
    api2 = d.volume_api == 2, headphones = a.headphones_en == true, phase = "pausing", ticks = 0,
    resume = (doc.playback or {}).state == "playing", track = copy((doc.playback or {}).now) }
  local cmds = { device().volume_command(doc, 0), { kind = "timer.every", name = "volume_test.poll", seconds = 0.1 } }
  if v.resume then
    local svc = (v.track or {}).service
    if svc == "SPOTIFY" or svc == "DEEZER" then
      for _, c in ipairs(require("services.streaming").transport(svc, "pause")) do cmds[#cmds + 1] = c end
    else cmds[#cmds + 1] = playback().cmd_audio("pauz", playback().MUSIC) end
  end
  if not v.api2 then cmds[#cmds + 1] = emit("volume_test.muted", { id = v.id }) end
  return result(v, cmds)
end

function test.on_muted(doc, ev)
  if not active(doc) or doc.volume_test_int.phase ~= "pausing" or (ev and ev.id ~= doc.volume_test_int.id) then return nil end
  local v = copy(doc.volume_test_int); v.muted = true
  return ready(doc, v) or result(v)
end
function test.on_ready(doc, ev)
  if not active(doc) or doc.volume_test_int.phase ~= "setting" or (ev and ev.id ~= doc.volume_test_int.id) then return nil end
  return play(doc, copy(doc.volume_test_int))
end
function test.on_confirmed(doc, ev)
  local v = doc.volume_test_int or {}
  if not v.active or not v.api2 then return nil end
  local expected = v.phase == "pausing" and 0 or v.phase == "setting" and v.percent or v.phase == "restoring" and v.restore_percent or nil
  if expected == nil or ev.percent ~= expected then return nil end
  if not ev.ok then return test.cancel(doc, false, "VOLUME_TEST_FAILED") end
  if v.phase == "restoring" then return test.on_restored(doc) end
  if v.phase == "pausing" then return test.on_muted(doc) end
  return test.on_ready(doc)
end
function test.on_playback(doc)
  if not active(doc) then return nil end
  local v = doc.volume_test_int
  if not same_track(doc, v) then return test.cancel(doc, false) end
  if v.phase == "pausing" then return ready(doc, copy(v)) end
  -- A remote Spotify app or an engine event took over: restore the normal volume.
  if v.resume and (doc.playback or {}).state ~= "paused" then return test.cancel(doc, false) end
end
function test.on_poll(doc, ev)
  if not active(doc) then return nil end
  local v = copy(doc.volume_test_int)
  v.ticks = v.ticks + 1
  if v.headphones ~= ((doc.audiocfg or {}).headphones_en == true) or v.api2 ~= ((doc.device or {}).volume_api == 2) then
    return test.cancel(doc, false, "VOLUME_TEST_FAILED")
  end
  local now = ev and ev.now
  if now then v.deadline = v.deadline or now + 3 end
  if (now and now >= v.deadline) or (not now and v.ticks >= 30) then
    if v.phase == "restoring" then return test.cancel(doc, false, "VOLUME_TEST_FAILED") end
    return restore(doc, "VOLUME_TEST_FAILED")
  end
  if v.phase ~= "playing" then return result(v) end
  return result(v, { { kind = "files.read_text", path = "/tmp/oj-volume-test." .. v.id .. ".status", reply = "volume_test.done", ref = v.id } })
end
function test.on_started(doc, ev)
  if active(doc) and ev.ref == doc.volume_test_int.id and ev.rc ~= 0 then return restore(doc, "VOLUME_TEST_FAILED") end
end
function test.on_done(doc, ev)
  -- nothing yet, or read in the instant the shell opens the file to write its status
  if not active(doc) or ev.ref ~= doc.volume_test_int.id or tonumber(ev.text) == nil then return nil end
  if doc.volume_test_int.phase ~= "playing" then return nil end
  return restore(doc, tonumber(ev.text) ~= 0 and "VOLUME_TEST_FAILED" or nil)
end
function test.install(api, dispatch)
  dispatch.on("boot", "device.volume_test", function() return { state = { volume_test = { active = false }, volume_test_int = {} } } end)
  dispatch.on("volume.confirmed", "device.volume_test", test.on_confirmed)
  dispatch.on("volume_test.muted", "device.volume_test", test.on_muted)
  dispatch.on("volume_test.ready", "device.volume_test", test.on_ready)
  dispatch.on("volume_test.restored", "device.volume_test", test.on_restored)
  dispatch.on("volume_test.started", "device.volume_test", test.on_started)
  dispatch.on("volume_test.done", "device.volume_test", test.on_done)
  dispatch.on("playback.changed", "device.volume_test", test.on_playback)
  dispatch.on_timer("volume_test.poll", "device.volume_test", test.on_poll)
  api.command("device.test_volume", { type = "object", required = { "target" }, properties = { target = { type = "string", enum = { "kids", "night" } } }, additionalProperties = false }, test.on_request)
end
return test
