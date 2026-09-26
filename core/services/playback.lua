-- services.playback: what plays, in what order, and where it resumes.
-- Owns state.playback:
--   { state = "idle"|"starting"|"playing"|"paused"|"ended",
--     position_ms, now = { playlist, index, queue_pos, track, uri, service, audiobook,
--                          title, album, artist, duration_ms, has_next, has_prev, image },
--     paused_by, paused_at, resume_ms (pending seek), last = { [playlist] = index },
--     shuffle = { [playlist] = { order... } },
--     sys = { name, after, resume_music } (a system sound in progress) }
-- and state.resume (persisted as resume.json, 1.3 shape: { [playlist] = { id, pos, t } }).
-- Talks to audio_ctrl: stream 7 = music, stream 3 = system sounds (docs/22 §4.4).
local playback = {}

local MUSIC, SOUND = 7, 3
local BACK_PAUSE, BACK_TIMER, MIN_BACK = 15000, 60000, 5000
local AUDIO_OUT = "/j/audio/out/"

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function cmd_audio(action, id, arg)
  local payload = tostring(id)
  if arg ~= nil then payload = payload .. "\t" .. tostring(arg) end
  return { kind = "bus.publish", topic = AUDIO_OUT .. action, payload = payload }
end

local function emit(t, extra)
  local e = { type = t }
  for k, v in pairs(extra or {}) do e[k] = v end
  return { kind = "emit", event = e }
end

local function pb_of(doc)
  local pb = copy(doc.playback or {})
  pb.state = pb.state or "idle"
  pb.last = pb.last or {}
  pb.shuffle = pb.shuffle or {}
  return pb
end

local function resume_path(doc)
  return ((doc.config and doc.config.data_dir) or "/jooki/external/jooki") .. "/resume.json"
end

local function write_resume(doc, resume)
  return { kind = "files.write", path = resume_path(doc), doc = resume, version = 1 }
end

-- ------------------------------------------------------------------ queue
local function shuffled(n, seed)
  local order = {}
  for i = 1, n do order[i] = i end
  local s = seed or 0
  for i = n, 2, -1 do
    s = (s * 1103515245 + 12345) % 2147483648
    local j = (s % i) + 1
    order[i], order[j] = order[j], order[i]
  end
  return order
end

--- The order in which a playlist's tracks are played (identity or a memoised shuffle).
local function queue_for(doc, pb, playlist_id, p)
  local n = #p.tracks
  local cfg = doc.audiocfg or {}
  if not cfg.shuffle_mode or p.audiobook then
    local q = {}
    for i = 1, n do q[i] = i end
    return q
  end
  local q = pb.shuffle[playlist_id]
  if q and #q == n then return q end
  q = shuffled(n, math.floor((doc.playback_seed or 0) + n * 7919))
  pb.shuffle[playlist_id] = q
  return q
end

local function index_of(q, index)
  for pos, i in ipairs(q) do if i == index then return pos end end
  return nil
end

-- ------------------------------------------------------------------ resume rules (1.3)
local function back_for(entry) return (entry and entry.t) and BACK_TIMER or BACK_PAUSE end

--- For an audiobook: the index and the position to start at, from resume.json.
function playback.resume_for(resume, playlist_id, tracks)
  local r = resume and resume[playlist_id]
  if not r then return nil end
  for i, t in ipairs(tracks) do
    if t == r.id then
      local ms = (tonumber(r.pos) or 0) - back_for(r)
      if ms >= MIN_BACK then return i, ms end
      return i, nil
    end
  end
  return nil
end

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
    if pb.state == "playing" or pb.state == "starting" then return { state = { playback = pb }, commands = cmds } end
    if pb.state == "paused" then return playback.resume_paused(doc, pb, opts.now_s) end
  end
  if pb.state == "playing" or pb.state == "paused" or pb.state == "starting" then
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
  return { state = { playback = pb }, commands = cmds }
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
  return { state = { playback = pb }, commands = cmds }
end

-- ------------------------------------------------------------------ resume bookkeeping
local function resume_copy(doc) return copy(doc.resume or {}) end

local function note_position(_, pb, resume, ms, from_timer)
  local now = pb.now
  if not (now and now.audiobook and now.service == "FILE") then return false end
  local r = resume[now.playlist]
  if r and r.id == now.track and math.abs((r.pos or 0) - ms) < 1000 and (r.t == true) == (from_timer == true) then return false end
  resume[now.playlist] = { id = now.track, pos = math.floor(ms), t = from_timer or nil }
  return true
end

-- ------------------------------------------------------------------ handlers
function playback.on_request(doc, ev)
  local pb = pb_of(doc)
  local r, err = start(doc, pb, ev.playlist, { index = ev.index, queue_pos = ev.queue_pos, now_s = ev.now, restart = ev.restart })
  if not r then return { commands = { { kind = "log", level = "warn", key = "playback.request_failed", fields = { playlist = tostring(ev.playlist), err = err.message } } } } end
  return r
end

function playback.on_pause(doc, ev)
  local pb = pb_of(doc)
  if pb.state ~= "playing" and pb.state ~= "starting" then return nil end
  pb.paused_by, pb.paused_at = ev.source, ev.now
  if pb.now and pb.now.service == "STREAM" then
    return { state = { playback = pb }, commands = { cmd_audio("stop", MUSIC) } }
  end
  return { state = { playback = pb }, commands = { cmd_audio("pauz", MUSIC) } }
end

function playback.on_resume(doc, ev)
  local pb = pb_of(doc)
  if pb.state == "paused" then return playback.resume_paused(doc, pb, ev.now) end
  if (pb.state == "ended" or pb.state == "idle") and pb.now then
    return start(doc, pb, pb.now.playlist, { index = pb.now.index, restart = true, now_s = ev.now })
  end
  return nil
end

function playback.on_toggle(doc, ev)
  local pb = pb_of(doc)
  if pb.state == "playing" or pb.state == "starting" then return playback.on_pause(doc, ev) end
  return playback.on_resume(doc, ev)
end

local function step(doc, pb, delta, ev)
  local now = pb.now
  if not now then return nil end
  if not ev.forced and pb.state ~= "playing" and pb.state ~= "starting" then return nil end
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

function playback.on_next(doc, ev) return step(doc, pb_of(doc), 1, ev) end

function playback.on_prev(doc, ev)
  local pb = pb_of(doc)
  if not pb.now then return nil end
  if not ev.forced and pb.state ~= "playing" and pb.state ~= "starting" then return nil end
  if (pb.position_ms or 0) > 5000 then
    pb.position_ms = 0
    return { state = { playback = pb }, commands = { cmd_audio("seek", MUSIC, 1) } }
  end
  return step(doc, pb, -1, ev)
end

function playback.on_seek(doc, ev)
  local pb = pb_of(doc)
  if not pb.now or pb.now.service == "STREAM" then return nil end
  local ms = math.max(1, math.floor(tonumber(ev.ms) or 1))
  pb.position_ms = ms
  return { state = { playback = pb }, commands = { cmd_audio("seek", MUSIC, ms) } }
end

function playback.on_skip(doc, ev)
  local pb = pb_of(doc)
  if not pb.now or pb.now.service == "STREAM" then return nil end
  return { commands = { cmd_audio("skip_sec", MUSIC, math.floor(tonumber(ev.seconds) or 0)) } }
end

function playback.on_stop(doc)
  local pb = pb_of(doc)
  if pb.state == "idle" then return nil end
  return { state = { playback = pb }, commands = { cmd_audio("stop", MUSIC) } }
end

-- audio engine events ----------------------------------------------------------
local function transition(pb, new_state)
  if pb.state == new_state then return false end
  pb.state = new_state
  return true
end

function playback.on_audio(doc, ev)
  local kind = ev.type:sub(7)   -- after "audio."
  if ev.id == SOUND then return playback.on_sound_audio(doc, ev, kind) end
  if ev.id ~= MUSIC then return nil end
  local pb = pb_of(doc)
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
    local r = { state = { playback = pb } }
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
      local next_id = p.tracks[now.index + 1]
      if next_id then resume[now.playlist] = { id = next_id, pos = 0 } else resume[now.playlist] = nil end
      resume_changed = true
    end
    local cfg = doc.audiocfg or {}
    -- with the sleep timer in "end of chapter" mode, stay ended (bedtime clears its flag on playback.changed)
    local stop_here = doc.bedtime_int and doc.bedtime_int.stop_at_end
    if not stop_here and p and cfg.repeat_mode == 2 and not p.audiobook then
      local r = start(doc, pb, now.playlist, { index = now.index, restart = true })
      if r then pb = r.state.playback for _, c in ipairs(r.commands) do cmds[#cmds + 1] = c end end
    elseif not stop_here and p then
      local r = step(doc, pb, 1, { forced = true, now = ev.now })
      if r then pb = r.state.playback for _, c in ipairs(r.commands) do cmds[#cmds + 1] = c end end
    end
  end
  cmds[#cmds + 1] = emit("playback.changed", { state = pb.state })
  local result = { state = { playback = pb }, commands = cmds }
  if resume_changed then
    result.state.resume = resume
    cmds[#cmds + 1] = write_resume(doc, resume)
    pb.resume_dirty = nil
  end
  return result
end

-- system sounds -----------------------------------------------------------------
local function sound_uri(doc, name)
  local sys = doc.system or {}
  local t = sys.tracks and sys.tracks[name]
  if not (t and t.filename) then return nil end
  return "file://" .. ((doc.config and doc.config.system_dir) or "/jooki/app/system") .. "/" .. t.filename
end

--- system.event { name, after? }: play the sound if there is one, pausing the music meanwhile.
function playback.on_system_event(doc, ev)
  local uri = sound_uri(doc, ev.name)
  local cmds = { emit("lights.event", { name = ev.name }) }
  if not uri then
    if ev.after then cmds[#cmds + 1] = { kind = "emit", event = ev.after } end
    return { commands = cmds }
  end
  local pb = pb_of(doc)
  local resume_music = false
  if (pb.state == "playing" or pb.state == "starting") and not ev.no_pause then
    cmds[#cmds + 1] = cmd_audio("pauz", MUSIC)
    resume_music = true
  end
  if pb.sys and pb.sys.name then cmds[#cmds + 1] = cmd_audio("stop", SOUND) end
  pb.sys = { name = ev.name, after = ev.after, resume_music = resume_music or (pb.sys and pb.sys.resume_music) or nil }
  cmds[#cmds + 1] = cmd_audio("play", SOUND, uri)
  return { state = { playback = pb }, commands = cmds }
end

function playback.on_sound_audio(doc, _, kind)
  if kind ~= "ended" and kind ~= "stopped" then return nil end
  local pb = pb_of(doc)
  local sys = pb.sys
  if not sys then return nil end
  local cmds = {}
  if sys.resume_music and pb.state ~= "idle" then cmds[#cmds + 1] = cmd_audio("cont", MUSIC) end
  if sys.after then cmds[#cmds + 1] = { kind = "emit", event = sys.after } end
  pb.sys = nil
  return { state = { playback = pb }, commands = cmds }
end

-- boot / timers / api ------------------------------------------------------------
function playback.on_boot(_, ev)
  local resume = {}
  for k, v in pairs(ev.resume or {}) do
    if type(v) == "table" and type(v.id) == "string" then resume[k] = { id = v.id, pos = tonumber(v.pos) or 0, t = v.t == true or nil } end
  end
  return { state = { playback = { state = "idle", last = {}, shuffle = {} }, resume = resume, system = ev.system or { tracks = {} } },
           commands = { { kind = "timer.every", name = "playback.save", seconds = 60 } } }
end

function playback.on_timer(doc, ev)
  if ev.name ~= "playback.save" then return nil end
  local pb = pb_of(doc)
  if not pb.resume_dirty then return nil end
  pb.resume_dirty = nil
  return { state = { playback = pb }, commands = { write_resume(doc, doc.resume or {}) } }
end

function playback.on_resume_reset(doc, playlist_id)
  local resume = resume_copy(doc)
  resume[playlist_id] = nil
  return { state = { resume = resume }, commands = { write_resume(doc, resume) } }
end

function playback.on_shutdown(doc)
  local pb = pb_of(doc)
  if not pb.resume_dirty then return nil end
  return { commands = { write_resume(doc, doc.resume or {}) } }
end

local S = {}
S.play = { type = "object", required = { "playlist" }, properties = { playlist = { type = "string", minLength = 1 }, index = { type = "integer", minimum = 1 } }, additionalProperties = false }
S.seek = { type = "object", required = { "ms" }, properties = { ms = { type = "integer", minimum = 0 } }, additionalProperties = false }
S.skip = { type = "object", required = { "seconds" }, properties = { seconds = { type = "integer", minimum = -3600, maximum = 3600 } }, additionalProperties = false }
S.playlist = { type = "object", required = { "playlist" }, properties = { playlist = { type = "string", minLength = 1 } }, additionalProperties = false }
playback.schemas = S

function playback.install(api, dispatch)
  dispatch.on("boot", "playback", playback.on_boot)
  dispatch.on("playback.request", "playback", playback.on_request)
  dispatch.on("playback.pause_request", "playback", playback.on_pause)
  dispatch.on("playback.resume_request", "playback", playback.on_resume)
  dispatch.on("playback.toggle", "playback", playback.on_toggle)
  dispatch.on("playback.next", "playback", playback.on_next)
  dispatch.on("playback.prev", "playback", playback.on_prev)
  dispatch.on("playback.stop", "playback", playback.on_stop)
  for _, k in ipairs({ "starting", "playing", "paused", "stopped", "ended", "position" }) do
    dispatch.on("audio." .. k, "playback", playback.on_audio)
  end
  dispatch.on("system.event", "playback", playback.on_system_event)
  dispatch.on("timer", "playback", playback.on_timer)
  dispatch.on("host.terminating", "playback", playback.on_shutdown)
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
  api.command("playback.resume_reset", S.playlist, function(doc, p) return playback.on_resume_reset(doc, p.playlist) end)
  playback.start = start
end

playback.MUSIC, playback.SOUND = MUSIC, SOUND
return playback
