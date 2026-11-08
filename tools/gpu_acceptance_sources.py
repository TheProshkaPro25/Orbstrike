#!/usr/bin/env python3
"""Freeze reviewed ordinary-import inputs; rerun explicitly after a new promotion.

This records hashes only. It does not import assets or claim GPU acceptance.
"""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/audits/2026-11-06-gpu-acceptance/accepted-sources.json'
models = []
for key in ['klykar_gale', 'levian_gale', 'kolossar_shadow', 'ratnik_light']:
    source = ROOT / f'assets/creatures_hd/{key}.glb'
    sidecar = Path(str(source) + '.import')
    imports = re.findall(r'"(res://\.godot/imported/[^"\n]+\.scn)"', sidecar.read_text())
    scene = ROOT / imports[0].removeprefix('res://')
    md5_path = scene.with_suffix('.md5')
    source_md5 = hashlib.md5(source.read_bytes()).hexdigest()
    if f'source_md5="{source_md5}"' not in md5_path.read_text():
        raise SystemExit(f'{key}: ordinary import md5 is stale; reimport before freezing acceptance inputs')
    models.append(dict(key=key, source='res://' + source.relative_to(ROOT).as_posix(),
                       sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                       source_md5=source_md5,
                       sidecar_sha256=hashlib.sha256(sidecar.read_bytes()).hexdigest(),
                       import_md5_path='res://' + md5_path.relative_to(ROOT).as_posix(),
                       import_scene='res://' + scene.relative_to(ROOT).as_posix(),
                       import_sha256=hashlib.sha256(scene.read_bytes()).hexdigest(),
                       import_md5=md5_path.read_text()))
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({'scope': 'frozen inputs, not GPU acceptance', 'models': models}, indent=2) + '\n')
print(OUT.relative_to(ROOT))
