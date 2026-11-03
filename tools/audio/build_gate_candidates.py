"""Five quiet gate-wave audition candidates, generated entirely from seeded noise.

Requires Python 3 and NumPy. Does not modify the currently active gate sound.
Run from any directory: python tools/audio/build_gate_candidates.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import wave

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets/audio/candidates/gate_wave"
RATE = 48_000
TARGET_RMS_DBFS = -37.0
PEAK_LIMIT_DBFS = -18.5
WAVE_SECONDS = 1.8
VARIANTS = [
    dict(id="01_soft_air", name="Мягкий воздух", duration=1.65, core_seconds=0.70, seed=73001,
         low=520, high=1800, width=0.66, attack=0.12, crest=0.36, stereo=0.10,
         texture=0.0, tail=0.045,
         description="Плавный воздушный выдох, который темнеет к концу."),
    dict(id="02_silk_fold", name="Шёлковая складка", duration=1.72, core_seconds=0.74, seed=73002,
         low=850, high=2700, width=0.43, attack=0.14, crest=0.44, stereo=0.13,
         texture=0.13, tail=0.03,
         description="Более светлый шелест с едва заметной мягкой фактурой."),
    dict(id="03_warm_ripple", name="Тёплая рябь", duration=1.80, core_seconds=0.78, seed=73003,
         low=330, high=880, width=0.50, attack=0.15, crest=0.39, stereo=0.08,
         texture=0.0, tail=0.06,
         description="Низкая приглушённая волна без суббаса и тонального удара."),
    dict(id="04_paper_breath", name="Дыхание бумаги", duration=1.40, core_seconds=0.62, seed=73004,
         low=1350, high=3250, width=0.49, attack=0.10, crest=0.30, stereo=0.05,
         texture=0.20, tail=0.0,
         description="Короткий сухой бумажный шелест с плавным входом."),
    dict(id="05_velvet_wave", name="Бархатная волна", duration=1.80, core_seconds=0.82, seed=73005,
         low=420, high=1350, width=0.72, attack=0.18, crest=0.46, stereo=0.23,
         texture=0.07, tail=0.09,
         description="Широкий обволакивающий шорох с наиболее длинным мягким хвостом."),
]


def noise_band(n: int, rng: np.random.Generator, center: float, width: float) -> np.ndarray:
    """Broad nonresonant band; no oscillators, pitched partials or impulses."""
    size = 1 << (n + RATE - 1).bit_length()
    freq = np.fft.rfftfreq(size, 1 / RATE)
    safe = np.maximum(freq, 1.0)
    shape = np.exp(-0.5 * (np.log2(safe / center) / width) ** 2)
    shape *= 1 - np.exp(-(safe / 170) ** 6)
    shape *= np.exp(-(safe / 4400) ** 8)
    shape[0] = 0
    samples = np.fft.irfft(np.fft.rfft(rng.normal(size=size)) * shape, size)
    samples = samples[RATE // 3:RATE // 3 + n]
    return samples / np.sqrt(np.mean(samples ** 2))


def smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def synthesize(spec: dict) -> np.ndarray:
    n = round(RATE * spec["duration"])
    t = np.arange(n) / RATE
    rng = np.random.default_rng(spec["seed"])
    low = noise_band(n, rng, spec["low"], spec["width"])
    high = noise_band(n, rng, spec["high"], spec["width"])
    side = noise_band(n, rng, math.sqrt(spec["high"] * spec["low"]), spec["width"])
    blend = 0.80 * (1 - smoothstep(t / WAVE_SECONDS))
    mono = (1 - blend) * low + blend * high
    # Soft core plus a much quieter tail following the actual floor wave.
    # The wave expands for 1.8 s; its shader strength is 1 - t / 1.8.
    attack = smoothstep(t / spec["attack"])
    core_u = t / spec["core_seconds"]
    core = np.cos(np.clip((core_u - spec["crest"]) / (1 - spec["crest"]), 0, 1) * np.pi / 2) ** 2
    wave_strength = np.clip(1 - t / WAVE_SECONDS, 0, 1)
    envelope = attack * (0.62 * core + 0.38 * wave_strength ** 1.1)
    texture = 1 + spec["texture"] * np.sin(2 * np.pi * (8 * t + 2.1 * t ** 2))
    stereo = np.column_stack([mono + side * spec["stereo"], mono - side * spec["stereo"]])
    stereo *= (envelope * texture)[:, None]
    # A few very quiet diffuse taps; no long reverberant or ringing tail.
    dry = stereo.copy()
    for seconds, gain in [(0.029, 1.0), (0.061, 0.65), (0.103, 0.35)]:
        for channel, offset in [(0, 0), (1, 0.003)]:
            delay = round((seconds + offset) * RATE)
            stereo[delay:, channel] += dry[:-delay, 1 - channel] * gain * spec["tail"]
    stereo *= smoothstep((spec["duration"] - t) / 0.09)[:, None]
    stereo -= stereo.mean(axis=0, keepdims=True) * envelope[:, None] / envelope.mean()
    stereo[[0, -1], :] = 0
    rms = np.sqrt(np.mean(stereo ** 2))
    stereo *= min(10 ** (TARGET_RMS_DBFS / 20) / rms,
                  10 ** (PEAK_LIMIT_DBFS / 20) / np.max(np.abs(stereo)))
    return np.rint(stereo * 32767).astype("<i2")


def metrics(pcm: np.ndarray) -> dict:
    x = pcm.astype(np.float64) / 32768
    mid = x.mean(axis=1)
    spectrum = np.abs(np.fft.rfft(mid * np.hanning(len(mid)))) ** 2
    freq = np.fft.rfftfreq(len(mid), 1 / RATE)
    rms = float(np.sqrt(np.mean(x ** 2)))
    peak = float(np.max(np.abs(x)))
    windows = []
    for start in np.arange(0, WAVE_SECONDS, 0.3):
        end = min(float(start) + 0.3, len(x) / RATE)
        part = x[round(float(start) * RATE):round(end * RATE)]
        level = float(np.sqrt(np.mean(part ** 2))) if len(part) else 0
        windows.append(dict(start_seconds=round(float(start), 2), end_seconds=round(max(float(start), end), 2),
                            rms_dbfs=round(20 * math.log10(max(level, 1e-12)), 3)))
    return dict(duration_seconds=round(len(x) / RATE, 6), sample_rate_hz=RATE,
                channels=2, pcm_bits=16, peak_dbfs=round(20 * math.log10(peak), 3),
                rms_dbfs=round(20 * math.log10(rms), 3), clipped_samples=int(np.sum(np.abs(x) >= 1)),
                dc_offset_max=float(np.max(np.abs(x.mean(axis=0)))),
                largest_sample_step=float(np.max(np.abs(np.diff(x, axis=0)))),
                energy_below_120hz_pct=round(float(spectrum[freq < 120].sum() / spectrum.sum() * 100), 4),
                spectral_centroid_hz=round(float(np.sum(freq * spectrum) / spectrum.sum()), 1),
                endpoint_samples=pcm[[0, -1]].tolist(), wave_timeline_rms=windows)


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    entries = []
    for spec in VARIANTS:
        pcm = synthesize(spec)
        path = DEST / f"gate_wave_{spec['id']}.wav"
        with wave.open(str(path), "wb") as file:
            file.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
            file.writeframes(pcm.tobytes())
        report = metrics(pcm)
        assert report["clipped_samples"] == 0
        assert report["peak_dbfs"] <= PEAK_LIMIT_DBFS + 0.002
        assert abs(report["rms_dbfs"] - TARGET_RMS_DBFS) <= 0.05
        assert report["energy_below_120hz_pct"] < 0.02
        assert not np.any(pcm[[0, -1]])
        levels = [window["rms_dbfs"] for window in report["wave_timeline_rms"]]
        assert all(later < earlier for earlier, later in zip(levels[1:], levels[2:])), levels
        entries.append(dict(**spec, path=path.relative_to(ROOT).as_posix(),
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest(), metrics=report))
        print(f"{spec['name']}: {report['duration_seconds']:.2f} s, "
              f"RMS {report['rms_dbfs']:.2f} dBFS, peak {report['peak_dbfs']:.2f} dBFS")
    manifest = dict(schema_version=1, purpose="Gate expansion wave audition; candidates are not active game sounds",
                    generator="tools/audio/build_gate_candidates.py", numpy_version=np.__version__,
                    source="Original deterministic procedural synthesis; no recordings, external samples or paid services",
                    listening_performed=False, game_integration_performed=False,
                    preview_gain_db=0.0,
                    timing_reference=dict(card_growth_seconds=0.68, floor_wave_seconds=1.8,
                                          wave_strength="1 - time_seconds / 1.8",
                                          tail_envelope="0.38 * wave_strength ** 1.1; soft core layered above it",
                                          trigger="At element_wave start, simultaneously with growth, after floor contact and the existing 0.10 second pause"),
                    target_rms_dbfs=TARGET_RMS_DBFS, peak_limit_dbfs=PEAK_LIMIT_DBFS,
                    candidates=entries)
    (DEST / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
