-- services.playback.resume: where an audiobook starts again (the 1.3 rules), kept in resume.json.
-- Owns state.resume = { [playlist] = { id, pos, t } } (persisted as resume.json, 1.3 shape) and the
-- flag playback_int.resume_dirty: a position noted but not yet on disk, which the save timer (every
-- 60 s) and the shutdown flush write. The facade, services.playback, notes the positions the engine
-- reports (on_audio) with the helpers here and asks resume_for where an audiobook starts. The
-- working table (pb_of / st) is the facade's: reached at call time, since the facade requires this module.
local util = require("services.util")
local resume = {}

local BACK_PAUSE, BACK_TIMER, MIN_BACK = 15000, 60000, 5000
resume.BACK_PAUSE, resume.BACK_TIMER, resume.MIN_BACK = BACK_PAUSE, BACK_TIMER, MIN_BACK

local copy = util.copy
local function facade() return require("services.playback") end

local function resume_path(doc) return util.data_dir(doc) .. "/resume.json" end

function resume.write_resume(doc, saved)
  return { kind = "files.write", path = resume_path(doc), doc = saved, version = 1 }
end
local write_resume = resume.write_resume

-- ------------------------------------------------------------------ resume rules (1.3)
local function back_for(entry) return (entry and entry.t) and BACK_TIMER or BACK_PAUSE end

--- For an audiobook: the index and the position to start at, from resume.json.
function resume.resume_for(saved, playlist_id, tracks)
  local r = saved and saved[playlist_id]
  if not r then return nil end
  for i, t in ipairs(tracks) do
    if t == r.id then
      local ms = (tonumber(r.pos) or 0) - back_for(r)
      if ms >= MIN_BACK then return i, ms end
      return i, nil
    end
  end
  return nil
end

-- ------------------------------------------------------------------ resume bookkeeping
function resume.resume_copy(doc) return copy(doc.resume or {}) end
local resume_copy = resume.resume_copy

--- Notes the position of the audiobook playing; true when resume.json would change.
function resume.note_position(_, pb, saved, ms, from_timer)
  local now = pb.now
  if not (now and now.audiobook and now.service == "FILE") then return false end
  local r = saved[now.playlist]
  if r and r.id == now.track and math.abs((r.pos or 0) - ms) < 1000 and (r.t == true) == (from_timer == true) then return false end
  saved[now.playlist] = { id = now.track, pos = math.floor(ms), t = from_timer or nil }
  return true
end

--- The end of a chapter: the next one starts at 0; the end of the book goes back to chapter 1 (forgotten).
function resume.note_ended(saved, now, p)
  local next_id = p.tracks[now.index + 1]
  if next_id then saved[now.playlist] = { id = next_id, pos = 0 } else saved[now.playlist] = nil end
end

-- ------------------------------------------------------------------ boot / timers / api
--- Boot: resume.json, each entry checked (an id, a number, the timer mark), and the save timer.
function resume.on_boot(_, ev)
  local saved = {}
  for k, v in pairs(ev.resume or {}) do
    if type(v) == "table" and type(v.id) == "string" then saved[k] = { id = v.id, pos = tonumber(v.pos) or 0, t = v.t == true or nil } end
  end
  return { state = { resume = saved }, commands = { { kind = "timer.every", name = "playback.save", seconds = 60 } } }
end

--- Every 60 s (timer playback.save): an audiobook position noted since the last write goes to disk.
function resume.on_save(doc)
  local playback = facade()
  local pb = playback.pb_of(doc)
  if not pb.resume_dirty then return nil end
  pb.resume_dirty = nil
  return { state = playback.st(pb), commands = { write_resume(doc, doc.resume or {}) } }
end

--- The timer by name (the specs drive this one; the kernel routes the name itself).
function resume.on_timer(doc, ev)
  if ev.name ~= "playback.save" then return nil end
  return resume.on_save(doc)
end

function resume.on_resume_reset(doc, playlist_id)
  local saved = resume_copy(doc)
  saved[playlist_id] = nil
  return { state = { resume = saved }, commands = { write_resume(doc, saved) } }
end

function resume.on_shutdown(doc)
  local pb = facade().pb_of(doc)
  if not pb.resume_dirty then return nil end
  return { commands = { write_resume(doc, doc.resume or {}) } }
end

local S = {}
S.playlist = { type = "object", required = { "playlist" }, properties = { playlist = { type = "string", minLength = 1 } }, additionalProperties = false }
resume.schemas = S

function resume.install(api, dispatch)
  dispatch.on("boot", "playback.resume", resume.on_boot)
  dispatch.on_timer("playback.save", "playback.resume", resume.on_save)
  dispatch.on("host.terminating", "playback.resume", resume.on_shutdown)
  api.command("playback.resume_reset", S.playlist, function(doc, p) return resume.on_resume_reset(doc, p.playlist) end)
end

return resume
