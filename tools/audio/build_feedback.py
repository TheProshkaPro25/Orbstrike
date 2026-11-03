"""Собственные сигналы и варианты существующих CC0 эффектов. Запуск из корня проекта."""
from pathlib import Path
import math
import random
import struct
import subprocess
import wave

DEST = Path('assets/audio/sfx')
RATE = 44100

def tone(name, notes, duration, gain=.18):
    data = []
    for i in range(int(RATE * duration)):
        t = i / RATE
        value = 0.0
        for start, freq, length in notes:
            age = t - start
            if 0 <= age < length:
                env = min(age / .015, 1) * (1 - age / length) ** 2
                value += math.sin(math.tau * freq * age) * env
                value += .16 * math.sin(math.tau * freq * 2 * age) * env
        data.append(struct.pack('<h', int(max(-1, min(1, value * gain)) * 32767)))
    with wave.open(str(DEST / (name + '.wav')), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(b''.join(data))

tone('ui_denied', [(0, 246.94, .14), (.09, 196, .18)], .29, .15)
tone('turn_yours', [(0, 523.25, .25), (.09, 659.25, .25), (.18, 783.99, .28)], .48, .14)
tone('turn_opponent', [(0, 392, .26), (.13, 293.66, .28)], .43, .12)
for name in ['card_select', 'card_place', 'ball_throw', 'clash']:
    for index, ratio in [(2, .94), (3, 1.06)]:
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(DEST / (name + '.ogg')),
            '-af', f'asetrate=44100*{ratio},aresample=44100,volume=0.95', '-ac', '1',
            str(DEST / f'{name}_v{index}.wav')], check=True)
subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(DEST / 'ball_throw.ogg'),
    '-af', 'highpass=f=450,lowpass=f=5500,afade=t=out:st=0.22:d=0.16,volume=0.65', '-t', '0.4', '-ac', '1', str(DEST / 'card_swoosh.wav')], check=True)
