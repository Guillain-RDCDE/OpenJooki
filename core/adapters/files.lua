-- adapters.files: the only code that writes the family's data files.
-- JSON documents with a `_` metadata object ({version, sum}) kept compatible
-- with the 1.x format ({"_":{"version":1}, ...}).
--   read(path, min_version)   -> table (without `_`), version   | nil, reason
--   write(path, table, version) -> true | nil, reason
-- Write is atomic: <path>.tmp is written and closed, the previous file is
-- renamed to <path>.bak, then the temp file is renamed to <path>. A crash at
-- any point leaves either the old file, the .bak, or both readable.
-- Read falls back to .bak when the main file is missing or corrupt. An
-- Adler-32 sum of the body detects truncation cheaply.
local json = require("vendor.json")
local files = {}

local function adler32(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

local function read_all(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function parse(text, min_version)
  if not text or text == "" then return nil, "empty" end
  local ok, doc = pcall(json.decode, text)
  if not ok or type(doc) ~= "table" then return nil, "corrupt" end
  local meta = doc._
  if type(meta) ~= "table" or type(meta.version) ~= "number" then return nil, "no version" end
  if meta.version < (min_version or 1) then return nil, "version too low" end
  if meta.sum then
    -- the sum covers the body with `_` removed, encoded the way we encode it
    local copy = {}
    for k, v in pairs(doc) do if k ~= "_" then copy[k] = v end end
    if adler32(files.encode_body(copy)) ~= meta.sum then return nil, "bad sum" end
  end
  doc._ = nil
  return doc, meta.version
end

--- Deterministic encoding (objects with sorted keys at every level, arrays in
--- order) so the sum is the same whatever the table's insertion order.
local function is_array(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n > 0 and #t == n
end

local function encode_sorted(v)
  if type(v) ~= "table" then return json.encode(v) end
  if is_array(v) then
    local parts = {}
    for i = 1, #v do parts[i] = encode_sorted(v[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  if #keys == 0 then return "[]" end   -- rxi/json also encodes an empty table as []
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = json.encode(k) .. ":" .. encode_sorted(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

function files.encode_body(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = json.encode(k) .. ":" .. encode_sorted(t[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

function files.read(path, min_version)
  local doc, why = parse(read_all(path), min_version)
  if doc then return doc, why end
  local main_reason = why
  local bak, why2 = parse(read_all(path .. ".bak"), min_version)
  if bak then return bak, why2, "recovered from .bak (" .. main_reason .. ")" end
  return nil, main_reason
end

function files.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

function files.write(path, t, version)
  assert(type(t) == "table", "files.write expects a table")
  assert(t._ == nil, "the `_` metadata is managed by files.write")
  local body = files.encode_body(t)
  local text = '{"_":' .. json.encode({ version = version or 1, sum = adler32(body) }) .. "," .. body:sub(2)
  if body == "{}" then text = '{"_":' .. json.encode({ version = version or 1, sum = adler32(body) }) .. "}" end
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then return nil, "open: " .. tostring(err) end
  local ok, werr = f:write(text)
  local ok2 = f:close()
  if not ok or not ok2 then os.remove(tmp) return nil, "write: " .. tostring(werr) end
  if files.exists(path) then
    local mok, merr = os.rename(path, path .. ".bak")
    if not mok then os.remove(tmp) return nil, "backup: " .. tostring(merr) end
  end
  local rok, rerr = os.rename(tmp, path)
  if not rok then return nil, "rename: " .. tostring(rerr) end
  return true
end

function files.remove(path) return os.remove(path) end

function files.read_text(path) return read_all(path) end

function files.write_text(path, text)
  local f, err = io.open(path, "wb")
  if not f then return nil, tostring(err) end
  f:write(text)
  f:close()
  return true
end

--- exists, size (LuaFileSystem when present, a plain open otherwise).
function files.stat(path)
  local ok, lfs = pcall(require, "lfs")
  if ok and lfs then
    local a = lfs.attributes(path)
    if not a then return false, nil end
    return true, a.size
  end
  local f = io.open(path, "rb")
  if not f then return false, nil end
  local size = f:seek("end")
  f:close()
  return true, size
end

--- rename, then report the size of the result.
function files.rename(from, to)
  local ok, err = os.rename(from, to)
  if not ok then return nil, tostring(err) end
  local _, size = files.stat(to)
  return true, nil, size
end

--- Flags are empty files in /data/mode (the daemons and scripts read them).
files.FLAG_DIR = "/data/mode"
function files.flag(name, set)
  local path = files.FLAG_DIR .. "/" .. name
  if set then
    local ok, lfs = pcall(require, "lfs")
    if ok and lfs and not lfs.attributes(files.FLAG_DIR) then lfs.mkdir(files.FLAG_DIR) end
    return files.write_text(path, "")
  end
  os.remove(path)
  return true
end

files.adler32 = adler32
return files
