-- Minimal test runner for the core (Lua 5.1, no dependency).
-- A busted-compatible subset: describe / it / before_each, plus assertions.
--   lua5.1 core/spec/run.lua [spec files...]      (default: every *_spec.lua in core/spec)
local runner = {}
local results = { passed = 0, failed = 0, failures = {} }
local stack = {}
local before_hooks = {}

local function deep_equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not deep_equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function dump(v, depth)
  depth = depth or 0
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  if depth > 3 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. dump(v[k], depth + 1) end
  return "{" .. table.concat(parts, ", ") .. "}"
end

assert_eq = function(actual, expected, msg)
  if not deep_equal(actual, expected) then
    error((msg and msg .. ": " or "") .. "expected " .. dump(expected) .. " got " .. dump(actual), 2)
  end
end
assert_true = function(v, msg) if not v then error((msg or "expected truthy") .. " (got " .. dump(v) .. ")", 2) end end
assert_false = function(v, msg) if v then error((msg or "expected falsy") .. " (got " .. dump(v) .. ")", 2) end end
assert_nil = function(v, msg) if v ~= nil then error((msg or "expected nil") .. " (got " .. dump(v) .. ")", 2) end end
assert_error = function(fn, pattern)
  local ok, err = pcall(fn)
  if ok then error("expected an error", 2) end
  if pattern and not tostring(err):find(pattern) then error("error '" .. tostring(err) .. "' does not match '" .. pattern .. "'", 2) end
end
assert_match = function(s, pattern, msg)
  if type(s) ~= "string" or not s:find(pattern) then error((msg or "no match") .. ": " .. dump(s) .. " !~ " .. pattern, 2) end
end

function describe(name, fn)
  stack[#stack + 1] = name
  local saved = before_hooks
  before_hooks = { unpack(before_hooks) }
  fn()
  before_hooks = saved
  stack[#stack] = nil
end

function before_each(fn) before_hooks[#before_hooks + 1] = fn end

function it(name, fn)
  local full = table.concat(stack, " > ") .. " > " .. name
  local ok, err = pcall(function()
    for _, h in ipairs(before_hooks) do h() end
    fn()
  end)
  if ok then
    results.passed = results.passed + 1
    io.write("PASS ", full, "\n")
  else
    results.failed = results.failed + 1
    results.failures[#results.failures + 1] = full .. "\n      " .. tostring(err)
    io.write("FAIL ", full, "\n      ", tostring(err), "\n")
  end
end

function runner.main(files)
  if #files == 0 then
    local p = io.popen('ls core/spec/*_spec.lua 2>/dev/null')
    for line in p:lines() do files[#files + 1] = line end
    p:close()
  end
  table.sort(files)
  for _, f in ipairs(files) do
    local chunk, err = loadfile(f)
    if not chunk then
      results.failed = results.failed + 1
      results.failures[#results.failures + 1] = f .. ": " .. tostring(err)
      io.write("FAIL ", f, ": ", tostring(err), "\n")
    else
      local ok, e = pcall(chunk)
      if not ok then
        results.failed = results.failed + 1
        results.failures[#results.failures + 1] = f .. ": " .. tostring(e)
        io.write("FAIL ", f, ": ", tostring(e), "\n")
      end
    end
  end
  io.write(string.format("\n%d passed, %d failed\n", results.passed, results.failed))
  os.exit(results.failed == 0 and 0 or 1)
end

package.path = "./core/?.lua;./core/?/init.lua;" .. package.path
runner.main({ ... })
