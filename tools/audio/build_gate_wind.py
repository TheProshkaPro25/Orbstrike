"""Тихие собственные шумовые эффекты полёта карты и расширения ворот, без сторонних сэмплов."""
from pathlib import Path
import math
import random
import struct
import wave
import runpy
RATE = 44100
DEST = Path('assets/audio/sfx')

def build(name, duration, expansion):
    rng = random.Random(9707 + int(expansion))
    slow = band = 0.0
    values = []
    phase = 0.0
    for i in range(int(duration * RATE)):
        t = i / RATE
        u = t / duration
        noise = rng.uniform(-1, 1)
        slow += .09 * (noise - slow)
        band += .006 * (noise - band)
        air = slow - band
        envelope = math.sin(math.pi * u) ** (.8 if expansion else .6)
        phase += math.tau * (360 * (1-u)**2 + 95) / RATE
        energy = (math.sin(phase) * .18 + math.sin(phase * .501) * .10) if expansion else 0
        values.append((air * 1.7 + energy) * envelope)
    peak = max(abs(v) for v in values)
    gain = (.20 if expansion else .14) / peak
    with wave.open(str(DEST/(name+'.wav')), 'wb') as file:
        file.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        file.writeframes(b''.join(struct.pack('<h', round(v * gain * 32767)) for v in values))
build('gate_flight_wind', 1.05, False)
# The accepted descending wave is generated separately; keep it reproducible.
runpy.run_path(str(Path(__file__).with_name('build_gate_activation.py')), run_name='__main__')
