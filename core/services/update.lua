-- services.update: check for / start an OpenJooki update from the page (docs/18).
-- The work happens in background shell actions (curl to GitHub, then the same
-- o.sh as the phone installer); the page reads /oj-latest.json and
-- /oj-status.txt from the web server's public directory, exactly as in 1.2/1.3.
-- The two addresses come from the configuration (the bench serves its own).
local update = {}

local STATUS = "/jooki/app/www/public/openjooki-status.txt"

local function cfg(doc, key, default) return (doc and doc.config and doc.config[key]) or default end
local function public(doc) return cfg(doc, "web_public_dir", "/tmp/web_ctrl_dirs/public") end

function update.on_check(doc)
  return { commands = { { kind = "shell", action = "update_check",
                          args = { out = public(doc) .. "/oj-latest.json", url = cfg(doc, "update_manifest_url") } },
                        { kind = "log", level = "info", key = "update.check" } } }
end

function update.on_start(doc)
  return { commands = { { kind = "shell", action = "update_start",
                          args = { status = STATUS, link = public(doc) .. "/oj-status.txt", url = cfg(doc, "update_script_url") } },
                        { kind = "log", level = "info", key = "update.start" } } }
end

-- The Wi-Fi chip firmware on trial (docs/32): a background shell action asks oj-esp32-trial and
-- writes its answer to /oj-chip.txt for the page (the state, then the step: idle, downloading,
-- checking, restarting, refused, unavailable). Trying downloads the package from GitHub; trying
-- and going back restart the Jooki, which writes the chip at the start.
local function chip(op)
  return function(doc)
    return { commands = { { kind = "shell", action = "chip_trial",
                            args = { op = op, out = public(doc) .. "/oj-chip.txt", url = cfg(doc, "chip_package_url") } },
                          { kind = "log", level = "info", key = "update.chip_" .. op } } }
  end
end
update.on_chip_status, update.on_chip_try, update.on_chip_back = chip("status"), chip("try"), chip("back")

-- Since 2.5.17 the new chip firmware is for every Jooki (#51): chip_auto_s after starting, once the
-- Jooki is online and plays nothing, the "auto" action takes it by itself. That action does nothing on
-- a Jooki whose parent went back to the original, after a trial that failed, or once it already tried
-- this package (it remembers it on /data); a Jooki with an older accepted package gets the newer one.
-- Trying restarts the Jooki: never while music plays or is paused, it then looks again 10 minutes later.
local AUTO_RETRY_S = 600
local function busy(doc)
  local s = (doc.playback or {}).state
  return s == "playing" or s == "starting" or s == "paused"
end
local function online(doc)
  local n = doc.net or {}
  return n.connected and type(n.ip) == "string" and n.ip ~= "" and n.route ~= false
end
function update.on_boot(doc)
  local s = tonumber(cfg(doc, "chip_auto_s", 0)) or 0
  if s <= 0 then return nil end
  return { commands = { { kind = "timer.once", name = "update.chip_auto", seconds = s } } }
end
function update.on_chip_auto(doc)
  if busy(doc) or not online(doc) then
    return { commands = { { kind = "timer.once", name = "update.chip_auto", seconds = AUTO_RETRY_S } } }
  end
  return chip("auto")(doc)
end

function update.install(api, dispatch)
  dispatch.on("update.check", "update", update.on_check)
  dispatch.on("update.start", "update", update.on_start)
  api.command("update.check", nil, update.on_check)
  api.command("update.start", nil, update.on_start)
  dispatch.on("boot", "update", update.on_boot)
  dispatch.on_timer("update.chip_auto", "update", update.on_chip_auto)
  for _, op in ipairs({ "status", "try", "back" }) do
    dispatch.on("chip." .. op, "update", update["on_chip_" .. op])
    api.command("chip." .. op, nil, update["on_chip_" .. op])
  end
end

return update
