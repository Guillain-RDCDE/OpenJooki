"""The new Wi-Fi chip firmware for every Jooki (#51, 2.5.17), on the real core.

chip_auto_s after starting, online and playing nothing, the core's own shell action takes the
package by itself, once. The trial tool (oj-esp32-trial) and the restart are stand-ins
(OJ_CHIP_TOOL, OJ_CHIP_REBOOT), as in test_chip_page.py. Checked: a Jooki on the original takes it
and restarts; the same package is never taken twice; a parent who went back, or a trial that failed,
is left alone; an older accepted package is replaced, the current one is not; while music plays,
nothing happens.
  python3 test_chip_auto.py
"""
import os
import shutil
import stat
import time
from pathlib import Path
import bench as B

R = B.Results()
F = Path('/tmp/oj-chip-auto'); shutil.rmtree(F, ignore_errors=True); F.mkdir()
TOOL = F / 'oj-esp32-trial'
TOOL.write_text('''#!/bin/sh
D=%s
case "$1" in
  status) echo "state: $(cat $D/state 2>/dev/null || echo none)"; [ -f $D/version ] && echo "version: $(cat $D/version)"; echo "log line" ;;
  install) cp "$2" $D/installed.tgz; echo staged > $D/state; echo "Ready. Restart the Jooki" ;;
esac
''' % F)
REBOOT = F / 'reboot'
REBOOT.write_text('#!/bin/sh\ndate > %s/rebooted\n' % F)
for p in (TOOL, REBOOT): p.chmod(p.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
PKG = Path(B.WEB_PUBLIC) / 'openjooki-esp32-0123abcd.tgz'
os.environ.update({'OJ_CHIP_TOOL': str(TOOL), 'OJ_CHIP_REBOOT': str(REBOOT), 'OJ_CHIP_PKG': str(F / 'candidate.tgz'),
                   'OJ_CHIP_AUTO': str(F / 'auto')})
AUTO_S = 4
config = B.core_config({'chip_package_url': 'http://127.0.0.1:%d/openjooki-esp32-0123abcd.tgz' % B.HTTP_PORT,
                        'chip_auto_s': AUTO_S}, 'chipauto')
MARK = F / 'auto.0123abcd'


def fake(state='none', version=None, keep_mark=False):
    (F / 'state').write_text(state + '\n')
    for n in ('rebooted', 'installed.tgz', 'candidate.tgz', 'version'): (F / n).unlink(missing_ok=True)
    if version: (F / 'version').write_text(version + '\n')
    if not keep_mark: MARK.unlink(missing_ok=True)


def online(j):
    # the core sets its web folder up again at every start: the package goes back in it
    PKG.write_bytes(b'the new chip firmware package\n' * 100)
    j.c.publish('/j/esp32/input/net/sta/config', '{"ssid": "Box", "signal": -50, "stat": "success", "ip": "10.0.0.2"}')


def taken(t=20):
    end = time.time() + t
    while time.time() < end:
        if (F / 'rebooted').exists(): return True
        time.sleep(0.5)
    return False


def nothing(t=AUTO_S + 8):
    time.sleep(t)
    return not (F / 'installed.tgz').exists() and not (F / 'rebooted').exists()


fake()
j = B.boot(seed=True, config=config)
online(j)
R.check('on the original, online and silent: taken by itself, then a restart', taken(AUTO_S + 30) and (F / 'installed.tgz').exists())
R.check('... and remembered for this package', MARK.exists())

fake('none', keep_mark=True)
j = B.restart(j, config=config); online(j)
R.check('the same package is never taken twice', nothing())

for st in ('restored', 'failed-no-wifi', 'restore-failed'):
    fake(st)
    j = B.restart(j, config=config); online(j)
    R.check('left alone after "%s" (a parent went back, or a trial failed)' % st, nothing())

fake('accepted', 'current')
j = B.restart(j, config=config); online(j)
R.check('the current package accepted: nothing to do', nothing())

fake('accepted', 'older')
j = B.restart(j, config=config); online(j)
R.check('an older package accepted: the newer one is taken', taken(AUTO_S + 30))

# music playing when the time comes: nothing, the core looks again 10 minutes later
fake()
j = B.restart(j, config=config); online(j)
pid = next(k for k, v in j.pls.items() if v.get('tracks'))
j.send('PLAYLIST_PLAY', {'playlistId': pid}); j.wait_state('audio.playback.state', 'PLAYING')
R.check('while music plays: nothing happens', nothing())
j.close()
B.check_clean_log(R, 'chip for every Jooki')
R.finish()
