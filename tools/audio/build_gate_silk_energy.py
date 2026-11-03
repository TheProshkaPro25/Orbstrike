"""Add a restrained tonal energy ripple to the existing silk preview only."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

import numpy as np

from build_gate_candidates import metrics, smoothstep

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets/audio/candidates/gate_wave"
SOURCE = DEST / "gate_wave_02_silk_fold.wav"
OUTPUT = DEST / "gate_wave_02_silk_energy.wav"


def main() -> None:
    source_sha = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    with wave.open(str(SOURCE), "rb") as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (2, 2, 48000)
        original_pcm = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").reshape(-1, 2)
    original = original_pcm.astype(np.float64) / 32768
    rate = 48000
    t = np.arange(len(original)) / rate
    duration = len(t) / rate
    # One continuous swell, with overlapping soft partials; no discrete melody,
    # metallic strike, transient or bright high-frequency bell.
    rise = smoothstep(t / 0.58)
    fall = smoothstep((t - 0.58) / 0.90)
    frequency = 435 + 225 * rise - 185 * fall
    frequency *= 1 + 0.0016 * np.sin(2 * np.pi * 3.0 * t)
    phase = 2 * np.pi * np.cumsum(frequency) / rate
    envelope = smoothstep(t / 0.19) * np.clip(1 - t / duration, 0, 1) ** 1.65
    envelope *= smoothstep((duration - t) / 0.15)
    # Overlapping harmonic colours breathe through the crest instead of attacks.
    colour = smoothstep((t - 0.12) / 0.48) * (1 - 0.6 * smoothstep((t - 0.65) / 0.65))
    voices = []
    for side in [-1, 1]:
        detune = side * 0.0035 * np.sin(np.pi * t / duration) ** 2
        voice = np.sin(phase + detune * 2 * np.pi * t)
        voice += 0.30 * colour * np.sin(phase * 1.5 + 0.35 + side * 0.12)
        voice += 0.16 * colour * np.sin(phase * 2.0 + 0.70 + side * 0.20)
        voices.append(voice * envelope)
    tonal = np.column_stack(voices)
    tonal *= 10 ** (-42.5 / 20) / np.sqrt(np.mean(tonal ** 2))
    mixed = original + tonal
    gain = np.sqrt(np.mean(original ** 2)) / np.sqrt(np.mean(mixed ** 2))
    mixed *= gain
    mixed[[0, -1]] = 0
    pcm = np.rint(mixed * 32768).astype("<i2")
    assert np.max(np.abs(mixed)) < 0.99
    with wave.open(str(OUTPUT), "wb") as output:
        output.setparams((2, 2, rate, 0, "NONE", "not compressed"))
        output.writeframes(pcm.tobytes())
    report = metrics(pcm)
    original_report = metrics(original_pcm)
    assert report["clipped_samples"] == 0
    assert abs(report["rms_dbfs"] - original_report["rms_dbfs"]) < 0.02
    assert not pcm[[0, -1]].any()
    assert source_sha == hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    metadata = dict(
        name="Шёлковая энергия", path=OUTPUT.relative_to(ROOT).as_posix(),
        generator="tools/audio/build_gate_silk_energy.py",
        source=SOURCE.relative_to(ROOT).as_posix(), source_sha256=source_sha,
        sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        description="Исходный шёлковый шелест с непрерывным мягким энергетическим переливом вверх и вниз; без отдельной мелодии и ударного разряда.",
        frequency_trajectory_hz=[435, 660, 475], partial_ratios=[1.0, 1.5, 2.0],
        tonal_rms_dbfs_after_mix=round(float(20 * np.log10(np.sqrt(np.mean((tonal * gain) ** 2)))) , 3),
        original_layer_gain_db=round(float(20 * np.log10(gain)), 3),
        preview_gain_db=0.0, numpy_version=np.__version__,
        listening_performed=False, game_integration_performed=False,
        original_metrics=original_report, metrics=report)
    (DEST / "silk_energy_manifest.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
