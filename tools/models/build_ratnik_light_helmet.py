"""Reproduce the accepted A04 helmet repair from immutable b209 and pre-A04454.

Only writes candidates. No Blender, Godot, rig, image, CapeGPU or production edits.
Three explicit regions replace the mistaken wide disc: skull roof and two horns.
"""
import argparse,hashlib,json
from pathlib import Path
import numpy as np
from inspect_geometry import read_glb,accessor
from repair_ratnik_light_halo import select
from remove_grifalon_gale_wind import boundary_edges,loops_of,triangulate
from ratnik_light_helmet_patch import crown_patch
from upgrade_rigs import Writer

BASE='b209b4bad3ec5e2a4b02104993b7de1adbbdd1b59dba565c7f1e14270fe13df8'
ORIGINAL='454e8442b83fe7fd618d0bc0338dfc8b51b1daabaa49b4a5237dcb669598f727'
FINAL='d51ab2dc59b810d39e2b7346fab0101256f44f421fdaa8ed4a538eb97cbf5a70'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def geometry(source,original,out):
 assert sha(source)==BASE and sha(original)==ORIGINAL
 s,sb=read_glb(original);sp,sa,sf,mask,w,inv,_=select(s,sb)
 d,b=read_glb(source);p=d['meshes'][0]['primitives'][0];a={k:accessor(d,b,i)for k,i in p['attributes'].items()};nv=len(sa['POSITION']);v=a['POSITION'][:nv]
 remove=(v[sf][:,:,1].max(1)>.373)&~mask
 basekept=sf[~mask&~remove];assert len(basekept)==113364
 orig={tuple(sorted(e))for e in boundary_edges(inv[sf])};edges=np.array([e for e in boundary_edges(inv[basekept])if tuple(sorted(e))not in orig]);ll=loops_of(edges,w);assert sorted(map(len,ll))==[3,3,149]
 l=max(ll,key=len);rep0=np.full(len(w),-1,int)
 for idx in np.unique(basekept):rep0[inv[idx]]=idx
 roof=np.r_[l[8:67],l[85:139]]
 upperparts=[roof,np.r_[l[138:],l[:9]],l[66:86]];positions=[];faces=[];donors=[];boundids=[];offset=0
 for partindex,loop in enumerate(upperparts):
  ids=rep0[loop];points=v[ids]
  if partindex==0:
   pp,nn,ff,dd,stats=crown_patch(points,0);print(stats,flush=True);positions.extend(pp.tolist());faces.append(ff+offset);donors.extend(ids[dd].tolist());boundids.extend(range(offset,offset+len(ids)));offset+=len(pp);continue
  center=points.mean(0);left=center[0]<.04;end=np.array([.004,.429,.074])if left else np.array([.093,.424,.038]);control=np.array([-.052,.410,.103])if left else np.array([.139,.409,.046]);tangent=control-center;tangent/=np.linalg.norm(tangent);axis=np.cross(tangent,[0,0,1]);axis/=np.linalg.norm(axis);other=np.cross(tangent,axis);residual=points-center;uv=np.column_stack([residual@axis,residual@other]);orientation=np.sign(sum(uv[j,0]*uv[(j+1)%len(uv),1]-uv[j,1]*uv[(j+1)%len(uv),0]for j in range(len(uv))));arc=np.r_[0,np.cumsum(np.linalg.norm(np.roll(points,-1,axis=0)-points,axis=1))];angles=np.arctan2(uv[0,1],uv[0,0])+orientation*2*np.pi*arc[:-1]/arc[-1];radius=np.mean(np.linalg.norm(uv,axis=1));n=len(points);previous=None
  for step in range(16):
   t=step/16;c=(1-t)**2*center+2*(1-t)*t*control+t*t*end;direction=2*(1-t)*(control-center)+2*t*(end-control);direction/=np.linalg.norm(direction);aa=np.cross(direction,[0,0,1]);aa/=np.linalg.norm(aa);bb=np.cross(direction,aa);circle=np.cos(angles)[:,None]*aa+np.sin(angles)[:,None]*bb;section=c+radius*(1-t)**.8*circle
   if step==0:section=points
   elif step<=3:
    mix=step/4;section=section*mix+(points-center+c)*(1-mix)
   current=len(positions);positions.extend(section.tolist());donors.extend(ids.tolist())
   if step==0:boundids.extend(range(current,current+n))
   if previous is not None:
    fs=[]
    for j in range(n):k=(j+1)%n;fs.extend([[previous+j,previous+k,current+k],[previous+j,current+k,current+j]])
    faces.append(np.array(fs))
   previous=current
  apex=len(positions);positions.append(end.tolist());donors.append(int(ids[0]));faces.append(np.array([[previous+j,previous+(j+1)%n,apex]for j in range(n)]))
 # preserve tiny original disk-contact closures
 for loop in ll:
  if len(loop)>3:continue
  ids=rep0[loop];pp=v[ids];ff,_=triangulate(pp);current=len(positions);positions.extend(pp.tolist());donors.extend(ids.tolist());boundids.extend(range(current,current+len(ids)));faces.append(ff+current)
 pos=np.array(positions,np.float32);faces=np.concatenate(faces).astype(np.uint32);donors=np.array(donors);norm=np.zeros_like(pos);fn=np.cross(pos[faces[:,1]]-pos[faces[:,0]],pos[faces[:,2]]-pos[faces[:,0]])
 for j in range(3):np.add.at(norm,faces[:,j],fn)
 norm/=np.maximum(np.linalg.norm(norm,axis=1,keepdims=True),1e-12)
 writer=Writer(d,b)
 for k,idx in list(p['attributes'].items()):
  added=a[k][donors].copy()
  if k=='POSITION':added=pos
  if k=='NORMAL':added=norm
  if k=='TEXCOORD_0':added[:]=[.242,.049]
  if k=='JOINTS_0':added[:]=[11,0,0,0];added[boundids]=a[k][donors[boundids]]
  if k=='WEIGHTS_0':added[:]=[1,0,0,0];added[boundids]=a[k][donors[boundids]]
  if k in ('JOINTS_1','WEIGHTS_1'):added[:]=0;added[boundids]=a[k][donors[boundids]]
  meta=d['accessors'][idx];p['attributes'][k]=writer.add(np.concatenate([a[k][:nv],added]),meta['type'],meta['componentType'])
 p['indices']=writer.add(np.concatenate([basekept,faces+nv]).reshape(-1,1),'SCALAR',5125)
 writer.save(out)
 metadata={'candidate_sha256':sha(out),'source_sha256':BASE,'original_sha256':ORIGINAL,'retained_triangles':len(basekept),'source_removed_face_ids':np.flatnonzero(remove).tolist(),'cap_source_vertex_ids':donors.tolist(),'cap_boundary_new_vertex_ids':(np.array(boundids)+nv).tolist(),'cap_triangles':len(faces),'source_vertices':nv,'roof':stats,'collar':{'source_vertex_ids':[]}}
 out.with_suffix('.manifest.json').write_text(json.dumps(metadata,indent=2))
 return out

def finish_normals(source,out):
 d,b=read_glb(source);prim=d['meshes'][0]['primitives'][0];a={k:accessor(d,b,i)for k,i in prim['attributes'].items()};old,ob=read_glb(Path(__file__).resolve().parents[2]/'build/model_candidates/2026-11-06-sculpt/source/ratnik_light.glb');nv=old['accessors'][old['meshes'][0]['primitives'][0]['attributes']['POSITION']]['count'];v=a['POSITION'][nv:];f=accessor(d,b,prim['indices']).reshape(-1,3)[113364:]-nv
 ww,inv=np.unique(np.round(v,6),axis=0,return_inverse=True);wf=inv[f];norm=np.zeros_like(ww);fn=np.cross(v[f[:,1]]-v[f[:,0]],v[f[:,2]]-v[f[:,0]])
 for j in range(3):np.add.at(norm,wf[:,j],fn)
 norm/=np.maximum(np.linalg.norm(norm,axis=1,keepdims=True),1e-12)
 edges=np.unique(np.sort(np.concatenate([wf[:,[0,1]],wf[:,[1,2]],wf[:,[2,0]]]),1),axis=0);rows=np.r_[edges[:,0],edges[:,1]];cols=np.r_[edges[:,1],edges[:,0]];deg=np.bincount(rows,minlength=len(norm))
 for iteration in range(32):
  avg=np.column_stack([np.bincount(rows,weights=norm[cols,j],minlength=len(norm))/np.maximum(deg,1)for j in range(3)]);norm=.5*norm+.5*avg;norm/=np.maximum(np.linalg.norm(norm,axis=1,keepdims=True),1e-12)
 new=a['NORMAL'].copy();new[nv:]=norm[inv];writer=Writer(d,b);prim['attributes']['NORMAL']=writer.add(new,'VEC3');writer.save(out)
 m=json.load(open(source.with_suffix('.manifest.json')));m['candidate_sha256']=hashlib.sha256(out.read_bytes()).hexdigest();m['geometry_reference_sha256']=hashlib.sha256(source.read_bytes()).hexdigest();m['finish']='only new NORMAL changed, other arrays/indices/rig exact';out.with_suffix('.manifest.json').write_text(json.dumps(m,indent=2))

def finish_seam(source,original,out):
 d,b=read_glb(source);p=d['meshes'][0]['primitives'][0];a={k:accessor(d,b,i)for k,i in p['attributes'].items()};f=accessor(d,b,p['indices']).reshape(-1,3);origd,origb=read_glb(source);op=origd['meshes'][0]['primitives'][0];ov=accessor(origd,origb,op['attributes']['POSITION']);fc=ov[f[:113364]].mean(1)
 mask=(fc[:,0]>-.016)&(fc[:,0]<.026)&(fc[:,1]>.357)&(fc[:,1]<.371)&(fc[:,2]>.123)&(fc[:,2]<.131)
 ids=f[:113364][mask].reshape(-1);nf=len(a['POSITION']);roofids=np.unique(f[113364:][a['POSITION'][f[113364:]][:,:,1].max(1)<.41])
 def metal_normals(points):
  delta=(points-np.array([.040,.350,.089]))/np.array([.054**2,.047**2,.043**2]);delta[:,1]=np.maximum(delta[:,1],8);delta/=np.linalg.norm(delta,axis=1,keepdims=True);return delta
 newnormal=metal_normals(a['POSITION'][ids])
 # roof is first1119 generated vertices; horns retain their smooth geometric normals.
 od,ob=read_glb(original);nv=od['accessors'][od['meshes'][0]['primitives'][0]['attributes']['POSITION']]['count'];roofcount=1119
 base_normal=a['NORMAL'].copy();points=a['POSITION'][nv:nv+roofcount];weight=np.clip((.045-points[:,0])/.020,0,1)*np.clip((points[:,0]+.035)/.020,0,1)*np.clip((points[:,2]-.109)/.010,0,1);weight=weight*weight*(3-2*weight);blend=base_normal[nv:nv+roofcount]*(1-weight[:,None])+metal_normals(points)*weight[:,None];blend/=np.linalg.norm(blend,axis=1,keepdims=True);base_normal[nv:nv+roofcount]=blend;a['NORMAL']=base_normal
 writer=Writer(d,b)
 for key,idx in list(p['attributes'].items()):
  added=a[key][ids].copy()
  if key=='TEXCOORD_0':added[:]=[.242,.049]
  if key=='NORMAL':added=newnormal
  meta=d['accessors'][idx];p['attributes'][key]=writer.add(np.concatenate([a[key],added]),meta['type'],meta['componentType'])
 newfaces=np.concatenate([f[:113364][~mask],f[113364:],np.arange(nf,nf+len(ids)).reshape(-1,3)]);p['indices']=writer.add(newfaces.reshape(-1,1),'SCALAR',5125)
 writer.save(out);m=json.load(open(source.with_suffix('.manifest.json')));m['candidate_sha256']=hashlib.sha256(out.read_bytes()).hexdigest();m['retained_triangles']=113364-int(mask.sum());m['local_lip_source_face_ids']=np.flatnonzero(mask).tolist();m['cap_source_vertex_ids'].extend(ids.tolist());m['cap_boundary_new_vertex_ids'].extend(range(nf,nf+len(ids)));m['cap_triangles']+=int(mask.sum());m['lip_finish']='The obsolete dark disc underside lip joins the helmet by a local material/normal seam; only22 local triangles duplicate source attributes/8weights with accepted gold palette and matched roof normals; source UV streams retained exactly.';out.with_suffix('.manifest.json').write_text(json.dumps(m,indent=2));print('lipfaces',mask.sum(),'SHA',m['candidate_sha256'],flush=True)

def build(source,original,output):
 assert not output.resolve().is_relative_to(Path(__file__).resolve().parents[2]/'assets')
 output.parent.mkdir(parents=True,exist_ok=True)
 geom=output.with_name('reproduced-geometry.glb');smooth=output.with_name('reproduced-smooth.glb')
 geometry(source,original,geom);finish_normals(geom,smooth);finish_seam(smooth,original,output)
 assert sha(geom)=='23403db98f3f9cbce0824283d74636edacd2edbf2316091172d8f197ef46e542'
 assert sha(output)==FINAL,'Reproduction differs from the frozen accepted file'
 print('EXACT REPRODUCTION',sha(output))
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--source',required=True,type=Path);parser.add_argument('--original',required=True,type=Path);parser.add_argument('--output',required=True,type=Path);args=parser.parse_args();build(args.source,args.original,args.output)
