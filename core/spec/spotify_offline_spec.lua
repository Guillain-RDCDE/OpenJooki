local offline = require("services.spotify_offline")
local playback = require("services.playback")
local json = require("vendor.json")
local api = require("api.v2")
local dispatch = require("kernel.dispatch")
local security = require("services.security")
local URI = "spotify:playlist:1111111111111111111111"
local function fixture()
  return { config = { spotify_offline_enabled = true, spotify_offline_root = "/offline", scratch_dir = "/run/test" },
    library = { playlists = { user_1 = { title = "Test", spotify = { uri = URI, preset = "00" }, tracks = {} } }, tracks = {} },
    spotify = { active = true }, playback = { state = "idle" }, playback_int = {},
    spotify_offline = { available = true, account_ready = true, metadata_ready = true, account_id = "account-one", modes = { user_1 = "auto" }, playlists = { [URI] = { ready = true, bytes = 3000, tracks = {
      { uri = "spotify:track:1111111111111111111111", name = "First", artists = { "Artist" }, album = "Album", duration_ms = 10000 },
      { uri = "spotify:track:2222222222222222222222", name = "Second", artists = { "Artist" }, album = "Album", duration_ms = 20000 },
    } } } }, spotify_offline_int = { next_id = 0, controls = {} } }
end
local function apply(d, r) for k, v in pairs(r and r.state or {}) do d[k] = v end return d end
local function shell(r, name) for _, c in ipairs(r.commands or {}) do if c.kind == "shell" and c.action == name then return c end end end
local function boot_play(d)
  local r = playback.on_request(d, { playlist = "user_1", index = 2, restart = true, now = 10 })
  apply(d, r); return r
end

describe("Spotify offline snapshots and routing", function()
  it("does no boot work unless explicitly enabled", function()
    local d = fixture(); d.config.spotify_offline_enabled = false
    assert_nil(offline.on_boot(d)); assert_false(offline.wants(d, "user_1"))
  end)
  it("retains the original controller when online mode is selected, including without an offline account", function()
    local d = fixture(); d.spotify_offline.modes.user_1 = "online"; d.spotify_offline.account_ready = false
    assert_false(offline.wants(d, "user_1"))
    local r = playback.on_request(d, { playlist = "user_1", now = 10 })
    assert_nil(shell(r, "offline_play"))
    assert_eq(d.library.playlists.user_1.spotify.preset, "00")
  end)
  it("starts the exact saved ordered track through the regular playback state machine", function()
    local d = fixture(); local r = boot_play(d)
    assert_eq(r.state.playback.now.title, "Second")
    assert_eq(r.state.playback.now.service, "SPOTIFY_OFFLINE")
    assert_eq(r.state.playback.now.index, 2)
    assert_eq(shell(r, "offline_play").args.index, 1)
    assert_eq(shell(r, "offline_play").args.uri, URI)
    assert_eq(r.state.playback.state, "starting")
  end)
  it("uses the last complete generation while a later update is incomplete or failed", function()
    local d = fixture(); d.spotify_offline.download = { uri = URI, phase = "error", tracks = { { name = "Partial" } } }
    local r = boot_play(d); assert_eq(r.state.playback.now.title, "Second")
    d.spotify_offline.playlists[URI].ready = false
    assert_false(offline.wants(d, "user_1"))
    d.spotify_offline.modes.user_1 = "offline"
    assert_true(offline.wants(d, "user_1"))
    local none, e = offline.start(d, "user_1", d.library.playlists.user_1, {})
    assert_nil(none); assert_eq(e.code, "unavailable")
  end)
  it("starts a typed background sync, deduplicates requests and rejects untrusted IDs", function()
    local d = fixture(); local r = offline.on_sync(d, { playlist = "user_1" })
    assert_eq(shell(r, "offline_sync").args.uri, URI)
    assert_eq(r.state.spotify_offline.download.phase, "resolving")
    apply(d, r)
    local same = offline.on_sync(d, { playlist = "user_1" }); assert_nil(shell(same, "offline_sync"))
    local none, e = offline.on_sync(d, { playlist = "../../secret" }); assert_nil(none); assert_eq(e.code, "not_found")
  end)
  it("queues other playlists, keeps exact order and removes waiting entries", function()
    local d = fixture(); local second = "spotify:playlist:2222222222222222222222"
    d.library.playlists.user_2 = { title = "Second playlist", spotify = { uri = second, preset = "00" } }
    apply(d, offline.on_sync(d, { playlist = "user_1", now = 10 }))
    local r = offline.on_sync(d, { playlist = "user_2", now = 11 }); apply(d, r)
    assert_nil(shell(r, "offline_sync")); assert_eq(#d.spotify_offline.queue, 1)
    assert_eq(d.spotify_offline.queue[1].uri, second)
    apply(d, offline.on_sync(d, { playlist = "user_2", now = 12 })); assert_eq(#d.spotify_offline.queue, 1)
    local job = json.encode({ version = 1, request = d.spotify_offline_int.job_request, uri = URI, account_id = "account-one", phase = "complete" })
    apply(d, offline.on_job(d, { text = job }))
    r = offline.on_timer(d, { now = 13 }); assert_eq(shell(r, "offline_sync").args.uri, second)
    apply(d, r); assert_eq(#d.spotify_offline.queue, 0)
    d.spotify_offline.queue = { { playlist = "user_1", uri = URI } }
    r = offline.on_cancel_queued(d, { playlist = "user_1" }); assert_eq(#r.state.spotify_offline.queue, 0)
  end)
  it("metadata-only accounts can list songs while forced offline mode falls back to the original player", function()
    local d = fixture(); d.spotify_offline.account_ready = false; d.spotify_offline.modes.user_1 = "offline"
    assert_false(offline.wants(d, "user_1"))
    local r = offline.on_preview_request(d, { playlist = "user_1", offset = 50, now = 12 })
    assert_eq(shell(r, "offline_preview").args.offset, 50)
    local none, e = offline.on_sync(d, { playlist = "user_1" }); assert_nil(none); assert_eq(e.code, "unavailable")
  end)
  it("accepts song positions beyond the first bounded catalog page", function()
    local d = fixture(); d.spotify_offline.playlists[URI].total_tracks = 710
    local r = playback.on_request(d, { playlist = "user_1", index = 700, restart = true, now = 10 }); apply(d, r)
    assert_eq(shell(r, "offline_play").args.index, 699)
    local session = d.spotify_offline_int.session
    r = offline.on_player(d, { path = session.status, text = json.encode({ version = 1, session = session.id, phase = "playing", index = 699, track = { uri = "spotify:track:3333333333333333333333", name = "Chapter 700", artists = { "Artist" }, duration_ms = 10000 } }) })
    assert_eq(r.state.playback.now.title, "Chapter 700"); assert_eq(r.state.playback.now.index, 700)
  end)
  it("accepts helper completion only for the active login and logout invalidates it", function()
    local d = fixture(); d.spotify_offline.helper_ready = true
    apply(d, offline.on_login(d, { mode = "metadata", now = 20 }))
    local id = d.spotify_offline.auth.request
    assert_nil(offline.on_auth_helper(d, { phase = "complete", request = "stale" }))
    local r = offline.on_auth_helper(d, { phase = "complete", request = id }); assert_true(shell(r, "offline_auth_activate") ~= nil)
    apply(d, offline.on_forget(d)); assert_nil(offline.on_auth_helper(d, { phase = "complete", request = id }))
    assert_false(d.spotify_offline.metadata_ready)
  end)
  it("resumes a paused offline figure without replacing its player or rewinding", function()
    local d = fixture(); d.library.playlists.user_1.resume = true
    boot_play(d); d.playback.state = "paused"; d.playback.position_ms = 180000
    local session = d.spotify_offline_int.session.id
    local r = playback.on_request(d, { playlist = "user_1", now = 60 })
    assert_nil(shell(r, "offline_play")); apply(d, r)
    assert_eq(d.spotify_offline_int.session.id, session)
    assert_eq(d.spotify_offline_int.controls[1].action, "resume")
    assert_eq(d.playback.position_ms, 180000)
  end)
  it("restores the interrupted download first in either boot read order and binds the queue to its account", function()
    for _, reverse in ipairs({ false, true }) do
      local d = fixture(); apply(d, offline.on_boot(d))
      local queue = { text = json.encode({ account_id = "account-one", active = { playlist = "user_1", uri = URI }, items = {} }) }
      local catalog = { text = json.encode({ version = 1, account_id = "account-one", account_ready = true, playlists = {} }) }
      if reverse then apply(d, offline.on_catalog(d, catalog)); apply(d, offline.on_queue(d, queue))
      else apply(d, offline.on_queue(d, queue)); apply(d, offline.on_catalog(d, catalog)) end
      assert_eq(d.spotify_offline.queue[1].uri, URI)
      local r = offline.on_timer(d, { now = 90 }); assert_eq(shell(r, "offline_sync").args.uri, URI)
      apply(d, offline.on_catalog(d, { text = json.encode({ version = 1, account_id = "other", account_ready = true, playlists = {} }) }))
      assert_eq(#d.spotify_offline.queue, 0)
    end
  end)
  it("pauses the remaining queue on a full card until explicitly continued", function()
    local d = fixture(); apply(d, offline.on_sync(d, { playlist = "user_1", now = 10 }))
    apply(d, offline.on_job(d, { text = json.encode({ version = 1, account_id = "account-one", request = d.spotify_offline_int.job_request, uri = URI, phase = "error", error = "storage_full" }) }))
    assert_eq(d.spotify_offline.queue_paused, "storage_full")
    apply(d, offline.on_sync(d, { playlist = "user_1", now = 11 }))
    assert_nil(shell(offline.on_timer(d, { now = 12 }), "offline_sync"))
    apply(d, offline.on_resume_queue(d))
    assert_true(shell(offline.on_timer(d, { now = 13 }), "offline_sync") ~= nil)
  end)
  it("requires an offline account only for the new download path", function()
    local d = fixture(); d.spotify_offline.account_ready = false
    local none, e = offline.on_sync(d, { playlist = "user_1" }); assert_nil(none); assert_match(e.message, "Premium")
    assert_false(offline.wants(d, "user_1"))
  end)
  it("queues transport commands without losing earlier button presses and trims acknowledgments", function()
    local d = fixture(); boot_play(d)
    local one = playback.on_next(d, {}); apply(d, one)
    local two = playback.on_seek(d, { ms = 7500 }); apply(d, two)
    assert_eq(#d.spotify_offline_int.controls, 2)
    assert_eq(d.spotify_offline_int.controls[1].action, "next")
    assert_eq(d.spotify_offline_int.controls[2].value, 7500)
    local session = d.spotify_offline_int.session
    local r = offline.on_player(d, { path = session.status, text = json.encode({ version = 1, session = session.id, phase = "playing", index = 0, position_ms = 1200, ack = d.spotify_offline_int.controls[1].id }) })
    assert_eq(#r.state.spotify_offline_int.controls, 1)
    assert_eq(r.state.playback.now.title, "First")
    assert_eq(r.state.playback.position_ms, 1200)
  end)
  it("waits for native pause/stop before emitting the normal playback transition", function()
    local d = fixture(); boot_play(d); d.playback.state = "playing"
    local r = playback.on_pause(d, { source = "page", now = 10 }); apply(d, r)
    assert_eq(d.playback.state, "playing")
    local session = d.spotify_offline_int.session
    r = offline.on_player(d, { path = session.status, text = json.encode({ version = 1, session = session.id, phase = "paused", index = 0, ack = d.spotify_offline_int.next_id }) })
    assert_eq(r.state.playback.state, "paused"); assert_eq(r.commands[1].event.type, "playback.changed")
    apply(d, r); apply(d, playback.on_stop(d)); assert_eq(d.playback.state, "paused")
  end)
  it("ignores stale session replies and refuses removal during playback", function()
    local d = fixture(); boot_play(d)
    assert_nil(offline.on_player(d, { path = "/stale", text = "{}" }))
    local none, e = offline.on_remove(d, { playlist = "user_1" }); assert_nil(none); assert_eq(e.code, "conflict")
  end)
  it("stops a session when changing sources even before its first status arrives", function()
    local d = fixture(); boot_play(d); d.playback.now = { service = "FILE" }
    local r = offline.on_playback_changed(d)
    assert_eq(r.state.spotify_offline_int.controls[1].action, "stop")
    apply(d, r); assert_nil(offline.on_playback_changed(d))
  end)
  it("fails a player that exits before producing any status instead of leaving starting forever", function()
    local d = fixture(); boot_play(d)
    for _ = 1, 15 do apply(d, offline.on_timer(d, { now = 30 })) end
    assert_eq(d.playback.state, "idle"); assert_eq(d.spotify_offline.player.error, "backend_start_failed")
  end)
  it("rejects a previous download reply and reports startup failure", function()
    local d = fixture(); apply(d, offline.on_sync(d, { playlist = "user_1", now = 10 }))
    assert_nil(offline.on_job(d, { text = json.encode({ version = 1, uri = URI, request = "old", phase = "complete" }) }))
    for _ = 1, 15 do apply(d, offline.on_timer(d, {})) end
    assert_eq(d.spotify_offline.download.phase, "error")
  end)
  it("checks process birth time and reads the final status before reporting interruption", function()
    local d = fixture(); apply(d, offline.on_sync(d, { playlist = "user_1", now = 10 }))
    local txt = json.encode({ version = 1, uri = URI, request = d.spotify_offline_int.job_request, phase = "downloading", process = { pid = 42, start = "123" } })
    apply(d, offline.on_job(d, { text = txt }))
    local r = offline.on_process(d, { ref = { kind = "job", pid = 42, start = "123" } })
    assert_eq(r.commands[1].reply, "offline.job_final")
    r = offline.on_job_final(d, { text = txt }); assert_eq(r.state.spotify_offline.download.phase, "interrupted")
  end)
  it("invalidates the active account and stops offline playback without touching the original preset", function()
    local d = fixture(); boot_play(d)
    local r = offline.on_forget(d)
    assert_false(r.state.spotify_offline.account_ready)
    assert_eq(r.state.spotify_offline.playlists, {})
    assert_eq(r.state.playback.state, "idle")
    assert_true(shell(r, "offline_forget") ~= nil)
    assert_eq(d.library.playlists.user_1.spotify.preset, "00")
  end)
  it("playing a saved song does not bypass the parent-protected persistent mode selection", function()
    local d = fixture(); d.spotify_offline.modes.user_1 = "online"
    local r = offline.on_play(d, { playlist = "user_1", index = 1, now = 10 })
    assert_eq(r.state.playback.now.service, "SPOTIFY_OFFLINE")
    assert_eq(r.state.spotify_offline.modes.user_1, "online")
  end)
  it("does not republish an unchanged catalog and hides internal state from the API", function()
    local d = fixture(); local text = json.encode({ version = 1, account_ready = true, account_id = "test", playlists = {}, used_bytes = 3 })
    apply(d, offline.on_catalog(d, { text = text }))
    assert_nil(offline.on_catalog(d, { text = text }))
    assert_false(api.published("spotify_offline_int")); assert_true(api.published("spotify_offline"))
  end)
  it("protects downloads and mode changes with the parent code while transport stays available", function()
    local d = fixture(); api.reset(); dispatch.reset({ clock = function() return 0 end })
    offline.install(api, dispatch); security._set_parent_code("1234")
    api.set_guard(function(kind, code) return security.gate(security.PROTECTED_V2, kind, code) end)
    local r = api.handle(d, { raw = json.encode({ v = 2, type = "spotify_offline.sync", payload = { playlist = "user_1" } }) })
    assert_false(r.commands[1].payload.ok); assert_eq(r.commands[1].payload.error.code, "forbidden")
    security._set_parent_code(nil)
  end)
end)

describe("offline process argument validation", function()
  it("rejects path traversal, invalid URIs and unbounded session names", function()
    local shell_adapter = require("adapters.shell"); local adapter = require("adapters.spotify_offline")
    local values = { spotify_offline_root = "/offline", scratch_dir = "/run/test", spotify_offline_binary = "/bin/player", spotify_offline_quota_bytes = 536870912 }
    adapter.install(shell_adapter, { get = function(k) return values[k] end })
    assert_nil(shell_adapter._argv("offline_sync", { uri = "https://untrusted/" }))
    assert_nil(shell_adapter._argv("offline_play", { uri = URI, session = "../oops", index = 0 }))
    assert_true(shell_adapter._argv("offline_sync", { uri = URI, request = "10-1" }) ~= nil)
    values.spotify_offline_root = "/offline/../secret"
    assert_error(function() adapter.install(shell_adapter, { get = function(k) return values[k] end }) end, "invalid offline configuration")
  end)
end)
