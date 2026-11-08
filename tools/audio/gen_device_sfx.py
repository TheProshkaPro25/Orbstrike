#!/usr/bin/env python3
"""Original quiet wrist-device cues; deterministic additive synthesis, no samples.

Generate 44.1 kHz mono PCM WAV in assets/audio/sfx/. The raised-sine envelope
starts and ends at zero; peak is limited to 0.28 before the in-game UI gain.
"""
from pathlib import Path
import math
import struct
import wave

RATE = 44100
DEST = Path(__file__).resolve().parents[2] / 'assets/audio/sfx'
# duration, (start, frequency, duration, relative amplitude)
CUES = {
    'device_hover': (.065, [(0, 880, .060, .65)]),
    'device_click': (.135, [(0, 660, .075, .8), (.035, 990, .095, .55)]),
    'device_denied': (.180, [(0, 392, .080, .65), (.075, 330, .100, .55)]),
    'device_power': (.190, [(0, 784, .110, .65), (.065, 1176, .120, .4)]),
    'device_power_up': (.190, [(0, 784, .105, .60), (.065, 1176, .120, .48)]),
    'device_power_down': (.190, [(0, 784, .105, .60), (.065, 523.25, .120, .48)]),
    'device_turn': (.260, [(0, 523.25, .130, .6), (.080, 784, .170, .5)]),
}


def generate() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    for name, (duration, notes) in CUES.items():
        values = []
        for index in range(round(duration * RATE)):
            time = index / RATE
            value = 0.0
            for start, frequency, length, gain in notes:
                phase = (time - start) / length
                if 0 < phase < 1:
                    envelope = math.sin(math.pi * phase) ** 2 * math.exp(-2 * phase)
                    angle = 2 * math.pi * frequency * (time - start)
                    value += gain * envelope * (math.sin(angle) + .12 * math.sin(2 * angle))
            values.append(value)
        scale = .28 / max(abs(value) for value in values)
        payload = b''.join(struct.pack('<h', round(value * scale * 32767)) for value in values)
        with wave.open(str(DEST / f'{name}.wav'), 'wb') as output:
            output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
            output.writeframes(payload)


if __name__ == '__main__':
    generate()
