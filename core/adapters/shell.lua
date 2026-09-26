-- adapters.shell: named actions only, never a free command string (ADR-0008).
-- Each action lists its program and how its arguments are checked. Output is
-- read from a pipe; no temp file is ever written. A counter lets the budget
-- test see how many processes the core started.
local shell = {}

local function is_ssid(s) return type(s) == "string" and #s >= 1 and #s <= 32 and not s:find("[%c'\"\\]") end
local function is_lang(s) return type(s) == "string" and s:match("^[A-Z][A-Z]$") ~= nil end
local function is_path(s) return type(s) == "string" and s:sub(1, 1) == "/" and not s:find("[%c'\"\\]") and not s:find("%.%.") end

-- name -> { argv = function(args) -> list | nil, err ; background = bool }
shell.ACTIONS = {
  sync           = { argv = function() return { "sync" } end },
  probe_audio    = { argv = function(a) if not (is_path(a.file) and is_path(a.image) and is_path(a.out)) then return nil, "bad path" end
                             return { "/jooki/app/services/ml-audio-probe-wrapper.sh", a.file, a.image, a.out } end },
  artwork        = { argv = function(a) if not (is_path(a.file) and is_path(a.out)) then return nil, "bad path" end
                             return { "ffmpeg", "-loglevel", "error", "-i", a.file, "-f", "image2", "-sn", "-an", "-dn", "-vcodec", "copy", a.out } end },
  set_lang       = { argv = function(a) if not is_lang(a.lang) then return nil, "bad lang" end return { "/jooki/app/services/lang_set.sh", a.lang } end },
  toysafe_update = { argv = function() return { "/jooki/app/services/toy_safe_update.sh" } end },
  errorbeep      = { argv = function() return { "/jooki/app/services/errorbeep.sh" } end },
  speak_info     = { argv = function() return { "/jooki/app/services/speak_info.sh" } end, background = true },
  radio          = { argv = function(a) return { "/jooki/app/services/radio.sh", a.wifi and "true" or "false", a.bt and "true" or "false" } end },
  wifi_add       = { argv = function(a) if not is_ssid(a.ssid) then return nil, "bad ssid" end
                             if a.password ~= nil and not (type(a.password) == "string" and #a.password <= 63 and not a.password:find("[%c'\"\\]")) then return nil, "bad password" end
                             return { "/jooki/app/services/wifi_add_network.sh", "", a.ssid, a.password or "", a.lang or "EN" } end },
  power_overheat = { argv = function() return { "/jooki/app/services/power_overheat.sh" } end, background = true },
  factory_reset  = { argv = function() return { "/jooki/app/services/factory_reset.sh" } end },
  poweroff       = { argv = function() return { "/sbin/poweroff" } end },
  reboot         = { argv = function() return { "/sbin/reboot" } end },
  update_start   = { argv = function(a) if not is_path(a.script) then return nil, "bad path" end return { "sh", a.script } end, background = true },
  df             = { argv = function(a) if not is_path(a.dir) then return nil, "bad path" end return { "df", "-k", a.dir } end },
  md5            = { argv = function(a) if not is_path(a.file) then return nil, "bad path" end return { "md5sum", a.file } end },
}

shell.count = 0
local runner = nil     -- tests inject a fake runner(argv, background) -> output, rc

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function run(argv, background)
  local parts = {}
  for _, a in ipairs(argv) do parts[#parts + 1] = quote(a) end
  local cmd = table.concat(parts, " ") .. " 2>&1"
  if background then
    os.execute("(" .. cmd .. ") >/dev/null &")
    return "", 0
  end
  local p = io.popen(cmd, "r")
  if not p then return nil, -1 end
  local out = p:read("*a")
  local ok, _, code = p:close()
  return out, (ok == true and 0) or tonumber(code) or 1
end

--- Run a named action. Returns output, exit code | nil, reason.
function shell.run(name, args)
  local action = shell.ACTIONS[name]
  if not action then return nil, "unknown action: " .. tostring(name) end
  local argv, err = action.argv(args or {})
  if not argv then return nil, name .. ": " .. tostring(err) end
  shell.count = shell.count + 1
  return (runner or run)(argv, action.background == true)
end

function shell._set_runner(fn) runner = fn end
function shell._argv(name, args) local a = shell.ACTIONS[name]; return a and a.argv(args or {}) end

return shell
