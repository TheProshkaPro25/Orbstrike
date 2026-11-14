"""Rebuild contact sounds from the credited Orbstrike recordings.

Run from any directory with NumPy and FFmpeg on PATH. Existing card sounds
and voices are read-only inputs. Add --fire-source and --light-source with
the original recordings to rebuild those cues. See CREDITS.md for sources.
"""
import argparse
from pathlib import Path
import subprocess

import numpy as np

SFX = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"
RATE = 44100


def layer(name, start, seconds, filters):
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", str(start), "-i", str(SFX / f"{name}.ogg"),
        "-af", filters, "-t", str(seconds), "-ar", str(RATE), "-ac", "1", "-f", "f32le", "-",
    ])
    return np.frombuffer(data, dtype="<f4").astype(np.float64)


def damp(audio, attack, release):
    time = np.arange(len(audio)) / RATE
    return audio * np.minimum(time / attack, 1) * np.clip((time[-1] - time) / release, 0, 1) ** 2


def add(mix, audio, start, gain):
    at = int(start * RATE)
    size = min(len(audio), len(mix) - at)
    mix[at:at + size] += audio[:size] * gain


def resonance(time, start, low, high, decay):
    age = np.maximum(time - start, 0)
    phase = low * age + (high - low) * (1 - np.exp(-age * 33)) / 33
    return np.sin(2 * np.pi * phase) * np.exp(-age * decay) * np.minimum(age * 700, 1)


def encode_supplied(name, source, start, length, fade, gain_db):
    if source is None:
        return
    fade_start = length - fade
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-ss", str(start), "-i", str(source), "-t", str(length),
        "-af", f"afade=t=in:d=0.003,afade=t=out:st={fade_start:.3f}:d={fade},volume={gain_db}dB",
        "-c:a", "libvorbis", "-q:a", "5", str(SFX / f"impact_{name}.ogg"),
    ], check=True)


def build(fire_source=None, light_source=None):
    encode_supplied("fire", fire_source, 0, 1.65, 0.20, -6)
    encode_supplied("light", light_source, 0.025, 2.873, 0.103, -5)
    # The contact itself has a distinct attack, spectrum and decay for each element.
    takes = {
        "gale": (0.09, 0.47, "highpass=f=310,equalizer=f=2400:t=q:w=1:g=2.2,lowpass=f=7900", 0.24),
        "stone": (0.00, 0.72, "highpass=f=60,lowpass=f=4400", 0.27),
        "shadow": (0.16, 0.64, "highpass=f=67,lowpass=f=1800", 0.36),
        "tide": (0.18, 0.62, "highpass=f=160,lowpass=f=7600", 0.25),
    }
    rng = np.random.default_rng(26114)
    # Keep the existing Gale sample sequence after removing Fire's four noise layers.
    rng.normal(size=4 * 1700)
    for name, (start, duration, filters, fade) in takes.items():
        t = np.arange(round(duration * RATE)) / RATE
        x = damp(layer("ability_" + name, start, duration, filters), 0.003, fade)
        mix = np.zeros_like(t)
        add(mix, x, 0, 1)
        if name == "gale":
            # A hard split discharge with falling taps, over the recorded air rush.
            for at, gain in [(0, 0.47), (0.043, 0.19), (0.095, 0.10)]:
                noise = np.diff(rng.normal(size=3700), prepend=0)
                add(mix, damp(noise, 0.0006, 0.080), at, gain * 0.46)
            mix += 0.09 * resonance(t, 0, 85, 230, 18)
        elif name == "stone":
            add(mix, damp(layer("ball_bounce_1", 0, 0.19, "highpass=f=75,lowpass=f=3600"), 0.002, 0.11), 0.29, 0.30)
            add(mix, damp(layer("ball_bounce_2", 0, 0.17, "highpass=f=180,lowpass=f=4900"), 0.002, 0.12), 0.42, 0.20)
            mix += 0.14 * resonance(t, 0, 74, 109, 19)
        elif name == "shadow":
            mix += 0.21 * resonance(t, 0.006, 55, 109, 11)
            mix += 0.13 * resonance(t, 0.012, 84, 129, 14)
            # A low second pulse follows the compressed transient.
            mix += 0.070 * resonance(t, 0.105, 48, 83, 13)
        else:
            droplets = damp(layer("ability_tide", 0.49, 0.16, "highpass=f=900,lowpass=f=6800"), 0.002, 0.11)
            add(mix, droplets, 0.23, 0.49)
            add(mix, droplets, 0.35, 0.28)
            mix += 0.11 * resonance(t, 0, 103, 217, 20)

        mix -= np.mean(mix)
        mix = damp(mix, 0.002, 0.025)
        mix = np.tanh(mix * 1.25)
        rms = np.sqrt(np.mean(mix[:RATE // 4] ** 2))
        mix *= min(0.20 / rms, 0.68 / np.max(np.abs(mix)))
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1",
            "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(SFX / f"impact_{name}.ogg"),
        ], input=mix.astype("<f4").tobytes(), check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fire-source", type=Path)
    parser.add_argument("--light-source", type=Path)
    args = parser.parse_args()
    build(args.fire_source, args.light_source)
