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
        'spotify': {'saved': False},
        'spotifyOffline': {'available': True, 'account_ready': True, 'metadata_ready': True, 'account_id': 'account-one', 'modes': {},
                           'download': {'uri': URI, 'phase': 'error', 'completed': 2, 'total': 710,
                                        'tracks': [{'name': 'Cached first'}, {'name': 'Cached second'}]},
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
        page.wait_for_function('window.offlineSent.some(x => x.topic.endsWith("/OJ_OFFLINE_PREVIEW"))')
        results.append('partial cached audio still requests the complete independent song metadata')

        def publish(offline):
            state['spotifyOffline'] = offline
            page.evaluate('(s) => window.offlinePeer.onmessage("/j/web/output/state", JSON.stringify(s))', state)

        offline = state['spotifyOffline']
        titles = page.locator('[data-k=spotify-titles]')
        tracks = [{'uri': 'spotify:track:' + str(i % 9 + 1) * 22,
                   'name': 'Kapitel %02d – Anton und das große Abenteuer' % (i + 1),
                   'artists': ['Die Geschichtenfreunde'], 'album': 'Neue Abenteuer',
                   'duration_ms': 180000} for i in range(50)]
        tracks[1]['name'] = '<img src=x onerror=alert(1)>'
        offline['previews'] = {URI: {'phase': 'complete', 'offset': 0, 'total': 710, 'tracks': tracks}}
        publish(offline)
        expect(titles.locator('li')).to_have_count(50)
        expect(titles.locator('img')).to_have_count(0)
        expect(titles).to_contain_text('1–50 / 710')
        expect(titles.get_by_role('button', name='Weiter', exact=True)).to_be_enabled()
        titles.get_by_role('button', name='Weiter', exact=True).click()
        page.wait_for_timeout(30)
        assert sent('OJ_OFFLINE_PREVIEW')['payload']['offset'] == 50
        results.append('songs load before downloads, escape markup, and request bounded pages of a 710-song playlist')
        offline['previews'][URI] = {'phase': 'complete', 'offset': 50, 'total': 710, 'tracks': tracks}
        offline['playlists'][URI] = {'ready': True, 'total_tracks': 710, 'bytes': 3145728, 'tracks': tracks}
        publish(offline)
        titles.locator('li button').nth(1).click()
        assert sent('OJ_OFFLINE_PLAY')['payload']['trackIndex'] == 52
        card.locator('select').select_option('online')
        assert sent('OJ_OFFLINE_MODE')['payload']['mode'] == 'online'
        results.append('a paged song starts its exact global one-based index; original online mode remains selectable')
        other_uri = 'spotify:playlist:' + '2' * 22
        state['db']['playlists']['user_2'] = {'title': 'Anton Fuchs', 'tracks': [], 'spotify': {'uri': other_uri}}
        offline['download'] = {'uri': other_uri, 'phase': 'downloading', 'completed': 12, 'total': 710, 'bytes': 84562432}
        publish(offline)
        expect(card.locator('[data-k=offline-progress] a')).to_have_attribute('href', '#/p/user_2')
        card.get_by_role('button', name='Zur Download-Queue hinzufügen', exact=True).click()
        assert sent('OJ_OFFLINE_SYNC')['payload']['playlistId'] == 'user_1'
        offline['queue'] = [{'playlist': 'user_1', 'uri': URI, 'title': 'Anton Krokodil'}]
        publish(offline)
        expect(card).to_contain_text('Platz 1 in der Download-Warteschlange')
        card.get_by_role('button', name='Aus Queue entfernen', exact=True).click()
        assert sent('OJ_OFFLINE_CANCEL_QUEUED')['payload']['playlistId'] == 'user_1'
        results.append('another active download allows enqueueing and shows queue position and cancellation')
        for width in (390, 1440):
            page.set_viewport_size({'width': width, 'height': 1000})
            page.evaluate('window.scrollTo(0, 0)')
            page.screenshot(path=str(args.out / ('spotify-offline-%d.png' % width)), full_page=True)
            card.scroll_into_view_if_needed()
            page.screenshot(path=str(args.out / ('spotify-offline-viewport-%d.png' % width)))
            assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        results.append('mobile and desktop have no horizontal overflow')
        offline['download'] = {'uri': URI, 'phase': 'error', 'error': 'storage_full'}
        offline['queue_paused'] = 'storage_full'
        publish(offline)
        expect(card.get_by_role('alert')).to_contain_text('Nicht genug freier Speicher')
        expect(titles.locator('li button').first).to_be_enabled()
        card.get_by_role('button', name='Warteschlange fortsetzen', exact=True).click()
        assert sent('OJ_OFFLINE_RESUME_QUEUE') is not None
        results.append('full storage preserves complete audio and offers an explicit queue restart')
        offline.update(account_ready=False, metadata_ready=True, playlists={}, download=None)
        publish(offline)
        expect(card).to_have_count(0)
        expect(page.locator('[data-k=spotify-metadata]')).to_be_visible()
        expect(titles.locator('li')).to_have_count(50)
        expect(titles.locator('li button')).to_have_count(0)
        results.append('Free metadata permission retains song lists and hides all offline download/play controls')
        offline['helper_ready'] = True
        offline['account_name'] = 'test-account'
        publish(offline)
        page.goto('http://127.0.0.1:%d/#/settings/spotify' % server.server_port)
        connection = page.locator('[data-k=spotify-connection]')
        expect(connection).to_contain_text('test-account')
        connection.locator('[data-k=spotify-premium-login]').click()
        assert sent('OJ_OFFLINE_LOGIN')['payload']['mode'] == 'premium'
        connection.locator('[data-k=spotify-oauth-logout]').click()
        page.get_by_role('dialog').get_by_role('button', name='Abmelden', exact=True).click()
        assert sent('OJ_OFFLINE_FORGET') is not None
        offline.update(metadata_ready=False, account_id=None, account_name=None, previews={})
        publish(offline)
        connection.locator('[data-k=spotify-oauth]').click()
        assert sent('OJ_OFFLINE_LOGIN')['payload']['mode'] == 'metadata'
        results.append('settings expose separate metadata/Premium computer OAuth and confirmed logout')
        page.goto('http://127.0.0.1:%d/#/p/user_1' % server.server_port)
        expect(page.locator('[data-k=spotify-metadata]')).to_be_visible()
        expect(titles.locator('li')).to_have_count(0)
        offline['available'] = False
        publish(offline)
        expect(card).to_have_count(0)
        expect(page.locator('[data-k=sphelp]')).to_be_visible()
        assert not errors, errors
        results.append('logout clears account songs and the original page works with the optional backend disabled')
        browser.close()
    server.shutdown()
    server.server_close()
    (args.out / 'results.json').write_text(json.dumps({'passed': len(results), 'checks': results}, indent=2) + '\n')
    for item in results:
        print('PASS', item)


if __name__ == '__main__':
    with contextlib.suppress(KeyboardInterrupt):
        main()
