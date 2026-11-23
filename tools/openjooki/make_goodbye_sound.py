#!/usr/bin/env python3
"""Reproduce goodbye.mp3, the Jooki's little goodbye when it switches off after its token was taken
off (#52): two soft bell notes going down, G5 then C5, about 1.1 s, -6 dBFS peak. Our own sound
(the factory catalogue has no power-off sound). Needs ffmpeg with libmp3lame."""
import math
from pathlib import Path
import struct
import subprocess
import tempfile
import wave

RATE = 44100
LENGTH = 1.1
PEAK = 10 ** (-6 / 20)
NOTES = ((0.0, 783.99), (0.28, 523.25))        # (start s, Hz)
HARMONICS = ((1, 1.0), (2, 0.25), (3, 0.08))    # a little bell, not a beep


def sample(t):
    v = 0.0
    for start, f in NOTES:
        d = t - start
        if d < 0: continue
        env = min(1.0, d / 0.008) * math.exp(-d / 0.28)
        v += env * sum(a * math.sin(2 * math.pi * f * k * d) for k, a in HARMONICS)
    fade = min(1.0, (LENGTH - t) / 0.05)          # no click at the end
    return v * max(0.0, fade)


def pcm():
    raw = [sample(i / RATE) for i in range(int(LENGTH * RATE))]
    top = max(abs(x) for x in raw)
    return b''.join(struct.pack('<h', round(32767 * PEAK * x / top)) for x in raw)


if __name__ == '__main__':
    out = Path(__file__).parent / 'webui' / 'goodbye.mp3'
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / 'goodbye.wav'
        with wave.open(str(wav), 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm())
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-codec:a', 'libmp3lame', '-b:a', '64k',
                        '-map_metadata', '-1', '-id3v2_version', '0', '-write_xing', '0', str(out)], check=True)
    print(out, out.stat().st_size, 'bytes')
