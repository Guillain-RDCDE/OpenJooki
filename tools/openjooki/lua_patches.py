# -*- coding: utf-8 -*-
"""OpenJooki — fixes for the Jooki v2 application logic (player.lib).

player.lib (on the device, /jooki/lib/player.lib) is Lua 5.1 source code,
zlib-compressed, with its first 2 bytes XOR-ed with its last 2 bytes.
This module decodes it, applies small targeted replacements (each one must
match exactly the expected number of times, otherwise NOTHING is applied),
and re-encodes it.  Only the fragments to change are listed here: the
original program is never distributed, it is patched in place on your own
Jooki.

Fixes (see docs/18-web-ui.md):
  tokens   : naming a token never steals its character's playlist; any token
             of a character plays that character's playlist (star-only links,
             old per-token links migrated at boot); renaming is idempotent (no
             more "No update required"), keeps the image, allows clearing;
             forgetting a token no longer unlinks its playlist; a playlist can
             be unlinked from its character.
  TRASH    : "Unused tracks" cannot be renamed/linked/deleted/filled; removing
             tracks from it only deletes files that are REALLY unused; it is
             kept up to date after every change, in a stable order.
  uploads  : a failed upload never deletes an existing file, never leaves a
             track without file; stale temp files cleaned at boot; clearer
             "unsupported type" errors; titles without ".mp3".
  robust   : a bad message can no longer crash the player (pcall), write
             errors are detected before rotating the database, unique ids,
             web radio validation, orphan radio tracks removed, stale resume
             position no longer makes a token beep, empty playlist plays the
             "empty" sound, "previous" works while paused, repeat/shuffle saved,
             dead-cloud curl calls time out.
  bedtime  : audiobooks resume at the saved chapter and position (survives a
             power-off), sleep timer with a gentle fade, night window with a
             volume limit, automatic timer and dimmed lights (docs/19-bedtime.md).
"""
import zlib

MARK_OLD = "_G._MINIFIED=true\n"
MARK_NEW = "_G._MINIFIED=true\n_G._OPENJOOKI_LUA='5'\n"
MAX_SIZE = 204800          # player binary decompresses into a 200 KiB buffer

def decode(blob):
    d = bytearray(blob)
    d[0] ^= d[-1]; d[1] ^= d[-2]
    return zlib.decompress(bytes(d)).decode("latin-1")

def encode(src):
    raw = src.encode("latin-1")
    if len(raw) >= MAX_SIZE:
        raise ValueError("patched source too big (%d >= %d)" % (len(raw), MAX_SIZE))
    c = bytearray(zlib.compress(raw, 9))
    c[0] ^= c[-1]; c[1] ^= c[-2]
    return bytes(c)

def is_patched(src):
    return "_G._OPENJOOKI_LUA=" in src

P = []
def patch(name, old, new, count=1):
    P.append((name, old, new, count))

patch("marker", MARK_OLD, MARK_NEW)

# ---------------------------------------------------------------- tokens
patch("tokenEdit idempotent, keep image, no star->tag conversion",
"""function e:tokenEdit(o)
local i=o.tagId
local e,n=self:token(i)
if n then return false,n end
if o.name==e.name and o.image==e.image then
return false,'No update required'
end
t.info('Updating:',e)
e.name=o.name
e.image=o.image
t.info('Updated:',e)
a.markDirty(self.tokens)
if not h(self.playlists,nil,i)then
local a,t=h(self.playlists,e.starId,nil)
if t then
self:updatePlaylistStar(e.starId,i,t)
end
end
return true
end""",
"""function e:tokenEdit(o)
local i=o.tagId
local e,n=self:token(i)
if n then return false,n end
local c=false
if o.name~=nil then
local m=o.name
if m~=false and type(m)~='string'then return false,'invalid name'end
if m==false then m=nil end
if m then
m=(m:gsub('^%s+',''))
m=(m:gsub('%s+$',''))
if m==''then m=nil elseif#m>60 then m=m:sub(1,60)end
end
if m~=e.name then e.name=m c=true end
end
if o.image~=nil then
local m=o.image
if m==false or m==''then m=nil end
if m~=e.image then e.image=m c=true end
end
if c then
t.info('EVT_TOKEN_EDIT',i,e)
a.markDirty(self.tokens)
end
return true
end""")

patch("tokenDelete keeps the character's playlist",
"""t.info('Deleting:',i)
self:maybeUnlinkStar(nil,e)
self.tokens[e]=nil""",
"""t.info('Deleting:',i)
self.tokens[e]=nil""")

patch("star-only playlist links",
"""function e:updatePlaylistStar(i,e,o)
if not(i or e)then
t.error('need starId or tagId')
return
end
if n(o)then return false,s end
self:maybeUnlinkStar(i,e)
o.star=i
o.tagId=e
if e then
o.star=nil
end
t.info('EVT_TOKEN_LINK',i,e,'to',o.title)
a.markDirty(self.playlists)
end""",
"""function e:updatePlaylistStar(i,e,o)
if n(o)then return false,s end
if e and not i then
local k=self.tokens[e]
i=k and k.starId
end
if type(i)~='string'or i==''or#i>64 then
t.error('need a valid starId',i,e)
return false,'invalid token type'
end
for _,p in pairs(self.playlists)do
if p~=o and not n(p)and(p.star==i or(p.tagId and self.tokens[p.tagId]and self.tokens[p.tagId].starId==i))then
t.info('Removing star from',p.title)
p.star=nil
p.tagId=nil
end
end
o.star=i
o.tagId=nil
t.info('EVT_TOKEN_LINK',i,'to',o.title)
a.markDirty(self.playlists)
return true
end""")

patch("migrate per-token links to character links at boot (definition)",
"""function e:revert()
local o,i
""",
"""function e:migrateTagLinks()
local c=false
for d,p in pairs(self.playlists)do
if p.tagId and p.plType~='JPLAY'then
local k=self.tokens[p.tagId]
local s=k and k.starId
local u=false
if s then
for _,q in pairs(self.playlists)do
if q~=p and q.star==s then u=true end
end
end
t.info('migrate tag link',d,p.tagId,s,u)
if s and not u then p.star=s end
p.tagId=nil
c=true
end
if d==r and(p.star or p.tagId)then
p.star=nil
p.tagId=nil
c=true
end
end
if c then a.markDirty(self.playlists)end
end
function e:revert()
local o,i
""")

patch("migrate per-token links to character links at boot (call)",
"""l(self.playlists)
if w(self.playlists)then a.markDirty(self.playlists)end""",
"""l(self.playlists)
if w(self.playlists)then a.markDirty(self.playlists)end
self:migrateTagLinks()""")

patch("system catalog load does not refresh TRASH per track",
"""self:playlistAddTrack('system',a)""",
"""self:playlistAddTrack('system',a,true)""")

# ---------------------------------------------------------------- playlists
patch("web PLAYLIST_NEW sanitized + payload type check",
"""function e:onPlaylist(a,e)
t.info('onPlaylist',a,e)
if a=='PLAYLIST_NEW'then
return self:playlistAdd(e)""",
"""function e:onPlaylist(a,e)
t.info('onPlaylist',a,e)
if type(e)~='table'then return false,'invalid payload'end
if a=='PLAYLIST_NEW'then
local m=type(e.title)=='string'and e.title or nil
if m then
m=(m:gsub('^%s+',''))
m=(m:gsub('%s+$',''))
if m==''then m=nil else m=m:sub(1,100)end
end
return self:playlistAdd({title=m,audiobook=(e.audiobook==true)or nil,star=type(e.star)=='string'and e.star or nil})""")

patch("playlistDelete: TRASH protected, TRASH refreshed",
"""function e:playlistDelete(e)
local t=self.playlists[e]
if not t then
return false,i('playlistId does not exist: %s',e)
end
if n(t)then return false,s end
a.markDirty(self.playlists)
self.playlists[e]=nil
return true,nil
end""",
"""function e:playlistDelete(e,c)
local t=self.playlists[e]
if not t then
return false,i('playlistId does not exist: %s',tostring(e))
end
if n(t)then return false,s end
if e==r and not c then return false,'TRASH_READONLY'end
a.markDirty(self.playlists)
self.playlists[e]=nil
if e~=r then
self:dropOrphanStreams()
self:updateTrashPlaylist()
end
return true,nil
end""")

patch("playlistAdd: unique ids",
"""local n=e.id or'user_'..tostring(os.time())""",
"""local n=e.id
if not n then
local b='user_'..tostring(os.time())
n=b
local k=0
while self.playlists[n]do k=k+1 n=b..'_'..k end
end""")

patch("playlistAddTrack: validation, TRASH protected, TRASH refreshed",
"""function e:playlistAddTrack(o,e)
local t=self.playlists[o]
local i=self.tracks[e]
if not t then return false,'playlistId invalid: '..o end
if not i then return false,'trackId invalid: '..e end
if n(t)then return false,s end
table.insert(t.tracks,e)
a.markDirty(self.playlists)
return true,nil
end""",
"""function e:playlistAddTrack(o,e,c)
local t=self.playlists[o]
local i=self.tracks[e]
if not t then return false,'playlistId invalid: '..tostring(o)end
if not i then return false,'trackId invalid: '..tostring(e)end
if n(t)then return false,s end
if o==r then return false,'TRASH_READONLY'end
table.insert(t.tracks,e)
a.markDirty(self.playlists)
if not c then self:updateTrashPlaylist()end
return true,nil
end""")

patch("web radio: validation, unique id, same URL allowed twice",
"""function e:playlistAddStream(t,h,r)
local e=self.playlists[t]
if n(e)then return false,s end
local o=i('stream_%d',tostring(os.time()))
local i={
title=h,
filename=r,
isUrl=true,
}
local i,n=self:addTrack(o,i)
if not i then return nil,n end
if not e then return false,'playlistId invalid: '..t end
table.insert(e.tracks,o)
a.markDirty(self.playlists)
return true,nil
end""",
"""function e:playlistAddStream(t,h,u)
local e=self.playlists[t]
if not e then return false,'playlistId invalid: '..tostring(t)end
if n(e)then return false,s end
if t==r then return false,'TRASH_READONLY'end
if type(u)~='string'or not u:match('^https?://[%w%[]')then return false,'invalid stream url'end
if type(h)~='string'or h:match('^%s*$')then h=u end
local b=os.time()
local o=i('stream_%d',b)
local k=0
while self.tracks[o]do k=k+1 o=i('stream_%d_%d',b,k)end
local c,m=self:addTrack(o,{title=h:sub(1,200),filename=u,isUrl=true},nil,true)
if not c then return false,m end
table.insert(e.tracks,o)
a.markDirty(self.playlists)
return true,nil
end""")

patch("playlistUpdate: TRASH read-only, safe track list, unlink",
"""local function d(a,i,o,e)
if n(e)then return false,s end
if i==r then
local e=h(e.tracks,o)
for e in pairs(e)do
t.info('Deleting',e)
local o,a=a:deleteTrack(e)
if not o or a then t.error('failed to delete',e,a)end
end
end
e.tracks=o
a:updateTrashPlaylist()
end
function e:playlistUpdate(e)
if not e.id then return false,'missing playlistId'end
local t=self.playlists[e.id]
if not t then return false,'playlistId invalid: '..e.id end
if n(t)then return false,s end
if e.title then
if type(e.title)~='string'then return false,'invalid title type'end
t.title=e.title
end
if e.star or e.tagId then
self:updatePlaylistStar(e.star,e.tagId,t)
end
if e.tracks then d(self,e.id,e.tracks,t)end""",
"""local function d(a,i,o,e)
if n(e)then return false,s end
if i==r then
local u={}
for _,x in ipairs(a:unusedTracks())do u[x]=true end
local k={}
for _,x in ipairs(o)do k[x]=true end
for x in pairs(u)do
if not k[x]then
t.info('Deleting unused track',x)
local c,m=a:deleteTrack(x)
if not c or m then t.error('failed to delete',x,m)end
end
end
a:updateTrashPlaylist()
return true
end
local v={}
for _,x in ipairs(o)do
if type(x)=='string'and a.tracks[x]then table.insert(v,x)end
end
local g={}
for _,x in ipairs(e.tracks)do g[x]=true end
e.tracks=v
for _,x in ipairs(v)do g[x]=nil end
for x in pairs(g)do
local q=a.tracks[x]
if q and q.isUrl then
local f=false
for _,p in pairs(a.playlists)do
for _,y in ipairs(p.tracks or{})do if y==x then f=true end end
end
if not f then
a.tracks[x]=nil
if q.filename then a.file2id[q.filename]=nil end
require'jsondb'.markDirty(a.tracks)
end
end
end
a:updateTrashPlaylist()
return true
end
function e:playlistUpdate(e)
if type(e)~='table'then return false,'missing playlist'end
if not e.id then return false,'missing playlistId'end
local t=self.playlists[e.id]
if not t then return false,'playlistId invalid: '..tostring(e.id)end
if n(t)then return false,s end
if e.id==r and(e.title~=nil or e.star~=nil or e.tagId~=nil or e.audiobook~=nil)then
return false,'TRASH_READONLY'
end
if e.title~=nil then
if type(e.title)~='string'then return false,'invalid title type'end
local m=(e.title:gsub('^%s+',''))
m=(m:gsub('%s+$',''))
if m==''then return false,'empty title'end
t.title=m:sub(1,100)
end
if e.star==false or e.star==''then
t.star=nil
t.tagId=nil
elseif e.star or e.tagId then
local c,m=self:updatePlaylistStar(e.star,e.tagId,t)
if not c then return false,m end
end
if e.tracks~=nil then
if type(e.tracks)~='table'then return false,'invalid tracks'end
d(self,e.id,e.tracks,t)
end""")

patch("orphan web radio tracks removed (definition + boot)",
"""self:updateTrashPlaylist()
return true,nil
end""",
"""self:dropOrphanStreams()
self:updateTrashPlaylist()
return true,nil
end
function e:dropOrphanStreams()
local u={}
for _,p in pairs(self.playlists)do
for _,y in ipairs(p.tracks or{})do u[y]=true end
end
for x,q in pairs(self.tracks)do
if q.isUrl and not u[x]then
self.tracks[x]=nil
if q.filename then self.file2id[q.filename]=nil end
a.markDirty(self.tracks)
end
end
end""")

patch("TRASH stays sorted (stable order, no useless rewrites)",
"""local t={}
for a,o in pairs(self.tracks)do
if not e[a]and not o.isUrl then
table.insert(t,a)
end
end
return t
end""",
"""local t={}
for a,o in pairs(self.tracks)do
if not e[a]and not o.isUrl then
table.insert(t,a)
end
end
local k=self.tracks
table.sort(t,function(x,y)
local p=string.lower(tostring(k[x].title or''))
local q=string.lower(tostring(k[y].title or''))
if p==q then return x<y end
return p<q
end)
return t
end""")

patch("TRASH internal delete when empty",
"""if#e==0 then
self:playlistDelete(r)""",
"""if#e==0 then
self:playlistDelete(r,true)""")

# ---------------------------------------------------------------- uploads
patch("upload: never delete an existing file, never leave a track without file",
"""function e:playlistAddUpload(r,e,d)
if not e then return false,'missing uploadId'end
local s=i('%s/upload_%s',self.dirs.uploads,e)
local n
local h=function(e)
t.warn('Deleting upload',s,n,e)
os.remove(s)
if n then os.remove(n)end
return false,e
end
local e,a=l(s)
if a then return h(a)end
n=i('%s/%s',self.dirs.uploads,e)
local i=self.tracks[e]and o.exists(n)
if i then
t.info('skipping duplicate track',e)
os.remove(s)
else
if self.tracks[e]then
t.error('track in db but not on disk',self.tracks[e])
self.tracks[e]=nil
end
if o.exists(n)then
t.error('track on disk but not in db',e)
os.remove(n)
end
local t
t,a=os.rename(s,n)
if a then return h(a)end
t,a=self:audioImport(n,e,d)
if a then return h(a)end
end
if not r then
return true
end
local t
t,a=self:playlistAddTrack(r,e)
if not t then return h(a)end
return e
end""",
"""function e:playlistAddUpload(p,e,d)
if not e then return false,'missing uploadId'end
e=tostring(e)
if not e:match('^%d+$')then return false,'invalid uploadId'end
if p==r then p=nil end
local s=i('%s/upload_%s',self.dirs.uploads,e)
local f=nil
local h=function(m)
t.warn('Deleting upload',s,f,m)
os.remove(s)
if f then
local k=self.file2id[f]
os.remove(f)
if k and self.tracks[k]and self.tracks[k].filename==f then
self.tracks[k]=nil
a.markDirty(self.tracks)
end
self.file2id[f]=nil
end
return false,m
end
if p and not self.playlists[p]then return h('playlistId invalid: '..tostring(p))end
local c,m=l(s)
if m then return h(m)end
local n=i('%s/%s',self.dirs.uploads,c)
if self.tracks[c]and o.exists(n)then
t.info('skipping duplicate track',c)
os.remove(s)
else
if self.tracks[c]then
t.error('track in db but not on disk',self.tracks[c])
if self.tracks[c].filename then self.file2id[self.tracks[c].filename]=nil end
self.tracks[c]=nil
a.markDirty(self.tracks)
end
if o.exists(n)then
t.error('track on disk but not in db',c)
os.remove(n)
end
local g,q=os.rename(s,n)
if not g then return h(q or'rename failed')end
f=n
local _,x=self:audioImport(n,c,d)
if x then return h(x)end
end
if not p then
self:updateTrashPlaylist()
return true
end
local g,q=self:playlistAddTrack(p,c)
if not g then return h(q)end
return c
end""")

patch("upload: clear error code for unsupported files (probe failure)",
"""if e then return nil,"Failed to extract metadata"end""",
"""if e then return nil,"UPLOAD_FAIL_TYPE failed to extract metadata"end""")
patch("upload: clear error code for unsupported files (type)",
"""return nil,"unsupported file type: "..e['mime-type']""",
"""return nil,"UPLOAD_FAIL_TYPE unsupported file type: "..e['mime-type']""")
patch("upload: remove probe temp file, title without extension",
"""s,e=o.read(n)
if e then return nil,"No metadata present"end""",
"""s,e=o.read(n)
os.remove(n)
if e then return nil,"UPLOAD_FAIL_TYPE no metadata present"end""")
patch("upload: title fallback without extension",
"""o=a:gsub('.+/','')""",
"""o=(a:gsub('.+/',''))
o=(o:gsub('%.%w+$',''))""")
patch("boot: clean stale partial uploads (real directory)",
"""o.execute('rm -f %s',r..'/upload_*')""",
"""if self.dirs.uploads then o.execute('rm -f %s',self.dirs.uploads..'/upload_*')end""")

# ---------------------------------------------------------------- playback
patch("stale resume position / empty playlist",
"""if not t then
t=self:trackToPlay(r)
s=t
end
local n=o.tracks[t]
if not n then return nil,i('invalid trackIndex %s',t)end""",
"""if#o.tracks==0 then return nil,nil end
if not t or not o.tracks[t]then
t=self:trackToPlay(r)
if not o.tracks[t]then t=1 end
s=t
end
local n=o.tracks[t]
if not n then return nil,i('invalid trackIndex %s',t)end""")
patch("previous works while paused (web)",
"""function t.on.do_prev_forced()
g(true)
end""",
"""function t.on.do_prev_forced()
g(false)
end""")
patch("repeat/shuffle saved immediately",
"""["/j/web/input/SET_CFG"]=a(l.set_cfg,v),""",
"""["/j/web/input/SET_CFG"]=a(function(x,y)local c,m=l.set_cfg(x,y)if c then l.save()end return c,m end,v),""")

# ---------------------------------------------------------------- robustness
patch("web errors for TRASH updates are real errors (not upload errors)",
"""if a=='PLAYLIST_ADD_FILE'
or a=='PLAYLIST_ADD_UPLOAD'
or a=='PLAYLIST_UPDATE'and t.playlist and t.playlist.id=='TRASH'
then""",
"""if a=='PLAYLIST_ADD_FILE'
or a=='PLAYLIST_ADD_UPLOAD'
then""")
patch("invalid JSON never crashes",
"""i=z:decode(o)
if i==nil then""",
"""local c,m=pcall(function()return z:decode(o,{})end)
i=c and m or nil
if i==nil then""")
patch("a failing handler never kills the player",
"""local r=function(a,i)
t.debug(a,':',i)
local e=o['*']
if e then e(i,a)end
e=o[a]
if not e then
t.error('topic "',a,'" not found in callback table.')
end
e(i,a)
end""",
"""local r=function(n,i)
t.debug(n,':',i)
local e=o['*']
if e then
local c,m=pcall(e,i,n)
if not c then t.error('ERR_HANDLER *',n,m)end
end
e=o[n]
if not e then
t.error('topic "',n,'" not found in callback table.')
return
end
local c,m=pcall(e,i,n)
if not c then
t.error('ERR_HANDLER',n,m)
if n:sub(1,13)=='/j/web/input/'then
pcall(a.publish,'/j/web/output/error','{"msg":"ERR_INTERNAL"}')
end
end
end""")
patch("write errors detected (database never rotated over a truncated file)",
"""function e.write(o,i)
local a,e=io.open(o,'w')
if a and not e then
a:write(i)
a:close()
else""",
"""function e.write(o,i)
local a,e=io.open(o,'w')
if a and not e then
local w,x=a:write(i)
local c,y=a:close()
if not w or not c then e=t('write to %s failed: %s',o,tostring(x or y))end
else""")
patch("MESSAGE_DISMISS tolerant id", """local a=a.id
if a and a>0 then""", """local a=tonumber(a.id)
if a and a>0 then""")
patch("MESSAGE_DISMISS tolerant error", """return false,s('invalid msg id %s',a)""", """return false,s('invalid msg id %s',tostring(a))""")
patch("SET_VOL tolerant error", """s('missing or invalid vol %s',e.vol)""", """s('missing or invalid vol %s',tostring(e.vol))""")
patch("dead cloud calls time out", "'curl --silent", "'curl --max-time 10 --silent", count=3)

# ---------------------------------------------------------------- OpenJooki updates from the web page
patch("installed OpenJooki version in the state",
"""firmware=os.getenv('firmware'),""",
"""firmware=os.getenv('firmware'),
openjooki=(function()local f=io.open('/etc/openjooki-version')if not f then return nil end local v=f:read('*l')f:close()return v end)(),""")
patch("check / start an OpenJooki update from the web page (handlers)",
"""function e.on.get_state()""",
"""function e.oj_update_check()
os.execute("P=/tmp/web_ctrl_dirs/public; echo '{\\"pending\\":true}' > $P/oj-latest.json; (curl -fsSL --max-time 30 https://github.com/Guillain-RDCDE/OpenJooki/releases/latest/download/version.json -o $P/oj-latest.tmp && mv $P/oj-latest.tmp $P/oj-latest.json || echo '{\\"error\\":\\"offline\\"}' > $P/oj-latest.json) >/dev/null 2>&1 &")
return true
end
function e.oj_update_start()
os.execute("S=/jooki/app/www/public/openjooki-status.txt; P=/tmp/web_ctrl_dirs/public; [ -e /tmp/oj-updating ] && exit 0; touch /tmp/oj-updating; : > $S; ln -sf $S $P/oj-status.txt; (if curl -fsSL --max-time 60 https://guillain-rdcde.github.io/OpenJooki/o.sh -o /tmp/oj-o.sh; then sh /tmp/oj-o.sh; else echo '[openjooki] ERROR: cannot reach GitHub - nothing changed' >> $S; fi; rm -f /tmp/oj-updating) >/dev/null 2>&1 &")
return true
end
function e.on.get_state()""")
patch("check / start an OpenJooki update from the web page (topics)",
"""["/j/web/input/GET_STATE"]=e.on.get_state,""",
"""["/j/web/input/GET_STATE"]=e.on.get_state,
["/j/web/input/OJ_UPDATE_CHECK"]=a(e.oj_update_check,nil,true),
["/j/web/input/OJ_UPDATE_START"]=a(e.oj_update_start,nil,true),""")

# ---------------------------------------------------------------- bedtime (1.3.0)
# One small module (ojbed) plus the hooks that feed it.  See docs/19-bedtime.md.
#   resume : an audiobook remembers its chapter AND the position in it, on disk
#            (resume.json), so it survives the Jooki turning itself off; it
#            restarts 15 s earlier; the end of the book clears it.
#   sleep  : a sleep timer (minutes, or "end of this chapter") that lowers the
#            volume gently before pausing, then restores the volume.
#   night  : a time window (default 20:00-07:00, Europe/Paris) during which every
#            playback gets the timer on its own, the volume is capped whatever
#            the knob says, and the lights are dimmed.
# The volume limit and the fade are applied where the volume reaches the
# hardware, because the knob re-sends its position every second.
OJBED_LUA = r"""package.preload['ojbed']=(function(...)
local B={}
local J=require'jsondb'
local L=require'log'
local X=require'sys'
local CF='/jooki/external/jooki/bedtime.json'
local RF='/jooki/external/jooki/resume.json'
local DEF={enabled=true,start=1200,stop=420,timer=20,maxvol=30,dim=true,tzbase=60,tzdst='EU'}
local C={}
for k,v in pairs(DEF)do C[k]=v end
local R={}
local S={cfg=C,night=false,resume=R}
local st,pub,acfg,cat
local fade,restore,sl=1,false,nil
local pausedAt=nil
local function back(r)return(r and r.t)and 60000 or 15000 end
local lastN,lastP,lastS,dirty=-1e3,0,0,false
local FADE=60
local function A()return require'audio'end
function B.now()return require'syscmd'.uptime()end
local function dow(y,m,d)
local k={0,3,2,5,0,3,5,1,4,6,2,4}
if m<3 then y=y-1 end
return(y+math.floor(y/4)-math.floor(y/100)+math.floor(y/400)+k[m]+d)%7
end
local function lastSun(y,m)return 31-dow(y,m,31)end
function B.localMinutes(u)
u=u or os.date('!*t')
if u.year<2024 then return nil end
local off=tonumber(C.tzbase)or 0
if C.tzdst=='EU'then
local k=u.month*10000+u.day*100+u.hour
if k>=30000+lastSun(u.year,3)*100+1 and k<100000+lastSun(u.year,10)*100+1 then off=off+60 end
end
return(u.hour*60+u.min+off)%1440
end
function B.isNight(u)
if not C.enabled then return false end
local m=B.localMinutes(u)
if not m then return false end
local a,b=C.start,C.stop
if a==b then return false end
if a<b then return m>=a and m<b end
return m>=a or m<b
end
function B.vol(v)
v=tonumber(v)or 0
if S.night and C.maxvol<100 and v>C.maxvol then v=C.maxvol end
if fade<1 then v=math.floor(v*fade+.5)end
return v
end
function B.led(c)
if not(S.night and C.dim)then return c end
local o={}
for i=1,3 do
local x=tonumber(c[i])or 0
o[i]=x>0 and math.max(1,math.floor(x*.05+.5))or 0
end
return o
end
local function applyVol()if acfg then pcall(acfg.syncVol)end end
local function setFade(f)
if f>=1 then f=1 elseif f<0 then f=0 end
if math.abs(f-fade)<.02 and f<1 and f>0 then return end
if f==fade then return end
fade=f
applyVol()
end
local function publish()
S.sleep=false
if sl then
local r=nil
if sl.ends then r=math.max(0,math.floor(sl.ends-B.now()+.5))end
S.sleep={mode=sl.mode,remaining=r,total=sl.total,auto=sl.auto}
end
lastP=B.now()
if pub then pcall(pub,'.bedtime')end
end
function B.saveResume()
dirty=false
lastS=B.now()
if cat then for k in pairs(R)do if not cat.playlists[k]then R[k]=nil end end end
J.markDirty(R)
if not J.write(RF,R,1)then L.error('OJ_RESUME write failed')end
publish()
end
function B.save()if dirty then B.saveResume()end end
function B.startSleep(sec,mode,auto)
sl={mode=mode or'time',total=sec,ends=sec and(B.now()+sec),auto=auto or nil}
L.info('OJ_SLEEP start',sl.mode,sec,auto)
publish()
end
local function finish()
L.info('OJ_SLEEP done')
sl=nil
local a=A()
if a.isPlaying()or a.isStarting()then
local np=st and st.audio.nowPlaying
local r=np and np.audiobook and R[np.playlistId]
if r and r.id==np.trackId then r.t=true dirty=true end
a.pause()
restore=true
else
setFade(1)
end
publish()
end
function B.cancel()
sl=nil
restore=false
setFade(1)
publish()
end
function B.onEnded()
if sl and sl.mode=='track'then
L.info('OJ_SLEEP end of chapter')
sl=nil
setFade(1)
publish()
return true
end
return false
end
function B.onPos(np,pos)
if not(np and np.audiobook and np.service=='FILE'and np.playlistId and np.trackId)then return end
pos=math.floor(tonumber(pos)or 0)
local r=R[np.playlistId]
if r and r.id==np.trackId and math.abs((r.pos or 0)-pos)<1000 then return end
R[np.playlistId]={id=np.trackId,pos=pos,t=(restore and r and r.id==np.trackId and r.t)or nil}
dirty=true
end
function B.resumeFor(pl,tracks)
local r=R[pl]
if not r then return nil end
for i,x in ipairs(tracks)do
if x==r.id then
local p=(tonumber(r.pos)or 0)-back(r)
if p>=5000 then return i,p end
return i,nil
end
end
return nil
end
function B.onState(s)
local np=st and st.audio.nowPlaying
if s=='PLAYING'then
if restore then restore=false setFade(1)end
if np and np.resume_ms then
local ms=np.resume_ms
np.resume_ms=nil
L.info('OJ_RESUME seek',ms)
pcall(A().on.do_seek,{position_ms=ms})
elseif pausedAt and B.now()-pausedAt>60 and np and np.audiobook and np.service=='FILE'then
local p=(tonumber(st.audio.playback.position_ms)or 0)-back(R[np.playlistId])
if p>=5000 then
L.info('OJ_RESUME rewind',p)
pcall(A().on.do_seek,{position_ms=p})
end
end
pausedAt=nil
if S.night and not sl and C.timer>0 then B.startSleep(C.timer*60,'time',true)end
elseif s=='STARTING'then
if not(np and np.resume_ms)then B.onPos(np,0)end
elseif s=='ENDED'then
if np and np.audiobook and np.service=='FILE'and np.playlistId and cat then
local p=cat.playlists[np.playlistId]
local nx=nil
for i,x in ipairs(p and p.tracks or{})do if x==np.trackId then nx=p.tracks[i+1]end end
if nx then R[np.playlistId]={id=nx,pos=0}else R[np.playlistId]=nil end
B.saveResume()
end
elseif s=='PAUSED'or s=='STOPPED'then
pausedAt=B.now()
if dirty then B.saveResume()end
end
end
function B.tick(now)
if now-lastN>=15 then
lastN=now
local n=B.isNight()
if n~=S.night then
S.night=n
L.info('OJ_NIGHT',n)
applyVol()
pcall(A().updateLeds)
publish()
end
end
local a=A()
if restore and not(a.isPlaying()or a.isStarting())then restore=false setFade(1)end
if sl then
local f=1
if sl.mode=='time'then
local r=sl.ends-now
if r<=0 then finish()return end
local fd=math.min(FADE,sl.total/3)
if r<fd then f=r/fd end
else
local d=tonumber(st.audio.nowPlaying.duration_ms)or 0
local p=tonumber(st.audio.playback.position_ms)or 0
if d>0 and p>0 and d-p<20000 then f=(d-p)/20000 end
end
if not restore then setFade(f)end
if now-lastP>=15 then publish()end
end
if dirty and now-lastS>=60 then B.saveResume()end
end
local function hm(v)
if type(v)=='number'and v>=0 and v<1440 then return math.floor(v)end
if type(v)=='string'then
local h,m=v:match('^(%d%d?):(%d%d)$')
h,m=tonumber(h),tonumber(m)
if h and m and h<24 and m<60 then return h*60+m end
end
return nil
end
function B.set(p)
if type(p)~='table'then return false,'invalid payload'end
local n={}
for k,v in pairs(C)do n[k]=v end
for _,k in ipairs({'enabled','dim'})do
if p[k]~=nil then
if type(p[k])~='boolean'then return false,'invalid '..k end
n[k]=p[k]
end
end
for _,k in ipairs({'start','stop'})do
if p[k]~=nil then
local v=hm(p[k])
if not v then return false,'invalid '..k end
n[k]=v
end
end
local lim={timer={0,180},maxvol={5,100},tzbase={-840,840}}
for k,r in pairs(lim)do
if p[k]~=nil then
local v=tonumber(p[k])
if not v or v<r[1]or v>r[2]then return false,'invalid '..k end
n[k]=math.floor(v)
end
end
if p.tzdst~=nil then
if p.tzdst~='EU'and p.tzdst~='none'then return false,'invalid tzdst'end
n.tzdst=p.tzdst
end
for k,v in pairs(n)do C[k]=v end
local t={}
for k,v in pairs(C)do t[k]=v end
J.markDirty(t)
if not J.write(CF,t,1)then return false,'write failed'end
lastN=-1e3
B.tick(B.now())
publish()
return true
end
function B.onSleep(p)
if type(p)~='table'then return false,'invalid payload'end
if p.cancel then B.cancel()return true end
if p.mode=='track'then B.startSleep(nil,'track')return true end
local s=tonumber(p.seconds)or(tonumber(p.minutes)and tonumber(p.minutes)*60)
if not s or s<1 or s>4*3600 then return false,'invalid duration'end
B.startSleep(math.floor(s),'time')
return true
end
function B.onResumeReset(p)
if type(p)~='table'or type(p.playlistId)~='string'then return false,'invalid payload'end
R[p.playlistId]=nil
B.saveResume()
return true
end
local function load(f)
if not X.exists(f)then return nil end
return J.read(f,1)
end
function B.init(state,p,a,c)
st,pub,acfg,cat=state,p,a,c
local f=load(CF)
if type(f)=='table'then
for k,v in pairs(DEF)do
if type(f[k])==type(v)then C[k]=f[k]end
end
end
local r=load(RF)
if type(r)=='table'then
for k,v in pairs(r)do
if type(v)=='table'and type(v.id)=='string'then R[k]={id=v.id,pos=tonumber(v.pos)or 0}end
end
end
state.bedtime=S
S.night=B.isNight()
lastN=B.now()
applyVol()
pcall(A().updateLeds)
end
return B
end)
"""

# ---------------------------------------------------------------- network health (1.3.0)
# ojnet: what the page needs to show how solid the Wi-Fi is, one-time cleanup of
# the logs the original system piled up, and the name "<hostname>.local".
#   wifi   : reads /tmp/oj-wifi.log (Wi-Fi events copied there by syslog-ng, see
#            system/syslog-ng.conf): access point in use, drops and beacon losses
#            since boot; published in the state as "net".
#   logs   : at boot, removes the queue of logs waiting for Muuselabs' Papertrail
#            and keeps only the end of the old never-rotated log.
#   mDNS   : answers "<hostname>.local" (e.g. jooki2-0426e8.local) with the
#            Jooki's address, so the page opens without knowing the IP (web_ctrl
#            only serves its own name: any other name is redirected to the dead
#            Muuselabs setup site); AAAA queries get an NSEC "IPv4 only" answer
#            so browsers do not wait for IPv6. Shares
#            port 5353 with spotify_ctrl's own responder (SO_REUSEADDR); if the
#            port cannot be shared, the Jooki simply keeps working without it.
OJNET_LUA = r"""package.preload['ojnet']=(function(...)
local N={}
local L=require'log'
local WF='/tmp/oj-wifi.log'
local LD='/jooki/external/logs/syslog-ng'
local S={ap=nil,drops=0,beacons=0,since=0,name=nil}
local st,pub
local U,joined,joinedIp=nil,false,nil
local lastW,lastJ=-1e3,-1e3
local names={}
local function publish()if pub then pcall(pub,'.net')end end
function N.readWifi(txt)
local d,b,ap=0,0,nil
for l in txt:gmatch('[^\n]+')do
if l:find('wifi:state: run -> init',1,true)then d=d+1
elseif l:find('bcn_timout',1,true)then b=b+1 end
local a=l:match('wifi:connected with (.-), aid')
if a then ap=a end
end
return d,b,ap
end
local function wifi()
local f=io.open(WF,'r')
local txt=''
if f then txt=f:read('*a')or'' f:close()end
local d,b,ap=N.readWifi(txt)
local w=st and st.wifi
if w and w.stat=='success'and type(w.ssid)=='string'then ap=w.ssid end
if d~=S.drops or b~=S.beacons or ap~=S.ap then
S.drops,S.beacons,S.ap=d,b,ap
publish()
end
end
local function u16(p,i)return p:byte(i)*256+p:byte(i+1)end
function N.qname(p,i)
local t={}
for _=1,20 do
local n=p:byte(i)
if not n or n>=192 then return nil end
if n==0 then return table.concat(t,'.'),i+1 end
t[#t+1]=p:sub(i+1,i+n)
i=i+n+1
end
return nil
end
local function enc(n)
local o={}
for part in n:gmatch('[^%.]+')do o[#o+1]=string.char(#part)..part end
return table.concat(o)..string.char(0)
end
function N.answer(q,ip,unicast,id,question,qt)
local a,b,c,d=ip:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
if not a then return nil end
local ttl=unicast and 10 or 120
local cls=unicast and 1 or 32769
local hd=(unicast and id or string.char(0,0))..string.char(132,0,0,unicast and 1 or 0,0,1,0,0,0,0)
local rr
if qt==28 then
local nx=enc(q)..string.char(0,1,64)
rr=enc(q)..string.char(0,47,math.floor(cls/256),cls%256,0,0,math.floor(ttl/256),ttl%256,0,#nx)..nx
else
rr=enc(q)..string.char(0,1,math.floor(cls/256),cls%256,0,0,math.floor(ttl/256),ttl%256,0,4,tonumber(a),tonumber(b),tonumber(c),tonumber(d))
end
return hd..(unicast and question or'')..rr
end
function N.handle(p,ip)
if #p<17 or p:byte(3)>=128 then return {}end
local out={}
local i=13
for _=1,u16(p,5)do
local n,j=N.qname(p,i)
if not n or not p:byte(j+3)then break end
local qt=u16(p,j)
local q=p:sub(i,j+3)
i=j+4
n=n:lower()
if names[n]and(qt==1 or qt==255 or qt==28)and ip then out[#out+1]={n=n,q=q,t=qt}end
end
return out
end
local function mdns()
if not U then return end
for _=1,8 do
local p,rip,rport=U:receivefrom()
if not p then return end
local ip=st and st.device and st.device.ip
for _,r in ipairs(N.handle(p,ip))do
local uni=rport~=5353
local pkt=N.answer(r.n,ip,uni,p:sub(1,2),r.q,r.t)
if pkt then
if uni then U:sendto(pkt,rip,rport)else U:sendto(pkt,'224.0.0.251',5353)end
end
end
end
end
local function join(now)
local ip=st and st.device and st.device.ip
if not U or not ip or ip==''then return end
if joined and joinedIp==ip then return end
if joined then pcall(U.setoption,U,'ip-drop-membership',{multiaddr='224.0.0.251',interface=joinedIp})end
local ok=U:setoption('ip-add-membership',{multiaddr='224.0.0.251',interface=ip})
joined,joinedIp=ok and true or false,ok and ip or nil
if ok then L.info('OJ_MDNS answering',ip)end
end
local function openMdns()
local ok,s=pcall(function()return require'socket'.udp()end)
if not ok or not s then return end
s:setoption('reuseaddr',true)
pcall(s.setoption,s,'reuseport',true)
if not s:setsockname('0.0.0.0',5353)then L.warn('OJ_MDNS port 5353 not available')s:close()return end
s:settimeout(0)
pcall(s.setoption,s,'ip-multicast-ttl',255)
U=s
end
function N.cleanup()
os.execute("(cd "..LD.." 2>/dev/null && rm -f syslog-ng-0*.qf && if [ -f syslog-ng.log ]; then tail -n 3000 syslog-ng.log > syslog-ng.old.log; rm -f syslog-ng.log; fi) >/dev/null 2>&1 &")
end
function N.tick(now)
if now-lastW>=20 then lastW=now wifi()end
if now-lastJ>=30 then lastJ=now pcall(join,now)end
mdns()
end
function N.init(state,p)
st,pub=state,p
local h=(state.device and state.device.hostname or''):lower():gsub('%.local$','')
if h~=''then names[h..'.local']=true S.name=h..'.local'end
S.since=require'syscmd'.uptime()
state.net=S
N.cleanup()
pcall(openMdns)
wifi()
end
return N
end)
"""

patch("bedtime module", "package.preload['bluetooth']=(function(...)",
      OJBED_LUA + OJNET_LUA + "package.preload['bluetooth']=(function(...)")
patch("bedtime: volume limit and fade applied where the volume reaches the hardware",
"""local e=c_alsa_set_volume(e,0)""",
"""local e=c_alsa_set_volume(require'ojbed'.vol(e),0)""")
patch("bedtime: dimmed lights at night",
"""local e=h('%s,%s',e,l(a))""",
"""local e=h('%s,%s',e,l(require'ojbed'.led(a)))""")
patch("bedtime: playback state changes",
"""e.playback.state=t
g(t)
p(t)
u()
end""",
"""e.playback.state=t
g(t)
p(t)
pcall(require'ojbed'.onState,t)
u()
end""")
patch("bedtime: 'end of chapter' timer stops instead of playing the next track",
"""if not l(a)then return end
n('ENDED')
""",
"""if not l(a)then return end
n('ENDED')
if require'ojbed'.onEnded()then return end
""")
patch("bedtime: audiobook position recorded",
"""function t.on.gs_position(t)
if not l(t)then return end
e.playback.position_ms=t.pos
""",
"""function t.on.gs_position(t)
if not l(t)then return end
e.playback.position_ms=t.pos
pcall(require'ojbed'.onPos,e.nowPlaying,t.pos)
""")
patch("bedtime: an audiobook resumes at its saved chapter and position",
"""if not t or not o.tracks[t]then
t=self:trackToPlay(r)
if not o.tracks[t]then t=1 end
s=t
end""",
"""local oj=nil
if not t or not o.tracks[t]then
t=self:trackToPlay(r)
if o.audiobook then
local x,y=require'ojbed'.resumeFor(r,o.tracks)
t=x or 1
oj=y
end
if not o.tracks[t]then t=1 end
s=t
end""")
patch("bedtime: resume position carried by the play action",
"""queueIndex=s,
trackIndex=t,""",
"""queueIndex=s,
trackIndex=t,
resume_ms=oj,""")
patch("bedtime: state filter",
"""elseif a==T then i={userMessages=t.userMessages}""",
"""elseif a==T then i={userMessages=t.userMessages}
elseif a=='.bedtime'then i={bedtime=t.bedtime}
elseif a=='.net'then i={net=t.net}""")
patch("bedtime: init",
"""i.init(h,t.audio,e.userCat,e.publish_state,c.isActiveOrWarn)""",
"""i.init(h,t.audio,e.userCat,e.publish_state,c.isActiveOrWarn)
require'ojbed'.init(t,e.publish_partial,l,e.userCat)
pcall(require'ojnet'.init,t,e.publish_partial)""")
patch("bedtime: tick",
"""d.update(y,d.inactivity,y)""",
"""d.update(y,d.inactivity,y)
local ok,er=pcall(require'ojbed'.tick,y)
if not ok then o.error('OJ_TICK',er)end
ok,er=pcall(require'ojnet'.tick,y)
if not ok then o.error('OJ_TICK net',er)end""")
patch("bedtime: saved on power off",
"""e.userCat:save()
l.save()""",
"""e.userCat:save()
l.save()
pcall(require'ojbed'.save)""")
patch("bedtime: web messages",
"""["/j/web/input/OJ_UPDATE_START"]=a(e.oj_update_start,nil,true),""",
"""["/j/web/input/OJ_UPDATE_START"]=a(e.oj_update_start,nil,true),
["/j/web/input/OJ_SLEEP"]=a(function(x)return require'ojbed'.onSleep(x)end),
["/j/web/input/OJ_BEDTIME_SET"]=a(function(x)return require'ojbed'.set(x)end),
["/j/web/input/OJ_RESUME_RESET"]=a(function(x)return require'ojbed'.onResumeReset(x)end),""")

def apply(src):
    """Return patched source. Raises ValueError (nothing applied) on any mismatch."""
    if is_patched(src):
        raise ValueError("already patched")
    out = src
    for name, old, new, count in P:
        n = out.count(old)
        if n != count:
            raise ValueError("patch '%s': expected %d match(es), found %d" % (name, count, n))
        out = out.replace(old, new)
    return out

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        print("usage: lua_patches.py <player.lib in> <player.lib out>"); sys.exit(1)
    src = decode(open(sys.argv[1], "rb").read())
    out = apply(src)
    open(sys.argv[2], "wb").write(encode(out))
    print("patched: %d fixes, %d -> %d bytes of source" % (len(P), len(src), len(out)))
