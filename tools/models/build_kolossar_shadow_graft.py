"""Build A03 candidate from local exact-Boolean geometry without re-exporting rig.

Writes only a candidate. All outside-ROI original faces and all original binary
streams remain exact; old smoke roots keep geometry/rig and receive dark armor UV.
"""
import sys,json,copy,hashlib,numpy as np
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'tools/models'))
import argparse
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source',type=Path,required=True);ap.add_argument('--geometry',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
from remove_kolossar_shadow_smoke import BASE_SHA
assert hashlib.sha256(args.source.read_bytes()).hexdigest()==BASE_SHA
assert args.source.resolve()!=args.output.resolve()
assert not args.output.resolve().is_relative_to((root/'assets/creatures_hd').resolve()), 'Candidate output required'
from inspect_geometry import read_glb,accessor
from upgrade_rigs import Writer
from remove_grifalon_gale_wind import boundary_edges
source=args.source;doc,b=read_glb(source);doc=copy.deepcopy(doc);p=doc['meshes'][0]['primitives'][0];a={k:accessor(doc,b,i)for k,i in p['attributes'].items()};v=a['POSITION'];f=accessor(doc,b,p['indices']).reshape(-1,3)
x=np.load(args.geometry);ov=x['v'];of=x['f'];ids=x['source_face'];mat=x['material'];fp=v[f];low=fp.min(1);high=fp.max(1)
roi=(high[:,1]>=.204999)&(((low[:,0]<=-.129999)&(high[:,2]>=.059999))|((high[:,0]>=.224999)&(low[:,2]<=.060001)))
keep=~roi;new=[]
for i,(face,id_)in enumerate(zip(of,ids)):
 if id_<0:new.append(i)
 elif roi[id_]:
  if sorted(map(tuple,ov[face]))==sorted(map(tuple,v[f[id_]])):keep[id_]=True
  else:new.append(i)
from remove_kolossar_shadow_smoke import locate
_,_,_,_,_,smoke,_,_=locate(doc,b)
recolored=np.flatnonzero(keep & smoke)
keep[recolored]=False
start=len(ov);first_face=len(of);ov=np.concatenate([ov,v[f[recolored]].reshape(-1,3).astype(float)]);of=np.concatenate([of,np.arange(start,start+3*len(recolored)).reshape(-1,3)]);ids=np.concatenate([ids,recolored]);mat=np.concatenate([mat,np.zeros(len(recolored),dtype=mat.dtype)]);new.extend(range(first_face,len(of)))
print('keep',keep.sum(),'removed',sum(~keep),'new',len(new),'cap',sum(ids[new]<0),'recolor',len(recolored),flush=True)
# New surface vertex records; retained source streams are untouched.
records={k:[]for k in a};weights_cache={};clip_records={};n_joints=len(doc['skins'][0]['joints'])

def key(point):return tuple(point.astype(np.float32))

def encode_weights(weights):
 order=np.argsort(-weights,kind='stable')[:8];ww=weights[order];ww/=max(ww.sum(),1e-20)
 return order.astype(a['JOINTS_0'].dtype),ww.astype(a['WEIGHTS_0'].dtype)

def decoded(vertex):
 out=np.zeros(n_joints)
 for js,ws in [('JOINTS_0','WEIGHTS_0'),('JOINTS_1','WEIGHTS_1')]:np.add.at(out,a[js][vertex],a[ws][vertex])
 return out
# Attribute interpolation on actual original source triangle, never nearest to a different island.
for i in new:
 id_=ids[i]
 if id_<0:continue
 tri=v[f[id_]].astype(float);e0=tri[1]-tri[0];e1=tri[2]-tri[0];matrix=np.array([[e0@e0,e0@e1],[e0@e1,e1@e1]])
 for point in ov[of[i]]:
  delta=point-tri[0];bc=np.linalg.solve(matrix,np.array([delta@e0,delta@e1]));bc=np.array([1-bc.sum(),*bc]);bc=np.clip(bc,0,1);bc/=bc.sum()
  rec={k:(vals[f[id_]]*bc[:,None]).sum(0)for k,vals in a.items()if not k.startswith(('JOINTS','WEIGHTS'))};rec['POSITION']=point.astype(np.float32);rec['NORMAL']/=max(np.linalg.norm(rec['NORMAL']),1e-12)
  exact_vertex=np.flatnonzero((tri==point).all(1))
  if len(exact_vertex):rec={k:vals[f[id_][exact_vertex[0]]].copy()for k,vals in a.items()if not k.startswith(('JOINTS','WEIGHTS'))}
  w=sum((decoded(int(vert))*weight for vert,weight in zip(f[id_],bc)),start=np.zeros(n_joints))
  k=key(point)
  if k not in weights_cache:weights_cache[k]=encode_weights(w)
  j,ws=weights_cache[k];rec.update(JOINTS_0=j[:4],JOINTS_1=j[4:],WEIGHTS_0=ws[:4],WEIGHTS_1=ws[4:]);clip_records[(i,k)]=rec
# At unchanged source vertices, restore the exact original influences.
source_lookup={key(point):i for i,point in enumerate(v)}
for point_key in list(weights_cache):
 if point_key in source_lookup:
  sv=source_lookup[point_key];weights_cache[point_key]=(np.concatenate([a['JOINTS_0'][sv],a['JOINTS_1'][sv]]),np.concatenate([a['WEIGHTS_0'][sv],a['WEIGHTS_1'][sv]]))
for i in new:
 points=ov[of[i]];id_=ids[i];normal=np.cross(points[1]-points[0],points[2]-points[0]);normal/=max(np.linalg.norm(normal),1e-12)
 for point in points:
  k=key(point)
  if id_>=0:rec=clip_records[(i,k)].copy()
  else:
   if k in source_lookup:
    sv=source_lookup[k];rec={name:vals[sv].copy()for name,vals in a.items()}
   else:
    # Cutter corner is strictly interior to this local shoulder patch. Blend
    # nearby original influences, leaving every original vertex untouched.
    dist=np.linalg.norm(v-point,axis=1);near=np.argsort(dist)[:12];w=1/np.maximum(dist[near],1e-5)**2;w/=w.sum();weights=sum((decoded(int(vert))*ww for vert,ww in zip(near,w)),start=np.zeros(n_joints));j,ws=encode_weights(weights)
    rec={'POSITION':point.astype(np.float32),'NORMAL':normal,'TEXCOORD_0':a['TEXCOORD_0'][f[13522]].mean(0),'JOINTS_0':j[:4],'JOINTS_1':j[4:],'WEIGHTS_0':ws[:4],'WEIGHTS_1':ws[4:]}
   rec['POSITION']=point.astype(np.float32);rec['NORMAL']=normal;rec['TEXCOORD_0']=a['TEXCOORD_0'][f[13522]].mean(0)
  if id_>=0 and smoke[id_]:rec['TEXCOORD_0']=a['TEXCOORD_0'][f[13522]].mean(0)
  if k in weights_cache:
   j,ws=weights_cache[k];rec.update(JOINTS_0=j[:4],JOINTS_1=j[4:],WEIGHTS_0=ws[:4],WEIGHTS_1=ws[4:])
  for name in records:records[name].append(rec[name])
wr=Writer(doc,b);p['indices']=wr.add(f[keep].ravel()[:,None],'SCALAR',5125);newprim={'attributes':{},'indices':None,'material':p['material'],'mode':4}
for key_,values in records.items():
 meta=doc['accessors'][p['attributes'][key_]];newprim['attributes'][key_]=wr.add(np.array(values),meta['type'],meta['componentType'])
newprim['indices']=wr.add(np.arange(len(new)*3)[:,None],'SCALAR',5125);doc['meshes'][0]['primitives'].append(newprim)
out=args.output;out.parent.mkdir(parents=True,exist_ok=True);wr.save(out)
manifest={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'retained_source_face_ids':np.flatnonzero(keep).tolist(),'removed_source_face_ids':np.flatnonzero(~keep).tolist(),'new_boolean_face_ids':list(map(int,new)),'recolored_original_face_ids':recolored.tolist(),'new_surface_triangles':len(new),'new_cap_triangles':int(sum(ids[new]<0)),'clipped_source_triangles':int(len(new)-len(recolored)-sum(ids[new]<0)),'new_surface_source_face_ids':ids[new].tolist(),'roi_source_face_ids':np.flatnonzero(roi).tolist(),'geometry_sha256':hashlib.sha256(args.geometry.read_bytes()).hexdigest(),'original_binary_prefix_preserved':True,'local_roots_geometry_weights_exact_uv_darkened':True,'scope':'local exact Boolean graft; all non-ROI original face indices and all original vertex attributes exact'}
out.with_suffix('.graft.json').write_text(json.dumps(manifest,indent=2)+'\n')
