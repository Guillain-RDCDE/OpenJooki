-- services.util: the handful of pure helpers every service used to define for itself.
-- No requires, no state, no I/O: a deep copy, the `emit` command, the data paths read
-- from the document's configuration, a typed error, and "is something playing".
-- (kernel.state has its own deep_copy: the kernel must not depend on a service.)
local util = {}

--- Deep copy of a value (tables copied recursively, anything else returned as is).
function util.copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = util.copy(x) end
  return out
end

--- The command that queues an internal event for the next turn: { kind = "emit", event = { type = t, ... } }.
function util.emit(t, extra)
  local e = { type = t }
  for k, v in pairs(extra or {}) do e[k] = v end
  return { kind = "emit", event = e }
end

--- Where the family's files live, from the document's configuration (kernel.config data_dir).
function util.data_dir(doc) return (doc and doc.config and doc.config.data_dir) or "/jooki/external/jooki" end

--- The tmpfs scratch directory (kernel.config scratch_dir).
function util.scratch_dir(doc) return (doc and doc.config and doc.config.scratch_dir) or "/run/openjooki" end

--- The typed error a command answers with (docs/21 §8): { code, field, message }.
function util.err(code, field, message) return { code = code, field = field, message = message } end

--- Music is on its way out of the speaker, or about to be: state "playing" or "starting".
--- (A paused track is loaded but not playing: the few sites that count "paused" too say so themselves.)
function util.is_playing(doc)
  local s = doc and doc.playback and doc.playback.state
  return s == "playing" or s == "starting"
end

return util
