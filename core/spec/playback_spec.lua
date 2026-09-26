local playback = require("services.playback")

local function doc_with(opts)
  opts = opts or {}
  local tracks = {}
  for _, id in ipairs({ "a", "b", "c" }) do tracks[id] = { title = "Chapter " .. id, filename = "/d/uploads/" .. id, duration = 100, album = "Book", artist = "Reader" } end
  tracks.radio = { title = "FIP", filename = "http://fip", isUrl = true }
  local doc = {
    config = { data_dir = "/d", system_dir = "/sys" },
    library = { playlists = { book = { title = "Book", tracks = { "a", "b", "c" }, audiobook = opts.audiobook ~= false },
                              music = { title = "Songs", tracks = { "a", "b", "c" } },
                              live = { title = "Radio", tracks = { "radio" } },
                              empty = { title = "Empty", tracks = {} } }, tracks = tracks, tokens = {} },
    audiocfg = { shuffle_mode = opts.shuffle or false, repeat_mode = opts.repeat_mode or 0 },
    resume = opts.resume or {},
    system = { tracks = { ["Evt.Jooki.Ready"] = { filename = "assets/ready.ogg" } } },
    playback = opts.playback,
  }
  return doc
end

local function topics(r)
  local out = {}
  for _, c in ipairs(r.commands or {}) do
    if c.kind == "bus.publish" then out[#out + 1] = c.topic:gsub("^/j/audio/out/", "") .. " " .. c.payload
    elseif c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type .. (c.event.name and (" " .. c.event.name) or "") .. (c.event.state and (" " .. c.event.state) or "")
    elseif c.kind == "files.write" then out[#out + 1] = "write " .. c.path
    elseif c.kind == "log" then out[#out + 1] = "log " .. c.key end
  end
  return out
end

local function apply(doc, r)
  for k, v in pairs(r.state or {}) do doc[k] = v end
  return doc
end

describe("services.playback — starting a playlist", function()
  it("plays track 1 of a music playlist, stopping what was playing", function()
    local doc = doc_with()
    local r = playback.on_request(doc, { playlist = "music", now = 10 })
    assert_eq(topics(r), { "play 7\tfile:///d/uploads/a", "emit playback.changed starting" })
    assert_eq(r.state.playback.state, "starting")
    assert_eq(r.state.playback.now.title, "Chapter a"); assert_true(r.state.playback.now.has_next); assert_false(r.state.playback.now.has_prev)
    apply(doc, r)
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    r = playback.on_request(doc, { playlist = "music", index = 3, now = 12 })
    assert_eq(topics(r)[1], "stop 7"); assert_eq(topics(r)[2], "play 7\tfile:///d/uploads/c")
  end)

  it("an empty playlist plays nothing and raises the 'empty' event; unknown playlist only logs", function()
    local doc = doc_with()
    assert_eq(topics(playback.on_request(doc, { playlist = "empty" })), { "emit system.event Evt.Character.Detect.Empty" })
    assert_eq(topics(playback.on_request(doc, { playlist = "nope" })), { "log playback.request_failed" })
  end)

  it("the same token put back: playing -> ignored, paused -> continues", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", now = 1 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    assert_eq(topics(playback.on_request(doc, { playlist = "music", now = 2 })), {})
    apply(doc, playback.on_pause(doc, { source = "token", now = 3 }))
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }))
    assert_eq(topics(playback.on_request(doc, { playlist = "music", now = 4 })), { "cont 7" })
  end)

  it("remembers the last track of a music playlist while on", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", index = 2 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.stopped", id = 7 }))
    local r = playback.on_request(doc, { playlist = "music" })
    assert_eq(r.state.playback.now.index, 2)
  end)

  it("shuffle: a memoised order, never for audiobooks", function()
    local doc = doc_with({ shuffle = true })
    local r = playback.on_request(doc, { playlist = "music" })
    local order = r.state.playback.shuffle.music
    assert_eq(#order, 3)
    assert_nil(r.state.playback.shuffle.book)
    apply(doc, r)
    local r2 = playback.on_request(doc, { playlist = "book" })
    assert_eq(r2.state.playback.now.index, 1)
    assert_nil(r2.state.playback.shuffle.book)
  end)
end)

describe("services.playback — audiobook resume", function()
  it("resumes at the saved chapter, 15 s back, seeking once the engine plays", function()
    local doc = doc_with({ resume = { book = { id = "b", pos = 125000 } } })
    local r = playback.on_request(doc, { playlist = "book" })
    assert_eq(r.state.playback.now.index, 2)
    assert_eq(r.state.playback.resume_ms, 110000)
    apply(doc, r)
    r = playback.on_audio(doc, { type = "audio.playing", id = 7 })
    assert_eq(topics(r)[1], "seek 7\t110000")
    assert_nil(r.state.playback.resume_ms)
    assert_eq(r.state.playback.position_ms, 110000)
  end)

  it("near the chapter start it starts the chapter; after the timer it goes 60 s back", function()
    local doc = doc_with({ resume = { book = { id = "b", pos = 12000 } } })
    local r = playback.on_request(doc, { playlist = "book" })
    assert_eq(r.state.playback.now.index, 2); assert_nil(r.state.playback.resume_ms)
    doc = doc_with({ resume = { book = { id = "c", pos = 200000, t = true } } })
    r = playback.on_request(doc, { playlist = "book" })
    assert_eq(r.state.playback.resume_ms, 140000)
  end)

  it("saves the position on pause, stop and end of chapter; the end of the book goes back to chapter 1", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "book", index = 2 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 40000 }))
    assert_eq(doc.resume.book, { id = "b", pos = 40000 })
    assert_true(doc.playback.resume_dirty)
    apply(doc, playback.on_pause(doc, { source = "token", now = 50 }))
    local r = playback.on_audio(doc, { type = "audio.paused", id = 7 })
    assert_eq(topics(r)[#topics(r)], "write /d/resume.json")
    apply(doc, r)
    apply(doc, playback.on_audio(doc, { type = "audio.ended", id = 7 }))
    assert_eq(doc.resume.book, { id = "c", pos = 0 })
    assert_eq(doc.playback.now.index, 3)   -- next chapter started
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.ended", id = 7 }))
    assert_nil(doc.resume.book)
    assert_eq(doc.playback.state, "ended")
  end)

  it("pause rules: short pause continues, long pause 15 s back, sleep-timer pause 60 s back", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "book", index = 1 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 200000 }))
    apply(doc, playback.on_pause(doc, { source = "token", now = 100 }))
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }))
    assert_eq(topics(playback.on_resume(doc, { now = 130 })), { "cont 7" })
    local r = playback.on_resume(doc, { now = 170 })
    assert_eq(topics(r)[1], "seek 7\t185000")
    apply(doc, r)
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_pause(doc, { source = "sleep_timer", now = 200 }))
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }))
    assert_eq(doc.resume.book.t, true)
    r = playback.on_resume(doc, { now = 201 })
    assert_eq(topics(r)[1], "seek 7\t140000")
  end)

  it("resume_reset forgets a book's position; the save timer flushes dirty positions", function()
    local doc = doc_with({ resume = { book = { id = "b", pos = 5 } } })
    local r = playback.on_resume_reset(doc, "book")
    assert_eq(r.state.resume, {}); assert_eq(topics(r), { "write /d/resume.json" })
    doc.playback = { state = "playing", resume_dirty = true, last = {}, shuffle = {} }
    r = playback.on_timer(doc, { name = "playback.save" })
    assert_eq(topics(r), { "write /d/resume.json" })
    assert_nil(playback.on_timer(doc, { name = "other" }))
  end)
end)

describe("services.playback — transport and end of track", function()
  it("next / prev, prev restarts after 5 s, forced works while paused", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", index = 2 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 9000 }))
    assert_eq(topics(playback.on_prev(doc, {}))[1], "seek 7\t1")
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 2000 }))
    local r = playback.on_prev(doc, {})
    assert_eq(r.state.playback.now.index, 1)
    apply(doc, playback.on_pause(doc, { source = "page", now = 1 }))
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }))
    assert_nil(playback.on_next(doc, {}))
    assert_eq(playback.on_next(doc, { forced = true }).state.playback.now.index, 3)
  end)

  it("end of track: next track, repeat-all wraps, repeat-one replays, no repeat stops", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", index = 3 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    local r = playback.on_audio(doc, { type = "audio.ended", id = 7 })
    assert_eq(r.state.playback.state, "ended")
    doc = doc_with({ repeat_mode = 1 })
    apply(doc, playback.on_request(doc, { playlist = "music", index = 3 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    r = playback.on_audio(doc, { type = "audio.ended", id = 7 })
    assert_eq(r.state.playback.now.index, 1); assert_eq(r.state.playback.state, "starting")
    doc = doc_with({ repeat_mode = 2 })
    apply(doc, playback.on_request(doc, { playlist = "music", index = 2 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    r = playback.on_audio(doc, { type = "audio.ended", id = 7 })
    assert_eq(r.state.playback.now.index, 2); assert_eq(topics(r)[1], "play 7\tfile:///d/uploads/b")
  end)

  it("streams pause by stopping and cannot seek", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "live" }))
    assert_eq(doc.playback.now.service, "STREAM"); assert_eq(doc.playback.now.uri, "http://fip")
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    assert_eq(topics(playback.on_pause(doc, { source = "page" })), { "stop 7" })
    assert_nil(playback.on_seek(doc, { ms = 5 }))
  end)

  it("ignores engine events for the wrong stream and out-of-state ones", function()
    local doc = doc_with()
    assert_nil(playback.on_audio(doc, { type = "audio.playing", id = 9 }))
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    assert_nil(playback.on_audio(doc, { type = "audio.paused", id = 7 }))   -- paused while starting: ignored
  end)
end)

describe("services.playback — system sounds", function()
  it("pauses the music, plays the sound on stream 3, then continues the music and runs `after`", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    local r = playback.on_system_event(doc, { name = "Evt.Jooki.Ready", after = { type = "shutdown.request" } })
    assert_eq(topics(r), { "emit lights.event Evt.Jooki.Ready", "pauz 7", "play 3\tfile:///sys/assets/ready.ogg" })
    apply(doc, r)
    r = playback.on_audio(doc, { type = "audio.ended", id = 3 })
    assert_eq(topics(r), { "cont 7", "emit shutdown.request" })
    assert_nil(r.state.playback.sys)
  end)

  it("an event without a sound only lights up and runs `after` at once", function()
    local doc = doc_with()
    local r = playback.on_system_event(doc, { name = "Evt.Character.Detect", after = { type = "x" } })
    assert_eq(topics(r), { "emit lights.event Evt.Character.Detect", "emit x" })
  end)
end)
