"""CPU raw-rest evidence for the single Gale Levian wind candidate.

This is not Godot/GPU evidence. No production files are changed.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import audit_20261106 as raw
from inspect_geometry import accessor, read_glb
from remove_grifalon_gale_wind import components


def locate(source):
    doc, binary = read_glb(source)
    prim = doc['meshes'][0]['primitives'][0]
    v = accessor(doc, binary, prim['attributes']['POSITION'])
    faces = accessor(doc, binary, prim['indices']).reshape(-1, 3)
    welded, inverse = np.unique(np.round(v, 6), axis=0, return_inverse=True)
    labels = components(inverse[faces], len(welded))[inverse[faces[:, 0]]]
    keys, counts = np.unique(labels, return_counts=True)
    assert sorted(counts.tolist()) == [2538, 141826], 'Unexpected source components'
    selected = np.flatnonzero(labels == keys[np.flatnonzero(counts == 2538)[0]])
    return doc, binary, prim, v, faces, selected


def normalization_bounds(primitives):
    all_points = np.concatenate([p[0] for p in primitives])
    active_points = np.concatenate([p[0][np.unique(p[3])] for p in primitives])
    root = Path(__file__).resolve().parents[2]
    arena = (root / 'scenes/arena.gd').read_text()
    world = float(re.search(r'const WORLD := ([0-9.]+)', arena).group(1))
    card = float(re.search(r'const CARD_SCALE := ([0-9.]+)', arena).group(1))
    unit = world * card
    fig_h, fig_w = 3.5*unit, 2.5*unit

    def values(points):
        low, high = points.min(0), points.max(0)
        size = high - low
        sx,sy,sz = np.maximum(size,.01)
        k = min(max(fig_h/3/sz, .85*fig_h/sy), min(fig_h/3*1.75/sz, fig_w*1.3/sx, fig_h/sy))
        offset = np.array([-(low[0]+size[0]*.5)*k,-low[1]*k,-(low[2]+size[2]*.5)*k])
        return {'bbox_min':low.tolist(), 'bbox_max':high.tolist(), 'bbox_size':size.tolist(),
                'build_scale':float(k), 'build_position':offset.tolist()}

    return {'all_accessor_positions': values(all_points), 'referenced_triangle_positions': values(active_points),
            'formula': 'CreatureModels.build/_bounds: transformed raw-rest nodes; FIG_H=3.5*WORLD*CARD_SCALE, FIG_W=2.5*WORLD*CARD_SCALE',
            'arena_source_sha256':hashlib.sha256((root/'scenes/arena.gd').read_bytes()).hexdigest(),
            'models_source_sha256':hashlib.sha256((root/'scenes/creature_models.gd').read_bytes()).hexdigest()}


def evidence(source, output, candidate=None):
    output.mkdir(parents=True, exist_ok=True)
    doc, binary, prim, v, faces, selected = locate(source)
    verts = np.unique(faces[selected])
    base = raw.read_glb(source)
    positions, normals, uv, triangles, texture, factor = base[0]
    retained = np.ones(len(triangles), dtype=bool)
    retained[selected] = False
    marked = [(positions, normals, uv, triangles[retained], texture, factor),
              (positions, normals, uv, triangles[selected], None, np.array([1.34, .08, 1.20])), *base[1:]]
    isolated = [(positions, normals, uv, triangles[selected], None, np.array([1.34, .08, 1.20]))]
    rows = [('source', base), ('mask_magenta', marked), ('isolated_component', isolated)]
    if candidate is not None:
        rows.append(('candidate', raw.read_glb(candidate)))
    raw.SIZE = 512
    views = [('front', .35), ('right', math.pi/2), ('rear', math.pi+.35), ('left', -math.pi/2)]
    sheet = Image.new('RGB', (512*4, 64 + len(rows)*546), '#111821')
    draw = ImageDraw.Draw(sheet)
    draw.text((12, 10), 'A02 GALE LEVIAN | CPU RAW REST | same source coordinate frame | NOT GODOT / GPU', fill='white')
    draw.text((12, 30), 'Magenta = selected connected component (2538 triangles). No positions, UV, weights or animation changed.', fill='#b8c4d4')
    for row, (label, primitives) in enumerate(rows):
        for column, (view, angle) in enumerate(views):
            image = raw.render(primitives, angle)
            image.save(output / f'{label}-{view}.png')
            x, y = column*512, 64+row*546
            sheet.paste(image, (x,y))
            draw.text((x+8,y+518), f'{label} / {view}', fill='white')
    sheet.save(output / ('before-after-mask.png' if candidate else 'component-localization.png'))
    repair = doc['meshes'][0]['primitives'][1]
    repair_faces = accessor(doc, binary, repair['indices']).reshape(-1, 3)
    selected_weld = set(map(tuple, np.round(v[verts], 6)))
    repair_v = accessor(doc, binary, repair['attributes']['POSITION'])
    repair_weld = set(map(tuple, np.round(repair_v[np.unique(repair_faces)], 6)))
    body_v = v[np.unique(faces[retained])]
    result = {
        'kind': 'CPU raw-rest localization, not runtime/GPU acceptance',
        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'selected_triangles': len(selected), 'retained_main_triangles': int(retained.sum()),
        'repair_surface_triangles_unchanged': len(repair_faces),
        'selected_source_face_ids': selected.tolist(),
        'selected_source_vertex_ids': verts.tolist(),
        'selected_bbox': [v[verts].min(0).tolist(), v[verts].max(0).tolist()],
        'retained_main_bbox': [body_v.min(0).tolist(), body_v.max(0).tolist()],
        'selected_welded_points_shared_with_tail_repair': len(selected_weld & repair_weld),
        'candidate_sha256': hashlib.sha256(candidate.read_bytes()).hexdigest() if candidate else None,
    }
    if candidate is not None:
        source_norm = normalization_bounds(base)
        candidate_norm = normalization_bounds(rows[-1][1])
        assert source_norm == candidate_norm, 'Unexpected bounds/normalization change'
        result['normalization'] = {'source':source_norm,'candidate':candidate_norm,
                                   'scale_delta':0.0,'position_delta':[0.0,0.0,0.0],
                                   'scope':'CPU mirror of current build formula. Both all stored points and active triangles give identical bounds. Godot import not executed.'}
    (output / 'localization.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if not k.endswith('_ids')}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    evidence(args.source, args.output, args.candidate)
