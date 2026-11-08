local streaming = require("services.streaming")
local playback = require("services.playback")
local device = require("services.device")
local function doc()
  return { audiocfg = { volume = 40, random_start = true, shuffle_mode = false, repeat_mode = 1 },
    library = { playlists = { music = { title = "Music", spotify = { uri = "spotify:playlist:music", preset = "AB" } } }, tracks = {}, tokens = {} },
    spotify = { active = true }, streaming_int = {}, playback = { state = "idle" }, resume = {}, config = {} }
end
local function apply(d, r) for k, v in pairs((r or {}).state or {}) do d[k] = v end return r end
local function sent(r, suffix)
  for _, c in ipairs((r or {}).commands or {}) do if c.topic == "/j/spotify/output/" .. suffix then return c.payload end end
end
local function event(d, ev) return apply(d, streaming.on_spotify(d, ev)) end
local function track(d, title, uri)
  local r = event(d, { type = "spotify.now_playing", now = 1, data = { track = title, album = "Album", source_uri = uri or "spotify:playlist:music" } })
  if (d.streaming_int.random_start or {}).phase == "settling" then return event(d, { type = "spotify.position", ms = 0, now = 1 }) end
  return r
end
local function begin(d)
  apply(d, playback.on_request(d, { playlist = "music" }))
  local r = apply(d, streaming.on_random_start(d, { playlist = "music" }))
  assert_eq(sent(r, "play_preset"), string.char(171)); assert_eq(device.effective_volume(d, 40), 0)
end
local function shuffled(d)
  begin(d); track(d, "First")
  local r = event(d, { type = "spotify.playing", now = 1 })
  assert_eq(sent(r, "set_shuffle"), "1"); assert_nil(sent(r, "next"))
  r = event(d, { type = "spotify.set_cfg", shuffle_mode = true })
  assert_eq(sent(r, "next"), "")
end

describe("Spotify random music start", function()
  it("waits for the matching speaker mute reply before loading the first song", function()
    local d = doc(); d.device = { volume_api = 2 }; d.volume_int = {}
    apply(d, playback.on_request(d, { playlist = "music" }))
    apply(d, device.on_volume_sent(d, { percent = 40 }))
    local r = apply(d, streaming.on_random_start(d, { playlist = "music" }))
    assert_nil(sent(r, "play_preset")); assert_eq(d.streaming_int.random_start.phase, "muting")
    apply(d, device.on_volume_sent(d, { percent = 0 }))
    r = apply(d, device.on_volume_ack(d, { result = 0 }))
    assert_nil(streaming.on_volume_confirmed(d, r.commands[1].event))
    r = apply(d, device.on_volume_ack(d, { result = 0 }))
    r = apply(d, streaming.on_volume_confirmed(d, r.commands[1].event))
    assert_eq(sent(r, "play_preset"), string.char(171))
  end)
  it("keeps sound muted through restricted metadata until the new song has a fresh position", function()
    local d = doc(); shuffled(d)
    event(d, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:music", track = "Random", restricted = true } })
    event(d, { type = "spotify.position", ms = 0, now = 3 }); assert_eq(device.effective_volume(d, 40), 0)
    event(d, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:music", track = "Random" } })
    assert_eq(device.effective_volume(d, 40), 0)
    event(d, { type = "spotify.position", ms = 0, now = 4 }); assert_eq(device.effective_volume(d, 40), 40)
  end)

  it("starts ordinary playlists reliably without a repeated playing notification", function()
    local d = doc(); d.audiocfg.random_start = false
    apply(d, playback.on_request(d, { playlist = "music", restart = true }))
    assert_nil(track(d, "Previous", "spotify:playlist:previous"))
    assert_eq(d.playback.now.playlist, "music")
    track(d, "First"); event(d, { type = "spotify.position", ms = 1200, now = 2 })
    assert_eq(d.playback.state, "playing"); assert_eq(d.playback.now.playlist, "music")
  end)

  it("ignores stale metadata from the previous playlist while the requested one loads", function()
    local d = doc(); begin(d)
    local r = track(d, "Previous", "spotify:playlist:previous")
    assert_nil(r); assert_eq(d.playback.now.playlist, "music")
    assert_eq(d.streaming_int.random_start.phase, "loading")
    track(d, "First"); event(d, { type = "spotify.playing", now = 2 })
    assert_eq(d.streaming_int.random_start.phase, "shuffle")
  end)
  it("accepts genuine position reports when an already playing context has no new playing event", function()
    local d = doc(); begin(d); track(d, "First")
    local r = event(d, { type = "spotify.position", ms = 1100, now = 3 })
    assert_eq(sent(r, "set_shuffle"), "1"); assert_eq(d.playback.state, "playing")
  end)
  it("waits for unrestricted metadata and skips chapter titles without changing saved volume", function()
    local d = doc(); begin(d)
    event(d, { type = "spotify.now_playing", data = { source_uri = "spotify:playlist:music", track = "First", restricted = true } })
    assert_nil(sent(event(d, { type = "spotify.playing", now = 2 }), "set_shuffle"))
    assert_eq(sent(track(d, "First"), "set_shuffle"), "1")
    for _, title in ipairs({ "Kapitel 01: Story", "Chapter 2 - Book" }) do
      d = doc(); begin(d); local r = track(d, title)
      assert_nil(d.streaming_int.random_start); assert_nil(sent(r, "next")); assert_eq(d.audiocfg.volume, 40)
    end
  end)
  it("recovers a missing same-value shuffle callback through a bounded transition", function()
    local d = doc(); begin(d); track(d, "First"); event(d, { type = "spotify.playing", now = 2 })
    assert_eq(sent(apply(d, streaming.on_random_probe(d)), "set_shuffle"), "0")
    assert_eq(sent(event(d, { type = "spotify.set_cfg", shuffle_mode = false }), "set_shuffle"), "1")
    assert_eq(sent(event(d, { type = "spotify.set_cfg", shuffle_mode = true }), "next"), "")
    assert_nil(streaming.on_random_probe(d))
    d = doc(); begin(d); track(d, "First"); event(d, { type = "spotify.playing", now = 2 })
    apply(d, streaming.on_random_probe(d))
    assert_eq(sent(apply(d, streaming.on_random_probe(d)), "set_shuffle"), "1")
    assert_nil(streaming.on_random_probe(d))
  end)
  it("releases startup silence immediately when the setting is disabled", function()
    local d = doc(); begin(d); d.audiocfg.random_start = false
    apply(d, streaming.on_random_config(d)); assert_nil(d.streaming_int.random_start)
    assert_eq(device.effective_volume(d, 40), 40)
    local r = streaming.on_random_start(d, { playlist = "music" })
    assert_eq(sent(r, "play_preset"), string.char(171))
  end)

  it("waits for playing and a confirmed shuffle before one random next, then restores ordered playback and volume", function()
    local d = doc(); shuffled(d)
    assert_nil(sent(event(d, { type = "spotify.set_cfg", shuffle_mode = true }), "next"))
    assert_nil(sent(track(d, "First"), "set_shuffle"))
    local r = track(d, "Random")
    assert_eq(sent(r, "set_shuffle"), "0"); assert_nil(d.streaming_int.random_start)
    assert_eq(device.effective_volume(d, 40), 40)
    assert_nil(sent(track(d, "Later"), "next"))
  end)
  it("accepts playing before metadata and keeps shuffle when configured", function()
    local d = doc(); d.audiocfg.shuffle_mode = true; begin(d)
    assert_nil(sent(event(d, { type = "spotify.playing", now = 1 }), "set_shuffle"))
    assert_eq(sent(track(d, "First"), "set_shuffle"), "1")
    event(d, { type = "spotify.set_cfg", shuffle_mode = true })
    assert_eq(sent(track(d, "Random"), "set_shuffle"), "1")
  end)
  it("ignores false/early confirmations and recovers the original volume on timeout or a single-song context", function()
    local d = doc(); begin(d)
    assert_nil(sent(event(d, { type = "spotify.set_cfg", shuffle_mode = true }), "next"))
    track(d, "First"); event(d, { type = "spotify.playing", now = 1 })
    assert_nil(sent(event(d, { type = "spotify.set_cfg", shuffle_mode = false }), "next"))
    local r = apply(d, streaming.on_random_timer(d))
    assert_eq(sent(r, "set_shuffle"), "0"); assert_eq(device.effective_volume(d, 40), 40)
    d = doc(); shuffled(d); track(d, "First"); apply(d, streaming.on_random_timer(d))
    assert_eq(device.effective_volume(d, 40), 40)
  end)
  it("cancels on errors, logout or another context without shuffling the phone's new choice", function()
    for _, kind in ipairs({ "spotify.play_error", "spotify.logout", "spotify.login_required" }) do
      local d = doc(); shuffled(d); event(d, { type = kind })
      assert_nil(d.streaming_int.random_start); assert_eq(device.effective_volume(d, 40), 40)
    end
    local d = doc(); shuffled(d)
    assert_nil(sent(track(d, "Phone", "spotify:playlist:other"), "set_shuffle"))
    assert_nil(d.streaming_int.random_start)
    d = doc(); begin(d); d.playback.now = { service = "FILE", playlist = "local" }
    apply(d, streaming.on_random_changed(d)); assert_nil(d.streaming_int.random_start)
  end)
  it("never randomises books, saved chapters, podcasts, albums or a playlist explicitly switched off", function()
    for _, change in ipairs({ { audiobook = true }, { resume = true }, { random_start = false },
      { spotify = { uri = "spotify:show:book", preset = "AB" } }, { spotify = { uri = "spotify:album:book", preset = "AB" } } }) do
      local d = doc(); local p = d.library.playlists.music
      for k, v in pairs(change) do p[k] = v end
      assert_false(streaming.wants_random(d, p))
      local normal = streaming.on_random_start(d, { playlist = "music" })
      assert_nil(normal.state); assert_nil(sent(normal, "next"))
      local _, commands = streaming.start(d, "music", p)
      for _, c in ipairs(commands) do assert_false(c.event and c.event.type == "streaming.random_start") end
    end
  end)
  it("continues a paused token but permits an explicit fresh playlist start", function()
    local d = doc(); shuffled(d); track(d, "Random")
    event(d, { type = "spotify.paused", now = 2 })
    local r = playback.on_request(d, { playlist = "music" })
    assert_eq(sent(r, "cont"), "")
    r = playback.on_request(d, { playlist = "music", restart = true })
    assert_eq(r.commands[1].event.type, "streaming.random_start")
  end)
end)


describe("Spotify resume status", function()
  it("starts the saved place directly when another context is already active after a core restart", function()
    local d = doc(); local p = d.library.playlists.music; p.resume = true
    d.spotify.active = false; d.spotify.track = { source_uri="spotify:playlist:other" }
    event(d, { type="spotify.status", active=true })
    local _, cmds = streaming.start(d, "music", p)
    assert_eq(sent({commands=cmds}, "play_preset"), string.char(171))
    assert_nil(sent({commands=cmds}, "cont"))
    d.spotify.track.source_uri = p.spotify.uri
    _, cmds = streaming.start(d, "music", p)
    assert_eq(sent({commands=cmds}, "cont"), "")
  end)
  it("preserves phone continuation when the native controller says the Jooki is inactive", function()
    local d = doc(); local p = d.library.playlists.music; p.resume=true
    d.spotify.track = {source_uri="spotify:playlist:other"}
    event(d,{type="spotify.status",active=false})
    local _,cmds=streaming.start(d,"music",p)
    assert_eq(sent({commands=cmds},"cont"),"")
  end)
end)
