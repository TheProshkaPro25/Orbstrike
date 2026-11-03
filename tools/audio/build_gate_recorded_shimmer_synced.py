"""Pitch-preserving4/3 temporal compression of the CC0-recorded shimmer preview.

Targets the actual1.8-second floor wave, not the0.68-second card growth.
Requires ffmpeg with librubberband and NumPy. No game integration.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import subprocess
import wave
import numpy as np
from build_gate_candidates import smoothstep
from build_gate_light_front_clean import pcm24_pack, pcm24_unpack, report

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT/'assets/audio/candidates/gate_wave'
SOURCE = DEST/'gate_wave_recorded_shimmer.wav'
OUTPUT = DEST/'gate_wave_recorded_shimmer_synced.wav'
RATE, TARGET_SECONDS, TEMPO = 48000, 1.8, 4/3
FILTER = ('rubberband=tempo=1.3333333333333333:pitch=1:transients=smooth:'
          'detector=soft:phase=laminar:channels=together')


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x*x)))


def compress() -> tuple[np.ndarray, float, int]:
    result = subprocess.run(['ffmpeg','-v','error','-i',str(SOURCE),'-af',FILTER,
                             '-ar',str(RATE),'-ac','2','-f','f64le','pipe:1'],
                            check=True,stdout=subprocess.PIPE)
    transformed = np.frombuffer(result.stdout,'<f8').reshape(-1,2).copy()
    frames_returned = len(transformed)
    frames = round(TARGET_SECONDS*RATE)
    x = np.zeros((frames,2))
    count = min(frames,len(transformed))
    x[:count] = transformed[:count]
    t = np.arange(frames)/RATE
    # Edge polishing only: preserve the compressed240ms source attack.
    edge = smoothstep(t/.018)*smoothstep((TARGET_SECONDS-t)/.075)
    x *= edge[:,None]
    x -= x.mean(axis=0,keepdims=True)*edge[:,None]/edge.mean()
    gain = 10**(-28/20)/rms(x)
    x *= gain
    x[[0,-1]]=0
    assert np.max(np.abs(x))<10**(-8/20)
    return x, float(20*np.log10(gain)), frames_returned


def main() -> None:
    old = sorted(p for p in DEST.glob('*.wav') if p != OUTPUT)
    assert len(old)==28
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in old}
    source_metadata=json.loads((DEST/'recorded_shimmer_manifest.json').read_text())
    x,gain_db,raw_frames=compress()
    packed=pcm24_pack(x)
    assert packed==pcm24_pack(compress()[0])
    with wave.open(str(OUTPUT),'wb') as w:
        w.setparams((2,3,RATE,0,'NONE','not compressed'));w.writeframes(packed)
    with wave.open(str(OUTPUT),'rb') as w:
        assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes())==(2,3,RATE,86400)
        actual=pcm24_unpack(w.readframes(w.getnframes()))
    measured=report(actual,RATE)
    assert abs(measured['rms_dbfs']+28)<.002
    assert measured['clipped_samples']==0 and measured['peak_dbfs'] < -8
    assert measured['dc_offset_max']<1e-7 and not actual[[0,-1]].any()
    assert measured['mono_loss_db']> -1
    assert hashes=={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in old}
    metadata=dict(name='Записанное сияние — под волну1,8с',path=OUTPUT.relative_to(ROOT).as_posix(),
        generator='tools/audio/build_gate_recorded_shimmer_synced.py',sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        source_preview=SOURCE.relative_to(ROOT).as_posix(),source_preview_sha256=hashes[SOURCE.name],
        original_source=source_metadata['source'],
        processing=dict(ffmpeg_filter=FILTER,tempo_ratio=TEMPO,pitch_ratio=1.0,
            source_seconds=2.4,target_seconds=TARGET_SECONDS,source_attack_seconds=.32,
            expected_compressed_attack_seconds=.24,normalisation_gain_db=round(gain_db,4),
            rubberband_output_frames=raw_frames,output_frames=86400,edge_polish_seconds=[.018,.075],
            hard_limiter_used=False),
        timing_reference=dict(wave_source='scenes/arena.gd:182',wave_duration_parameter='scenes/arena.gd:190',
            wave_duration_seconds=1.8,wave_radius='t*155',wave_strength='(1-t)*strength',
            trigger_source='scenes/presentation/arena_director.gd:316',
            sound_call_source='scenes/presentation/arena_director.gd:317',
            relative_start='Same call sequence as element_wave, after landed and game._wait(0.10); simultaneous with card growth.',
            card_growth_seconds=.68,card_growth_constant='scenes/presentation/arena_director.gd:250',
            phase='Floor radial wave, not the card flight or the card-growth duration'),
        pcm_bits=24,sample_rate_hz=RATE,channels=2,preview_gain_db=0,
        listening_performed=False,game_integration_performed=False,
        previous_twenty_eight_sha256=hashes,metrics=measured)
    (DEST/'recorded_shimmer_synced_manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(metrics=measured,processing=metadata['processing']),indent=2))


if __name__=='__main__':
    main()
