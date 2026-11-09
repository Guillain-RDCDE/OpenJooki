"""Account staging/cancellation checks with invented credentials and no network."""
import hashlib
import io
import json
import tarfile
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import computer_login as login


def info(username='fixture'):
    return {'version': 1, 'username': username,
            'account_id': hashlib.sha256(username.encode()).hexdigest(),
            'metadata_ready': True, 'premium': False}


class ComputerLoginContract(unittest.TestCase):
    def helper(self):
        helper = login.Companion.__new__(login.Companion)
        helper.state = {'spotifyOffline': {'auth': {'request': '1000-1', 'phase': 'working'}}}
        helper.lock = threading.RLock()
        helper.cancelled = threading.Event()
        helper.status = Mock(return_value=SimpleNamespace(wait_for_publish=lambda **_kwargs: None))
        helper.ssh = Mock(return_value=b'')
        return helper

    def test_metadata_login_does_not_request_streaming_and_only_uploads_verified_identity(self):
        helper = self.helper()
        actions = []

        def run(_request, folder, action):
            actions.append(action)
            (folder / 'cache/offline-account.json').write_text(json.dumps(info()))

        helper.run_sdk = run
        helper.upload = Mock()
        helper.authenticate({'request': '1000-1', 'mode': 'metadata'})
        self.assertEqual(actions, ['metadata-login'])
        helper.upload.assert_called_once()

    def test_premium_account_mismatch_does_not_replace_the_device_account(self):
        helper = self.helper()
        helper.state['spotifyOffline'].update(metadata_ready=True, account_ready=False)
        def copy(cache):
            (cache / 'offline-account.json').write_text(json.dumps(info('first')))
        helper.copy_existing_metadata = copy
        helper.upload = Mock()

        def run(_request, folder, action):
            account = info('first' if action == 'metadata-login' else 'other')
            (folder / 'cache/offline-account.json').write_text(json.dumps(account))

        helper.run_sdk = run
        helper.authenticate({'request': '1000-1', 'mode': 'premium'})
        helper.upload.assert_not_called()
        helper.status.assert_any_call('error', '1000-1', error='account_mismatch')

    def test_premium_login_needs_no_web_api_grant_or_metadata_request(self):
        helper = self.helper(); actions = []
        def run(_request, folder, action):
            actions.append(action)
            account = info(); account['premium'] = True
            (folder / 'cache/offline-account.json').write_text(json.dumps(account))
        helper.run_sdk = run
        helper.copy_existing_metadata = Mock()
        helper.upload = Mock()
        helper.authenticate({'request':'1000-1','mode':'premium'})
        self.assertEqual(actions,['login'])
        helper.copy_existing_metadata.assert_not_called()
        helper.upload.assert_called_once()

    def test_cancelled_request_cannot_upload_or_activate_credentials(self):
        helper = self.helper()
        helper.state['spotifyOffline']['auth'] = {'phase': 'logged_out'}
        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp)
            (cache / 'offline-account.json').write_text(json.dumps(info()))
            with self.assertRaisesRegex(login.LoginFailure, 'cancelled'):
                helper.upload('1000-1', cache)
        helper.ssh.assert_not_called()
        helper.status.assert_not_called()

    def test_completed_staging_contains_only_grants_and_keeps_tokens_out_of_public_status(self):
        helper = self.helper()
        payloads = []

        def ssh(_command, data=None, **_kwargs):
            if data:
                payloads.append(data)
            return b''

        def status(phase, _request):
            if phase == 'complete':
                helper.state['spotifyOffline']['auth']['phase'] = 'complete'
            return SimpleNamespace(wait_for_publish=lambda **_kwargs: None)

        helper.ssh = ssh
        helper.status = Mock(side_effect=status)
        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp)
            (cache / 'offline-account.json').write_text(json.dumps(info()))
            (cache / 'credentials.json').write_text('{"invented":"fixture-secret"}')
            (cache / 'unrelated.txt').write_text('do not transfer')
            helper.upload('1000-1', cache)
        with tarfile.open(fileobj=io.BytesIO(payloads[0])) as archive:
            self.assertEqual(set(archive.getnames()), {'offline-account.json', 'credentials.json'})
            staged = json.load(archive.extractfile('offline-account.json'))
            self.assertEqual(staged['request'], '1000-1')
        helper.status.assert_called_once_with('complete', '1000-1')
        self.assertNotIn('fixture-secret', str(helper.status.call_args_list))

    def test_imported_cache_refuses_archive_paths(self):
        helper = self.helper()
        payload = io.BytesIO()
        with tarfile.open(fileobj=payload, mode='w:gz') as archive:
            entry = tarfile.TarInfo('../credentials.json')
            entry.size = 2
            archive.addfile(entry, io.BytesIO(b'{}'))
        helper.ssh.return_value = payload.getvalue()
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(login.LoginFailure, 'invalid_account_cache'):
                helper.copy_existing_metadata(Path(temp))


if __name__ == '__main__':
    unittest.main()
