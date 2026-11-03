"""Compare actual LBS surfaces of Dragnar before/after Godot pose exports.

Run through Blender (mathutils BVHTree), not a renderer:
  blender -b --factory-startup -P tools/models/dragnar_torso_surface.py -- BEFORE AFTER REPORT.json
Inputs: tools/deformation_audit.gd exports of all six variants, idle+attack,
4 seconds idle at sample-step=6. Geometry/weights must match byte for byte.
The region includes every triangle with >5% hips/chest influence at any vertex,
so shoulders, hips and the tail root are included. Check idle extrema and every
exported attack pose. Crossings exclude triangles sharing a welded vertex.
Raw intersections include pre-existing internal joint folds: judge depth and
location along with the before/after renders; count alone is not a pass/fail.
"""
import json,sys,numpy as np
from pathlib import Path
from mathutils.bvhtree import BVHTree
args=sys.argv[sys.argv.index('--')+1:];before,after,out=map(Path,args[:3]);report=[]
for folder in sorted(after.iterdir()):
 if not (folder/'poses.json').exists():continue
 a=json.loads((before/folder.name/'poses.json').read_text());b=json.loads((folder/'poses.json').read_text());b['poses']=[p for p in b['poses'] if (p['action']=='idle' and p['frame'] in [0,60,120,180,240]) or p['action']=='attack'];a['poses']=[next(x for x in a['poses'] if x['action']==p['action'] and x['frame']==p['frame']) for p in b['poses']]
 rows=[]
 for mesh in b['meshes']:
  prefix=folder/mesh['prefix']
  def read(name,dtype):
   path=str(prefix)+'_'+name+'.bin';assert Path(path).read_bytes()==(before/folder.name/(mesh['prefix']+'_'+name+'.bin')).read_bytes();return np.fromfile(path,dtype)
  v=read('vertices',np.float32).reshape(-1,3);j=read('joints',np.int32).reshape(-1,mesh['stride']);w=read('weights',np.float32).reshape(j.shape);f=read('indices',np.int32).reshape(-1,3)
  torso=np.array([n in ['hips','chest'] for n in mesh['bones']]);influence=(torso[j]*w).sum(1);region=(influence[f].max(1)>.05);f=f[region]
  used,remap=np.unique(f,return_inverse=True);v=v[used];j=j[used];w=w[used];f=remap.reshape(-1,3);_,uid=np.unique(np.round(v,6),axis=0,return_inverse=True);height=np.ptp(v[:,1]);p=v[f];area=np.linalg.norm(np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]),axis=1);keep=area>height*height*1e-9;f=f[keep];area=area[keep]
  edges=np.unique(np.sort(np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]),1),axis=0);length=np.linalg.norm(v[edges[:,0]]-v[edges[:,1]],axis=1);keep=length>height*.001;edges=edges[keep];length=length[keep]
  for pa,pb in zip(a['poses'],b['poses']):
   stats=[];pairs=[]
   for pose in [pa,pb]:
    pal=np.array(pose['palettes'][mesh['mi']]).reshape(-1,3,4);posed=np.zeros_like(v)
    for k in range(j.shape[1]):
     m=pal[j[:,k]];posed+=(np.einsum('nij,nj->ni',m[:,:,:3],v)+m[:,:,3])*w[:,k,None]
    tri=posed[f];ar=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)/area;el=np.linalg.norm(posed[edges[:,0]]-posed[edges[:,1]],axis=1)
    tree=BVHTree.FromPolygons(posed.tolist(),f.tolist(),all_triangles=True,epsilon=0);cross=np.array([(x,y) for x,y in tree.overlap(tree) if x<y],int).reshape(-1,2)
    if len(cross):cross=cross[~(uid[f[cross[:,0]]][:,:,None]==uid[f[cross[:,1]]][:,None,:]).any((1,2))]
    depths=[]
    for aa,bb in cross:
     ta=posed[f[aa]].astype(float);tb=posed[f[bb]].astype(float);na=np.cross(ta[1]-ta[0],ta[2]-ta[0]);nb=np.cross(tb[1]-tb[0],tb[2]-tb[0]);na/=max(np.linalg.norm(na),1e-20);nb/=max(np.linalg.norm(nb),1e-20);da=(tb-ta[0])@na;db=(ta-tb[0])@nb;depths.append(max(0,min(da.max(),-da.min(),db.max(),-db.min()))/height)
    pairs.append(set(map(tuple,cross.tolist())));stats.append({'min_area_ratio':float(ar.min()),'p01_area_ratio':float(np.quantile(ar,.01)),'area_fraction_below_half':float(area[ar<.5].sum()/area.sum()),'max_added_edge_in_height':float(np.maximum(el-length,0).max()/height),'p999_edge_ratio':float(np.quantile(el/length,.999)),'crossings':len(cross),'crossing_depth_max_height':max(depths,default=0),'crossing_depth_sum_height':sum(depths)})
   rows.append({'action':pb['action'],'frame':pb['frame'],'before':stats[0],'after':stats[1],'new_crossings':len(pairs[1]-pairs[0]),'removed_crossings':len(pairs[0]-pairs[1]),'new_bone_weights':[{mesh['bones'][bn]:round(sum(float(w[vi,k]) for vi in f[list(pair)].flat for k in range(j.shape[1]) if j[vi,k]==bn)/6,4) for bn in range(len(mesh['bones'])) if any(j[vi,k]==bn and w[vi,k]>.001 for vi in f[list(pair)].flat for k in range(j.shape[1]))} for pair in sorted(pairs[1]-pairs[0])[:12]],'new_rest_points':[np.mean(v[f[list(pair)]],axis=(0,1)).tolist() for pair in sorted(pairs[1]-pairs[0])[:12]]})
 result={'id':folder.name,'faces':len(f),'poses':rows};report.append(result);print(folder.name,'faces',len(f),'area',min(x['before']['min_area_ratio'] for x in rows),'->',min(x['after']['min_area_ratio'] for x in rows),'crossingmax',max(x['before']['crossings'] for x in rows),'->',max(x['after']['crossings'] for x in rows),'new max',max(x['new_crossings'] for x in rows),flush=True)
out.write_text(json.dumps(report,indent=2));sys.stdout.flush();import os;os._exit(0)
