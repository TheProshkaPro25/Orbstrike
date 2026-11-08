"""A03 CPU four-view material comparison and exact source-face-mask evidence."""
import argparse,hashlib,json,math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
import audit_20261106 as raw
from inspect_geometry import read_glb
from tint_kolossar_shadow_smoke import material_mask,PALETTES


def review(source,candidates,output):
    output.mkdir(parents=True,exist_ok=True);d,b=read_glb(source);mask=material_mask(d,b);base=raw.read_glb(source);v,n,u,f,t,factor=base[0]
    marked=[(v,n,u,f[~mask],t,factor),(v,n,u,f[mask],None,np.array([1.34,.08,1.2]))]
    rows=[('source',base),('exact_material_mask',marked)]+[(p.stem,raw.read_glb(p))for p in candidates]
    raw.SIZE=640;sheet=Image.new('RGB',(2560,64+674*len(rows)),'#111821');draw=ImageDraw.Draw(sheet)
    draw.text((12,10),'A03 MATERIAL-ONLY COMPARISON | CPU RAW REST | SOURCE GEOMETRY / UV / SKIN IDENTICAL',fill='white')
    draw.text((12,30),'Magenta =10443 pale effect faces. Armor139551 faces retain original material. Angular effect form is still open; no transparency/VFX.',fill='#b8c4d4')
    for row,(label,ps)in enumerate(rows):
        strip=Image.new('RGB',(2560,674),'#111821');sd=ImageDraw.Draw(strip)
        for column,(view,angle)in enumerate([('front',.12),('right',math.pi/2),('rear',math.pi+.12),('left',-math.pi/2)]):
            im=raw.render(ps,angle);im.save(output/f'{label}-{view}.png');x=column*640;strip.paste(im,(x,0));sd.text((x+8,646),f'{label} / {view} / CPU',fill='white')
        strip.save(output/f'{label}-four-views.png');sheet.paste(strip,(0,64+row*674))
    sheet.save(output/'tint-comparison-four-views.png')
    result={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'scope':'CPU raw-rest material comparison; not Godot/GPU','material_mask_faces':int(mask.sum()),
            'original_material_faces':int((~mask).sum()),'form_repair_claimed':False,'variants':[{'file':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'palette':p.stem,'tint_rgb':PALETTES[p.stem]}for p in candidates]}
    (output/'tint-comparison.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source',type=Path,required=True);ap.add_argument('--candidates',type=Path,nargs='+',required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();review(a.source,a.candidates,a.output)
