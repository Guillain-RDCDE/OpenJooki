"""Startup timing and the physical heart gesture through the real core/MQTT."""
import datetime
import json
import time
import paho.mqtt.client as mqtt
import bench as B

R = B.Results()
LED = '/j/ht/output/raw_write'
peer = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, 'heart-lights-controller')
peer.on_message = lambda c, u, m: c.publish('/j/ht/input/raw_read_response', m.payload)
peer.connect('127.0.0.1', 1883); peer.subscribe(LED); peer.loop_start()
spy = B.Spy(LED, '/j/led/output/#', '/j/audio/out/play')
def pre():
    json.dump({'_': {'version': 1}, 'enabled': False}, open(B.DB + '/bedtime.json', 'w'))
    json.dump({'_': {'version': 1}, 'lights_off': True, 'heart_press': 'next'}, open(B.DB + '/audiocfg.json', 'w'))
def last():
    values = spy.payloads(LED)
    return values[-1] if values else None
def flashes(mark=0):
    return [p for p in spy.payloads('/j/led/output/set_raw', mark) if p.startswith('ALL,') and p != 'ALL,0,0,0']
def five():
    for _ in range(5):
        j.c.publish('/j/gpio/input/circle', '1')
        B.quiet(0.08, 'short physical heart press')
        j.c.publish('/j/gpio/input/circle', '0')
        B.quiet(0.10, 'gap between the five physical presses')
    j.barrier()
def window(night):
    n = datetime.datetime.now(datetime.timezone.utc); m = n.hour * 60 + n.minute
    return {'enabled': True, 'start': (m - 60 if night else m + 120) % 1440,
            'stop': (m + 60 if night else m + 180) % 1440, 'tzbase': 0, 'tzdst': 'none', 'lights_off': True, 'dim': False}
started = time.time(); j = B.boot(seed=True, pre=pre)
R.check('saved darkness is retained during startup indication', j.get('audio.config.lights_off') is True and last() == '34 8')
R.expect('three startup flashes finish in darkness', lambda: len(flashes()) == 3 and last() == '34 0', 13)
first = next(t for t, topic, p in spy.seen if topic == '/j/led/output/set_raw' and p.startswith('ALL,') and p != 'ALL,0,0,0')
R.check('flashes wait at least ten seconds after boot began', first - started >= 10, first - started)
mark = spy.mark();j.c.publish('/j/power/input/plugged_in', '1');j.barrier()
R.expect('charging reasserts darkness', lambda: last() == '34 0')
R.check('charging does not replay the startup cue', not flashes(mark))
j.send('PLAYLIST_PLAY', {'playlistId': 'user_1', 'trackIndex': 2});j.wait_state('audio.playback.state', 'PLAYING')
j.send('OJ_PARENT_SET', {'code': '9876'});j.wait_state('maintenance.parent', True)
mark = spy.mark();five()
R.expect('five heart presses enable the lights with a parent code set', lambda: last() == '34 8' and j.get('audio.config.lights_off') is False)
R.check('the light gesture does not skip songs', not spy.payloads('/j/audio/out/play', mark))
R.expect('physical preference is persisted', lambda: json.load(open(B.DB + '/audiocfg.json')).get('lights_off') is False)
five();R.expect('the next five presses disable all lights', lambda: last() == '34 0' and j.get('audio.config.lights_off') is True)
j.send('OJ_PARENT_CLEAR', {'current': '9876'});j.wait_state('maintenance.parent', False)
j.send('SET_CFG', {'lights_off': False});j.wait_state('audio.config.lights_off', False)
j.send('OJ_BEDTIME_SET', window(True));j.wait_state('bedtime.night', True)
R.expect('scheduled night darkness is active', lambda: last() == '34 0')
five();R.expect('five presses temporarily override night darkness', lambda: last() == '34 8')
R.check('night preference is kept', j.get('bedtime.cfg.lights_off') is True and j.get('audio.config.lights_off') is False)
j.send('OJ_BEDTIME_SET', window(False));j.wait_state('bedtime.night', False)
j.send('OJ_BEDTIME_SET', window(True));j.wait_state('bedtime.night', True)
R.expect('next night boundary restores scheduled darkness', lambda: last() == '34 0')
five();R.expect('night light can be enabled again', lambda: last() == '34 8')
mark = spy.mark();j = B.restart(j)
R.expect('restart clears the override and ends the startup cue in darkness', lambda: len(flashes(mark)) == 3 and last() == '34 0', 13)
R.check('no pending click changes the saved switch on restart', j.get('audio.config.lights_off') is False)
B.check_clean_log(R, 'startup / heart light gesture')
spy.close();j.close();peer.loop_stop();peer.disconnect();R.finish()
