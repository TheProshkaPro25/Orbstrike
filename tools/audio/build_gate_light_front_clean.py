"""Newly synthesized clean Light Front preview: 192 kHz synthesis -> 48 kHz PCM24.

NumPy only. Does not upscale or overwrite the previous PCM16 preview.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import wave

import numpy as np

from build_gate_candidates import smoothstep

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/audio/candidates/gate_wave'
OUTPUT = DEST / 'gate_wave_radial_04_light_front_clean.wav'
RATE, INTERNAL_RATE = 48000, 192000
DURATION, SEED = 1.82, 73404


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)))


def synthesize() -> np.ndarray:
    n = round(DURATION * INTERNAL_RATE)
    t = np.arange(n) / INTERNAL_RATE
    padding = round(0.25 * INTERNAL_RATE)
    size = 1 << (n + 2 * padding - 1).bit_length()
    frequency = np.fft.rfftfreq(size, 1 / INTERNAL_RATE)
    safe = np.maximum(frequency, 1.0)
    rng = np.random.default_rng(SEED)
    centers = np.array([430, 620, 890, 1280, 1840, 2640, 3790])
    # Broad overlapping components of the SAME excitation, blended continuously.
    # No independent pitched partials, dust layer, delays, comb paths or pulses.
    opening = smoothstep(t / 0.43)
    distance = smoothstep((t - 0.34) / 1.25)
    moving_center = 930 + 690 * opening - 940 * distance
    weights = np.exp(-0.5 * ((np.log2(centers)[None, :] - np.log2(moving_center)[:, None]) / 0.54) ** 2)
    weights /= weights.sum(axis=1, keepdims=True)
    streams = []
    for channel in range(2):
        excitation = np.fft.rfft(rng.normal(size=size))
        bands = []
        for center in centers:
            spectral_shape = np.exp(-0.5 * (np.log2(safe / center) / 0.66) ** 2)
            # Smoothly remove rumble and exposed fizzy highs before modulation.
            spectral_shape *= (1 - np.exp(-(safe / 210) ** 4)) * np.exp(-(safe / 3450) ** 4)
            spectral_shape[0] = 0
            samples = np.fft.irfft(excitation * spectral_shape, size)[padding:padding+n]
            bands.append(samples / rms(samples))
        source = (np.column_stack(bands) * weights).sum(axis=1)
        streams.append(source)
    mid, diffuse = streams
    # The coherent centre stays present throughout the symmetric outward spread.
    width = 0.008 + 0.69 * smoothstep((t - 0.11) / 0.93)
    stereo = np.column_stack([mid + width * diffuse, mid - width * diffuse])
    attack = smoothstep(t / 0.19)
    release = 1 - smoothstep(np.clip((t - 0.30) / 1.40, 0, 1))
    envelope = attack * release ** 1.6
    envelope *= smoothstep((DURATION - t) / 0.18)
    stereo *= envelope[:, None]
    # Windowed-sinc anti-alias FIR before decimating by4; designed at192kHz.
    # Modulation is smooth, but this also removes any residual above output Nyquist.
    taps = np.arange(257) - 128
    cutoff = 14000 / INTERNAL_RATE
    kernel = 2 * cutoff * np.sinc(2 * cutoff * taps) * np.kaiser(257, 10.0)
    kernel /= kernel.sum()
    stereo = np.column_stack([np.convolve(stereo[:, c], kernel, 'same')[::4] for c in range(2)])
    tout = np.arange(len(stereo)) / RATE
    edge = smoothstep(tout / 0.025) * smoothstep((DURATION - tout) / 0.09)
    stereo *= edge[:, None]
    envout = envelope[::4] * edge
    stereo -= stereo.mean(axis=0, keepdims=True) * envout[:, None] / envout.mean()
    stereo *= 10 ** (-35 / 20) / rms(stereo)
    stereo[[0, -1]] = 0
    assert np.max(np.abs(stereo)) < 0.20
    return stereo


def pcm24_pack(x: np.ndarray) -> bytes:
    pcm = np.rint(x * 8388608).astype(np.int32)
    assert np.max(np.abs(pcm)) < 8388607
    unsigned = pcm.astype(np.uint32)
    packed = np.stack([unsigned & 255, (unsigned >> 8) & 255, (unsigned >> 16) & 255], axis=-1)
    return packed.astype(np.uint8).tobytes()


def pcm24_unpack(data: bytes) -> np.ndarray:
    b = np.frombuffer(data, np.uint8).reshape(-1, 3).astype(np.int32)
    value = b[:, 0] | b[:, 1] << 8 | b[:, 2] << 16
    value = (value ^ 8388608) - 8388608
    return value.reshape(-1, 2).astype(float) / 8388608


def report(x: np.ndarray, rate: int) -> dict:
    mono = x.mean(axis=1)
    spectrum = np.abs(np.fft.rfft(mono * np.hanning(len(mono)))) ** 2
    frequencies = np.fft.rfftfreq(len(mono), 1 / rate)
    def correlation(a: float, b: float) -> float:
        return round(float(np.corrcoef(x[round(a * rate):round(b * rate)].T)[0, 1]), 5)
    return dict(duration_seconds=len(x) / rate, rms_dbfs=round(20 * np.log10(rms(x)), 3),
                peak_dbfs=round(20 * np.log10(np.max(np.abs(x))), 3),
                clipped_samples=int(np.sum(np.abs(x) >= 1)),
                dc_offset_max=float(np.max(np.abs(x.mean(axis=0)))),
                endpoint_samples=x[[0, -1]].tolist(),
                mono_loss_db=round(20 * np.log10(rms(mono) / rms(x)), 3),
                early_channel_correlation=correlation(0.04, 0.24),
                distant_channel_correlation=correlation(0.95, 1.50),
                spectral_centroid_hz=round(float(np.sum(frequencies * spectrum) / spectrum.sum()), 1),
                energy_above_3500hz_pct=round(float(spectrum[frequencies > 3500].sum() / spectrum.sum() * 100), 4),
                energy_above_12000hz_pct=round(float(spectrum[frequencies > 12000].sum() / spectrum.sum() * 100), 8))


def main() -> None:
    old = sorted(p for p in DEST.glob('*.wav') if p != OUTPUT)
    assert len(old) == 21
    old_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in old}
    generated = synthesize()
    packed = pcm24_pack(generated)
    assert packed == pcm24_pack(synthesize())
    with wave.open(str(OUTPUT), 'wb') as output:
        output.setparams((2, 3, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(packed)
    with wave.open(str(OUTPUT), 'rb') as stored:
        assert (stored.getnchannels(), stored.getsampwidth(), stored.getframerate()) == (2, 3, RATE)
        actual = pcm24_unpack(stored.readframes(stored.getnframes()))
    improved = report(actual, RATE)
    assert improved['clipped_samples'] == 0 and improved['peak_dbfs'] < -15
    assert abs(improved['rms_dbfs'] + 35) < .002
    assert improved['dc_offset_max'] < 1e-7 and not actual[[0, -1]].any()
    assert improved['mono_loss_db'] > -1
    assert improved['early_channel_correlation'] > .98
    assert improved['distant_channel_correlation'] < .55
    source = DEST / 'gate_wave_radial_04_light_front.wav'
    with wave.open(str(source), 'rb') as stored:
        original = np.frombuffer(stored.readframes(stored.getnframes()), '<i2').reshape(-1, 2).astype(float) / 32768
    old_report = report(original, RATE)
    assert old_hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in old}
    metadata = dict(name='Световой фронт — чистый вариант', path=OUTPUT.relative_to(ROOT).as_posix(),
                    generator='tools/audio/build_gate_light_front_clean.py', numpy_version=np.__version__, seed=SEED,
                    sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(), source_reference=source.relative_to(ROOT).as_posix(),
                    synthesis_rate_hz=INTERNAL_RATE, output_rate_hz=RATE, pcm_bits=24, channels=2,
                    synthesis='New noise excitation, seven coherent overlapping bands with smooth continuous spectral motion, no dust layer or delayed comb paths; symmetric diffuse widening, windowed sinc FIR decimation.',
                    target_rms_dbfs=-35.0, preview_gain_db=0.0,
                    listening_performed=False, game_integration_performed=False,
                    quality_note='Proposed cleaner texture for user audition; technical metrics do not establish subjective quality.',
                    previous_twenty_one_sha256=old_hashes, original_metrics=old_report, metrics=improved)
    (DEST / 'light_front_clean_manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(original_metrics=old_report, new_metrics=improved), indent=2))


if __name__ == '__main__':
    main()
