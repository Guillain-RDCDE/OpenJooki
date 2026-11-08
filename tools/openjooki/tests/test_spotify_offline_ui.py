"""Offline card in the real browser bundle, with a deterministic MQTT peer.

Run on the host with Playwright installed. This verifies UI behavior and outgoing
v1 messages; core and native storage behavior have separate tests.
"""
import argparse
import contextlib
import functools
import http.server
import json
import threading
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

URI = 'spotify:playlist:' + '1' * 22
WEB = Path(__file__).resolve().parents[1] / 'webui'
PEER = """
window.MiniMqtt = function () {
  var self = this;
  window.offlinePeer = self;
  window.offlineSent = [];
  self.connect = function () { setTimeout(function () { self.onconnect(); }, 0); };
  self.subscribe = self.close = function () {};
  self.publish = function (topic, text) {
    window.offlineSent.push({topic: topic, payload: JSON.parse(text)});
    if (topic.endsWith('/GET_STATE')) setTimeout(function () {
      self.onmessage('/j/web/output/state', JSON.stringify(window.offlineInitial));
    }, 0);
    return true;
  };
};
"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=Path('build/spotify-offline/ui'))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    handler = functools.partial(QuietHandler, directory=str(WEB))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    state = {
        'db': {'playlists': {'user_1': {'title': 'Anton Krokodil', 'tracks': [],
                'spotify': {'uri': URI, 'preset': '00'}, 'star': 'Jooki.Crocodile'}},
               'tracks': {}, 'tokens': {}},
        'audio': {'config': {}, 'playback': {'state': 'STOPPED'}, 'nowPlaying': {}},
        'spotifyOffline': {'available': True, 'account_ready': True, 'modes': {},
                           'playlists': {}, 'storage': {'used_bytes': 1048576, 'quota_bytes': 536870912}},
    }
    results = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport={'width': 390, 'height': 844}, locale='de-DE')
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.add_init_script('window.offlineInitial = ' + json.dumps(state) + '; localStorage.setItem("oj.lang", "de"); localStorage.setItem("oj.parent", "1234");')
        page.route('**/mqtt.js*', lambda route: route.fulfill(content_type='application/javascript', body=PEER))
        page.route('**/oj-auth.json', lambda route: route.fulfill(json={}))
        page.goto('http://127.0.0.1:%d/#/p/user_1' % server.server_port)
        card = page.locator('[data-k=spotify-offline]')
        expect(card).to_be_visible()
        expect(card.get_by_role('button', name='Offline herunterladen', exact=True)).to_be_enabled()
        card.get_by_role('button', name='Offline herunterladen', exact=True).click()

        def sent(kind):
            return page.evaluate('(kind) => window.offlineSent.filter(x => x.topic.endsWith("/" + kind)).pop()', kind)

        assert sent('OJ_OFFLINE_SYNC')['payload'] == {'playlistId': 'user_1', 'code': '1234'}
        results.append('download button sends parent-authorized playlist identifier')

        def publish(offline):
            state['spotifyOffline'] = offline
            page.evaluate('(s) => window.offlinePeer.onmessage("/j/web/output/state", JSON.stringify(s))', state)

        offline = state['spotifyOffline']
        offline['download'] = {'uri': URI, 'phase': 'downloading', 'completed': 1, 'total': 2,
                               'tracks': [{'name': 'First', 'artists': ['Artist'], 'duration_ms': 10000},
                                          {'name': '<img src=x onerror=alert(1)>', 'artists': ['Artist'], 'duration_ms': 20000}]}
        publish(offline)
        expect(card.get_by_role('progressbar')).to_have_attribute('value', '1')
        expect(card.locator('[data-k=offline-tracks] li')).to_have_count(2)
        expect(card.locator('[data-k=offline-tracks] button')).to_have_count(0)
        expect(card.get_by_role('button', name='Offline herunterladen', exact=True)).to_be_disabled()
        results.append('incomplete download shows ordered metadata and progress without play controls')
        tracks = offline['download']['tracks']
        offline['playlists'][URI] = {'ready': True, 'bytes': 3145728, 'tracks': tracks}
        offline['download']['phase'] = 'complete'
        publish(offline)
        expect(card.locator('[data-k=offline-ready]')).to_contain_text('3.0 MiB')
        expect(card.locator('[data-k=offline-tracks] img')).to_have_count(0)
        card.locator('[data-k=offline-tracks] button').nth(1).click()
        assert sent('OJ_OFFLINE_PLAY')['payload']['trackIndex'] == 2
        card.locator('select').select_option('online')
        assert sent('OJ_OFFLINE_MODE')['payload']['mode'] == 'online'
        results.append('complete songs retain order, escape titles, and select exact one-based song index')
        results.append('original online controller remains selectable')
        for width in (390, 1440):
            page.set_viewport_size({'width': width, 'height': 1000})
            page.evaluate('window.scrollTo(0, 0)')
            page.screenshot(path=str(args.out / ('spotify-offline-%d.png' % width)), full_page=True)
            assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        results.append('mobile and desktop have no horizontal overflow')
        offline['download'].update(phase='error', error='storage_full')
        publish(offline)
        expect(card.get_by_role('alert')).to_contain_text('Nicht genug freier Speicher')
        expect(card.locator('[data-k=offline-tracks] button').first).to_be_enabled()
        results.append('full-storage error leaves the previous complete snapshot playable')
        offline.update(account_ready=False, playlists={}, download=None)
        publish(offline)
        expect(card.get_by_role('button', name='Offline herunterladen', exact=True)).to_be_disabled()
        expect(card.locator('[data-k=offline-tracks]')).to_have_count(0)
        expect(card.locator('select option[value=online]')).to_be_enabled()
        results.append('missing Premium login disables downloads and clears old account songs')
        offline['available'] = False
        publish(offline)
        expect(card).to_have_count(0)
        expect(page.locator('[data-k=sphelp]')).to_be_visible()
        assert not errors, errors
        results.append('original Spotify page works with backend disabled; no browser errors')
        browser.close()
    server.shutdown()
    server.server_close()
    (args.out / 'results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2) + '\n')
    for item in results:
        print('PASS', item)


if __name__ == '__main__':
    with contextlib.suppress(KeyboardInterrupt):
        main()
