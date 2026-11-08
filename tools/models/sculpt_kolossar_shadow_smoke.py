"""Rejected A03 harmonic-sculpt experiment. CPU only, no production install.

Repro: python tools/models/sculpt_kolossar_shadow_smoke.py --source SOURCE --output CANDIDATE
This experiment has174new raw-rest intersections and is not approved.
"""
import sys,json,copy,hashlib,numpy as np
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'tools/models'))
import argparse
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
from inspect_geometry import read_glb,accessor
from remove_kolossar_shadow_smoke import locate
from remove_grifalon_gale_wind import boundary_edges
from upgrade_rigs import Writer
source=args.source;assert source.resolve()!=args.output.resolve();assert 'assets/creatures_hd' not in str(args.output);from remove_kolossar_shadow_smoke import BASE_SHA
assert hashlib.sha256(source.read_bytes()).hexdigest()==BASE_SHA
d,b=read_glb(source);d=copy.deepcopy(d);pr,a,f,vw,iv,m,rgb,uv=locate(d,b)
fsub=iv[f[m]];used,ivsub=np.unique(fsub,return_inverse=True);ff=ivsub.reshape(-1,3);v=vw[used].astype(float);boundary=np.unique(boundary_edges(ff));mask=np.ones(len(v),bool);mask[boundary]=False;interior=np.flatnonzero(mask)
ed=np.unique(np.sort(np.concatenate([ff[:,[0,1]],ff[:,[1,2]],ff[:,[2,0]]]),1),axis=0);ed=np.concatenate([ed,ed[:,::-1]])
row,col=ed.T;degree=np.bincount(row,minlength=len(v));mapping=np.full(len(v),-1);mapping[interior]=np.arange(len(interior));q=(mapping[row]>=0)&(mapping[col]>=0);rr=mapping[row[q]].astype(int);cc=mapping[col[q]].astype(int);diag=degree[interior]
fixed=v.copy();fixed[interior]=0
rhs=np.array([np.bincount(row,weights=fixed[col,k],minlength=len(v))[interior]for k in range(3)]).T

def mult(x):return diag[:,None]*x-np.array([np.bincount(rr,weights=x[cc,k],minlength=len(interior))for k in range(3)]).T
x=v[interior].copy();res=rhs-mult(x);direction=res.copy();rs=(res*res).sum(0)
for it in range(2000):
 ad=mult(direction);alpha=rs/np.maximum((direction*ad).sum(0),1e-30);x+=direction*alpha;res-=ad*alpha;nr=(res*res).sum(0)
 if nr.max()<1e-18:break
 direction=res+direction*(nr/np.maximum(rs,1e-30));rs=nr
v[interior]=x;print('CG',it,'residual',nr,flush=True)
# Exact boundary source coordinates rather than rounded welded points.
rep=np.full(len(vw),-1,dtype=int)
for vert in np.unique(f[m]):rep[iv[vert]]=vert
for vert in np.unique(f[~m]):rep[iv[vert]]=vert
ids=rep[used];v[boundary]=a['POSITION'][ids[boundary]]
# Use closest attachment attributes for interior; boundary attributes exact.
nearest=boundary[np.argmin(((v[interior,None,:]-v[boundary][None,:,:])**2).sum(2),axis=1)]
cap_ids=ids.copy();cap_ids[interior]=ids[nearest]
cap={'attributes':{},'material':pr['material'],'mode':4};wr=Writer(d,b);pr['indices']=wr.add(f[~m].ravel()[:,None],'SCALAR',5125)
normal=np.zeros_like(v);ns=np.cross(v[ff[:,1]]-v[ff[:,0]],v[ff[:,2]]-v[ff[:,0]])
for k in range(3):np.add.at(normal,ff[:,k],ns)
normal/=np.maximum(np.linalg.norm(normal,axis=1,keepdims=True),1e-12)
for key,vals in a.items():
 val=vals[cap_ids].copy()
 if key=='POSITION':val=v
 if key=='NORMAL':val=normal
 if key=='TEXCOORD_0':
  q=a['POSITION'][f].mean(1);val[:]=uv[13522]
 meta=d['accessors'][pr['attributes'][key]];cap['attributes'][key]=wr.add(val,meta['type'],meta['componentType'])
cap['indices']=wr.add(ff.ravel()[:,None],'SCALAR',5125);d['meshes'][0]['primitives'].append(cap)
out=args.output;out.parent.mkdir(parents=True,exist_ok=True);wr.save(out)
area=np.linalg.norm(ns,axis=1)*.5;print('cap',len(ff),'degenerate',sum(area<1e-12),'bbox',v.min(0),v.max(0),flush=True)

report={'status':'REJECTED_PROTOTYPE','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'removed_smoke_triangles':int(m.sum()),'sculpt_triangles':len(ff),'cap_degenerate_triangles':int((area<1e-12).sum()),'scope':'Harmonic coordinates with attachment boundary fixed. Interior weights copied from closest attachment; not animation-accepted. Not approved.'}
out.with_suffix('.sculpt.json').write_text(json.dumps(report,indent=2)+'\n')
