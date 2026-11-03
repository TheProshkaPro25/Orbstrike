"""Descending tonal energy only: no wind, noise, crackle or distortion."""
from pathlib import Path
import numpy as np
import wave
sr=48000
duration=1.65
n=round(sr*duration)
t=np.arange(n)/sr
out=Path(__file__).resolve().parents[2]/"assets/audio/sfx"
def osc(freq):return np.sin(2*np.pi*np.cumsum(freq)/sr)
def decay(tau,attack=.002):return (1-np.exp(-t/attack))*np.exp(-t/tau)
for name,tau in [('gate_expand_wave',.70)]:
 sweep=.22+.66*np.exp(-t/tau)
 partials=np.zeros(n)
 for freq,gain in [(1350,.30),(2190,.23),(3280,.17),(4730,.10),(6110,.055)]:
  partials+=gain*osc(freq*sweep)
 # All layers descend from the onset; no broadband noise is mixed.
 x=.54*partials*decay(.55)
 x+=.17*osc(2850*sweep)*decay(.36,.012)
 x+=.16*osc(62+115*np.exp(-t/.035))*decay(.09)
 x=1.15*x
 stereo=np.column_stack([x.copy(),x.copy()])
 for seconds,gain in [(.023,.12),(.053,.08),(.091,.045),(.157,.022)]:
  for ch,offset in [(0,0),(1,.0037)]:
   d=round((seconds+offset)*sr);stereo[d:,ch]+=gain*x[:-d]
 stereo*=np.minimum(1,t/.001)[:,None]*np.clip((duration-t)/.18,0,1)[:,None]
 stereo-=stereo.mean(axis=0)
 stereo*=.80/np.abs(stereo).max()
 pcm=np.rint(stereo*32767).astype('<i2')
 with wave.open(str(out/(name+'.wav')),'wb') as w:
  w.setparams((2,2,sr,0,'NONE','not compressed'));w.writeframes(pcm.tobytes())
 centroids=[]
 for start,end in [(.03,.15),(.35,.50),(.75,.95)]:
  s=stereo[int(start*sr):int(end*sr)].mean(axis=1)
  spectrum=np.abs(np.fft.rfft(s*np.hanning(len(s))))**2
  freq=np.fft.rfftfreq(len(s),1/sr)
  centroids.append(round(float((freq*spectrum).sum()/spectrum.sum())))
 assert centroids[0]>centroids[1]>centroids[2],centroids
 print(name,'spectral centroid Hz:',centroids,'peak',round(float(np.abs(stereo).max()),2))
