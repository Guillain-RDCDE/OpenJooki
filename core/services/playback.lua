-- services.playback: what plays, in what order, and where it resumes.
-- The transport and the music state machine; the facade of three sub-modules it installs and whose
-- handlers it re-exports under their old names:
--   services.playback.sounds   the system sounds on stream 3, the music paused and continued around them
--   services.playback.resume   resume.json: where an audiobook starts again, the bookkeeping, the save timer
--   services.playback.queue    the order of a playlist's tracks (identity or a memoised shuffle)
-- Owns state.playback (what the page sees):
--   { state = "idle"|"starting"|"playing"|"paused"|"ended",
--     position_ms, now = { playlist, index, queue_pos, track, uri, service, audiobook,
--                          title, album, artist, duration_ms, has_next, has_prev, image },
--     paused_by, paused_at, resume_ms (pending seek) }
-- and state.playback_int (its own bookkeeping, never published):
--   { last = { [playlist] = index }, shuffle = { [playlist] = { order... } }, seed (set at boot from
--     the clock), sys = { name, after, resume_music } (a system sound in progress), resume_dirty }
-- The handlers work on the two merged into one table (pb_of) and split them again on the way out (st);
-- the sub-modules reach pb_of, st and cmd_audio here, at call time.
-- (state.resume is services.playback.resume's, state.system services.playback.sounds'.)
-- Talks to audio_ctrl: stream 7 = music, stream 3 = system sounds (docs/22 §4.4).
local util = require("services.util")
local sounds = require("services.playback.sounds")
local resume_rules = require("services.playback.resume")
local queue = require("services.playback.queue")
local playback = {}

local MUSIC, SOUND = 7, 3
local BACK_PAUSE, BACK_TIMER, MIN_BACK = resume_rules.BACK_PAUSE, resume_rules.BACK_TIMER, resume_rules.MIN_BACK
local AUDIO_OUT = "/j/audio/out/"
local INT = { last = true, shuffle = true, seed = true, sys = true, resume_dirty = true }   -- the playback_int keys

local copy, emit, is_playing = util.copy, util.emit, util.is_playing
local queue_for, index_of = queue.queue_for, queue.index_of
local resume_copy, note_position, note_ended, write_resume = resume_rules.resume_copy, resume_rules.note_position, resume_rules.note_ended, resume_rules.write_resume

local function cmd_audio(action, id, arg)
  local payload = tostring(id)
  if arg ~= nil then payload = payload .. "\t" .. tostring(arg) end
  return { kind = "bus.publish", topic = AUDIO_OUT .. action, payload = payload }
end
playback.cmd_audio = cmd_audio

local function pb_of(doc)
  local pb = copy(doc.playback or {})
  for k, v in pairs(doc.playback_int or {}) do pb[k] = copy(v) end
  pb.state = pb.state or "idle"
  pb.last = pb.last or {}
  pb.shuffle = pb.shuffle or {}
  return pb
end
playback.pb_of = pb_of

--- The working table split back into the two sub-trees a handler returns: { playback, playback_int }.
local function st(pb)
  local pub, int = {}, {}
  for k, v in pairs(pb) do if INT[k] then int[k] = v else pub[k] = v end end
  return { playback = pub, playback_int = int }
end
playback.st = st

--- For an audiobook: the index and the position to start at, from resume.json (services.playback.resume).
playback.resume_for = resume_rules.resume_for

-- ------------------------------------------------------------------ now-playing
local function describe(doc, playlist_id, p, index, queue_pos, n)
  local tid = p.tracks[index]
  local t = (doc.library and doc.library.tracks and doc.library.tracks[tid]) or {}
  local uri
  if t.isUrl then uri = t.filename else uri = "file://" .. tostring(t.filename or "") end
  return {
    playlist = playlist_id, index = index, queue_pos = queue_pos, track = tid, uri = uri,
    service = t.isUrl and "STREAM" or "FILE", audiobook = p.audiobook == true,
    title = t.title, album = t.album, artist = t.artist,
    duration_ms = math.floor((tonumber(t.duration) or 0) * 1000),
    has_next = queue_pos < n, has_prev = queue_pos > 1,
    image = t.hasImage and ("/artwork/" .. tid .. ".jpg") or nil, source = p.title,
  }
end

--- Start (or continue) a track of a playlist. Returns the handler result.
local function start(doc, pb, playlist_id, opts)
  opts = opts or {}
  local lib = doc.library or { playlists = {}, tracks = {} }
  local p = lib.playlists[playlist_id]
  if not p then return nil, { code = "not_found", field = "playlist", message = "unknown playlist" } end
  local has_streaming, streaming = pcall(require, "services.streaming")
  local svc = has_streaming and streaming.service_of(p)
  if svc then
    local now, cmds0 = streaming.start(doc, playlist_id, p)
    if not now then return { commands = cmds0 } end
    local cmds = {}
    if pb.state == "playing" or pb.state == "paused" or pb.state == "starting" then
      if pb.now and pb.now.service == "FILE" then cmds[#cmds + 1] = cmd_audio("stop", MUSIC) end
    end
    for _, c in ipairs(cmds0) do cmds[#cmds + 1] = c end
    pb.now, pb.state, pb.position_ms, pb.resume_ms = now, "starting", 0, nil
    pb.paused_by, pb.paused_at = nil, nil
    cmds[#cmds + 1] = emit("playback.changed", { state = "starting" })
    return { state = st(pb), commands = cmds }
  end
  local n = #(p.tracks or {})
  local cmds = {}
  if n == 0 then
    cmds[#cmds + 1] = emit("system.event", { name = "Evt.Character.Detect.Empty" })
    return { commands = cmds }
  end
  local q = queue_for(doc, pb, playlist_id, p)
  local index, queue_pos, seek_ms = nil, nil, nil
  if opts.index and p.tracks[opts.index] then
    index = opts.index; queue_pos = index_of(q, index) or 1
  elseif opts.queue_pos and q[opts.queue_pos] then
    queue_pos = opts.queue_pos; index = q[queue_pos]
  else
    if p.audiobook then
      -- an audiobook follows its saved position only; without one it starts at chapter 1 (1.3 rule)
      index, seek_ms = playback.resume_for(doc.resume, playlist_id, p.tracks)
      index = index or 1
    end
    index = index or pb.last[playlist_id] or 1
    if not p.tracks[index] then index = 1 end
  end
  queue_pos = queue_pos or index_of(q, index) or 1
  local now = describe(doc, playlist_id, p, index, queue_pos, n)
  -- same track already loaded?
  if pb.now and pb.now.playlist == playlist_id and pb.now.index == index and not opts.restart then
    if pb.state == "playing" or pb.state == "starting" then return { state = st(pb), commands = cmds } end
    if pb.state == "paused" then return playback.resume_paused(doc, pb, opts.now_s) end
  end
  local streamed = pb.now and (pb.now.service == "SPOTIFY" or pb.now.service == "DEEZER")
  if has_streaming and (streamed or (doc.spotify and doc.spotify.playing)) then
    -- the last one to start wins: a token put on while Spotify plays pauses Spotify
    for _, c in ipairs(streaming.transport(streamed and pb.now.service or "SPOTIFY", "stop")) do cmds[#cmds + 1] = c end
  end
  if not streamed and (pb.state == "playing" or pb.state == "paused" or pb.state == "starting") then
    cmds[#cmds + 1] = cmd_audio("stop", MUSIC)
  end
  pb.last[playlist_id] = index
  pb.now = now
  pb.state = "starting"
  pb.position_ms = 0
  pb.resume_ms = seek_ms
  pb.paused_by, pb.paused_at = nil, nil
  cmds[#cmds + 1] = cmd_audio("play", MUSIC, now.uri)
  cmds[#cmds + 1] = emit("playback.changed", { state = "starting" })
  return { state = st(pb), commands = cmds }
end

--- Continue after a pause, with the rewind rules: short pause -> exactly where it
--- was; more than a minute (or the Jooki turned off) -> 15 s back; paused by the
--- sleep timer -> the faded minute is played again (60 s back).
function playback.resume_paused(_, pb, now_s)
  local cmds = {}
  if pb.now and pb.now.audiobook and pb.now.service == "FILE" and pb.paused_at and now_s then
    local long = (now_s - pb.paused_at) > 60
    if long or pb.paused_by == "sleep_timer" then
      local back = pb.paused_by == "sleep_timer" and BACK_TIMER or BACK_PAUSE
      local target = (pb.position_ms or 0) - back
      if target >= MIN_BACK then
        cmds[#cmds + 1] = cmd_audio("seek", MUSIC, target)
        cmds[#cmds + 1] = { kind = "log", level = "info", key = "playback.rewind", fields = { ms = target } }
      end
    end
  end
  cmds[#cmds + 1] = cmd_audio("cont", MUSIC)
  pb.paused_by, pb.paused_at = nil, nil
  return { state = st(pb), commands = cmds }
end

-- ------------------------------------------------------------------ handlers
function playback.on_request(doc, ev)
  local pb = pb_of(doc)
  local r, err = start(doc, pb, ev.playlist, { index = ev.index, queue_pos = ev.queue_pos, now_s = ev.now, restart = ev.restart })
  if not r then return { commands = { { kind = "log", level = "warn", key = "playback.request_failed", fields = { playlist = tostring(ev.playlist), err = err.message } } } } end
  return r
end

local function is_streaming(pb) return pb.now and (pb.now.service == "SPOTIFY" or pb.now.service == "DEEZER") end
local function stream_cmds(pb, action, arg) return { commands = require("services.streaming").transport(pb.now.service, action, arg) } end

function playback.on_pause(doc, ev)
  local pb = pb_of(doc)
  if not is_playing(doc) then return nil end
  if is_streaming(pb) then
    -- taking a token off pauses what a token started, not Spotify started from the phone
    if ev.source == "token" and not pb.now.playlist then return nil end
    return stream_cmds(pb, "pause")
  end
  pb.paused_by, pb.paused_at = ev.source, ev.now
  if pb.now and pb.now.service == "STREAM" then
    return { state = st(pb), commands = { cmd_audio("stop", MUSIC) } }
  end
  return { state = st(pb), commands = { cmd_audio("pauz", MUSIC) } }
end

function playback.on_resume(doc, ev)
  local pb = pb_of(doc)
  if pb.state == "paused" and is_streaming(pb) then return stream_cmds(pb, "resume") end
  -- Spotify started from the phone has no playlist of ours: "play" asks the daemon to continue
  if is_streaming(pb) and not pb.now.playlist and pb.state ~= "playing" then return stream_cmds(pb, "resume") end
  if pb.state == "paused" then return playback.resume_paused(doc, pb, ev.now) end
  if (pb.state == "ended" or pb.state == "idle") and pb.now then
    return start(doc, pb, pb.now.playlist, { index = pb.now.index, restart = true, now_s = ev.now })
  end
  return nil
end

function playback.on_toggle(doc, ev)
  if is_playing(doc) then return playback.on_pause(doc, ev) end
  return playback.on_resume(doc, ev)
end

local function step(doc, pb, delta, ev)
  local now = pb.now
  if not now then return nil end
  if not ev.forced and not is_playing(doc) then return nil end
  local p = doc.library and doc.library.playlists[now.playlist]
  if not p then return nil end
  local q = queue_for(doc, pb, now.playlist, p)
  local cfg = doc.audiocfg or {}
  local repeat_all = cfg.repeat_mode == 1 and not p.audiobook
  local pos = now.queue_pos + delta
  if pos < 1 or pos > #q then
    if not repeat_all then return nil end
    pos = pos < 1 and #q or 1
  end
  return start(doc, pb, now.playlist, { queue_pos = pos, restart = true, now_s = ev.now })
end

function playback.on_next(doc, ev)
  local pb = pb_of(doc)
  if is_streaming(pb) then return stream_cmds(pb, "next") end
  return step(doc, pb, 1, ev)
end

function playback.on_prev(doc, ev)
  local pb = pb_of(doc)
  if not pb.now then return nil end
  if is_streaming(pb) then return stream_cmds(pb, "prev") end
  if not ev.forced and not is_playing(doc) then return nil end
  if (pb.position_ms or 0) > 5000 then
    pb.position_ms = 0
    return { state = st(pb), commands = { cmd_audio("seek", MUSIC, 1) } }
  end
  return step(doc, pb, -1, ev)
end

function playback.on_seek(doc, ev)
  local pb = pb_of(doc)
  if not pb.now or pb.now.service == "STREAM" then return nil end
  local ms = math.max(1, math.floor(tonumber(ev.ms) or 1))
  if is_streaming(pb) then return stream_cmds(pb, "seek", ms) end
  pb.position_ms = ms
  return { state = st(pb), commands = { cmd_audio("seek", MUSIC, ms) } }
end

function playback.on_skip(doc, ev)
  local pb = pb_of(doc)
  if not pb.now or pb.now.service == "STREAM" then return nil end
  if is_streaming(pb) then return stream_cmds(pb, "skip", math.floor(tonumber(ev.seconds) or 0)) end
  return { commands = { cmd_audio("skip_sec", MUSIC, math.floor(tonumber(ev.seconds) or 0)) } }
end

function playback.on_stop(doc)
  local pb = pb_of(doc)
  if pb.state == "idle" then return nil end
  if is_streaming(pb) then return stream_cmds(pb, "stop") end
  return { state = st(pb), commands = { cmd_audio("stop", MUSIC) } }
end

-- what the streaming daemons report ---------------------------------------------
--- Local music (a file or a web radio) loaded on the engine: playing, starting or paused.
function playback.local_busy(doc)
  local pb = doc.playback or {}
  return pb.now and (pb.now.service == "FILE" or pb.now.service == "STREAM")
    and (pb.state == "playing" or pb.state == "starting" or pb.state == "paused")
end

--- playback.external { service, takeover?, now? | clear?, uri?, position_ms?, state? }: what a daemon
--- (services.streaming) says about the track IT plays, applied to the published machine state -- the
--- one way a daemon's word reaches state.playback. `takeover`: Spotify started from the phone becomes
--- what plays and the local music stops (the last one to start wins); `state` raises playback.changed.
--- Only the published sub-tree moves: the bookkeeping (playback_int) is the local machine's. Returns
--- the handler result for the caller to complete (its own sub-tree, its logs; nil commands when none).
function playback.on_external(doc, ev)
  local pb = copy(doc.playback or {})
  pb.state = pb.state or "idle"
  local cmds = {}
  if ev.takeover then
    if playback.local_busy(doc) then cmds[#cmds + 1] = cmd_audio("stop", MUSIC) end
    pb.paused_by, pb.paused_at, pb.resume_ms = nil, nil, nil
  end
  if ev.clear then pb.now = nil elseif ev.now then pb.now = ev.now end
  if ev.uri then pb.now.uri = ev.uri end
  if ev.position_ms then pb.position_ms = ev.position_ms end
  if ev.state then
    pb.state = ev.state
    cmds[#cmds + 1] = emit("playback.changed", { state = ev.state })
  end
  return { state = { playback = pb }, commands = #cmds > 0 and cmds or nil }
end

-- audio engine events ----------------------------------------------------------
local function transition(pb, new_state)
  if pb.state == new_state then return false end
  pb.state = new_state
  return true
end

function playback.on_audio(doc, ev)
  local kind = ev.type:sub(7)   -- after "audio."
  if ev.id == SOUND then return sounds.on_sound_audio(doc, ev, kind) end
  if ev.id ~= MUSIC then return nil end
  local pb = pb_of(doc)
  -- Spotify/Deezer plays: late reports of the local track it stopped must not touch its state
  if is_streaming(pb) then return nil end
  local cmds = {}
  local resume, resume_changed = nil, false
  if kind == "position" then
    -- positions only count while a track is loaded (after "ended"/"stopped" the engine's late reports are stale)
    if pb.state ~= "playing" and pb.state ~= "starting" and pb.state ~= "paused" then return nil end
    pb.position_ms = ev.ms
    if pb.now and pb.now.audiobook then
      resume = resume_copy(doc)
      resume_changed = note_position(doc, pb, resume, ev.ms, false)
      pb.resume_dirty = resume_changed or pb.resume_dirty
    end
    local r = { state = st(pb) }
    if resume_changed then r.state.resume = resume end
    return r
  end
  if kind == "starting" then
    pb.position_ms = 0
    transition(pb, "starting")
  elseif kind == "playing" then
    if transition(pb, "playing") then
      if pb.resume_ms then
        cmds[#cmds + 1] = cmd_audio("seek", MUSIC, pb.resume_ms)
        cmds[#cmds + 1] = { kind = "log", level = "info", key = "playback.resume_seek", fields = { ms = pb.resume_ms } }
        pb.position_ms = pb.resume_ms
        pb.resume_ms = nil
      end
    end
  elseif kind == "paused" then
    if pb.state == "starting" then return nil end
    transition(pb, "paused")
    resume = resume_copy(doc)
    if note_position(doc, pb, resume, pb.position_ms or 0, pb.paused_by == "sleep_timer") then resume_changed = true end
    if pb.resume_dirty and pb.now and pb.now.audiobook then resume_changed = true end   -- a pause always secures the position
  elseif kind == "stopped" then
    transition(pb, "idle")
    resume = resume_copy(doc)
    if note_position(doc, pb, resume, pb.position_ms or 0, false) then resume_changed = true end
    if pb.resume_dirty and pb.now and pb.now.audiobook then resume_changed = true end
  elseif kind == "ended" then
    transition(pb, "ended")
    pb.position_ms = 0
    local now = pb.now
    local p = now and doc.library and doc.library.playlists[now.playlist]
    if now and now.audiobook and p then
      resume = resume_copy(doc)
      note_ended(resume, now, p)
      resume_changed = true
    end
    local cfg = doc.audiocfg or {}
    -- with the sleep timer in "end of chapter" mode, stay ended (bedtime clears its flag on playback.changed)
    local stop_here = doc.bedtime_int and doc.bedtime_int.stop_at_end
    -- (start and step work on this very pb: only their commands are to be collected)
    if not stop_here and p and cfg.repeat_mode == 2 and not p.audiobook then
      local r = start(doc, pb, now.playlist, { index = now.index, restart = true })
      if r then for _, c in ipairs(r.commands) do cmds[#cmds + 1] = c end end
    elseif not stop_here and p then
      local r = step(doc, pb, 1, { forced = true, now = ev.now })
      if r then for _, c in ipairs(r.commands) do cmds[#cmds + 1] = c end end
    end
  end
  cmds[#cmds + 1] = emit("playback.changed", { state = pb.state })
  if resume_changed then
    cmds[#cmds + 1] = write_resume(doc, resume)
    pb.resume_dirty = nil
  end
  local result = { state = st(pb), commands = cmds }
  if resume_changed then result.state.resume = resume end
  return result
end

-- boot / timers / api ------------------------------------------------------------
--- Boot: an idle machine and the shuffle seed. (resume.json and the save timer are
--- services.playback.resume's boot, the sound catalogue services.playback.sounds'.)
function playback.on_boot(_, ev)
  -- the shuffle seed: the clock at boot, so that two starts (or two playlists of the same length)
  -- do not play in the same "random" order
  local seed = math.floor(tonumber(ev.wall) or tonumber(ev.now) or 0) % 2147483648
  return { state = { playback = { state = "idle" }, playback_int = { last = {}, shuffle = {}, seed = seed } } }
end

--- The timer by name (the specs drive this one; the kernel routes the name itself): the save timer is resume's.
function playback.on_timer(doc, ev) return resume_rules.on_timer(doc, ev) end

-- the sub-modules' handlers under their old names (the other services and the specs reach them here)
playback.on_system_event, playback.on_sound_audio = sounds.on_system_event, sounds.on_sound_audio
playback.on_save, playback.on_resume_reset, playback.on_shutdown = resume_rules.on_save, resume_rules.on_resume_reset, resume_rules.on_shutdown

local S = {}
S.play = { type = "object", required = { "playlist" }, properties = { playlist = { type = "string", minLength = 1 }, index = { type = "integer", minimum = 1 } }, additionalProperties = false }
S.seek = { type = "object", required = { "ms" }, properties = { ms = { type = "integer", minimum = 0 } }, additionalProperties = false }
S.skip = { type = "object", required = { "seconds" }, properties = { seconds = { type = "integer", minimum = -3600, maximum = 3600 } }, additionalProperties = false }
S.playlist = resume_rules.schemas.playlist
playback.schemas = S

function playback.install(api, dispatch)
  dispatch.on("boot", "playback", playback.on_boot)
  dispatch.on("playback.request", "playback", playback.on_request)
  dispatch.on("playback.pause_request", "playback", playback.on_pause)
  dispatch.on("playback.next", "playback", playback.on_next)
  dispatch.on("playback.prev", "playback", playback.on_prev)
  for _, k in ipairs({ "starting", "playing", "paused", "stopped", "ended", "position" }) do
    dispatch.on("audio." .. k, "playback", playback.on_audio)
  end
  api.command("playback.play", S.play, function(doc, p, ev)
    local pb = pb_of(doc)
    local r, err = start(doc, pb, p.playlist, { index = p.index, now_s = ev.now, restart = p.index ~= nil })
    return r, err
  end)
  api.command("playback.pause", nil, function(doc, _, ev) return playback.on_pause(doc, { source = "page", now = ev.now }) or {} end)
  api.command("playback.resume", nil, function(doc, _, ev) return playback.on_resume(doc, { now = ev.now }) or {} end)
  api.command("playback.next", nil, function(doc, _, ev) return playback.on_next(doc, { forced = true, now = ev.now }) or {} end)
  api.command("playback.prev", nil, function(doc, _, ev) return playback.on_prev(doc, { forced = true, now = ev.now }) or {} end)
  api.command("playback.seek", S.seek, function(doc, p) return playback.on_seek(doc, { ms = p.ms }) or {} end)
  api.command("playback.skip", S.skip, function(doc, p) return playback.on_skip(doc, { seconds = p.seconds }) or {} end)
  api.command("playback.stop", nil, function(doc) return playback.on_stop(doc) or {} end)
  -- the sub-modules' own handlers and timers
  sounds.install(api, dispatch)
  resume_rules.install(api, dispatch)
end

playback.MUSIC, playback.SOUND = MUSIC, SOUND
return playback
