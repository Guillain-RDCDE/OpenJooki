local streaming = require("services.streaming")
local playback = require("services.playback")

local function doc_with(o)
  o = o or {}
  return { config = { data_dir = "/d" }, spotify = o.spotify or { active = false }, deezer = o.deezer or {}, net = { connected = true },
           audiocfg = o.audiocfg or { volume = 50, shuffle_mode = false, repeat_mode = 1 },
           library = { playlists = { sp = { title = "Jazz", spotify = { uri = "spotify:playlist:1", preset = "4142" }, tracks = {} },
                                     dz = { title = "Kids", deezer = { type = "playlist", id = "77" }, tracks = {} },
                                     loc = { title = "Local", tracks = { "a" } } }, tracks = { a = { title = "A", filename = "/d/uploads/a" } }, tokens = {} },
           playback = o.playback or { state = "idle", last = {}, shuffle = {} }, streaming_int = o.int or {} }
end
local function topics(r)
  local out = {}
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == "bus.publish" then out[#out + 1] = c.topic:gsub("^/j/", "") .. " " .. c.payload
    elseif c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type .. (c.event.name and " " .. c.event.name or "") .. (c.event.state and " " .. c.event.state or "") end
  end
  return out
end
local function apply(doc, r) for k, v in pairs((r and r.state) or {}) do doc[k] = v end return doc end

describe("services.streaming — starting and transport through playback", function()
  it("a Spotify playlist plays its preset (hex decoded) and the state follows the daemon's events", function()
    local doc = doc_with()
    local r = playback.on_request(doc, { playlist = "sp", now = 1 })
    assert_eq(topics(r), { "spotify/output/play_preset AB", "emit playback.changed starting" })
    assert_eq(r.state.playback.now.service, "SPOTIFY"); assert_eq(r.state.playback.now.uri, "spotify:playlist:1")
    apply(doc, r)
    r = streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "So What", artist = "Miles", hasNext = true } })
    assert_eq(r.state.playback.now.title, "So What"); assert_eq(r.state.playback.now.playlist, "sp")
    apply(doc, r)
    r = streaming.on_spotify(doc, { type = "spotify.playing" })
    assert_eq(r.state.playback.state, "playing"); assert_eq(topics(r), { "emit playback.changed playing" })
    apply(doc, r)
    assert_eq(streaming.on_spotify(doc, { type = "spotify.position", ms = 4200 }).state.playback.position_ms, 4200)
    assert_eq(topics(playback.on_pause(doc, { source = "page" })), { "spotify/output/pauz " })
    assert_eq(topics(playback.on_next(doc, { forced = true })), { "spotify/output/next " })
    assert_eq(topics(playback.on_seek(doc, { ms = 9000 })), { "spotify/output/seek 9000" })
    apply(doc, streaming.on_spotify(doc, { type = "spotify.paused" }))
    assert_eq(doc.playback.state, "paused")
    assert_eq(topics(playback.on_resume(doc, { now = 5 })), { "spotify/output/cont " })
    r = streaming.on_spotify(doc, { type = "spotify.logout" })
    assert_eq(r.state.playback.state, "idle"); assert_nil(r.state.playback.now)
  end)

  it("Spotify taking over from the app stops the local file", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "loc" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    local r = streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:album:9", track = "X" } })
    assert_eq(topics(r), { "audio/out/stop 7" })
    assert_eq(r.state.playback.state, "idle"); assert_eq(r.state.playback.now.service, "SPOTIFY")
  end)

  it("Deezer needs a login; then plays the media uri and follows its events", function()
    local doc = doc_with()
    local r = playback.on_request(doc, { playlist = "dz" })
    assert_eq(topics(r), { "emit system.event Evt.Deezer.NoLoginError" })
    apply(doc, streaming.on_deezer(doc, { type = "deezer.login", name = "u", id = 1 }))
    apply(doc, streaming.on_deezer(doc, { type = "deezer.options", license = true }))
    assert_true(doc.deezer.active)
    r = playback.on_request(doc, { playlist = "dz" })
    assert_eq(topics(r)[1], "deezer/output/play dzmedia:///playlist/77")
    apply(doc, r)
    apply(doc, streaming.on_deezer(doc, { type = "deezer.playing" }))
    assert_eq(doc.playback.state, "playing")
    assert_eq(topics(playback.on_pause(doc, { source = "page" })), { "deezer/output/pauz " })
    r = streaming.on_deezer(doc, { type = "deezer.ended" })
    assert_eq(topics(r)[1], "deezer/output/next ")
  end)

  it("local playback is untouched by streaming events", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "loc" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    assert_nil(streaming.on_spotify(doc, { type = "spotify.playing" }))
    assert_nil(streaming.on_spotify(doc, { type = "spotify.position", ms = 1 }))
    assert_nil(streaming.on_deezer(doc, { type = "deezer.paused", flag = "1" }))
    assert_eq(doc.playback.state, "playing")
  end)
end)

describe("services.streaming — presets, config, login", function()
  it("saving a Spotify preset creates the playlist from what is playing", function()
    local doc = doc_with()
    local _, err = streaming.on_new_spotify_playlist(doc, { title = "T" })
    assert_eq(err.code, "unavailable")
    doc.playback = { state = "playing", now = { service = "SPOTIFY", uri = "spotify:playlist:1", source = "Jazz", image = "i.png" }, last = {}, shuffle = {} }
    local r = streaming.on_new_spotify_playlist(doc, { title = "Soir", star = "Jooki.Fox" })
    assert_eq(topics(r), { "spotify/output/save_preset " })
    apply(doc, r)
    r = streaming.on_spotify(doc, { type = "spotify.new_preset", raw = "AB" })
    local ev = r.commands[1].event
    assert_eq(ev.type, "library.add_playlist"); assert_eq(ev.spotify, { uri = "spotify:playlist:1", preset = "4142" }); assert_eq(ev.star, "Jooki.Fox")
    assert_eq(r.state.streaming_int, {})
  end)

  it("config and volume changes reach the active service only", function()
    local doc = doc_with({ playback = { state = "playing", now = { service = "SPOTIFY" } }, audiocfg = { volume = 50, shuffle_mode = true, repeat_mode = 0 } })
    assert_eq(topics(streaming.on_config(doc, { shuffle_mode = true, volume = 50 })), { "spotify/output/set_shuffle 1", "spotify/output/set_vol 32767" })
    doc.playback.now.service = "FILE"
    assert_nil(streaming.on_config(doc, { shuffle_mode = true }))
  end)

  it("login / logout / errors", function()
    local doc = doc_with()
    local r = streaming.on_spotify(doc, { type = "spotify.login", username = "bob" })
    assert_eq(r.state.spotify.username, "bob"); assert_eq(topics(r), { "emit volume.apply" })
    assert_eq(topics(streaming.on_spotify(doc, { type = "spotify.login_required" })), { "emit system.event Evt.Spotify.NoLoginError" })
    assert_eq(topics(streaming.on_spotify(doc, { type = "spotify.status" })), { "spotify/output/connection_state 2" })
    assert_eq(streaming.hex2str("4142"), "AB"); assert_eq(streaming.str2hex("AB"), "4142")
  end)
end)
