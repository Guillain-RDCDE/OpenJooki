"""Playlist Play starts a fresh random draw; the player and books keep resume behaviour."""
import json
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R = B.Results()
def pre():
    path = B.DB + '/playlists.json'
    pls = json.load(open(path))
    pls['user_5']['audiobook'] = True
    json.dump(pls, open(path, 'w'))
    json.dump({'_': {'version': 1}, 'enabled': False}, open(B.DB + '/bedtime.json', 'w'))
    json.dump({'_': {'version': 1}, 'random_start': True, 'shuffle_mode': False}, open(B.DB + '/audiocfg.json', 'w'))
    json.dump({'_': {'version': 1}, 'user_5': {'id': pls['user_5']['tracks'][1], 'pos': 60000}}, open(B.DB + '/resume.json', 'w'))
j = B.boot(seed=True, ui=True, pre=pre)
spy = B.Spy('/j/web/input/PLAYLIST_PLAY', '/j/audio/out/play')
with sync_playwright() as pw:
    browser = pw.chromium.launch(args=['--no-sandbox'])
    pg = browser.new_page(locale='en-GB')
    errors = []
    pg.on('pageerror', lambda e: errors.append(str(e)))
    def click_play(selector, fresh):
        mark = spy.mark()
        pg.locator(selector).click()
        R.expect('playlist click reaches the core', lambda: spy.since(mark, '/j/web/input/PLAYLIST_PLAY'))
        request = json.loads(spy.since(mark, '/j/web/input/PLAYLIST_PLAY')[0][1])
        R.check('fresh random request' if fresh else 'normal resume request', request.get('restart', False) is fresh, request)
        return mark
    for route, selector in (('/#/', '[data-pl=user_1] button.play'), ('/#/p/user_1', '.actions .btn.primary')):
        pg.goto(PAGE + route)
        pg.wait_for_selector(selector)
        for _ in range(2):
            mark = click_play(selector, True)
            R.expect('each random Play loads a song, including when the same list is already playing', lambda: spy.since(mark, '/j/audio/out/play'))
            j.wait_state('audio.playback.state', 'PLAYING')
    j.v2('playlist.update', {'id': 'user_1', 'random_start': False})
    pg.goto(PAGE + '/#/p/user_1');pg.wait_for_selector('[data-k=plrandomstart]')
    pg.wait_for_function("() => document.querySelector('[data-k=plrandomstart]').value === 'off'")
    click_play('.actions .btn.primary', False)
    # Explicit on also works while the global default is off.
    j.send('SET_CFG', {'random_start': False})
    j.v2('playlist.update', {'id': 'user_1', 'random_start': True})
    pg.wait_for_function("() => document.querySelector('[data-k=plrandomstart]').value === 'on'")
    click_play('.actions .btn.primary', True)
    pg.goto(PAGE + '/#/p/user_5');pg.wait_for_selector('.actions .btn.primary')
    click_play('.actions .btn.primary', False)
    R.expect('audiobook starts at its saved chapter', lambda: j.np.get('playlistId') == 'user_5' and j.np.get('trackIndex') == 2)
    R.check('no browser errors', not errors, errors)
    browser.close()
B.check_clean_log(R, 'random playlist Play')
spy.close();j.close();R.finish()
