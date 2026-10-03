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

-- Assertion rule: the commands of a handler are a set, unless their order is a rule of the player
-- itself -- "stop" before "play", "seek" before "cont" (or the engine plays the old position for an
-- instant). Those keep a positional assert; everything else uses `same` (whole set, any order) or `has` (one topic).
local function sorted(list) local out = {} for i, v in ipairs(list) do out[i] = v end table.sort(out) return out end
local function same(r, expected) assert_eq(sorted(topics(r)), sorted(expected)) end
local function has(r, s) for _, t in ipairs(topics(r)) do if t == s then return true end end return false end

local function apply(doc, r)
  for k, v in pairs(r.state or {}) do doc[k] = v end
  return doc
end

describe("services.playback — starting a playlist", function()
  it("plays track 1 of a music playlist, stopping what was playing", function()
    local doc = doc_with()
    local r = playback.on_request(doc, { playlist = "music", now = 10 })
    same(r, { "play 7\tfile:///d/uploads/a", "emit playback.changed starting" })
    assert_eq(r.state.playback.state, "starting")
    assert_eq(r.state.playback.now.title, "Chapter a"); assert_true(r.state.playback.now.has_next); assert_false(r.state.playback.now.has_prev)
    apply(doc, r)
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    r = playback.on_request(doc, { playlist = "music", index = 3, now = 12 })
    assert_eq(topics(r)[1], "stop 7"); assert_eq(topics(r)[2], "play 7\tfile:///d/uploads/c")   -- stop before play: order matters
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

  it("boot: an idle machine and a seed from the clock", function()
    local r = playback.on_boot(doc_with(), { wall = 1700000000, now = 5 })
    assert_eq(r.state.playback, { state = "idle" }); assert_eq(r.state.playback_int.seed, 1700000000)
    assert_eq(r.state.playback_int.last, {}); assert_eq(r.state.playback_int.shuffle, {})
  end)
end)

describe("services.playback — pause and continue", function()
  it("pause rules: short pause continues, long pause 15 s back, sleep-timer pause 60 s back", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "book", index = 1 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 200000 }))
    apply(doc, playback.on_pause(doc, { source = "token", now = 100 }))
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }))
    assert_eq(topics(playback.on_resume(doc, { now = 130 })), { "cont 7" })
    local r = playback.on_resume(doc, { now = 170 })
    assert_eq(topics(r)[1], "seek 7\t185000")   -- seek before cont: order matters
    apply(doc, r)
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_pause(doc, { source = "sleep_timer", now = 200 }))
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }))
    assert_eq(doc.resume.book.t, true)
    r = playback.on_resume(doc, { now = 201 })
    assert_eq(topics(r)[1], "seek 7\t140000")   -- seek before cont: order matters
  end)
end)

describe("services.playback — transport and end of track", function()
  it("next / prev, prev restarts after 5 s, forced works while paused", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", index = 2 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 9000 }))
    assert_true(has(playback.on_prev(doc, {}), "seek 7\t1"))
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
    assert_eq(r.state.playback.now.index, 2); assert_true(has(r, "play 7\tfile:///d/uploads/b"))
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

describe("services.playback — what a streaming daemon reports (the one door to state.playback)", function()
  it("a takeover stops the local music that plays, clears the pause, and says the state changed", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    assert_true(playback.local_busy(doc))
    local r = playback.on_external(doc, { service = "SPOTIFY", takeover = true, now = { service = "SPOTIFY", title = "X" }, state = "playing", position_ms = 0 })
    assert_eq(topics(r), { "stop 7", "emit playback.changed playing" })   -- stop before the word goes round: order matters
    assert_eq(r.state.playback.now.title, "X"); assert_eq(r.state.playback.position_ms, 0); assert_nil(r.state.playback.paused_by)
    assert_nil(r.state.playback_int)                                       -- the bookkeeping is the local machine's
    apply(doc, r)
    assert_false(playback.local_busy(doc) == true)
    r = playback.on_external(doc, { service = "SPOTIFY", takeover = true, now = { service = "SPOTIFY" }, state = "idle" })
    assert_eq(topics(r), { "emit playback.changed idle" })                 -- nothing local to stop
  end)

  it("a track, a position or a uri alone change the state silently; clear empties it", function()
    local doc = doc_with({ playback = { state = "playing", now = { service = "DEEZER", playlist = "dz" } } })
    local r = playback.on_external(doc, { service = "DEEZER", position_ms = 4200 })
    assert_eq(r.state.playback.position_ms, 4200); assert_nil(r.commands)
    r = playback.on_external(doc, { service = "DEEZER", uri = "dzmedia:///track/1" })
    assert_eq(r.state.playback.now.uri, "dzmedia:///track/1"); assert_eq(r.state.playback.now.playlist, "dz"); assert_nil(r.commands)
    r = playback.on_external(doc, { service = "DEEZER", clear = true, state = "idle" })
    assert_nil(r.state.playback.now); assert_eq(topics(r), { "emit playback.changed idle" })
    assert_eq(playback.on_external({}, { service = "SPOTIFY", now = { service = "SPOTIFY" } }).state.playback.state, "idle")
  end)
end)
