#!/usr/bin/env python3
"""Run the actual ESP32 volume application functions against the factory curve."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
from test_sdk import function

HERE = Path(__file__).resolve().parent

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('source', type=Path)
    source = ap.parse_args().source / 'esp32-code/jooki_v2/main'
    cfg = (source / 'config.h').read_text()
    audio = (source / 'audio.c').read_text()
    pieces = []
    for key in ('VOLUME_TABLE_SCALING_NORMAL', 'VOLUME_TABLE_SCALING_TOYSAFE', 'VOLUME_TABLE_SIZE'):
        pieces.append(re.search(r'^#define ' + key + r' .+$', cfg, re.M).group(0))
    pieces.append(re.search(r'static const float VOLUME_TABLE\[.*?\n};', cfg, re.S).group(0))
    for signature in ('static void audio_apply_volume_locked(void)', 'int audio_set_host_volume(int percent, unsigned maximum_plus_one)', 'void audio_set_knob_volume(int percent)', 'int audio_set_toysafe(bool state)'):
        pieces.append(function(audio, signature))
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / 'gain_functions.inc').write_text('\n'.join(pieces))
        subprocess.run(['cc', '-std=c99', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-g', '-I' + str(source), '-I' + str(tmp), str(HERE / 'tests/gain.c'), '-o', str(tmp / 'gain')], check=True)
        subprocess.run([str(tmp / 'gain')], check=True)

if __name__ == '__main__':
    main()
