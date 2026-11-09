-- Native offline commands: fixed programs, typed arguments, background processes.
local adapter = {}
local function path(v) return type(v) == "string" and v:sub(1, 1) == "/" and not v:find("[%c]") and not v:find("..", 1, true) end
local function uri(v) return type(v) == "string" and #v == 39 and v:match("^spotify:playlist:%w+$") ~= nil end
function adapter.install(shell, config)
  local root, scratch = config.get("spotify_offline_root"), config.get("scratch_dir") .. "/spotify-offline"
  local binary, quota = config.get("spotify_offline_binary"), config.get("spotify_offline_quota_bytes")
  if not (path(root) and path(scratch) and path(binary) and type(quota) == "number" and (quota == 0 or quota >= 1048576) and quota == math.floor(quota)) then error("invalid offline configuration") end
  local function args(command, a)
    a = a or {}
    if command == "sync" or command == "remove" or command == "play" or command == "preview" then if not uri(a.uri) then return nil, "invalid Spotify playlist URI" end end
    local memory = command == "sync" and 16384 or (command == "play" and 12288 or 8192)
    -- LuaSocket descriptors survive exec on the device. A long-lived player must
    -- not retain the core's HTTP listener and prevent the next core from binding.
    local script = 'for offline_fd_path in /proc/self/fd/*; do offline_fd=${offline_fd_path##*/}; case "$offline_fd" in 0|1|2|*[!0-9]*) continue;; esac; eval "exec ${offline_fd}>&-"; done; ulimit -c 0; ulimit -d ' .. memory .. '; ulimit -v 65536; umask 077; mkdir -p "$1" "$2/tmp" || exit 1; export TMPDIR="$2/tmp"; shift 2; export RUST_LOG=off; exec "$@"'
    if command == "sync" then script = script:gsub('exec "%$@"', 'exec nice -n 15 "$@"') end
    local out = { "/bin/busybox", "sh", "-c", script, "offline", scratch, root .. "/store",
      binary, "-c", root .. "/config", "-C", root .. "/cache", "downloads", "managed",
      "--store", root .. "/store", "--catalog", scratch .. "/catalog.json", "--job", scratch .. "/job.json",
      "--quota-bytes", string.format("%.0f", quota) }
    if command == "sync" or command == "preview" or command == "activate-login" then
      if type(a.request) ~= "string" or #a.request > 64 or not a.request:match("^[%d%-]+$") then return nil, "invalid offline request" end
      out[#out + 1] = "--request"; out[#out + 1] = a.request
    end
    if command == "cancel-login" then
      if not a.request then return { "true" } end
      if type(a.request) ~= "string" or #a.request > 64 or not a.request:match("^[%d%-]+$") then return nil, "invalid offline request" end
      out[#out + 1] = "--request"; out[#out + 1] = a.request
    end
    out[#out + 1] = command
    if command == "activate-login" then out[#out + 1] = "--marker"; out[#out + 1] = scratch .. "/auth-request" end
    if a.uri then out[#out + 1] = a.uri end
    if command == "preview" then
      if type(a.offset) ~= "number" or a.offset < 0 or a.offset > 10000 or a.offset ~= math.floor(a.offset) then return nil, "invalid metadata offset" end
      for _, item in ipairs({ "--output", scratch .. "/preview-" .. a.uri:sub(18) .. ".json", "--offset", tostring(a.offset) }) do out[#out + 1] = item end
    end
    if command == "play" then
      if type(a.session) ~= "string" or #a.session > 64 or not a.session:match("^[%d%-]+$") then return nil, "invalid offline session" end
      if type(a.index) ~= "number" or a.index < 0 or a.index ~= math.floor(a.index) or a.index > 10000 then return nil, "invalid offline track index" end
      local prefix = scratch .. "/session-" .. a.session
      for _, x in ipairs({ "--session", a.session, "--control", prefix .. ".commands.json", "--status", prefix .. ".status.json", "--index", tostring(a.index) }) do out[#out + 1] = x end
      if a.resume then out[#out + 1] = "--resume" end
    end
    return out
  end
  shell.ACTIONS.offline_auth_cancel = { argv = function(a)
    return args("cancel-login", a)
  end, background = true }
  shell.ACTIONS.offline_auth_activate = { argv = function(a)
    return args("activate-login", a)
  end, background = true }
  for _, name in ipairs({ "catalog", "sync", "remove", "play", "forget", "preview" }) do
    local command = name
    shell.ACTIONS["offline_" .. command] = { argv = function(a) return args(command, a) end, background = true }
  end
end
return adapter
