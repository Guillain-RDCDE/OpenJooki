-- services.streaming: Spotify Connect and Deezer, kept by decision (ADR-0009).
-- A faithful port of the message paths of the original program (docs/22),
-- isolated from local playback: the closed daemons (spotify_ctrl, deezer_ctrl)
-- do the streaming; this module only carries messages and keeps two small
-- sub-trees: state.spotify = { username, saved, active }, state.deezer = { username, id, active }.
-- `saved` is the Jooki's own account, the one spotify_ctrl logs back into at every start (false: none).
-- The daemon keeps only the first account that reaches it with no account at all; any other one is a
-- guest, gone at the next restart, and the tokens then play on the saved account again.
-- What a daemon says about the track it plays reaches state.playback through one door,
-- playback.on_external: this module never writes the music machine's sub-tree itself.
-- Best effort: verified on the bench with a fake daemon, not against the services.
-- Note: the 2022 firmware ships spotify_ctrl but no deezer_ctrl (docs/22 §1).
local util = require("services.util")
local playback = require("services.playback")
local resume_rules = require("services.playback.resume")
local queue = require("services.playback.queue")
local streaming = {}

local SP, DZ = "/j/spotify/output/", "/j/deezer/output/"

local copy, emit = util.copy, util.emit
local function pub(topic, payload) return { kind = "bus.publish", topic = topic, payload = payload == nil and "" or tostring(payload) } end

local function hex2str(h) return (tostring(h):gsub("..", function(x) return string.char(tonumber(x, 16)) end)) end
local function str2hex(s) return (tostring(s):gsub(".", function(c) return string.format("%02X", string.byte(c)) end)) end
streaming.hex2str, streaming.str2hex = hex2str, str2hex

-- ------------------------------------------------------------------ helpers used by playback
--- Is this playlist a streaming one? Returns "SPOTIFY" | "DEEZER" | nil.
function streaming.service_of(p)
  if type(p) ~= "table" then return nil end
  if p.spotify then return "SPOTIFY" end
  if p.deezer then return "DEEZER" end
  return nil
end

--- The top-level fields of a protobuf message, by number (the first of each; varints as
--- numbers, exact up to 2^53, length-delimited ones as strings). nil when the bytes do not parse.
local function proto_fields(raw)
  local i, n, out = 1, #raw, {}
  local function varint()
    local v, mul = 0, 1
    while i <= n do
      local b = raw:byte(i); i = i + 1
      v = v + (b % 128) * mul
      if b < 128 then return v end
      mul = mul * 128
    end
  end
  while i <= n do
    local key = varint()
    if not key then return nil end
    local field, wire = math.floor(key / 8), key % 8
    local val
    if wire == 0 then
      val = varint()
      if not val then return nil end
    elseif wire == 2 then
      local len = varint()
      if not len or i + len - 1 > n then return nil end
      val = raw:sub(i, i + len - 1); i = i + len
    else
      return nil
    end
    if out[field] == nil then out[field] = val end
  end
  return out
end

--- A Spotify preset's context URI (field 2) and track index (field 2 of field 3), or nil.
local function preset_place(raw)
  local f = proto_fields(raw)
  local inner = f and type(f[3]) == "string" and proto_fields(f[3])
  local index = inner and inner[2]
  if type(f and f[2]) ~= "string" or type(index) ~= "number" then return nil end
  return { uri = f[2], index = index }
end
streaming.preset_place = preset_place

--- The request a patched spotify_ctrl takes on play_preset (tools/openjooki/spotify_direct.py):
--- the context URI null-padded to 64 bytes, then five little-endian 32-bit words: track index,
--- 0, time in ms, 0, 0. 84 bytes in all; a preset never starts with "s".
local function direct_request(uri, index, ms)
  local function u32(v)
    v = math.floor(v)
    return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  return uri .. string.rep("\0", 64 - #uri) .. u32(index) .. u32(0) .. u32(ms) .. u32(0) .. u32(0)
end
streaming.direct_request = direct_request

--- The commands that start a Spotify playlist at its place and, without the patch, where to seek
--- once it plays (its place in resume.json, less the audiobooks' rewind). Spotify starts a preset
--- at the top of its playlist whatever track it names, so where spotify_ctrl is patched the place
--- goes as a direct request instead, track and time together, and there is nothing to seek.
local function place_commands(doc, playlist_id, p)
  local saved = p.resume and doc.resume and doc.resume[playlist_id]
  saved = saved and saved.preset and saved
  local seek_ms = saved and (tonumber(saved.pos) or 0) - resume_rules.BACK_PAUSE
  if not (seek_ms and seek_ms >= resume_rules.MIN_BACK) then seek_ms = nil end
  local preset = hex2str(saved and saved.preset or p.spotify.preset or "")
  local place = saved and (doc.streaming_int or {}).direct and preset_place(preset)
  if place and place.uri and #place.uri < 64 and place.uri:match("^spotify:") and place.index and place.index < 2 ^ 31 then
    local cmds = { pub(SP .. "play_preset", direct_request(place.uri, place.index, seek_ms or 0)) }
    if saved.id and saved.id ~= "" then
      cmds[#cmds + 1] = emit("streaming.find", { playlist = playlist_id, id = saved.id, album = saved.album, index = place.index, pos = seek_ms })
    end
    return cmds, nil
  end
  return { pub(SP .. "play_preset", preset) }, seek_ms
end

-- Music playlists only: saved positions and all book/podcast contexts take priority.
function streaming.wants_random(doc, p)
  local _, _, enabled = queue.modes(doc, p)
  local uri = p.spotify and p.spotify.uri
  return enabled and not p.audiobook and not p.resume and type(uri) == "string" and uri:find(":playlist:", 1, true) ~= nil
end

local RANDOM_WAIT_S = 12
local function random_done(doc, r, reason)
  local int = copy((r.state or {}).streaming_int or doc.streaming_int or {})
  local f = int.random_start
  if not f then return r end
  int.random_start = nil
  r.state = r.state or {}; r.state.streaming_int = int
  r.commands = r.commands or {}
  local sp = (r.state or {}).spotify or doc.spotify or {}
  if f.phase ~= "loading" and (sp.track or {}).source_uri == f.uri then
    local p = ((doc.library or {}).playlists or {})[f.playlist] or {}
    local shuffle = queue.modes(doc, p)
    r.commands[#r.commands + 1] = pub(SP .. "set_shuffle", shuffle and 1 or 0)
  end
  r.commands[#r.commands + 1] = { kind = "timer.cancel", name = "streaming.random" }
  r.commands[#r.commands + 1] = { kind = "timer.cancel", name = "streaming.random_probe" }
  r.commands[#r.commands + 1] = emit("volume.apply", {})
  r.commands[#r.commands + 1] = { kind = "log", level = reason == "ready" and "info" or "warn", key = "streaming.random_" .. reason }
  if f.phase == "muting" and reason == "timeout" then
    local p = ((doc.library or {}).playlists or {})[f.playlist]
    if p then for _, c in ipairs(place_commands(doc, f.playlist, p)) do r.commands[#r.commands + 1] = c end end
  end
  return r
end

-- Wait for the new context to play before changing shuffle: the Spotify SDK
-- explicitly says a shuffle command sent during context loading can be lost.
function streaming.on_random_start(doc, ev)
  local p = ((doc.library or {}).playlists or {})[ev.playlist]
  if not p then return nil end
  if not streaming.wants_random(doc, p) then return { commands = place_commands(doc, ev.playlist, p) } end
  local int = copy(doc.streaming_int or {})
  int.random_start = { playlist = ev.playlist, uri = p.spotify.uri, phase = (doc.device or {}).volume_api == 2 and "muting" or "loading" }
  int.find = nil
  local device = require("services.device")
  local silence = device.volume_command and device.volume_command(doc, 0) or { kind = "host.volume", percent = 0 }
  local cmds = { silence, { kind = "timer.cancel", name = "streaming.find" },
                 { kind = "timer.once", name = "streaming.random", seconds = RANDOM_WAIT_S } }
  if int.random_start.phase == "loading" then
    local start = place_commands(doc, ev.playlist, p)
    for _, c in ipairs(start) do cmds[#cmds + 1] = c end
  end
  return { state = { streaming_int = int }, commands = cmds }
end

function streaming.on_volume_confirmed(doc, ev)
  local int = copy(doc.streaming_int or {})
  local f = int.random_start
  if not f or f.phase ~= "muting" or ev.percent ~= 0 or not ev.ok then return nil end
  local p = ((doc.library or {}).playlists or {})[f.playlist]
  if not p then return random_done(doc, {}, "cancelled") end
  f.phase = "loading"
  return { state = { streaming_int = int }, commands = place_commands(doc, f.playlist, p) }
end

local function random_step(doc, r, ev)
  local pending = (doc.streaming_int or {}).random_start
  if not pending then return r end
  r = r or {}; r.state = r.state or {}; r.commands = r.commands or {}
  local pb = r.state.playback or doc.playback or {}
  local sp = r.state.spotify or doc.spotify or {}
  local track = sp.track or {}
  if ev.type == "spotify.logout" or ev.type == "spotify.play_error" or ev.type == "spotify.login_required" then return random_done(doc, r, "failed") end
  if not (pb.now and pb.now.service == "SPOTIFY" and pb.now.playlist == pending.playlist) then return random_done(doc, r, "cancelled") end
  local int = copy(r.state.streaming_int or doc.streaming_int or {})
  local f = copy(pending)
  int.random_start = f; r.state.streaming_int = int
  if f.phase == "loading" then
    if ev.type == "spotify.now_playing" and track.source_uri == f.uri then
      -- Chapter metadata also protects saved Spotify books without a resume flag.
      local title = (track.track or ""):lower()
      if title:match("^kapitel%s+%d") or title:match("^chapter%s+%d") then return random_done(doc, r, "book") end
      f.metadata = track.restricted ~= true
    end
    -- The daemon sends position only while actually playing. A context switch
    -- while already playing need not produce another playing notification.
    if f.metadata and ev.type == "spotify.position" and track.source_uri == f.uri and pb.state ~= "playing" then
      local playing = playback.on_external(doc, { service = "SPOTIFY", state = "playing", position_ms = ev.ms })
      for k, v in pairs(playing.state or {}) do r.state[k] = v end
      for _, c in ipairs(playing.commands or {}) do r.commands[#r.commands + 1] = c end
      pb = r.state.playback or pb
    end
    if f.metadata and pb.state == "playing" and track.source_uri == f.uri then
      f.phase = "shuffle"
      f.first = (track.track or "") .. "\t" .. (track.album or "") .. "\t" .. (track.artist or "")
      r.commands[#r.commands + 1] = pub(SP .. "set_shuffle", 1)
      r.commands[#r.commands + 1] = { kind = "timer.once", name = "streaming.random_probe", seconds = 1 }
    end
  elseif f.phase == "reset_shuffle" and ev.type == "spotify.set_cfg" and ev.shuffle_mode == false then
    f.phase = "shuffle_retry"
    r.commands[#r.commands + 1] = pub(SP .. "set_shuffle", 1)
    r.commands[#r.commands + 1] = { kind = "timer.cancel", name = "streaming.random_probe" }
  elseif (f.phase == "shuffle" or f.phase == "shuffle_retry") and ev.type == "spotify.set_cfg" and ev.shuffle_mode == true then
    f.phase = "skipping"
    r.commands[#r.commands + 1] = { kind = "timer.cancel", name = "streaming.random_probe" }
    r.commands[#r.commands + 1] = pub(SP .. "next")
  elseif f.phase == "skipping" and ev.type == "spotify.now_playing" and track.source_uri == f.uri then
    local key = (track.track or "") .. "\t" .. (track.album or "") .. "\t" .. (track.artist or "")
    if key ~= f.first then f.phase = "settling"; f.candidate = key end
  elseif f.phase == "settling" and ev.type == "spotify.position" and track.source_uri == f.uri and track.restricted ~= true then
    local key = (track.track or "") .. "\t" .. (track.album or "") .. "\t" .. (track.artist or "")
    if key == f.candidate and tonumber(ev.ms) and ev.ms >= 0 and ev.ms <= 5000 then return random_done(doc, r, "ready") end
  end
  return r
end

-- Some SDK versions omit a callback when shuffle already has the requested
-- value. Make a bounded off/on transition, still waiting for the final on ACK.
function streaming.on_random_probe(doc)
  local int = copy(doc.streaming_int or {})
  local f = int.random_start
  if not f or (f.phase ~= "shuffle" and f.phase ~= "reset_shuffle") then return nil end
  local enable = f.phase == "reset_shuffle"
  f.phase = enable and "shuffle_retry" or "reset_shuffle"
  local cmds = { pub(SP .. "set_shuffle", enable and 1 or 0) }
  if not enable then cmds[#cmds + 1] = { kind = "timer.once", name = "streaming.random_probe", seconds = 1 } end
  return { state = { streaming_int = int }, commands = cmds }
end
function streaming.on_random_config(doc)
  local f = (doc.streaming_int or {}).random_start
  local p = f and ((doc.library or {}).playlists or {})[f.playlist]
  if f and not (p and streaming.wants_random(doc, p)) then return random_done(doc, {}, "cancelled") end
end

function streaming.on_random_timer(doc) return random_done(doc, {}, "timeout") end
function streaming.on_random_changed(doc)
  local f, pb = (doc.streaming_int or {}).random_start, doc.playback or {}
  if f and not (pb.now and pb.now.service == "SPOTIFY" and pb.now.playlist == f.playlist) then return random_done(doc, {}, "cancelled") end
end

local CONT_WAIT_S = 5   -- Spotify asked to continue and silent: the character's own place after this long

--- The now-playing record, the commands that start a streaming playlist and, for Spotify, where
--- to seek once it plays. A playlist set to resume first asks Spotify to continue the account's
--- playback on the Jooki: if that is the playlist, listened to on the phone since, it goes on
--- from the phone's place; otherwise the character's own place follows (streaming_int.cont).
--- When Spotify plays something else on the Jooki already, continuing would only resume that.
function streaming.start(doc, playlist_id, p)
  if p.spotify then
    local now = { playlist = playlist_id, service = "SPOTIFY", uri = p.spotify.uri, source = p.title, audiobook = false, image = p.image }
    local sp = doc.spotify or {}
    local other = sp.active and sp.track and sp.track.source_uri and sp.track.source_uri ~= p.spotify.uri
    if p.resume and not other then
      return now, { pub(SP .. "cont"), emit("streaming.cont", { playlist = playlist_id }),
                    { kind = "timer.once", name = "streaming.cont", seconds = CONT_WAIT_S } }, nil
    end
    if streaming.wants_random(doc, p) then
      return now, { emit("streaming.random_start", { playlist = playlist_id }) }, nil
    end
    local cmds, seek_ms = place_commands(doc, playlist_id, p)
    return now, cmds, seek_ms
  end
  if p.deezer then
    if not (doc.deezer and doc.deezer.active) then
      return nil, { emit("system.event", { name = "Evt.Deezer.NoLoginError" }) }
    end
    local uri = string.format("dzmedia:///%s/%s", tostring(p.deezer.type), tostring(p.deezer.id))
    local now = { playlist = playlist_id, service = "DEEZER", uri = uri, source = p.title, audiobook = false, image = p.image }
    return now, { pub(DZ .. "play", uri) }
  end
  return nil, {}
end

--- Transport for a streaming track: commands only, the daemon's events update the state.
function streaming.transport(service, action, arg)
  local base = service == "SPOTIFY" and SP or DZ
  if action == "pause" then return { pub(base .. "pauz") } end
  if action == "resume" then return { pub(base .. "cont") } end
  if action == "next" then return { pub(base .. "next") } end
  if action == "prev" then return { pub(base .. "prev") } end
  if action == "stop" then return { pub(service == "SPOTIFY" and (SP .. "pauz") or (DZ .. "stop")) } end
  if action == "seek" then return { pub(base .. "seek", arg) } end
  if action == "skip" then return { pub(base .. "skip_sec", arg) } end
  return {}
end

-- ------------------------------------------------------------------ Spotify events
local function active(doc, service) return doc.playback and doc.playback.now and doc.playback.now.service == service end
-- the daemon's word on the music state, through playback's door, completed with this module's own sub-tree
local function external(doc, ev, own)
  local r = playback.on_external(doc, ev)
  for k, v in pairs(own or {}) do r.state[k] = v end
  return r
end
-- a service logged out while it played: nothing plays any more
local function gone(doc, service, own)
  if not active(doc, service) then return { state = own } end
  return external(doc, { service = service, clear = true, state = "idle" }, own)
end

--- A cover a browser can show: the daemon may give Spotify's own "spotify:image:<id>", which is
--- the file on Spotify's image server i.scdn.co. Anything else is passed on as it is.
function streaming.cover_url(u)
  if type(u) ~= "string" then return nil end
  local id = u:match("^spotify:image:(%x+)$")
  if id then return "https://i.scdn.co/image/" .. id end
  return u ~= "" and u or nil
end

--- The now-playing record of a Spotify track (`d` = the daemon's now_playing payload).
local function sp_now(d, playlist)
  d = d or {}
  return { playlist = playlist, service = "SPOTIFY", uri = d.source_uri, source = d.source, title = d.track, album = d.album,
           artist = d.artist, image = streaming.cover_url(d.image), duration_ms = tonumber(d.duration_ms), has_next = d.hasNext ~= false,
           has_prev = d.hasPrev ~= false, audiobook = type(d.source_uri) == "string" and d.source_uri:find(":show:", 1, true) ~= nil }
end

--- The character playlist set to resume that plays this Spotify context, if any: started from
--- the phone, it is still that playlist, and its place follows what the phone played.
local function resume_playlist_for(doc, uri)
  if type(uri) ~= "string" then return nil end
  local ids = {}
  for id, p in pairs((doc.library or {}).playlists or {}) do
    if type(p) == "table" and p.resume and p.spotify and p.spotify.uri == uri then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids[1]
end

--- Spotify started playing on the Jooki from the phone: it becomes what plays, the local
--- music stops (the last one to start wins). The daemon's two messages, "playing" and
--- "now_playing", may come in either order: `sp.playing` and `sp.track` remember each.
local function take_over(doc, sp)
  local now = sp_now(sp.track, resume_playlist_for(doc, (sp.track or {}).source_uri))
  local r = external(doc, { service = "SPOTIFY", takeover = true, now = now, state = sp.playing and "playing" or "idle", position_ms = 0 }, { spotify = sp })
  r.commands[#r.commands + 1] = { kind = "log", level = "info", key = "streaming.spotify_took_over", fields = { cover = tostring((sp.track or {}).image or ""):sub(1, 90) } }
  return r
end

-- Where Spotify is in its track. The daemon reports a position now and then, not continuously:
-- streaming_int.clock keeps the last one and when it came, so that while it plays the time since
-- is added (up to the track's end).
local function sp_position(doc, now)
  local pb, c = doc.playback or {}, (doc.streaming_int or {}).clock
  local ms = tonumber(pb.position_ms) or 0
  if pb.state == "playing" and c and now then ms = c.ms + math.max(0, now - c.t) * 1000 end
  local d = pb.now and tonumber(pb.now.duration_ms)
  if d and d > 0 and ms > d then ms = d end
  return math.floor(ms)
end
streaming.sp_position = sp_position

-- streaming_int less one of its keys (a request answered); the others stay
local function without(doc, k)
  local int = copy(doc.streaming_int or {}); int[k] = nil
  return int
end

-- The character waiting for Spotify's answer to `cont`, while it is still what the Jooki plays.
local function cont_waiting(doc)
  local c = (doc.streaming_int or {}).cont
  local p = c and doc.library and doc.library.playlists[c.playlist]
  local pb = doc.playback or {}
  if not (p and p.spotify and active(doc, "SPOTIFY") and pb.now.playlist == c.playlist and pb.state ~= "paused") then return nil end
  return c, p
end

-- Spotify continued something else, or nothing: the character's own place. Its seek waits for its
-- playlist to play, as what Spotify continued may report "playing" first.
local function cont_fallback(doc, c, p, own)
  local cmds, seek_ms = place_commands(doc, c.playlist, p)
  local int = copy(doc.streaming_int or {})
  int.cont = { playlist = c.playlist, fallback = true, seek_ms = seek_ms }
  cmds[#cmds + 1] = { kind = "timer.once", name = "streaming.cont", seconds = 2 * CONT_WAIT_S }
  cmds[#cmds + 1] = { kind = "log", level = "info", key = "streaming.cont_other", fields = { playlist = c.playlist } }
  own = own or {}
  own.streaming_int = int
  return { state = own, commands = cmds }
end

-- A saved place is a track index, and chapters added at the top of a playlist move the saved one
-- further down: started at its index, a character would play another chapter (and its place would
-- become that one). The track that starts is checked against the saved title and album; another one
-- is skipped, muted, until the saved one comes, then the time is sought. Spotify takes `next` reliably
-- once now_playing names the new track (about 0.8 s a track).
local FIND_MAX = 60      -- tracks skipped at most (about two episodes of an audio drama)
local FIND_WAIT_S = 90   -- the search given up after this long

local function find_done(int, cmds)
  int.find = nil
  cmds[#cmds + 1] = { kind = "timer.cancel", name = "streaming.find" }
  cmds[#cmds + 1] = emit("volume.apply", {})
end

-- now_playing of the playlist being searched: the saved track, or one more skip, or give up there.
local function find_step(doc, r, d)
  local f = (doc.streaming_int or {}).find
  local p = f and doc.library and doc.library.playlists[f.playlist]
  if not (p and p.spotify) or d.restricted then return r end
  local int = copy(r.state.streaming_int or doc.streaming_int or {})
  r.commands = r.commands or {}
  local cmds = r.commands
  if d.source_uri ~= p.spotify.uri then   -- something else plays now (the phone): the search is over
    find_done(int, cmds)
  elseif d.track == f.id and (not f.album or not d.album or d.album == f.album) then
    find_done(int, cmds)
    if f.skips > 0 then
      if f.pos then
        r.state.playback.resume_ms = f.pos
        if doc.playback.state == "playing" then
          for _, x in ipairs(streaming.transport("SPOTIFY", "seek", f.pos)) do cmds[#cmds + 1] = x end
        end
      end
      cmds[#cmds + 1] = { kind = "log", level = "info", key = "streaming.place_found", fields = { playlist = f.playlist, skips = f.skips } }
    end
  elseif f.skips >= FIND_MAX or d.hasNext == false then
    find_done(int, cmds)
    cmds[#cmds + 1] = pub(SP .. "play_preset", direct_request(p.spotify.uri, f.index, f.pos or 0))
    cmds[#cmds + 1] = { kind = "log", level = "warn", key = "streaming.place_lost", fields = { playlist = f.playlist, skips = f.skips } }
  else
    if f.skips == 0 then cmds[#cmds + 1] = require("services.device").volume_command(doc, 0) end
    int.find = copy(f); int.find.skips = f.skips + 1
    for _, x in ipairs(streaming.transport("SPOTIFY", "next")) do cmds[#cmds + 1] = x end
  end
  r.state.streaming_int = int
  return r
end

-- ------------------------------------------------------------------ the Jooki's own account
local CREDENTIALS = "/data/spotify/credentials.bin"
local function credentials_file(doc) return (doc.config or {}).spotify_credentials_file or CREDENTIALS end
local function read_saved(doc) return { kind = "files.read_text", path = credentials_file(doc), reply = "spotify.saved_read" } end

--- The account name that starts the daemon's file (NUL-terminated), or nil.
function streaming.saved_user(text)
  if type(text) ~= "string" then return nil end
  local stop = text:find("\0", 1, true)
  local name = stop and text:sub(1, stop - 1) or ""
  if #name == 0 or #name > 64 or not name:match("^[%w%._%-]+$") then return nil end
  return name
end

--- The file read back (at boot, after each login): what the Jooki will log into at its next start.
function streaming.on_saved_read(doc, ev)
  local sp = copy(doc.spotify or { active = false })
  sp.saved = streaming.saved_user(ev.text) or false
  if sp.saved == (doc.spotify or {}).saved then return nil end
  return { state = { spotify = sp } }
end

--- The page asks the Jooki to forget its account: the daemon starts again with none, and the next
--- account that picks the Jooki in the Spotify app becomes its own.
function streaming.on_forget_account(doc)
  local sp = copy(doc.spotify or {})
  sp.username, sp.saved, sp.active, sp.playing, sp.track = nil, false, false, nil, nil
  local r = gone(doc, "SPOTIFY", { spotify = sp })
  r.commands = r.commands or {}
  table.insert(r.commands, 1, { kind = "shell", action = "spotify_forget", args = { file = credentials_file(doc) } })
  r.commands[#r.commands + 1] = { kind = "log", level = "info", key = "streaming.spotify_forgotten" }
  return r
end

--- Boot: ask the daemon how it is, read which account it will log into, note whether
--- spotify_ctrl is patched, and start noting the place of a playlist set to resume.
function streaming.on_boot(doc, ev)
  return { state = { spotify = { active = false, saved = false }, deezer = {}, streaming_int = { direct = (ev or {}).spotify_direct or nil } },
           commands = { pub(SP .. "get_status"), read_saved(doc), { kind = "timer.every", name = "streaming.resume", seconds = 30 } } }
end

local on_spotify
function streaming.on_spotify(doc, ev)
  local f = (doc.streaming_int or {}).random_start
  -- Spotify can still report the previous context during preset loading.
  -- It must not detach the requested playlist or cancel its pending start.
  if f and (f.phase == "loading" or f.phase == "muting") and ev.type == "spotify.now_playing" and (ev.data or {}).source_uri ~= f.uri then return nil end
  local r = random_step(doc, on_spotify(doc, ev), ev)
  local kind = ev.type:sub(9)
  if not (r and ev.now and (kind == "position" or kind == "playing" or kind == "paused" or kind == "now_playing")) then return r end
  local pb = (r.state and r.state.playback) or doc.playback or {}
  if not (pb.now and pb.now.service == "SPOTIFY") then return r end
  local was = (doc.playback or {}).now or {}
  local ms = tonumber(pb.position_ms) or 0
  -- a new track starts at 0 until the daemon says otherwise
  if kind == "now_playing" and pb.now.title ~= was.title then ms = 0 end
  r.state = r.state or {}
  local int = copy(r.state.streaming_int or doc.streaming_int or {})
  int.clock = { ms = ms, t = ev.now }
  r.state.streaming_int = int
  return r
end

function on_spotify(doc, ev)
  local kind = ev.type:sub(9)     -- after "spotify."
  local sp = copy(doc.spotify or { active = false })
  if kind == "login" then
    sp.username = ev.username
    -- the daemon has just saved the account if it reached a Jooki with none: read the file again
    return { state = { spotify = sp }, commands = { emit("volume.apply", {}), read_saved(doc) } }
  elseif kind == "logout" then
    sp.username, sp.playing, sp.track = nil, nil, nil
    return gone(doc, "SPOTIFY", { spotify = sp })
  elseif kind == "login_required" then
    return { commands = { emit("system.event", { name = "Evt.Spotify.NoLoginError" }) } }
  elseif kind == "active" then
    sp.active = ev.active == true
    return { state = { spotify = sp } }
  elseif kind == "play_error" then
    local c, cp = cont_waiting(doc)
    if c and not c.fallback then return cont_fallback(doc, c, cp) end
    return { commands = { emit("system.event", { name = "Evt.Spotify.PlayError" }) } }
  elseif kind == "status" then
    local n = doc.net or {}
    local r = { commands = { pub(SP .. "connection_state", (n.connected and n.ip and n.ip ~= "") and 2 or 0) } }
    if ev.active ~= nil then sp.active = ev.active; r.state = { spotify = sp } end
    return r
  elseif kind == "now_playing" then
    local pb = doc.playback or {}
    local target = pb.now or {}
    if not (doc.streaming_int or {}).cont and pb.state == "starting" and target.service == "SPOTIFY" and target.playlist and not target.title and
       (ev.data or {}).source_uri ~= target.uri then return nil end
    sp.track = copy(ev.data or {})
    local c, cp = cont_waiting(doc)
    local cont_here = c and sp.track.source_uri == cp.spotify.uri
    if c and not cont_here then
      if c.fallback then return { state = { spotify = sp } } end   -- what was continued, before the place plays
      return cont_fallback(doc, c, cp, { spotify = sp })
    end
    if active(doc, "SPOTIFY") then
      local was = doc.playback.now
      -- another context started from the phone is no longer the token's playlist: kept as it,
      -- the page would offer no "Put on a character" and the resume tick would save its place
      -- as the token's. It may be another character's playlist set to resume.
      local p = was.playlist and doc.library and doc.library.playlists[was.playlist]
      local uri = p and p.spotify and p.spotify.uri
      local playlist = was.playlist
      if uri and sp.track.source_uri and sp.track.source_uri ~= uri then playlist = nil end
      if not playlist then playlist = resume_playlist_for(doc, sp.track.source_uri) end
      local now = sp_now(sp.track, playlist)
      local r = external(doc, { service = "SPOTIFY", now = now }, { spotify = sp })
      if cont_here then
        r.state.streaming_int = without(doc, "cont")
        r.commands = r.commands or {}
        r.commands[#r.commands + 1] = { kind = "timer.cancel", name = "streaming.cont" }
        if c.seek_ms then
          r.state.playback.resume_ms = c.seek_ms
          if doc.playback.state == "playing" then
            for _, x in ipairs(streaming.transport("SPOTIFY", "seek", c.seek_ms)) do r.commands[#r.commands + 1] = x end
          end
        end
        if not c.fallback then r.commands[#r.commands + 1] = { kind = "log", level = "info", key = "streaming.cont_here", fields = { playlist = c.playlist } } end
        return find_step(doc, r, sp.track)
      end
      -- what the daemon gives as a cover, once per new cover (docs: the page's covers)
      if now.image ~= was.image then r.commands = { { kind = "log", level = "info", key = "streaming.spotify_cover", fields = { raw = tostring(sp.track.image or ""):sub(1, 90) } } } end
      return find_step(doc, r, sp.track)
    end
    -- local music loaded: wait for "playing" (the phone may only have changed the track of a paused Spotify)
    if playback.local_busy(doc) then return { state = { spotify = sp } } end
    return take_over(doc, sp)
  elseif kind == "playing" or kind == "paused" then
    sp.playing = kind == "playing"
    if not active(doc, "SPOTIFY") then
      if kind == "playing" then return take_over(doc, sp) end
      return { state = { spotify = sp } }
    end
    return external(doc, { service = "SPOTIFY", state = kind }, { spotify = sp })
  elseif kind == "position" then
    if not active(doc, "SPOTIFY") then return nil end
    local pb, track = doc.playback or {}, sp.track or {}
    if pb.state == "starting" and track.source_uri == (pb.now or {}).uri and track.restricted ~= true then
      return external(doc, { service = "SPOTIFY", state = "playing", position_ms = tonumber(ev.ms) or 0 })
    end
    if pb.state ~= "playing" then return nil end
    return external(doc, { service = "SPOTIFY", position_ms = tonumber(ev.ms) or 0 })
  elseif kind == "volume" then
    return nil   -- 1.x ignored the app's volume and re-applied its own
  elseif kind == "set_cfg" then
    -- the app's shuffle and repeat stay the app's: saved as the Jooki's own (what 1.x did), a shuffle left
    -- on in the Spotify app shuffled every token's playlist afterwards, bedtime stories included
    return nil
  elseif kind == "new_preset" then
    local pending = doc.streaming_int and doc.streaming_int.preset_for
    local resume_for = doc.streaming_int and doc.streaming_int.resume_for
    if not pending and resume_for then
      local int = without(doc, "resume_for")
      if (ev.raw or "") == "" then
        return { state = { streaming_int = int }, commands = { { kind = "log", level = "warn", key = "streaming.resume_preset_empty" } } }
      end
      return { state = { streaming_int = int }, commands = { emit("playback.spotify_resume", { playlist = resume_for.playlist,
        title = resume_for.title, album = resume_for.album, preset = str2hex(ev.raw), position_ms = resume_for.position_ms, flush = resume_for.flush }) } }
    end
    if not pending then return { commands = { { kind = "log", level = "warn", key = "streaming.preset_unexpected" } } } end
    if (ev.raw or "") == "" then   -- Spotify refused: no playlist that would play nothing (the page says Spotify did not answer)
      return { state = { streaming_int = without(doc, "preset_for") }, commands = { { kind = "log", level = "warn", key = "streaming.preset_empty" } } }
    end
    if not (active(doc, "SPOTIFY") and doc.playback.state == "playing") then
      return { state = { streaming_int = without(doc, "preset_for") }, commands = { { kind = "log", level = "warn", key = "streaming.preset_not_playing" } } }
    end
    local now = doc.playback.now
    return { state = { streaming_int = without(doc, "preset_for") }, commands = { emit("library.add_playlist", {
      title = pending.title or now.source, star = pending.star, image = now.image, spotify = { uri = now.uri, preset = str2hex(ev.raw or "") } }) } }
  end
  return nil
end

-- ------------------------------------------------------------------ Deezer events
function streaming.on_deezer(doc, ev)
  local kind = ev.type:sub(8)     -- after "deezer."
  local dz = copy(doc.deezer or {})
  if kind == "login" then dz.username, dz.id, dz.active = ev.name, ev.id, nil return { state = { deezer = dz } }
  elseif kind == "options" then dz.active = (ev.license and dz.username) and true or nil return { state = { deezer = dz } }
  elseif kind == "logout" then
    dz.username, dz.id, dz.active = nil, nil, nil
    return gone(doc, "DEEZER", { deezer = dz })
  elseif kind == "play_error" then return { commands = { emit("system.event", { name = "Evt.Deezer.PlayError" }) } }
  elseif kind == "playlists" then return { commands = { pub("/j/web/output/state", ev.raw or "{}") } }   -- 1.x: state {deezerPlaylists}
  elseif kind == "now_playing" then
    local cur = doc.playback and doc.playback.now; local d = ev.data or {}
    local now = { playlist = cur and cur.playlist, service = "DEEZER", source_uri = d.link, album = d.album and d.album.title, artist = d.artist and d.artist.name,
                  audiobook = false, duration_ms = (tonumber(d.duration) or 0) * 1000, has_next = true, has_prev = true, image = d.album and d.album.cover_big, title = d.title }
    return external(doc, { service = "DEEZER", now = now })
  elseif kind == "now_pl" then
    if not active(doc, "DEEZER") then return nil end
    return external(doc, { service = "DEEZER", uri = ev.uri })
  elseif kind == "starting" or kind == "playing" or kind == "paused" or kind == "stopped" or kind == "ended" then
    if not active(doc, "DEEZER") then return nil end
    local state
    if kind == "paused" then state = ev.flag == "1" and "paused" or "playing"
    elseif kind == "ended" and (doc.bedtime_int or {}).stop_at_end then state = "ended"
    elseif kind == "ended" or kind == "stopped" then state = "idle"
    else state = kind end
    local r = external(doc, { service = "DEEZER", state = state, position_ms = kind == "starting" and 0 or nil })
    if kind == "ended" and state ~= "ended" then table.insert(r.commands, 1, pub(DZ .. "next")) end   -- the daemon is asked for the next track first
    return r
  elseif kind == "position" then
    if not active(doc, "DEEZER") or (doc.playback or {}).state ~= "playing" then return nil end
    return external(doc, { service = "DEEZER", position_ms = tonumber(ev.ms) or 0 })
  end
  return nil
end

-- ------------------------------------------------------------------ requests from the page
function streaming.on_new_spotify_playlist(doc, p)
  if not (active(doc, "SPOTIFY") and doc.playback.state == "playing") then
    return nil, { code = "unavailable", field = "", message = "Not playing spotify right now" }
  end
  local int = without(doc, "resume_for")   -- one answer for one request: the page's is the one waited for
  int.preset_for = { title = p.title, star = p.star }
  return { state = { streaming_int = int }, commands = { pub(SP .. "save_preset") } }
end

--- A token taken off a Spotify playlist set to resume: ask Spotify for a preset of where it is
--- (the track), keep the time ourselves, then pause. The answer goes to resume.json at once.
function streaming.on_save_resume(doc, ev)
  local int = copy(doc.streaming_int or {})
  local now = (doc.playback or {}).now or {}
  local ms = int.clock and ev.now and sp_position(doc, ev.now) or tonumber(ev.position_ms) or 0
  int.resume_for = { playlist = ev.playlist, title = now.title, album = now.album, position_ms = ms, t = ev.now, flush = true }
  int.cont = nil
  local cmds = { pub(SP .. "save_preset"), pub(SP .. "pauz") }
  if int.find then   -- taken off during the search: the saved place stays, the playing track is not it
    find_done(int, cmds)
    int.resume_for = nil
    table.remove(cmds, 1)
  end
  return { state = { streaming_int = int }, commands = cmds }
end

local ASK_AGAIN_S = 20   -- a preset asked for and not answered: asked again after this long

--- Every 30 s (timer streaming.resume) while a Spotify playlist set to resume plays: its place is
--- noted, so that a Jooki switched off with the token on (inactivity, battery, the button) starts
--- there again. A preset names the track only: one is asked for each new track, the time is ours.
function streaming.on_resume_tick(doc, ev)
  local pb = doc.playback or {}
  local pl = pb.state == "playing" and pb.now and pb.now.service == "SPOTIFY" and pb.now.playlist
  local p = pl and doc.library and doc.library.playlists[pl]
  if not (p and p.resume and p.spotify) then return nil end
  local int = doc.streaming_int or {}
  if int.preset_for or int.cont or int.find then return nil end
  local title, ms = pb.now.title, sp_position(doc, ev.now)
  local saved = (doc.resume or {})[pl]
  -- the same title in another album (a chapter of the next episode) is another track: a new preset
  if saved and saved.preset and saved.id == title and saved.album == pb.now.album then
    return { commands = { emit("playback.spotify_resume", { playlist = pl, title = title, album = pb.now.album, position_ms = ms }) } }
  end
  if int.resume_for and ev.now and ev.now - (int.resume_for.t or 0) < ASK_AGAIN_S then return nil end
  local int2 = copy(int)
  int2.resume_for = { playlist = pl, title = title, album = pb.now.album, position_ms = ms, t = ev.now }
  return { state = { streaming_int = int2 }, commands = { pub(SP .. "save_preset") } }
end

--- A playlist set to resume started with `cont` (streaming.start): its answer is awaited.
function streaming.on_cont(doc, ev)
  local int = copy(doc.streaming_int or {})
  int.cont = { playlist = ev.playlist }
  return { state = { streaming_int = int } }
end

--- A place started at its saved index (place_commands): the track that starts is checked (find_step).
function streaming.on_find(doc, ev)
  local int = copy(doc.streaming_int or {})
  int.find = { playlist = ev.playlist, id = ev.id, album = ev.album, index = ev.index, pos = ev.pos, skips = 0 }
  return { state = { streaming_int = int }, commands = { { kind = "timer.once", name = "streaming.find", seconds = FIND_WAIT_S } } }
end

--- Playback left the character during the search (local music, another token): it ends, the volume back.
function streaming.on_playback_changed(doc)
  local f = (doc.streaming_int or {}).find
  local pb = doc.playback or {}
  if not f or (active(doc, "SPOTIFY") and pb.now.playlist == f.playlist) then return nil end
  local int, cmds = copy(doc.streaming_int), {}
  find_done(int, cmds)
  return { state = { streaming_int = int }, commands = cmds }
end

--- The saved track not found in time: it plays where it is, at the volume it had.
function streaming.on_find_timer(doc)
  local f = (doc.streaming_int or {}).find
  if not f then return nil end
  local int, cmds = copy(doc.streaming_int), {}
  find_done(int, cmds)
  cmds[#cmds + 1] = { kind = "log", level = "warn", key = "streaming.place_lost", fields = { playlist = f.playlist, skips = f.skips } }
  return { state = { streaming_int = int }, commands = cmds }
end

--- No answer to `cont` in time: the character's own place. After that, the wait is over.
function streaming.on_cont_timer(doc)
  local c, p = cont_waiting(doc)
  if c and not c.fallback then return cont_fallback(doc, c, p) end
  if (doc.streaming_int or {}).cont then return { state = { streaming_int = without(doc, "cont") } } end
  return nil
end

function streaming.on_deezer_get_playlists() return { commands = { pub(DZ .. "get_playlists") } } end

function streaming.on_deezer_set_cfg(_, p)
  local text = string.format("%s\n%s\n%s\n%s", tostring(p.appId), tostring(p.appName), tostring(p.appVersion), tostring(p.token))
  return { commands = { { kind = "files.write_text", path = "/data/auth/DEEZER", text = text },
                        { kind = "log", level = "warn", key = "streaming.deezer_restart_unavailable", fields = { note = "no deezer_ctrl / systemctl on this firmware" } } } }
end

--- Every Wi-Fi report tells Spotify whether the Jooki is online (1.x publish_wifi_state). Without
--- it, a "no network" answered once at boot (Wi-Fi not up yet) left Spotify offline until the next
--- restart: seen by the phone, but never connecting.
function streaming.on_net(_, ev)
  return { commands = { pub(SP .. "connection_state", (ev.connected and ev.ip and ev.ip ~= "") and 2 or 0) } }
end

--- audiocfg changes reach the active service (1.x SET_CFG / SET_VOL paths).
function streaming.on_config(doc, ev)
  local cmds = {}
  local a = doc.audiocfg or {}
  if active(doc, "SPOTIFY") then
    if ev.shuffle_mode ~= nil then cmds[#cmds + 1] = pub(SP .. "set_shuffle", a.shuffle_mode and 1 or 0) end
    if ev.repeat_mode ~= nil then cmds[#cmds + 1] = pub(SP .. "set_repeat", a.repeat_mode or 0) end
    if ev.volume ~= nil then cmds[#cmds + 1] = pub(SP .. "set_vol", math.floor(65535 * (a.volume or 0) / 100)) end
  elseif active(doc, "DEEZER") then
    if ev.shuffle_mode ~= nil then cmds[#cmds + 1] = pub(DZ .. "set_shuffle", a.shuffle_mode and 1 or 0) end
    if ev.repeat_mode ~= nil then cmds[#cmds + 1] = pub(DZ .. "set_repeat", a.repeat_mode or 0) end
  end
  if #cmds == 0 then return nil end
  return { commands = cmds }
end

local S = {}
S.new_spotify = { type = "object", additionalProperties = false, properties = { title = { type = "string", maxLength = 200 }, star = { type = "string", maxLength = 64 } } }
S.deezer_cfg = { type = "object", required = { "appId", "appName", "appVersion", "token" }, additionalProperties = false,
                 properties = { appId = { type = { "string", "integer" } }, appName = { type = "string" }, appVersion = { type = "string" }, token = { type = "string" } } }
streaming.schemas = S

function streaming.install(api, dispatch)
  for _, k in ipairs({ "login", "logout", "login_required", "active", "play_error", "status", "now_playing", "playing", "paused", "position", "volume", "set_cfg", "new_preset" }) do
    dispatch.on("spotify." .. k, "streaming", streaming.on_spotify)
  end
  for _, k in ipairs({ "login", "options", "logout", "play_error", "playlists", "now_playing", "now_pl", "starting", "playing", "paused", "stopped", "ended", "position" }) do
    dispatch.on("deezer." .. k, "streaming", streaming.on_deezer)
  end
  dispatch.on("audiocfg.changed", "streaming", streaming.on_config)
  dispatch.on("streaming.save_resume", "streaming", streaming.on_save_resume)
  dispatch.on_timer("streaming.resume", "streaming", streaming.on_resume_tick)
  dispatch.on("volume.confirmed", "streaming.random", streaming.on_volume_confirmed)
  dispatch.on("streaming.random_start", "streaming.random", streaming.on_random_start)
  dispatch.on_timer("streaming.random", "streaming.random", streaming.on_random_timer)
  dispatch.on_timer("streaming.random_probe", "streaming.random", streaming.on_random_probe)
  dispatch.on("audiocfg.changed", "streaming.random", streaming.on_random_config)
  dispatch.on("playback.changed", "streaming.random", streaming.on_random_changed)
  dispatch.on("streaming.cont", "streaming", streaming.on_cont)
  dispatch.on_timer("streaming.cont", "streaming", streaming.on_cont_timer)
  dispatch.on("streaming.find", "streaming", streaming.on_find)
  dispatch.on_timer("streaming.find", "streaming", streaming.on_find_timer)
  dispatch.on("playback.changed", "streaming", streaming.on_playback_changed)
  dispatch.on("net.status", "streaming", streaming.on_net)
  dispatch.on("spotify.saved_read", "streaming", streaming.on_saved_read)
  dispatch.on("boot", "streaming", streaming.on_boot)
  api.command("spotify.new_playlist", S.new_spotify, streaming.on_new_spotify_playlist)
  api.command("spotify.forget_account", nil, streaming.on_forget_account)
  api.command("deezer.get_playlists", nil, streaming.on_deezer_get_playlists)
  api.command("deezer.set_config", S.deezer_cfg, streaming.on_deezer_set_cfg)
end

return streaming
