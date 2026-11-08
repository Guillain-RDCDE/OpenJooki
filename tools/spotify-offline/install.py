#!/usr/bin/env python3
"""Inspect an offline test package; --apply installs through existing A/B rollback.

Only for an existing OpenJooki 2.4.21. Account provisioning is separate from the
archive and never imports the vendor player's credentials. Default: read-only.
"""
import argparse
import hashlib
import io
import json
import re
import shlex
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import trial

sys.path.insert(0, str(trial.ROOT / 'tools/openjooki'))
import jooki  # noqa: E402

SD_ROOT = '/jooki/external/openjooki-offline'
FLAG = '/data/openjooki/spotify-offline-enabled'
q = shlex.quote


def package(path):
    files = {}
    with tarfile.open(path, 'r:gz') as archive:
        for member in archive.getmembers():
            if not member.isfile() or member.size > 32 * 1024 * 1024 or member.name in files:
                raise ValueError('Invalid package member')
            if len(files) > 2048:
                raise ValueError('Too many package files')
            files[member.name] = archive.extractfile(member).read()
    manifest = json.loads(files.pop('manifest.json'))
    if manifest['format'] != 1 or manifest['sd_root'] != SD_ROOT or not re.fullmatch(r'2\.4\.21-offline\.[1-9][0-9]*', manifest['version']):
        raise ValueError('Unsupported package')
    if set(files) != set(manifest['files']):
        raise ValueError('Package inventory differs from its manifest')
    allowed = {'application/jooki/lib/player.lib', 'application/jooki/lib/core.lua',
               'application/etc/openjooki-version', 'sdk/spotify_player', 'sdk/app.toml',
               'sdk/build.json', 'licenses/spotify-player.txt', 'README.txt'}
    for name, data in files.items():
        parts = Path(name).parts
        if name not in allowed and not (name.startswith('webui/') and '..' not in parts and not Path(name).is_absolute()):
            raise ValueError('Unexpected destination in package')
        entry = manifest['files'][name]
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Package checksum mismatch: ' + name)
    if manifest['credentials_included'] or manifest['music_included']:
        raise ValueError('Package must not include private account data')
    binary = files['sdk/spotify_player']
    if hashlib.sha256(binary).hexdigest() != manifest['native_build']['binary_sha256']:
        raise ValueError('SDK binary differs from its build record')
    if binary[:6] != b'\x7fELF\x01\x01' or binary[18:20] != b'\x08\x00':
        raise ValueError('Expected the MIPS player')
    if files['application/etc/openjooki-version'] != (manifest['version'] + '\n').encode():
        raise ValueError('Installed version differs from the manifest')
    with tempfile.TemporaryDirectory(prefix='openjooki-package-check-') as temporary:
        core = Path(temporary)
        (core / 'player.lib').write_bytes(files['application/jooki/lib/player.lib'])
        (core / 'core.min.lua').write_bytes(files['application/jooki/lib/core.lua'])
        jooki.load_core(str(core / 'player.lib'))
        jooki.core_side_files(str(core / 'player.lib'))
    return manifest, files


def remote(host, command, **kwargs):
    result = jooki.ssh(host, command, **kwargs)
    if result.returncode:
        raise RuntimeError('Device command failed: ' + result.stderr[-300:])
    return result.stdout


def put_tar(host, target, files):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as archive:
        for name, (body, mode) in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.size, info.mode = len(body), mode
            archive.addfile(info, io.BytesIO(body))
    command = 'set -eu; umask 077; mkdir -p ' + q(target) + '; tar xzf - -C ' + q(target) + '; sync'
    result = jooki.ssh_bytes(host, command, data=data.getvalue(), timeout=120)
    if result.returncode:
        raise RuntimeError('SD transfer failed')


def select_sdk_command(target, link):
    # BusyBox mv on the Jooki has no -T; rename(2) replaces the symlink itself.
    temporary = link + '.new'
    rename = 'assert(os.rename(' + json.dumps(temporary) + ',' + json.dumps(link) + '))'
    return ('rm -f ' + q(temporary) + '; ln -s ' + q(target) + ' ' + q(temporary) +
            '; /usr/bin/lua -e ' + q(rename))


def restore_sd(host, state):
    target = state.get('previous_sdk')
    if target:
        command = select_sdk_command(target, SD_ROOT + '/current')
    else:
        command = 'rm -f ' + q(SD_ROOT + '/current')
    command += '; ' + ('mkdir -p /data/openjooki; touch ' if state.get('previous_enabled') else 'rm -f ') + q(FLAG) + '; sync'
    remote(host, 'set -eu; ' + command)


def apply(host, manifest, files, auth, state_path):
    previous = jooki._boot_part(host)
    if previous not in ('2', '3'):
        raise ValueError('Unexpected boot partition')
    old = remote(host, 'readlink ' + q(SD_ROOT + '/current') + ' || true').strip()
    enabled = remote(host, 'if test -f ' + q(FLAG) + '; then echo yes; fi').strip() == 'yes'
    state = {'version': manifest['version'], 'previous_partition': previous,
             'previous_sdk': old, 'previous_enabled': enabled, 'host': host}
    # Save the concrete rollback information before any device mutation.
    state_path.parent.mkdir(parents=True, exist_ok=True)
    with state_path.open('x') as output:
        json.dump(state, output, indent=2)
        output.write('\n')
    release = SD_ROOT + '/releases/' + manifest['version']
    put_tar(host, release, {'spotify_player': (files['sdk/spotify_player'], 0o700),
                           'build.json': (files['sdk/build.json'], 0o600)})
    remote(host, 'set -eu; chmod 700 ' + q(SD_ROOT) + '; test "$(md5sum ' + q(release + '/spotify_player') + ' | cut -d " " -f 1)" = ' + q(hashlib.md5(files['sdk/spotify_player']).hexdigest()))
    config = SD_ROOT + '/config'
    if remote(host, 'if test ! -e ' + q(config + '/app.toml') + '; then echo initialize; fi').strip():
        put_tar(host, config, {'app.toml': (files['sdk/app.toml'], 0o600)})
    if auth:
        credentials = auth / 'credentials.json'
        account_files = {'credentials.json': (credentials.read_bytes(), 0o600)}
        # A mismatched account is not silently substituted during installation.
        previous_creds = jooki.ssh_bytes(host, 'cat ' + q(SD_ROOT + '/cache/credentials.json') + ' 2>/dev/null')
        if previous_creds.returncode == 0:
            if json.loads(previous_creds.stdout).get('username') != json.loads(account_files['credentials.json'][0]).get('username'):
                raise ValueError('Forget the previous offline account before replacing it')
        for token in auth.glob('*_token.json'):
            if re.fullmatch(r'[A-Za-z0-9_-]+_token\.json', token.name):
                account_files[token.name] = (token.read_bytes(), 0o600)
        put_tar(host, SD_ROOT + '/cache', account_files)
    remote(host, 'set -eu; mkdir -p ' + q(SD_ROOT + '/store') + ' /run/openjooki/spotify-offline; '
           '(ulimit -c 0; ulimit -d 8192; ulimit -s 512; ulimit -v 65536; RUST_LOG=off ' + q(release + '/spotify_player') +
           ' -c ' + q(config) + ' -C ' + q(SD_ROOT + '/cache') + ' downloads managed --store ' + q(SD_ROOT + '/store') +
           ' --catalog /run/openjooki/spotify-offline/catalog.json --job /run/openjooki/spotify-offline/job.json catalog)')
    with tempfile.TemporaryDirectory(prefix='openjooki-install-') as temp:
        core = Path(temp)
        (core / 'player.lib').write_bytes(files['application/jooki/lib/player.lib'])
        (core / 'core.min.lua').write_bytes(files['application/jooki/lib/core.lua'])
        jooki.load_core(str(core / 'player.lib'))
        jooki.core_side_files(str(core / 'player.lib'))
        application = {'/' + name[len('application/'):]: body for name, body in files.items() if name.startswith('application/')}
        loader = application.pop(jooki.PLAYER_LIB)
        application.update({jooki.WWW_PUBLIC + '/' + name[len('webui/'):]: body for name, body in files.items() if name.startswith('webui/')})
        original_build, original_switch, original_system = jooki._webui_build, jooki.switch_or_back, jooki.system_files

        def build(_host, _core):
            original = jooki.ssh_bytes(host, 'cat ' + jooki.PLAYER_LIB + '.openjooki-orig').stdout
            import playerlib
            if not original or playerlib.is_openjooki(playerlib.decode(original)):
                raise ValueError('Original player.lib backup is missing')
            return original, loader, application

        activated = False

        def activate():
            nonlocal activated
            remote(host, 'set -eu; ' + select_sdk_command('releases/' + manifest['version'], SD_ROOT + '/current') +
                   '; mkdir -p /data/openjooki; touch ' + q(FLAG) + '; sync')
            activated = True

        def switch(_host, part, back):
            activate()
            return original_switch(_host, part, back)

        try:
            jooki._webui_build, jooki.switch_or_back = build, switch
            jooki.system_files = lambda _core=None: {'/etc/openjooki-version': 'version'}
            result = jooki.ab_webui(host, core=str(core / 'player.lib'))
            if result:
                if result != jooki.AB_LOST:
                    restore_sd(host, state)
                raise RuntimeError('A/B installation failed; see saved rollback state: ' + str(state_path))
            if not activated:
                activate()
        finally:
            jooki._webui_build, jooki.switch_or_back, jooki.system_files = original_build, original_switch, original_system
    print('Installed', manifest['version'], '; rollback state:', state_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path, nargs='?')
    parser.add_argument('--host', required=True)
    parser.add_argument('--key', type=Path, default=Path.home() / '.ssh/id_rsa')
    parser.add_argument('--known-hosts', type=Path, required=True)
    parser.add_argument('--port', type=int, default=22)
    parser.add_argument('--auth-cache', type=Path)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--rollback', action='store_true')
    parser.add_argument('--state', type=Path)
    args = parser.parse_args()
    try:
        jooki.KEY, jooki.SSH_PORT = str(args.key.expanduser().resolve()), str(args.port)
        jooki.SSH_OPTS = [
            'StrictHostKeyChecking=yes' if item.startswith('StrictHostKeyChecking=') else
            'UserKnownHostsFile=' + str(args.known_hosts.resolve()) if item.startswith('UserKnownHostsFile=') else item
            for item in jooki.SSH_OPTS
        ]
        if args.rollback:
            if not args.state:
                raise ValueError('--rollback requires --state')
            state = json.loads(args.state.read_text())
            if state['host'] != args.host or state['previous_partition'] not in ('2', '3'):
                raise ValueError('Rollback state belongs to another device')
            print('Rollback target: p' + state['previous_partition'])
            if args.apply:
                restore_sd(args.host, state)
                if jooki.ab_switch(args.host, state['previous_partition']):
                    raise RuntimeError('Rollback did not complete')
            return
        if not args.archive:
            raise ValueError('Package archive required')
        manifest, files = package(args.archive)
        version = remote(args.host, 'cat /etc/openjooki-version').strip()
        if version != manifest['base_version'] and not version.startswith(manifest['base_version'] + '-offline.'):
            raise ValueError('Expected existing OpenJooki ' + manifest['base_version'])
        mounted = remote(args.host, "awk '$2 == \"/jooki/external\" {print $3}' /proc/mounts").strip()
        if mounted != 'ext4':
            raise ValueError('The persistent SD filesystem is not mounted')
        part = jooki._boot_part(args.host)
        if part not in ('2', '3'):
            raise ValueError('Unexpected partition layout')
        print('Verified', manifest['version'], ';', len(files), 'checksums; current:', version, 'on p' + part)
        if args.auth_cache and not (args.auth_cache / 'credentials.json').is_file():
            raise ValueError('Separate SDK credentials.json is missing')
        if not args.apply:
            print('Read-only check complete. --apply prepares the SD backend, clones A/B, installs and reboots.')
            return
        state_path = args.state or args.archive.parent / ('install-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S') + '.json')
        jooki.BKP = str(args.archive.parent / 'private-backups')
        apply(args.host, manifest, files, args.auth_cache, state_path)
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
