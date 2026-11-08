"""Same camera/light/frame old/new actual runtime skin comparison, CPU not GPU cloth."""
from pathlib import Path
import json,math,hashlib
import numpy as np
from PIL import Image,ImageDraw
import audit_20261106 as raw
from inspect_geometry import read_glb,accessor
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/audits/2026-11-08-humanoid-motion';OUT.mkdir(parents=True,exist_ok=True)
path=ROOT/'assets/creatures_hd/ratnik_light.glb'
doc,buf=read_glb(path);prims=raw.read_glb(path)
raw_prims=[p for n in doc['nodes'] if 'mesh'in n for p in doc['meshes'][n['mesh']]['primitives']]
names=[doc['nodes'][j]['name']for j in doc['skins'][0]['joints']]
reports=[json.loads((ROOT/'build/checks/humanoid-motion'/stage/'creature_ratnik_light.json').read_text())for stage in ['before','after']]
samples=[[s for s in r['samples'] if s['action']=='attack'][::2]for r in reports]
def posed(sample):
 matrices=np.array([sample['bones'][n]for n in names]).reshape(-1,3,4)
 result=[]
 for primitive,(v,n,uv,f,t,c)in zip(raw_prims,prims):
  js=np.concatenate([accessor(doc,buf,primitive['attributes']['JOINTS_'+str(i)]).astype(int)for i in [0,1]if 'JOINTS_'+str(i)in primitive['attributes']],axis=1)
  ws=np.concatenate([accessor(doc,buf,primitive['attributes']['WEIGHTS_'+str(i)])for i in [0,1]if 'WEIGHTS_'+str(i)in primitive['attributes']],axis=1)
  out=np.zeros_like(v);norm=np.zeros_like(n)
  for j in range(js.shape[1]):
   m=matrices[js[:,j]];out+=(np.einsum('nij,nj->ni',m[:,:,:3],v)+m[:,:,3])*ws[:,j,None];norm+=np.einsum('nij,nj->ni',m[:,:,:3],n)*ws[:,j,None]
  norm/=np.maximum(np.linalg.norm(norm,axis=1,keepdims=True),1e-9)
  result.append((out,norm,uv,f,t,c))
 return result
allposes=[[posed(s)for s in stage]for stage in samples]
# Include an invisible bounding frame in every picture: no per-frame auto zoom.
bounds=np.concatenate([p[0]for stage in allposes for pose in stage for p in pose]);lo,hi=bounds.min(0),bounds.max(0)
frame=np.array([[x,y,z]for x in [lo[0],hi[0]]for y in [lo[1],hi[1]]for z in [lo[2],hi[2]]])
dummy=(frame,np.ones_like(frame),np.zeros((8,2)),np.empty((0,3),int),None,np.ones(3))
raw.SIZE=320
images=[]
for i in range(len(samples[0])):
 canvas=Image.new('RGB',(640,380),'#111821');draw=ImageDraw.Draw(canvas)
 draw.text((14,10),'RATNIK LIGHT | OLD / NEW | SAME GEOMETRY',fill='white')
 draw.text((14,28),'Actual Godot animation + support matrices; CPU skin / approximate light. Not GPU cloth.',fill='#b8c4d4')
 for k,label in enumerate(['BEFORE','AFTER']):
  canvas.paste(raw.render([*allposes[k][i],dummy],.60,.65),(k*320,52));draw.text((k*320+14,356),label+' | frame '+str(samples[k][i]['frame']),fill='white')
 images.append(canvas)
contact=min(range(len(samples[0])),key=lambda i:abs(samples[0][i]['phase']-1/3))
images[contact].save(OUT/'ratnik-slash-contact.png')
# An unambiguous fixed-rate strip: one sample per 4 simulation frames (15fps).
images[0].save(OUT/'ratnik-slash-before-after.gif',save_all=True,append_images=images[1:]+[images[-1]]*7,duration=133,loop=0,optimize=False)
strip=Image.new('RGB',(640*3,380*2),'#111821')
for i,idx in enumerate([0,2,3,contact,6,len(images)-1]):strip.paste(images[idx],((i%3)*640,(i//3)*380))
strip.save(OUT/'ratnik-slash-phases.png')
(OUT/'slash-visual-evidence.json').write_text(json.dumps({'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'before_after_same_glb':True,'source':'actual Godot runtime bone matrices after BodySupport','render':'CPU skin and approximate light, not GPU cloth','shared_camera':True,'shared_frame_bounds':[lo.tolist(),hi.tolist()],'frames':[s['frame']for s in samples[0]],'contact_frame':samples[0][contact]['frame']},indent=2)+'\n')
print(OUT/'ratnik-slash-before-after.gif')
