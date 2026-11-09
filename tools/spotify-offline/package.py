#!/usr/bin/env python3
"""Build a private-data-free OpenJooki offline test application package."""
import argparse
import hashlib
import io
import json
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

import mips
import trial

sys.path.insert(0, str(trial.ROOT / 'tools/openjooki'))
import jooki  # noqa: E402

VERSION = '2.4.21-offline.5'
SD_ROOT = '/jooki/external/openjooki-offline'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def assemble(work, output, version):
    if not re.fullmatch(r'2\.4\.21-offline\.[1-9][0-9]*', version):
        raise ValueError('Use a 2.4.21-offline.N test version')
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((work / 'mips-build.json').read_text())
    executable = work / 'cross-smoke/target' / mips.TARGET / 'release/spotify_player'
    binary = executable.read_bytes()
    if manifest['binary_sha256'] != digest(binary):
        raise ValueError('MIPS binary does not match its build manifest')
    if manifest['patches'] != {p.name: digest(p.read_bytes()) for p in mips.PATCHES}:
        raise ValueError('MIPS build is stale; rebuild with the reviewed patches')
    if binary[:6] != b'\x7fELF\x01\x01' or binary[18:20] != b'\x08\x00':
        raise ValueError('Expected a little-endian 32-bit MIPS ELF')
    subprocess.run([sys.executable, str(trial.ROOT / 'tools/openjooki/webui/build.py'), '--check'], check=True)
    with tempfile.TemporaryDirectory(prefix='offline-package-', dir=output) as temporary:
        core = Path(temporary) / 'core'
        subprocess.run([sys.executable, str(trial.ROOT / 'tools/build/bundle.py'),
                        '--out', str(core), '--version', version, '--max-kib', '400'], check=True)
        loader = jooki.load_core(str(core / 'player.lib'))
        core_files = jooki.core_side_files(str(core / 'player.lib'))
        files = {'application/jooki/lib/player.lib': loader,
                 'application/jooki/lib/core.lua': core_files[jooki.CORE_FILE],
                 'application/etc/openjooki-version': (version + '\n').encode(),
                 'sdk/spotify_player': binary,
                 'sdk/app.toml': ('download_folder = "' + SD_ROOT + '/store"\n'
                                 '[device]\nbitrate = 96\nvolume = 100\naudio_cache = false\n').encode(),
                 'sdk/build.json': (json.dumps(manifest, indent=2) + '\n').encode(),
                 'licenses/spotify-player.txt': (Path(__file__).with_name('LICENSE.spotify-player')).read_bytes()}
        web = Path(jooki.WEBUI_DIR)
        for name in jooki.WEBUI_FILES:
            data = (web / name).read_bytes()
            if name in ('index.html', 'app.js'):
                data = data.replace(b'?v=2.4.21', ('?v=' + version).encode())
            if name == 'app.js':
                data = data.replace(b"var VERSION = '2.4.21';", ("var VERSION = '" + version + "';").encode())
            files['webui/' + name] = data
        for folder in jooki.WEBUI_DIRS:
            for name in jooki.webui_dir_files(folder):
                files['webui/' + folder + '/' + name] = (web / folder / name).read_bytes()
        files['README.txt'] = (
            'OpenJooki ' + version + '\nExperimental private test package.\n\n'
            'Application: Lua core and web page. Native player: static MIPS binary for SD.\n'
            'Requires existing OpenJooki 2.4.21, mounted SD and separate Premium sign-in.\n'
            'Credentials, audio files and keys are deliberately excluded.\n'
            'Online keeps the existing vendor player; auto selects a completed local snapshot.\n'
            'Cold offline reboot/UI playback passed on one Jooki 2; physical figure acceptance remains.\n\n'
            'Inspect/install with tools/spotify-offline/install.py from the matching source branch.\n'
            'It checks the package, prepares A/B rollback and leaves account data on SD.\n'
            'Use its default check mode before explicitly selecting --apply.\n'
        ).encode()
        modes = {name: (0o700 if name == 'sdk/spotify_player' else 0o644) for name in files}
        modes['sdk/app.toml'] = 0o600
        sources = sorted((trial.ROOT / 'core').rglob('*.lua')) + sorted((web / 'src').glob('*.js'))
        source_hashes = {str(p.relative_to(trial.ROOT)): digest(p.read_bytes()) for p in sources
                         if 'spec' not in p.relative_to(trial.ROOT).parts}
        package_manifest = {
            'format': 1, 'version': version, 'base_version': '2.4.21',
            'experimental': True, 'requires_premium_for_offline': True,
            'credentials_included': False, 'music_included': False,
            'sd_root': SD_ROOT, 'native_build': manifest,
            'source_revision': trial.run(['git', 'rev-parse', 'HEAD'], cwd=trial.ROOT, capture=True).stdout.strip(),
            'source_files': source_hashes,
            'files': {name: {'sha256': digest(data), 'bytes': len(data), 'mode': modes[name]}
                      for name, data in sorted(files.items())},
        }
        files['manifest.json'] = (json.dumps(package_manifest, indent=2) + '\n').encode()
        modes['manifest.json'] = 0o644
        target = output / ('openjooki-' + version + '.tar.gz')
        with tarfile.open(target, 'w:gz', format=tarfile.USTAR_FORMAT) as archive:
            for name, data in sorted(files.items()):
                info = tarfile.TarInfo(name)
                info.size, info.mode, info.mtime = len(data), modes[name], 0
                archive.addfile(info, io.BytesIO(data))
        (output / 'manifest.json').write_bytes(files['manifest.json'])
        (output / (target.name + '.sha256')).write_text(digest(target.read_bytes()) + '  ' + target.name + '\n')
        print('Built', target, '(%d bytes; %d verified files)' % (target.stat().st_size, len(files)))
        return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, default=trial.DEFAULT_WORK)
    parser.add_argument('--out', type=Path, default=trial.ROOT / 'build/spotify-offline/test-version')
    parser.add_argument('--version', default=VERSION)
    args = parser.parse_args()
    try:
        assemble(args.work_dir.resolve(), args.out.resolve(), args.version)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
