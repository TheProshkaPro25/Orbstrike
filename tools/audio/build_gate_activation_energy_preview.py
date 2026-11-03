"""Original soft activation accent expanding into a radial energy wave.

No source-anime audio was available: this is a new design, not a verified imitation.
NumPy only; preserves all existing previews, creates one PCM24 WAV and manifest.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

import numpy as np

from build_gate_candidates import smoothstep
from build_gate_light_front_clean import pcm24_pack, pcm24_unpack, report

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/audio/candidates/gate_wave'
OUTPUT = DEST / 'gate_wave_activation_energy.wav'
RATE, INTERNAL_RATE, DURATION, SEED = 48000, 192000, 2.02, 73501


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)))


def band(n: int, rng: np.random.Generator, center: float, width: float) -> np.ndarray:
    padding = INTERNAL_RATE // 4
    size = 1 << (n + padding * 2 - 1).bit_length()
    frequency = np.fft.rfftfreq(size, 1 / INTERNAL_RATE)
    safe = np.maximum(frequency, 1.0)
    shape = np.exp(-0.5 * (np.log2(safe / center) / width) ** 2)
    shape *= (1 - np.exp(-(safe / 170) ** 6)) * np.exp(-(safe / 3600) ** 6)
    shape[0] = 0
    x = np.fft.irfft(np.fft.rfft(rng.normal(size=size)) * shape, size)[padding:padding+n]
    return x / rms(x)



def synthesize_gentle(air_gain_db: float = 0.0) -> np.ndarray:
    """A slower light profile: broad soft onset and near-level high resonance."""
    duration = 2.40
    n = round(duration * INTERNAL_RATE)
    t = np.arange(n) / INTERNAL_RATE
    rng = np.random.default_rng(SEED)
    # Small continuous downward drift, not a dive or a change of note.
    frequency = 1180 - 120 * smoothstep(t / 1.60)
    phase = 2 * np.pi * np.cumsum(frequency) / INTERNAL_RATE
    tone = np.sin(phase) + 0.065 * np.sin(2 * phase + 0.45)
    tone += 0.012 * np.sin(3 * phase + 0.7)
    # A broad crest blends organically into the tail; no old low voice is inserted.
    attack = smoothstep(t / 0.36)
    release = (1 - smoothstep(np.clip((t - 0.46) / 1.79, 0, 1))) ** 1.20
    envelope = attack * release
    tone_envelope = smoothstep(t / 0.39)
    tone_envelope *= (1 - smoothstep(np.clip((t - 0.52) / 1.31, 0, 1))) ** 1.40
    tone *= tone_envelope
    tone *= 0.48 / rms(tone)
    near = band(n, rng, 1450, 0.84)
    distant = band(n, rng, 720, 0.91)
    side_near = band(n, rng, 1300, 0.88)
    side_distant = band(n, rng, 650, 0.94)
    blend = smoothstep(t / 2.05)
    mid = ((1 - blend) * near + blend * distant) * envelope
    side = ((1 - blend) * side_near + blend * side_distant) * envelope
    noise_level = rms(mid)
    mid /= noise_level
    side /= noise_level
    width = 0.015 + 0.64 * smoothstep((t - 0.20) / 1.27)
    reference_stereo = np.column_stack([mid + width * side + tone, mid - width * side + tone])
    stereo = reference_stereo.copy()
    if air_gain_db:
        air_gain = 10 ** (air_gain_db / 20)
        stereo = np.column_stack([(mid + width * side) * air_gain + tone,
                                  (mid - width * side) * air_gain + tone])
    taps = np.arange(257) - 128
    cutoff = 14000 / INTERNAL_RATE
    kernel = 2 * cutoff * np.sinc(2 * cutoff * taps) * np.kaiser(257, 10)
    kernel /= kernel.sum()
    stereo = np.column_stack([np.convolve(stereo[:, c], kernel, 'same')[::4] for c in [0, 1]])
    tout = np.arange(len(stereo)) / RATE
    edge = smoothstep(tout / 0.03) * smoothstep((duration - tout) / 0.16)
    stereo *= edge[:, None]
    correction = envelope[::4] * edge
    stereo -= stereo.mean(axis=0, keepdims=True) * correction[:, None] / correction.mean()
    reference_rms = rms(stereo)
    if air_gain_db:
        # Retain the original master gain: do not normalise the removed air back up.
        ref = np.column_stack([np.convolve(reference_stereo[:, c], kernel, 'same')[::4] for c in [0, 1]])
        ref *= edge[:, None]
        ref -= ref.mean(axis=0, keepdims=True) * correction[:, None] / correction.mean()
        reference_rms = rms(ref)
    stereo *= 10 ** (-34.5 / 20) / reference_rms
    stereo[[0, -1]] = 0
    assert np.max(np.abs(stereo)) < 10 ** (-15 / 20)
    return stereo


def synthesize(high_start_semitones: float = 0.0, light_start: bool = False, gentle_profile: bool = False, gentle_air_gain_db: float = 0.0) -> np.ndarray:
    if gentle_profile:
        return synthesize_gentle(gentle_air_gain_db)
    n = round(DURATION * INTERNAL_RATE)
    t = np.arange(n) / INTERNAL_RATE
    rng = np.random.default_rng(SEED)
    # A rounded voiced 'zhum' accent: continuous down-bending resonance, no notes,
    # metallic ping, bass hit or rapid high laser sweep.
    frequency = 245 + 245 * np.exp(-t / 0.35)
    phase = 2 * np.pi * np.cumsum(frequency) / INTERNAL_RATE
    movement = np.sin(np.pi * np.clip(t / 0.90, 0, 1)) ** 2
    fm_index = 0.54 * np.exp(-t / 0.43)
    voiced = np.sin(phase + fm_index * np.sin(2.08 * phase + 0.35))
    voiced += 0.28 * np.sin(2 * phase + 0.18 * movement * np.sin(phase * 0.13))
    voiced += 0.14 * np.sin(3 * phase + 0.45)
    voiced += 0.075 * np.sin(4 * phase + 0.80)
    voiced += 0.035 * np.sin(5 * phase + 0.35)
    accent_env = smoothstep(t / 0.078) * np.exp(-t / 0.34)
    accent_env *= (1 - smoothstep((t - 0.64) / 0.59))
    voiced *= accent_env
    voiced /= rms(voiced)
    if high_start_semitones:
        # Raise only the early voiced accent, then return to the unchanged voice.
        # A smooth phase-safe crossfade avoids an abrupt pitch/phase reset.
        offset = (2 ** (high_start_semitones / 12) - 1) * (1 - smoothstep((t - 0.08) / (0.62 if light_start else 0.50)))
        high_phase = 2 * np.pi * np.cumsum(frequency * (1 + offset)) / INTERNAL_RATE
        higher_fm = fm_index * (0.26 if light_start else 1.0)
        higher = np.sin(high_phase + higher_fm * np.sin(2.08 * high_phase + 0.35))
        higher += (0.13 if light_start else 0.28) * np.sin(2 * high_phase + 0.18 * movement * np.sin(high_phase * 0.13))
        higher += (0.04 if light_start else 0.14) * np.sin(3 * high_phase + 0.45)
        higher += (0.012 if light_start else 0.075) * np.sin(4 * high_phase + 0.80)
        higher += (0.004 if light_start else 0.035) * np.sin(5 * high_phase + 0.35)
        higher *= accent_env
        higher /= rms(higher)
        return_to_original = smoothstep((t - (0.50 if light_start else 0.40)) / 0.22)
        voiced = higher * (1 - return_to_original) + voiced * return_to_original
    # Soft breath/charged texture makes the resonance part of the front, not a
    # disconnected electronic note. Continuous spectral darkening with distance.
    near = band(n, rng, 1450, 0.77)
    distant = band(n, rng, 570, 0.86)
    side_near = band(n, rng, 1300, 0.83)
    side_far = band(n, rng, 510, 0.91)
    distance = smoothstep((t - 0.27) / 1.32)
    blend = smoothstep(t / 1.55)
    mid = near * (1 - blend) + distant * blend
    side = side_near * (1 - blend) + side_far * blend
    air_env = smoothstep((t - 0.025) / 0.22)
    air_env *= (1 - smoothstep(np.clip((t - 0.26) / 1.61, 0, 1))) ** 1.32
    mid *= air_env
    side *= air_env
    noise_level = rms(mid)
    mid /= noise_level
    side /= noise_level
    width = 0.012 + 0.78 * smoothstep((t - 0.12) / 0.97)
    stereo = np.column_stack([mid + width * side, mid - width * side])
    # Accent remains central; the surrounding wave opens radially on both sides.
    stereo += (voiced * 0.93)[:, None]
    edge = smoothstep((DURATION - t) / 0.19)
    stereo *= edge[:, None]
    # Oversampled synthesis and anti-alias filtering before 4x decimation.
    taps = np.arange(257) - 128
    cutoff = 14000 / INTERNAL_RATE
    kernel = 2 * cutoff * np.sinc(2 * cutoff * taps) * np.kaiser(257, 10)
    kernel /= kernel.sum()
    stereo = np.column_stack([np.convolve(stereo[:, c], kernel, 'same')[::4] for c in [0, 1]])
    tout = np.arange(len(stereo)) / RATE
    fade = smoothstep(tout / 0.025) * smoothstep((DURATION - tout) / 0.10)
    stereo *= fade[:, None]
    correction = air_env[::4] * fade
    stereo -= stereo.mean(axis=0, keepdims=True) * correction[:, None] / correction.mean()
    stereo *= 10 ** (-33 / 20) / rms(stereo)
    stereo[[0, -1]] = 0
    assert np.max(np.abs(stereo)) < 10 ** (-12 / 20)
    return stereo


def main() -> None:
    previous = sorted(p for p in DEST.glob('*.wav') if p != OUTPUT)
    assert len(previous) == 22
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    packed = pcm24_pack(synthesize())
    assert packed == pcm24_pack(synthesize())
    with wave.open(str(OUTPUT), 'wb') as output:
        output.setparams((2, 3, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(packed)
    with wave.open(str(OUTPUT), 'rb') as stored:
        assert (stored.getnchannels(), stored.getsampwidth(), stored.getframerate()) == (2, 3, RATE)
        actual = pcm24_unpack(stored.readframes(stored.getnframes()))
    measured = report(actual, RATE)
    assert measured['duration_seconds'] == DURATION
    assert abs(measured['rms_dbfs'] + 33) < .002
    assert measured['peak_dbfs'] < -12 and measured['clipped_samples'] == 0
    assert measured['dc_offset_max'] < 1e-7 and not actual[[0, -1]].any()
    assert measured['mono_loss_db'] > -1.2
    assert measured['early_channel_correlation'] > .97
    assert measured['distant_channel_correlation'] < .60
    assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    metadata = dict(name='Активация — расходящаяся энергия', path=OUTPUT.relative_to(ROOT).as_posix(),
                    generator='tools/audio/build_gate_activation_energy_preview.py', numpy_version=np.__version__, seed=SEED,
                    sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
                    source='Original procedural synthesis; no sampled anime or other external audio',
                    design='Soft rounded voiced energy accent with continuous downward resonance, expanding broadband wave body and distant darkening tail. No discrete melody or bell ping.',
                    reference_note='Conceptual direction only: source-anime audio could not be obtained, similarity is not verified.',
                    synthesis_rate_hz=INTERNAL_RATE, output_rate_hz=RATE, pcm_bits=24, channels=2,
                    target_rms_dbfs=-33.0, peak_ceiling_dbfs=-12.0, preview_gain_db=0.0,
                    listening_performed=False, game_integration_performed=False,
                    previous_twenty_two_sha256=hashes, metrics=measured)
    (DEST / 'activation_energy_manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(measured, indent=2))


if __name__ == '__main__':
    main()
