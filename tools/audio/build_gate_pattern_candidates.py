"""Five new temporal light/energy patterns; creates previews only, NumPy only."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

import numpy as np

from build_gate_candidates import RATE, metrics, noise_band, smoothstep

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/audio/candidates/gate_wave'
SPECS = [
    dict(id='01_double_pulse', name='Двойной импульс', duration=1.72, seed=73201,
         description='Две мягкие энергетические волны; вторая тише и ниже первой.',
         crests_seconds=[0.25, 0.73]),
    dict(id='02_rising_breath', name='Нарастающее дыхание', duration=1.84, seed=73202,
         description='Одно непрерывное расширяющееся дыхание с плавным сходом.',
         crests_seconds=[0.86]),
    dict(id='03_light_sequence', name='Цепочка света', duration=1.66, seed=73203,
         description='Четыре мягкие вспышки с неодинаковыми паузами и плотностью.',
         crests_seconds=[0.18, 0.43, 0.81, 1.12]),
    dict(id='04_scattered_glints', name='Рассыпающееся мерцание', duration=1.80, seed=73204,
         description='Короткое сияние переходит в редеющие тихие световые искры.',
         crests_seconds=[0.23, 0.49, 0.64, 0.82, 0.97, 1.13, 1.32, 1.49]),
    dict(id='05_reverse_surge', name='Обратный перелив', duration=1.88, seed=73205,
         description='Обратный втягивающий подхват собирается в мягкую кульминацию и затухает.',
         crests_seconds=[1.03]),
]


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)))


def pulse(t: np.ndarray, peak: float, attack: float, release: float) -> np.ndarray:
    return smoothstep((t - peak + attack) / attack) * (1 - smoothstep((t - peak) / release))


def phase(frequency: np.ndarray) -> np.ndarray:
    return 2 * np.pi * np.cumsum(frequency) / RATE


def synthesize(spec: dict) -> np.ndarray:
    n = round(spec['duration'] * RATE)
    t = np.arange(n) / RATE
    duration = spec['duration']
    rng = np.random.default_rng(spec['seed'])
    identifier = spec['id'][:2]
    if identifier == '01':
        first = pulse(t, 0.25, 0.19, 0.29)
        second = pulse(t, 0.73, 0.20, 0.38)
        env = first + 0.73 * second + 0.045 * pulse(t, 0.34, 0.25, 1.26)
        freq1 = 480 + 130 * smoothstep(t / 0.27) - 145 * smoothstep((t - 0.27) / 0.34)
        freq2 = 420 + 110 * smoothstep((t - 0.51) / 0.23) - 150 * smoothstep((t - 0.76) / 0.42)
        p1, p2 = phase(freq1), phase(freq2)
        tone = (np.sin(p1) + 0.24 * np.sin(1.5 * p1 + 0.4)) * first
        tone += 0.73 * (np.sin(p2) + 0.18 * np.sin(2 * p2 + 0.6)) * second
        low, high, width = 650, 1700, 0.49
        blend = 0.45 + 0.20 * (first + second)
        tonal_balance = 1.05
    elif identifier == '02':
        env = pulse(t, 0.86, 0.82, 0.90)
        freq = 390 + 260 * smoothstep(t / 0.96) - 205 * smoothstep((t - 0.96) / 0.80)
        p = phase(freq)
        warmth = smoothstep(t / 0.75)
        tone = (np.sin(p) + 0.29 * warmth * np.sin(2 * p + 0.3)
                + 0.10 * warmth * np.sin(3 * p + 0.8)) * env
        low, high, width = 520, 2100, 0.57
        blend = 0.20 + 0.55 * smoothstep(t / 0.90) - 0.45 * smoothstep((t - 0.90) / 0.80)
        tonal_balance = 0.92
    elif identifier == '03':
        env = np.zeros(n)
        tone = np.zeros(n)
        for i, (peak, attack, release, gain) in enumerate([
            (0.18, 0.12, 0.18, 0.76), (0.43, 0.10, 0.23, 1.0),
            (0.81, 0.16, 0.22, 0.80), (1.12, 0.13, 0.34, 0.64),
        ]):
            e = pulse(t, peak, attack, release) * gain
            # Each flash bends through a small non-musical pitch range.
            local = np.clip((t - peak + attack) / (attack + release), 0, 1)
            f = 770 + 95 * np.sin(np.pi * local) - 125 * local + i * 16
            p = phase(f)
            tone += e * (np.sin(p + i * 0.7) + 0.19 * np.sin(2 * p + 0.3))
            env += e
        low, high, width = 1100, 2600, 0.46
        blend = 0.55
        tonal_balance = 1.08
    elif identifier == '04':
        main = pulse(t, 0.23, 0.17, 0.32)
        env = main.copy()
        f = 790 + 165 * smoothstep(t / 0.24) - 260 * smoothstep((t - 0.24) / 0.45)
        p = phase(f)
        tone = main * (np.sin(p) + 0.16 * np.sin(2 * p + 0.7))
        for i, peak in enumerate(spec['crests_seconds'][1:]):
            gain = 0.29 * (1 - i / 9) ** 1.1
            attack = 0.052 + 0.009 * (i % 3)
            release = 0.13 + 0.018 * (i % 2)
            e = pulse(t, peak, attack, release) * gain
            f0 = rng.uniform(1040, 1560)
            local = np.clip((t - peak + attack) / (attack + release), 0, 1)
            p = phase(f0 * (1 - 0.12 * local))
            tone += e * np.sin(p + rng.uniform(0, 2 * np.pi))
            env += e * 0.38
        low, high, width = 1300, 2800, 0.55
        blend = 0.63 - 0.22 * smoothstep(t / duration)
        tonal_balance = 1.10
    else:
        # Accelerating reverse swell, then a rounded release with a dropping tone.
        pre = smoothstep((t - 0.07) / 0.96) ** 2.0
        post = 1 - smoothstep((t - 1.03) / 0.73)
        env = pre * post
        f = 315 + 710 * smoothstep(t / 1.03) ** 1.8 - 510 * smoothstep((t - 1.03) / 0.73)
        p = phase(f)
        bloom = smoothstep((t - 0.58) / 0.48)
        tone = (np.sin(p + 0.10 * np.sin(2 * p))
                + 0.22 * bloom * np.sin(1.5 * p + 0.5)) * env
        low, high, width = 500, 2900, 0.50
        blend = 0.05 + 0.78 * smoothstep(t / 1.03) ** 1.7 - 0.70 * smoothstep((t - 1.03) / 0.72)
        tonal_balance = 0.94
    airy_low = noise_band(n, rng, low, width)
    airy_high = noise_band(n, rng, high, width)
    side = noise_band(n, rng, np.sqrt(low * high), width)
    mono = (airy_low * (1 - blend) + airy_high * blend) * env
    side *= env * 0.13
    noise = np.column_stack([mono + side, mono - side])
    noise /= rms(noise)
    # Shared tonal core guarantees energy remains stable when summed to mono.
    tone *= tonal_balance / rms(tone)
    stereo = noise + tone[:, None]
    # Very quiet short diffusion rounds edges without hiding the pattern's gaps.
    dry = stereo.copy()
    for channel in [0, 1]:
        delay = round((0.033 + 0.004 * channel) * RATE)
        stereo[delay:, channel] += dry[:-delay, 1 - channel] * 0.033
    final_fade = smoothstep(t / 0.035) * smoothstep((duration - t) / 0.10)
    stereo *= final_fade[:, None]
    correction = env * final_fade
    stereo -= stereo.mean(axis=0, keepdims=True) * correction[:, None] / correction.mean()
    stereo *= 10 ** (-37 / 20) / rms(stereo)
    stereo[[0, -1]] = 0
    assert np.max(np.abs(stereo)) < 0.17
    return np.rint(stereo * 32768).astype('<i2')


def inspect(pcm: np.ndarray) -> dict:
    report = metrics(pcm)
    x = pcm.astype(np.float64) / 32768
    report['mono_rms_dbfs'] = round(20 * np.log10(rms(x.mean(axis=1))), 3)
    report['mono_loss_db'] = round(20 * np.log10(rms(x.mean(axis=1)) / rms(x)), 3)
    report['channel_correlation'] = round(float(np.corrcoef(x.T)[0, 1]), 6)
    timeline = []
    for start in np.arange(0, len(x) / RATE, 0.05):
        part = x[round(start * RATE):round((start + 0.05) * RATE)]
        timeline.append(round(20 * np.log10(max(rms(part), 1e-12)), 2))
    report['pattern_50ms_rms_dbfs'] = timeline
    return report


def main() -> None:
    previous = sorted(p for p in DEST.glob('*.wav') if not p.name.startswith('gate_wave_pattern_'))
    assert len(previous) == 11
    original_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    entries = []
    for spec in SPECS:
        pcm = synthesize(spec)
        assert np.array_equal(pcm, synthesize(spec))
        output = DEST / f"gate_wave_pattern_{spec['id']}.wav"
        with wave.open(str(output), 'wb') as w:
            w.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
            w.writeframes(pcm.tobytes())
        # Validate actual file bytes, not only the array before saving.
        with wave.open(str(output), 'rb') as w:
            assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (2, 2, RATE)
            actual = np.frombuffer(w.readframes(w.getnframes()), '<i2').reshape(-1, 2)
        assert np.array_equal(pcm, actual)
        report = inspect(actual)
        assert report['clipped_samples'] == 0
        assert abs(report['rms_dbfs'] + 37) < 0.02
        assert report['peak_dbfs'] < -16
        assert report['mono_loss_db'] > -0.3
        assert report['dc_offset_max'] < 1e-6
        assert not actual[[0, -1]].any()
        entries.append(dict(**spec, metrics=report, path=output.relative_to(ROOT).as_posix(),
                            sha256=hashlib.sha256(output.read_bytes()).hexdigest()))
        print(f"{spec['name']}: {spec['duration']:.2f}s RMS{report['rms_dbfs']:.3f}, peak{report['peak_dbfs']:.3f}, mono loss{report['mono_loss_db']:.3f}dB")
    assert original_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    manifest = dict(schema_version=1, purpose='Five new temporal energy/light wave patterns; previews only',
                    generator='tools/audio/build_gate_pattern_candidates.py', numpy_version=np.__version__,
                    source='Original deterministic procedural synthesis; no external recordings or paid services',
                    listening_performed=False, game_integration_performed=False, preview_gain_db=0.0,
                    level_note='RMS matched at -37dBFS; perceptual loudness requires listening',
                    previous_eleven_sha256=original_hashes, candidates=entries)
    (DEST / 'pattern_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
