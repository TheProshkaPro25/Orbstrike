"""A01 CPU raw-rest component masks; never a Godot/GPU acceptance."""
import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import audit_20261106 as raw
from inspect_geometry import accessor, read_glb
from remove_grifalon_gale_wind import boundary_edges, components

BASE_SHA = 'f16e61d615e7897ed513d3abb73aa941cb335827d7f43c07961fd8e277ab4c28'


def locate(source):
    assert hashlib.sha256(source.read_bytes()).hexdigest() == BASE_SHA
    doc, binary = read_glb(source)
    prim = doc['meshes'][0]['primitives'][0]
    v = accessor(doc, binary, prim['attributes']['POSITION'])
    faces = accessor(doc, binary, prim['indices']).reshape(-1, 3)
    welded, inv = np.unique(np.round(v, 6), axis=0, return_inverse=True)
    labels = components(inv[faces], len(welded))[inv[faces[:, 0]]]
    groups = {int((labels == key).sum()): np.flatnonzero(labels == key) for key in np.unique(labels)}
    assert sorted(groups) == [1974, 2304, 13572, 132146]
    return doc, binary, prim, v, faces, inv, groups


def evidence(source, output, candidate=None):
    output.mkdir(parents=True, exist_ok=True)
    doc, binary, prim, v, faces, inv, groups = locate(source)
    base = raw.read_glb(source)
    p, n, uv, f, texture, factor = base[0]
    colors = {13572: [1.34, .08, 1.20], 2304: [.12, 1.30, .35], 1974: [.15, .55, 1.50]}
    rows = [('source', base)]
    for count in [13572, 2304, 1974]:
        selected = groups[count]
        keep = np.ones(len(f), dtype=bool); keep[selected] = False
        rows.append((f'mask_{count}', [(p,n,uv,f[keep],texture,factor),
                    (p,n,uv,f[selected],None,np.array(colors[count]))]))
        rows.append((f'isolated_{count}', [(p,n,uv,f[selected],texture,factor)]))
    if candidate:
        rows.append(('candidate', raw.read_glb(candidate)))
    raw.SIZE = 512
    views = [('front', .35), ('right', math.pi/2), ('rear', math.pi+.35), ('left', -math.pi/2)]
    sheet = Image.new('RGB', (2048, 64+len(rows)*546), '#111821')
    draw = ImageDraw.Draw(sheet)
    draw.text((12,10), 'A01 KLYKAR GALE | CPU RAW REST | same source frame | NOT GODOT / GPU', fill='white')
    draw.text((12,30), 'Magenta 13572 / green 2304 / blue 1974 triangles; closed components are reviewed individually.', fill='#b8c4d4')
    for row,(label,primitives) in enumerate(rows):
        for column,(view,angle) in enumerate(views):
            img = raw.render(primitives,angle)
            img.save(output / f'{label}-{view}.png')
            x,y=column*512,64+row*546
            sheet.paste(img,(x,y));draw.text((x+8,y+518),f'{label} / {view}',fill='white')
    sheet.save(output/'component-localization.png')
    if candidate:
        summary=Image.new('RGB',(2048,64+3*546),'#111821')
        sd=ImageDraw.Draw(summary)
        sd.text((12,10),'A01 KLYKAR GALE | CPU RAW REST | source / main wind mask / candidate',fill='white')
        sd.text((12,30),'Three personally reviewed detached wind components removed; small integrated white details intentionally retained.',fill='#b8c4d4')
        for row,name in enumerate(['source','mask_13572','candidate']):
            for col,(view,_) in enumerate(views):
                summary.paste(Image.open(output/f'{name}-{view}.png'),(col*512,64+row*546))
                sd.text((col*512+8,64+row*546+518),name+' / '+view,fill='white')
        summary.save(output/'before-after-mask.png')
    result = {'kind':'CPU raw-rest component masks; no animation or GPU execution',
              'source_sha256':BASE_SHA, 'components':{}}
    for count,ids in groups.items():
        points=v[np.unique(faces[ids])]
        result['components'][count]={'triangles':count,'source_face_ids':ids.tolist(),
            'bbox':[points.min(0).tolist(),points.max(0).tolist()],
            'boundary_edges':len(boundary_edges(inv[faces[ids]]))}
    if candidate:
        from review_levian_gale_wind import normalization_bounds
        result['candidate_sha256']=hashlib.sha256(candidate.read_bytes()).hexdigest()
        result['normalization']={'source':normalization_bounds(base),
                                'candidate':normalization_bounds(rows[-1][1])}
        before=result['normalization']['source'];after=result['normalization']['candidate']
        assert before['all_accessor_positions']==after['all_accessor_positions']
        result['normalization']['stored_positions_scale_delta']=0.0
        result['normalization']['active_triangles_scale_ratio']=(
            after['referenced_triangle_positions']['build_scale']/before['referenced_triangle_positions']['build_scale'])
        result['normalization']['scope']='CPU formula mirror only. Stored unused vertices retained; real Godot import may retain or compact them. Imported AABB/normalization must be checked before promotion.'
    (output/'localization.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='components'},indent=2))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--candidate',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();evidence(args.source,args.output,args.candidate)
