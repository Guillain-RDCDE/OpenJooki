"""Connected startup cue, immediate heart actions and UI on the real core/MQTT."""
import json
import time
import paho.mqtt.client as mqtt
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R=B.Results();LED='/j/ht/output/raw_write'
peer=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,'startup-lights-controller')
peer.on_message=lambda c,u,m:c.publish('/j/ht/input/raw_read_response',m.payload)
peer.connect('127.0.0.1',1883);peer.subscribe(LED);peer.loop_start()
spy=B.Spy(LED,'/j/led/output/#','/j/audio/out/play')
def pre():
    json.dump({'_':{'version':1},'enabled':False},open(B.DB+'/bedtime.json','w'))
    json.dump({'_':{'version':1},'lights_off':True,'heart_press':'next','repeat_mode':1},open(B.DB+'/audiocfg.json','w'))
def last():
    values=spy.payloads(LED)
    return values[-1] if values else None
def flashes(mark=0):
    return [p for p in spy.payloads('/j/led/output/set_raw',mark) if p.startswith('ALL,') and p!='ALL,0,0,0']
j=B.boot(seed=True,ui=True,pre=pre)
B.quiet(.7,'offline startup must not begin the cue')
R.check('startup waits for a Wi-Fi address',not flashes())
def status(on):
    j.c.publish('/j/esp32/input/net/sta/config',json.dumps({'stat':'success' if on else 'disconnected','ip':'10.0.0.2' if on else ''}))
status(True);j.wait_state('net.connected',True)
B.quiet(.7,'disconnect during the startup countdown')
status(False);j.wait_state('net.connected',False)
B.quiet(.7,'the disconnected countdown is cancelled')
started=time.time();status(True);j.wait_state('net.connected',True)
R.check('saved darkness is retained during startup indication',j.get('audio.config.lights_off') is True and last()=='34 8')
R.expect('three startup flashes finish in darkness',lambda:len(flashes())==3 and last()=='34 0',13)
first=next(t for t,topic,p in spy.seen if topic=='/j/led/output/set_raw' and p.startswith('ALL,') and p!='ALL,0,0,0')
R.check('flashes wait ten seconds after the final Wi-Fi connection',first-started>=9.8,first-started)
mark=spy.mark();j.c.publish('/j/power/input/plugged_in','1');j.barrier()
R.check('charging retains darkness without replaying the cue',last()=='34 0' and not flashes(mark))
j.send('PLAYLIST_PLAY',{'playlistId':'user_1','trackIndex':1});j.wait_state('audio.playback.state','PLAYING')
mark=spy.mark()
for _ in range(5):
    j.c.publish('/j/gpio/input/circle','1');B.quiet(.08,'ordinary short heart press')
    j.c.publish('/j/gpio/input/circle','0');B.quiet(.10,'gap between short heart presses')
R.expect('five fast presses perform five normal next actions',lambda:len(spy.payloads('/j/audio/out/play',mark))==5)
R.check('rapid heart presses cannot change the light preference',j.get('audio.config.lights_off') is True and last()=='34 0')
with sync_playwright() as pw:
    browser=pw.chromium.launch(args=['--no-sandbox'])
    pg=browser.new_page(locale='de-DE',viewport={'width':375,'height':812})
    pg.goto(PAGE+'/#/settings/buttons');pg.wait_for_selector('[data-k=heartpress]')
    text=pg.locator('[data-k=heartpress]').evaluate("e => e.closest('.srow').textContent")
    R.check('heart setting explains silent red shutdown feedback','dreimal kurz rot blinken, ohne Ton' in text,text)
    R.check('no obsolete five-click instruction remains','Fünfmal' not in pg.locator('body').inner_text() and 'Fünf schnelle' not in pg.locator('body').inner_text())
    R.check('narrow German settings have no horizontal overflow',pg.evaluate('() => document.documentElement.scrollWidth <= innerWidth'))
    browser.close()
B.check_clean_log(R,'connected startup / immediate heart actions')
spy.close();j.close();peer.loop_stop();peer.disconnect();R.finish()
