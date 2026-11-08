"""Package checks use an invented MIPS-header fixture; no device or Spotify data."""
import hashlib
import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path

import install
import playerlib


class PackageContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'candidate.tar.gz'
        self.files = {
            'application/jooki/lib/player.lib': playerlib.encode("_OPENJOOKI_CORE='2.4.21-offline.1'\n"),
            'application/jooki/lib/core.lua': b'-- fixture\n',
            'application/etc/openjooki-version': b'2.4.21-offline.1\n',
            'sdk/spotify_player': b'\x7fELF\x01\x01' + bytes(12) + b'\x08\x00',
        }
        self.manifest = {'format': 1, 'version': '2.4.21-offline.1', 'sd_root': install.SD_ROOT,
                         'credentials_included': False, 'music_included': False}

    def archive(self, mutate=None, extra_link=False):
        self.manifest['native_build'] = {'binary_sha256': hashlib.sha256(self.files['sdk/spotify_player']).hexdigest()}
        self.manifest['files'] = {name: {'bytes': len(body), 'sha256': hashlib.sha256(body).hexdigest()}
                                  for name, body in self.files.items()}
        if mutate:
            mutate()
        with tarfile.open(self.path, 'w:gz') as out:
            for name, body in list(self.files.items()) + [('manifest.json', json.dumps(self.manifest).encode())]:
                member = tarfile.TarInfo(name)
                member.size = len(body)
                out.addfile(member, io.BytesIO(body))
            if extra_link:
                member = tarfile.TarInfo('webui/link')
                member.type, member.linkname = tarfile.SYMTYPE, '/etc'
                out.addfile(member)

    def test_exact_inventory_and_loader_are_accepted(self):
        self.archive()
        manifest, files = install.package(self.path)
        self.assertEqual(manifest['version'], '2.4.21-offline.1')
        self.assertEqual(files, self.files)

    def test_changed_bytes_are_refused(self):
        self.archive(lambda: self.files.update({'application/jooki/lib/core.lua': b'changed'}))
        with self.assertRaisesRegex(ValueError, 'checksum'):
            install.package(self.path)

    def test_manifest_cannot_redirect_an_application_destination(self):
        self.files['application/etc/unexpected'] = b'wrong destination'
        self.archive()
        with self.assertRaisesRegex(ValueError, 'destination'):
            install.package(self.path)

    def test_links_are_not_extracted(self):
        self.archive(extra_link=True)
        with self.assertRaisesRegex(ValueError, 'member'):
            install.package(self.path)

    def test_new_loader_refuses_a_stale_core(self):
        self.files['application/jooki/lib/player.lib'] = playerlib.encode(
            "_OPENJOOKI_LOADER='test'\n_OPENJOOKI_CORE='test'\nlocal EXPECT=1000\n")
        self.archive()
        with self.assertRaisesRegex(RuntimeError, 'stale build'):
            install.package(self.path)


if __name__ == '__main__':
    unittest.main()
