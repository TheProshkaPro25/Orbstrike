"""CPU raw-rest A03 source/cut-and-recolor whitelist/final evidence."""
import argparse,hashlib,json,math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
import audit_20261106 as raw


def review(source,candidate,manifest_path,output):
    m=json.loads(manifest_path.read_text());sha=hashlib.sha256(candidate.read_bytes()).hexdigest();assert sha==m['candidate_sha256']
    output.mkdir(parents=True,exist_ok=True);base=raw.read_glb(source);p,n,u,f,t,factor=base[0]
    removed=np.zeros(len(f),bool);removed[m['removed_source_face_ids']]=True
    recolor=np.zeros(len(f),bool);recolor[m['recolored_original_face_ids']]=True;cut=removed&~recolor
    marked=[(p,n,u,f[~removed],t,factor),(p,n,u,f[cut],None,np.array([1.34,.08,1.20])),(p,n,u,f[recolor],None,np.array([.05,1.25,1.30]))]
    final=raw.read_glb(candidate);raw.SIZE=768
    rows=[('source',base),('whitelist_magenta_cut_cyan_UV_only',marked),('final_candidate',final)]
    sheet=Image.new('RGB',(3072,64+802*len(rows)),'#111821');draw=ImageDraw.Draw(sheet)
    draw.text((12,10),'A03 FINAL LOCAL SHOULDER GRAFT | CPU RAW REST | NOT GODOT / GPU / SUPPORT',fill='white')
    draw.text((12,30),'Magenta = removed/split original faces. Cyan = original root geometry/normals/8weights exact, UV darkened. Outside whitelist exact.',fill='#b8c4d4')
    for row,(label,ps)in enumerate(rows):
        for column,(view,angle)in enumerate([('front',.12),('right',math.pi/2),('rear',math.pi+.12),('left',-math.pi/2)]):
            im=raw.render(ps,angle);im.save(output/f'{label}-{view}.png');x,y=column*768,64+row*802;sheet.paste(im,(x,y));draw.text((x+8,y+774),f'{label} / {view}',fill='white')
    sheet.save(output/'final-before-after-mask.png')
    result={'kind':'CPU raw-rest personal art-review evidence','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'candidate_sha256':sha,
            'source_triangles':len(f),'cut_or_split_original_triangles':int(cut.sum()),'root_triangles_geometry_weights_exact_uv_only':int(recolor.sum()),
            'candidate_triangles':sum(len(a[3])for a in final),'views':['front','right','rear','left'],
            'runtime_gpu_import_animation_executed':False,'whitelist_manifest':str(manifest_path)}
    (output/'final-localization.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source',type=Path,required=True);ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--manifest',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    a=ap.parse_args();review(a.source,a.candidate,a.manifest,a.output)
