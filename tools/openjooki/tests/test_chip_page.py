"""Settings > Advanced > Wi-Fi with several access points (docs/32), in a real browser, on the real core.

The core's own shell action fetches the package and asks the trial tool; the tool (oj-esp32-trial)
and the restart are stand-ins (OJ_CHIP_TOOL, OJ_CHIP_REBOOT), the package comes from the bench's
web server. Checked: the row and the page, the original state; trying (two taps), the download,
the install asked, the restart and its note; a refusal says why and changes nothing; a download
that fails says so; the new version in use and going back.
  python3 test_chip_page.py
"""
import os
import shutil
import stat
from pathlib import Path
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R = B.Results()
F = Path('/tmp/oj-chip-fake'); shutil.rmtree(F, ignore_errors=True); F.mkdir()
TOOL = F / 'oj-esp32-trial'
TOOL.write_text('''#!/bin/sh
D=%s
case "$1" in
  status) echo "state: $(cat $D/state 2>/dev/null || echo none)"; [ -f $D/version ] && echo "version: $(cat $D/version)"; echo "2026-11-21 log line" ;;
  install) cp "$2" $D/installed.tgz
    if [ "$(cat $D/mode)" = refuse ]; then echo "ok      no trial in progress (none)"; echo "NOT OK  the chip does not answer now"; echo "Nothing changed."; exit 1; fi
    echo staged > $D/state; echo "Ready. Restart the Jooki" ;;
  uninstall) [ "$(cat $D/state)" = accepted ] && echo restore > $D/state && echo "The original firmware is written back at the next start" ;;
esac
''' % F)
REBOOT = F / 'reboot'
REBOOT.write_text('#!/bin/sh\ndate > %s/rebooted\n' % F)
for p in (TOOL, REBOOT): p.chmod(p.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
PKG = Path(B.WEB_PUBLIC) / 'oj-test-chip.tgz'
os.environ.update({'OJ_CHIP_TOOL': str(TOOL), 'OJ_CHIP_REBOOT': str(REBOOT), 'OJ_CHIP_PKG': str(F / 'candidate.tgz')})
config = B.core_config({'chip_package_url': 'http://127.0.0.1:%d/oj-test-chip.tgz' % B.HTTP_PORT}, 'chip')


def fake(state='none', mode='ok'):
    (F / 'state').write_text(state + '\n'); (F / 'mode').write_text(mode + '\n')
    for n in ('rebooted', 'installed.tgz', 'candidate.tgz', 'version'): (F / n).unlink(missing_ok=True)


fake()
j = B.boot(seed=True, ui=True, config=config)
PKG.write_bytes(b'the new chip firmware package\n' * 100)
with sync_playwright() as pw:
    browser = pw.chromium.launch(args=['--no-sandbox'])
    pg = browser.new_page(locale='en-GB')
    errors = []
    pg.on('pageerror', lambda e: errors.append(str(e)))
    pg.on('dialog', lambda d: (errors.append('dialog: ' + d.message), d.dismiss()))

    def text(): return pg.locator('.settings').inner_text()

    def open_chip():
        pg.goto(PAGE + '/#/settings/advanced'); pg.wait_for_selector('[data-k=chipnav]')
        pg.click('[data-k=chipnav]'); pg.wait_for_selector('[data-k=chipstate]')

    pg.goto(PAGE + '/#/settings/advanced'); pg.wait_for_selector('[data-k=maintnav]')
    R.check('Advanced shows the Wi-Fi chip row', 'Wi-Fi with several access points' in pg.locator('[data-k=chipnav]').inner_text(),
            pg.locator('.settings').inner_text())
    open_chip()
    R.expect('the original version is said', lambda: 'Original version' in pg.locator('[data-k=chipstate]').inner_text(), 10, text)
    R.check('the page says what it is for and that it comes back by itself', 'same name' in text() and 'goes back to the original version by itself' in text(), text())
    R.check('no going back offered on the original', pg.locator('[data-k=chipback]').count() == 0)

    # try: two taps, then the download, the install, the restart
    pg.click('[data-k=chiptry]'); pg.wait_for_selector('[data-k=chiptrysure]')
    R.check('the first tap only asks to confirm', not (F / 'installed.tgz').exists() and pg.locator('[data-k=chipcancel]').count() == 1)
    pg.click('[data-k=chipcancel]'); pg.wait_for_selector('[data-k=chiptry]')
    R.check('cancel goes back, nothing done', not (F / 'installed.tgz').exists())
    pg.click('[data-k=chiptry]'); pg.click('[data-k=chiptrysure]')
    R.expect('the Jooki restarts once the new version is ready', lambda: (F / 'rebooted').exists(), 20)
    R.check('the package was downloaded and given to the tool, intact',
            (F / 'installed.tgz').exists() and (F / 'installed.tgz').read_bytes() == PKG.read_bytes())
    R.expect('the page says the Jooki restarts', lambda: 'The Jooki restarts' in text(), 10, text)

    # the new version in use: going back
    fake('accepted')
    open_chip()
    R.expect('the new version in use is said', lambda: 'New version in use' in pg.locator('[data-k=chipstate]').inner_text(), 10, text)
    R.check('no trying again while in use', pg.locator('[data-k=chiptry]').count() == 0)
    pg.click('[data-k=chipback]')
    R.expect('going back restarts the Jooki', lambda: (F / 'rebooted').exists() and (F / 'state').read_text().strip() == 'restore', 15)

    # a newer version than the one on trial (this OpenJooki carries a newer package): offered the same way
    fake('accepted'); (F / 'version').write_text('older\n')
    open_chip()
    R.expect('a newer version is said', lambda: 'A newer version is ready' in text(), 10, text)
    R.check('... and both trying it and going back are offered', pg.locator('[data-k=chiptry]').count() == 1 and pg.locator('[data-k=chipback]').count() == 1)
    pg.click('[data-k=chiptry]'); pg.click('[data-k=chiptrysure]')
    R.expect('the newer version: downloaded, given to the tool, the Jooki restarts', lambda: (F / 'rebooted').exists() and (F / 'installed.tgz').exists(), 20)
    fake('accepted'); (F / 'version').write_text('current\n')
    open_chip()
    R.expect('the current version: no trying again', lambda: 'New version in use' in text() and pg.locator('[data-k=chiptry]').count() == 0
             and 'newer version' not in text(), 10, text)

    # a refusal: said, nothing changed, no restart
    fake('none', 'refuse')
    open_chip(); pg.wait_for_selector('[data-k=chiptry]')
    pg.click('[data-k=chiptry]'); pg.click('[data-k=chiptrysure]')
    R.expect('a refusal says why', lambda: pg.locator('[data-k=chiprefused]').count() == 1 and 'the chip does not answer now' in text(), 20, text)
    R.check('a refusal: no restart, still the original', not (F / 'rebooted').exists() and (F / 'state').read_text().strip() == 'none')
    R.expect('a refusal: trying again is offered', lambda: pg.locator('[data-k=chiptry]').count() == 1, 10, text)

    # a download that fails
    fake('none', 'ok'); PKG.unlink()
    pg.click('[data-k=chiptry]'); pg.click('[data-k=chiptrysure]')
    R.expect('a download that fails says so', lambda: 'could not download' in text(), 20, text)
    R.check('a failed download: nothing installed, no restart', not (F / 'installed.tgz').exists() and not (F / 'rebooted').exists())
    R.check('no script error on the page, no browser dialog', not errors, errors)
    browser.close()
j.close()
B.check_clean_log(R, 'Wi-Fi chip page')
R.finish()
