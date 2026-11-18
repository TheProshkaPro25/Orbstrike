# Resource/texture audit — 18 November 2026

Only the client was investigated. No production sources, models, imported assets,
user settings or journals were edited by this subtask. Evidence lives in this
ignored build directory. No server, Windows build, listening test or publication.
The catalog contract is preserved: **67 definitions × 2 actors = 134**, with four
arenas and four prepared fighters in the current source run. Catalog residency
is an explicit author requirement; removing it is not proposed as a fix.

## Fresh runtime evidence

One real `scenes/loading/boot.tscn` → main-menu process, Godot 4.7.2
`ed1daf0bf`, Linux/X11 Vulkan Forward+, RTX 4070 Laptop, default 1280×720,
isolated settings `[graphics] level=2/max_fps=60` (HIGH), existing
`tools/test_window.gd` minimized/unfocusable/offscreen wrapper. No match or new
scene/arena was entered after the normal Boot. `StartupCatalog` held 225 roots;
Boot created 134 actors, 4 arenas, 4 fighters, exactly once.

| Measure | Before Boot, first frame | Menu, eight settled frames | Menu, another second |
|---|---:|---:|---:|
| RenderingServer / Performance texture bytes | 7,521,280 | 2,824,876,544 | 2,824,876,544 |
| buffer bytes | 1,934,476 | 807,346,402 | 807,346,402 |
| video bytes | 12,605,824 | 3,806,295,728 | 3,806,295,728 |
| Linux process VmRSS, KiB | 728,048 | 2,505,388 | 2,507,448 |
| OS static allocation bytes | 65,254,536 | 401,977,020 | 401,988,120 |

Menu texture counter **2.631 GiB**, buffer **0.752 GiB**, video **3.545 GiB**;
process RSS **2.389–2.391 GiB**. These categories overlap; do not add them.
Video is not simply texture+buffer. No device/driver residency was measured.
Boot-to-menu elapsed 32.279 s in this instrumented, cold-process run, not an
A/B optimization result. Metadata snapshot capture cost 3.3–6.7 ms, resource
owner traversal afterward 858 ms. No GPU pixel/image readback was performed.

Raw evidence:

- `runtime-checks/models/selected-memory-catalog/memory-catalog/runtime.json`
- `runtime-memory/memory.json` and `packets.bin`: three memory replies;
  the **two menu replies have exactly equal row arrays**.
- `runtime-checks/models/selected-memory-catalog/memory-catalog.log` and
  `summary.json`: engine exit 0 but runner **FAIL**, 42.92 s. This is not a clean
  PASS. The immediate fixture `quit()` omitted the established orderly teardown.
  First errors are AFTER `DONE snapshot` (line 239), at log line 252+: late
  materials/textures/shaders and queued cloth cleanup reach renderer shutdown.
  `low_load_benchmark.gd:119–124` / `match_bottleneck_benchmark.gd:232–239`
  first free current scene, wait 3 frames, free loader, wait 3, free SoundFx,
  wait 3. The fixture now uses that order; **the correction has not been run**.
  The executed immediate-quit form is preserved as
  `runtime_snapshot_executed.gd`. This run does not prove a normal client exit bug.
- One unrelated `performance:profile_names` typed-array packet was unsupported
  by the existing decoder (484 bytes). All three `servers:memory_usage` replies
  passed explicit framing/length validation. The decode warning is preserved.

## What the debugger list means

`RenderingServer.texture_debug_usage()` is not exposed to GDScript in this
engine (see `api-probe.log`). The standard loopback debugger `servers:memory`
request was used, without enabling a CPU/script/visual profiler. Its engine
implementation emits path, format, type, bytes for each RS texture or mesh.
**It does not serialize RID**, although it assigns one internally: equal path
rows must not be merged as duplicates. Empty labels stay separate rows.

The texture byte field is a logical Image payload estimate per registered
RS texture, not exact padded RD allocation or driver residency. Internal render
targets, raw RD textures/buffers and other renderer memory are not fully covered.
Mesh bytes sum the engine's six mesh buffer fields and also do not cover all RD
buffers. Therefore neither list is expected to reconcile to the Performance
counters. Sources:
[debugger serialization and query](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/debugger/servers_debugger.cpp#L42-L52),
[resource enumeration](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/debugger/servers_debugger.cpp#L403-L463),
[texture logical-byte calculation](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/renderer_rd/storage_rd/texture_storage.cpp#L1964-L1994).

Settled debugger inventory: **1,606 rows**, 2,605,878,027 logical bytes:
738 textures = **2,059,295,877 B (1.918 GiB)**;
868 meshes = **546,582,150 B (521.261 MiB)**.
508 texture rows are unlabelled: **1,268,970,330 B (1,210.184 MiB)**.
This is an attribution boundary, not permission to call all blank rows avatars.

| Texture group definitely present in menu | Logical payload | Current imported format |
|---|---:|---|
| Repaired Rogozhuk Stone atlas, 1 map | 85.333 MiB | 4096² RGBA8, 12 extra mip levels |
| Floris, 6 maps | 96.000 MiB | 2048² RGB8, 11 extra mips |
| Armat, 6 maps | 96.000 MiB | 2048² RGB8, 11 extra mips |
| Octo, 6 maps | 24.000 MiB | 1024² RGB8, 10 extra mips |
| Creature portraits, 67 maps | 89.333 MiB | 512² RGBA8, 9 extra mips |
| Modular bob diffuse, 1 labelled map | 21.333 MiB | 2048² RGBA8, 11 extra mips |
| Editor catalogs, 2 maps | 5.859 MiB | 800×960 RGBA8, no mips |
| Old illustrated-harbor PNG group | no labelled rows | no live residency claim |

The four modular hair diffuse imports exist, 85.333 MiB total potential,
but the debugger labelled only bob. Do not claim all four were independently
proven live by debugger labels. RGB8 can require a different GPU storage format;
logical RGB8 size does not settle its actual RD padding.

## Active imports versus files merely on disk

`inventory.py` reads current `.import` remaps and the active GST2/CTEX headers,
including actual width, height, Image format and mip count. Four representative
headers were verified against headless Godot `Texture2D.get_image()` metadata
(`probe.json`): raw RGBA8, mipmapped portrait RGBA8, RGTC_RG and BPTC_RGBA.

Formula per Image: sum base plus every stored mip; raw = w×h×bytes/pixel,
BC = ceil(w/4)×ceil(h/4)×8 or ×16 bytes. Dimensions halve toward 1 each mip.
This is **Image payload**, excluding API/driver allocation overhead. It is not
PNG source disk size or RSS. All active imports loaded once is a hypothetical
scope, not Boot reachability. Embedded textures in `.res/.scn` are excluded here.

344 active remaps across assets/scenes/art: **1,366.493 MiB** payload;
164 compressed maps **684.087 MiB**, 180 uncompressed maps **682.406 MiB**.
The script refuses to silently aggregate multiple backend variants per source.
The filesystem currently has 612 CTEX files / 1,782.178 MiB; 268 / 1,008.430 MiB
are not named by these roots' active sidecars. They are disk/import-cache
candidates only, not 1 GiB of observed resident waste or automatically deletable.

`export_presets.cfg` uses `all_resources`. Its explicit excludes remove
comparison/reference subsets, while art reconstruction folders contain
`.gdignore` and no active CTEX sidecars were found under art. Export filtering,
import cache size and runtime residency are separate questions. Huge source
GLBs/VRMs do not imply that many GPU bytes. An excluded or unreferenced PNG
must not be blamed for menu memory. `StartupCatalog._collect` scans scenes,
fonts, editor and portraits, adds creature model paths/wardrobe additions and
retains strong resource references in `GameLoading.resources` before the menu.
ResourceLoader caches repeated same-path loads; the two actors do not imply two
copies of each source texture. Distinct embedded ImageTexture resources do.

## Embedded avatar textures and exact duplicate candidates

`addons/vrm/import_vrm.gd` explicitly requests
`GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED`. The headless graph walk loaded
all 68 available avatar `.vrm/.res` roots once, held refs, and counted each
Texture2D object once: **385 textures / 1,295.050 MiB Image payload**.
Exact pixel-data SHA-256 + Image format + dimensions + mip count yield
**428.043 MiB repeated payload beyond 867.006 MiB unique contents**.
This is an upper amount of repeated Image data in the examined available
asset graph, not guaranteed savings in the current GPU process.

A separate no-readback walk of `GameLoading.resources` found 395 texture RIDs.
259 resource paths cross-match the headless avatar graph:
**977.179 MiB payload, 246.760 MiB repeated content**. This confirms strong
resource reachability for that subset; because the wire omits RIDs and most
ImageTexture renderer labels are blank, it cannot map all blank debugger rows
or promise a matching Performance-counter reduction.

Three specific sets, checked by `roles_probe.gd` in seven source roots:

| Set | Objects / Image data | Repeated payload | Material property |
|---|---:|---:|---|
| Sakurada skin color in base + deer_haori/fantasy_robe/orchid_armor/orchid_uniform | 5 × 16 MiB | 64 MiB | `_MainTex` + `_ShadeTexture` |
| Same five roots' skin normal | 5 × 16 MiB | 64 MiB | `_BumpMap` |
| Vita and Vivi skin normal | 2 × 16 MiB | 16 MiB | `_BumpMap` |

All are 2048² RGBA8, zero extra mips and exact hashes match within each set.
The relevant shader uses identical per-role sampler declarations (color slots
`source_color`, normal `hint_normal`); normal must remain distinct from color.
Material scalars/colors/UV transforms and materials themselves must stay per
outfit. `roles.json` contains the material/property/path edges. Sampler state is
shader/material-side; no promise of global equivalence across unexamined shaders.

## Concrete next changes, without removing the catalog

1. **Share only exact avatar texture sets during preparation**, retaining
   canonical shared textures while keeping outfit materials/geometry separate.
   Address the two 5×16 MiB sets first. Preparation/generator changes should use
   shared external texture resources or a canonical startup registry, keyed by
   bytes + format/mips + semantic role, without cloning ImageTexture into each
   generated `.res`. This is not a global importer replacement and needs a fresh
   same-scope memory comparison before any savings claim. Originals and derived
   materials both retain refs today, so merely changing one generated file will
   not automatically reach the full upper saving.
2. **Target specific uncompressed albedo imports**, after visual A/B approval:
   repaired 4096 atlas and Floris/Armat/Octo color maps. At unchanged resolution,
   BC7/BPTC payload would be 21.333 MiB for the atlas (64 MiB logical reduction),
   64 MiB for the twelve Floris/Armat maps (128 MiB reduction), 8 MiB for Octo
   (16 MiB reduction). These are formulas, not measured savings. Preserve alpha,
   accepted materials, UV/rest/bind/skeleton and all model meshes. Existing older
   maps already use BPTC/DXT1/RGTC; do not blanket-recompress everything.
3. **Portrait payload**: 67 pre-rendered mipmapped 512² maps cost 89.333 MiB.
   An unchanged-resolution BC7 experiment would be 22.335 MiB logical payload;
   requires edge/alpha/text UI visual checks. The old runtime matte helper has
   no current caller in the portrait preload path; do not blame its image copies
   for this run without a real call path.
4. **Disk/package hygiene**: review stale imported files and obsolete experiments
   via normal clean import/export manifest audit. This may reduce workspace or
   package size; it is not a demonstrated menu VRAM or FPS fix. No source asset
   was removed or changed here.
5. **Preserve the Boot contract**: shared meshes/texture payloads and canonical
   cloth buffers can improve memory while 134 actors remain prebuilt and six
   match actors are leased. Source texture sharing does not eliminate per-actor
   skinning/cloth/output buffers. The separate render/grid audit covers those.

## Recompute, scope and artifacts

Static: `python build/audit-resource-path-20261118/inventory.py` and
`python build/audit-resource-path-20261118/analyze.py`.
Headless probes are `texture_probe.gd`, `embedded_probe.gd`, `roles_probe.gd`;
all ran with `--headless --max-fps 60`, no Boot except the one actual GPU test.
The first metadata probe emitted sandbox user-log errors while still returning
all four facts; subsequent probes use isolated XDG dirs/absolute log paths and
were clean. Earlier parser diagnostics are retained, not passing tests.
The single GPU run used `launch_snapshot.py` → isolated `check_snapshot.py`
(derived from existing `tools/check.py`, only ROOT/BASE_OUT/script/debug port
changed), external `memory_collector.py`, TCP 127.0.0.1 only. Both menu readings
were taken in that same process. No rerun was made for a green teardown status.
Current cleanup template differs from the executed immediate-quit version as
explicitly described above. No test or real client remains running.

`analysis.json` holds recomputable group totals and duplicate-set paths/hashes;
`inventory.json` has all active import rows; `embedded.json` has all headless
texture metadata/hashes. This is a resource diagnosis, not a full GPU memory
accounting, performance acceptance or proof of Windows behavior.
