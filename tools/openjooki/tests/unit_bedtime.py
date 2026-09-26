"""Unit tests of the bedtime module (ojbed) alone, under Lua 5.1, with a fake clock.
Only OpenJooki's own code is run here (no Jooki program needed):  python3 unit_bedtime.py"""
import os, subprocess, sys, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import lua_patches as L

HARNESS = r"""
local UP, UTC = 1000, {year=2026,month=1,day=15,hour=19,min=30,sec=0}
local real_date = os.date
os.date = function(f, ...) if f == '!*t' then local c = {} for k, v in pairs(UTC) do c[k] = v end return c end return real_date(f, ...) end
local VOL, PAUSED, PLAYING, SEEK, PUB, WRITES = {}, 0, false, nil, 0, {}
package.preload['log'] = function() local l = {} function l.info() end function l.error(...) print('LOGERR', ...) end function l.warn() end return l end
package.preload['sys'] = function() return {exists = function() return false end} end
package.preload['syscmd'] = function() return {uptime = function() return UP end} end
package.preload['jsondb'] = function() return {markDirty = function() end, write = function(p, t) WRITES[p] = t return true end, read = function() return nil end} end
package.preload['audio'] = function()
  return {isPlaying = function() return PLAYING end, isStarting = function() return false end,
          pause = function() PAUSED = PAUSED + 1 PLAYING = false end, updateLeds = function() end,
          on = {do_seek = function(m) SEEK = m.position_ms end}}
end
__OJBED__
local B = require'ojbed'
local KNOB = 97
local acfg = {syncVol = function() table.insert(VOL, B.vol(KNOB)) end}
local state = {audio = {nowPlaying = {}, playback = {}}}
local cat = {playlists = {pl = {tracks = {'a', 'b', 'c'}}, other = {tracks = {'x'}}}}
local fails, n = 0, 0
local function ok(name, c, info) n = n + 1 if not c then fails = fails + 1 print('FAIL ' .. name .. '  -> ' .. tostring(info)) else print('PASS ' .. name) end end
local function at(y, mo, d, h, mi) UTC = {year=y,month=mo,day=d,hour=h,min=mi,sec=0} end
local function lastvol() return VOL[#VOL] end

-- time zone: Paris = UTC+1, +2 in summer (EU rule: last Sunday of March / October at 01:00 UTC)
B.init(state, function() PUB = PUB + 1 end, acfg, cat)
at(2026,1,15,19,30); ok('U1 winter: 19:30 UTC = 20:30 Paris', B.localMinutes() == 20*60+30, B.localMinutes())
at(2026,7,15,18,30); ok('U1 summer: 18:30 UTC = 20:30 Paris', B.localMinutes() == 20*60+30, B.localMinutes())
at(2026,3,29,0,59); ok('U2 spring change: 00:59 UTC = 01:59', B.localMinutes() == 119, B.localMinutes())
at(2026,3,29,1,0);  ok('U2 spring change: 01:00 UTC = 03:00', B.localMinutes() == 180, B.localMinutes())
at(2026,10,25,0,59); ok('U2 autumn change: 00:59 UTC = 02:59', B.localMinutes() == 179, B.localMinutes())
at(2026,10,25,1,0);  ok('U2 autumn change: 01:00 UTC = 02:00', B.localMinutes() == 120, B.localMinutes())
at(2027,3,28,1,0);  ok('U2 2027 spring change (28 March)', B.localMinutes() == 180, B.localMinutes())
at(1970,1,1,0,5);   ok('U3 clock not set: never night', B.localMinutes() == nil and B.isNight() == false)
-- default window 20:00-07:00 (Paris)
local function night(h, m) at(2026,1,15,(h - 1) % 24, m) return B.isNight() end
ok('U4 19:59 is not night', night(19,59) == false)
ok('U4 20:00 is night', night(20,0) == true)
ok('U4 03:00 is night', night(3,0) == true)
ok('U4 06:59 is night', night(6,59) == true)
ok('U4 07:00 is not night', night(7,0) == false)
-- settings: validation + same-day window
ok('U5 bad time refused', B.set({start = '25:00'}) == false)
ok('U5 bad volume refused', B.set({maxvol = 3}) == false)
ok('U5 bad type refused', B.set({enabled = 'yes'}) == false)
ok('U5 unknown time zone rule refused', B.set({tzdst = 'US'}) == false)
ok('U5 valid settings accepted', B.set({start = '13:00', stop = '15:30', tzdst = 'none', tzbase = 0}) == true)
at(2026,1,15,14,0); ok('U5 inside a same-day window', B.isNight() == true)
at(2026,1,15,15,30); ok('U5 end of a same-day window', B.isNight() == false)
B.set({enabled = false}); at(2026,1,15,14,0); ok('U5 disabled: never night', B.isNight() == false)
ok('U5 settings saved to bedtime.json', WRITES['/jooki/external/jooki/bedtime.json'] and WRITES['/jooki/external/jooki/bedtime.json'].enabled == false)
-- volume limit at night (knob at 97)
B.set({enabled = true, maxvol = 30})
ok('U6 night: knob 97 -> 30', lastvol() == 30, lastvol())
UP = UP + 20; at(2026,1,15,16,0); B.tick(UP)
ok('U6 day: knob 97 -> 97', lastvol() == 97, lastvol())
-- sleep timer: 90 s, fade over the last 30 s, then pause and volume back
PLAYING = true; state.audio.playback.state = 'PLAYING'
B.onSleep({seconds = 90})
ok('U7 timer published', state.bedtime.sleep and state.bedtime.sleep.remaining == 90 and state.bedtime.sleep.mode == 'time', state.bedtime.sleep and state.bedtime.sleep.remaining)
UP = UP + 50; B.tick(UP); ok('U7 no fade 40 s before the end', lastvol() == 97, lastvol())
UP = UP + 25; B.tick(UP); ok('U7 fading 15 s before the end', lastvol() < 60 and lastvol() > 30, lastvol())
UP = UP + 14; B.tick(UP); ok('U7 almost silent 1 s before the end', lastvol() <= 5, lastvol())
UP = UP + 1; B.tick(UP); ok('U7 paused at the end', PAUSED == 1 and not state.bedtime.sleep)
ok('U7 still silent while pausing', lastvol() <= 5, lastvol())
UP = UP + 0.5; B.tick(UP); ok('U7 volume back once paused', lastvol() == 97, lastvol())
-- cancel restores at once
PLAYING = true; B.onSleep({minutes = 1}); UP = UP + 50; B.tick(UP)
ok('U8 fading before cancel', lastvol() < 97, lastvol())
B.onSleep({cancel = true}); ok('U8 cancel: volume back, no pause', lastvol() == 97 and PAUSED == 1 and not state.bedtime.sleep)
ok('U8 invalid duration refused', B.onSleep({minutes = 0}) == false and B.onSleep({}) == false)
-- end of chapter: fade on the last 20 s, stop instead of next track
B.onSleep({mode = 'track'})
state.audio.nowPlaying.duration_ms = 300000; state.audio.playback.position_ms = 290000; B.tick(UP)
ok('U9 end-of-chapter fade', lastvol() < 60, lastvol())
ok('U9 end of chapter stops', B.onEnded() == true and not state.bedtime.sleep and lastvol() == 97)
ok('U9 no timer: next track as usual', B.onEnded() == false)
-- automatic timer at night
at(2026,1,15,14,0); UP = UP + 20; B.tick(UP)
B.onState('PLAYING')
ok('U10 night: playback gets the automatic timer', state.bedtime.sleep and state.bedtime.sleep.auto == true and state.bedtime.sleep.total == 1200, state.bedtime.sleep and state.bedtime.sleep.total)
B.onSleep({cancel = true})
at(2026,1,15,16,0); UP = UP + 20; B.tick(UP); B.onState('PLAYING')
ok('U10 day: no automatic timer', not state.bedtime.sleep)
-- audiobook resume
local np = {audiobook = true, service = 'FILE', playlistId = 'pl', trackId = 'b'}
B.onPos(np, 125000)
local i, ms = B.resumeFor('pl', cat.playlists.pl.tracks)
ok('U11 resumes chapter 2, 15 s earlier', i == 2 and ms == 110000, tostring(i) .. ' ' .. tostring(ms))
B.onPos(np, 12000); i, ms = B.resumeFor('pl', cat.playlists.pl.tracks)
ok('U11 near the chapter start: from the start of the chapter', i == 2 and ms == nil)
B.onPos({audiobook = false, service = 'FILE', playlistId = 'other', trackId = 'x'}, 50000)
ok('U11 music playlists are not tracked', B.resumeFor('other', {'x'}) == nil)
state.audio.nowPlaying = np; B.onState('PAUSED')
ok('U12 saved when paused', WRITES['/jooki/external/jooki/resume.json'] and WRITES['/jooki/external/jooki/resume.json'].pl.id == 'b')
B.onState('ENDED'); i = B.resumeFor('pl', cat.playlists.pl.tracks)
ok('U13 chapter finished: next time starts at chapter 3', i == 3, i)
np.trackId = 'c'; B.onState('ENDED')
ok('U13 book finished: next time starts from the beginning', B.resumeFor('pl', cat.playlists.pl.tracks) == nil)
B.onPos(np, 60000); state.audio.nowPlaying = {audiobook = true, service = 'FILE', playlistId = 'pl', trackId = 'c', resume_ms = 45000}
B.onState('STARTING'); ok('U14 starting a resumed chapter keeps the saved position', select(2, B.resumeFor('pl', cat.playlists.pl.tracks)) == 45000)
B.onSleep({cancel = true}); at(2026,1,15,16,0); UP = UP + 20; B.tick(UP)
B.onState('PLAYING'); ok('U14 seek to the saved position once playing', SEEK == 45000 and state.audio.nowPlaying.resume_ms == nil, SEEK)
cat.playlists.pl = nil; B.saveResume(); ok('U15 deleted playlist forgotten', B.resumeFor('pl', {'c'}) == nil)
B.onResumeReset({playlistId = 'other'}); ok('U15 reset from the page', true)
-- lights
at(2026,1,15,14,0); UP = UP + 20; B.tick(UP)
local c = B.led({200, 200, 200}); ok('U16 night: lights dimmed', c[1] == 10 and c[3] == 10, c[1])
c = B.led({0, 10, 200}); ok('U16 night: off stays off, faint stays visible', c[1] == 0 and c[2] == 1 and c[3] == 10)
B.set({dim = false}); ok('U16 dimming can be turned off', B.led({200, 200, 200})[1] == 200)
-- the Jooki stayed on: continue exactly after a short pause, 15 s back after a long one
at(2026,1,15,16,0); UP = UP + 20; B.tick(UP)
cat.playlists.bk = {tracks = {'k1', 'k2'}}
state.audio.nowPlaying = {audiobook = true, service = 'FILE', playlistId = 'bk', trackId = 'k1'}
state.audio.playback.position_ms = 200000
B.onPos(state.audio.nowPlaying, 200000)
SEEK = nil; B.onState('PAUSED'); UP = UP + 30; B.onState('PLAYING')
ok('U17 short pause: continues exactly', SEEK == nil, SEEK)
B.onState('PAUSED'); UP = UP + 120; B.onState('PLAYING')
ok('U17 long pause: 15 s back', SEEK == 185000, SEEK)
-- paused by the sleep timer: the faded minute is played again (60 s back)
SEEK = nil; PLAYING = true; B.onSleep({seconds = 30}); UP = UP + 31; B.tick(UP)
B.onState('PAUSED'); UP = UP + 0.5; B.tick(UP)
i, ms = B.resumeFor('bk', cat.playlists.bk.tracks)
ok('U18 after the timer, next start is 60 s back', i == 1 and ms == 140000, tostring(i) .. ' ' .. tostring(ms))
UP = UP + 3600; B.onState('PLAYING')
ok('U18 continue after the timer: 60 s back', SEEK == 140000, SEEK)
B.onPos(state.audio.nowPlaying, 150000); i, ms = B.resumeFor('bk', cat.playlists.bk.tracks)
ok('U18 playing again clears the timer mark', ms == 135000, ms)
print(string.format('\n%d/%d passed', n - fails, n))
os.exit(fails == 0 and 0 or 1)
"""

src = HARNESS.replace("__OJBED__", L.OJBED_LUA)
with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
    f.write(src)
r = subprocess.run(["lua5.1", f.name])
os.unlink(f.name)
sys.exit(r.returncode)
