"""Reduce all gentle-profile broadband layers20dB; preserve tone and master gain."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import wave
import numpy as np
from build_gate_activation_energy_preview import DEST, RATE, INTERNAL_RATE, SEED, synthesize_gentle
from build_gate_light_front_clean import pcm24_pack, pcm24_unpack, report

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = DEST / 'gate_wave_activation_energy_gentle_low_air.wav'
AIR_GAIN_DB = -20.0


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)))


def main() -> None:
    previous = sorted(p for p in DEST.glob('*.wav') if p != OUTPUT)
    assert len(previous) == 26
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    original = synthesize_gentle()
    tone = synthesize_gentle(float('-inf'))
    reduced = synthesize_gentle(AIR_GAIN_DB)
    with wave.open(str(DEST / 'gate_wave_activation_energy_gentle.wav'), 'rb') as w:
        assert w.readframes(w.getnframes()) == pcm24_pack(original)
    # Linear component proof, including FIR, fades, DC correction and master gain.
    air_before = original - tone
    air_after = reduced - tone
    assert np.max(np.abs(reduced - (tone + air_before * .1))) < 1e-14
    measured_reduction = 20 * np.log10(rms(air_after) / rms(air_before))
    assert abs(measured_reduction - AIR_GAIN_DB) < 1e-9
    assert np.max(np.abs((reduced - air_after) - tone)) < 1e-15
    packed = pcm24_pack(reduced)
    assert packed == pcm24_pack(synthesize_gentle(AIR_GAIN_DB))
    with wave.open(str(OUTPUT), 'wb') as w:
        w.setparams((2, 3, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(packed)
    with wave.open(str(OUTPUT), 'rb') as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()) == (2, 3, RATE, 115200)
        actual = pcm24_unpack(w.readframes(w.getnframes()))
    measured = report(actual, RATE)
    assert measured['clipped_samples'] == 0 and measured['peak_dbfs'] < -15
    assert measured['dc_offset_max'] < 1e-7 and not actual[[0,-1]].any()
    assert measured['mono_loss_db'] > -.5
    assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    metadata = dict(name='Размеренное сияние — почти без воздуха', path=OUTPUT.relative_to(ROOT).as_posix(),
        generator='tools/audio/build_gate_activation_gentle_low_air.py', base_generator='tools/audio/build_gate_activation_energy_preview.py',
        profile='gentle', seed=SEED, synthesis_rate_hz=INTERNAL_RATE, output_rate_hz=RATE, pcm_bits=24, channels=2,
        sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        air_gain_db=AIR_GAIN_DB, measured_air_component_change_db=round(float(measured_reduction), 6),
        tone_gain_change_db=0.0, master_gain_change_db=0.0, normalised_after_air_reduction=False,
        design='All broadband mid/side layers reduced10x in amplitude; original high tone,360ms attack, slow drift and master gain retained. No added tail noise.',
        preview_gain_db=0.0, listening_performed=False, game_integration_performed=False,
        previous_twenty_six_sha256=hashes, original_metrics=report(original, RATE), metrics=measured)
    (DEST / 'activation_gentle_low_air_manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in metadata.items() if k in ['measured_air_component_change_db','tone_gain_change_db','master_gain_change_db','metrics']},indent=2))


if __name__ == '__main__':
    main()
