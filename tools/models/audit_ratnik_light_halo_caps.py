"""CPU raw-rest A04 new-cap intersections; excludes shared points and coplanar contact."""
import sys,numpy as np,json,argparse
from pathlib import Path
from inspect_geometry import accessor,read_glb
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('candidate',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args();p=args.candidate;d,b=read_glb(p);pr=d['meshes'][0]['primitives'][0];v=accessor(d,b,pr['attributes']['POSITION']);f=accessor(d,b,pr['indices']).reshape(-1,3);meta=json.loads(p.with_suffix('.manifest.json').read_text());retained=meta['retained_triangles'];ret=f[:retained];cap=f[retained:];w,inv=np.unique(np.round(v,6),axis=0,return_inverse=True)
retp=v[ret];lo,hi=retp.min(1),retp.max(1)

def segment_hit(origin,direction,tri):
 e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(direction,e2);det=np.einsum('ij,ij->i',e1,h);valid=abs(det)>1e-13
 safe=np.where(valid,det,1);ss=origin-tri[:,0];u=np.einsum('ij,ij->i',ss,h)/safe;q=np.cross(ss,e1);vv=np.einsum('ij,ij->i',direction,q)/safe;t=np.einsum('ij,ij->i',e2,q)/safe
 return valid&(u>1e-7)&(vv>1e-7)&(u+vv<1-1e-7)&(t>1e-7)&(t<1-1e-7)
found=[]
for i,c in enumerate(cap):
 cp=v[c];inds=np.flatnonzero((hi>cp.min(0)+1e-8).all(1)&(lo<cp.max(0)-1e-8).all(1))
 if not len(inds):continue
 shared=np.isin(inv[ret[inds]],inv[c]).any(1);inds=inds[~shared]
 if not len(inds):continue
 tri=retp[inds];hits=np.zeros(len(inds),bool)
 for j in range(3):
  hits|=segment_hit(np.broadcast_to(cp[j],(len(inds),3)),np.broadcast_to(cp[(j+1)%3]-cp[j],(len(inds),3)),tri)
  hits|=segment_hit(tri[:,j],tri[:,(j+1)%3]-tri[:,j],np.broadcast_to(cp,(len(inds),3,3)))
 found.extend([[int(i),int(k)]for k in inds[hits]])
res={'kind':'CPU raw rest exact segment-triangle intersections; not animation or coplanar contact proof','caps_vs_retained_body_nonshared_intersection_pairs':len(found),'pairs_cap_index_retained_face_index':found,'candidate_sha256':__import__('hashlib').sha256(p.read_bytes()).hexdigest()};args.output.write_text(json.dumps(res,indent=2)+'\n');print({k:v for k,v in res.items()if not k.startswith('pairs')})
