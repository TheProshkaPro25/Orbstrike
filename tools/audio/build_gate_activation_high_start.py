"""One higher-start version; retains the previous activation and all previews."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import wave
import numpy as np
from build_gate_activation_energy_preview import DEST, RATE, INTERNAL_RATE, DURATION, SEED, synthesize
from build_gate_light_front_clean import pcm24_pack, pcm24_unpack, report

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = DEST / 'gate_wave_activation_energy_high_start.wav'
SEMITONES = 7.0


def read(path: Path) -> np.ndarray:
    with wave.open(str(path), 'rb') as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (2, 3, RATE)
        return pcm24_unpack(w.readframes(w.getnframes()))


def early_peak(x: np.ndarray) -> float:
    section = x[round(.07 * RATE):round(.13 * RATE)].mean(axis=1)
    size = 32768
    power = abs(np.fft.rfft(section * np.hanning(len(section)), n=size)) ** 2
    freq = np.fft.rfftfreq(size, 1 / RATE)
    selection = (freq >= 250) & (freq < 850)
    return round(float(freq[selection][np.argmax(power[selection])]), 2)


def main() -> None:
    previous = sorted(p for p in DEST.glob('*.wav') if p != OUTPUT)
    assert len(previous) == 23
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    original_path = DEST / 'gate_wave_activation_energy.wav'
    original = read(original_path)
    # The optional generator parameter preserves the old default byte-for-byte.
    with wave.open(str(original_path), 'rb') as w:
        assert w.readframes(w.getnframes()) == pcm24_pack(synthesize())
    packed = pcm24_pack(synthesize(SEMITONES))
    assert packed == pcm24_pack(synthesize(SEMITONES))
    with wave.open(str(OUTPUT), 'wb') as w:
        w.setparams((2, 3, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(packed)
    x = read(OUTPUT)
    measured = report(x, RATE)
    assert measured['duration_seconds'] == DURATION
    assert abs(measured['rms_dbfs'] + 33) < .002
    assert measured['peak_dbfs'] < -12 and measured['clipped_samples'] == 0
    assert measured['dc_offset_max'] < 1e-7 and not x[[0, -1]].any()
    assert measured['mono_loss_db'] > -1.2
    peak_before, peak_after = early_peak(original), early_peak(x)
    assert peak_after > peak_before * 1.35
    # From0.65s onward only the final RMS normalisation and tiny DC correction differ.
    late_original = original[round(.65 * RATE):]
    late_new = x[round(.65 * RATE):]
    late_gain = float(np.sum(late_new * late_original) / np.sum(late_original ** 2))
    assert np.corrcoef(late_original.ravel(), late_new.ravel())[0, 1] > .99999
    assert abs(20 * np.log10(late_gain)) < .15
    assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    metadata = dict(name='Активация — выше в начале', path=OUTPUT.relative_to(ROOT).as_posix(),
        generator='tools/audio/build_gate_activation_high_start.py', base_generator='tools/audio/build_gate_activation_energy_preview.py',
        source=original_path.relative_to(ROOT).as_posix(), sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        synthesis_rate_hz=INTERNAL_RATE, output_rate_hz=RATE, pcm_bits=24, channels=2, seed=SEED,
        initial_voice_pitch_raise_semitones=SEMITONES, original_voice_return_seconds=.62,
        early_70_130ms_dominant_peak_hz=dict(original=peak_before, higher_start=peak_after),
        after_650ms_gain_difference_db=round(float(20 * np.log10(late_gain)), 4),
        after_650ms_correlation=round(float(np.corrcoef(late_original.ravel(), late_new.ravel())[0, 1]), 8),
        target_rms_dbfs=-33.0, preview_gain_db=0.0, listening_performed=False, game_integration_performed=False,
        previous_twenty_three_sha256=hashes, metrics=measured)
    (DEST / 'activation_high_start_manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in metadata.items() if k in ['early_70_130ms_dominant_peak_hz','after_650ms_gain_difference_db','after_650ms_correlation','metrics']}, indent=2))


if __name__ == '__main__':
    main()
