-- services.update: check for / start an OpenJooki update from the page (docs/18).
-- The work happens in background shell actions (curl to GitHub, then the same
-- o.sh as the phone installer); the page reads /oj-latest.json and
-- /oj-status.txt from web_ctrl, exactly as in 1.2/1.3.
local update = {}

local PUBLIC = "/tmp/web_ctrl_dirs/public"
local STATUS = "/jooki/app/www/public/openjooki-status.txt"

function update.on_check()
  return { commands = { { kind = "shell", action = "update_check", args = { out = PUBLIC .. "/oj-latest.json" } },
                        { kind = "log", level = "info", key = "update.check" } } }
end

function update.on_start()
  return { commands = { { kind = "shell", action = "update_start", args = { status = STATUS, link = PUBLIC .. "/oj-status.txt" } },
                        { kind = "log", level = "info", key = "update.start" } } }
end

function update.install(api, dispatch)
  dispatch.on("update.check", "update", update.on_check)
  dispatch.on("update.start", "update", update.on_start)
  api.command("update.check", nil, update.on_check)
  api.command("update.start", nil, update.on_start)
end

return update
