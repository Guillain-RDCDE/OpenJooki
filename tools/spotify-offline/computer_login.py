#!/usr/bin/env python3
"""Computer OAuth companion for the experimental OpenJooki Spotify connection.

Start this on the computer whose browser will receive Spotify's loopback callback.
Tokens travel to the Jooki over authenticated SSH; MQTT carries status only.
"""
import argparse
import hashlib
import io
import json
import os
import re
import shlex
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.request
from pathlib import Path

import trial

sys.path.insert(0, str(trial.ROOT / 'tools/openjooki'))
import jooki  # noqa: E402

SD_ROOT = '/jooki/external/openjooki-offline'
AUTH_URL = re.compile(r'Browse to: (https://accounts\.spotify\.com/authorize\?\S+)')


class LoginFailure(Exception):
    pass


class Companion:
    def __init__(self, host, executable, parent_code=''):
        import paho.mqtt.client as mqtt
        self.host, self.executable, self.parent_code = host, executable, parent_code
        self.state, self.lock = {}, threading.RLock()
        self.process, self.worker = None, None
        self.cancelled = threading.Event()
        self.seen = set()
        with urllib.request.urlopen('http://' + host + '/oj-auth.json', timeout=8) as response:
            credentials = json.load(response)
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='openjooki-oauth-' + str(os.getpid()), transport='websockets')
        self.client.username_pw_set(credentials['mqttUser'], credentials['mqttPass'])
        self.client.on_connect = self.connected
        self.client.on_message = self.received
        self.client.connect(host, int(credentials.get('wsPort', 8000)))
        self.client.loop_start()

    def connected(self, client, _userdata, _flags, _rc, _properties):
        client.subscribe('/j/web/output/#')
        client.publish('/j/web/input/GET_STATE', '{}')

    def received(self, _client, _userdata, message):
        try:
            data = json.loads(message.payload)
        except (ValueError, UnicodeError):
            return
        if message.topic == '/j/web/output/state':
            with self.lock:
                if isinstance(data, dict):
                    self.state.update(data)
        elif message.topic == '/j/web/output/error' and isinstance(data, dict) and data.get('msg') == 'PARENT_CODE_REQUIRED':
            print('Parent code required: restart with --parent-code-file.', flush=True)

    def status(self, phase, request=None, **fields):
        payload = {'phase': phase, **fields}
        if request:
            payload['request'] = request
        if self.parent_code:
            payload['code'] = self.parent_code
        return self.client.publish('/j/web/input/OJ_OFFLINE_AUTH_HELPER', json.dumps(payload))

    def requested(self):
        with self.lock:
            offline = self.state.get('spotifyOffline') or {}
            return dict(offline.get('auth') or {})

    def current(self, request):
        auth = self.requested()
        return not self.cancelled.is_set() and auth.get('request') == request and auth.get('phase') in ('requested', 'working')

    def ssh(self, command, data=None, timeout=45):
        result = jooki.ssh_bytes(self.host, command, data=data, timeout=timeout)
        if result.returncode:
            raise LoginFailure('device_connection_failed')
        return result.stdout

    def copy_existing_metadata(self, cache):
        command = ('set -eu; cd ' + shlex.quote(SD_ROOT + '/cache') + '; set --; '
                   'for f in offline-account.json *_token.json; do if test -f "$f"; then set -- "$@" "$f"; fi; done; '
                   'test "$#" -gt 0; tar czf - "$@"')
        try:
            data = self.ssh(command)
        except LoginFailure:
            return
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            for item in archive.getmembers():
                if not item.isfile() or item.size > 1024 * 1024 or '/' in item.name or '\\' in item.name:
                    raise LoginFailure('invalid_account_cache')
                if item.name != 'offline-account.json' and not re.fullmatch(r'[A-Za-z0-9_-]+_token\.json', item.name):
                    raise LoginFailure('invalid_account_cache')
                destination = cache / item.name
                destination.write_bytes(archive.extractfile(item).read())
                destination.chmod(0o600)

    def run_sdk(self, request, folder, action):
        store = folder / 'store'
        command = [str(self.executable), '-c', str(folder / 'config'), '-C', str(folder / 'cache'),
                   'downloads', 'managed', '--store', str(store), '--catalog', str(store / 'catalog.json'),
                   '--job', str(store / 'job.json'), action]
        env = dict(os.environ, RUST_LOG='error')
        self.process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        deadline = time.monotonic() + 300
        lines = []
        # A reader thread allows cancellation and a deadline while the SDK waits for a browser.
        def read():
            for line in self.process.stdout:
                lines.append(line)
                match = AUTH_URL.search(line)
                if match and self.current(request):
                    self.status('url', request, url=match.group(1))
        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        try:
            while self.process.poll() is None:
                if not self.current(request):
                    raise LoginFailure('cancelled')
                if time.monotonic() > deadline:
                    raise LoginFailure('login_timeout')
                time.sleep(0.2)
            reader.join(timeout=2)
            if self.process.returncode:
                detail = ''.join(lines).lower()
                if 'does not support' in detail and 'accounts' in detail or 'premium_required' in detail:
                    raise LoginFailure('premium_required')
                if 'account_changed' in detail or 'same account' in detail:
                    raise LoginFailure('account_mismatch')
                if '429' in detail or 'too many requests' in detail:
                    raise LoginFailure('rate_limited')
                raise LoginFailure('login_failed')
        finally:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=5)
            self.process.stdout.close()
            self.process = None

    def upload(self, request, cache):
        info_path = cache / 'offline-account.json'
        info = json.loads(info_path.read_text())
        username = info.get('username')
        if not isinstance(username, str) or hashlib.sha256(username.encode()).hexdigest() != info.get('account_id'):
            raise LoginFailure('invalid_account_cache')
        info['request'] = request
        info_path.write_text(json.dumps(info) + '\n')
        payload = io.BytesIO()
        with tarfile.open(fileobj=payload, mode='w:gz') as archive:
            for file in sorted(cache.iterdir()):
                if file.name not in ('offline-account.json', 'credentials.json') and not re.fullmatch(r'[A-Za-z0-9_-]+_token\.json', file.name):
                    continue
                data = file.read_bytes()
                item = tarfile.TarInfo(file.name)
                item.size, item.mode = len(data), 0o600
                archive.addfile(item, io.BytesIO(data))
        if not self.current(request):
            raise LoginFailure('cancelled')
        stage = SD_ROOT + '/auth-stage/' + request + '/cache'
        self.ssh('set -eu; umask 077; mkdir -p ' + shlex.quote(stage) + '; tar xzf - -C ' + shlex.quote(stage) + '; sync', data=payload.getvalue())
        if not self.current(request):
            self.cleanup_stage(request)
            raise LoginFailure('cancelled')
        self.status('complete', request).wait_for_publish(timeout=5)
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            auth = self.requested()
            if auth.get('request') != request or auth.get('phase') in ('logged_out', 'cancelled'):
                raise LoginFailure('cancelled')
            if auth.get('phase') == 'complete':
                return
            if auth.get('phase') == 'error':
                raise LoginFailure('activation_failed')
            time.sleep(0.2)
        raise LoginFailure('activation_failed')

    def cleanup_stage(self, request):
        command = [SD_ROOT + '/current/spotify_player', '-c', SD_ROOT + '/config', '-C', SD_ROOT + '/cache',
                   'downloads', 'managed', '--store', SD_ROOT + '/store',
                   '--catalog', '/run/openjooki/spotify-offline/catalog.json',
                   '--job', '/run/openjooki/spotify-offline/job.json', '--request', request, 'cancel-login']
        self.ssh('umask 077; ' + shlex.join(command))

    def authenticate(self, auth):
        request, mode = auth['request'], auth.get('mode', 'metadata')
        try:
            self.status('working', request)
            with tempfile.TemporaryDirectory(prefix='openjooki-oauth-') as temporary:
                folder = Path(temporary)
                for name in ('config', 'cache'):
                    (folder / name).mkdir(mode=0o700)
                (folder / 'config/app.toml').write_text('download_folder = ' + json.dumps(str(folder / 'store')) + '\n[device]\nbitrate = 96\naudio_cache = false\n')
                cache = folder / 'cache'
                if mode == 'metadata':
                    self.run_sdk(request, folder, 'metadata-login')
                else:
                    with self.lock:
                        offline = self.state.get('spotifyOffline') or {}
                        upgrading = bool(offline.get('metadata_ready') and not offline.get('account_ready'))
                    if upgrading:
                        self.copy_existing_metadata(cache)
                    before = cache / 'offline-account.json'
                    metadata = json.loads(before.read_text()) if before.exists() else None
                    self.run_sdk(request, folder, 'login')
                    info = json.loads((cache / 'offline-account.json').read_text())
                    if metadata and info.get('username') != metadata.get('username'):
                        raise LoginFailure('account_mismatch')
                    info['metadata_ready'] = True
                    (cache / 'offline-account.json').write_text(json.dumps(info) + '\n')
                self.upload(request, cache)
            print('Spotify permission saved on Jooki (' + mode + ').', flush=True)
        except (LoginFailure, OSError, ValueError, subprocess.SubprocessError) as error:
            code = str(error) if isinstance(error, LoginFailure) else 'login_failed'
            if self.current(request):
                self.status('error', request, error=code)
            print('Spotify sign-in ended: ' + code, flush=True)
        finally:
            try:
                self.cleanup_stage(request)
            except (OSError, LoginFailure, subprocess.SubprocessError):
                pass

    def run(self):
        print('Computer helper connected. Open Spotify settings on the Jooki to sign in.', flush=True)
        heartbeat = 0.0
        try:
            while True:
                auth = self.requested()
                if self.worker and self.worker.is_alive():
                    if auth.get('phase') not in ('requested', 'working', 'checking'):
                        self.cancelled.set()
                elif auth.get('phase') == 'requested' and auth.get('request') not in self.seen:
                    request = auth['request']
                    if not re.fullmatch(r'[0-9-]{1,64}', request):
                        continue
                    self.seen.add(request)
                    self.cancelled.clear()
                    self.worker = threading.Thread(target=self.authenticate, args=(auth,), daemon=True)
                    self.worker.start()
                if time.monotonic() >= heartbeat:
                    self.status('ready')
                    heartbeat = time.monotonic() + 5
                time.sleep(0.2)
        finally:
            self.cancelled.set()
            if self.worker:
                self.worker.join(timeout=8)
            self.client.loop_stop()
            self.client.disconnect()


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', required=True)
    parser.add_argument('--known-hosts', type=Path, required=True)
    parser.add_argument('--key', type=Path, default=Path.home() / '.ssh/id_rsa')
    parser.add_argument('--port', type=int, default=22)
    parser.add_argument('--parent-code-file', type=Path)
    parser.add_argument('--work-dir', type=Path, default=trial.DEFAULT_WORK)
    args = parser.parse_args()
    try:
        source = trial.prepare(args.work_dir.expanduser().resolve())
        if trial.needs_build(source):
            trial.build(source)
        jooki.KEY, jooki.SSH_PORT = str(args.key.expanduser().resolve()), str(args.port)
        jooki.SSH_OPTS = [('StrictHostKeyChecking=yes' if item.startswith('StrictHostKeyChecking=') else
                           'UserKnownHostsFile=' + str(args.known_hosts.resolve()) if item.startswith('UserKnownHostsFile=') else item) for item in jooki.SSH_OPTS]
        code = args.parent_code_file.read_text().strip() if args.parent_code_file else ''
        Companion(args.host, trial.binary(source), code).run()
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError, ImportError, subprocess.SubprocessError) as error:
        parser.exit(1, 'Computer helper failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
