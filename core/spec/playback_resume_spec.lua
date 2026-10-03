local resume = require("services.playback.resume")
local playback = require("services.playback")

local function doc_with(opts)
  opts = opts or {}
  local tracks = {}
  for _, id in ipairs({ "a", "b", "c" }) do tracks[id] = { title = "Chapter " .. id, filename = "/d/uploads/" .. id, duration = 100, album = "Book", artist = "Reader" } end
  local doc = {
    config = { data_dir = "/d", system_dir = "/sys" },
    library = { playlists = { book = { title = "Book", tracks = { "a", "b", "c" }, audiobook = true },
                              music = { title = "Songs", tracks = { "a", "b", "c" } } }, tracks = tracks, tokens = {} },
    audiocfg = { shuffle_mode = false, repeat_mode = 0 },
    resume = opts.resume or {},
    system = { tracks = {} },
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
    elseif c.kind == "timer.every" then out[#out + 1] = "timer " .. c.name end
  end
  return out
end
-- Assertion rule: the commands of a handler are a set; `has` looks for one topic, `topics` is compared
-- whole only where there is a single command.
local function has(r, s) for _, t in ipairs(topics(r)) do if t == s then return true end end return false end

local function apply(doc, r)
  for k, v in pairs(r.state or {}) do doc[k] = v end
  return doc
end

describe("services.playback.resume — audiobook resume (1.3 rules)", function()
  it("resumes at the saved chapter, 15 s back, seeking once the engine plays", function()
    local doc = doc_with({ resume = { book = { id = "b", pos = 125000 } } })
    local r = playback.on_request(doc, { playlist = "book" })
    assert_eq(r.state.playback.now.index, 2)
    assert_eq(r.state.playback.resume_ms, 110000)
    apply(doc, r)
    r = playback.on_audio(doc, { type = "audio.playing", id = 7 })
    assert_true(has(r, "seek 7\t110000"))
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

  it("resume_for: the rule on its own (unknown chapter or no entry: nothing)", function()
    local tracks = { "a", "b", "c" }
    assert_eq({ resume.resume_for({ book = { id = "b", pos = 125000 } }, "book", tracks) }, { 2, 110000 })
    assert_eq({ resume.resume_for({ book = { id = "b", pos = 125000, t = true } }, "book", tracks) }, { 2, 65000 })
    assert_eq({ resume.resume_for({ book = { id = "a", pos = 19000 } }, "book", tracks) }, { 1 })   -- less than 5 s left after the rewind
    assert_nil(resume.resume_for({ book = { id = "z", pos = 1 } }, "book", tracks))
    assert_nil(resume.resume_for({}, "book", tracks)); assert_nil(resume.resume_for(nil, "book", tracks))
  end)

  it("saves the position on pause, stop and end of chapter; the end of the book goes back to chapter 1", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "book", index = 2 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 40000 }))
    assert_eq(doc.resume.book, { id = "b", pos = 40000 })
    assert_true(doc.playback_int.resume_dirty); assert_nil(doc.playback.resume_dirty)
    apply(doc, playback.on_pause(doc, { source = "token", now = 50 }))
    local r = playback.on_audio(doc, { type = "audio.paused", id = 7 })
    assert_true(has(r, "write /d/resume.json"))
    apply(doc, r)
    apply(doc, playback.on_audio(doc, { type = "audio.ended", id = 7 }))
    assert_eq(doc.resume.book, { id = "c", pos = 0 })
    assert_eq(doc.playback.now.index, 3)   -- next chapter started
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.ended", id = 7 }))
    assert_nil(doc.resume.book)
    assert_eq(doc.playback.state, "ended")
  end)

  it("a stop saves the position too; music (not an audiobook) is never noted", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "book", index = 1 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 30000 }))
    local r = playback.on_audio(doc, { type = "audio.stopped", id = 7 })
    assert_true(has(r, "write /d/resume.json")); assert_eq(r.state.resume.book, { id = "a", pos = 30000 })
    doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", index = 1 }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 30000 }))
    assert_eq(doc.resume, {}); assert_nil(doc.playback_int.resume_dirty)
    assert_false(has(playback.on_audio(doc, { type = "audio.stopped", id = 7 }), "write /d/resume.json"))
  end)

  it("resume_reset forgets a book's position; the save timer flushes dirty positions", function()
    local doc = doc_with({ resume = { book = { id = "b", pos = 5 } } })
    local r = resume.on_resume_reset(doc, "book")
    assert_eq(r.state.resume, {}); assert_eq(topics(r), { "write /d/resume.json" })
    doc.playback = { state = "playing" }; doc.playback_int = { resume_dirty = true, last = {}, shuffle = {} }
    r = resume.on_timer(doc, { name = "playback.save" })
    assert_eq(topics(r), { "write /d/resume.json" }); assert_nil(r.state.playback_int.resume_dirty)
    assert_nil(resume.on_timer(doc, { name = "other" }))
    assert_eq(topics(playback.on_timer(doc, { name = "playback.save" })), { "write /d/resume.json" })   -- the facade routes it too
    doc.playback_int.resume_dirty = nil
    assert_nil(resume.on_save(doc))
  end)

  it("shutdown flushes a dirty position, and nothing otherwise", function()
    local doc = doc_with({ resume = { book = { id = "b", pos = 5 } } })
    doc.playback = { state = "playing" }; doc.playback_int = { resume_dirty = true, last = {}, shuffle = {} }
    assert_eq(topics(resume.on_shutdown(doc)), { "write /d/resume.json" })
    doc.playback_int.resume_dirty = nil
    assert_nil(resume.on_shutdown(doc))
  end)

  it("boot: resume.json entries checked, the save timer scheduled", function()
    local r = resume.on_boot(doc_with(), { resume = { book = { id = "b", pos = "125000", t = true }, bad = { pos = 3 }, worse = "x", music = { id = "a" } } })
    assert_eq(r.state.resume, { book = { id = "b", pos = 125000, t = true }, music = { id = "a", pos = 0 } })
    assert_eq(topics(r), { "timer playback.save" })
    assert_eq(resume.on_boot(doc_with(), {}).state.resume, {})
  end)
end)
