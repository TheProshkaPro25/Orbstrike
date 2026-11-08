"""Read-only double/float32 witnesses for selected A03 BVH candidate pairs.
No BVH scan, asset mutation, renderer, or new-pose claim.
"""
import hashlib,json
from pathlib import Path
from collections import Counter
import numpy as np
ROOT=Path(__file__).resolve().parents[3]


def bary(p,t):
 e=t[1:]-t[0];gram=e@e.T
 if abs(np.linalg.det(gram))<1e-28:return np.array([np.nan]*3)
 x=np.linalg.solve(gram,e@(p-t[0]));return np.r_[1-x.sum(),x]


def intersections(a,b):
 out=[]
 for label,t,u in [('A',a,b),('B',b,a)]:
  n=np.cross(u[1]-u[0],u[2]-u[0]);ln=np.linalg.norm(n);n/=ln
  distances=(t-u[0])@n
  for i,j in [(0,1),(1,2),(2,0)]:
   den=distances[i]-distances[j]
   if abs(den)<1e-17:continue
   s=distances[i]/den
   if -1e-9<=s<=1+1e-9:
    q=t[i]+s*(t[j]-t[i]);bc=bary(q,u)
    if bc.min()>=-1e-9:out.append({'edge_on':label,'edge':[i,j],'fraction':float(s),'point':q.tolist(),'other_bary':bc.tolist()})
 unique=[]
 for r in out:
  if not any(np.linalg.norm(np.array(r['point'])-x)<1e-10 for x in unique):unique.append(np.array(r['point']))
 return {'witnesses':out,'segment_length':max([np.linalg.norm(x-y) for x in unique for y in unique],default=0),'unique_points':len(unique),
         'A_to_B_plane':((a-b[0])@(np.cross(b[1]-b[0],b[2]-b[0])/np.linalg.norm(np.cross(b[1]-b[0],b[2]-b[0])))).tolist(),
         'B_to_A_plane':((b-a[0])@(np.cross(a[1]-a[0],a[2]-a[0])/np.linalg.norm(np.cross(a[1]-a[0],a[2]-a[0])))).tolist()}


def load(folder):
 d=json.loads((folder/'poses.json').read_text());meshes=[]
 for m in d['meshes']:
  def r(k,dt):return np.fromfile(folder/(m['prefix']+'_'+k+'.bin'),dt)
  meshes.append((m,r('vertices',np.float32).reshape(-1,3),r('indices',np.int32).reshape(-1,3),r('joints',np.int32).reshape(-1,m['stride']),r('weights',np.float32).reshape(-1,m['stride'])))
 return d,meshes


def triangle(mesh,face,pose,dtype):
 m,v,f,j,w=mesh;ids=f[face];pos=np.zeros((3,3),dtype=dtype);palette=np.asarray(pose['palettes'][m['mi']]).reshape(-1,3,4)
 for k in range(j.shape[1]):
  mat=palette[j[ids,k]];pos+=(np.einsum('nij,nj->ni',mat[:,:,:3],v[ids])+mat[:,:,3])*w[ids,k,None]
 return pos.astype(float)


def rest_edge_witness(a,b,ja,wa,jb,wb):
 # Vertex-on-other-edge witnesses identify T seams lacking a shared vertex ID.
 found=[]
 def weights(js,ws):
  out=np.zeros((3,64))
  for row in range(3):np.add.at(out[row],js[row],ws[row])
  return out
 av=weights(ja,wa);bv=weights(jb,wb)
 for label,t,u,tw,uw in [('A',a,b,av,bv),('B',b,a,bv,av)]:
  for i in range(3):
   for j,k in [(0,1),(1,2),(2,0)]:
    edge=u[k]-u[j];s=float((t[i]-u[j])@edge/(edge@edge));q=u[j]+s*edge
    if -1e-6<=s<=1+1e-6:
     dist=np.linalg.norm(q-t[i])
     if dist<1e-5:found.append({'vertex_on':label,'vertex':i,'other_edge':[j,k],'fraction':s,'rest_distance':float(dist),'interpolated_weight_max_delta':float(np.max(abs(tw[i]-((1-s)*uw[j]+s*uw[k]))))})
 return found


def run():
 result=[]
 requests=[('retry0430','retry0430',5),('retry0415','retry0415',2),('retry0430-bulged','retry0430_bulged',2)]
 for reportname,dirname,limit in requests:
  report=json.loads((ROOT/f'docs/audits/2026-11-06-model-a03/{reportname}-posed-scope.json').read_text());folder=ROOT/f'build/model_candidates/2026-11-06-a03/{dirname}/projected-poses';d,meshes=load(folder);manifest=json.loads((folder.parent/'kolossar_shadow.graft.json').read_text());nmain=len(manifest['retained_source_face_ids'])
  counts=Counter(tuple(r['candidate_face_pair'])for r in report['genuinely_new_pairs']);rows=[]
  for pair,count in counts.most_common(limit):
   chosen=[r for r in report['genuinely_new_pairs']if tuple(r['candidate_face_pair'])==pair];samples=[]
   a_m,a_id=(0,pair[0])if pair[0]<nmain else(1,pair[0]-nmain)
   b_m,b_id=(0,pair[1])if pair[1]<nmain else(1,pair[1]-nmain)
   ma,mb=meshes[a_m],meshes[b_m];ai,bi=ma[2][a_id],mb[2][b_id];a,b=ma[1][ai].astype(float),mb[1][bi].astype(float)
   for event in chosen:
    pose=next(p for p in d['poses']if(p['action'],p['frame'])==(event['action'],event['frame']))
    af,bf=triangle(ma,a_id,pose,np.float32),triangle(mb,b_id,pose,np.float32);ad,bd=triangle(ma,a_id,pose,np.float64),triangle(mb,b_id,pose,np.float64)
    samples.append({'action':event['action'],'frame':event['frame'],'float32':intersections(af,bf),'double':intersections(ad,bd),'float32_triangles':[af.tolist(),bf.tolist()],'double_triangles':[ad.tolist(),bd.tolist()]})
   rows.append({'candidate_pair':pair,'new_local_pair':[p-nmain if p>=nmain else None for p in pair],'source_faces':chosen[0]['source_face_pair'],'reported_occurrences':count,'rest_triangles':[a.tolist(),b.tolist()],'rest':intersections(a,b),'near_rest_vertex_edge_matches':rest_edge_witness(a,b,ma[3][ai],ma[4][ai],mb[3][bi],mb[4][bi]),'samples':samples})
  result.append({'variant':reportname,'candidate_sha256':report['candidate_sha256'],'pose_export_kind':d.get('export_kind','ACTUAL_GODOT_EXPORT'),'projection_proof':d.get('projection_proof'),'pairs':rows})
 output=ROOT/'docs/audits/2026-11-06-model-sculpt-runtime/contact-witness-review.json';output.write_text(json.dumps(result,indent=2)+'\n')
 for r in result:
  print(r['variant'])
  for pair in r['pairs']:
   ds=[s['double']['segment_length']for s in pair['samples']];fs=[s['float32']['segment_length']for s in pair['samples']]
   print(pair['new_local_pair'],'occ',pair['reported_occurrences'],'restsegment',pair['rest']['segment_length'],'doublesegmax',max(ds),'floatsegmax',max(fs),'matches',pair['near_rest_vertex_edge_matches'])

if __name__=='__main__':run()
