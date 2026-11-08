-- Optional offline snapshots and the native player's file protocol. No I/O here.
local util = require("services.util")
local json = require("vendor.json")
local offline = {}
local copy, err = util.copy, util.err
local SERVICE = "SPOTIFY_OFFLINE"
offline.SERVICE = SERVICE

function offline.paths(doc)
  local c = doc.config or {}
  local root = c.spotify_offline_root or "/jooki/external/openjooki-offline"
  local scratch = util.scratch_dir(doc) .. "/spotify-offline"
  return { root = root, scratch = scratch, store = root .. "/store", modes = root .. "/modes.json",
    catalog = scratch .. "/catalog.json", job = scratch .. "/job.json" }
end
local function current(doc) return copy(doc.spotify_offline or { available = false, account_ready = false, modes = {}, playlists = {} }) end
local function internal(doc) return copy(doc.spotify_offline_int or { next_id = 0, controls = {} }) end
local function result(pub, int, commands) return { state = { spotify_offline = pub, spotify_offline_int = int }, commands = commands or {} } end
local function read(path, reply) return { kind = "files.read_text", path = path, reply = reply } end
local function action(name, args) return { kind = "shell", action = "offline_" .. name, args = args or {} } end
local function busy(pub) return pub.download and (pub.download.phase == "resolving" or pub.download.phase == "downloading" or pub.download.phase == "verifying") end
local function playlist(doc, id)
  local p = type(id) == "string" and doc.library and doc.library.playlists and doc.library.playlists[id]
  if not (p and p.spotify and type(p.spotify.uri) == "string" and p.spotify.uri:match("^spotify:playlist:%w+$") and #p.spotify.uri == 39) then
    return nil, err("not_found", "playlist", "unknown Spotify playlist")
  end
  return p
end
local function write_modes(doc, pub)
  return { kind = "files.write", path = offline.paths(doc).modes, doc = { modes = pub.modes or {} }, version = 1 }
end
local function enabled(doc) return (doc.config or {}).spotify_offline_enabled == true end

function offline.on_boot(doc)
  if not enabled(doc) then return nil end
  local p = offline.paths(doc)
  return result(current(doc), internal(doc), {
    { kind = "files.stat", path = (doc.config or {}).spotify_offline_binary or p.root .. "/current/spotify_player", reply = "offline.binary" },
    read(p.modes, "offline.modes"),
  })
end
function offline.on_binary(doc, ev)
  if not ev.exists then return nil end
  local pub = current(doc); pub.available = true
  return result(pub, internal(doc), { action("catalog"), { kind = "timer.every", name = "offline.poll", seconds = 1 } })
end
function offline.on_timer(doc, ev)
  if not enabled(doc) or not (doc.spotify_offline or {}).available then return nil end
  local p, int = offline.paths(doc), internal(doc)
  local cmds = { read(p.catalog, "offline.catalog"), read(p.job, "offline.job") }
  if int.session then cmds[#cmds + 1] = read(int.session.status, "offline.player") end
  local function check_process(process, kind)
    if type(process) == "table" and type(process.pid) == "number" and process.pid > 1 and process.pid < 2147483648 and process.pid == math.floor(process.pid) and type(process.start) == "string" then
      local c = read("/proc/" .. string.format("%.0f", process.pid) .. "/stat", "offline.process")
      c.ref = { kind = kind, pid = process.pid, start = process.start }; cmds[#cmds + 1] = c
    end
  end
  if busy(doc.spotify_offline or {}) then check_process(int.job_process, "job") end
  if int.session and (doc.playback or {}).now and doc.playback.now.service == SERVICE and doc.playback.state ~= "idle" and doc.playback.state ~= "ended" then check_process(int.player_process, "player") end
  if not int.auto_routed and doc.spotify_offline.catalog_loaded and int.modes_loaded then
    local star = (doc.nfc or {}).starId
    local pb = doc.playback or {}
    for id, item in pairs((doc.library or {}).playlists or {}) do
      if star and item.star == star and offline.mode(doc, id) == "auto" and offline.snapshot(doc, item) and (not pb.now or pb.now.playlist == id) then
        int.auto_routed = true
        if not (pb.now and pb.now.service == SERVICE) then cmds[#cmds + 1] = util.emit("playback.request", { playlist = id, now = ev and ev.now }) end
        return { state = { spotify_offline_int = int }, commands = cmds }
      end
    end
  end
  local pub = current(doc)
  if busy(pub) and not int.job_process then
    int.job_wait = (int.job_wait or 0) + 1
    if int.job_wait >= 15 then pub.download.phase, pub.download.error = "error", "backend_start_failed" end
  end
  if int.session and not int.player_process and (doc.playback or {}).state == "starting" then
    int.player_wait = (int.player_wait or 0) + 1
    if int.player_wait >= 15 then
      pub.player = { state = "idle", error = "backend_start_failed", playlist = int.session.playlist }
      local r = result(pub, int, cmds); r.state.playback = copy(doc.playback); r.state.playback.state = "idle"
      cmds[#cmds + 1] = util.emit("playback.changed", { state = "idle" })
      return r
    end
  end
  return result(pub, int, cmds)
end
function offline.on_modes(doc, ev)
  local int = internal(doc); int.modes_loaded = true
  if not ev.text then return result(current(doc), int) end
  local ok, data = pcall(json.decode, ev.text)
  if not (ok and type(data) == "table" and type(data.modes) == "table") then return nil end
  local pub = current(doc); pub.modes = {}
  for id, mode in pairs(data.modes) do if mode == "online" or mode == "auto" or mode == "offline" then pub.modes[id] = mode end end
  return result(pub, int)
end
function offline.on_catalog(doc, ev)
  local int = internal(doc)
  if not ev.text or ev.text == int.catalog_text then return nil end
  local ok, data = pcall(json.decode, ev.text)
  if not (ok and type(data) == "table" and data.version == 1 and type(data.playlists) == "table") then return nil end
  int.catalog_text = ev.text
  local pub = current(doc)
  if pub.account_id ~= data.account_id then pub.download = nil; int.job_process = nil end
  pub.catalog_loaded = true
  pub.account_ready, pub.account_id = data.account_ready == true, data.account_id
  pub.playlists = data.playlists
  pub.storage = { used_bytes = data.used_bytes or 0, free_bytes = data.free_bytes or 0, quota_bytes = data.quota_bytes or 0 }
  pub.error = data.error
  return result(pub, int)
end
function offline.on_job(doc, ev)
  local int = internal(doc)
  if not ev.text or ev.text == int.job_text then return nil end
  local ok, data = pcall(json.decode, ev.text)
  if not (ok and type(data) == "table" and data.version == 1 and type(data.uri) == "string") then return nil end
  local pub = current(doc)
  if data.account_id ~= nil and data.account_id ~= pub.account_id then return nil end
  if int.job_request and data.request ~= int.job_request then return nil end
  int.job_text, int.job_process = ev.text, copy(data.process)
  data.process = nil; pub.download = data
  local cmds = {}
  if data.phase == "complete" or data.phase == "error" or data.phase == "interrupted" then cmds[1] = read(offline.paths(doc).catalog, "offline.catalog") end
  return result(pub, int, cmds)
end
function offline.on_process(doc, ev)
  local ref = ev.ref or {}; local int = internal(doc)
  local process = ref.kind == "job" and int.job_process or int.player_process
  if not process or process.pid ~= ref.pid then return nil end
  local tail = ev.text and ev.text:match("^%d+ %b() (.*)$")
  local fields = {}; for field in (tail or ""):gmatch("%S+") do fields[#fields + 1] = field end
  if fields[20] == ref.start then return nil end
  local path = ref.kind == "job" and offline.paths(doc).job or (int.session and int.session.status)
  if not path then return nil end
  local c = read(path, ref.kind == "job" and "offline.job_final" or "offline.player_final")
  return { commands = { c } }
end
function offline.on_job_final(doc, ev)
  local int = internal(doc)
  if ev.text ~= int.job_text then return offline.on_job(doc, ev) end
  local pub = current(doc)
  if not busy(pub) then return nil end
  pub.download.phase, pub.download.error = "interrupted", "interrupted"
  int.job_process = nil
  return result(pub, int)
end
function offline.on_player_final(doc, ev)
  local int = internal(doc)
  if ev.text ~= int.player_text then return offline.on_player(doc, ev) end
  local pub, pb = current(doc), copy(doc.playback or {})
  if not (pb.now and pb.now.service == SERVICE) or pb.state == "idle" or pb.state == "ended" then return nil end
  pub.player = { state = "idle", error = "player_interrupted", playlist = int.session and int.session.playlist }
  pb.state, int.player_process = "idle", nil
  local r = result(pub, int, { util.emit("playback.changed", { state = "idle" }) }); r.state.playback = pb
  return r
end
function offline.on_sync(doc, ev)
  local p, e = playlist(doc, ev.playlist); if not p then return nil, e end
  local pub, int = current(doc), internal(doc)
  if not pub.available then return nil, err("unavailable", "", "offline backend is not installed") end
  if not pub.account_ready then return nil, err("unavailable", "", "offline Premium authentication required") end
  if busy(pub) then return nil, err("conflict", "", "another offline download is running") end
  if (doc.playback or {}).now and doc.playback.now.service == SERVICE and (doc.playback.state == "playing" or doc.playback.state == "starting") then
    return nil, err("conflict", "", "pause offline playback before synchronizing")
  end
  pub.modes = pub.modes or {}; pub.modes[ev.playlist] = "auto"
  pub.download = { uri = p.spotify.uri, phase = "resolving", completed = 0, total = 0 }
  int.next_id = (int.next_id or 0) + 1
  int.job_request = string.format("%.0f", (ev.now or 0) * 1000) .. "-" .. int.next_id
  int.job_text, int.job_process, int.job_wait = nil, nil, 0
  return result(pub, int, { write_modes(doc, pub), action("sync", { uri = p.spotify.uri, request = int.job_request }) })
end
function offline.on_mode(doc, ev)
  local p, e = playlist(doc, ev.playlist); if not p then return nil, e end
  if ev.mode ~= "online" and ev.mode ~= "auto" and ev.mode ~= "offline" then return nil, err("invalid_argument", "mode", "invalid offline playback mode") end
  local pub = current(doc); pub.modes = pub.modes or {}; pub.modes[ev.playlist] = ev.mode
  return result(pub, internal(doc), { write_modes(doc, pub) })
end
function offline.on_remove(doc, ev)
  local p, e = playlist(doc, ev.playlist); if not p then return nil, e end
  local pub, int = current(doc), internal(doc)
  if busy(pub) or (int.session and int.session.uri == p.spotify.uri and (doc.playback or {}).state ~= "idle" and (doc.playback or {}).state ~= "ended") then
    return nil, err("conflict", "", "stop playback and downloads before removing a snapshot")
  end
  return result(pub, int, { action("remove", { uri = p.spotify.uri }) })
end
function offline.mode(doc, id) return ((doc.spotify_offline or {}).modes or {})[id] or "online" end
function offline.snapshot(doc, p)
  local pub = doc.spotify_offline or {}
  if not pub.account_ready then return nil end
  local snap = p.spotify and (pub.playlists or {})[p.spotify.uri]
  return snap and snap.ready == true and type(snap.tracks) == "table" and #snap.tracks > 0 and snap or nil
end
function offline.wants(doc, id)
  if not enabled(doc) then return false end
  local p = doc.library and doc.library.playlists[id]
  if not (p and p.spotify) then return false end
  local mode = offline.mode(doc, id)
  return mode == "offline" or (mode == "auto" and offline.snapshot(doc, p) ~= nil)
end
function offline.describe(id, p, snap, index)
  local t = snap.tracks[index]
  return { playlist = id, service = SERVICE, index = index, queue_pos = index, track = t.uri, uri = t.uri,
    title = t.name, artist = table.concat(t.artists or {}, ", "), album = t.album, duration_ms = t.duration_ms,
    source = p.title, audiobook = p.audiobook == true, has_next = index < #snap.tracks, has_prev = index > 1, image = p.image }
end
function offline.transport(doc, name, value)
  local pub, int = current(doc), internal(doc)
  if not int.session then return { commands = {} } end
  int.controls = int.controls or {}
  if #int.controls >= 32 then return nil, err("conflict", "", "offline control queue is full") end
  int.next_id = (int.next_id or 0) + 1
  int.controls[#int.controls + 1] = { id = int.next_id, action = name, value = value }
  return result(pub, int, { { kind = "files.write", path = int.session.control,
    doc = { session = int.session.id, commands = int.controls }, version = 1 } })
end
function offline.start(doc, id, p, opts)
  opts = opts or {}
  local snap = offline.snapshot(doc, p)
  if not snap then return nil, err("unavailable", "playlist", "no complete offline snapshot") end
  if busy(current(doc)) then return nil, err("conflict", "", "offline download is running") end
  local index = tonumber(opts.index) or 1
  if index ~= math.floor(index) or index < 1 or index > #snap.tracks then return nil, err("invalid_argument", "index", "invalid offline track index") end
  local pub, int, cmds = current(doc), internal(doc), {}
  if int.session then
    local r = offline.transport(doc, "stop")
    for _, c in ipairs(r and r.commands or {}) do cmds[#cmds + 1] = c end
  end
  int.next_id = (int.next_id or 0) + 1
  local session = string.format("%.0f", (opts.now_s or 0) * 1000) .. "-" .. int.next_id
  local prefix = offline.paths(doc).scratch .. "/session-" .. session
  int.session = { id = session, playlist = id, uri = p.spotify.uri, control = prefix .. ".commands.json", status = prefix .. ".status.json", snapshot = copy(snap), account_id = pub.account_id }
  int.controls, int.player_text, int.player_process, int.stopping, int.player_wait = {}, nil, nil, false, 0
  cmds[#cmds + 1] = { kind = "files.write", path = int.session.control, doc = { session = session, commands = {} }, version = 1 }
  cmds[#cmds + 1] = action("play", { uri = p.spotify.uri, session = session, index = index - 1, resume = p.resume == true and not opts.restart })
  local r = result(pub, int, cmds); r.now = offline.describe(id, p, snap, index)
  return r
end
function offline.on_player(doc, ev)
  local pub, int = current(doc), internal(doc)
  if not int.session or ev.path ~= int.session.status or not ev.text or ev.text == int.player_text then return nil end
  local ok, data = pcall(json.decode, ev.text)
  if not (ok and type(data) == "table" and data.version == 1 and data.session == int.session.id) then return nil end
  int.player_text, int.player_process = ev.text, copy(data.process)
  local pending = {}
  for _, c in ipairs(int.controls or {}) do if c.id > (tonumber(data.ack) or 0) then pending[#pending + 1] = c end end
  int.controls = pending
  local p = doc.library and doc.library.playlists[int.session.playlist]
  local snap = p and pub.account_ready and pub.account_id == int.session.account_id and int.session.snapshot
  local pb = copy(doc.playback or {})
  if not (snap and pb.now and pb.now.service == SERVICE and pb.now.playlist == int.session.playlist) then return result(pub, int) end
  local index = (tonumber(data.index) or 0) + 1
  if index < 1 or index > #snap.tracks then return nil end
  pb.now = offline.describe(int.session.playlist, p, snap, index)
  local phase = data.phase
  if phase ~= "playing" and phase ~= "paused" and phase ~= "ended" and phase ~= "starting" then phase = "idle" end
  pb.state, pb.position_ms = phase, math.max(0, tonumber(data.position_ms) or 0)
  pub.player = { playlist = int.session.playlist, state = phase, index = index, error = data.error }
  local r = result(pub, int)
  r.state.playback = pb
  if (doc.playback or {}).state ~= phase then r.commands[1] = util.emit("playback.changed", { state = phase }) end
  return r
end
function offline.on_playback_changed(doc)
  local int = internal(doc)
  local pb = doc.playback or {}
  if int.session and not int.stopping and (not pb.now or pb.now.service ~= SERVICE) then
    local r = offline.transport(doc, "stop")
    if r then r.state.spotify_offline_int.stopping = true end
    return r
  end
end
function offline.on_forget(doc)
  local pub, int = current(doc), internal(doc)
  local r = offline.transport(doc, "stop")
  pub.account_ready, pub.account_id, pub.playlists, pub.download = false, nil, {}, nil
  int.session, int.controls = nil, {}
  local cmds = r and r.commands or {}; cmds[#cmds + 1] = action("forget")
  local out = result(pub, int, cmds)
  if (doc.playback or {}).now and doc.playback.now.service == SERVICE then
    out.state.playback = copy(doc.playback); out.state.playback.state = "idle"
    out.commands[#out.commands + 1] = util.emit("playback.changed", { state = "idle" })
  end
  return out
end
function offline.on_play(doc, ev)
  local p, e = playlist(doc, ev.playlist); if not p then return nil, e end
  if not offline.snapshot(doc, p) then return nil, err("unavailable", "playlist", "no complete offline snapshot") end
  local pub = current(doc); pub.modes = pub.modes or {}; pub.modes[ev.playlist] = "offline"
  local d = copy(doc); d.spotify_offline = pub
  local r, pe = require("services.playback").on_request(d, { playlist = ev.playlist, index = ev.index, restart = true, now = ev.now })
  if not r then return nil, pe end
  r.state = r.state or {}; r.state.spotify_offline = r.state.spotify_offline or pub
  r.state.spotify_offline.modes = copy((doc.spotify_offline or {}).modes or {})
  return r
end

local S = {}
S.playlist = { type = "object", additionalProperties = false, required = { "playlist" }, properties = { playlist = { type = "string", minLength = 1, maxLength = 100 } } }
S.mode = copy(S.playlist); S.mode.required = { "playlist", "mode" }; S.mode.properties.mode = { type = "string", enum = { "online", "auto", "offline" } }
S.play = copy(S.playlist); S.play.properties.index = { type = "integer", minimum = 1, maximum = 10000 }
function offline.install(api, dispatch)
  api.command("spotify_offline.sync", S.playlist, function(doc, p, ev) p = copy(p); p.now = ev.now; return offline.on_sync(doc, p) end)
  api.command("spotify_offline.remove", S.playlist, offline.on_remove)
  api.command("spotify_offline.mode", S.mode, offline.on_mode)
  api.command("spotify_offline.play", S.play, function(doc, p, ev) p = copy(p); p.now = ev.now; return offline.on_play(doc, p) end)
  api.command("spotify_offline.forget_account", { type = "object", additionalProperties = false }, offline.on_forget)
  local protected = require("services.security").PROTECTED_V2
  for _, k in ipairs({ "sync", "remove", "mode", "forget_account" }) do protected["spotify_offline." .. k] = true end
  dispatch.on("boot", "spotify_offline", offline.on_boot)
  dispatch.on("offline.binary", "spotify_offline", offline.on_binary)
  dispatch.on("offline.modes", "spotify_offline", offline.on_modes)
  dispatch.on("offline.catalog", "spotify_offline", offline.on_catalog)
  dispatch.on("offline.job", "spotify_offline", offline.on_job)
  dispatch.on("offline.player", "spotify_offline", offline.on_player)
  dispatch.on("offline.process", "spotify_offline", offline.on_process)
  dispatch.on("offline.job_final", "spotify_offline", offline.on_job_final)
  dispatch.on("offline.player_final", "spotify_offline", offline.on_player_final)
  dispatch.on("playback.changed", "spotify_offline", offline.on_playback_changed)
  dispatch.on_timer("offline.poll", "spotify_offline", offline.on_timer)
end
return offline
