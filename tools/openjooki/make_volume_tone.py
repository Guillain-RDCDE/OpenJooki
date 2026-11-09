#!/usr/bin/env python3
"""Reproduce volume-test.wav: 0.8 s, 660 Hz, -3 dBFS peak, 25 ms cosine ramps."""
import math
from pathlib import Path
import struct
import wave

RATE = 44100
SAMPLES = int(0.8 * RATE)
RAMP = int(0.025 * RATE)


def pcm():
    values = []
    for i in range(SAMPLES):
        ramp = min(i, SAMPLES - 1 - i, RAMP) / RAMP
        gain = (1 - math.cos(math.pi * ramp)) / 2
        value = round(32767 * 10 ** (-3 / 20) * gain * math.sin(2 * math.pi * 660 * i / RATE))
        values.append(struct.pack('<h', value))
    return b''.join(values)


if __name__ == '__main__':
    with wave.open(str(Path(__file__).parent / 'webui' / 'volume-test.wav'), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm())
