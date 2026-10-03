-- services.playback.sounds: the system sounds (system.event: the ready chime, the warnings, the
-- power-off sound) on audio_ctrl's stream 3, with the music (stream 7) paused meanwhile, continued
-- after, and then `after` run. A second, tiny machine next to the music's: playback_int.sys =
-- { name, after, resume_music } while a sound plays. Owns state.system = { tracks } (the sound
-- catalogue, read at boot). The working table (pb_of / st) and the audio_ctrl command are the
-- facade's, services.playback: reached at call time, since the facade requires this module; the
-- engine's events on stream 3 come through the facade's on_audio.
local util = require("services.util")
local sounds = {}

local emit, is_playing = util.emit, util.is_playing
local function facade() return require("services.playback") end

-- system sounds -----------------------------------------------------------------
local function sound_uri(doc, name)
  local sys = doc.system or {}
  local t = sys.tracks and sys.tracks[name]
  if not (t and t.filename) then return nil end
  return "file://" .. ((doc.config and doc.config.system_dir) or "/jooki/app/system") .. "/" .. t.filename
end

--- system.event { name, after? }: play the sound if there is one, pausing the music meanwhile.
function sounds.on_system_event(doc, ev)
  local uri = sound_uri(doc, ev.name)
  local cmds = { emit("lights.event", { name = ev.name }) }
  if not uri then
    if ev.after then cmds[#cmds + 1] = { kind = "emit", event = ev.after } end
    return { commands = cmds }
  end
  local playback = facade()
  local cmd_audio, MUSIC, SOUND = playback.cmd_audio, playback.MUSIC, playback.SOUND
  local pb = playback.pb_of(doc)
  local resume_music = false
  if is_playing(doc) and not ev.no_pause then
    cmds[#cmds + 1] = cmd_audio("pauz", MUSIC)
    resume_music = true
  end
  if pb.sys and pb.sys.name then cmds[#cmds + 1] = cmd_audio("stop", SOUND) end
  pb.sys = { name = ev.name, after = ev.after, resume_music = resume_music or (pb.sys and pb.sys.resume_music) or nil }
  cmds[#cmds + 1] = cmd_audio("play", SOUND, uri)
  return { state = playback.st(pb), commands = cmds }
end

--- The engine's report on stream 3 (`kind` = ended | stopped | ...): the music continues, `after` runs.
function sounds.on_sound_audio(doc, _, kind)
  if kind ~= "ended" and kind ~= "stopped" then return nil end
  local playback = facade()
  local pb = playback.pb_of(doc)
  local sys = pb.sys
  if not sys then return nil end
  local cmds = {}
  if sys.resume_music and pb.state ~= "idle" then cmds[#cmds + 1] = playback.cmd_audio("cont", playback.MUSIC) end
  if sys.after then cmds[#cmds + 1] = { kind = "emit", event = sys.after } end
  pb.sys = nil
  return { state = playback.st(pb), commands = cmds }
end

-- boot / install ----------------------------------------------------------------
--- Boot: the sound catalogue (the system playlist's tracks.json, read by main).
function sounds.on_boot(_, ev)
  return { state = { system = ev.system or { tracks = {} } } }
end

function sounds.install(_, dispatch)
  dispatch.on("boot", "playback.sounds", sounds.on_boot)
  dispatch.on("system.event", "playback.sounds", sounds.on_system_event)
end

return sounds
