"""One measured, gentle activation profile; no game integration."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import wave
import numpy as np
from build_gate_activation_energy_preview import DEST, RATE, INTERNAL_RATE, SEED, synthesize
from build_gate_light_front_clean import pcm24_pack, pcm24_unpack, report

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = DEST / 'gate_wave_activation_energy_gentle.wav'
DURATION = 2.40


def main() -> None:
    old = sorted(p for p in DEST.glob('*.wav') if p != OUTPUT)
    assert len(old) == 25
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in old}
    packed = pcm24_pack(synthesize(gentle_profile=True))
    assert packed == pcm24_pack(synthesize(gentle_profile=True))
    with wave.open(str(OUTPUT), 'wb') as w:
        w.setparams((2, 3, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(packed)
    with wave.open(str(OUTPUT), 'rb') as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()) == (2, 3, RATE, round(DURATION * RATE))
        actual = pcm24_unpack(w.readframes(w.getnframes()))
    measured = report(actual, RATE)
    assert measured['clipped_samples'] == 0 and measured['peak_dbfs'] < -15
    assert abs(measured['rms_dbfs'] + 34.5) < .002
    assert measured['dc_offset_max'] < 1e-7 and not actual[[0,-1]].any()
    assert measured['mono_loss_db'] > -1.2
    envelope = []
    for start in np.arange(0, DURATION, .10):
        section = actual[round(start * RATE):round((start + .1) * RATE)]
        envelope.append(round(float(20 * np.log10(max(np.sqrt(np.mean(section ** 2)), 1e-12))), 2))
    assert envelope[0] + 15 < envelope[3]
    assert envelope[0] < envelope[1] < envelope[2] < envelope[3]
    # Track dominant early tonal ridge directly in stored audio, not just the formula.
    frequency_track = []
    for start in [.10, .30, .50, .70, .90, 1.10]:
        section = actual[round(start * RATE):round((start + .12) * RATE)].mean(axis=1)
        size = 65536
        power = abs(np.fft.rfft(section * np.hanning(len(section)), n=size)) ** 2
        frequency = np.fft.rfftfreq(size, 1 / RATE)
        mask = (frequency > 950) & (frequency < 1300)
        peak = float(frequency[mask][np.argmax(power[mask])])
        frequency_track.append(dict(start_seconds=start, dominant_tonal_peak_hz=round(peak, 2)))
    peaks = [item['dominant_tonal_peak_hz'] for item in frequency_track]
    assert 1000 < min(peaks) <= max(peaks) < 1250
    assert max(abs(a-b) for a,b in zip(peaks,peaks[1:])) < 35
    assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in old}
    metadata = dict(name='Активация — размеренное сияние', path=OUTPUT.relative_to(ROOT).as_posix(),
        generator='tools/audio/build_gate_activation_gentle.py', base_generator='tools/audio/build_gate_activation_energy_preview.py',
        profile='gentle', seed=SEED, synthesis_rate_hz=INTERNAL_RATE, output_rate_hz=RATE, pcm_bits=24, channels=2,
        sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        design='360ms smooth attack, rounded broad crest, high resonance drifts1180→1060Hz over1.6s and dissolves into a symmetrically expanding wave; no sudden return of low voice or hard reflections.',
        target_rms_dbfs=-34.5, preview_gain_db=0.0, listening_performed=False, game_integration_performed=False,
        first_400ms_rms_rise_db=round(envelope[3]-envelope[0], 2), rms_100ms_timeline_dbfs=envelope,
        measured_tonal_track=frequency_track, previous_twenty_five_sha256=hashes, metrics=measured)
    (DEST / 'activation_gentle_manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in metadata.items() if k in ['first_400ms_rms_rise_db','measured_tonal_track','metrics']},indent=2))


if __name__ == '__main__':
    main()
