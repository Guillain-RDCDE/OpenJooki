-- services.tokens: a token on the Jooki -> a character -> a playlist.
-- Owns state.nfc = { starId, tagId } (what is on the Jooki right now).
-- Events in:  nfc.tag { uid, star_code | foreign }, nfc.removed, nfc.written { uid }
-- A foreign tag (not a Jooki token: an amiibo, a sticker) is its own character "tag.<uid>":
-- it is learned and starts its playlist like a token, but the ESP32 never reports its
-- removal, so it does not claim state.nfc (the page would show it on the Jooki forever)
-- and taking it off does not pause.
-- The round flat tokens (code 512) and the Thank-you token (260) all carry the same code, so
-- each one is its own character too, "flat.<uid>" / "thanks.<uid>" (docs/23 §4): a real
-- Jooki token, so it claims state.nfc and taking it off pauses. Until it has a playlist of
-- its own it plays the one linked to the shared character (Jooki.Flat / Jooki.ThankYou).
-- Emits:      playback.request { playlist, source = "token" }
--             playback.pause_request { source = "token" }
--             system.tag { name }            (sys.* tags: device handles them)
--             system.event { name }          (Evt.Character.Detect / .Empty / .Write)
-- Writes:     tokens.json when a token is learned (through library.mutate)
local library = require("services.library")
local util = require("services.util")
local tokens = {}

-- character codes (docs/22 §3.5); anything else is "new.<hex>" and still works
local STARS = {
  [256] = "Jooki.Dragon", [257] = "Jooki.Fox", [258] = "Jooki.Ghost", [259] = "Jooki.Knight", [260] = "Jooki.ThankYou",
  [261] = "Jooki.Whale", [262] = "Jooki.Black.Dragon", [263] = "Jooki.Black.Fox", [264] = "Jooki.Black.Knight",
  [265] = "Jooki.Black.Whale", [266] = "Jooki.White.Dragon", [267] = "Jooki.White.Fox", [268] = "Jooki.White.Knight",
  [269] = "Jooki.White.Whale", [512] = "Jooki.Flat",
  [528] = "G2.Orange", [529] = "G2.DarkBlue", [530] = "G2.Turquoise", [531] = "G2.Yellow", [532] = "G2.Red",
  [533] = "G2.Purple", [534] = "G2.Green", [535] = "G2.Pink",
  [768] = "sys.record", [769] = "sys.factory_mode_on", [770] = "sys.factory_mode_off", [771] = "sys.airplane_mode_on",
  [772] = "sys.airplane_mode_off", [773] = "sys.toy_safe_on", [774] = "sys.toy_safe_off", [775] = "sys.wifi_on",
  [776] = "sys.wifi_off", [777] = "sys.bt_on", [778] = "sys.bt_off", [779] = "sys.production_finished",
  [780] = "sys.production_test_start", [781] = "sys.production_test_buttons", [782] = "sys.production_test_audio",
  [783] = "sys.production_test_radio", [1023] = "sys.factory_reset",
}
for i = 0, 20 do STARS[1024 + i] = "test." .. i end
for i = 0, 9 do STARS[2304 + i] = "Jooki.Temp" .. i end
tokens.STARS = STARS

function tokens.star_name(code)
  if code == nil or code == 65535 then return nil end
  return STARS[code] or ("new." .. string.format("%x", code))
end

local function is_system(name) return name and (name:sub(1, 4) == "sys." or name:sub(1, 5) == "test.") end

-- shared character -> prefix of the per-token characters (docs/23 §4)
local PER_TOKEN = library.PER_TOKEN
--- The character of one physical token: its own for the per-token codes, else the shared one.
function tokens.own_star(star, uid)
  local prefix = star and PER_TOKEN[star]
  if prefix and type(uid) == "string" and uid ~= "" then return prefix .. uid, star end
  return star, nil
end

function tokens.on_tag(doc, ev)
  if ev.bad then return { commands = { { kind = "log", level = "warn", key = "tokens.bad_tag", fields = { raw = tostring(ev.raw) } } } } end
  local star, shared
  if ev.foreign then star = "tag." .. ev.uid else star, shared = tokens.own_star(tokens.star_name(ev.star_code), ev.uid) end
  if not star then return { commands = { { kind = "log", level = "warn", key = "tokens.no_star", fields = { uid = ev.uid } } } } end
  local result = { state = { nfc = { starId = star, tagId = ev.uid } }, commands = {} }
  if ev.foreign then
    result.state.nfc = nil
    result.commands[1] = { kind = "log", level = "info", key = "tokens.foreign", fields = { uid = ev.uid } }
  end
  if is_system(star) then
    result.commands[#result.commands + 1] = { kind = "emit", event = { type = "system.tag", name = star, uid = ev.uid } }
    return result
  end
  -- learn the token (seen count, character), persist tokens.json
  local mutated = library.mutate(doc, { tokens = true }, function(lib) return library.ops.learn(lib, ev.uid, star) end)
  if mutated then
    result.state.library = mutated.state.library
    for _, c in ipairs(mutated.commands) do result.commands[#result.commands + 1] = c end
  end
  local lib = (mutated and mutated.state.library) or doc.library or { playlists = {}, tracks = {}, tokens = {} }
  local playlist = library.ops.playlist_for(lib, star, ev.uid)
  -- a flat token without a playlist of its own plays the one of all the flat tokens (as before)
  if not playlist and shared then playlist = library.ops.playlist_for(lib, shared) end
  if playlist then
    result.commands[#result.commands + 1] = { kind = "emit", event = { type = "system.event", name = "Evt.Character.Detect" } }
    result.commands[#result.commands + 1] = { kind = "emit", event = { type = "playback.request", playlist = playlist, source = "token" } }
  else
    result.commands[#result.commands + 1] = { kind = "log", level = "info", key = "tokens.no_playlist", fields = { star = star } }
    result.commands[#result.commands + 1] = { kind = "emit", event = { type = "system.event", name = "Evt.Character.Detect.Empty" } }
  end
  return result
end

function tokens.on_removed(doc)
  local was = doc.nfc or {}
  local result = { state = { nfc = { starId = nil, tagId = nil } }, commands = {} }
  if was.starId == "sys.record" then
    result.commands[#result.commands + 1] = { kind = "emit", event = { type = "system.tag", name = "sys.record.stop" } }
  end
  result.commands[#result.commands + 1] = { kind = "emit", event = { type = "playback.pause_request", source = "token" } }
  return result
end

function tokens.on_written(_, ev)
  return { commands = { { kind = "emit", event = { type = "system.event", name = "Evt.Character.Write" } },
                        { kind = "log", level = "info", key = "tokens.written", fields = { uid = ev.uid } } } }
end

-- A picture for a token (docs/23 §3): the page sends a small PNG through web_ctrl's /upload
-- (stored as <data_dir>/uploads/upload_<id>), then TOKEN_SET_IMAGE { tagId, uploadId }.
-- The file moves to <data_dir>/artwork/tok_<tagId>.png (served at /artwork/) and the token
-- keeps that address, with the file size as a cache key so the page reloads a new picture.
local data_dir = util.data_dir
function tokens.image_path(doc, uid) return data_dir(doc) .. "/artwork/tok_" .. uid .. ".png" end

local function image_fail(ref, err)
  return { commands = { { kind = "files.remove", path = ref.temp },
                        { kind = "log", level = "warn", key = "tokens.image_failed", fields = { uid = ref.uid, err = err } },
                        { kind = "emit", event = { type = "user.message", level = "ERROR", messageType = "TOKEN_IMAGE_FAIL", extra = { tagId = ref.uid, err = err } } } } }
end

--- TOKEN_SET_IMAGE { tagId, uploadId }
function tokens.on_set_image(doc, ev)
  local uid, id = tostring(ev.tagId or ""), tostring(ev.uploadId or "")
  local temp = data_dir(doc) .. "/uploads/upload_" .. id
  local ref = { uid = uid, temp = temp }
  if not id:match("^%d+$") then return image_fail(ref, "invalid uploadId") end
  if not (doc.library and doc.library.tokens[uid]) then return image_fail(ref, "unknown token") end
  return { commands = { { kind = "files.rename", from = temp, to = tokens.image_path(doc, uid), reply = "tokens.image_moved", ref = ref } } }
end

function tokens.on_image_moved(doc, ev)
  local ref = ev.ref
  if not ev.ok then return image_fail(ref, "rename failed: " .. tostring(ev.err)) end
  local url = "/artwork/tok_" .. ref.uid .. ".png?v=" .. tostring(ev.size or 0)
  local r, err = library.mutate(doc, { tokens = true }, function(lib) return library.ops.token_edit(lib, ref.uid, nil, url) end)
  if not r then return image_fail({ uid = ref.uid, temp = tokens.image_path(doc, ref.uid) }, err.message) end
  r.commands[#r.commands + 1] = { kind = "log", level = "info", key = "tokens.image_set", fields = { uid = ref.uid, size = ev.size } }
  return r
end

function tokens.install(_, dispatch)
  dispatch.on("nfc.tag", "tokens", tokens.on_tag)
  dispatch.on("nfc.removed", "tokens", tokens.on_removed)
  dispatch.on("nfc.written", "tokens", tokens.on_written)
  dispatch.on("tokens.image_moved", "tokens", tokens.on_image_moved)
end

return tokens
