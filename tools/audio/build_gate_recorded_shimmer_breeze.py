"""Add one quiet local breeze tail to the selected1.8s recorded-wave preview.

Preserves all source samples before1.25s; does not renormalise the main effect.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import wave
import numpy as np
from build_gate_candidates import noise_band, smoothstep
from build_gate_light_front_clean import pcm24_pack, pcm24_unpack, report

ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'assets/audio/candidates/gate_wave'
SOURCE=DEST/'gate_wave_recorded_shimmer_synced.wav'
OUTPUT=DEST/'gate_wave_recorded_shimmer_synced_breeze.wav'
RATE,DURATION,SEED=48000,1.8,73601
START,CREST,END=1.25,1.48,1.8
BREEZE_TO_BODY_DB=-18.0


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x*x)))


def add_breeze(source: np.ndarray) -> tuple[np.ndarray,dict]:
    n=len(source);t=np.arange(n)/RATE;rng=np.random.default_rng(SEED)
    low=noise_band(n,rng,460,.75)
    upper=noise_band(n,rng,1300,.62)
    diffuse=noise_band(n,rng,740,.77)
    darken=smoothstep((t-START)/(END-START))
    mid=.78*low+.22*(1-.65*darken)*upper
    breeze=np.column_stack([mid+.10*diffuse,mid-.10*diffuse])
    envelope=smoothstep((t-START)/(CREST-START))
    envelope*=1-smoothstep((t-CREST)/(END-CREST))
    breeze*=envelope[:,None]
    # Correct DC only within the tail, preserving the approved earlier waveform.
    breeze-=breeze.mean(axis=0,keepdims=True)*envelope[:,None]/envelope.mean()
    body_rms=rms(source[round(.20*RATE):round(.90*RATE)])
    tail_slice=slice(round(START*RATE),n)
    target_rms=body_rms*10**(BREEZE_TO_BODY_DB/20)
    breeze*=target_rms/rms(breeze[tail_slice])
    breeze[[0,-1]]=0
    combined=source+breeze
    combined[[0,-1]]=0
    assert np.array_equal(source[:round(START*RATE)],combined[:round(START*RATE)])
    return combined,dict(start_seconds=START,crest_seconds=CREST,end_seconds=END,
        body_reference_seconds=[.20,.90],body_reference_rms_dbfs=round(20*np.log10(body_rms),3),
        breeze_active_rms_dbfs=round(20*np.log10(rms(breeze[tail_slice])),3),
        breeze_to_body_db=BREEZE_TO_BODY_DB,master_gain_change_db=0,
        normalised_after_addition=False)


def main() -> None:
    previous=sorted(p for p in DEST.glob('*.wav') if p!=OUTPUT)
    assert len(previous)==29
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    provenance=json.loads((DEST/'recorded_shimmer_synced_manifest.json').read_text())
    with wave.open(str(SOURCE),'rb') as w:
        assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes())==(2,3,RATE,86400)
        source=pcm24_unpack(w.readframes(w.getnframes()))
    combined,layer=add_breeze(source)
    packed=pcm24_pack(combined)
    assert packed==pcm24_pack(add_breeze(source)[0])
    with wave.open(str(OUTPUT),'wb') as w:
        w.setparams((2,3,RATE,0,'NONE','not compressed'));w.writeframes(packed)
    with wave.open(str(OUTPUT),'rb') as w:
        assert w.getnframes()==86400
        actual=pcm24_unpack(w.readframes(w.getnframes()))
    assert np.array_equal(actual[:round(START*RATE)],source[:round(START*RATE)])
    measured,original=report(actual,RATE),report(source,RATE)
    assert measured['clipped_samples']==0 and measured['peak_dbfs']<-8
    assert abs(measured['rms_dbfs']-original['rms_dbfs'])<.10
    assert measured['dc_offset_max']<1e-7 and not actual[[0,-1]].any()
    assert measured['mono_loss_db']> -1
    assert hashes=={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in previous}
    metadata=dict(name='Записанное сияние — лёгкий ветерок в конце',path=OUTPUT.relative_to(ROOT).as_posix(),
        generator='tools/audio/build_gate_recorded_shimmer_breeze.py',sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        source_preview=SOURCE.relative_to(ROOT).as_posix(),source_preview_sha256=hashes[SOURCE.name],
        original_source=provenance['original_source'],timing_reference=provenance['timing_reference'],
        breeze_layer=dict(source='Original seeded filtered-noise synthesis',seed=SEED,**layer),
        pcm_bits=24,sample_rate_hz=RATE,channels=2,preview_gain_db=0,
        listening_performed=False,game_integration_performed=False,
        first_1250ms_bit_identical=True,previous_twenty_nine_sha256=hashes,
        original_metrics=original,metrics=measured)
    (DEST/'recorded_shimmer_breeze_manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(breeze_layer=layer,metrics=measured),indent=2))


if __name__=='__main__':
    main()
