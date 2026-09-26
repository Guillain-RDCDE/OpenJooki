-- api.schema: a small JSON-Schema-like validator, the subset we use:
--   type (object, array, string, integer, number, boolean), required,
--   properties, additionalProperties (false), items, enum, minimum, maximum,
--   minLength, maxLength, pattern (Lua pattern), minItems, maxItems.
-- validate(value, schema) -> true | false, field_path, message
local schema = {}

local function typeof(v)
  local t = type(v)
  if t == "number" then return math.floor(v) == v and "integer" or "number" end
  if t == "table" then
    -- an array is a table whose keys are 1..n (an empty table counts as both)
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n == 0 then return "empty" end
    return #v == n and "array" or "object"
  end
  return t
end

local function type_ok(actual, wanted)
  if wanted == actual then return true end
  if wanted == "number" and actual == "integer" then return true end
  if actual == "empty" and (wanted == "object" or wanted == "array") then return true end
  return false
end

local function check(v, s, path)
  if s.type then
    local actual = typeof(v)
    local wanted = s.type
    if type(wanted) == "string" then wanted = { wanted } end
    local ok = false
    for _, w in ipairs(wanted) do if type_ok(actual, w) then ok = true end end
    if not ok then return false, path, "expected " .. table.concat(wanted, "|") .. ", got " .. (actual == "empty" and "empty table" or actual) end
  end
  if s.enum then
    local found = false
    for _, e in ipairs(s.enum) do if e == v then found = true end end
    if not found then return false, path, "not one of the allowed values" end
  end
  if type(v) == "string" then
    if s.minLength and #v < s.minLength then return false, path, "too short" end
    if s.maxLength and #v > s.maxLength then return false, path, "too long" end
    if s.pattern and not v:find(s.pattern) then return false, path, "does not match the expected format" end
  elseif type(v) == "number" then
    if s.minimum and v < s.minimum then return false, path, "below minimum " .. s.minimum end
    if s.maximum and v > s.maximum then return false, path, "above maximum " .. s.maximum end
  elseif type(v) == "table" then
    local actual = typeof(v)
    if actual == "object" or (actual == "empty" and s.properties) then
      for _, r in ipairs(s.required or {}) do
        if v[r] == nil then return false, (path == "" and r or path .. "." .. r), "required" end
      end
      for k, sub in pairs(s.properties or {}) do
        if v[k] ~= nil then
          local ok, p, m = check(v[k], sub, path == "" and k or path .. "." .. k)
          if not ok then return false, p, m end
        end
      end
      if s.additionalProperties == false then
        for k in pairs(v) do
          if not (s.properties and s.properties[k]) then return false, (path == "" and tostring(k) or path .. "." .. tostring(k)), "unexpected field" end
        end
      end
    end
    if actual == "array" or (actual == "empty" and s.items) then
      if s.minItems and #v < s.minItems then return false, path, "too few items" end
      if s.maxItems and #v > s.maxItems then return false, path, "too many items" end
      if s.items then
        for i, item in ipairs(v) do
          local ok, p, m = check(item, s.items, path .. "[" .. i .. "]")
          if not ok then return false, p, m end
        end
      end
    end
  end
  return true
end

function schema.validate(value, s)
  return check(value, s, "")
end

schema.typeof = typeof
return schema
