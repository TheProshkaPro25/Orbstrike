"""Five distinct soft light/energy wave previews. NumPy only; no game integration.

Run: python tools/audio/build_gate_energy_candidates.py
Existing previews are read only and their hashes are checked before/after.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

import numpy as np

from build_gate_candidates import RATE, metrics, noise_band, smoothstep

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets/audio/candidates/gate_wave"
SPECS = [
    dict(id="01_light_shimmer", name="Световое мерцание", duration=1.58, seed=73101,
         low=1200, high=2800, width=0.48, attack=0.13, crest=0.32, core=0.64,
         tone_balance=0.80, stereo=0.16,
         description="Тонкий светлый перелив с мягкими перекрывающимися мерцаниями."),
    dict(id="02_energy_arc", name="Энергетическая дуга", duration=1.76, seed=73102,
         low=650, high=1700, width=0.55, attack=0.18, crest=0.38, core=0.86,
         tone_balance=1.10, stereo=0.10,
         description="Плавная округлая дуга энергии: подъём, широкий гребень и спад."),
    dict(id="03_warm_plasma", name="Тёплая плазма", duration=1.84, seed=73103,
         low=370, high=950, width=0.62, attack=0.22, crest=0.43, core=1.02,
         tone_balance=1.00, stereo=0.12,
         description="Тёплая низкая волна с мягким пульсирующим гармоническим свечением."),
    dict(id="04_air_halo", name="Воздушный ореол", duration=1.88, seed=73104,
         low=1450, high=3200, width=0.65, attack=0.24, crest=0.45, core=0.94,
         tone_balance=0.82, stereo=0.30,
         description="Воздушное рассеянное сияние с широким пространством и плавным хвостом."),
    dict(id="05_silk_current", name="Шёлковый ток", duration=1.70, seed=73105,
         low=850, high=2700, width=0.43, attack=0.16, crest=0.38, core=0.78,
         tone_balance=0.92, stereo=0.14,
         description="Шёлковый шелест с приглушённым электрическим переливом и лёгкой живой рябью."),
]


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)))


def sine_phase(frequency: np.ndarray) -> np.ndarray:
    return 2 * np.pi * np.cumsum(frequency) / RATE


def synthesize(spec: dict) -> tuple[np.ndarray, dict]:
    duration = spec['duration']
    n = round(duration * RATE)
    t = np.arange(n) / RATE
    u = t / duration
    rng = np.random.default_rng(spec['seed'])
    attack = smoothstep(t / spec['attack'])
    fade = smoothstep((duration - t) / 0.15)
    tail = np.clip(1 - u, 0, 1) ** 1.6
    core_u = np.clip((t / spec['core'] - spec['crest']) / (1 - spec['crest']), 0, 1)
    core = np.cos(core_u * np.pi / 2) ** 2
    envelope = attack * fade * (0.73 * core + 0.27 * tail)
    low = noise_band(n, rng, spec['low'], spec['width'])
    high = noise_band(n, rng, spec['high'], spec['width'])
    side = noise_band(n, rng, np.sqrt(spec['low'] * spec['high']), spec['width'])
    blend = 0.72 * (1 - smoothstep(t / 1.65))
    mono = low * (1 - blend) + high * blend
    noise = np.column_stack([mono + spec['stereo'] * side, mono - spec['stereo'] * side])
    noise *= envelope[:, None]
    voices = []
    for channel, spread in enumerate([-1, 1]):
        if spec['id'].startswith('01'):
            # Continuous thin glint: three overlapping smooth crests, no note attacks.
            frequency = 930 + 150 * np.sin(np.pi * np.clip(t / 1.15, 0, 1)) - 110 * smoothstep(t / duration)
            phase = sine_phase(frequency * (1 + spread * 0.0010))
            glint = np.exp(-((t - 0.30) / 0.22) ** 2)
            glint2 = np.exp(-((t - 0.60) / 0.26) ** 2)
            glint3 = np.exp(-((t - 0.88) / 0.29) ** 2)
            voice = np.sin(phase) * (0.55 + 0.22 * glint)
            voice += 0.23 * glint2 * np.sin(phase * 2 + 0.4 + spread * 0.17)
            voice += 0.10 * glint3 * np.sin(phase * 3 + 0.9 + spread * 0.23)
            voice *= attack * fade * tail
        elif spec['id'].startswith('02'):
            frequency = 350 + 430 * smoothstep(t / 0.68) - 300 * smoothstep((t - 0.68) / 0.90)
            phase = sine_phase(frequency * (1 + spread * 0.0006))
            fm = 0.15 * np.sin(phase * 2) * np.sin(np.pi * u) ** 2
            voice = np.sin(phase + fm) + 0.25 * np.sin(phase * 1.5 + 0.3)
            voice += 0.10 * np.sin(phase * 2 + spread * 0.15)
            voice *= attack * fade * (0.65 * core + 0.35 * tail)
        elif spec['id'].startswith('03'):
            frequency = 235 + 115 * np.sin(np.pi * np.clip(t / 1.5, 0, 1)) - 18 * u
            phase = sine_phase(frequency * (1 + spread * 0.0016))
            pulse = 0.87 + 0.13 * np.sin(2 * np.pi * (2.2 * t + 0.3 * t ** 2))
            voice = 0.82 * np.sin(phase) + 0.38 * np.sin(phase * 2 + 0.4)
            voice += 0.19 * np.sin(phase * 3 + 0.7) + 0.07 * np.sin(phase * 4)
            voice *= attack * fade * (0.58 * core + 0.42 * tail) * pulse
        elif spec['id'].startswith('04'):
            frequency = 625 + 65 * smoothstep(t / 0.65) - 45 * smoothstep((t - 0.65) / 1.1)
            phase = sine_phase(frequency * (1 + spread * 0.0024))
            bloom = smoothstep((t - 0.09) / 0.36)
            voice = 0.72 * np.sin(phase + spread * 0.13)
            voice += 0.27 * bloom * np.sin(phase * 1.5 + 0.8 + spread * 0.33)
            voice += 0.15 * bloom * np.sin(phase * 2 + 0.4 + spread * 0.40)
            voice *= attack * fade * tail ** 0.78
        else:
            frequency = 535 + 235 * smoothstep(t / 0.52) - 235 * smoothstep((t - 0.58) / 0.95)
            phase = sine_phase(frequency * (1 + spread * 0.0012))
            ripple = 2 * np.pi * (6.5 * t + 1.6 * t ** 2)
            fm = 0.24 * np.sin(ripple + spread * 0.12)
            voice = np.sin(phase + fm)
            voice += 0.22 * np.sin(phase * 2 + 0.35 + 0.13 * np.sin(ripple))
            voice += 0.10 * np.sin(phase * 3 + 0.75)
            voice *= attack * fade * (0.65 * core + 0.35 * tail)
            noise[:, channel] *= 1 + 0.09 * np.sin(ripple + spread * 0.20)
        voices.append(voice)
    tonal = np.column_stack(voices)
    noise /= rms(noise)
    tonal *= spec['tone_balance'] / rms(tonal)
    dry = noise + tonal
    mixed = dry.copy()
    # Halo has a broader diffuse bloom; others only quiet short reflections.
    taps = [(0.041, 0.05), (0.079, 0.032)]
    if spec['id'].startswith('04'):
        taps = [(0.047, 0.12), (0.093, 0.09), (0.151, 0.06), (0.211, 0.03)]
    for seconds, gain in taps:
        for channel in [0, 1]:
            delay = round((seconds + channel * 0.004) * RATE)
            mixed[delay:, channel] += dry[:-delay, 1 - channel] * gain
    mixed *= fade[:, None]
    # DC correction uses the envelope, so endpoints remain smoothly zero.
    mixed -= mixed.mean(axis=0, keepdims=True) * envelope[:, None] / envelope.mean()
    mixed *= 10 ** (-37 / 20) / rms(mixed)
    mixed[[0, -1]] = 0
    assert np.max(np.abs(mixed)) < 0.20
    pcm = np.rint(mixed * 32768).astype('<i2')
    return pcm, dict(dry_tone_to_noise_rms_db=round(20 * np.log10(spec['tone_balance']), 3),
                     diffuse_taps_seconds_gain=taps)


def main() -> None:
    old_paths = sorted(DEST.glob('gate_wave_0*.wav'))
    assert len(old_paths) == 6
    original_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in old_paths}
    entries = []
    for spec in SPECS:
        pcm, synthesis = synthesize(spec)
        # In-memory repeat proves deterministic synthesis without regenerating old WAVs.
        repeated, _ = synthesize(spec)
        assert np.array_equal(pcm, repeated)
        path = DEST / f"gate_wave_energy_{spec['id']}.wav"
        with wave.open(str(path), 'wb') as output:
            output.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
            output.writeframes(pcm.tobytes())
        report = metrics(pcm)
        assert report['clipped_samples'] == 0
        assert report['peak_dbfs'] < -18
        assert abs(report['rms_dbfs'] + 37) <= 0.02
        assert not pcm[[0, -1]].any()
        assert report['dc_offset_max'] < 1e-6
        entries.append(dict(**spec, synthesis=synthesis, metrics=report,
                            path=path.relative_to(ROOT).as_posix(),
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        print(f"{spec['name']}: {report['duration_seconds']:.2f}s, RMS{report['rms_dbfs']:.3f}dBFS, peak{report['peak_dbfs']:.3f}dBFS")
    assert original_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in old_paths}
    manifest = dict(schema_version=1, purpose='Five additional light/energy wave previews; not integrated',
                    generator='tools/audio/build_gate_energy_candidates.py', numpy_version=np.__version__,
                    source='Original deterministic procedural noise and tonal synthesis; no external samples or paid service',
                    preview_gain_db=0.0, target_rms_dbfs=-37.0,
                    listening_performed=False, game_integration_performed=False,
                    previous_six_sha256=original_hashes, candidates=entries)
    (DEST / 'energy_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
