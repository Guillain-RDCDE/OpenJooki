-- services.uploads: a file the page sent -> a track in the library.
-- web_ctrl stores the file as <data_dir>/uploads/upload_<id>; the page then
-- sends upload.add. The steps each need a process or a file read, so the flow
-- is a chain of commands with replies (docs/22 §4.3, guarantees of 1.3):
--   upload.add -> md5 (shell) -> upload.hashed
--     duplicate track: temp removed, track appended to the playlist
--     new track: rename to uploads/<id> -> probe (shell) -> upload.probed
--                -> read the probe JSON -> upload.meta -> track added
--   any failure: temp file removed, an existing file is never deleted,
--   a user message UPLOAD_FAIL[_TYPE] is raised, upload.done is emitted.
local json = require("vendor.json")
local library = require("services.library")
local uploads = {}

local function data_dir(doc) return (doc.config and doc.config.data_dir) or "/jooki/external/jooki" end
local function scratch_dir(doc) return (doc.config and doc.config.scratch_dir) or "/run/openjooki" end
local function emit(t, extra)
  local e = { type = t }
  for k, v in pairs(extra or {}) do e[k] = v end
  return { kind = "emit", event = e }
end

local function fail(ref, kind, err, remove_path)
  local cmds = {}
  if remove_path then cmds[#cmds + 1] = { kind = "files.remove", path = remove_path } end
  cmds[#cmds + 1] = { kind = "log", level = "warn", key = "uploads.failed", fields = { file = ref.filename, err = err } }
  cmds[#cmds + 1] = emit("user.message", { level = "ERROR", messageType = kind, extra = { filename = ref.filename, err = err } })
  cmds[#cmds + 1] = emit("upload.done", { ok = false, uploadId = ref.uploadId, playlistId = ref.playlistId })
  return { commands = cmds }
end

local function finish(result, ref)
  result.commands = result.commands or {}
  result.commands[#result.commands + 1] = emit("upload.done", { ok = true, uploadId = ref.uploadId, playlistId = ref.playlistId, trackId = ref.trackId })
  return result
end

--- upload.add { uploadId, filename, playlistId? }
function uploads.on_add(doc, ev)
  local id = tostring(ev.uploadId or "")
  if not id:match("^%d+$") then
    return { commands = { emit("user.message", { level = "ERROR", messageType = "UPLOAD_FAIL", extra = { filename = ev.filename, err = "invalid uploadId" } }),
                          emit("upload.done", { ok = false }) } }
  end
  local playlist = ev.playlistId
  if playlist == library.TRASH then playlist = nil end
  if playlist and not (doc.library and doc.library.playlists[playlist]) then
    return fail({ filename = ev.filename, uploadId = id, playlistId = playlist }, "UPLOAD_FAIL", "playlistId invalid: " .. tostring(playlist), data_dir(doc) .. "/uploads/upload_" .. id)
  end
  local temp = data_dir(doc) .. "/uploads/upload_" .. id
  local ref = { uploadId = id, filename = ev.filename, playlistId = playlist, temp = temp }
  return { commands = { { kind = "shell", action = "md5", args = { file = temp }, reply = "upload.hashed", ref = ref } } }
end

function uploads.on_hashed(doc, ev)
  local ref = ev.ref
  local hash = ev.rc == 0 and tostring(ev.out or ""):match("^(%x+)") or nil
  if not hash or #hash < 16 then return fail(ref, "UPLOAD_FAIL", "cannot hash the file", ref.temp) end
  local tid = hash:sub(1, 16)
  ref.trackId = tid
  local lib = doc.library or { playlists = {}, tracks = {} }
  if lib.tracks[tid] then
    -- duplicate: keep the existing file, drop the temp, still add to the playlist
    local cmds = { { kind = "files.remove", path = ref.temp }, { kind = "log", level = "info", key = "uploads.duplicate", fields = { track = tid } } }
    if ref.playlistId then
      local r, err = library.mutate(doc, { playlists = true }, function(l) return library.ops.playlist_add_track(l, ref.playlistId, tid) end)
      if not r then
        for _, c in ipairs(cmds) do table.insert(fail(ref, "UPLOAD_FAIL", err.message).commands, 1, c) end
        return fail(ref, "UPLOAD_FAIL", err.message, ref.temp)
      end
      for _, c in ipairs(r.commands) do cmds[#cmds + 1] = c end
      return finish({ state = r.state, commands = cmds }, ref)
    end
    return finish({ commands = cmds }, ref)
  end
  ref.final = data_dir(doc) .. "/uploads/" .. tid
  return { commands = { { kind = "files.rename", from = ref.temp, to = ref.final, reply = "upload.renamed", ref = ref } } }
end

function uploads.on_renamed(doc, ev)
  local ref = ev.ref
  if not ev.ok then return fail(ref, "UPLOAD_FAIL", "rename failed: " .. tostring(ev.err), ref.temp) end
  ref.size = ev.size
  ref.image = data_dir(doc) .. "/artwork/" .. ref.trackId .. ".jpg"
  ref.probe = scratch_dir(doc) .. "/probe_" .. ref.trackId .. ".json"
  return { commands = { { kind = "shell", action = "probe_audio", args = { file = ref.final, image = ref.image, out = ref.probe }, reply = "upload.probed", ref = ref } } }
end

function uploads.on_probed(_, ev)
  local ref = ev.ref
  if ev.rc ~= 0 then return fail(ref, "UPLOAD_FAIL_TYPE", "failed to extract metadata", ref.final) end
  return { commands = { { kind = "files.read_text", path = ref.probe, reply = "upload.meta", ref = ref } } }
end

local function title_from(filename)
  local t = tostring(filename or ""):gsub(".+/", ""):gsub("%.%w+$", "")
  return t
end

function uploads.on_meta(doc, ev)
  local ref = ev.ref
  local cmds = { { kind = "files.remove", path = ref.probe } }
  local ok, m = pcall(json.decode, ev.text or "")
  if not ev.text or not ok or type(m) ~= "table" then
    local r = fail(ref, "UPLOAD_FAIL_TYPE", "no metadata present", ref.final)
    table.insert(r.commands, 1, cmds[1])
    return r
  end
  if m["file-type"] == 0 or (not m["audio-codec"] and not m.duration_s) then
    local r = fail(ref, "UPLOAD_FAIL_TYPE", "unsupported file type: " .. tostring(m["mime-type"] or "unknown"), ref.final)
    table.insert(r.commands, 1, cmds[1])
    return r
  end
  local meta = {
    filename = ref.final, userFilename = ref.filename, size = ref.size,
    codec2 = m["audio-codec"], format2 = m["container-format"], duration = tonumber(m.duration_s) or 0,
    title = m.title or m.TITLE or title_from(ref.filename), album = m.album or m.ALBUM or "unknown",
    artist = m.artist or m.ARTIST or "unknown", hasImage = (m["ml-image-tag"] ~= nil) or nil,
  }
  local r, err = library.mutate(doc, { playlists = true, tracks = true }, function(l)
    local ok2, e = library.ops.track_add(l, ref.trackId, meta)
    if not ok2 then return nil, e end
    if ref.playlistId then return library.ops.playlist_add_track(l, ref.playlistId, ref.trackId) end
    return true
  end)
  if not r then
    local f = fail(ref, "UPLOAD_FAIL", err.message, ref.final)
    table.insert(f.commands, 1, cmds[1])
    return f
  end
  for _, c in ipairs(r.commands) do cmds[#cmds + 1] = c end
  cmds[#cmds + 1] = { kind = "log", level = "info", key = "uploads.imported", fields = { track = ref.trackId, title = meta.title } }
  return finish({ state = r.state, commands = cmds }, ref)
end

local S = { type = "object", required = { "uploadId" }, additionalProperties = false,
            properties = { uploadId = { type = { "string", "integer" } }, filename = { type = "string", maxLength = 300 }, playlistId = { type = "string", maxLength = 80 } } }
uploads.schema = S

function uploads.install(api, dispatch)
  dispatch.on("upload.add", "uploads", uploads.on_add)
  dispatch.on("upload.hashed", "uploads", uploads.on_hashed)
  dispatch.on("upload.renamed", "uploads", uploads.on_renamed)
  dispatch.on("upload.probed", "uploads", uploads.on_probed)
  dispatch.on("upload.meta", "uploads", uploads.on_meta)
  api.command("upload.add", S, function(doc, p)
    return uploads.on_add(doc, { uploadId = tostring(p.uploadId), filename = p.filename, playlistId = p.playlistId })
  end)
end

return uploads
