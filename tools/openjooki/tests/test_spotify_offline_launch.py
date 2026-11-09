"""Linux launch regression: an offline child must not retain the core HTTP socket.

Run with Python 3 and Lua 5.1, from the repository root. No account/device needed.
"""
import json
import contextlib
import select
import re
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(sys.platform == 'linux', 'the device launcher uses Linux procfs')
class NativeLaunchContract(unittest.TestCase):
    def test_native_child_releases_inherited_listener(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            native = root / 'native'
            native.write_text('#!/bin/sh\necho NATIVE_READY\nexec sleep 3\n')
            native.chmod(0o700)
            lua = '''package.path="core/?.lua;"..package.path
local root=arg[1]
local values={spotify_offline_root=root.."/account",scratch_dir=root.."/run",spotify_offline_binary=root.."/native",spotify_offline_quota_bytes=0}
local shell={ACTIONS={}}
require("adapters.spotify_offline").install(shell,{get=function(k) return values[k] end})
io.write(require("vendor.json").encode(shell.ACTIONS.offline_catalog.argv({})))'''
            script = root / 'arguments.lua'
            script.write_text(lua)
            argv = json.loads(subprocess.check_output(['lua5.1', str(script), str(root)]))
            # Hardware checks cover these limits. An emulated exec needs extra
            # address space; this regression isolates descriptor ownership.
            argv[3] = re.sub(r'ulimit -[dv] [0-9]+; ', '', argv[3])
            with contextlib.ExitStack() as sockets:
                for _ in range(12):
                    sockets.enter_context(socket.socket())
                listener = sockets.enter_context(socket.socket())
                listener.bind(('127.0.0.1', 0))
                listener.listen()
                address = listener.getsockname()
                descriptor = listener.fileno()
                assert descriptor > 9
                with subprocess.Popen(argv, pass_fds=(descriptor,), stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True) as child:
                    readable, _, _ = select.select([child.stdout], [], [], 5)
                    if not readable:
                        child.terminate()
                        self.fail('Native fixture did not start within five seconds')
                    ready = child.stdout.readline().strip()
                    self.assertEqual(ready, 'NATIVE_READY', child.stderr.read() if not ready else '')
                    listener.close()
                    with socket.socket() as replacement:
                        # Rebind while the native child is still alive: it must have
                        # closed the inherited listener before executing its program.
                        replacement.bind(address)
                        replacement.listen()
                    self.assertIsNone(child.poll())
                    child.terminate()
                    child.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
