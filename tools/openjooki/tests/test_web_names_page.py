"""Other addresses for the page (#45), in a real browser.

A parent whose browsers cannot open .local names points a name of their own DNS at the Jooki.
Here Chromium resolves those names to the bench (--host-resolver-rules), so the page is opened
exactly as at home:
  - a home-network name (jooki.lan) opens the page and connects, with nothing to set;
  - a name of one's own DNS is refused ("bad host") until it is listed;
  - Settings > Advanced > Other addresses lists it (an address pasted whole is cleaned), and
    the page then opens and connects under that name; a bad name is said, and nothing is sent;
  - an empty list forgets the names.
  python3 test_web_names_page.py
"""
import json
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R = B.Results()
j = B.boot(seed=True, ui=True)
spy = B.Spy('/j/web/input/OJ_WEB_NAMES')
PORT = B.HTTP_PORT
NAMES = ('jooki.lan', 'jooki.example.com', 'kids-room')
with sync_playwright() as pw:
    browser = pw.chromium.launch(args=['--no-sandbox', '--host-resolver-rules=' + ', '.join('MAP %s 127.0.0.1' % n for n in NAMES)])
    pg = browser.new_page(locale='en-GB')
    errors = []
    pg.on('pageerror', lambda e: errors.append(str(e)))

    def opens(host):
        """The page under http://host:port/ loads and connects to the Jooki."""
        r = pg.goto('http://%s:%d/#/settings' % (host, PORT))
        if not r or r.status != 200: return 'HTTP %s' % (r and r.status)
        try: pg.wait_for_selector('.hsub .dot.on', timeout=15000)
        except Exception as e: return 'not connected: %s' % e
        return True

    R.check('a home-network name opens the page and connects, nothing to set (jooki.lan)', opens('jooki.lan') is True, opens('jooki.lan'))
    r = pg.goto('http://jooki.example.com:%d/' % PORT)
    R.check('a name of your own DNS is refused before it is listed ("bad host")', r.status == 421 and 'bad host' in pg.content(), (r.status, pg.content()[:200]))

    # the setting, from the usual address
    pg.goto(PAGE + '/#/settings/advanced'); pg.wait_for_selector('[data-k=addrnav]')
    R.check('Advanced shows Other addresses, none yet', 'Other addresses' in pg.locator('[data-k=addrnav]').inner_text() and 'None' in pg.locator('[data-k=addrnav]').inner_text(),
            pg.locator('[data-k=addrnav]').inner_text())
    pg.click('[data-k=addrnav]'); pg.wait_for_selector('[data-k=addr]')
    R.check('the page says what it is for', 'own DNS' in pg.locator('.settings').inner_text())
    # a bad name: said on the page, nothing sent
    mark = spy.mark()
    pg.fill('[data-k=addr]', 'jooki.example.com\nnot_a name')
    pg.click('[data-k=addrsave]'); pg.wait_for_selector('text=Up to 5 names')
    R.check('a bad name is said and nothing is sent', not spy.since(mark, '/j/web/input/OJ_WEB_NAMES'))
    # an address pasted whole, and a second name
    mark = spy.mark()
    pg.fill('[data-k=addr]', 'http://Jooki.Example.com:%d/#/settings\nkids-room' % PORT)
    pg.click('[data-k=addrsave]')
    R.expect('the cleaned names reach the Jooki', lambda: spy.since(mark, '/j/web/input/OJ_WEB_NAMES'))
    sent = json.loads(spy.since(mark, '/j/web/input/OJ_WEB_NAMES')[0][1])
    R.check('sent as host names only', sent.get('names') == ['jooki.example.com', 'kids-room'], sent)
    R.expect('the Jooki keeps them', lambda: (j.maint or {}).get('web_names') == ['jooki.example.com', 'kids-room'], 5, lambda: j.maint)
    R.check('no error message after a good save', pg.locator('text=Up to 5 names').count() == 0)
    pg.goto(PAGE + '/#/settings/advanced'); pg.wait_for_selector('[data-k=addrnav]')
    pg.wait_for_function("() => document.querySelector('[data-k=addrnav]').innerText.indexOf('jooki.example.com') >= 0")
    R.check('Advanced shows the names', 'kids-room' in pg.locator('[data-k=addrnav]').inner_text(), pg.locator('[data-k=addrnav]').inner_text())

    R.check('the page opens and connects under the listed name', opens('jooki.example.com') is True, opens('jooki.example.com'))
    R.check('and under a one-word name', opens('kids-room') is True, opens('kids-room'))

    # forget them, from the page opened under one of them
    pg.goto('http://jooki.example.com:%d/#/settings/addr' % PORT); pg.wait_for_selector('[data-k=addr]')
    pg.wait_for_function("() => document.querySelector('[data-k=addr]').value.indexOf('kids-room') >= 0")
    pg.fill('[data-k=addr]', ''); pg.click('[data-k=addrsave]')
    R.expect('an empty list forgets them', lambda: (j.maint or {}).get('web_names') == [], 5, lambda: j.maint)
    r = pg.goto('http://jooki.example.com:%d/' % PORT)
    R.check('the forgotten name is refused again', r.status == 421, r.status)
    R.check('no JavaScript errors', not errors, errors)
    browser.close()
B.check_clean_log(R, 'other addresses page')
spy.close(); j.close(); R.finish()
