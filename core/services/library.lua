-- services.library: playlists, tracks, tokens — the family's library.
-- Two halves:
--   library.ops   pure functions on a library table { playlists, tracks, tokens }
--                 (mutate the table they are given; the handlers copy first)
--   handlers      boot + api commands, returning state changes and file writes
-- Data shapes are those of 1.x (docs/22 §4) so that 1.x and 2.0 share files.
--   playlists[id] = { title, tracks = {trackId...}, star?, audiobook?, image?, plType?, spotify?, deezer? }
--   tracks[id]    = { filename, userFilename?, title, album, artist, duration, size, hasImage, isUrl? }
--   tokens[uid]   = { starId, seen, name?, image? }
local library = {}
local ops = {}
library.ops = ops

local TRASH, SYSTEM = "TRASH", "system"
local TRASH_TITLE = "Unused tracks"
library.TRASH = TRASH

-- ------------------------------------------------------------------ helpers
local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
local function is_uid(s) return type(s) == "string" and #s == 14 and s:match("^%x+$") ~= nil end
local function is_star(s) return type(s) == "string" and s ~= "" and #s <= 64 end
local function is_jplay(p) return p and p.plType == "JPLAY" end
local function is_url(u) return type(u) == "string" and u:match("^https?://[%w%[]") ~= nil end

local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deep_copy(x) end
  return out
end
library.copy = deep_copy

local function used_track_ids(lib)
  local used = {}
  for id, p in pairs(lib.playlists) do
    if id ~= TRASH then for _, t in ipairs(p.tracks or {}) do used[t] = true end end
  end
  return used
end

-- ------------------------------------------------------------------ queries
function ops.unused(lib)
  local used = used_track_ids(lib)
  local out = {}
  for id, t in pairs(lib.tracks) do
    if not used[id] and not t.isUrl then out[#out + 1] = id end
  end
  table.sort(out, function(a, b)
    local x, y = string.lower(tostring(lib.tracks[a].title or "")), string.lower(tostring(lib.tracks[b].title or ""))
    if x == y then return a < b end
    return x < y
  end)
  return out
end

--- The playlist a character starts (legacy per-token links are honoured too).
function ops.playlist_for(lib, star, uid)
  if uid then
    for id, p in pairs(lib.playlists) do if p.tagId == uid then return id end end
  end
  if star then
    for id, p in pairs(lib.playlists) do if not p.tagId and p.star == star then return id end end
  end
  return nil
end

function ops.user_playlist_ids(lib)
  local out = {}
  for id in pairs(lib.playlists) do if id ~= TRASH and id ~= SYSTEM then out[#out + 1] = id end end
  table.sort(out)
  return out
end

-- ------------------------------------------------------------------ maintenance
function ops.rebuild_trash(lib)
  local unused = ops.unused(lib)
  local trash = lib.playlists[TRASH]
  if #unused == 0 then
    if trash then lib.playlists[TRASH] = nil return true end
    return false
  end
  if not trash then
    lib.playlists[TRASH] = { title = TRASH_TITLE, tracks = unused }
    return true
  end
  local same = #trash.tracks == #unused
  if same then for i, t in ipairs(unused) do if trash.tracks[i] ~= t then same = false break end end end
  if same then return false end
  trash.tracks = unused
  return true
end

function ops.drop_orphan_streams(lib)
  local used = {}
  for _, p in pairs(lib.playlists) do for _, t in ipairs(p.tracks or {}) do used[t] = true end end
  local changed = false
  for id, t in pairs(lib.tracks) do
    if t.isUrl and not used[id] then lib.tracks[id] = nil changed = true end
  end
  return changed
end

--- Everything 1.x's loader did at boot, plus the 1.3 migrations. Returns { playlists=bool, tracks=bool, tokens=bool }.
function ops.normalise(lib)
  local changed = { playlists = false, tracks = false, tokens = false }
  for uid in pairs(lib.tokens) do
    if not is_uid(uid) then lib.tokens[uid] = nil changed.tokens = true end
  end
  for id, p in pairs(lib.playlists) do
    p.tracks = p.tracks or {}
    if p.star == "Jooki.Flat.Dragon" then p.star = "Jooki.Flat" changed.playlists = true end
    if p.tagId and not is_jplay(p) then
      local tok = lib.tokens[p.tagId]
      local star = tok and tok.starId
      local taken = false
      if star then for oid, q in pairs(lib.playlists) do if oid ~= id and q.star == star then taken = true end end end
      if star and not taken then p.star = star end
      p.tagId = nil
      changed.playlists = true
    end
    if id == TRASH and (p.star or p.tagId or p.audiobook) then p.star, p.tagId, p.audiobook = nil, nil, nil changed.playlists = true end
    -- a track list that names unknown tracks is repaired
    local kept = {}
    for _, t in ipairs(p.tracks) do if lib.tracks[t] then kept[#kept + 1] = t end end
    if #kept ~= #p.tracks then p.tracks = kept changed.playlists = true end
  end
  if ops.drop_orphan_streams(lib) then changed.tracks = true end
  if ops.rebuild_trash(lib) then changed.playlists = true end
  return changed
end

-- ------------------------------------------------------------------ playlists
local function unique_id(lib, prefix, now)
  local base = prefix .. tostring(math.floor(now))
  local id, k = base, 0
  while lib.playlists[id] or lib.tracks[id] do k = k + 1 id = base .. "_" .. k end
  return id
end

local function clean_title(t, max)
  if type(t) ~= "string" then return nil end
  t = trim(t)
  if t == "" then return nil end
  return t:sub(1, max or 100)
end

--- Link a character to a playlist: one playlist per character, always.
function ops.link_star(lib, id, star)
  local p = lib.playlists[id]
  if not p then return nil, { code = "not_found", field = "id", message = "unknown playlist" } end
  if is_jplay(p) or id == TRASH then return nil, { code = "read_only", field = "id", message = "this playlist cannot be linked" } end
  if not is_star(star) then return nil, { code = "invalid_argument", field = "star", message = "invalid character" } end
  for oid, q in pairs(lib.playlists) do
    if oid ~= id and (q.star == star or (q.tagId and lib.tokens[q.tagId] and lib.tokens[q.tagId].starId == star)) then
      q.star, q.tagId = nil, nil
    end
  end
  p.star, p.tagId = star, nil
  return true
end

function ops.unlink(lib, id)
  local p = lib.playlists[id]
  if not p then return nil, { code = "not_found", field = "id", message = "unknown playlist" } end
  p.star, p.tagId = nil, nil
  return true
end

function ops.playlist_new(lib, args, now)
  args = args or {}
  local id = unique_id(lib, "user_", now)
  lib.playlists[id] = { title = clean_title(args.title) or "Untitled Playlist", tracks = {}, audiobook = args.audiobook == true or nil }
  if args.star ~= nil then
    local ok, err = ops.link_star(lib, id, args.star)
    if not ok then lib.playlists[id] = nil return nil, err end
  end
  return id
end

function ops.playlist_delete(lib, id)
  if id == TRASH or id == SYSTEM then return nil, { code = "read_only", field = "id", message = "this playlist cannot be deleted" } end
  local p = lib.playlists[id]
  if not p then return nil, { code = "not_found", field = "id", message = "unknown playlist" } end
  if is_jplay(p) then return nil, { code = "read_only", field = "id", message = "Jooki Play playlist" } end
  lib.playlists[id] = nil
  ops.drop_orphan_streams(lib)
  ops.rebuild_trash(lib)
  return true
end

function ops.playlist_add_track(lib, id, track_id)
  if id == TRASH then return nil, { code = "read_only", field = "id", message = "this playlist cannot be changed" } end
  local p = lib.playlists[id]
  if not p then return nil, { code = "not_found", field = "id", message = "unknown playlist" } end
  if not lib.tracks[track_id] then return nil, { code = "not_found", field = "trackId", message = "unknown track" } end
  if is_jplay(p) then return nil, { code = "read_only", field = "id", message = "this playlist cannot be changed" } end
  table.insert(p.tracks, track_id)
  ops.rebuild_trash(lib)
  return true
end

function ops.playlist_add_stream(lib, id, title, url, now)
  if id == TRASH then return nil, { code = "read_only", field = "id", message = "this playlist cannot be changed" } end
  local p = lib.playlists[id]
  if not p then return nil, { code = "not_found", field = "id", message = "unknown playlist" } end
  if is_jplay(p) then return nil, { code = "read_only", field = "id", message = "this playlist cannot be changed" } end
  if not is_url(url) then return nil, { code = "invalid_argument", field = "url", message = "invalid stream url" } end
  local tid = unique_id(lib, "stream_", now)
  lib.tracks[tid] = { title = (clean_title(title, 200) or url), filename = url, isUrl = true }
  table.insert(p.tracks, tid)
  return tid
end

--- Update title / character / audiobook / track order. Returns true, { removed_files = {...} }.
function ops.playlist_update(lib, args)
  local id = args.id
  if id == TRASH and (args.title ~= nil or args.star ~= nil or args.audiobook ~= nil) then
    return nil, { code = "read_only", field = "id", message = "TRASH_READONLY" }
  end
  local p = lib.playlists[id]
  if not p and id == TRASH then p = { title = TRASH_TITLE, tracks = {} } end   -- "Unused" may be empty right now
  if not p then return nil, { code = "not_found", field = "id", message = "unknown playlist" } end
  if is_jplay(p) then return nil, { code = "read_only", field = "id", message = "Jooki Play playlist" } end
  local removed_files = {}
  if args.title ~= nil then
    local t = clean_title(args.title)
    if not t then return nil, { code = "invalid_argument", field = "title", message = "empty title" } end
    p.title = t
  end
  if args.star == false or args.star == "" then
    ops.unlink(lib, id)
  elseif args.star ~= nil then
    local ok, err = ops.link_star(lib, id, args.star)
    if not ok then return nil, err end
  end
  if type(args.audiobook) == "boolean" then p.audiobook = args.audiobook or nil end
  if args.tracks ~= nil then
    if id == TRASH then
      -- the page removed tracks from "Unused": delete only files that are really unused
      local keep = {}
      for _, t in ipairs(args.tracks) do keep[t] = true end
      for _, t in ipairs(ops.unused(lib)) do
        if not keep[t] then
          local f = lib.tracks[t].filename
          lib.tracks[t] = nil
          if f then removed_files[#removed_files + 1] = f end
        end
      end
    else
      local valid = {}
      for _, t in ipairs(args.tracks) do if type(t) == "string" and lib.tracks[t] then valid[#valid + 1] = t end end
      p.tracks = valid
      ops.drop_orphan_streams(lib)
    end
    ops.rebuild_trash(lib)
  end
  return true, { removed_files = removed_files }
end

-- ------------------------------------------------------------------ tracks
function ops.track_add(lib, id, meta)
  if lib.tracks[id] then return nil, { code = "conflict", field = "id", message = "track exists" } end
  lib.tracks[id] = meta
  ops.rebuild_trash(lib)
  return true
end

--- Remove a track from every playlist and the library; returns its filename.
function ops.track_delete(lib, id)
  local t = lib.tracks[id]
  if not t then return nil, { code = "not_found", field = "id", message = "unknown track" } end
  for _, p in pairs(lib.playlists) do
    local kept = {}
    for _, x in ipairs(p.tracks or {}) do if x ~= id then kept[#kept + 1] = x end end
    p.tracks = kept
  end
  lib.tracks[id] = nil
  ops.rebuild_trash(lib)
  return t.filename
end

-- ------------------------------------------------------------------ tokens
--- A physical token was seen with a character code: learn or update it. Returns true when tokens changed.
function ops.learn(lib, uid, star)
  if not is_uid(uid) then return false end
  local tok = lib.tokens[uid]
  if not tok then tok = { seen = 0 } lib.tokens[uid] = tok end
  tok.seen = (tok.seen or 0) + 1
  if star and tok.starId ~= star then tok.starId = star end
  return true
end

function ops.token_edit(lib, uid, name, image)
  local tok = lib.tokens[uid]
  if not tok then return nil, { code = "not_found", field = "tagId", message = "unknown token" } end
  if name ~= nil then
    if name ~= false and type(name) ~= "string" then return nil, { code = "invalid_argument", field = "name", message = "invalid name" } end
    local n = name ~= false and clean_title(name, 60) or nil
    tok.name = n
  end
  if image ~= nil then
    if image == false or image == "" then tok.image = nil else tok.image = image end
  end
  return true
end

function ops.token_forget(lib, uid)
  if not lib.tokens[uid] then return nil, { code = "not_found", field = "tagId", message = "unknown token" } end
  lib.tokens[uid] = nil
  return true
end

-- ------------------------------------------------------------------ handlers
local function paths(doc)
  local dir = (doc.config and doc.config.data_dir) or "/jooki/external/jooki"
  return { playlists = dir .. "/playlists.json", tracks = dir .. "/tracks.json", tokens = dir .. "/tokens.json" }
end

local function writes(doc, lib, which)
  local p = paths(doc)
  local cmds = {}
  for _, name in ipairs({ "playlists", "tracks", "tokens" }) do
    if which == true or which[name] then
      cmds[#cmds + 1] = { kind = "files.write", path = p[name], doc = lib[name], version = 1 }
    end
  end
  return cmds
end

--- boot: event { type = "boot", library = { playlists, tracks, tokens } } from main (files already read).
function library.on_boot(doc, ev)
  local lib = deep_copy(ev.library or {})
  lib.playlists, lib.tracks, lib.tokens = lib.playlists or {}, lib.tracks or {}, lib.tokens or {}
  local changed = ops.normalise(lib)
  return { state = { library = lib }, commands = writes(doc, lib, changed) }
end

--- Run a mutating op on a copy of the library and return the handler result.
local function mutate(doc, which, fn)
  local lib = deep_copy(doc.library or { playlists = {}, tracks = {}, tokens = {} })
  local ok, extra = fn(lib)
  if not ok then return nil, extra end
  local cmds = writes(doc, lib, which)
  for _, f in ipairs((extra and extra.removed_files) or {}) do cmds[#cmds + 1] = { kind = "files.remove", path = f } end
  return { state = { library = lib }, commands = cmds }, nil, ok
end
library.mutate = mutate

local S = {}   -- schemas
S.id = { type = "string", minLength = 1, maxLength = 80 }
S.playlist_new = { type = "object", properties = { title = { type = "string", maxLength = 200 }, audiobook = { type = "boolean" }, star = { type = "string", maxLength = 64 } }, additionalProperties = false }
S.playlist_id = { type = "object", required = { "id" }, properties = { id = S.id }, additionalProperties = false }
S.playlist_update = { type = "object", required = { "id" }, additionalProperties = false,
  properties = { id = S.id, title = { type = "string", maxLength = 200 }, star = { type = { "string", "boolean" } }, audiobook = { type = "boolean" },
                 tracks = { type = "array", items = { type = "string" }, maxItems = 2000 } } }
S.add_track = { type = "object", required = { "id", "trackId" }, properties = { id = S.id, trackId = S.id }, additionalProperties = false }
S.add_stream = { type = "object", required = { "id", "url" }, properties = { id = S.id, url = { type = "string", maxLength = 500 }, title = { type = "string", maxLength = 200 } }, additionalProperties = false }
S.token_edit = { type = "object", required = { "tagId" }, properties = { tagId = { type = "string", pattern = "^%x+$", minLength = 14, maxLength = 14 }, name = { type = { "string", "boolean" }, maxLength = 100 }, image = { type = { "string", "boolean" } } }, additionalProperties = false }
S.token_id = { type = "object", required = { "tagId" }, properties = { tagId = { type = "string", minLength = 14, maxLength = 14 } }, additionalProperties = false }
library.schemas = S

--- Register the api commands and the boot handler.
function library.install(api, dispatch)
  dispatch.on("boot", "library", library.on_boot)
  -- a playlist created by another service (Spotify preset)
  dispatch.on("library.add_playlist", "library", function(doc, ev)
    return mutate(doc, { playlists = true }, function(lib)
      local id, err = ops.playlist_new(lib, { title = ev.title, star = ev.star }, ev.wall or ev.now or 0)
      if not id then return nil, err end
      lib.playlists[id].image, lib.playlists[id].spotify, lib.playlists[id].deezer = ev.image, ev.spotify, ev.deezer
      return id
    end)
  end)
  api.command("playlist.new", S.playlist_new, function(doc, p, ev)
    return mutate(doc, { playlists = true }, function(lib) return ops.playlist_new(lib, p, ev.wall or ev.now or 0) end)
  end)
  api.command("playlist.delete", S.playlist_id, function(doc, p)
    return mutate(doc, { playlists = true, tracks = true }, function(lib) return ops.playlist_delete(lib, p.id) end)
  end)
  api.command("playlist.update", S.playlist_update, function(doc, p)
    return mutate(doc, { playlists = true, tracks = true }, function(lib) return ops.playlist_update(lib, p) end)
  end)
  api.command("playlist.add_track", S.add_track, function(doc, p)
    return mutate(doc, { playlists = true }, function(lib) return ops.playlist_add_track(lib, p.id, p.trackId) end)
  end)
  api.command("playlist.add_stream", S.add_stream, function(doc, p, ev)
    return mutate(doc, { playlists = true, tracks = true }, function(lib) return ops.playlist_add_stream(lib, p.id, p.title, p.url, ev.wall or ev.now or 0) end)
  end)
  api.command("token.edit", S.token_edit, function(doc, p)
    return mutate(doc, { tokens = true }, function(lib) return ops.token_edit(lib, p.tagId, p.name, p.image) end)
  end)
  api.command("token.forget", S.token_id, function(doc, p)
    return mutate(doc, { tokens = true }, function(lib) return ops.token_forget(lib, p.tagId) end)
  end)
end

return library
