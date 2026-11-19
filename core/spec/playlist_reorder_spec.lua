-- Re-ordering a playlist while one of its songs plays (#46): the song keeps playing, so the
-- player's place in the list (index, queue position, last played, shuffle) follows it to its new
-- position instead of staying at the old number.
local playback = require("services.playback")
local v1 = require("api.v1")
local json = require("vendor.json")

local function doc_with(opts)
  opts = opts or {}
  local tracks = {}
  for _, id in ipairs({ "a", "b", "c", "d" }) do tracks[id] = { title = "Song " .. id, filename = "/d/uploads/" .. id, duration = 100 } end
  return {
    config = { data_dir = "/d", system_dir = "/sys" },
    library = { playlists = { music = { title = "Songs", tracks = { "a", "b", "c", "d" } } }, tracks = tracks, tokens = {} },
    audiocfg = { shuffle_mode = opts.shuffle or false, random_start = false, repeat_mode = 0 },
    resume = {}, system = { tracks = {} }, playback = { state = "idle" }, device = { id = "j" },
  }
end
local function apply(doc, r)
  for k, v in pairs(r.state or {}) do doc[k] = v end
  return doc
end
local function reorder(doc, order)
  local r = v1.on_cmd(doc, { type = "v1.cmd", name = "PLAYLIST_UPDATE", now = 5, wall = 1000,
    raw = json.encode({ playlist = { id = "music", tracks = order } }) })
  return apply(doc, r)
end

describe("PLAYLIST_UPDATE while the playlist plays (#46)", function()
  it("the playing song's index follows it to its new position", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", index = 2 }))   -- "b" plays
    assert_eq(doc.playback.now.track, "b")
    reorder(doc, { "b", "a", "c", "d" })                                      -- b moves to the top
    assert_eq(doc.playback.now.track, "b")
    assert_eq(doc.playback.now.index, 1)
    assert_eq(doc.playback.now.queue_pos, 1)
    assert_eq(doc.playback.now.has_prev, false)
    assert_eq(doc.playback.now.has_next, true)
    reorder(doc, { "a", "c", "d", "b" })                                      -- and to the bottom
    assert_eq(doc.playback.now.index, 4)
    assert_eq(doc.playback.now.has_next, false)
  end)

  it("another playlist's playback, or a playlist that is not playing, is left alone", function()
    local doc = doc_with()
    doc.library.playlists.other = { title = "Other", tracks = { "a", "b" } }
    apply(doc, playback.on_request(doc, { playlist = "other", index = 2 }))
    reorder(doc, { "d", "c", "b", "a" })
    assert_eq(doc.playback.now.playlist, "other")
    assert_eq(doc.playback.now.index, 2)
  end)

  it("the next song after a reorder is the one that now follows the playing one", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", index = 2 }))
    reorder(doc, { "c", "d", "b", "a" })                                      -- b is third, a follows
    local r = playback.on_request(doc, { playlist = "music", index = 4 })
    assert_eq(r.state.playback.now.track, "a")
  end)

  it("a shuffled queue keeps its order, in the songs' new positions", function()
    local doc = doc_with({ shuffle = true })
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    local before = {}
    for _, i in ipairs(doc.playback_int.shuffle.music) do before[#before + 1] = doc.library.playlists.music.tracks[i] end
    local playing = doc.playback.now.track
    reorder(doc, { "d", "c", "b", "a" })
    local after = {}
    for _, i in ipairs(doc.playback_int.shuffle.music) do after[#after + 1] = doc.library.playlists.music.tracks[i] end
    assert_eq(after, before)                                                  -- same songs, same order
    assert_eq(doc.playback.now.track, playing)
    assert_eq(doc.library.playlists.music.tracks[doc.playback.now.index], playing)
    assert_eq(doc.playback_int.shuffle.music[doc.playback.now.queue_pos], doc.playback.now.index)
  end)

  it("a removed playing song: the rest is renumbered and the song plays on", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music", index = 2 }))
    reorder(doc, { "a", "c", "d" })                                           -- b taken out
    assert_eq(doc.playback.now.track, "b")
    assert_eq(doc.playback.state, "starting")                                 -- untouched
  end)
end)
