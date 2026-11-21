"""The parent code in a real browser (#53): when the page asks for it, what closing the question
does, and when a phone or computer remembers it.

  - a protected setting asks for the code; closing the question (outside, or Escape) changes
    nothing, says so, and the switch shows the Jooki's real setting again;
  - the code typed is used for this visit only, unless "remember" is ticked;
  - a device that remembers it says so in Settings > Parent code, and can forget it there;
  - setting the code from the page does not make that device remember it for ever.
The Jooki itself refuses without the code whatever the page does (test_security_backend.py).
  python3 test_parent_page.py
"""
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R = B.Results()
j = B.boot(seed=True, ui=True)
CODE = '4826'
j.send('OJ_PARENT_CLEAR', {'current': CODE})
j.send('SET_CFG', {'shuffle_mode': False}); j.wait(lambda: j.get('audio.config.shuffle_mode') is False)
with sync_playwright() as pw:
    browser = pw.chromium.launch(args=['--no-sandbox'])
    ctx = browser.new_context(locale='en-GB')
    pg = ctx.new_page()
    errors = []
    pg.on('pageerror', lambda e: errors.append(str(e)))
    pg.on('dialog', lambda d: (errors.append('dialog: ' + d.message), d.dismiss()))

    def shuffle(): return j.get('audio.config.shuffle_mode')
    def play_page():
        pg.goto(PAGE + '/#/settings/play'); pg.reload(); pg.wait_for_selector('[data-k=shuffle]')
    def asks():
        try: pg.wait_for_selector('[data-k=pask]', timeout=5000); return True
        except Exception: return False
    def toggle(): pg.click('label:has([data-k=shuffle])')

    # the code set from the page: used at once, but this browser does not keep it for ever
    pg.goto(PAGE + '/#/settings/parent'); pg.wait_for_selector('[data-k=parent]')
    pg.click('label:has([data-k=parent])'); pg.wait_for_selector('[data-k=pnew]')
    pg.fill('[data-k=pnew]', CODE); pg.click('.sheet .btn.primary')
    R.expect('the code is set from the page', lambda: (j.maint or {}).get('parent') is True, 5, lambda: j.maint)
    R.check('setting it does not make this browser remember it', pg.evaluate("localStorage.getItem('oj.parent')") in (None, ''),
            pg.evaluate("localStorage.getItem('oj.parent')"))

    # a protected switch asks for the code; closing the question changes nothing and says so
    play_page(); toggle()
    R.check('a protected setting asks for the code', asks())
    pg.mouse.click(5, 5)
    R.expect('closed outside: the question goes', lambda: pg.locator('[data-k=pask]').count() == 0, 5)
    R.expect('... it says nothing was changed', lambda: 'needs the parent code' in pg.locator('body').inner_text(), 5)
    R.check('... the Jooki did not change', shuffle() is False)
    R.expect('... and the switch shows the real setting again', lambda: not pg.is_checked('[data-k=shuffle]'), 5)
    toggle(); R.check('asked again', asks())
    pg.keyboard.press('Escape')
    R.expect('closed with Escape: the same', lambda: pg.locator('[data-k=pask]').count() == 0 and not pg.is_checked('[data-k=shuffle]') and shuffle() is False, 5)

    # the code typed, not remembered: the change is made, and the next visit asks again
    toggle(); asks()
    R.check('remembering is off unless ticked', not pg.is_checked('[data-k=premember]'))
    pg.fill('[data-k=pask]', CODE); pg.keyboard.press('Enter')
    R.expect('with the code the change is made', lambda: shuffle() is True, 5)
    R.check('not remembered on this device', pg.evaluate("localStorage.getItem('oj.parent')") in (None, ''))
    play_page(); toggle()
    R.check('a new visit asks again', asks())

    # remembered: never asked here again, said in Settings, and forgotten there
    pg.check('[data-k=premember]'); pg.fill('[data-k=pask]', CODE); pg.keyboard.press('Enter')
    R.expect('remembered: the change is made', lambda: shuffle() is False, 5)
    play_page(); toggle()
    R.expect('remembered: no question on the next visit, the change is made', lambda: shuffle() is True, 5)
    R.check('... and no question shown', pg.locator('[data-k=pask]').count() == 0)
    pg.goto(PAGE + '/#/settings/parent'); pg.wait_for_selector('[data-k=pforget]')
    R.check('Settings says this device remembers the code', 'remembers the code' in pg.locator('[data-k=pforget]').inner_text())
    pg.click('[data-k=pforget]')
    R.expect('forgotten here', lambda: pg.evaluate("localStorage.getItem('oj.parent')") in (None, '') and pg.locator('[data-k=pforget]').count() == 0, 5)
    play_page(); toggle()
    R.check('after forgetting, asked again', asks())
    pg.keyboard.press('Escape')

    # a device that does not remember: nothing said in Settings
    pg.goto(PAGE + '/#/settings/parent'); pg.wait_for_selector('[data-k=pchange]')
    R.check('a device that does not remember: no such row', pg.locator('[data-k=pforget]').count() == 0)
    R.check('no script error on the page, no browser dialog', not errors, errors)
    browser.close()
j.send('OJ_PARENT_CLEAR', {'current': CODE}); j.wait(lambda: (j.maint or {}).get('parent') is False)
j.close()
B.check_clean_log(R, 'parent code page')
R.finish()
