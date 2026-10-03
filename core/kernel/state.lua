-- kernel.state: the one state document.
-- Modules own sub-trees (state.doc.playback, state.doc.library, ...). They
-- never write into it directly: a handler returns a new value for its
-- sub-tree, and the kernel applies it here. Every applied change bumps `rev`
-- and tells which top-level keys changed (the loop collects them, so that the
-- api publishes a patch instead of the whole document).
local state = {}

local doc = { rev = 0 }

function state.reset(initial)
  doc = { rev = 0 }
  for k, v in pairs(initial or {}) do doc[k] = v end
end

function state.doc() return doc end
function state.rev() return doc.rev end
function state.get(key) return doc[key] end

local function deep_equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not deep_equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

--- Replace one top-level sub-tree. Returns true when something changed.
function state.set(key, value)
  assert(key ~= "rev", "rev is managed by the kernel")
  if deep_equal(doc[key], value) then return false end
  doc[key] = value
  doc.rev = doc.rev + 1
  return true
end

--- Apply several sub-trees at once: { key = value, ... }. Returns the list of changed keys.
function state.apply(changes)
  local changed = {}
  local keys = {}
  for k in pairs(changes) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    if state.set(k, changes[k]) then changed[#changed + 1] = k end
  end
  return changed
end

--- Deep copy of the document, for a full publish or a test snapshot.
local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deep_copy(x) end
  return out
end
function state.snapshot() return deep_copy(doc) end
state.deep_copy = deep_copy

return state
