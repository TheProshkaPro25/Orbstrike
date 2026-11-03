"""Continuous expanding wavefront previews: broadband textures, no pitched tones.

Run with Python + NumPy. Writes five new radial WAVs and their own manifest only.
"""
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
    dict(id='01_air_front', name='Воздушный фронт', duration=1.86, seed=73301,
         centers=[280, 1550, 650], widths=[0.82, 0.94, 0.95],
         attack=0.15, crest=0.29, fall=1.45, side=0.80, diffusion=0.11,
         description='Плотный мягкий центр раскрывается в широкую воздушную волну и уходит вдаль.'),
    dict(id='02_liquid_field', name='Текучее поле', duration=1.94, seed=73302,
         centers=[620, 1950, 570], widths=[0.62, 0.64, 0.76],
         attack=0.19, crest=0.35, fall=1.50, side=0.84, diffusion=0.14,
         description='Текучий приглушённый шорох расходится вязким пространственным полем.'),
    dict(id='03_volume_shift', name='Объёмное смещение', duration=1.98, seed=73303,
         centers=[210, 630, 290], widths=[0.84, 0.93, 0.91],
         attack=0.21, crest=0.36, fall=1.57, side=0.72, diffusion=0.10,
         description='Округлое низкое смещение пространства с широким уходящим давлением, без удара.'),
    dict(id='04_light_front', name='Световой фронт', duration=1.78, seed=73304,
         centers=[1350, 3050, 1050], widths=[0.83, 0.70, 0.88],
         attack=0.12, crest=0.25, fall=1.38, side=0.87, diffusion=0.13,
         description='Цельный светлый шумовой ореол расширяется и мягко темнеет по мере удаления.'),
    dict(id='05_spatial_wake', name='Пространственный след', duration=1.92, seed=73305,
         centers=[430, 1250, 420], widths=[0.75, 0.84, 0.97],
         attack=0.18, crest=0.33, fall=1.50, side=0.91, diffusion=0.18,
         description='Турбулентная пространственная волна с широким медленно рассеивающимся следом.'),
]


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)))


def drift(n: int, rng: np.random.Generator, speed: float) -> np.ndarray:
    """Smooth irregular motion, not a rhythmic pulse train."""
    t = np.arange(n) / RATE
    knots = np.arange(0, t[-1] + 2 / speed, 1 / speed)
    values = rng.uniform(-1, 1, len(knots))
    k = np.floor(t * speed).astype(int)
    weight = smoothstep(t * speed - k)
    return values[k] * (1 - weight) + values[k + 1] * weight


def synthesize(spec: dict) -> np.ndarray:
    n = round(spec['duration'] * RATE)
    t = np.arange(n) / RATE
    rng = np.random.default_rng(spec['seed'])
    identifier = spec['id'][:2]
    # A central broad pressure/texture becomes a propagating front, then darkens.
    open_front = smoothstep(t / 0.40)
    distance = smoothstep((t - 0.30) / 1.15)
    weights = np.stack([1 - open_front, open_front * (1 - distance),
                        open_front * distance], axis=1)
    weights /= np.sqrt((weights ** 2).sum(axis=1, keepdims=True))
    streams = []
    for channel in range(2):
        bands = np.column_stack([noise_band(n, rng, center, width)
                                 for center, width in zip(spec['centers'], spec['widths'])])
        source = (bands * weights).sum(axis=1)
        if identifier == '02':
            # Wet moving interference comes from quiet, changing short diffuse
            # paths in broadband noise; no periodic comb, resonance or oscillator.
            wet = np.zeros(n)
            for seconds, gain in [(0.0031, 0.15), (0.0073, -0.12), (0.0137, 0.09)]:
                delay = round(seconds * RATE)
                wet[delay:] += bands[:-delay, 1] * gain
            source += wet * (0.70 + 0.30 * drift(n, rng, 5.3))
            source *= 1 + 0.11 * drift(n, rng, 8.5)
        elif identifier == '03':
            # Separate broad low and body layers produce displaced volume,
            # with neither a bass impact nor a pitched sub oscillator.
            body = noise_band(n, rng, 450, 0.88)
            source = 0.83 * source + 0.22 * body * (1 - 0.5 * distance)
        elif identifier == '04':
            # Fine aerated edge fades sooner than the diffuse, darker body.
            dust = noise_band(n, rng, 3700, 0.48)
            source = 0.87 * source + 0.18 * dust * (1 - distance) ** 1.4
        elif identifier == '05':
            # Irregular spectral eddies, never separate amplitude pulses.
            eddy = drift(n, rng, 7.2)
            source += 0.22 * bands[:, 0] * eddy
            source *= 1 + 0.10 * drift(n, rng, 4.6)
        streams.append(source)
    mid, diffuse = streams
    # Symmetric widening from a narrow central source, not left-to-right travel.
    width = 0.015 + spec['side'] * smoothstep((t - 0.08) / 0.82)
    stereo = np.column_stack([mid + width * diffuse, mid - width * diffuse])
    direct = stereo.copy()
    for seconds, gain in [(0.019, 0.65), (0.043, 0.46), (0.079, 0.31), (0.121, 0.18)]:
        for channel in [0, 1]:
            delay = round((seconds + channel * 0.003) * RATE)
            stereo[delay:, channel] += direct[:-delay, 1 - channel] * gain * spec['diffusion'] * distance[delay:]
    attack = smoothstep(t / spec['attack'])
    release = np.clip((t - spec['crest']) / spec['fall'], 0, 1)
    envelope = attack * (1 - smoothstep(release)) ** 1.55
    envelope *= smoothstep((spec['duration'] - t) / 0.16)
    stereo *= envelope[:, None]
    stereo -= stereo.mean(axis=0, keepdims=True) * envelope[:, None] / envelope.mean()
    stereo *= 10 ** (-35 / 20) / rms(stereo)
    stereo[[0, -1]] = 0
    assert np.max(np.abs(stereo)) < 0.20
    return np.rint(stereo * 32768).astype('<i2')


def spatial_metrics(pcm: np.ndarray) -> dict:
    x = pcm.astype(float) / 32768
    def window(start: float, end: float) -> dict:
        part = x[round(start * RATE):round(end * RATE)]
        mid, side = part.mean(axis=1), (part[:, 0] - part[:, 1]) / 2
        return dict(start_seconds=start, end_seconds=end,
                    channel_correlation=round(float(np.corrcoef(part.T)[0, 1]), 5),
                    side_to_mid_rms_db=round(20 * np.log10(rms(side) / rms(mid)), 3))
    return dict(early=window(0.04, 0.24), distant=window(0.95, 1.55),
                mono_rms_dbfs=round(20 * np.log10(rms(x.mean(axis=1))), 3),
                mono_loss_db=round(20 * np.log10(rms(x.mean(axis=1)) / rms(x)), 3))


def main() -> None:
    previous = sorted(p for p in DEST.glob('*.wav') if not p.name.startswith('gate_wave_radial_'))
    assert len(previous) == 16
    old_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    entries = []
    for spec in SPECS:
        pcm = synthesize(spec)
        assert np.array_equal(pcm, synthesize(spec))
        path = DEST / f"gate_wave_radial_{spec['id']}.wav"
        with wave.open(str(path), 'wb') as output:
            output.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
            output.writeframes(pcm.tobytes())
        with wave.open(str(path), 'rb') as stored:
            assert (stored.getnchannels(), stored.getsampwidth(), stored.getframerate()) == (2, 2, RATE)
            actual = np.frombuffer(stored.readframes(stored.getnframes()), '<i2').reshape(-1, 2)
        assert np.array_equal(pcm, actual)
        report, spatial = metrics(actual), spatial_metrics(actual)
        assert abs(report['rms_dbfs'] + 35) < 0.02
        assert report['clipped_samples'] == 0 and report['peak_dbfs'] < -15
        assert report['dc_offset_max'] < 1e-6 and not actual[[0, -1]].any()
        assert spatial['early']['channel_correlation'] > 0.95
        assert spatial['distant']['channel_correlation'] < 0.58
        assert spatial['distant']['side_to_mid_rms_db'] > spatial['early']['side_to_mid_rms_db'] + 12
        assert spatial['mono_loss_db'] > -1.5
        entries.append(dict(**spec, metrics=report, spatial_metrics=spatial,
                            path=path.relative_to(ROOT).as_posix(), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        print(f"{spec['name']}: {spec['duration']:.2f}s, RMS{report['rms_dbfs']:.3f}, peak{report['peak_dbfs']:.3f}; "
              f"L/R corr {spatial['early']['channel_correlation']:.3f}→{spatial['distant']['channel_correlation']:.3f}, mono{spatial['mono_loss_db']:.3f}dB")
    assert old_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    manifest = dict(schema_version=1, purpose='Continuous radially expanding wavefront previews, not game-integrated',
                    generator='tools/audio/build_gate_radial_candidates.py', numpy_version=np.__version__,
                    source='Original deterministic broadband noise synthesis; no pitched oscillators, note sequences, external samples or paid services',
                    target_rms_dbfs=-35.0, preview_gain_db=0.0, listening_performed=False, game_integration_performed=False,
                    design='Narrow central source expands symmetrically into diffuse sides; spectral darkening suggests distance. Single continuous envelope.',
                    previous_sixteen_sha256=old_hashes, candidates=entries)
    (DEST / 'radial_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
