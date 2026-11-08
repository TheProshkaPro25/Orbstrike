"""A03 four-view CPU raw-rest source/mask/candidate evidence, not Godot/GPU."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
import audit_20261106 as raw
from inspect_geometry import read_glb
from remove_kolossar_shadow_smoke import locate


def evidence(source,candidate,output):
    output.mkdir(parents=True,exist_ok=True)
    doc,binary=read_glb(source);prim,arrays,faces,welded,inverse,mask,rgb,uv=locate(doc,binary)
    original=raw.read_glb(source);p,n,u,f,t,fac=original[0]
    marked=[(p,n,u,f[~mask],t,fac),(p,n,u,f[mask],None,np.array([1.34,.08,1.2]))]
    after=raw.read_glb(candidate)
    rows=[('source',original),('mask_magenta',marked),('candidate',after)]
    raw.SIZE=768
    sheet=Image.new('RGB',(768*4,64+len(rows)*802),'#111821');draw=ImageDraw.Draw(sheet)
    draw.text((12,10),'A03 KOLOSSAR SHADOW | CPU RAW REST | NOT GODOT / GPU / ANIMATION',fill='white')
    draw.text((12,30),'Magenta = reviewed shoulder-local connected smoke cut. Original armor/neck streams retained; dark attachment caps added.',fill='#b8c4d4')
    for ri,(label,primitives) in enumerate(rows):
        for ci,(view,angle) in enumerate([('front',.12),('right',math.pi/2),('rear',math.pi+.12),('left',-math.pi/2)]):
            im=raw.render(primitives,angle);im.save(output/f'{label}-{view}.png')
            x,y=ci*768,64+ri*802;sheet.paste(im,(x,y));draw.text((x+8,y+774),f'{label} / {view}',fill='white')
    sheet.save(output/'before-after-mask.png')
    # Fixed camera frame includes original unused positions deliberately, matching
    # the existing main-mesh AABB used for runtime normalization.
    bounds={'source_all_accessor_bbox':[p.min(0).tolist(),p.max(0).tolist()],
            'candidate_all_accessor_bbox':[np.concatenate([a[0]for a in after]).min(0).tolist(),np.concatenate([a[0]for a in after]).max(0).tolist()],
            'source_active_bbox':[p[np.unique(f)].min(0).tolist(),p[np.unique(f)].max(0).tolist()],
            'candidate_active_bbox':[np.concatenate([a[0][np.unique(a[3])]for a in after]).min(0).tolist(),np.concatenate([a[0][np.unique(a[3])]for a in after]).max(0).tolist()]}
    assert bounds['source_all_accessor_bbox']==bounds['candidate_all_accessor_bbox']
    result={'kind':'CPU raw-rest only','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'selected_triangles':int(mask.sum()),
            'mask_method':'two shoulder-bound connected neutral regions, enclosed flecks filled; not a global color mask',
            'bounds':bounds,'runtime_import_animation_or_gpu_executed':False}
    (output/'localization.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source',type=Path,required=True);ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    a=ap.parse_args();evidence(a.source,a.candidate,a.output)
