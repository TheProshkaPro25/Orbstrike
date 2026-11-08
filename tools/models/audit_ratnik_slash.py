"""Read-only narrow sword-blade/body BVH in exported runtime poses; Blender Python."""
import sys,json
from pathlib import Path
import numpy as np
from mathutils.bvhtree import BVHTree
ROOT=Path('/home/loq/Документы/game/sfery_stikhiy');sys.path.insert(0,str(ROOT/'tools/models'))
from inspect_geometry import read_glb,accessor
from upgrade_rigs import globals_of
source=ROOT/'assets/creatures_hd/ratnik_light.glb';d,b=read_glb(source)
skin=d['skins'][0];names=[d['nodes'][i]['name']for i in skin['joints']];slot=names.index('sword');rest=globals_of(d)[skin['joints'][slot]]
meshes=[]
for node in d['nodes']:
 if 'mesh'not in node or node.get('name')=='CapeGPU':continue
 for p in d['meshes'][node['mesh']]['primitives']:
  v=accessor(d,b,p['attributes']['POSITION']);f=accessor(d,b,p['indices']).reshape(-1,3)
  js=np.concatenate([accessor(d,b,p['attributes']['JOINTS_'+str(i)]).astype(int)for i in [0,1]if 'JOINTS_'+str(i)in p['attributes']],1)
  ws=np.concatenate([accessor(d,b,p['attributes']['WEIGHTS_'+str(i)])for i in [0,1]if 'WEIGHTS_'+str(i)in p['attributes']],1)
  weight=np.where(js==slot,ws,0).sum(1);local=(np.c_[v,np.ones(len(v))]@np.linalg.inv(rest).T)[:,:3]
  blade=(weight[f].min(1)>.90)&(local[f,1].min(1)>.12);body=weight[f].max(1)<.10
  meshes.append((v,f,js,ws,blade,body))
rows=[]
for stage in ['before','after']:
 report=json.loads((ROOT/'build/checks/humanoid-motion'/stage/'creature_ratnik_light.json').read_text())
 for sample in report['samples']:
  if sample['action']!='attack' or sample['frame']not in [12,20,28,36,44,52]:continue
  pal=np.array([sample['bones'][n]for n in names]).reshape(-1,3,4)
  points=[];bf=[];sf=[];offset=0
  for v,f,j,w,blade,body in meshes:
   pos=np.zeros_like(v)
   for k in range(j.shape[1]):
    m=pal[j[:,k]];pos+=(np.einsum('nij,nj->ni',m[:,:,:3],v)+m[:,:,3])*w[:,k,None]
   points.extend(pos.tolist());bf.extend((f[body]+offset).tolist());sf.extend((f[blade]+offset).tolist());offset+=len(v)
  body_bvh=BVHTree.FromPolygons(points,bf,all_triangles=True,epsilon=0)
  blade_bvh=BVHTree.FromPolygons(points,sf,all_triangles=True,epsilon=0)
  hits=blade_bvh.overlap(body_bvh)
  row={'stage':stage,'frame':sample['frame'],'blade_body_pairs':len(hits),'blade_triangles':len(sf),'body_triangles':len(bf)}
  rows.append(row);print(row)
out=ROOT/'docs/audits/2026-11-08-humanoid-motion/blade-body-bvh.json'
out.write_text(json.dumps({'scope':'Only rigid distal blade (localY>.12, swordweight>.90) against body (<.10 swordweight); six exported runtime attack poses each old/new. Not all armor/cloth/continuous collision audit.','poses':rows},indent=2)+'\n')
