-- services.streaming: Spotify Connect and Deezer, kept by decision (ADR-0009).
-- A faithful port of the message paths of the original program (docs/22),
-- isolated from local playback: the closed daemons (spotify_ctrl, deezer_ctrl)
-- do the streaming; this module only carries messages and keeps two small
-- sub-trees: state.spotify = { username, active }, state.deezer = { username, id, active }.
-- Best effort: verified on the bench with a fake daemon, not against the services.
-- Note: the 2022 firmware ships spotify_ctrl but no deezer_ctrl (docs/22 §1).
local streaming = {}

local SP, DZ = "/j/spotify/output/", "/j/deezer/output/"

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
local function pub(topic, payload) return { kind = "bus.publish", topic = topic, payload = payload == nil and "" or tostring(payload) } end
local function emit(t, extra)
  local e = { type = t }
  for k, v in pairs(extra or {}) do e[k] = v end
  return { kind = "emit", event = e }
end

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

--- The now-playing record and the commands that start a streaming playlist.
function streaming.start(doc, playlist_id, p)
  if p.spotify then
    local now = { playlist = playlist_id, service = "SPOTIFY", uri = p.spotify.uri, source = p.title, audiobook = false, image = p.image }
    return now, { pub(SP .. "play_preset", hex2str(p.spotify.preset or "")) }
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
local function pb_of(doc) local pb = copy(doc.playback or {}); pb.state = pb.state or "idle"; return pb end
local function active(doc, service) return doc.playback and doc.playback.now and doc.playback.now.service == service end
local function local_busy(pb)
  return pb.now and (pb.now.service == "FILE" or pb.now.service == "STREAM")
    and (pb.state == "playing" or pb.state == "starting" or pb.state == "paused")
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

--- Spotify started playing on the Jooki from the phone: it becomes what plays, the local
--- music stops (the last one to start wins). The daemon's two messages, "playing" and
--- "now_playing", may come in either order: `sp.playing` and `sp.track` remember each.
local function take_over(doc, sp)
  local pb = pb_of(doc)
  local cmds = {}
  if local_busy(pb) then cmds[#cmds + 1] = pub("/j/audio/out/stop", "7") end
  pb.now = sp_now(sp.track)
  pb.state = sp.playing and "playing" or "idle"
  pb.position_ms = 0
  pb.paused_by, pb.paused_at, pb.resume_ms = nil, nil, nil
  cmds[#cmds + 1] = emit("playback.changed", { state = pb.state })
  cmds[#cmds + 1] = { kind = "log", level = "info", key = "streaming.spotify_took_over", fields = { cover = tostring((sp.track or {}).image or ""):sub(1, 90) } }
  return { state = { spotify = sp, playback = pb }, commands = cmds }
end

function streaming.on_spotify(doc, ev)
  local kind = ev.type:sub(9)     -- after "spotify."
  local sp = copy(doc.spotify or { active = false })
  if kind == "login" then
    sp.username = ev.username
    return { state = { spotify = sp }, commands = { emit("volume.apply", {}) } }
  elseif kind == "logout" then
    sp.username, sp.playing, sp.track = nil, nil, nil
    local r = { state = { spotify = sp }, commands = {} }
    if active(doc, "SPOTIFY") then local pb = pb_of(doc); pb.now, pb.state = nil, "idle"; r.state.playback = pb; r.commands[1] = emit("playback.changed", { state = "idle" }) end
    return r
  elseif kind == "login_required" then
    return { commands = { emit("system.event", { name = "Evt.Spotify.NoLoginError" }) } }
  elseif kind == "active" then
    sp.active = ev.active == true
    return { state = { spotify = sp } }
  elseif kind == "play_error" then
    return { commands = { emit("system.event", { name = "Evt.Spotify.PlayError" }) } }
  elseif kind == "status" then
    local n = doc.net or {}
    return { commands = { pub(SP .. "connection_state", (n.connected and n.ip and n.ip ~= "") and 2 or 0) } }
  elseif kind == "now_playing" then
    sp.track = copy(ev.data or {})
    if active(doc, "SPOTIFY") then
      local pb = pb_of(doc)
      local was = pb.now and pb.now.image
      pb.now = sp_now(sp.track, pb.now.playlist)
      local r = { state = { spotify = sp, playback = pb } }
      -- what the daemon gives as a cover, once per new cover (docs: the page's covers)
      if pb.now.image ~= was then r.commands = { { kind = "log", level = "info", key = "streaming.spotify_cover", fields = { raw = tostring(sp.track.image or ""):sub(1, 90) } } } end
      return r
    end
    -- local music loaded: wait for "playing" (the phone may only have changed the track of a paused Spotify)
    if local_busy(pb_of(doc)) then return { state = { spotify = sp } } end
    return take_over(doc, sp)
  elseif kind == "playing" or kind == "paused" then
    sp.playing = kind == "playing"
    if not active(doc, "SPOTIFY") then
      if kind == "playing" then return take_over(doc, sp) end
      return { state = { spotify = sp } }
    end
    local pb = pb_of(doc)
    pb.state = kind
    return { state = { spotify = sp, playback = pb }, commands = { emit("playback.changed", { state = kind }) } }
  elseif kind == "position" then
    if not active(doc, "SPOTIFY") or (doc.playback or {}).state ~= "playing" then return nil end
    local pb = pb_of(doc); pb.position_ms = tonumber(ev.ms) or 0
    return { state = { playback = pb } }
  elseif kind == "volume" then
    return nil   -- 1.x ignored the app's volume and re-applied its own
  elseif kind == "set_cfg" then
    return { commands = { emit("device.set_config_request", { shuffle_mode = ev.shuffle_mode, repeat_mode = ev.repeat_mode }) } }
  elseif kind == "new_preset" then
    local pending = doc.streaming_int and doc.streaming_int.preset_for
    if not pending then return { commands = { { kind = "log", level = "warn", key = "streaming.preset_unexpected" } } } end
    if (ev.raw or "") == "" then   -- Spotify refused: no playlist that would play nothing (the page says Spotify did not answer)
      return { state = { streaming_int = {} }, commands = { { kind = "log", level = "warn", key = "streaming.preset_empty" } } }
    end
    if not (active(doc, "SPOTIFY") and doc.playback.state == "playing") then
      return { state = { streaming_int = {} }, commands = { { kind = "log", level = "warn", key = "streaming.preset_not_playing" } } }
    end
    local now = doc.playback.now
    return { state = { streaming_int = {} }, commands = { emit("library.add_playlist", {
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
    local r = { state = { deezer = dz }, commands = {} }
    if active(doc, "DEEZER") then local pb = pb_of(doc); pb.now, pb.state = nil, "idle"; r.state.playback = pb; r.commands[1] = emit("playback.changed", { state = "idle" }) end
    return r
  elseif kind == "play_error" then return { commands = { emit("system.event", { name = "Evt.Deezer.PlayError" }) } }
  elseif kind == "playlists" then return { commands = { pub("/j/web/output/state", ev.raw or "{}") } }   -- 1.x: state {deezerPlaylists}
  elseif kind == "now_playing" then
    local pb = pb_of(doc); local d = ev.data or {}
    pb.now = { playlist = pb.now and pb.now.playlist, service = "DEEZER", source_uri = d.link, album = d.album and d.album.title, artist = d.artist and d.artist.name,
               audiobook = false, duration_ms = (tonumber(d.duration) or 0) * 1000, has_next = true, has_prev = true, image = d.album and d.album.cover_big, title = d.title }
    return { state = { playback = pb } }
  elseif kind == "now_pl" then
    if not active(doc, "DEEZER") then return nil end
    local pb = pb_of(doc); pb.now.uri = ev.uri
    return { state = { playback = pb } }
  elseif kind == "starting" or kind == "playing" or kind == "paused" or kind == "stopped" or kind == "ended" then
    if not active(doc, "DEEZER") then return nil end
    local pb = pb_of(doc)
    local cmds = {}
    if kind == "paused" then pb.state = ev.flag == "1" and "paused" or "playing"
    elseif kind == "ended" then pb.state = "idle" cmds[#cmds + 1] = pub(DZ .. "next")
    elseif kind == "stopped" then pb.state = "idle"
    else pb.state = kind end
    if kind == "starting" then pb.position_ms = 0 end
    cmds[#cmds + 1] = emit("playback.changed", { state = pb.state })
    return { state = { playback = pb }, commands = cmds }
  elseif kind == "position" then
    if not active(doc, "DEEZER") or (doc.playback or {}).state ~= "playing" then return nil end
    local pb = pb_of(doc); pb.position_ms = tonumber(ev.ms) or 0
    return { state = { playback = pb } }
  end
  return nil
end

-- ------------------------------------------------------------------ requests from the page
function streaming.on_new_spotify_playlist(doc, p)
  if not (active(doc, "SPOTIFY") and doc.playback.state == "playing") then
    return nil, { code = "unavailable", field = "", message = "Not playing spotify right now" }
  end
  return { state = { streaming_int = { preset_for = { title = p.title, star = p.star } } }, commands = { pub(SP .. "save_preset") } }
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
  dispatch.on("net.status", "streaming", streaming.on_net)
  dispatch.on("boot", "streaming", function() return { state = { spotify = { active = false }, deezer = {}, streaming_int = {} }, commands = { pub(SP .. "get_status") } } end)
  api.command("spotify.new_playlist", S.new_spotify, streaming.on_new_spotify_playlist)
  api.command("deezer.get_playlists", nil, streaming.on_deezer_get_playlists)
  api.command("deezer.set_config", S.deezer_cfg, streaming.on_deezer_set_cfg)
end

return streaming
