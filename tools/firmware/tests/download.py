"""Regression checks for source hosts rejecting Python's default User-Agent."""
import hashlib
import http.server
from pathlib import Path
import sys
import tempfile
import threading
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare import checked_download  # noqa: E402

DATA = b'checksum-pinned source archive fixture'
DIGEST = hashlib.sha256(DATA).hexdigest()

class Host(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get('User-Agent') != 'OpenJooki-source-builder/1.0':
            self.send_error(403)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(DATA)
    def log_message(self, *_args):
        pass

class Download(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dest = Path(self.tmp.name) / 'source.tgz'
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Host)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.url = 'http://127.0.0.1:%d/source.tgz' % server.server_port
    def test_identified_download_and_verified_cache(self):
        self.assertEqual(checked_download(self.url, DIGEST, self.dest).read_bytes(), DATA)
        self.assertEqual(checked_download('http://unreachable.invalid', DIGEST, self.dest).read_bytes(), DATA)
    def test_bad_download_is_never_promoted(self):
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            checked_download(self.url, '0' * 64, self.dest)
        self.assertFalse(self.dest.exists())
        self.assertFalse(self.dest.with_suffix('.tgz.part').exists())
    def test_modified_cache_is_refused(self):
        self.dest.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'archive checksum mismatch'):
            checked_download(self.url, DIGEST, self.dest)

if __name__ == '__main__':
    unittest.main()
