local uploads = require("services.uploads")
local v1 = require("api.v1")
local json = require("vendor.json")

local function doc_with()
  return { config = { data_dir = "/d", scratch_dir = "/run" }, userMessages = {},
           library = { playlists = { p = { title = "P", tracks = {} } }, tracks = { ["0123456789abcdef"] = { title = "old", filename = "/d/uploads/0123456789abcdef" } }, tokens = {} },
           playback = { state = "idle" }, audiocfg = { volume = 40, shuffle_mode = false, repeat_mode = 1 }, device = { id = "j" } }
end
local function kinds(r)
  local out = {}
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type .. (c.event.messageType and " " .. c.event.messageType or "")
    elseif c.kind == "shell" then out[#out + 1] = "shell " .. c.action
    elseif c.kind == "files.remove" or c.kind == "files.rename" or c.kind == "files.read_text" or c.kind == "files.write" then out[#out + 1] = c.kind .. " " .. (c.path or c.from)
    elseif c.kind == "bus.publish" then out[#out + 1] = "pub " .. c.topic
    else out[#out + 1] = c.kind end
  end
  return out
end

describe("services.uploads", function()
  it("happy path: md5 -> rename -> probe -> meta -> track added to the playlist", function()
    local doc = doc_with()
    local r = uploads.on_add(doc, { uploadId = "42", filename = "Song.mp3", playlistId = "p" })
    assert_eq(kinds(r), { "shell md5" }); local ref = r.commands[1].ref
    assert_eq(ref.temp, "/d/uploads/upload_42")
    r = uploads.on_hashed(doc, { rc = 0, out = "fedcba9876543210ffff  /d/uploads/upload_42\n", ref = ref })
    assert_eq(kinds(r), { "files.rename /d/uploads/upload_42" }); assert_eq(r.commands[1].to, "/d/uploads/fedcba9876543210")
    r = uploads.on_renamed(doc, { ok = true, size = 1234, ref = ref })
    assert_eq(kinds(r), { "shell probe_audio" }); assert_eq(r.commands[1].args.out, "/run/probe_fedcba9876543210.json")
    r = uploads.on_probed(doc, { rc = 0, ref = ref })
    assert_eq(kinds(r), { "files.read_text /run/probe_fedcba9876543210.json" })
    r = uploads.on_meta(doc, { text = json.encode({ ["file-type"] = 1, ["audio-codec"] = "mp3", duration_s = 12.5, title = "T", album = "A" }), ref = ref })
    local t = r.state.library.tracks.fedcba9876543210
    assert_eq(t.title, "T"); assert_eq(t.album, "A"); assert_eq(t.artist, "unknown"); assert_eq(t.duration, 12.5); assert_eq(t.size, 1234)
    assert_eq(r.state.library.playlists.p.tracks, { "fedcba9876543210" })
    assert_eq(kinds(r)[1], "files.remove /run/probe_fedcba9876543210.json")
    assert_eq(kinds(r)[#kinds(r)], "emit upload.done")
  end)

  it("title falls back to the file name without extension; non-audio is refused and removed", function()
    local doc = doc_with()
    local ref = { uploadId = "1", filename = "sans tags é.mp3", trackId = "aaaaaaaaaaaaaaaa", final = "/d/uploads/aaaaaaaaaaaaaaaa", probe = "/run/p.json" }
    local r = uploads.on_meta(doc, { text = json.encode({ ["file-type"] = 1, ["audio-codec"] = "mp3", duration_s = 3 }), ref = ref })
    assert_eq(r.state.library.tracks.aaaaaaaaaaaaaaaa.title, "sans tags é")
    r = uploads.on_meta(doc, { text = json.encode({ ["file-type"] = 0, ["mime-type"] = "text/plain" }), ref = ref })
    assert_eq(kinds(r), { "files.remove /run/p.json", "files.remove /d/uploads/aaaaaaaaaaaaaaaa", "log", "emit user.message UPLOAD_FAIL_TYPE", "emit upload.done" })
    r = uploads.on_probed(doc, { rc = 1, ref = ref })
    assert_eq(kinds(r)[1], "files.remove /d/uploads/aaaaaaaaaaaaaaaa")
  end)

  it("a duplicate keeps the existing file and is added to the playlist; a bad playlist fails early", function()
    local doc = doc_with()
    local ref = { uploadId = "7", filename = "x.mp3", playlistId = "p", temp = "/d/uploads/upload_7" }
    local r = uploads.on_hashed(doc, { rc = 0, out = "0123456789abcdef0000 x", ref = ref })
    assert_eq(kinds(r)[1], "files.remove /d/uploads/upload_7")
    assert_eq(r.state.library.playlists.p.tracks, { "0123456789abcdef" })
    r = uploads.on_add(doc, { uploadId = "8", filename = "x.mp3", playlistId = "nope" })
    assert_eq(kinds(r), { "files.remove /d/uploads/upload_8", "log", "emit user.message UPLOAD_FAIL", "emit upload.done" })
    r = uploads.on_add(doc, { uploadId = "../x", filename = "x.mp3" })
    assert_eq(kinds(r), { "emit user.message UPLOAD_FAIL", "emit upload.done" })
  end)
end)

describe("api.v1", function()
  local function cmd(doc, name, payload)
    return v1.on_cmd(doc, { type = "v1.cmd", name = name, raw = type(payload) == "string" and payload or json.encode(payload), now = 5, wall = 1000 })
  end

  it("builds the 1.x state document from ours", function()
    local doc = doc_with()
    doc.playback = { state = "playing", position_ms = 500, now = { playlist = "p", index = 1, queue_pos = 1, track = "t", title = "T", has_next = false, has_prev = false, service = "FILE", uri = "file:///x" } }
    doc.flags = { TOY_SAFE_OFF = true }; doc.net = { ssid = "Box", signal = -60, connected = true, ip = "10.0.0.2" }
    local s = v1.state(doc)
    assert_eq(s.audio.playback, { state = "PLAYING", position_ms = 500 })
    assert_eq(s.audio.nowPlaying.playlistId, "p"); assert_eq(s.audio.nowPlaying.track, "T"); assert_eq(s.audio.nowPlaying.trackIndex, 1)
    assert_eq(s.db.tracks["0123456789abcdef"].title, "old")
    assert_eq(s.device.flags, { "TOY_SAFE_OFF" }); assert_eq(s.device.ip, "10.0.0.2")
    assert_eq(s.wifi.ssid, "Box"); assert_eq(s.wifi.stat, "success")
  end)

  it("partial publishes map our keys to 1.x sub-trees", function()
    local doc = doc_with()
    local p = v1.partial(doc, { "library", "audiocfg" })
    assert_eq(p.topic, v1.TOPIC_STATE)
    assert_true(p.payload.db ~= nil); assert_true(p.payload.audio ~= nil); assert_nil(p.payload.device)
    assert_nil(v1.partial(doc, { "activity" }))
    assert_true(v1.partial(doc, {}, { "db", "device" }).payload.device ~= nil)
    -- coalesced db+device are split (db+device together means "upload ended" to the 1.x page)
    local second, first = v1.partial(doc, { "library", "device" })
    assert_true(first.payload.device ~= nil and first.payload.db == nil)
    assert_true(second.payload.db ~= nil and second.payload.device == nil)
  end)

  it("GET_STATE publishes everything; malformed JSON and unknown names give 1.x errors", function()
    local doc = doc_with()
    local r = cmd(doc, "GET_STATE", "{}")
    assert_eq(r.commands[1].topic, v1.TOPIC_STATE); assert_true(r.commands[1].payload.db ~= nil)
    r = cmd(doc, "PLAYLIST_NEW", "{not json")
    assert_eq(r.commands[1].payload.msg, "received invalid message")
    r = cmd(doc, "NOPE", {})
    assert_match(r.commands[1].payload.msg, "unknown topic")
  end)

  it("PLAYLIST_* map to the library with 1.x error texts", function()
    local doc = doc_with()
    local r = cmd(doc, "PLAYLIST_NEW", { title = "Comptines", audiobook = false })
    assert_eq(r.state.library.playlists.user_1000.title, "Comptines")
    doc.library = r.state.library
    r = cmd(doc, "PLAYLIST_UPDATE", { playlist = { id = "TRASH", title = "x" } })
    assert_eq(r.commands[1].payload.msg, "TRASH_READONLY")
    r = cmd(doc, "PLAYLIST_ADD_STREAM", { playlistId = "user_1000", title = "", url = "javascript:alert(1)" })
    assert_eq(r.commands[1].payload.msg, "invalid stream url")
    r = cmd(doc, "PLAYLIST_UPDATE", { playlist = { id = "x", tracks = 5 } })
    assert_eq(r.commands[1].payload.msg, "invalid tracks")
    r = cmd(doc, "PLAYLIST_UPDATE", { playlist = { id = "user_1000", star = "Jooki.Fox" } })
    assert_eq(r.state.library.playlists.user_1000.star, "Jooki.Fox")
    assert_eq(r.commands[#r.commands].event.parts, { "db", "device" })
    r = cmd(doc, "PLAYLIST_UPDATE", { playlist = { id = "user_1000", tagId = "04000000B00001" } })
    assert_eq(r.commands[1].payload.msg, "invalid token type")
  end)

  it("transport, volume, config, messages", function()
    local doc = doc_with()
    local r = cmd(doc, "SET_VOL", { vol = 55 })
    assert_eq(r.state.audiocfg.volume, 55)
    r = cmd(doc, "SET_VOL", "[]")
    assert_match(r.commands[1].payload.msg, "missing or invalid vol")
    r = cmd(doc, "SET_CFG", { repeat_mode = false, shuffle_mode = true })
    assert_eq(r.state.audiocfg.repeat_mode, 0); assert_true(r.state.audiocfg.shuffle_mode); assert_eq(r.commands[1].kind, "files.write")
    r = cmd(doc, "MESSAGE_DISMISS", { id = "a" })
    assert_match(r.commands[1].payload.msg, "invalid msg id")
    doc.userMessages = { { id = 3, messageType = "UPLOAD_FAIL" } }
    r = cmd(doc, "MESSAGE_DISMISS", { id = 3 })
    assert_eq(r.state.userMessages, {})
    r = v1.on_user_message(doc, { level = "ERROR", messageType = "UPLOAD_FAIL_TYPE", extra = { filename = "x" }, wall = 9 })
    assert_eq(r.state.userMessages[2].messageType, "UPLOAD_FAIL_TYPE")
    r = cmd(doc, "DO_PLAY", "")
    assert_eq(r, {})
    r = cmd(doc, "SHUTDOWN", { src = "from-web" })
    assert_eq(r.commands[1].event.name, "Evt.Jooki.Poweroff")
  end)
end)
