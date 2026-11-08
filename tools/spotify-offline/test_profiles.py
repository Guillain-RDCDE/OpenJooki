"""Hermetic Git profile guards: overlapping patches, new files and local edits."""
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import trial


class ProfileGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.source = self.work / 'source'
        self.source.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        (self.source / 'Cargo.toml').write_text('dependency = "native"\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture')
        revision = self.git('rev-parse', 'HEAD').strip()
        self.revision = patch.object(trial, 'REVISION', revision)
        self.revision.start()
        self.addCleanup(self.revision.stop)
        (self.source / 'Cargo.toml').write_text('dependency = "managed"\n')
        (self.source / 'managed.rs').write_text('// fixture\n')
        self.git('add', '-N', 'managed.rs')
        self.first = self.work / 'first.patch'
        self.first.write_text(self.git('diff', '--binary', '--abbrev=7', '--unified=0', 'HEAD'))
        self.git('add', '.')
        self.git('commit', '-qm', 'First')
        (self.source / 'Cargo.toml').write_text('dependency = "tls"\n')
        self.second = self.work / 'tls.patch'
        self.second.write_text(self.git('diff', '--binary', '--abbrev=7', '--unified=0', 'HEAD'))
        self.git('reset', '--hard', revision)
        self.patches = (self.first, self.second)

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.source, check=True,
                              capture_output=True, text=True).stdout

    def prepare(self, patches=None):
        return trial.prepare(self.work, patch_files=patches or self.patches)

    def test_overlapping_patches_and_intent_to_add_survive_repeated_validation(self):
        self.prepare((self.first,))
        self.prepare()
        self.prepare()
        self.assertEqual((self.source / 'Cargo.toml').read_text(), 'dependency = "tls"\n')
        self.assertEqual(self.git('diff', '--cached', '--name-only'), '')
        self.assertTrue((self.source / 'managed.rs').exists())

    def test_extra_tracked_changes_are_refused_and_preserved(self):
        self.prepare()
        (self.source / 'Cargo.toml').write_text('user change\n')
        with self.assertRaisesRegex(ValueError, 'differs'):
            self.prepare()
        self.assertEqual((self.source / 'Cargo.toml').read_text(), 'user change\n')

    def test_untracked_files_are_refused(self):
        (self.source / 'extra').write_text('user file')
        with self.assertRaisesRegex(ValueError, 'local changes'):
            self.prepare()

    def test_staged_changes_are_refused(self):
        self.prepare()
        self.git('add', '.')
        with self.assertRaisesRegex(ValueError, 'local changes'):
            self.prepare()


if __name__ == '__main__':
    unittest.main()
