"""Silent three-red-flash shutdown on the real core; /sbin/poweroff is intercepted."""
import json
import os
import tempfile
from pathlib import Path
import paho.mqtt.client as mqtt
import bench as B

R=B.Results();LED='/j/ht/output/raw_write';power_log='/tmp/oj-shutdown-test.log'
peer=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,'shutdown-light-controller')
peer.on_message=lambda c,u,m:c.publish('/j/ht/input/raw_read_response',m.payload)
peer.connect('127.0.0.1',1883);peer.subscribe(LED);peer.loop_start()
spy=B.Spy(LED,'/j/led/output/#','/j/audio/out/#','/j/all/quit')
source=Path(os.environ['CORE_BUILD'])
with tempfile.TemporaryDirectory(prefix='oj-shutdown-build-') as td:
    target=Path(td)
    (target/'core.lua').write_bytes((source/'core.lua').read_bytes())
    # Override only the actual poweroff syscall, leaving the application and bus real.
    harness=(source/'harness.lua').read_text()
    intercept='''local original = io.popen
io.popen = function(cmd, mode)
  if cmd:find("'/sbin/poweroff'", 1, true) then
    local f = assert(io.open("/tmp/oj-shutdown-test.log", "a"))
    f:write(tostring(require("socket").gettime()) .. "\\n"); f:close()
    return { read = function() return "" end, close = function() return true, "exit", 0 end }
  end
  return original(cmd, mode)
end
'''
    (target/'harness.lua').write_text(intercept+harness)
    os.environ['CORE_BUILD']=td
    def pre():
        json.dump({'_':{'version':1},'enabled':False},open(B.DB+'/bedtime.json','w'))
        json.dump({'_':{'version':1},'lights_off':True,'heart_press':'none','volume':37},open(B.DB+'/audiocfg.json','w'))
        # Even with a valid sound catalogue, manual shutdown must not play it.
        json.dump({'_':{'version':1},'Evt.Jooki.Poweroff':{'filename':'poweroff.ogg'}},open('/jooki/app/system/tracks.json','w'))
        Path(power_log).write_text('')
    for manual in ('page','button'):
        j=B.boot(pre=pre);mark=spy.mark()
        if manual=='page':
            reply=j.v2('device.power_off',{});R.check('web shutdown accepted',reply.get('ok'),reply)
        else:
            j.c.publish('/j/gpio/input/circle','1')
            B.quiet(2.2,'hold the real heart input to request power off')
            j.c.publish('/j/gpio/input/circle','0')
        R.expect(manual+': shutdown completes after the cue',lambda:bool(Path(power_log).read_text().strip()),5)
        red=spy.payloads('/j/led/output/set_raw',mark)
        R.check(manual+': exactly three red flashes',red.count('ALL,200,0,0')==3,red)
        R.check(manual+': no power-off sound',not any(p.startswith('3\t') for p in spy.payloads('/j/audio/out/play',mark)))
        R.check(manual+': global driver ends off',spy.payloads(LED,mark)[-1]=='34 0')
        first=next(at for at,t,p in spy.seen[mark:] if t=='/j/led/output/set_raw' and p=='ALL,200,0,0')
        cut=float(Path(power_log).read_text().strip())
        R.check(manual+': poweroff waits until all flashes finish',cut-first>=.85,cut-first)
        R.check(manual+': requested volume survives',json.load(open(B.DB+'/audiocfg.json'))['volume']==37)
        R.check(manual+': quit comes after final flash',spy.payloads('/j/all/quit',mark)==['"from-player"'])
        j.close()
    os.environ['CORE_BUILD']=str(source)
B.check_clean_log(R,'silent shutdown flashes')
spy.close();peer.loop_stop();peer.disconnect();R.finish()
