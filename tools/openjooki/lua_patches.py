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
"""
import zlib

MARK_OLD = "_G._MINIFIED=true\n"
MARK_NEW = "_G._MINIFIED=true\n_G._OPENJOOKI_LUA='4'\n"
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
