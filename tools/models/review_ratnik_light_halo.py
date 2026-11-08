"""CPU raw-rest six-view A04 mask/candidate evidence, explicitly not GPU/runtime."""
import argparse,math,json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
import audit_20261106 as raw
from inspect_geometry import read_glb
from repair_ratnik_light_halo import select

def focus(prims):
    result=[]
    for v,n,uv,f,t,c in prims:
        f=f[v[f][:,:,1].min(1)>.27]
        if not len(f):continue
        ids,inv=np.unique(f,return_inverse=True)
        result.append((v[ids],n[ids],uv[ids],inv.reshape(-1,3),t,c))
    return result

def review(source,candidate,output):
    output.mkdir(parents=True,exist_ok=True);doc,binary=read_glb(source)
    _,_,_,mask,_,_,_=select(doc,binary)
    base=raw.read_glb(source);v,n,uv,f,t,c=base[0]
    metadata=json.loads(candidate.with_suffix('.manifest.json').read_text())
    collar_ids=metadata.get('collar',{}).get('source_vertex_ids',[])
    collar=(~mask)&np.isin(f,collar_ids).any(1)
    marked=[(v,n,uv,f[~mask&~collar],t,c),(v,n,uv,f[mask],None,np.array([1.34,.08,1.20])),*base[1:]]
    if collar.any():marked.append((v,n,uv,f[collar],None,np.array([.08,1.30,1.35])))
    rows=[('source',base),('mask',marked),('candidate',raw.read_glb(candidate))]
    views=[('front',0,.15),('right',math.pi/2,.15),('back',math.pi,.15),('left',-math.pi/2,.15),('above',.3,3),('below',.3,-2)]
    raw.SIZE=512
    for crop in [False,True]:
        sheet=Image.new('RGB',(512*3,64+3*2*546),'#111821');draw=ImageDraw.Draw(sheet)
        draw.text((10,10),'A04 RATNIK LIGHT | CPU RAW REST | NOT GODOT / GPU / CLOTH',fill='white')
        draw.text((10,30),'Magenta = removed disc; cyan = bounded source collar. New crown + thin ring. Source UV/skin/rig/Cape preserved.',fill='#b8c4d4')
        for ri,(label,prims)in enumerate(rows):
            if crop:prims=focus(prims)
            for vi,(name,ang,el)in enumerate(views):
                im=raw.render(prims,ang,el); x,y=vi%3*512,64+(ri*2+vi//3)*546
                sheet.paste(im,(x,y));draw.text((x+8,y+518),f'{label} / {name}',fill='white')
                im.save(output/f'{label}-{"head" if crop else "full"}-{name}.png')
        sheet.save(output/('head-before-mask-after.png' if crop else 'full-before-mask-after.png'))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',required=True,type=Path);p.add_argument('--candidate',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();review(a.source,a.candidate,a.output)
