"""Real-core MQTT check of random Spotify startup; the provider is simulated."""
import json
import time
import paho.mqtt.client as mqtt
import bench as B
R=B.Results();events=[];volumes=[];shuffle_state=True
peer=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,'random-spotify-peer')
def publish(kind,data):peer.publish('/j/spotify/input/'+kind,json.dumps(data) if isinstance(data,dict) else data)
def song(title):publish('now_playing',{'source_uri':'spotify:playlist:demo','track':title,'album':'Music','duration_ms':100000})
def receive(c,u,m):
 global shuffle_state
 t=m.topic;p=m.payload
 if t=='/j/esp32/output/knobs/state':c.publish('/j/esp32/input/knobs/state','{"volume":100,"hp_state":0,"volume_api":2}')
 elif t=='/j/esp32/output/audio/set_volume':
  volumes.append(json.loads(p));c.publish('/j/esp32/input/audio/volume','0')
 elif t=='/j/spotify/output/play_preset':
  events.append(('preset',volumes[-1]['percent']));publish('active','1')
  publish('now_playing',{'source_uri':'spotify:playlist:previous','track':'Previous'})
  publish('now_playing',{'source_uri':'spotify:playlist:demo','track':'First','album':'Music','restricted':True})
  song('First');publish('position','1100')
 elif t=='/j/spotify/output/set_shuffle':
  events.append(('shuffle',p.decode()));new=p==b'1'
  if new!=shuffle_state:
   shuffle_state=new;publish('set_cfg',{'shuffle_mode':new,'repeat_mode':1})
 elif t=='/j/spotify/output/next':events.append(('next',''));song('Random');publish('playing','');publish('position','0')
peer.on_message=receive;peer.connect('127.0.0.1',1883)
peer.subscribe('/j/esp32/output/#');peer.subscribe('/j/spotify/output/#');peer.loop_start()
def pre():
 json.dump({'_':{'version':1},'demo':{'title':'Music','tracks':[],'spotify':{'uri':'spotify:playlist:demo','preset':'AB'}}},open(B.DB+'/playlists.json','w'))
 json.dump({'_':{'version':1},'enabled':False},open(B.DB+'/bedtime.json','w'))
 json.dump({'_':{'version':1},'volume':20,'random_start':True,'shuffle_mode':False,'toy_safe_maxvol':56,'toy_safe_maxvol_global':True},open(B.DB+'/audiocfg.json','w'))
j=B.boot(pre=pre)
r=j.v2('playback.play',{'playlist':'demo','restart':True});R.check('fresh-start API accepted',r.get('ok'),r)
R.expect('random track reaches the real core',lambda:j.get('audio.nowPlaying.track')=='Random')
R.check('speaker is silenced before loading the preset',('preset',0) in events,events)
R.expect('shuffle confirmed before a single next and then restored',lambda:events==[('preset',0),('shuffle','1'),('shuffle','0'),('shuffle','1'),('next',''),('shuffle','0')])
R.expect('bounded speaker volume restored',lambda:volumes and volumes[-1]=={'percent':20,'maximum':56})
R.check('requested volume preserved',j.get('audio.config.volume')==20)
# Another explicit playlist Play must start again even while that playlist is playing.
j.send('PLAYLIST_PLAY',{'playlistId':'demo','restart':True})
R.expect('repeated playlist Play requests another random Spotify song',lambda:sum(t=='next' for t,v in events)==2,8)
R.expect('repeated random start restores the speaker volume',lambda:volumes and volumes[-1]=={'percent':20,'maximum':56})
# Reproduce a restarted core whose cached active flag is stale.
j.send('SET_CFG',{'random_start':False})
j.v2('playlist.update',{'id':'demo','resume':True})
publish('active','false')
j.wait_state('spotify.active',False)
publish('now_playing',{'source_uri':'spotify:playlist:previous','track':'Previous'})
publish('status',{'state':'ready','active':1,'logged_in':1})
j.wait_state('spotify.active',True)
mark=len(events);started=time.monotonic()
r=j.v2('playback.play',{'playlist':'demo','restart':True})
R.expect('resume switch loads its preset without the five-second continuation wait',lambda:any(t=='preset' for t,v in events[mark:]),1)
R.check('resume switch stayed below two seconds',time.monotonic()-started<2)
R.check('resume setting never triggers random next',not any(t=='next' for t,v in events[mark:]),events[mark:])
B.check_clean_log(R,'random Spotify startup')
j.close();peer.loop_stop();peer.disconnect();R.finish()
