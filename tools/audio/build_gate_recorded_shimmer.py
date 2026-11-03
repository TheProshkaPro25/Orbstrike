"""Adapt a public CC0 processed-cymbal recording into one gentle energy wave.

Requires Python, NumPy and ffmpeg. Source is kept outside imported game assets.
Obtain the public HQ preview from the URL in the manifest, then run:
python tools/audio/build_gate_recorded_shimmer.py --source /path/to/826131-hq.mp3
No sine oscillators or generated noise are added.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import wave
import numpy as np
from build_gate_candidates import smoothstep
from build_gate_light_front_clean import pcm24_pack, pcm24_unpack, report

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'assets/audio/candidates/gate_wave'
OUTPUT = DEST / 'gate_wave_recorded_shimmer.wav'
RATE, DURATION = 48000, 2.4
SOURCE_URL = 'https://freesound.org/people/Vrymaa/sounds/826131/'
PREVIEW_URL = 'https://cdn.freesound.org/previews/826/826131_13973196-hq.mp3'
START_SECONDS, SPEED = 27.1, 1.025


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)))


def soften(x: np.ndarray, cutoff: float) -> np.ndarray:
    size = 1 << (len(x) + RATE - 1).bit_length()
    frequency = np.fft.rfftfreq(size, 1 / RATE)
    shape = (1 - np.exp(-(frequency / 340) ** 4)) * np.exp(-(frequency / cutoff) ** 6)
    return np.fft.irfft(np.fft.rfft(x, n=size) * shape, n=size)[:len(x)]


def make(source: np.ndarray) -> np.ndarray:
    n = round(DURATION * RATE)
    t = np.arange(n) / RATE
    # A sustained recorded body after the source's impact; slight continuous
    # varispeed keeps its real inharmonic complexity rather than replacing it.
    positions = START_SECONDS * RATE + np.arange(n) * SPEED
    original_index = np.arange(len(source))
    mid_source = np.interp(positions, original_index, source)
    side_source = np.interp(positions + .137 * RATE, original_index, source)
    distance = smoothstep((t - .38) / 1.64)
    near = soften(mid_source, 6500)
    far = soften(mid_source, 4000)
    mid = near * (1 - distance) + far * distance
    side = soften(side_source, 4300)
    side *= rms(mid) / rms(side)
    width = .015 + .44 * smoothstep((t - .18) / 1.30)
    stereo = np.column_stack([mid + width * side, mid - width * side])
    envelope = smoothstep(t / .32)
    envelope *= (1 - smoothstep(np.clip((t - .66) / 1.69, 0, 1))) ** 1.18
    envelope *= smoothstep((DURATION - t) / .16)
    stereo *= envelope[:, None]
    stereo -= stereo.mean(axis=0, keepdims=True) * envelope[:, None] / envelope.mean()
    stereo *= 10 ** (-28 / 20) / rms(stereo)
    stereo[[0,-1]] = 0
    assert np.max(np.abs(stereo)) < 10 ** (-8 / 20)
    return stereo


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    source_bytes = args.source.read_bytes()
    decoded = subprocess.run(['ffmpeg','-v','error','-i',str(args.source),'-ac','1','-ar',str(RATE),'-f','f32le','pipe:1'],check=True,stdout=subprocess.PIPE).stdout
    source = np.frombuffer(decoded, '<f4').astype(float)
    assert len(source) > round(30 * RATE)
    old = sorted(p for p in DEST.glob('*.wav') if p != OUTPUT)
    assert len(old) == 27
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in old}
    packed = pcm24_pack(make(source))
    assert packed == pcm24_pack(make(source))
    with wave.open(str(OUTPUT), 'wb') as w:
        w.setparams((2,3,RATE,0,'NONE','not compressed'));w.writeframes(packed)
    with wave.open(str(OUTPUT), 'rb') as w:
        assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes()) == (2,3,RATE,115200)
        actual = pcm24_unpack(w.readframes(w.getnframes()))
    measured = report(actual, RATE)
    assert measured['clipped_samples'] == 0 and measured['peak_dbfs'] < -8
    assert abs(measured['rms_dbfs'] + 28) < .002
    assert measured['dc_offset_max'] < 1e-7 and not actual[[0,-1]].any()
    assert measured['mono_loss_db'] > -1
    assert measured['early_channel_correlation'] > .97
    assert measured['distant_channel_correlation'] < .90
    assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in old}
    metadata = dict(name='Расходящееся сияние — записанная фактура',path=OUTPUT.relative_to(ROOT).as_posix(),
        generator='tools/audio/build_gate_recorded_shimmer.py',sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        source=dict(title='Magic - Cymbal Swell 2',author='Vrymaa',page_url=SOURCE_URL,public_hq_preview_url=PREVIEW_URL,
            license='CC0 1.0 Universal',license_url='https://creativecommons.org/publicdomain/zero/1.0/',
            license_verified='2026-11-03; author page explicitly permits copy, modification and distribution including commercial use',
            origin='Author describes a luminous magical wave created by processing recorded larger cymbals',
            sha256=hashlib.sha256(source_bytes).hexdigest(),acquired_file_bytes=len(source_bytes),
            acquired_format='Public HQ preview MP3, VBR approximately180kbps,44.1kHz mono; not original lossless WAV',
            used_range_seconds=[START_SECONDS,round(START_SECONDS+DURATION*SPEED+.137,4)],
            source_stored_in_game_assets=False),
        processing=dict(method='Recorded inharmonic body; no generated tones/noise',varispeed_ratio=SPEED,
            removed_source_impact=True,highpass_hz=340,lowpass_near_hz=6500,lowpass_distant_hz=4000,
            attack_seconds=.32,stereo='Coherent mono body with symmetric widening from another recorded offset; mono sums to the body',
            normalised_rms_dbfs=-28,hard_limiter_used=False),
        pcm_bits=24,sample_rate_hz=RATE,channels=2,preview_gain_db=0,
        listening_performed=False,game_integration_performed=False,
        quality_note='Different recorded-source approach for user audition; technical checks do not establish subjective quality.',
        previous_twenty_seven_sha256=hashes,metrics=measured)
    (DEST/'recorded_shimmer_manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(measured,indent=2))


if __name__ == '__main__':
    main()
