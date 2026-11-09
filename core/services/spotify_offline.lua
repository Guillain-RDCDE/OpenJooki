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
    catalog = scratch .. "/catalog.json", job = scratch .. "/job.json", queue = root .. "/queue.json" }
end
local function current(doc) return copy(doc.spotify_offline or { available = false, account_ready = false, modes = {}, playlists = {}, queue = {}, jobs = {}, previews = {} }) end
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
local function write_queue(doc, pub)
  return { kind = "files.write", path = offline.paths(doc).queue, doc = { account_id = pub.account_id, items = pub.queue or {}, jobs = pub.jobs or {},
    active = busy(pub) and { playlist = pub.download.playlist, uri = pub.download.uri } or nil, paused = pub.queue_paused }, version = 1 }
end
local function restore_queue(doc, pub, int)
  if not int.queue_loaded or not pub.catalog_loaded then return end
  if int.queue_account == pub.account_id and not int.restore_pending then return end
  pub.queue, pub.jobs, pub.queue_paused = {}, {}, nil
  local saved = int.saved_queue
  if saved and saved.account_id == pub.account_id and pub.account_id then
    local seen = {}
    local function add(item)
      if type(item) ~= "table" then return end
      local p = playlist(doc, item.playlist)
      if p and p.spotify.uri == item.uri and not seen[item.uri] and #pub.queue < 32 then
        pub.queue[#pub.queue + 1] = { playlist = item.playlist, uri = item.uri, title = p.title }
        seen[item.uri] = true
      end
    end
    add(saved.active)
    for _, item in ipairs(saved.items or {}) do add(item) end
    pub.jobs = type(saved.jobs) == "table" and saved.jobs or {}
    pub.queue_paused = saved.paused
  end
  int.queue_account, int.restore_pending, int.saved_queue = pub.account_id, nil, nil
end
local function job_summary(data)
  return { phase = data.phase, completed = data.completed, total = data.total, bytes = data.bytes, error = data.error }
end
local function audio_active(doc)
  local pb = doc.playback or {}
  return pb.now and pb.now.service == SERVICE and (pb.state == "playing" or pb.state == "starting")
end
local function kick_queue(doc, pub, int, cmds, now)
  if int.restore_pending or pub.queue_paused or busy(pub) or not pub.account_ready or audio_active(doc) or ((pub.auth or {}).phase == "requested" or (pub.auth or {}).phase == "working" or (pub.auth or {}).phase == "checking") then return end
  pub.queue, pub.jobs = pub.queue or {}, pub.jobs or {}
  while #pub.queue > 0 do
    local item = table.remove(pub.queue, 1)
    local p = playlist(doc, item.playlist)
    if p and p.spotify.uri == item.uri then
      int.next_id = (int.next_id or 0) + 1
      int.job_request = string.format("%.0f", (now or 0) * 1000) .. "-" .. int.next_id
      int.job_text, int.job_process, int.job_wait = nil, nil, 0
      pub.download = { uri = item.uri, playlist = item.playlist, phase = "resolving", completed = 0, total = 0 }
      pub.jobs[item.uri] = job_summary(pub.download)
      cmds[#cmds + 1] = write_queue(doc, pub)
      cmds[#cmds + 1] = action("sync", { uri = item.uri, request = int.job_request })
      return
    end
    pub.jobs[item.uri] = { phase = "error", error = "playlist_changed" }
    cmds[#cmds + 1] = write_queue(doc, pub)
  end
end
local function write_modes(doc, pub)
  return { kind = "files.write", path = offline.paths(doc).modes, doc = { modes = pub.modes or {} }, version = 1 }
end
local function enabled(doc) return (doc.config or {}).spotify_offline_enabled == true end

function offline.on_boot(doc)
  if not enabled(doc) then return nil end
  local p = offline.paths(doc)
  local int = internal(doc); int.restore_pending = true
  return result(current(doc), int, {
    { kind = "files.stat", path = (doc.config or {}).spotify_offline_binary or p.root .. "/current/spotify_player", reply = "offline.binary" },
    read(p.modes, "offline.modes"), read(p.queue, "offline.queue"),
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
  if int.preview then
    cmds[#cmds + 1] = read(int.preview.path, "offline.preview")
    int.preview_wait = (int.preview_wait or 0) + 1
  end
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
      if star and item.star == star and (offline.mode(doc, id) == "auto" or offline.mode(doc, id) == "offline") and offline.snapshot(doc, item) and (not pb.now or pb.now.playlist == id) then
        int.auto_routed = true
        if not (pb.now and pb.now.service == SERVICE) then cmds[#cmds + 1] = util.emit("playback.request", { playlist = id, now = ev and ev.now }) end
        return { state = { spotify_offline_int = int }, commands = cmds }
      end
    end
  end
  local pub = current(doc)
  int.helper_ticks = (int.helper_ticks or 0) + 1
  if int.helper_ticks > 15 then pub.helper_ready = false end
  if (pub.auth or {}).phase == "checking" then
    int.auth_ticks = (int.auth_ticks or 0) + 1
    if int.auth_ticks > 20 then
      pub.auth.phase, pub.auth.error = "error", "activation_failed"
      cmds[#cmds + 1] = { kind = "files.write_text", path = p.scratch .. "/auth-request", text = "" }
      cmds[#cmds + 1] = action("auth_cancel", { request = pub.auth.request })
    end
  end
  if int.preview and int.preview_wait and int.preview_wait > 90 and ((pub.previews or {})[int.preview.uri] or {}).phase == "loading" then
    pub.previews[int.preview.uri].phase, pub.previews[int.preview.uri].error = "error", "network_timeout"
  end
  if busy(pub) and not int.job_process then
    int.job_wait = (int.job_wait or 0) + 1
    if int.job_wait >= 15 then
      pub.download.phase, pub.download.error = "error", "backend_start_failed"
      pub.jobs = pub.jobs or {}; pub.jobs[pub.download.uri] = job_summary(pub.download)
      cmds[#cmds + 1] = write_queue(doc, pub)
    end
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
  kick_queue(doc, pub, int, cmds, ev and ev.now)
  return result(pub, int, cmds)
end
function offline.on_cancel_queued(doc, ev)
  local pub, int = current(doc), internal(doc); local items = {}
  for _, item in ipairs(pub.queue or {}) do if item.playlist ~= ev.playlist then items[#items + 1] = item else pub.jobs[item.uri] = nil end end
  pub.queue = items
  return result(pub, int, { write_queue(doc, pub) })
end
function offline.on_resume_queue(doc)
  local pub, int = current(doc), internal(doc); pub.queue_paused = nil
  return result(pub, int, { write_queue(doc, pub), action("catalog") })
end
function offline.on_preview_request(doc, ev)
  local p, e = playlist(doc, ev.playlist); if not p then return nil, e end
  local pub, int = current(doc), internal(doc)
  if not (pub.metadata_ready or pub.account_ready) then return nil, err("unavailable", "", "Spotify metadata authentication required") end
  local offset = tonumber(ev.offset) or 0
  if offset < 0 or offset ~= math.floor(offset) or offset > 10000 then return nil, err("invalid_argument", "offset", "invalid metadata page") end
  if int.preview and (pub.previews or {})[int.preview.uri] and pub.previews[int.preview.uri].phase == "loading" then return result(pub, int) end
  int.next_id = (int.next_id or 0) + 1
  local request = string.format("%.0f", (ev.now or 0) * 1000) .. "-" .. int.next_id
  local path = offline.paths(doc).scratch .. "/preview-" .. p.spotify.uri:sub(18) .. ".json"
  int.preview_wait = 0
  int.preview = { uri = p.spotify.uri, request = request, path = path, account_id = pub.account_id }
  pub.previews = { [p.spotify.uri] = { phase = "loading", offset = offset, tracks = {} } }
  return result(pub, int, { action("preview", { uri = p.spotify.uri, request = request, offset = offset }) })
end
function offline.on_preview(doc, ev)
  local pub, int = current(doc), internal(doc)
  if not int.preview or ev.path ~= int.preview.path or not ev.text or int.preview_text == ev.text then return nil end
  local ok, data = pcall(json.decode, ev.text)
  if not (ok and type(data) == "table" and data.account_id == pub.account_id and data.request == int.preview.request and data.uri == int.preview.uri) then return nil end
  int.preview_wait = 0
  int.preview_text = ev.text; pub.previews = { [data.uri] = data }
  return result(pub, int)
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
function offline.on_queue(doc, ev)
  local int = internal(doc); int.queue_loaded = true
  local ok, data = pcall(json.decode, ev.text or "")
  if ok and type(data) == "table" and type(data.items) == "table" then int.saved_queue = data end
  local pub = current(doc); restore_queue(doc, pub, int)
  return result(pub, int, pub.catalog_loaded and { write_queue(doc, pub) } or {})
end
function offline.on_catalog(doc, ev)
  local int = internal(doc)
  if not ev.text or ev.text == int.catalog_text then return nil end
  local ok, data = pcall(json.decode, ev.text)
  if not (ok and type(data) == "table" and data.version == 1 and type(data.playlists) == "table") then return nil end
  local pub = current(doc)
  if int.forgetting and (data.account_ready or data.metadata_ready) then return nil end
  if not data.account_ready and not data.metadata_ready then int.forgetting = nil; pub.logging_out = false end
  int.catalog_text = ev.text
  local changed = pub.account_id ~= data.account_id
  if changed then
    pub.download, pub.player, pub.previews = nil, nil, {}
    int.preview, int.preview_text, int.job_process, int.session, int.controls = nil, nil, nil, nil, {}
  end
  pub.catalog_loaded = true
  pub.account_ready, pub.account_id = data.account_ready == true, data.account_id
  pub.playlists = data.playlists
  pub.storage = { used_bytes = data.used_bytes or 0, free_bytes = data.free_bytes or 0, quota_bytes = data.quota_bytes or 0 }
  pub.error = data.error
  pub.account_name, pub.premium_verified = data.account_name, data.premium_verified == true
  pub.metadata_ready = data.metadata_ready == true or data.account_ready == true
  if (pub.auth or {}).phase == "checking" and data.auth_request == pub.auth.request and not data.error then pub.auth.phase = "complete" end
  pub.storage.reserve_bytes = data.reserve_bytes or 0
  restore_queue(doc, pub, int)
  local r = result(pub, int, changed and int.queue_loaded and { write_queue(doc, pub) } or {})
  if changed and (doc.playback or {}).now and doc.playback.now.service == SERVICE then
    r.state.playback = copy(doc.playback); r.state.playback.state = "idle"
    r.commands[#r.commands + 1] = util.emit("playback.changed", { state = "idle" })
  end
  return r
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
  if not data.playlist then
    for id, p in pairs((doc.library or {}).playlists or {}) do if p.spotify and p.spotify.uri == data.uri then data.playlist = id; break end end
  end
  if data.phase == "error" and (data.error == "storage_full" or data.error == "authentication_required") then pub.queue_paused = data.error end
  pub.jobs = pub.jobs or {}; pub.jobs[data.uri] = job_summary(data)
  local cmds = {}
  if data.phase == "complete" or data.phase == "error" or data.phase == "interrupted" then cmds[1] = read(offline.paths(doc).catalog, "offline.catalog"); cmds[#cmds + 1] = write_queue(doc, pub) end
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
  pub.jobs = pub.jobs or {}; pub.jobs[pub.download.uri] = job_summary(pub.download)
  int.job_process = nil
  return result(pub, int, { write_queue(doc, pub) })
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
  pub.queue, pub.jobs = pub.queue or {}, pub.jobs or {}
  if busy(pub) and pub.download.uri == p.spotify.uri then return result(pub, int) end
  for _, item in ipairs(pub.queue) do if item.uri == p.spotify.uri then return result(pub, int) end end
  if #pub.queue >= 32 then return nil, err("conflict", "", "download queue is full") end
  pub.modes = pub.modes or {}; pub.modes[ev.playlist] = "auto"
  pub.queue[#pub.queue + 1] = { playlist = ev.playlist, uri = p.spotify.uri, title = p.title }
  pub.jobs[p.spotify.uri] = { phase = "queued" }
  local cmds = { write_modes(doc, pub), write_queue(doc, pub) }
  kick_queue(doc, pub, int, cmds, ev.now)
  return result(pub, int, cmds)
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
  return snap and snap.ready == true and type(snap.tracks) == "table" and (snap.total_tracks or #snap.tracks) > 0 and snap or nil
end
function offline.wants(doc, id)
  if not enabled(doc) or not (doc.spotify_offline or {}).account_ready then return false end
  local p = doc.library and doc.library.playlists[id]
  if not (p and p.spotify) then return false end
  local mode = offline.mode(doc, id)
  return mode == "offline" or (mode == "auto" and offline.snapshot(doc, p) ~= nil)
end
function offline.describe(id, p, snap, index)
  local t = snap.current_track or snap.tracks[index] or { name = p.title, artists = {} }
  local total = snap.total_tracks or #snap.tracks
  return { playlist = id, service = SERVICE, index = index, queue_pos = index, track = t.uri, uri = t.uri,
    title = t.name, artist = table.concat(t.artists or {}, ", "), album = t.album, duration_ms = t.duration_ms,
    source = p.title, audiobook = p.audiobook == true, has_next = index < total, has_prev = index > 1, image = p.image }
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
  local pb = doc.playback or {}
  if p.resume and not opts.restart and not opts.index and pb.now and pb.now.service == SERVICE and pb.now.playlist == id then
    if pb.state == "playing" or pb.state == "starting" or pb.state == "paused" then
      local r = pb.state == "paused" and offline.transport(doc, "resume") or result(current(doc), internal(doc))
      r.now, r.continued = copy(pb.now), true
      return r
    end
  end
  if busy(current(doc)) then return nil, err("conflict", "", "offline download is running") end
  local index = tonumber(opts.index) or 1
  if index ~= math.floor(index) or index < 1 or index > (snap.total_tracks or #snap.tracks) then return nil, err("invalid_argument", "index", "invalid offline track index") end
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
  cmds[#cmds + 1] = action("play", { uri = p.spotify.uri, session = session, index = index - 1, resume = p.resume == true and not opts.restart and not opts.index })
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
  if index < 1 or index > (snap.total_tracks or #snap.tracks) then return nil end
  if type(data.track) == "table" then snap.current_track = data.track end
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
  pub.account_ready, pub.metadata_ready, pub.premium_verified, pub.account_id, pub.playlists, pub.download = false, false, false, nil, {}, nil
  int.session, int.controls, int.forgetting, int.preview = nil, {}, true, nil
  pub.queue, pub.jobs, pub.previews, pub.auth, pub.queue_paused = {}, {}, {}, { phase = "logged_out" }, nil
  int.saved_queue, int.queue_account = nil, nil
  local cmds = r and r.commands or {}
  cmds[#cmds + 1] = { kind = "files.write_text", path = offline.paths(doc).scratch .. "/auth-request", text = "" }
  pub.logging_out = true
  cmds[#cmds + 1] = write_queue(doc, pub); cmds[#cmds + 1] = action("forget")
  local out = result(pub, int, cmds)
  if (doc.playback or {}).now and doc.playback.now.service == SERVICE then
    out.state.playback = copy(doc.playback); out.state.playback.state = "idle"
    out.commands[#out.commands + 1] = util.emit("playback.changed", { state = "idle" })
  end
  return out
end
function offline.on_login(doc, ev)
  local pub, int = current(doc), internal(doc)
  if int.forgetting then return nil, err("unavailable", "", "wait for sign-out to finish") end
  if not pub.available or not pub.helper_ready then return nil, err("unavailable", "", "computer login helper is not connected") end
  if busy(pub) then return nil, err("conflict", "", "wait for the active download before changing accounts") end
  local mode = ev.mode or "metadata"
  if mode ~= "metadata" and mode ~= "premium" then return nil, err("invalid_argument", "mode", "invalid login mode") end
  int.next_id = (int.next_id or 0) + 1; int.auth_ticks = 0
  local id = string.format("%.0f", (ev.now or 0) * 1000) .. "-" .. int.next_id
  pub.auth = { request = id, mode = mode, phase = "requested" }
  local stopped = offline.transport(doc, "stop")
  if stopped and stopped.state then int = stopped.state.spotify_offline_int end
  local cmds = stopped and stopped.commands or {}
  cmds[#cmds + 1] = { kind = "files.write_text", path = offline.paths(doc).scratch .. "/auth-request", text = id }
  return result(pub, int, cmds)
end
function offline.on_cancel_login(doc)
  local pub, int = current(doc), internal(doc)
  local request = (pub.auth or {}).request
  pub.auth = { phase = "cancelled" }
  return result(pub, int, { { kind = "files.write_text", path = offline.paths(doc).scratch .. "/auth-request", text = "" }, action("auth_cancel", { request = request }) })
end
function offline.on_auth_helper(doc, ev)
  local pub, int = current(doc), internal(doc)
  pub.helper_ready, int.helper_ticks = true, 0
  if ev.phase == "ready" then return result(pub, int) end
  if not pub.auth or pub.auth.request ~= ev.request or (pub.auth.phase ~= "requested" and pub.auth.phase ~= "working") then return nil end
  if ev.phase == "url" then
    if type(ev.url) ~= "string" or not ev.url:match("^https://accounts%.spotify%.com/authorize%?") then return nil, err("invalid_argument", "url", "invalid Spotify authorization URL") end
    pub.auth.phase, pub.auth.url = "working", ev.url
  elseif ev.phase == "working" then pub.auth.phase = "working"
  elseif ev.phase == "error" then pub.auth.phase, pub.auth.error, pub.auth.url = "error", ev.error or "login_failed", nil
  elseif ev.phase == "complete" then
    pub.auth.phase, pub.auth.url, int.auth_ticks = "checking", nil, 0
    return result(pub, int, { action("auth_activate", { request = ev.request }) })
  end
  return result(pub, int)
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
  local login_schema = { type = "object", additionalProperties = false, properties = { mode = { type = "string", enum = { "metadata", "premium" } } } }
  local helper_schema = { type = "object", additionalProperties = false, required = { "phase" }, properties = {
    phase = { type = "string", enum = { "ready", "working", "url", "complete", "error" } }, request = { type = "string", maxLength = 64 }, url = { type = "string", maxLength = 4096 }, error = { type = "string", maxLength = 100 } } }
  api.command("spotify_offline.login", login_schema, function(doc, p, ev) p = copy(p); p.now = ev.now; return offline.on_login(doc, p) end)
  api.command("spotify_offline.cancel_login", { type = "object", additionalProperties = false }, offline.on_cancel_login)
  api.command("spotify_offline.resume_queue", { type = "object", additionalProperties = false }, offline.on_resume_queue)
  api.command("spotify_offline.auth_helper", helper_schema, offline.on_auth_helper)
  api.command("spotify_offline.sync", S.playlist, function(doc, p, ev) p = copy(p); p.now = ev.now; return offline.on_sync(doc, p) end)
  api.command("spotify_offline.cancel_queued", S.playlist, offline.on_cancel_queued)
  local preview_schema = copy(S.playlist); preview_schema.properties.offset = { type = "integer", minimum = 0, maximum = 10000 }
  api.command("spotify_offline.preview", preview_schema, function(doc, p, ev) p = copy(p); p.now = ev.now; return offline.on_preview_request(doc, p) end)
  api.command("spotify_offline.remove", S.playlist, offline.on_remove)
  api.command("spotify_offline.mode", S.mode, offline.on_mode)
  api.command("spotify_offline.play", S.play, function(doc, p, ev) p = copy(p); p.now = ev.now; return offline.on_play(doc, p) end)
  api.command("spotify_offline.forget_account", { type = "object", additionalProperties = false }, offline.on_forget)
  local protected = require("services.security").PROTECTED_V2
  for _, k in ipairs({ "sync", "remove", "mode", "forget_account", "cancel_queued", "resume_queue", "login", "auth_helper", "cancel_login" }) do protected["spotify_offline." .. k] = true end
  dispatch.on("boot", "spotify_offline", offline.on_boot)
  dispatch.on("offline.binary", "spotify_offline", offline.on_binary)
  dispatch.on("offline.queue", "spotify_offline", offline.on_queue)
  dispatch.on("offline.preview", "spotify_offline", offline.on_preview)
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
