local queue = require("services.playback.queue")
local playback = require("services.playback")

local function doc_with(opts)
  opts = opts or {}
  local tracks = {}
  for _, id in ipairs({ "a", "b", "c" }) do tracks[id] = { title = "Chapter " .. id, filename = "/d/uploads/" .. id, duration = 100 } end
  return {
    config = { data_dir = "/d", system_dir = "/sys" },
    library = { playlists = { book = { title = "Book", tracks = { "a", "b", "c" }, audiobook = true },
                              music = { title = "Songs", tracks = { "a", "b", "c" } } }, tracks = tracks, tokens = {} },
    audiocfg = { shuffle_mode = opts.shuffle or false, random_start = opts.random_start or false, repeat_mode = 0 },
    resume = {}, system = { tracks = {} },
  }
end
local function apply(doc, r)
  for k, v in pairs(r.state or {}) do doc[k] = v end
  return doc
end

describe("services.playback.queue — the order of a playlist", function()
  it("shuffle: a memoised order, never for audiobooks", function()
    local doc = doc_with({ shuffle = true })
    local r = playback.on_request(doc, { playlist = "music" })
    local order = r.state.playback_int.shuffle.music     -- the order is the player's own business: never published
    assert_eq(#order, 3)
    assert_nil(r.state.playback_int.shuffle.book); assert_nil(r.state.playback.shuffle)
    apply(doc, r)
    local r2 = playback.on_request(doc, { playlist = "book" })
    assert_eq(r2.state.playback.now.index, 1)
    assert_nil(r2.state.playback_int.shuffle.book)
    assert_eq(r2.state.playback_int.shuffle.music, order)   -- what was memoised stays
  end)

  it("identity without shuffle (and always for an audiobook); a shuffle is a permutation kept per playlist", function()
    local doc = doc_with()
    local p = doc.library.playlists.music
    local pb = { shuffle = {}, seed = 12345 }
    assert_eq(queue.queue_for(doc, pb, "music", p), { 1, 2, 3 }); assert_nil(pb.shuffle.music)
    doc.audiocfg.shuffle_mode = true
    assert_eq(queue.queue_for(doc, pb, "book", doc.library.playlists.book), { 1, 2, 3 })
    local q = queue.queue_for(doc, pb, "music", p)
    local seen = {}
    for _, i in ipairs(q) do seen[i] = true end
    assert_eq(seen, { true, true, true }); assert_eq(pb.shuffle.music, q)
    assert_eq(queue.queue_for(doc, pb, "music", p), q)                     -- memoised
    p.tracks = { "a", "b" }                                                -- the playlist changed: drawn again
    assert_eq(#queue.queue_for(doc, pb, "music", p), 2)
    -- two seeds, two orders (the seed is the clock at boot)
    local six = { title = "Six", tracks = { "a", "b", "c", "d", "e", "f" } }
    local orders = {}
    for seed = 1, 8 do orders[table.concat(queue.queue_for(doc, { shuffle = {}, seed = seed * 1000 }, "six", six), ",")] = true end
    local n = 0
    for _ in pairs(orders) do n = n + 1 end
    assert_true(n > 1)
  end)

  it("shuffle: a token starts its playlist on a new order, from its first song; put back, it goes on (#22)", function()
    local doc = doc_with({ shuffle = true })
    local ids = {}
    for i = 1, 8 do ids[i] = "t" .. i; doc.library.tracks["t" .. i] = { title = "Song " .. i, filename = "/d/uploads/t" .. i, duration = 100 } end
    doc.library.playlists.big = { title = "Big", tracks = ids }
    doc.playback_int = { last = {}, shuffle = {}, seed = 42 }
    local firsts = {}
    for k = 1, 12 do
      local r = playback.on_request(doc, { playlist = "big", now = 100 + k })
      local now = r.state.playback.now
      assert_eq(now.queue_pos, 1); assert_eq(now.index, r.state.playback_int.shuffle.big[1])
      firsts[now.index] = true
      apply(doc, r)
      apply(doc, playback.on_request(doc, { playlist = "music", now = 200 + k }))   -- another token in between
    end
    local n = 0
    for _ in pairs(firsts) do n = n + 1 end
    assert_true(n > 2)                                                            -- not always the same first song
    -- the same token again while its playlist is on: the song goes on, nothing drawn again
    local r = playback.on_request(doc, { playlist = "big", now = 400 })
    apply(doc, r); apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    local index, order = doc.playback.now.index, doc.playback_int.shuffle.big
    local again = playback.on_request(doc, { playlist = "big", now = 401 })
    if again.state.playback_int then assert_eq(again.state.playback_int.shuffle.big, order) end
    assert_eq((again.state.playback or doc.playback).now.index, index)
    -- without shuffle, as before: the last song played of that playlist
    doc.audiocfg.shuffle_mode = false
    apply(doc, playback.on_request(doc, { playlist = "music", now = 500 }))
    assert_eq(playback.on_request(doc, { playlist = "big", now = 501 }).state.playback.now.index, index)
  end)

  it("a playlist's own shuffle wins over the Settings', both ways (#22)", function()
    local doc = doc_with()
    local music = doc.library.playlists.music
    assert_false((queue.modes(doc, music)))
    music.shuffle_mode = true
    local pb = { shuffle = {}, seed = 7 }
    assert_true((queue.modes(doc, music)))
    assert_eq(#queue.queue_for(doc, pb, "music", music), 3); assert_eq(pb.shuffle.music ~= nil, true)
    doc.audiocfg.shuffle_mode = true; music.shuffle_mode = false
    assert_eq(queue.queue_for(doc, { shuffle = {}, seed = 7 }, "music", music), { 1, 2, 3 })
    music.shuffle_mode = nil
    doc.audiocfg.repeat_mode = 2
    assert_eq(select(2, queue.modes(doc, music)), 2)
    music.repeat_mode = 0
    assert_eq(select(2, queue.modes(doc, music)), 0)
  end)

  it("random start without shuffle varies the first song and then follows playlist order", function()
    local doc = doc_with({ random_start = true })
    local p = doc.library.playlists.music
    for i = 4, 8 do
      p.tracks[i] = "t" .. i
      doc.library.tracks["t" .. i] = { filename = "/d/uploads/t" .. i }
    end
    doc.playback_int = { last = {}, shuffle = {}, seed = 42 }
    local seen = {}
    for k = 1, 32 do
      apply(doc, playback.on_request(doc, { playlist = "music", now = 100 + k }))
      local now = doc.playback.now
      seen[now.index] = true
      assert_eq(now.queue_pos, now.index)
      assert_nil(doc.playback_int.shuffle.music)
      apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
      local r = playback.on_next(doc, { now = 150 + k })
      if now.index < #p.tracks then
        assert_eq(r.state.playback.now.index, now.index + 1)
        assert_eq(r.state.playback_int.seed, doc.playback_int.seed)
      else
        assert_nil(r) -- repeat-off still stops at the end
      end
      apply(doc, playback.on_request(doc, { playlist = "book", now = 200 + k }))
    end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    assert_true(n > 4) -- includes both halves of an even-length playlist
  end)

  it("random start respects an explicit track, the current song and a paused token", function()
    local doc = doc_with({ random_start = true })
    doc.playback_int = { last = {}, shuffle = {}, seed = 42 }
    apply(doc, playback.on_request(doc, { playlist = "music", index = 2, now = 10 }))
    assert_eq(doc.playback.now.index, 2); assert_eq(doc.playback_int.seed, 42)
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_request(doc, { playlist = "music", now = 11 }))
    assert_eq(doc.playback.now.index, 2); assert_eq(doc.playback_int.seed, 42)
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }))
    local r = playback.on_request(doc, { playlist = "music", now = 12 })
    assert_eq(r.commands[1].topic, "/j/audio/out/cont")
    assert_eq(doc.playback.now.index, 2); assert_eq(doc.playback_int.seed, 42)
    apply(doc, playback.on_request(doc, { playlist = "music", index = 3, restart = true, now = 13 }))
    assert_eq(doc.playback.now.index, 3); assert_eq(doc.playback_int.seed, 42)
  end)

  it("random start draws again for a stopped, ended or explicitly restarted playlist", function()
    for _, state in ipairs({ "idle", "ended", "playing" }) do
      local doc = doc_with({ random_start = true })
      doc.playback_int = { last = {}, shuffle = {}, seed = 42 }
      local seen = {}
      for k = 1, 20 do
        apply(doc, playback.on_request(doc, { playlist = "music", restart = state == "playing", now = 100 + k }))
        seen[doc.playback.now.index] = true
        doc.playback.state = state
      end
      assert_true(seen[1] and seen[2] and seen[3], state)
    end
  end)

  it("random start combines with shuffle and respects repeat-all at the end", function()
    local doc = doc_with({ random_start = true, shuffle = true })
    apply(doc, playback.on_request(doc, { playlist = "music", now = 50 }))
    local order = doc.playback_int.shuffle.music
    assert_eq(doc.playback.now.index, order[1]); assert_eq(doc.playback.now.queue_pos, 1)
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    local r = playback.on_next(doc, { now = 51 })
    assert_eq(r.state.playback.now.index, order[2]); assert_eq(r.state.playback_int.shuffle.music, order)
    doc.audiocfg.shuffle_mode, doc.audiocfg.repeat_mode = false, 1
    apply(doc, playback.on_request(doc, { playlist = "music", index = 3, restart = true }))
    r = playback.on_next(doc, { forced = true, now = 52 })
    assert_eq(r.state.playback.now.index, 1)
  end)

  it("random start also varies the first song of short shuffled playlists", function()
    for n = 2, 3 do
      local doc = doc_with({ random_start = true, shuffle = true })
      if n == 2 then doc.library.playlists.music.tracks = { "a", "b" } end
      doc.playback_int = { last = {}, shuffle = {}, seed = 42 }
      local seen = {}
      for k = 1, 20 do
        apply(doc, playback.on_request(doc, { playlist = "music", now = 100 + k }))
        seen[doc.playback.now.index] = true
        assert_eq(doc.playback.now.queue_pos, 1)
        local order = doc.playback_int.shuffle.music
        local sorted = { unpack(order) }; table.sort(sorted)
        for i = 1, n do assert_eq(sorted[i], i) end
        apply(doc, playback.on_request(doc, { playlist = "book", now = 200 + k }))
      end
      for i = 1, n do assert_true(seen[i], "song " .. i .. " of " .. n) end
    end
  end)

  it("random start preserves audiobook resume and handles empty or single-song playlists", function()
    local doc = doc_with({ random_start = true })
    doc.resume = { book = { id = "b", pos = 45000 } }
    local r = playback.on_request(doc, { playlist = "book", now = 10 })
    assert_eq(r.state.playback.now.index, 2); assert_eq(r.state.playback.resume_ms, 30000)
    doc.library.playlists.one = { tracks = { "a" } }
    r = playback.on_request(doc, { playlist = "one", now = 11 })
    assert_eq(r.state.playback.now.index, 1)
    doc.library.playlists.empty = { tracks = {} }
    r = playback.on_request(doc, { playlist = "empty", now = 12 })
    assert_eq(r.commands[1].event.name, "Evt.Character.Detect.Empty")
  end)

  it("random start inherits Settings and honors a playlist's explicit off or on", function()
    local doc = doc_with({ random_start = true })
    local p = doc.library.playlists.music
    assert_true(select(3, queue.modes(doc, p)))
    p.random_start = false
    assert_false(select(3, queue.modes(doc, p)))
    doc.playback_int = { last = { music = 2 }, shuffle = {}, seed = 42 }
    assert_eq(playback.on_request(doc, { playlist = "music" }).state.playback.now.index, 2)
    doc.audiocfg.random_start, p.random_start = false, true
    assert_true(select(3, queue.modes(doc, p)))
    p.random_start = nil
    assert_false(select(3, queue.modes(doc, p)))
  end)

  it("index_of: where a track sits in the queue", function()
    assert_eq(queue.index_of({ 3, 1, 2 }, 1), 2); assert_eq(queue.index_of({ 3, 1, 2 }, 3), 1)
    assert_nil(queue.index_of({ 3, 1, 2 }, 4))
  end)
end)

describe("random first song", function()
  it("uses OS entropy even before the wall clock is set", function()
    local clock = require("adapters.clock")
    assert_eq(clock.seed(function() return "\1\2\3\4" end), 16909060)
    assert_eq(clock.seed(function() return "\0\0\0\0" end), 0)
    local a = playback.on_boot({}, { wall = 0, seed = 123 })
    local b = playback.on_boot({}, { wall = 0, seed = 456 })
    assert_eq(a.state.playback_int.seed, 123); assert_eq(b.state.playback_int.seed, 456)
  end)

  it("redraws on a fresh start of an ended playlist, retaining a valid permutation", function()
    local d = doc_with({ shuffle = true }); d.playback_int = { seed = 1001 }
    local seen = {}
    for i = 1, 30 do
      local r = playback.on_request(d, { playlist = "music", now = i })
      local p, order = r.state.playback, r.state.playback_int.shuffle.music
      assert_eq(p.now.index, order[1]); assert_eq(p.now.queue_pos, 1)
      local present = {}; for _, n in ipairs(order) do present[n] = true end
      assert_eq(present, { true, true, true }); seen[p.now.index] = true
      apply(d, r); d.playback.state = "ended"
    end
    assert_true(seen[1] and seen[2] and seen[3])
  end)

  it("honours explicit track choices, ordered playlists, audiobook resume and pause/resume", function()
    local d = doc_with({ shuffle = true }); d.playback_int = { seed = 9876 }
    local r = playback.on_request(d, { playlist = "music", index = 2, restart = true })
    assert_eq(r.state.playback.now.index, 2); apply(d, r)
    d.playback.state = "paused"; d.playback.position_ms = 18000
    r = playback.on_request(d, { playlist = "music" })
    assert_eq(r.state.playback.now.index, 2)
    d.library.playlists.music.shuffle_mode = false; d.playback = { state = "idle" }; d.playback_int.last = {}
    assert_eq(playback.on_request(d, { playlist = "music" }).state.playback.now.index, 1)
    d.resume.book = { id = "b", pos = 30000 }
    assert_eq(playback.on_request(d, { playlist = "book" }).state.playback.now.index, 2)
  end)
end)
