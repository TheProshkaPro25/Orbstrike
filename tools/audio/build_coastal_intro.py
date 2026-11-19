"""Synthesize Stone Cove's stereo flyby and ascent cues with Python and ffmpeg."""
from __future__ import annotations

import math
from pathlib import Path
import random
import struct
import subprocess

RATE = 48000
DEST = Path(__file__).resolve().parents[2] / "assets/audio/sfx"


def ramp(t: float, start: float, end: float) -> float:
    u = min(1.0, max(0.0, (t - start) / (end - start)))
    return u * u * (3.0 - 2.0 * u)


def coefficient(hz: float) -> float:
    return -math.expm1(-math.tau * hz / RATE)


class NoiseBand:
    """Two one-pole filters for broad, soft-edged airflow."""

    def __init__(self, low_hz: float, high_hz: float):
        self.low_coefficient = coefficient(low_hz)
        self.high_coefficient = coefficient(high_hz)
        self.low = 0.0
        self.high = 0.0

    def sample(self, noise: float) -> float:
        self.low += self.low_coefficient * (noise - self.low)
        self.high += self.high_coefficient * (noise - self.high)
        return self.high - self.low


def wind() -> list[tuple[float, float]]:
    rng = random.Random(17831)
    body = NoiseBand(45, 205)
    rush = NoiseBand(160, 970)
    spray = NoiseBand(1850, 6600)
    flutter = NoiseBand(0.65, 4.3)
    frames = []
    for frame in range(round(3.45 * RATE)):
        t = frame / RATE
        pressure = body.sample(rng.uniform(-1.0, 1.0))
        flow = rush.sample(rng.uniform(-1.0, 1.0))
        airy = spray.sample(rng.uniform(-1.0, 1.0))
        gust = 1.0 + 10.0 * flutter.sample(rng.uniform(-1.0, 1.0))
        speed = ramp(t, 0.15, 2.8)
        braking = 1.0 - ramp(t, 2.96, 3.45)
        envelope = ramp(t, 0.0, 0.18) * (0.30 + 0.70 * speed) * braking
        center = (1.5 * pressure + (0.85 + 0.55 * speed) * flow) * gust
        # Short, overlapping sprays get brighter closer to the rim.
        spray_level = (0.32 + 0.60 * speed) * (0.75 + 0.25 * math.sin(math.tau * 1.7 * t))
        side = airy * spray_level
        frames.append((envelope * (center + side), envelope * (center - 0.65 * side)))
    return frames


def ascent() -> list[tuple[float, float]]:
    rng = random.Random(62819)
    lower = NoiseBand(125, 490)
    air = NoiseBand(320, 1650)
    width = NoiseBand(2100, 7500)
    phase = 0.0
    frames = []
    for frame in range(round(0.90 * RATE)):
        t = frame / RATE
        climb = ramp(t, 0.023, 0.37)
        air.low_coefficient = coefficient(320 + 780 * climb)
        air.high_coefficient = coefficient(1650 + 4250 * climb)
        lift = lower.sample(rng.uniform(-1.0, 1.0))
        whistle = air.sample(rng.uniform(-1.0, 1.0))
        sheen = width.sample(rng.uniform(-1.0, 1.0))
        phase += math.tau * (145 + 280 * climb) / RATE
        attack = ramp(t, 0.0, 0.17)
        motion = attack * (1.0 - ramp(t, 0.25, 0.49))
        trail = ramp(t, 0.16, 0.31) * (1.0 - ramp(t, 0.37, 0.90)) ** 2
        center = motion * (lift * 1.1 + whistle * 1.2 + 0.020 * math.sin(phase))
        center += trail * (0.23 * whistle + 0.15 * sheen)
        side = sheen * (0.35 * motion * climb + 0.22 * trail)
        frames.append((center + side, center - 0.82 * side))
    return frames


def encode(name: str, frames: list[tuple[float, float]], peak: float) -> None:
    gain = peak / max(abs(sample) for frame in frames for sample in frame)
    pcm = b"".join(struct.pack("<ff", left * gain, right * gain) for left, right in frames)
    subprocess.run(
        [
            "ffmpeg", "-nostdin", "-loglevel", "error", "-y",
            "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "pipe:0",
            "-c:a", "libvorbis", "-q:a", "5", str(DEST / f"{name}.ogg"),
        ],
        input=pcm,
        check=True,
    )


if __name__ == "__main__":
    encode("coastal_intro_wind", wind(), 0.42)
    encode("coastal_intro_ascent", ascent(), 0.46)
