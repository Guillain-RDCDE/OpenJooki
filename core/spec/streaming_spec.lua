local streaming = require("services.streaming")
local playback = require("services.playback")
local resume = require("services.playback.resume")
local function emitted(r, t) for _, c in ipairs((r and r.commands) or {}) do if c.kind == "emit" and c.event.type == t then return c.event end end end

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
-- a playlist set to resume started, and Spotify asked to continue gave no answer: the character's own place
local function own_place(doc, r)
  apply(doc, r)
  apply(doc, streaming.on_cont(doc, emitted(r, "streaming.cont")))
  return streaming.on_cont_timer(doc)
end

describe("services.streaming — starting and transport through playback", function()
  it("Deezer stops at the song end with a track timer, and otherwise asks for the next song", function()
    local doc = doc_with({ playback = { state = "playing", now = { service = "DEEZER", title = "Song" } } })
    assert_eq(topics(streaming.on_deezer(doc, { type = "deezer.ended" })),
      { "deezer/output/next ", "emit playback.changed idle" })
    doc.bedtime_int = { stop_at_end = true }
    local r = streaming.on_deezer(doc, { type = "deezer.ended" })
    assert_eq(r.state.playback.state, "ended")
    assert_eq(topics(r), { "emit playback.changed ended" })
  end)

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

  it("Spotify taking over from the app stops the local file (on 'playing', the last one to start wins)", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "loc" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    -- the track alone does not take over: the phone may only have changed the track of a paused Spotify
    local r = streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:album:9", track = "X" } })
    assert_eq(topics(r), {}); assert_nil(r.state.playback)
    apply(doc, r)
    r = streaming.on_spotify(doc, { type = "spotify.playing" })
    assert_eq(topics(r), { "audio/out/stop 7", "emit playback.changed playing" })
    assert_eq(r.state.playback.state, "playing"); assert_eq(r.state.playback.now.service, "SPOTIFY"); assert_eq(r.state.playback.now.title, "X")
    apply(doc, r)
    -- the local engine's late "stopped" must not touch Spotify's state
    assert_nil(playback.on_audio(doc, { type = "audio.stopped", id = 7 }))
    assert_nil(playback.on_audio(doc, { type = "audio.position", id = 7, ms = 10 }))
    assert_eq(doc.playback.state, "playing")
  end)

  it("Spotify started from the phone is what plays, whatever the order of the daemon's two messages", function()
    local track = { source_uri = "spotify:playlist:5", source = "Chill", track = "Song", artist = "Band", duration_ms = "180000", image = "http://i" }
    for _, order in ipairs({ { "now_playing", "playing" }, { "playing", "now_playing" } }) do
      local doc = doc_with()
      for _, kind in ipairs(order) do
        apply(doc, streaming.on_spotify(doc, { type = "spotify." .. kind, data = kind == "now_playing" and track or nil }))
      end
      local now = doc.playback.now
      assert_eq(doc.playback.state, "playing", order[1] .. " first")
      assert_eq(now.service, "SPOTIFY"); assert_nil(now.playlist)
      assert_eq(now.title, "Song"); assert_eq(now.artist, "Band"); assert_eq(now.source, "Chill"); assert_eq(now.duration_ms, 180000)
      apply(doc, streaming.on_spotify(doc, { type = "spotify.position", ms = 3000 }))
      assert_eq(doc.playback.position_ms, 3000)
      -- taking a token off does not pause the phone's Spotify; the sleep timer does
      assert_nil(playback.on_pause(doc, { source = "token" }))
      assert_eq(topics(playback.on_pause(doc, { source = "sleep_timer" })), { "spotify/output/pauz " })
      -- the page's pause and play reach the daemon, even without a playlist of ours
      assert_eq(topics(playback.on_pause(doc, { source = "page" })), { "spotify/output/pauz " })
      apply(doc, streaming.on_spotify(doc, { type = "spotify.paused" }))
      assert_eq(doc.playback.state, "paused")
      assert_eq(topics(playback.on_toggle(doc, { now = 9 })), { "spotify/output/cont " })
    end
  end)

  it("the cover: Spotify's own spotify:image:<id> becomes the address a browser can show", function()
    assert_eq(streaming.cover_url("spotify:image:ab67616d0000b273e8b066f70c206551210d902b"),
              "https://i.scdn.co/image/ab67616d0000b273e8b066f70c206551210d902b")
    assert_eq(streaming.cover_url("https://i.scdn.co/image/ab67"), "https://i.scdn.co/image/ab67")   -- already an address
    assert_nil(streaming.cover_url("")); assert_nil(streaming.cover_url(nil))
    assert_eq(streaming.cover_url("spotify:image:not-hex!"), "spotify:image:not-hex!")              -- unknown form: untouched
    local doc = doc_with()
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing" }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { track = "A", image = "spotify:image:0a1b" } }))
    assert_eq(doc.playback.now.image, "https://i.scdn.co/image/0a1b")
    local r = streaming.on_spotify(doc, { type = "spotify.now_playing", data = { track = "B", image = "spotify:image:2c3d" } })
    assert_eq(r.state.playback.now.image, "https://i.scdn.co/image/2c3d")
    assert_eq(r.commands[1].key, "streaming.spotify_cover"); assert_eq(r.commands[1].fields.raw, "spotify:image:2c3d")
    apply(doc, r)
    assert_nil(streaming.on_spotify(doc, { type = "spotify.now_playing", data = { track = "B", image = "spotify:image:2c3d" } }).commands)
  end)

  it("a token put on while Spotify plays pauses Spotify and plays alone", function()
    local doc = doc_with()
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing" }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:album:9", track = "X" } }))
    assert_eq(doc.playback.state, "playing")
    local r = playback.on_request(doc, { playlist = "loc" })
    assert_eq(topics(r), { "spotify/output/pauz ", "audio/out/play 7\tfile:///d/uploads/a", "emit playback.changed starting" })
    apply(doc, r)
    assert_eq(doc.playback.now.service, "FILE")
    -- the daemon confirms the pause: our state stays the token's
    apply(doc, streaming.on_spotify(doc, { type = "spotify.paused" }))
    assert_eq(doc.playback.now.service, "FILE"); assert_eq(doc.playback.state, "starting")
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    assert_eq(doc.playback.state, "playing")
    -- pressing play on the phone again: Spotify takes the speaker back
    r = streaming.on_spotify(doc, { type = "spotify.playing" })
    assert_eq(topics(r)[1], "audio/out/stop 7"); assert_eq(r.state.playback.now.title, "X")
  end)

  it("a token put on pauses Spotify even when our state missed that it plays", function()
    local doc = doc_with({ spotify = { active = true, playing = true } })
    local r = playback.on_request(doc, { playlist = "loc" })
    assert_eq(topics(r)[1], "spotify/output/pauz ")
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
    assert_nil(streaming.on_spotify(doc, { type = "spotify.position", ms = 1 }))
    assert_nil(streaming.on_spotify(doc, { type = "spotify.paused" }).state.playback)
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
    -- an empty answer from Spotify creates nothing
    apply(doc, streaming.on_new_spotify_playlist(doc, { title = "Soir", star = "Jooki.Fox" }))
    r = streaming.on_spotify(doc, { type = "spotify.new_preset", raw = "" })
    assert_eq(r.commands[1].key, "streaming.preset_empty"); assert_eq(r.state.streaming_int, {})
  end)

  it("a token linked to a Spotify preset plays it; taking it off pauses it (a token started it)", function()
    local doc = doc_with()
    doc.library.playlists.sp.star = "Jooki.Fox"
    local r = playback.on_request(doc, { playlist = "sp", now = 1 })
    assert_eq(topics(r)[1], "spotify/output/play_preset AB")
    apply(doc, r)
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing" }))
    assert_eq(doc.playback.now.playlist, "sp"); assert_eq(doc.playback.state, "playing")
    assert_eq(topics(playback.on_pause(doc, { source = "token" })), { "spotify/output/pauz " })
  end)

  it("the token put back on its paused Spotify playlist starts it again, or continues it when the playlist is set to resume", function()
    local function paused_on_sp(on)
      local doc = doc_with()
      doc.library.playlists.sp.resume = on
      apply(doc, playback.on_request(doc, { playlist = "sp", now = 1 }))
      apply(doc, streaming.on_spotify(doc, { type = "spotify.active", active = true }))
      apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Track 1" } }))
      apply(doc, streaming.on_spotify(doc, { type = "spotify.playing" }))
      apply(doc, streaming.on_spotify(doc, { type = "spotify.paused" }))
      return doc
    end
    assert_eq(topics(playback.on_request(paused_on_sp(nil), { playlist = "sp", now = 2 }))[1], "spotify/output/play_preset AB")
    local doc = paused_on_sp(true)
    local r = playback.on_request(doc, { playlist = "sp", now = 2 })
    assert_eq(topics(r), { "spotify/output/cont " }); assert_nil(r.state)
    -- the account went on elsewhere since (the phone): `cont` would bring that, so it is checked
    local moved = paused_on_sp(true)
    apply(moved, streaming.on_spotify(moved, { type = "spotify.active", active = false }))
    assert_eq(topics(playback.on_request(moved, { playlist = "sp", now = 2 })), { "spotify/output/cont ", "emit streaming.cont", "emit playback.changed starting" })
    -- put back while it still plays (taken off with continue_on_token_removal): it goes on playing
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing" }))
    r = playback.on_request(doc, { playlist = "sp", now = 2 })
    assert_eq(topics(r), {}); assert_nil(r.state)
    apply(doc, streaming.on_spotify(doc, { type = "spotify.paused" }))
    -- another playlist in between: Spotify is asked to continue
    apply(doc, playback.on_request(doc, { playlist = "loc", now = 3 }))
    doc.playback.state = "paused"
    assert_eq(topics(playback.on_request(doc, { playlist = "sp", now = 4 })), { "audio/out/stop 7", "spotify/output/cont ", "emit streaming.cont", "emit playback.changed starting" })
  end)

  it("a playlist set to resume saves where it stopped on token off, and plays from there after another playlist", function()
    local doc = doc_with()
    doc.library.playlists.sp.resume = true
    apply(doc, playback.on_request(doc, { playlist = "sp", now = 1 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Track 1", album = "Album 1" }, now = 1 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 1 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.position", ms = 96824, now = 2 }))
    -- token off: playback hands over to streaming, which asks for a preset, then pauses
    local r = playback.on_pause(doc, { source = "token", now = 2 })
    local ev = emitted(r, "streaming.save_resume")
    assert_eq(ev, { type = "streaming.save_resume", playlist = "sp", position_ms = 96824, now = 2 })
    ev.now = 2
    r = streaming.on_save_resume(doc, ev)
    assert_eq(topics(r), { "spotify/output/save_preset ", "spotify/output/pauz " })
    apply(doc, r)
    -- Spotify answers with where it is: resume.json gets it at once
    r = streaming.on_spotify(doc, { type = "spotify.new_preset", raw = "CD" })
    ev = emitted(r, "playback.spotify_resume")
    assert_eq(ev.playlist, "sp"); assert_eq(ev.title, "Track 1"); assert_eq(ev.album, "Album 1"); assert_eq(ev.preset, "4344"); assert_eq(ev.position_ms, 96824); assert_true(ev.flush)
    apply(doc, r)
    assert_nil(doc.streaming_int.resume_for)
    r = resume.on_spotify(doc, ev)
    assert_eq(r.commands[1].path, "/d/resume.json"); assert_eq(r.commands[1].doc.sp, { id = "Track 1", album = "Album 1", pos = 96824, preset = "4344" })
    apply(doc, r)
    assert_eq(doc.library.playlists.sp.spotify, { uri = "spotify:playlist:1", preset = "4142" })
    apply(doc, streaming.on_spotify(doc, { type = "spotify.paused", now = 3 }))
    -- another playlist in between, then the token again: the saved preset, and the seek once it plays
    apply(doc, playback.on_request(doc, { playlist = "loc", now = 3 }))
    r = own_place(doc, playback.on_request(doc, { playlist = "sp", now = 4 }))
    assert_eq(topics(r), { "spotify/output/play_preset CD" })
    apply(doc, r)
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Track 1" } }))
    assert_eq(doc.playback.resume_ms, 96824 - 15000)
    r = streaming.on_spotify(doc, { type = "spotify.playing" })
    assert_eq(topics(r), { "emit playback.changed playing", "spotify/output/seek 81824" })
    apply(doc, r)
    assert_nil(doc.playback.resume_ms)
    -- with the switch off: the preset saved with the playlist, from its start
    doc.library.playlists.sp.resume = nil
    apply(doc, playback.on_request(doc, { playlist = "loc", now = 5 }))
    r = playback.on_request(doc, { playlist = "sp", now = 6 })
    assert_eq(topics(r)[2], "spotify/output/play_preset AB"); assert_nil(r.state.playback.resume_ms)
  end)

  it("another playlist started from the phone after a token's is no longer the token's, and its place is not saved as the token's", function()
    local doc = doc_with()
    doc.library.playlists.sp.resume = true
    apply(doc, playback.on_request(doc, { playlist = "sp", now = 0 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Track 1" }, now = 0 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 0 }))
    assert_eq(doc.playback.now.playlist, "sp")
    -- the same playlist, next track: still the token's
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Track 3" }, now = 1 }))
    assert_eq(doc.playback.now.playlist, "sp")
    -- the phone starts another playlist
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:9", track = "Track 9" }, now = 2 }))
    assert_nil(doc.playback.now.playlist)
    assert_nil(streaming.on_resume_tick(doc, { now = 40 }))
  end)

  it("a character's playlist set to resume, played from the phone, is that playlist: its place follows the phone", function()
    local doc = doc_with()
    doc.library.playlists.sp.resume = true
    doc.resume = { sp = { id = "Track 1", pos = 5000, preset = "4344" } }
    -- started from the phone with nothing playing
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Track 2" }, now = 0 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 0 }))
    assert_eq(doc.playback.now.playlist, "sp")
    -- a new track: the tick asks for its preset, as for the token
    assert_eq(topics(streaming.on_resume_tick(doc, { now = 30 })), { "spotify/output/save_preset " })
    -- without the switch, it stays the phone's
    local d2 = doc_with()
    apply(d2, streaming.on_spotify(d2, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Track 2" }, now = 0 }))
    assert_nil(d2.playback.now.playlist)
    -- the phone moving on to that playlist from another one
    local d3 = doc_with()
    d3.library.playlists.sp.resume = true
    apply(d3, streaming.on_spotify(d3, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:9", track = "Track 9" }, now = 0 }))
    apply(d3, streaming.on_spotify(d3, { type = "spotify.playing", now = 0 }))
    assert_nil(d3.playback.now.playlist)
    apply(d3, streaming.on_spotify(d3, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Track 1" }, now = 5 }))
    assert_eq(d3.playback.now.playlist, "sp")
    -- paused on the phone, the character put on: it continues
    apply(doc, streaming.on_spotify(doc, { type = "spotify.active", active = true }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.paused", now = 40 }))
    assert_eq(topics(playback.on_request(doc, { playlist = "sp", now = 50 })), { "spotify/output/cont " })
  end)

  it("with spotify_ctrl patched, the saved place goes as one request for its track and time", function()
    -- a preset as Spotify gives it: context, then track 41, then options, then the track's URI
    local preset = "088180FCFFFFFFFFFFFF01122773706F746966793A706C61796C6973743A304578616D706C65506C61796C697374303030303031"
      .. "1A0408001029" .. "2206080010001800" .. "2A2473706F746966793A747261636B3A304578616D706C65547261636B303030303030303431"
    local doc = doc_with({ int = { direct = true } })
    doc.library.playlists.sp.resume = true
    doc.resume = { sp = { id = "Chapter 14", pos = 96824, preset = preset } }
    local r = own_place(doc, playback.on_request(doc, { playlist = "sp", now = 1 }))
    local c = r.commands[1]
    assert_eq(c.topic, "/j/spotify/output/play_preset")
    local uri = "spotify:playlist:0ExamplePlaylist000001"
    local function u32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
    assert_eq(c.payload, uri .. string.rep("\0", 64 - #uri) .. u32(41) .. u32(0) .. u32(96824 - 15000) .. u32(0) .. u32(0))
    -- nothing to seek once it plays
    assert_nil(r.state.streaming_int.cont.seek_ms)
    -- a place too close to the start: time 0
    doc.resume.sp.pos = 4000
    c = own_place(doc, playback.on_request(doc, { playlist = "sp", now = 2 })).commands[1]
    assert_eq(c.payload:sub(65), u32(41) .. u32(0) .. u32(0) .. u32(0) .. u32(0))
    -- without the patch, or with a preset that does not read as one: the preset, and the seek
    doc.resume.sp.pos = 96824
    doc.streaming_int.direct = nil
    r = own_place(doc, playback.on_request(doc, { playlist = "sp", now = 3 }))
    assert_eq(r.commands[1].payload, streaming.hex2str(preset)); assert_eq(r.state.streaming_int.cont.seek_ms, 96824 - 15000)
    doc.streaming_int.direct = true
    doc.resume.sp.preset = "4344"
    r = own_place(doc, playback.on_request(doc, { playlist = "sp", now = 4 }))
    assert_eq(r.commands[1].payload, "CD"); assert_eq(r.state.streaming_int.cont.seek_ms, 96824 - 15000)
  end)

  it("chapters added at the top of its playlist: the saved track is sought from its old index, muted, then its time", function()
    local preset = "088180FCFFFFFFFFFFFF01122773706F746966793A706C61796C6973743A304578616D706C65506C61796C697374303030303031"
      .. "1A0408001029" .. "2206080010001800" .. "2A2473706F746966793A747261636B3A304578616D706C65547261636B303030303030303431"
    local uri = "spotify:playlist:0ExamplePlaylist000001"
    local function started()
      local doc = doc_with({ int = { direct = true } })
      doc.library.playlists.sp.resume = true
      doc.library.playlists.sp.spotify.uri = uri
      doc.resume = { sp = { id = "Chapter 14", album = "Episode 103", pos = 96824, preset = preset } }
      local r = own_place(doc, playback.on_request(doc, { playlist = "sp", now = 1 }))
      apply(doc, r)
      local f = emitted(r, "streaming.find")
      assert_eq(f.index, 41); assert_eq(f.pos, 81824)
      apply(doc, streaming.on_find(doc, f))
      apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 2 }))
      return doc
    end
    local function np(doc, track, album, more)
      local d = { source_uri = uri, track = track, album = album, hasNext = true }
      for k, v in pairs(more or {}) do d[k] = v end
      local r = streaming.on_spotify(doc, { type = "spotify.now_playing", data = d, now = 3 })
      apply(doc, r)
      return r
    end
    local function has(r, kind) for _, c in ipairs(r.commands or {}) do if c.kind == kind then return c end end end
    -- the saved track at its index: nothing more
    local doc = started()
    local r = np(doc, "Chapter 14", "Episode 103")
    assert_eq(topics(r), { "emit volume.apply" }); assert_nil(doc.streaming_int.find)
    -- two chapters added: another one plays, muted and skipped until the saved one, then its time
    doc = started()
    r = np(doc, "Chapter 12", "Episode 103")
    assert_eq(topics(r), { "spotify/output/next " }); assert_eq(has(r, "host.volume").percent, 0)
    assert_nil(streaming.on_resume_tick(doc, { now = 30 }))
    assert_eq(topics(np(doc, "Chapter 13", "Episode 103", { restricted = true })), {})
    assert_eq(topics(np(doc, "Chapter 13", "Episode 103")), { "spotify/output/next " })
    r = np(doc, "Chapter 14", "Episode 103")
    assert_eq(topics(r), { "emit volume.apply", "spotify/output/seek 81824" })
    assert_nil(doc.streaming_int.find)
    -- the same title in another episode is not the saved track
    doc = started()
    assert_eq(topics(np(doc, "Chapter 14", "Episode 104")), { "spotify/output/next " })
    -- the end of the playlist, or too many skips: back to the saved index, at the volume it had
    doc = started()
    r = np(doc, "Theme song", "Episode 50", { hasNext = false })
    assert_eq(topics(r), { "emit volume.apply", "spotify/output/play_preset " .. streaming.direct_request(uri, 41, 81824) })
    assert_nil(doc.streaming_int.find)
    doc = started()
    doc.streaming_int.find.skips = 60
    assert_eq(topics(np(doc, "Chapter 1", "Episode 120")), { "emit volume.apply", "spotify/output/play_preset " .. streaming.direct_request(uri, 41, 81824) })
    -- given up after a while
    doc = started()
    np(doc, "Chapter 12", "Episode 103")
    r = streaming.on_find_timer(doc)
    assert_eq(topics(r), { "emit volume.apply" }); apply(doc, r); assert_nil(doc.streaming_int.find)
    assert_nil(streaming.on_find_timer(doc))
    -- taken off during the search: the saved place stays
    doc = started()
    np(doc, "Chapter 12", "Episode 103")
    r = streaming.on_save_resume(doc, { playlist = "sp", now = 4 })
    assert_eq(topics(r), { "spotify/output/pauz ", "emit volume.apply" }); apply(doc, r)
    assert_nil(doc.streaming_int.find); assert_nil(doc.streaming_int.resume_for)
    -- an older place without its album: the title alone
    doc = started()
    doc.streaming_int.find.album = nil
    assert_eq(topics(np(doc, "Chapter 14", "Episode 104")), { "emit volume.apply" })
    -- the phone plays something else during the search: it ends, the volume back
    doc = started()
    np(doc, "Chapter 12", "Episode 103")
    r = streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:9", track = "Track 9" }, now = 4 })
    assert_eq(topics(r), { "emit volume.apply" }); apply(doc, r); assert_nil(doc.streaming_int.find)
    -- local music started from the page during the search: the same
    doc = started()
    np(doc, "Chapter 12", "Episode 103")
    apply(doc, playback.on_request(doc, { playlist = "loc", now = 4 }))
    r = streaming.on_playback_changed(doc)
    assert_eq(topics(r), { "emit volume.apply" }); apply(doc, r); assert_nil(doc.streaming_int.find)
    assert_nil(streaming.on_playback_changed(doc))
    -- the album survives a restart
    local saved = resume.on_boot(doc, { resume = { sp = { id = "Chapter 14", album = "Episode 103", pos = 1, preset = "AB" } } }).state.resume
    assert_eq(saved.sp.album, "Episode 103")
  end)

  it("a character set to resume continues the account's playback when that is its playlist, or else plays its own place", function()
    local function started(o)
      local doc = doc_with(o)
      doc.library.playlists.sp.resume = true
      doc.resume = { sp = { id = "Track 1", pos = 96824, preset = "4344" } }
      local r = playback.on_request(doc, { playlist = "sp", now = 1 })
      apply(doc, r)
      if emitted(r, "streaming.cont") then apply(doc, streaming.on_cont(doc, emitted(r, "streaming.cont"))) end
      return doc, r
    end
    local function np(doc, uri, track) return streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = uri, track = track }, now = 2 }) end
    -- listened to on the phone since: it goes on from there, and is still the character's
    local doc, r = started()
    assert_eq(topics(r), { "spotify/output/cont ", "emit streaming.cont", "emit playback.changed starting" })
    r = np(doc, "spotify:playlist:1", "Track 2")
    assert_eq(topics(r), {}); assert_eq(r.commands[1], { kind = "timer.cancel", name = "streaming.cont" })
    apply(doc, r)
    assert_eq(doc.playback.now.playlist, "sp"); assert_eq(doc.playback.now.title, "Track 2"); assert_nil(doc.streaming_int.cont)
    assert_nil(doc.playback.resume_ms)
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 2 }))
    assert_eq(topics(streaming.on_resume_tick(doc, { now = 30 })), { "spotify/output/save_preset " })
    assert_nil(streaming.on_cont_timer(doc))
    -- something else was continued: the character's place, and its seek waits for its playlist
    doc = started()
    r = np(doc, "spotify:playlist:9", "Track 9")
    assert_eq(topics(r), { "spotify/output/play_preset CD" })
    apply(doc, r)
    assert_eq(doc.playback.now.playlist, "sp"); assert_nil(doc.playback.now.title)
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 2 }))
    assert_nil(doc.playback.resume_ms)
    assert_nil(streaming.on_resume_tick(doc, { now = 30 }))
    assert_eq(topics(np(doc, "spotify:playlist:9", "Track 9")), {})
    r = np(doc, "spotify:playlist:1", "Track 1")
    assert_eq(topics(r), { "spotify/output/seek 81824" })
    apply(doc, r)
    assert_nil(doc.streaming_int.cont); assert_eq(doc.playback.now.title, "Track 1")
    -- no answer in time, or an error: the character's place
    doc = started()
    assert_eq(topics(streaming.on_cont_timer(doc)), { "spotify/output/play_preset CD" })
    doc = started()
    r = streaming.on_spotify(doc, { type = "spotify.play_error" })
    assert_eq(topics(r), { "spotify/output/play_preset CD" })
    apply(doc, r)
    -- the second timer ends a wait whose playlist never reported
    apply(doc, streaming.on_cont_timer(doc))
    assert_nil(doc.streaming_int.cont)
    -- the token taken off while waiting: what Spotify then continues is left alone
    doc = started()
    apply(doc, streaming.on_save_resume(doc, { playlist = "sp", now = 2 }))
    assert_nil(doc.streaming_int.cont)
    -- Spotify already plays another playlist on the Jooki: continuing would resume that, so the place
    r = select(2, started({ spotify = { active = true, track = { source_uri = "spotify:playlist:9" } } }))
    assert_eq(topics(r), { "spotify/output/play_preset CD", "emit playback.changed starting" })
  end)

  it("the core knows at boot whether spotify_ctrl is patched", function()
    local seen
    local dispatch = { on = function(t, _, fn) if t == "boot" then seen = fn end end, on_timer = function() end }
    streaming.install({ command = function() end }, dispatch)
    assert_true(seen({}, { spotify_direct = true }).state.streaming_int.direct)
    assert_nil(seen({}, { spotify_direct = false }).state.streaming_int.direct)
  end)

  it("a playlist set to resume keeps its place while it plays: a Jooki switched off with the token on starts there", function()
    local doc = doc_with()
    doc.library.playlists.sp.resume = true
    local function track(name, t) apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = name, duration_ms = 600000 }, now = t })) end
    apply(doc, playback.on_request(doc, { playlist = "sp", now = 0 }))
    track("Track 1", 0)
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 0 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.position", ms = 1000, now = 1 }))
    -- the first tick asks Spotify for a preset of the track; not again while the answer is on its way
    local r = streaming.on_resume_tick(doc, { now = 30 })
    assert_eq(topics(r), { "spotify/output/save_preset " })
    assert_eq(r.state.streaming_int.resume_for, { playlist = "sp", title = "Track 1", position_ms = 30000, t = 30 })
    apply(doc, r)
    assert_nil(streaming.on_resume_tick(doc, { now = 40 }))
    r = streaming.on_spotify(doc, { type = "spotify.new_preset", raw = "CD" })
    local ev = emitted(r, "playback.spotify_resume")
    assert_nil(ev.flush)
    apply(doc, r)
    r = resume.on_spotify(doc, ev)
    assert_nil(r.commands); assert_true(r.state.playback_int.resume_dirty)
    apply(doc, r)
    -- later ticks note the time (the daemon said nothing since: it is counted from its last report)
    r = streaming.on_resume_tick(doc, { now = 150 })
    ev = emitted(r, "playback.spotify_resume")
    assert_eq(ev, { type = "playback.spotify_resume", playlist = "sp", title = "Track 1", position_ms = 150000 })
    apply(doc, resume.on_spotify(doc, ev))
    -- the save timer writes it
    r = resume.on_save(doc)
    assert_eq(r.commands[1].doc.sp, { id = "Track 1", pos = 150000, preset = "4344" })
    apply(doc, r)
    -- a new track: its time is not noted against the old track's preset; a new preset is asked for
    track("Track 3", 160)
    r = streaming.on_resume_tick(doc, { now = 180 })
    assert_eq(topics(r), { "spotify/output/save_preset " }); assert_eq(r.state.streaming_int.resume_for.position_ms, 20000)
    -- switched off here (no token off): after the restart, resume.json read back, the token starts where it was
    local doc2 = doc_with()
    doc2.library.playlists.sp.resume = true
    apply(doc2, resume.on_boot(doc2, { resume = doc.resume }))
    r = own_place(doc2, playback.on_request(doc2, { playlist = "sp", now = 1 }))
    assert_eq(topics(r)[1], "spotify/output/play_preset CD")
    assert_eq(r.state.streaming_int.cont.seek_ms, 150000 - 15000)
    -- the same title in another album is another track: a new preset, not the old one's time
    local doc3 = doc_with()
    doc3.library.playlists.sp.resume = true
    doc3.resume = { sp = { id = "Chapter 1", album = "Episode 1", pos = 1000, preset = "4344" } }
    apply(doc3, playback.on_request(doc3, { playlist = "sp", now = 0 }))
    apply(doc3, streaming.on_spotify(doc3, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Chapter 1", album = "Episode 2" }, now = 0 }))
    apply(doc3, streaming.on_spotify(doc3, { type = "spotify.playing", now = 0 }))
    assert_eq(topics(streaming.on_resume_tick(doc3, { now = 30 })), { "spotify/output/save_preset " })
    assert_nil(resume.on_spotify(doc3, { playlist = "sp", title = "Chapter 1", album = "Episode 2", position_ms = 30000 }))
  end)

  it("page pause saves the elapsed position and repeated metadata does not rewind its clock", function()
    local doc = doc_with(); doc.library.playlists.sp.resume = true
    apply(doc, playback.on_request(doc, { playlist = "sp", now = 0 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Chapter", album = "Album" }, now = 0 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 0 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:1", track = "Chapter", album = "Album" }, now = 60 }))
    assert_eq(streaming.sp_position(doc, 180), 180000)
    local ev = emitted(playback.on_pause(doc, { source = "page", now = 180 }), "streaming.save_resume")
    local r = streaming.on_save_resume(doc, ev)
    assert_eq(r.state.streaming_int.resume_for.position_ms, 180000)
    assert_true(r.state.streaming_int.resume_for.flush)
    apply(doc, r)
    apply(doc, streaming.on_spotify(doc, { type = "spotify.paused", now = 180 }))
    assert_eq(doc.playback.position_ms, 180000)
  end)

  it("nothing is noted for a Spotify playlist without the switch, or paused", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "sp", now = 0 }))
    apply(doc, streaming.on_spotify(doc, { type = "spotify.playing", now = 0 }))
    assert_nil(streaming.on_resume_tick(doc, { now = 30 }))
    doc.library.playlists.sp.resume = true
    apply(doc, streaming.on_spotify(doc, { type = "spotify.paused", now = 31 }))
    assert_nil(streaming.on_resume_tick(doc, { now = 60 }))
  end)

  it("an empty answer from Spotify keeps the last saved place", function()
    local doc = doc_with({ int = { resume_for = { playlist = "sp", position_ms = 5000 } } })
    local r = streaming.on_spotify(doc, { type = "spotify.new_preset", raw = "" })
    assert_eq(r.commands[1].key, "streaming.resume_preset_empty"); assert_eq(r.state.streaming_int, {})
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
    assert_eq(topics(streaming.on_spotify(doc, { type = "spotify.status" })), { "spotify/output/connection_state 0" })   -- no address yet
    doc.net.ip = "192.168.1.19"
    assert_eq(topics(streaming.on_spotify(doc, { type = "spotify.status" })), { "spotify/output/connection_state 2" })
    -- every Wi-Fi report tells Spotify (a "no network" at boot must not stick)
    assert_eq(topics(streaming.on_net(doc, { connected = false })), { "spotify/output/connection_state 0" })
    assert_eq(topics(streaming.on_net(doc, { connected = true, ip = "192.168.1.19" })), { "spotify/output/connection_state 2" })
    assert_eq(streaming.hex2str("4142"), "AB"); assert_eq(streaming.str2hex("AB"), "4142")
  end)
end)

describe("services.streaming — the Jooki's own Spotify account", function()
  local v1 = require("api.v1")
  local security = require("services.security")
  local shell = require("adapters.shell")
  local function kinds(r, kind)
    local out = {}
    for _, c in ipairs((r and r.commands) or {}) do if c.kind == kind then out[#out + 1] = c end end
    return out
  end

  it("the account name is what starts the daemon's file, up to its NUL", function()
    assert_eq(streaming.saved_user("10987654321\0\0\0\1\2blob"), "10987654321")
    assert_eq(streaming.saved_user("x7q2example0account0id00\0" .. string.rep("\0", 40)), "x7q2example0account0id00")
    assert_nil(streaming.saved_user(nil)); assert_nil(streaming.saved_user("")); assert_nil(streaming.saved_user("\0abc"))
    assert_nil(streaming.saved_user("no-nul-anywhere"))            -- not the daemon's file
    assert_nil(streaming.saved_user("bad name\0"))                 -- not an account name
  end)

  it("boot and every login read the file again; the state says which account comes back after a restart", function()
    local doc = doc_with(); doc.config.spotify_credentials_file = "/tmp/cred.bin"
    local r = streaming.on_boot(doc)
    assert_eq(r.state.spotify.saved, false)
    local reads = kinds(r, "files.read_text")
    assert_eq(#reads, 1); assert_eq(reads[1].path, "/tmp/cred.bin"); assert_eq(reads[1].reply, "spotify.saved_read")
    apply(doc, r)
    r = streaming.on_saved_read(doc, { text = "alice\0rest" })
    assert_eq(r.state.spotify.saved, "alice")
    apply(doc, r)
    assert_nil(streaming.on_saved_read(doc, { text = "alice\0rest" }))       -- unchanged: nothing published
    -- a guest logs in: the daemon does not save it, the file still says alice
    r = streaming.on_spotify(doc, { type = "spotify.login", username = "bob" })
    assert_eq(#kinds(r, "files.read_text"), 1)
    apply(doc, r)
    assert_nil(streaming.on_saved_read(doc, { text = "alice\0rest" }))
    assert_eq(doc.spotify.username, "bob"); assert_eq(doc.spotify.saved, "alice")
    -- no file: no account of its own
    assert_eq(streaming.on_saved_read(doc, { text = nil }).state.spotify.saved, false)
  end)

  it("forgetting: the daemon starts again with no account, what Spotify played stops being what plays", function()
    local doc = doc_with({ spotify = { active = true, username = "bob", saved = "alice", playing = true },
                           playback = { state = "playing", now = { service = "SPOTIFY", title = "Song" }, last = {}, shuffle = {} } })
    doc.config.spotify_credentials_file = "/tmp/cred.bin"
    local r = streaming.on_forget_account(doc)
    local sh = kinds(r, "shell")
    assert_eq(#sh, 1); assert_eq(sh[1].action, "spotify_forget"); assert_eq(sh[1].args.file, "/tmp/cred.bin")
    assert_eq(r.state.spotify.saved, false); assert_nil(r.state.spotify.username); assert_eq(r.state.spotify.active, false)
    assert_nil(r.state.playback.now); assert_eq(r.state.playback.state, "idle")
    -- the next account that picks the Jooki is saved by the daemon: the read after its login says so
    apply(doc, r)
    apply(doc, streaming.on_spotify(doc, { type = "spotify.login", username = "carol" }))
    assert_eq(streaming.on_saved_read(doc, { text = "carol\0x" }).state.spotify.saved, "carol")
  end)

  it("v1: a change of state.spotify reaches the page (its Spotify settings follow the account)", function()
    local msg = v1.partial({ spotify = { active = false, saved = "alice", username = "bob" } }, { "spotify" })
    assert_eq(msg.payload.spotify.saved, "alice"); assert_eq(msg.payload.spotify.username, "bob")
  end)

  it("forgetting needs the parent code (v1 and v2); the shell action only takes a plain path", function()
    assert_true(v1.PROTECTED.OJ_SPOTIFY_FORGET); assert_true(security.PROTECTED_V2["spotify.forget_account"])
    local argv = shell.ACTIONS.spotify_forget.argv({ file = "/data/spotify/credentials.bin" })
    assert_eq(argv[1], "sh"); assert_eq(argv[#argv], "/data/spotify/credentials.bin")
    assert_nil(shell.ACTIONS.spotify_forget.argv({ file = "../etc/passwd" }))
    assert_nil(shell.ACTIONS.spotify_forget.argv({ file = "/x;rm -rf /" .. "'" }))
  end)
end)
