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

function update.install(api, dispatch)
  dispatch.on("update.check", "update", update.on_check)
  dispatch.on("update.start", "update", update.on_start)
  api.command("update.check", nil, update.on_check)
  api.command("update.start", nil, update.on_start)
end

return update
