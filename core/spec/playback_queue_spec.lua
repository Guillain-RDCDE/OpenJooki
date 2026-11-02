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
    audiocfg = { shuffle_mode = opts.shuffle or false, repeat_mode = 0 },
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

  it("index_of: where a track sits in the queue", function()
    assert_eq(queue.index_of({ 3, 1, 2 }, 1), 2); assert_eq(queue.index_of({ 3, 1, 2 }, 3), 1)
    assert_nil(queue.index_of({ 3, 1, 2 }, 4))
  end)
end)
