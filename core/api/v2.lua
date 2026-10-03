-- api.v2: the contract with the page (ADR-0005), version 2.
-- Topics:  page -> Jooki   /j/web/v2/cmd      {"v":2,"id":"...","type":"...","payload":{...},"code":"1234"?}
--                          (code: the parent code, required by the protected commands when one is set)
--          Jooki -> page   /j/web/v2/reply    {"v":2,"id":"...","ok":true} | {..."ok":false,"error":{code,field,message}}
--                          /j/web/v2/state    full: {"v":2,"rev":n,"full":true,"state":{...}}  patch: {"v":2,"rev":n,"patch":{...}}
--                          /j/web/v2/event    {"v":2,"type":"...","payload":{...}}
-- This module translates bus messages into events, validates envelopes and
-- payloads, and turns handler results into replies. Commands are registered
-- by services with api.command(type, schema, fn). The state it publishes leaves
-- out the private sub-trees (api.published).
local json = require("vendor.json")
local schema = require("api.schema")
local api = {}

api.TOPIC_CMD, api.TOPIC_REPLY, api.TOPIC_STATE, api.TOPIC_EVENT =
  "/j/web/v2/cmd", "/j/web/v2/reply", "/j/web/v2/state", "/j/web/v2/event"

local ENVELOPE = {
  type = "object", required = { "v", "type" },
  properties = { v = { type = "integer", enum = { 2 } }, id = { type = "string", maxLength = 64 },
                 type = { type = "string", pattern = "^[a-z_]+%.[a-z_]+$" }, payload = { type = "object" },
                 code = { type = "string", maxLength = 8 } },
}

local commands = {}     -- type -> { schema, fn }
local guard = nil       -- fn(type, code) -> nil | error{code,field,message}: asked before any command runs

function api.reset() commands = {}; guard = nil end

--- The gate every command passes first (the parent code, services.security.gate).
function api.set_guard(fn) guard = fn end

--- Register a command: fn(doc, payload, event) -> result table (as a handler) | nil, error{code,field,message}
function api.command(ctype, payload_schema, fn)
  commands[ctype] = { schema = payload_schema, fn = fn }
end

function api.commands()
  local out = {}
  for k in pairs(commands) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function api.schema_of(ctype) return commands[ctype] and commands[ctype].schema end

local function reply(id, ok, err)
  local r = { v = 2, id = id, ok = ok }
  if err then r.error = err end
  return { kind = "bus.publish", topic = api.TOPIC_REPLY, payload = r }
end

--- Bus message -> event (nil when the topic is not ours).
function api.translate(topic, payload)
  if topic ~= api.TOPIC_CMD then return nil end
  return { type = "api.cmd", raw = payload }
end

--- The handler for "api.cmd" events: validate, run the command, reply.
function api.handle(doc, event)
  local ok, msg = pcall(json.decode, event.raw)
  if not ok or type(msg) ~= "table" then
    return { commands = { reply(nil, false, { code = "invalid_argument", field = "", message = "not a JSON object" }) } }
  end
  local id = type(msg.id) == "string" and msg.id or nil
  local eok, efield, emsg = schema.validate(msg, ENVELOPE)
  if not eok then
    return { commands = { reply(id, false, { code = "invalid_argument", field = efield, message = emsg }) } }
  end
  local cmd = commands[msg.type]
  if not cmd then
    return { commands = { reply(id, false, { code = "not_found", field = "type", message = "unknown command " .. msg.type }) } }
  end
  local gerr = guard and guard(msg.type, msg.code)
  if gerr then
    return { commands = { reply(id, false, gerr) } }
  end
  local payload = msg.payload or {}
  if cmd.schema then
    local pok, pfield, pmsg = schema.validate(payload, cmd.schema)
    if not pok then
      return { commands = { reply(id, false, { code = "invalid_argument", field = "payload." .. pfield, message = pmsg }) } }
    end
  end
  local result, err = cmd.fn(doc, payload, event)
  if err then
    return { commands = { reply(id, false, { code = err.code or "internal", field = err.field or "", message = err.message or "" }) } }
  end
  result = result or {}
  result.commands = result.commands or {}
  table.insert(result.commands, reply(id, true))
  return result
end

-- Sub-trees that stay on the Jooki: the kernel's configuration, the services' own bookkeeping
-- (activity: the last press, system: the sound files, and every `<module>_int`). The page sees the rest.
local PRIVATE = { config = true, activity = true, system = true }
function api.published(key) return key ~= "rev" and not PRIVATE[key] and not tostring(key):match("_int$") end

--- State publication: full or patch, as commands for the kernel. A change to private keys only
--- still goes out as an empty patch, so the page sees no gap in `rev` (it would ask for a full state).
function api.publisher(doc, dirty_keys, full)
  if full then
    local copy = {}
    for k, v in pairs(doc) do if api.published(k) then copy[k] = v end end
    return { { kind = "bus.publish", topic = api.TOPIC_STATE, payload = { v = 2, rev = doc.rev, full = true, state = copy } } }
  end
  local patch = {}
  for _, k in ipairs(dirty_keys) do if api.published(k) then patch[k] = doc[k] end end
  return { { kind = "bus.publish", topic = api.TOPIC_STATE, payload = { v = 2, rev = doc.rev, patch = patch } } }
end

function api.event(etype, payload)
  return { kind = "bus.publish", topic = api.TOPIC_EVENT, payload = { v = 2, type = etype, payload = payload or {} } }
end

--- Built-in commands.
function api.install_builtin(version)
  api.command("state.get", nil, function(doc)
    return { commands = api.publisher(doc, {}, true) }
  end)
  api.command("core.ping", nil, function() return {} end)
  api.command("core.version", nil, function()
    return { commands = { api.event("core.version", { core = version or "dev" }) } }
  end)
end

return api
