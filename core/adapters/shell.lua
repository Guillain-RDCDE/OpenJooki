-- adapters.shell: named actions only, never a free command string (ADR-0008).
-- Each action lists its program and how its arguments are checked. Output is
-- read from a pipe; no temp file is ever written. A counter lets the budget
-- test see how many processes the core started.
local shell = {}

local function is_ssid(s) return type(s) == "string" and #s >= 1 and #s <= 32 and not s:find("[%c'\"\\]") end
local function is_lang(s) return type(s) == "string" and s:match("^[A-Z][A-Z]$") ~= nil end
local function is_path(s) return type(s) == "string" and s:sub(1, 1) == "/" and not s:find("[%c'\"\\]") and not s:find("%.%.") end
-- a network name: lower-case letters, digits, inner hyphens, 1-32 characters ("" = back to the factory name)
-- an SSH public key on one line: its type, the base64 blob, an optional plain comment
local function is_pubkey(s)
  if type(s) ~= "string" or #s > 1000 then return false end
  local kind, blob, rest = s:match("^(%S+) ([A-Za-z0-9+/]+=?=?)(.*)$")
  if not (kind == "ssh-ed25519" or kind == "ssh-rsa" or (kind and kind:match("^ecdsa%-sha2%-nistp%d+$"))) then return false end
  if #blob < 60 then return false end
  return rest == "" or rest:match("^ [%w@%.%-_]+$") ~= nil
end
shell.is_pubkey = is_pubkey
local function is_hostname(s) return type(s) == "string" and #s <= 32 and (s:match("^[a-z0-9]$") or s:match("^[a-z0-9][a-z0-9%-]*[a-z0-9]$")) ~= nil end

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
  -- the broker, when the core cannot reach it (adapters.broker_watch): started again only if it is not
  -- running, exactly as /etc/rcS.d/S58_mosquitto.sh starts it at boot
  broker_start   = { argv = function() return { "sh", "-c", [[
if ps 2>/dev/null | grep -q '[m]osquitto -c'; then echo running; exit 0; fi
rm -f /var/run/mosquitto.pid
# detached from our pipe: a daemon holding it would keep the core waiting for its output for good
/usr/sbin/mosquitto -c /etc/mosquitto/mosquitto.conf -d </dev/null >/dev/null 2>&1 && echo started || echo failed]] } end },
  poweroff       = { argv = function() return { "/sbin/poweroff" } end },
  reboot         = { argv = function() return { "/sbin/reboot" } end },
  -- the Wi-Fi watchdog's restart (services.network): never during an OpenJooki update
  watchdog_reboot = { argv = function() return { "sh", "-c", [[
if [ -e /tmp/oj-updating ]; then rm -f /data/openjooki/quiet_boot; echo updating; exit 0; fi
logger -t openjooki-core "warn network.watchdog: restarting the Jooki to bring the Wi-Fi back"
sync; sleep 1; /sbin/reboot]] } end, background = true },
  -- maintenance SSH (docs/adr/0007): a second dropbear on 2222 (the factory one on 22 keeps root off);
  -- turned off after an hour by the core. Killing targets only the 2222 instance, never port 22.
  -- The keys live on /data (kept across A/B updates, which rewrite /home): put back before dropbear starts.
  ssh_on         = { argv = function() return { "sh", "-c", [[
K=/data/openjooki/authorized_keys; H=/home/root/.ssh
if [ -s "$K" ]; then mkdir -p "$H" && chmod 700 "$H" && cp "$K" "$H/authorized_keys" && chmod 600 "$H/authorized_keys"; fi
dropbear -p 2222 -R >/dev/null 2>&1; echo on]] } end, background = true },
  -- a public key for the maintenance access (checked by the core: type, base64, comment), at most five kept
  ssh_key_add    = { argv = function(a) if not is_pubkey(a.key) then return nil, "bad key" end
                             return { "sh", "-c", [[
K=/data/openjooki/authorized_keys; H=/home/root/.ssh
mkdir -p /data/openjooki || exit 1
touch "$K"; grep -qxF "$1" "$K" || printf '%s\n' "$1" >> "$K"
tail -n 5 "$K" > "$K.tmp" && mv "$K.tmp" "$K" && chmod 600 "$K"
mkdir -p "$H" && chmod 700 "$H" && cp "$K" "$H/authorized_keys" && chmod 600 "$H/authorized_keys"
sync; echo ok]], "ssh_key_add", a.key } end },
  ssh_key_clear  = { argv = function() return { "sh", "-c", "rm -f /data/openjooki/authorized_keys /home/root/.ssh/authorized_keys; sync; echo ok" } end },
  ssh_off        = { argv = function() return { "sh", "-c",
                             "for p in $(ps 2>/dev/null | grep 'dropbear -p 2222' | grep -v grep | awk '{print $1}'); do kill $p 2>/dev/null; done; echo off" } end },
  -- MQTT on the LAN for home automation: flip the flag, then let the boot script rebuild the
  -- broker config and restart it (it adds/removes a LAN listener bound to the Wi-Fi IP, password required).
  mqtt_lan       = { argv = function(a) return { "sh", "-c", [[
if [ "$1" = "on" ]; then touch /data/openjooki/mqtt_lan; else rm -f /data/openjooki/mqtt_lan; fi
[ -x /etc/rcS.d/S57_oj-security.sh ] && /etc/rcS.d/S57_oj-security.sh >/dev/null 2>&1
echo ok]], "mqtt_lan", (a.on == true) and "on" or "off" } end, background = true },
  -- OpenJooki updates (docs/18): the Jooki itself fetches version.json / the installer from GitHub, in the background
  update_check   = { argv = function(a) if not is_path(a.out) then return nil, "bad path" end
                             return { "sh", "-c", [[
O="$1"; echo '{"pending":true}' > "$O"
if curl -fsSL --max-time 30 https://github.com/Guillain-RDCDE/OpenJooki/releases/latest/download/version.json -o "$O.tmp"; then mv "$O.tmp" "$O"; else echo '{"error":"offline"}' > "$O"; fi]], "update_check", a.out } end, background = true },
  update_start   = { argv = function(a) if not (is_path(a.status) and is_path(a.link)) then return nil, "bad path" end
                             return { "sh", "-c", [[
S="$1"; L="$2"; [ -e /tmp/oj-updating ] && exit 0; touch /tmp/oj-updating; : > "$S"; ln -sf "$S" "$L"
if curl -fsSL --max-time 60 https://guillain-rdcde.github.io/OpenJooki/o.sh -o /tmp/oj-o.sh; then sh /tmp/oj-o.sh; else echo '[openjooki] ERROR: cannot reach GitHub - nothing changed' >> "$S"; fi
rm -f /tmp/oj-updating]], "update_start", a.status, a.link } end, background = true },
  df             = { argv = function(a) if not is_path(a.dir) then return nil, "bad path" end return { "df", "-k", a.dir } end },
  -- the logs the original system piled up (docs/20): the Papertrail queue and the never-rotated file, once at boot
  log_cleanup    = { argv = function() return { "sh", "-c", [[
cd /jooki/external/logs/syslog-ng 2>/dev/null || exit 0
rm -f syslog-ng-0*.qf
if [ -f syslog-ng.log ]; then tail -n 3000 syslog-ng.log > syslog-ng.old.log; rm -f syslog-ng.log; fi
exit 0]] } end, background = true },
  -- what web_ctrl serves: /tmp/web_ctrl_dirs/{public,uploads,wifi_setup,deezer} rebuilt once at boot (1.x setupWebServer).
  -- In the background (0.8 s on the device, web_ctrl starts 5 s after the core): a failure goes to syslog itself.
  setup_web_dirs = { argv = function(a) if not is_path(a.data) then return nil, "bad path" end
                             return { "sh", "-c", [[
D="$1"; W=/tmp/web_ctrl_dirs
fail() { logger -t openjooki-core "error boot.web_dirs_failed"; exit 1; }
rm -f "$D"/uploads/upload_* 2>/dev/null
rm -rf "$W" && mkdir -p "$W/public" "$W/wifi_setup/setup" "$W/deezer" "$D/uploads" "$D/artwork" || fail
ln -s "$D/uploads" "$W/uploads" && ln -s "$D/artwork" "$W/public/artwork" || fail
for f in /jooki/app/www/public/*; do [ -e "$f" ] && ln -s "$f" "$W/public/"; done
for f in /jooki/app/www/wifi_setup/public/*; do [ -e "$f" ] && ln -s "$f" "$W/wifi_setup/setup/"; done
for f in /jooki/app/www/deezer/*; do [ -e "$f" ] && ln -s "$f" "$W/deezer/"; done
exit 0]], "setup_web_dirs", a.data } end, background = true },
  md5            = { argv = function(a) if not is_path(a.file) then return nil, "bad path" end return { "md5sum", a.file } end },
  -- the name chosen on the page: kept on /data (survives A/B updates), applied now; the boot script
  -- (ml-jooki-hostname.sh) applies it again at every start. /etc/hostname keeps the factory name (device id).
  set_name       = { argv = function(a) if not (a.name == "" or is_hostname(a.name)) then return nil, "bad name" end
                             return { "sh", "-c", [[
N="$1"; F=/data/openjooki/hostname
mkdir -p /data/openjooki || exit 1
if [ -z "$N" ]; then rm -f "$F"; N=$(cat /etc/hostname); else printf '%s\n' "$N" > "$F.tmp" && mv "$F.tmp" "$F" || exit 1; fi
sync; hostname "$N"]], "set_name", a.name } end },
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
