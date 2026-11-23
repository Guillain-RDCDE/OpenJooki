"""Switch off when the token is taken off (#52), on the real core; /sbin/poweroff is intercepted.
Off by default; on, the Jooki switches off token_off_s after the token is taken off (2 s here),
unless a token is put back before; never when no token was on (switched on without one); the
delay chosen on the page (off_token_s) wins; with "keep playing" too, off the delay after the music stops.
  sudo -E python3 test_token_off.py
"""
import json
import os
import tempfile
import time
from pathlib import Path
import bench as B

R = B.Results(); power_log = '/tmp/oj-token-off-test.log'
TAG = '04A1B2C3D4E5F6'
source = Path(os.environ['CORE_BUILD'])
with tempfile.TemporaryDirectory(prefix='oj-token-off-build-') as td:
    target = Path(td)
    (target / 'core.lua').write_bytes((source / 'core.lua').read_bytes())
    # Override only the actual poweroff (it would switch off the bench itself), as test_shutdown_lights.py
    harness = (source / 'harness.lua').read_text()
    intercept = '''local original = io.popen
io.popen = function(cmd, mode)
  if cmd:find("'/sbin/poweroff'", 1, true) then
    local f = assert(io.open("/tmp/oj-token-off-test.log", "a"))
    f:write(tostring(require("socket").gettime()) .. "\\n"); f:close()
    return { read = function() return "" end, close = function() return true, "exit", 0 end }
  end
  return original(cmd, mode)
end
'''
    (target / 'harness.lua').write_text(intercept + harness)
    os.environ['CORE_BUILD'] = td
    config = B.core_config({'token_off_s': 2}, 'token-off')

    def pre(on):
        def f():
            json.dump({'_': {'version': 1}, 'enabled': False}, open(B.DB + '/bedtime.json', 'w'))
            cfg = {'_': {'version': 1}, 'volume': 30}
            if on is not None: cfg['off_on_token_removal'] = on
            json.dump(cfg, open(B.DB + '/audiocfg.json', 'w'))
            Path(power_log).write_text('')
        return f

    def off(): return bool(Path(power_log).read_text().strip())

    # off by default: taking the token off only pauses
    j = B.boot(pre=pre(None), config=config)
    R.check('off by default', j.get('audio.config.off_on_token_removal') is False, j.get('audio.config'))
    j.nfc(TAG, '102'); j.wait(lambda: j.nfc_state.get('tagId') == TAG)
    t0 = time.time(); j.nfc_off(); j.wait(lambda: not j.nfc_state)
    B.quiet(4, 'twice token_off_s with the switch off')
    R.check('switch off: the Jooki stays on', not off())
    # turned on from the page (SET_CFG), then the token taken off: off about token_off_s later
    j.send('SET_CFG', {'off_on_token_removal': True}); j.wait(lambda: j.get('audio.config.off_on_token_removal') is True)
    R.check('the switch is saved', json.load(open(B.DB + '/audiocfg.json')).get('off_on_token_removal') is True)
    j.nfc(TAG, '102'); j.wait(lambda: j.nfc_state.get('tagId') == TAG)
    t0 = time.time(); j.nfc_off()
    R.expect('switch on: the Jooki switches off after the token is taken off', off, 8)
    took = float(Path(power_log).read_text().split()[0]) - t0 if off() else -1
    R.check('... about token_off_s later, not at once', 1.8 <= took <= 6, took)
    j.close()

    # a token put back in time: no switching off
    j = B.boot(pre=pre(True), config=config)
    j.nfc(TAG, '102'); j.wait(lambda: j.nfc_state.get('tagId') == TAG)
    j.nfc_off(); j.wait(lambda: not j.nfc_state)
    time.sleep(1); j.nfc(TAG, '102'); j.wait(lambda: j.nfc_state.get('tagId') == TAG)
    B.quiet(4, 'past token_off_s with the token back')
    R.check('a token put back in time: the Jooki stays on', not off())
    j.close()

    # switched on without a token: the reader says "removed" with nothing on it -> stays on (#52)
    j = B.boot(pre=pre(True), config=config)
    j.nfc_off()
    B.quiet(5, 'past token_off_s, no token was ever on')
    R.check('switched on without a token: the Jooki stays on', not off())
    # how long, chosen on the page: 5 s here, not the core's 2 s
    j.send('SET_CFG', {'off_token_s': 5}); j.wait(lambda: j.get('audio.config.off_token_s') == 5)
    R.check('the delay is saved', json.load(open(B.DB + '/audiocfg.json')).get('off_token_s') == 5)
    j.nfc(TAG, '102'); j.wait(lambda: j.nfc_state.get('tagId') == TAG)
    t0 = time.time(); j.nfc_off()
    R.expect('the chosen delay: off after the token is taken off', off, 12)
    took = float(Path(power_log).read_text().split()[0]) - t0 if off() else -1
    R.check('... about 5 s later, not 2', 4.8 <= took <= 9, took)
    j.close()

    # with "keep playing" too: the music goes on, and the Jooki switches off the delay after it stops
    def pre_both():
        pre(True)()
        cfg = json.load(open(B.DB + '/audiocfg.json')); cfg['continue_on_token_removal'] = True
        json.dump(cfg, open(B.DB + '/audiocfg.json', 'w'))
    j = B.boot(seed=True, pre=pre_both, config=B.core_config({'token_off_s': 2, 'token_off_poll_s': 1}, 'token-off-both'))
    j.nfc('04000000F00001', '101'); j.wait(lambda: j.pb == 'PLAYING', 8)
    j.nfc_off(); j.wait(lambda: not j.nfc_state)
    B.quiet(5, 'more than twice token_off_s while the music goes on')
    R.check('keep playing on: still playing, still on', j.pb == 'PLAYING' and not off(), j.get('audio.playback'))
    spy = B.Spy('/j/audio/out/play')
    j.send('DO_PAUSE', {}); j.wait(lambda: j.pb == 'PAUSED')
    t0 = time.time()
    R.expect('... the music stopped: off', off, 10)
    took = float(Path(power_log).read_text().split()[0]) - t0 if off() else -1
    R.check('... about token_off_s after the music stopped', 1.8 <= took <= 5, took)
    sounds = spy.payloads('/j/audio/out/play')
    R.check('... with a little goodbye first', any(p.startswith('3\t') and p.endswith('/goodbye.mp3') for p in sounds), sounds)
    spy.close(); j.close()
    os.environ['CORE_BUILD'] = str(source)
B.check_clean_log(R, 'switch off on token removal')
R.finish()
