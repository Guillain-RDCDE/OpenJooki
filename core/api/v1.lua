-- api.v1: the 2018 contract, kept for one release (ADR-0005).
--   page -> Jooki   /j/web/input/<NAME>   JSON payload
--   Jooki -> page   /j/web/output/state   the 1.x state document (full or partial)
--                   /j/web/output/error   { msg, info }
-- Every v1 command maps onto the same services as v2; the state document is
-- rebuilt from ours (docs/22 §3.1). Owns state.userMessages.
local json = require("vendor.json")
local library = require("services.library")
local playback = require("services.playback")
local device = require("services.device")
local uploads = require("services.uploads")
local bedtime = require("services.bedtime")
local schema = require("api.schema")
local v1 = {}

v1.TOPIC_STATE, v1.TOPIC_ERROR = "/j/web/output/state", "/j/web/output/error"

local PB_STATE = { idle = "STOPPED", starting = "STARTING", playing = "PLAYING", paused = "PAUSED", ended = "ENDED" }

local function now_playing(pb)
  local n = pb and pb.now
  if not n then return {} end
  return { album = n.album, artist = n.artist, audiobook = n.audiobook, duration_ms = n.duration_ms, hasNext = n.has_next,
           hasPrev = n.has_prev, image = n.image, playlistId = n.playlist, service = n.service, source = n.source, uri = n.uri,
           track = n.title, trackId = n.track, trackIndex = n.index, queueIndex = n.queue_pos }
end

local function flags_list(flags)
  local out = {}
  for k in pairs(flags or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

--- Sub-trees of the 1.x document, each built from our state.
local PARTS = {}
function PARTS.db(doc) return { playlists = (doc.library or {}).playlists or {}, tracks = (doc.library or {}).tracks or {}, tokens = (doc.library or {}).tokens or {} } end
function PARTS.audio(doc)
  local pb = doc.playback or {}
  return { config = doc.audiocfg or {}, playback = { state = PB_STATE[pb.state or "idle"], position_ms = pb.position_ms or 0 }, nowPlaying = now_playing(pb) }
end
function PARTS.device(doc)
  local d = doc.device or {}
  local h = doc.health or {}
  return { flags = flags_list(doc.flags), toy_safe = d.toy_safe, id = d.id, hostname = d.hostname, ip = (doc.net or {}).ip or d.ip,
           wifi_mac = d.wifi_mac, machine = d.machine, firmware = d.firmware, openjooki = d.openjooki or d.core,
           diskUsage = d.diskUsage, usage = d.usage, core = d.core, rss_kb = h.rss_kb }
end
function PARTS.nfc(doc) return doc.nfc or {} end
function PARTS.power(doc) return doc.power or {} end
function PARTS.wifi(doc)
  local n = doc.net or {}
  return { ssid = n.ssid, bssid = n.bssid, ch = n.channel, signal = n.signal, stat = n.connected and "success" or nil, ip = n.ip }
end
function PARTS.userMessages(doc) return doc.userMessages or {} end
function PARTS.bedtime(doc)
  local b = doc.bedtime
  if not b then return nil end
  return { cfg = b.cfg, night = b.night, sleep = b.sleep, resume = doc.resume or {} }
end
function PARTS.net(doc) return doc.net end
function PARTS.bluetooth(doc) return doc.bluetooth or {} end

function v1.state(doc)
  return { userMessages = PARTS.userMessages(doc), nfc = PARTS.nfc(doc), audio = PARTS.audio(doc), wifi = PARTS.wifi(doc),
           bt = (doc.bluetooth and doc.bluetooth.connected_mac) or "", bluetooth = PARTS.bluetooth(doc), power = PARTS.power(doc),
           mender = {}, spotify = doc.spotify or { active = false }, deezer = doc.deezer or {}, device = PARTS.device(doc),
           jplay = {}, db = PARTS.db(doc), bedtime = doc.bedtime, net = doc.net }
end

-- which 1.x sub-trees change when one of our keys changes
local MAP = { library = { "db" }, playback = { "audio" }, resume = { "bedtime" }, audiocfg = { "audio" }, device = { "device" }, flags = { "device" },
              health = { "device" }, nfc = { "nfc" }, power = { "power" }, net = { "wifi", "net", "device" }, userMessages = { "userMessages" },
              bedtime = { "bedtime" }, bluetooth = { "bluetooth" } }

--- Partial publish for the keys that changed (nil when none of them is visible in v1).
--- Contract kept from 1.x: a message carrying BOTH `db` and `device` means "an
--- upload request ended", so the coalesced path never puts them together;
--- only `force` (used by upload.done) does.
function v1.partial(doc, dirty_keys, force)
  local parts, any = {}, false
  for _, k in ipairs(dirty_keys) do
    for _, p in ipairs(MAP[k] or {}) do parts[p] = true any = true end
  end
  for _, p in ipairs(force or {}) do parts[p] = true any = true end
  if not any then return nil end
  if not force and parts.db and parts.device then
    parts.device = nil
    local first = v1.partial(doc, {}, { "device" })
    local msg = {}
    for p in pairs(parts) do msg[p] = PARTS[p](doc) end
    return { kind = "bus.publish", topic = v1.TOPIC_STATE, payload = msg }, first
  end
  local msg = {}
  for p in pairs(parts) do msg[p] = PARTS[p](doc) end
  return { kind = "bus.publish", topic = v1.TOPIC_STATE, payload = msg }
end

local function err_cmd(msg, info) return { kind = "bus.publish", topic = v1.TOPIC_ERROR, payload = { msg = msg, info = info } } end

--- 1.x error texts the page pattern-matches (docs/22, webui/app.js errorText).
local function v1_message(err)
  if not err then return "error" end
  if err.message == "TRASH_READONLY" then return "TRASH_READONLY" end
  if err.code == "not_found" then
    if err.field == "id" or err.field == "playlist" then return "playlistId invalid: " .. tostring(err.message) end
    if err.field == "trackId" then return "trackId invalid" end
    if err.field == "tagId" then return "unknown token" end
    return tostring(err.message)
  end
  if err.code == "read_only" then return "TRASH_READONLY" end
  if err.code == "invalid_argument" and err.field == "star" then return "invalid token type" end
  return tostring(err.message or err.code)
end

-- ------------------------------------------------------------------ commands
local H = {}    -- name -> function(doc, payload, ev) -> result | nil, err ; second return: force partial parts

local function lib(doc, which, fn) return library.mutate(doc, which, fn) end

H.GET_STATE = function(doc) return { commands = { { kind = "bus.publish", topic = v1.TOPIC_STATE, payload = v1.state(doc) } } } end
H.CONNECT = function() return { commands = { { kind = "emit", event = { type = "system.event", name = "Evt.Mobile.connect", no_pause = true } } } } end
H.PLAYLIST_PLAY = function(doc, p, ev)
  if type(p.playlistId) ~= "string" then return nil, { code = "not_found", field = "playlist", message = "nil playlistId" } end
  return playback.on_request(doc, { playlist = p.playlistId, index = tonumber(p.trackIndex), now = ev.now, restart = p.trackIndex ~= nil })
end
H.PLAYLIST_NEW = function(doc, p, ev)
  return lib(doc, { playlists = true }, function(l) return library.ops.playlist_new(l, { title = p.title, audiobook = p.audiobook == true, star = type(p.star) == "string" and p.star or nil }, ev.wall or ev.now or 0) end)
end
H.PLAYLIST_NEW_DEEZER = H.PLAYLIST_NEW
H.PLAYLIST_ADD_TRACK = function(doc, p) return lib(doc, { playlists = true }, function(l) return library.ops.playlist_add_track(l, p.playlistId, p.trackId) end) end
H.PLAYLIST_ADD_STREAM = function(doc, p, ev) return lib(doc, { playlists = true, tracks = true }, function(l) return library.ops.playlist_add_stream(l, p.playlistId, p.title, p.url, ev.wall or ev.now or 0) end) end
H.PLAYLIST_DELETE = function(doc, p) return lib(doc, { playlists = true, tracks = true }, function(l) return library.ops.playlist_delete(l, p.playlistId) end) end
H.PLAYLIST_UPDATE = function(doc, p)
  local pl = p.playlist
  if type(pl) ~= "table" then return nil, { code = "invalid_argument", field = "playlist", message = "missing playlist" } end
  if pl.id == nil then return nil, { code = "invalid_argument", field = "id", message = "missing playlistId" } end
  if pl.tracks ~= nil and type(pl.tracks) ~= "table" then return nil, { code = "invalid_argument", field = "tracks", message = "invalid tracks" } end
  if pl.title ~= nil and type(pl.title) ~= "string" then return nil, { code = "invalid_argument", field = "title", message = "invalid title type" } end
  local star = pl.star
  if pl.tagId and not star then star = nil end
  local r, err = lib(doc, { playlists = true, tracks = true }, function(l)
    local args = { id = pl.id, title = pl.title, star = star, audiobook = pl.audiobook, tracks = pl.tracks }
    if pl.tagId and star == nil and pl.star == nil then
      local tok = l.tokens[pl.tagId]
      if not tok then return nil, { code = "invalid_argument", field = "star", message = "invalid token type" } end
      args.star = tok.starId
    end
    return library.ops.playlist_update(l, args)
  end)
  return r, err, { "db", "device" }
end
H.PLAYLIST_ADD_UPLOAD = function(doc, p)
  local r = uploads.on_add(doc, { uploadId = p.uploadId, filename = p.filename, playlistId = p.playlistId })
  return r
end
H.PLAYLIST_ADD_FILE = function() return nil, { code = "unavailable", field = "", message = "PLAYLIST_ADD_FILE is not supported by OpenJooki 2.0" } end
H.TOKEN_EDIT = function(doc, p)
  if type(p.tagId) ~= "string" then return nil, { code = "not_found", field = "tagId", message = "unknown token" } end
  return lib(doc, { tokens = true }, function(l) return library.ops.token_edit(l, p.tagId, p.name, p.image) end)
end
H.TOKEN_DELETE = function(doc, p) return lib(doc, { tokens = true }, function(l) return library.ops.token_forget(l, p.tagId) end) end
H.DO_PAUSE = function(doc, _, ev) return playback.on_pause(doc, { source = "page", now = ev.now }) or {} end
H.DO_PLAY = function(doc, _, ev) return playback.on_resume(doc, { now = ev.now }) or {} end
H.DO_NEXT = function(doc, _, ev) return playback.on_next(doc, { forced = true, now = ev.now }) or {} end
H.DO_PREV = function(doc, _, ev) return playback.on_prev(doc, { forced = true, now = ev.now }) or {} end
H.SEEK = function(doc, p)
  if p.position_ms == nil then return nil, { code = "invalid_argument", field = "position_ms", message = "missing position_ms" } end
  return playback.on_seek(doc, { ms = p.position_ms }) or {}
end
H.SKIP_SEC = function(doc, p)
  if p.delta_s == nil then return nil, { code = "invalid_argument", field = "delta_s", message = "missing delta_s" } end
  return playback.on_skip(doc, { seconds = p.delta_s }) or {}
end
H.SET_VOL = function(doc, p)
  local v = tonumber(p.vol)
  if not v then return nil, { code = "invalid_argument", field = "vol", message = "missing or invalid vol " .. tostring(p.vol) } end
  return device.set_volume(doc, v), nil, { "audio" }
end
H.SET_CFG = function(doc, p)
  local a = {}
  for k, v in pairs(doc.audiocfg or {}) do a[k] = v end
  if p.shuffle_mode ~= nil then a.shuffle_mode = p.shuffle_mode == true end
  if p.repeat_mode ~= nil then
    local m = p.repeat_mode
    if m == true then m = 1 elseif m == false then m = 0 end
    a.repeat_mode = tonumber(m) or a.repeat_mode
  end
  return { state = { audiocfg = a }, commands = { { kind = "files.write", path = ((doc.config or {}).data_dir or "/jooki/external/jooki") .. "/audiocfg.json", doc = a, version = 1 } } }, nil, { "audio" }
end
H.SET_TOY_SAFE = function(doc, p) return device.on_toy_safe(doc, { enable = p.enable == true }) end
H.SET_WIFI = function(_, p)
  if type(p.ssid) ~= "string" then return nil, { code = "invalid_argument", field = "ssid", message = "missing ssid" } end
  return { commands = { { kind = "shell", action = "wifi_add", args = { ssid = p.ssid, password = p.password, lang = "EN" } } } }
end
H.SHUTDOWN = function(_, p, ev) return device.on_off_request(nil, { reason = tostring(p.src or "page"), now = ev.now }) end
H.MESSAGE_DISMISS = function(doc, p)
  local id = tonumber(p.id)
  if not id or id <= 0 then return nil, { code = "invalid_argument", field = "id", message = "invalid msg id " .. tostring(p.id) } end
  local msgs = {}
  local found = false
  for _, m in ipairs(doc.userMessages or {}) do
    if m.id == id then found = true else msgs[#msgs + 1] = m end
  end
  if not found then return nil, { code = "not_found", field = "id", message = "invalid msg id " .. tostring(id) } end
  return { state = { userMessages = msgs } }
end
H.SWITCH_LOCALE = function(_, p)
  local l = string.upper(tostring(p.locale or ""))
  if l == "" then return nil, { code = "invalid_argument", field = "locale", message = "missing locale" } end
  return { commands = { { kind = "shell", action = "set_lang", args = { lang = l } } } }
end
H.OJ_SLEEP = function(doc, p, ev) return bedtime.on_sleep(doc, p, ev.now) end
H.OJ_BEDTIME_SET = function(doc, p, ev) return bedtime.on_set(doc, p, ev.wall) end
H.OJ_RESUME_RESET = function(doc, p)
  if type(p.playlistId) ~= "string" then return nil, { code = "invalid_argument", field = "playlistId", message = "invalid payload" } end
  return playback.on_resume_reset(doc, p.playlistId)
end
H.OJ_UPDATE_CHECK = function() return { commands = { { kind = "emit", event = { type = "update.check" } } } } end
H.OJ_UPDATE_START = function() return { commands = { { kind = "emit", event = { type = "update.start" } } } } end
v1.handlers = H

--- The handler for v1.cmd events.
function v1.on_cmd(doc, ev)
  local ok, payload = pcall(json.decode, ev.raw)
  if not ok or type(payload) ~= "table" then
    if ev.name == "GET_STATE" or ev.name == "CONNECT" or ev.name == "DO_PLAY" or ev.name == "DO_PAUSE" or ev.name == "DO_NEXT" or ev.name == "DO_PREV" then
      payload = {}
    else
      return { commands = { err_cmd("received invalid message", ev.raw) } }
    end
  end
  local h = H[ev.name]
  if not h then return { commands = { err_cmd("unknown topic " .. tostring(ev.name)) } } end
  local hok, result, err, force = pcall(h, doc, payload, ev)
  if type(force) ~= "table" then force = nil end   -- library.mutate returns the op's own value third
  if not hok then
    return { commands = { { kind = "log", level = "error", key = "v1.handler_failed", fields = { name = ev.name, err = tostring(result) } }, err_cmd("ERR_INTERNAL") } }
  end
  if err then
    return { commands = { err_cmd(v1_message(err), payload) } }
  end
  result = result or {}
  if force then
    result.commands = result.commands or {}
    result.commands[#result.commands + 1] = { kind = "emit", event = { type = "v1.force_publish", parts = force } }
  end
  return result
end

local next_msg_id = 0
--- user.message { level, messageType, extra } -> userMessages (dedup by type, like 1.x msg_set for errors)
function v1.on_user_message(doc, ev)
  local msgs = {}
  for _, m in ipairs(doc.userMessages or {}) do msgs[#msgs + 1] = m end
  next_msg_id = next_msg_id + 1
  msgs[#msgs + 1] = { id = next_msg_id, timestamp = ev.wall or 0, level = ev.level or "ERROR", messageType = ev.messageType, extra = ev.extra }
  -- published at once (before the upload's closing db+device message), as 1.x did
  return { state = { userMessages = msgs }, commands = { { kind = "bus.publish", topic = v1.TOPIC_STATE, payload = { userMessages = msgs } } } }
end

function v1.on_force_publish(doc, ev)
  local cmd = v1.partial(doc, {}, ev.parts)
  return cmd and { commands = { cmd } } or nil
end

--- after an upload (ok or not): the 1.x page waits for a partial with db AND device
function v1.on_upload_done(doc)
  return { commands = { v1.partial(doc, {}, { "db", "device" }) } }
end

function v1.install(dispatch)
  dispatch.on("v1.cmd", "v1", v1.on_cmd)
  dispatch.on("user.message", "v1", v1.on_user_message)
  dispatch.on("v1.force_publish", "v1", v1.on_force_publish)
  dispatch.on("upload.done", "v1", v1.on_upload_done)
end

v1.schema = schema
return v1
