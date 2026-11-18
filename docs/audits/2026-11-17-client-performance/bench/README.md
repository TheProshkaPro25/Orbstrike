# Current-client performance audit — 17 November 2026

Reproduce from project root:

```sh
python docs/audits/2026-11-17-client-performance/bench/run.py --list
python docs/audits/2026-11-17-client-performance/bench/run.py
python docs/audits/2026-11-17-client-performance/bench/summarize.py
```

`run.py` reads the normal `tools/check.py` and substitutes only its `optimization`
script path and output root in memory. It does not edit the runner or game code.
The generated normal runner wrapper calls `tools/test_window.gd`: minimized,
unfocusable, offscreen force_draw(false), max_fps=60. Test settings and XDG data
are isolated under this report. The name `optimization` in runner summary labels
this custom sea fixture, not the unrelated normal tooltip optimization test.

`sea_ab.gd` snapshots the existing loading_fps_benchmark setup: real Boot → main →
match startup, preset deck/seed271828, six actual creatures spawned onto the field.
The benchmark then stops input/pumping and fixes the camera. It does not play a
complete physical match. Both overview and the second Harbor flyby endpoint use
FOV52. Only the first ColorRect of IllustratedHarborCanvas (sea plus raymarched
terrain) is hidden for B. Clouds/landmarks remain present, their CPU projection
and positions are frozen identically for A/B. Creature idle, cloth and shader TIME
continue. Camera transforms, render/viewport sizes and counters are in result.json.

One process, Godot4.7.2/Linux, RTX4070Laptop, Vulkan1.4.357/Forward+, HIGH quality,
1920×1080 internal render (window1920×1050), VSync disabled, 60FPS cap. Per camera:
ABBA, 1s warmup then2s measurement per segment,122 measured process/draw frames.
No driver/OS cache flush. Eight fresh PNGs are retained, including negative
controls with the ColorRect hidden. PNG MD5 equals the import .md5 source_md5 for
map.png, proving the currently used texture content matches the latest source.
Hashes of shader, texture, imported texture and fixture are in summary.json.

| Fixed camera | GPU sea on | GPU sea off | Difference | CPU render on/off |
|---|---:|---:|---:|---:|
| Overview |5.286ms|4.755ms|+0.532ms|1.289/1.279ms|
| Low flyby endpoint |4.905ms|4.301ms|+0.604ms|1.178/1.149ms|

Numbers average the two segment means per condition. GPU timings measure the
root viewport draw; they are not whole-system latency or fullscreen player FPS.
Off-segment means vary by about0.5ms. This one short ABBA suggests a measurable
cost in these views but does not establish a current60FPS bottleneck on this GPU,
performance on integrated GPUs,4K, LOW quality, or worst-case angles. Capped FPS
is deliberately not used to claim speedup.

The same run sampled ready main menu after real Boot:21.890307s wall time from
SceneTree._initialize (excludes process/engine initialization before that point),
1 preparation,134 actors,4 arenas,ready=true. Engine static360533524B, renderer
texture3070607360B and buffer792288062B. These are separate resource/accounting
categories, not total RAM/RSS or physical driver VRAM; do not add them to RSS.
RSS was unavailable: FileAccess.get_file_as_string returned empty for procfs's
zero-sized pseudo-file. No optional repeat was run merely to obtain RSS.

Normal runner result:PASS,exit0,65.93s,failures[],no SCRIPT ERROR/ERROR/leaks.
Raw records:runner/presentation/selected-optimization/optimization/{result.json,
frames.csv,*.png}; engine/console logs and summary one directory above.
No Windows run, server test/build, audio listening, export or publication.

## Historical report inventory

- tools/checkpoints/memory-gpu-2026-11-04.json and .md:49×2 actors/3arenas,
  a before/after memory optimization comparison. Valid historical provenance;
  its reported ~101MiB RSS change and older3-arena numbers are not current results.
- build/checks/gameplay/selected-startup-loading/startup-loading/result.json:
  15November report237/0,20.144s,134actors/3arenas. Current fourth-arena Boot
  is measured above; no attribution of growth to one new asset is possible from
  these differently scoped/time-separated snapshots.
- docs/audits/2026-11-08-client-optimization/README.md and selected-optimization:
  old167/0 tooltip/card fixture,34.447ms→1.927ms for500 cached/uncached queries.
  This supports an old narrow CPU workload result, not current gameplay FPS.
- build/checks/cloth-sharing-comparison.json:4November fixed-pose cloth pair,
  pixel equality and2777564B shared readonly storage. Not a new gameplay run.
- build/checks/loading-fps-comparison/comparison.json:older paths/49×2/3arenas,
  explicitly fps_limit0. Kept as historical data; not rerun under current60FPS rule.
- selected-illustrated-harbor/summary.json:17November54.17s is the full36/0
  integration scenario, not Boot time. Its original PNGs precede the latest shader
  changes. Fresh on/off PNGs in this report use the current shader/texture.

Current memory-catalog expectation arena_build_count==3 is stale after fourth
arena; startup-loading preview loops cover only indexes0..2. Neither was used as
current acceptance in this audit. No game/test code changed for this audit.
