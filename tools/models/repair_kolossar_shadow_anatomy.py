"""A03 local rounded shoulder anatomy; immutable source/rig/retained body.

Build only a separate candidate. Source-edge mincut removes the foreign smoke
sheets; a closed low collar and two compact unequal volumes replace them.
Original indexed body, all UV/8-weight streams, skeleton/rest/binds/clips and
original material/image bytes remain exact. Actual Godot poses and independent
art are separate acceptance gates; no automatic production promotion.
"""
import sys,json,copy,hashlib
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from inspect_geometry import read_glb,accessor
from remove_grifalon_gale_wind import boundary_edges,loops_of,triangulate,project_loop
from remove_kolossar_shadow_smoke import locate
from upgrade_rigs import Writer
import argparse
from kolossar_shadow_attachment import attachment_mask
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--original',required=True,type=Path);ap.add_argument('--source',required=True,type=Path);ap.add_argument('--output',required=True,type=Path)
args=ap.parse_args();base=args.original;src=args.source;root=args.output.parent
assert not args.output.resolve().is_relative_to((Path(__file__).resolve().parents[2]/'assets/creatures_hd').resolve())
assert hashlib.sha256(base.read_bytes()).hexdigest()=='6ea6f89a1f2632961e66821d504c57a219952f27e8f0974b4ebc07503ab1462c'
assert hashlib.sha256(src.read_bytes()).hexdigest()=='ca2580a32b502635b15193141c6b71b388ebdde75c04ac10e1646c733c8b4e0f'
sd,sb=read_glb(base);_,a,f,_,_,oldmask,rgb,uv=locate(sd,sb);d,b=read_glb(src)
v=a['POSITION'];w,iv=np.unique(v,axis=0,return_inverse=True);mask=attachment_mask(v,f,oldmask,rgb);kept=f[~mask];loops=loops_of(boundary_edges(iv[kept]),w);rep=np.full(len(w),-1,int)
for i in np.unique(kept):rep[iv[i]]=i
# Distinct named interior tracks preserve exactly up to eight source influences.
j=np.concatenate([a['JOINTS_0'],a['JOINTS_1']],axis=1);wt=np.concatenate([a['WEIGHTS_0'],a['WEIGHTS_1']],axis=1);count=int(j.max())+1
weights=np.zeros((len(v),count))
for k in range(8):np.add.at(weights,(np.arange(len(v)),j[:,k]),wt[:,k])
for amp in [.022]:
 additions={k:[]for k in a};capfaces=[];rows=[];offset=0;boundarysource=[]
 for li,loop in enumerate(loops):
  ids=rep[loop];pp=v[ids].astype(float);cf,q=triangulate(pp);normal=np.cross(pp[cf[:,1]]-pp[cf[:,0]],pp[cf[:,2]]-pp[cf[:,0]]).sum(0);normal/=np.linalg.norm(normal)
  # Start with a true source-edge loop and refine its interior only.
  bary=np.eye(len(pp));ff=cf.copy();pv=pp.copy();bw=weights[ids].copy();proj=q.copy()
  basis=np.linalg.lstsq(pp-pp.mean(0),q,rcond=None)[0]
  seeds=np.array([[-.213,.282,.042],[-.221,.269,.086]]) if li==0 else np.array([[.265,.269,-.035],[.279,.246,.006]])
  cq=(seeds-pp.mean(0))@basis
  # Refine the actual local volume footprints uniformly; retained source edges
  # are never split, so no T-junction with the exact body can be introduced.
  for it in range(8 if len(ids)>20 else 0):
   bed=set(map(tuple,np.sort(boundary_edges(ff),axis=1)));edges=np.unique(np.sort(np.concatenate([ff[:,[0,1]],ff[:,[1,2]],ff[:,[2,0]]]),1),axis=0);mids={};newv=list(pv);newbw=list(bw);newproj=list(proj)
   for aa,bb in edges:
    key=(int(aa),int(bb));mid=(proj[aa]+proj[bb])/2
    if key in bed:continue
    if np.linalg.norm(proj[aa]-proj[bb])<=.0035:continue
    if min(np.linalg.norm(mid-c)for c in cq)>.055:continue
    mids[key]=len(newv);newv.append((pv[aa]+pv[bb])/2);newbw.append((bw[aa]+bw[bb])/2);newproj.append(mid)
   if not mids:break
   nf=[]
   for tri in ff:
    aa,bb,cc=map(int,tri);mm=[mids.get(tuple(sorted(pair)))for pair in [(aa,bb),(bb,cc),(cc,aa)]];num=sum(vv is not None for vv in mm)
    if num==0:nf.append([aa,bb,cc])
    elif num==3:
     ab,bc,ca=mm;nf.extend([[aa,ab,ca],[ab,bb,bc],[ca,bc,cc],[ab,bc,ca]])
    elif num==1:
     k=next(k for k in range(3)if mm[k]is not None);tt=list(tri[k:])+list(tri[:k]);a0,b0,c0=map(int,tt);mid=mm[k];nf.extend([[a0,mid,c0],[mid,b0,c0]])
    else:
     k=next(k for k in range(3)if mm[k]is not None and mm[(k+1)%3]is not None);tt=list(tri[k:])+list(tri[:k]);a0,b0,c0=map(int,tt);ab,bc=mm[k],mm[(k+1)%3];nf.extend([[b0,bc,ab],[a0,ab,c0],[ab,bc,c0]])
   pv=np.array(newv);bw=np.array(newbw);proj=np.array(newproj);ff=np.array(nf,int)
  ab=q;end=np.roll(q,-1,axis=0);edge=end-ab;rel=proj[:,None]-ab;tt=np.clip(np.einsum('vli,li->vl',rel,edge)/np.maximum((edge*edge).sum(1),1e-20),0,1);dist=np.sqrt(((rel-tt[:,:,None]*edge)**2).sum(2)).min(1)
  # Lift only along the exact non-crossing projection normal: projection remains injective.
  basis=np.linalg.lstsq(pp-pp.mean(0),q,rcond=None)[0];pn=np.cross(basis[:,0],basis[:,1]);pn/=np.linalg.norm(pn);pn*=np.sign(np.dot(pn,normal));normal=pn
  edgeids=np.unique(np.sort(np.concatenate([ff[:,[0,1]],ff[:,[1,2]],ff[:,[2,0]]]),1),axis=0);edgeids=np.concatenate([edgeids,edgeids[:,::-1]]);rr,cc=edgeids.T;dd=np.bincount(rr,minlength=len(pv));hh=pv@normal;ori=hh.copy()
  for step in range(250):
   avg=np.bincount(rr,weights=hh[cc],minlength=len(pv))/np.maximum(dd,1);hh[len(ids):]=avg[len(ids):]
  if len(ids)>20:pv+=normal*(hh-ori)[:,None]
  # The compact shoulder patch carries two very low asymmetric smoke swells.
  axis=np.linalg.svd(q-q.mean(0),full_matrices=False)[2][0];long=(proj-q.mean(0))@axis;extent=np.ptp(q@axis)
  # The collar itself has no broad lift. Two compact unequal 3D volumes
  # sit on it; their footprints are much smaller than the source closure.
  center=q.mean(0);short=np.array([-axis[1],axis[0]])
  center1,center2=cq
  sigma1=.021;sigma2=.016
  g1=np.exp(-((proj-center1)**2).sum(1)/(sigma1*sigma1));g2=np.exp(-((proj-center2)**2).sum(1)/(sigma2*sigma2))
  taper=1-np.exp(-(dist/.007)**2)
  lift=(.022*g1+.015*g2)*taper if len(ids)>20 else np.zeros(len(pv))
  lift[:len(ids)]=0;pv+=normal*lift[:,None]
  uvmap=(proj-q.min(0))/np.maximum(np.ptp(q,axis=0),1e-8)
  uvmap[:,0]=(uvmap[:,0]*.48+.01)+(0 if li==0 else .5)
  if li>1:uvmap[:]=[.505,.005]
  normals=np.zeros_like(pv);ns=np.cross(pv[ff[:,1]]-pv[ff[:,0]],pv[ff[:,2]]-pv[ff[:,0]])
  for k in range(3):np.add.at(normals,ff[:,k],ns)
  normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-12)
  # Smooth only authored cap normals; exact retained body streams are untouched.
  true_normals=normals.copy()
  normals[:len(ids)]=a['NORMAL'][ids]
  for step in range(60):
   avg=np.array([np.bincount(rr,weights=normals[cc,k],minlength=len(pv))/np.maximum(dd,1)for k in range(3)]).T
   normals[len(ids):]=avg[len(ids):];normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-12)

  # Preserve the honest curvature of the small 3D peaks, not a broad flat field.
  for step in range(6):
   avg=np.array([np.bincount(rr,weights=true_normals[cc,k],minlength=len(pv))/np.maximum(dd,1)for k in range(3)]).T
   true_normals[len(ids):]=avg[len(ids):];true_normals/=np.maximum(np.linalg.norm(true_normals,axis=1,keepdims=True),1e-12)
  blend=np.clip(lift/.005,0,1)[:,None];normals=normals*(1-blend)+true_normals*blend;normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-12)
  jointids=np.argsort(bw,axis=1)[:,-8:][:,::-1];wvals=np.take_along_axis(bw,jointids,axis=1);wvals/=wvals.sum(1)[:,None]
  # Boundary skin bytes are copied rather than sorted, interior is smooth sparse8.
  jointids[:len(ids)]=j[ids];wvals[:len(ids)]=wt[ids]
  arrays={'POSITION':pv,'NORMAL':normals,'TEXCOORD_0':uvmap,'JOINTS_0':jointids[:,:4],'JOINTS_1':jointids[:,4:],'WEIGHTS_0':wvals[:,:4],'WEIGHTS_1':wvals[:,4:]}
  for k in a:additions[k].append(arrays[k])
  capfaces.append(ff+offset);boundarysource.extend(ids.tolist());rows.append({'loop':li,'source_boundary_ids':ids.tolist(),'normal':normal.tolist(),'vertices':len(pv),'faces':len(ff),'max_lift':float(lift.max()),'q_bounds':[q.min(0).tolist(),q.max(0).tolist()],'smoke_centers':[center1.tolist(),center2.tolist()],'smoke_sigmas':[float(sigma1),float(sigma2)]});offset+=len(pv)
 doc=copy.deepcopy(d);writer=Writer(doc,b);ps=doc['meshes'][0]['primitives'];sourcefaceids=[]
 # Preserve installed material partition and exact original source-face indices.
 for pp in ps:
  face=accessor(doc,b,pp['indices']).reshape(-1,3);look={tuple(tri):i for i,tri in enumerate(f)};ids=np.array([look[tuple(tri)]for tri in face]);keep=~mask[ids];pp['indices']=writer.add(face[keep].ravel()[:,None],'SCALAR',5125);sourcefaceids.append(ids[keep].tolist())
 # Use an authored low-violet smoke material without texture projection distortions.
 mat=copy.deepcopy(doc['materials'][ps[1]['material']]);mat['name']='A03 low rounded smoke';mat['pbrMetallicRoughness'].pop('baseColorTexture',None);mat['pbrMetallicRoughness']['baseColorFactor']=[1,1,1,1];mat['pbrMetallicRoughness']['roughnessFactor']=.85;# A small authored gradient blends the broad closure into the source armor;
 # only compact central swells receive a restrained smoke-violet accent.
 import io
 from PIL import Image
 colors=np.zeros((256,512,3))
 for li,row in enumerate(rows[:2]):
  lo,hi=np.array(row['q_bounds']);yy,xx=np.mgrid[0:256,0:256];qq=np.stack([xx/255,yy/255],axis=2)*(hi-lo)+lo
  c1,c2=np.array(row['smoke_centers']);s1,s2=row['smoke_sigmas'];accent=np.exp(-((qq-c1)**2).sum(2)/s1**2)+.70*np.exp(-((qq-c2)**2).sum(2)/s2**2);accent=np.clip(accent,0,1)[:,:,None]
  colors[:,li*256:(li+1)*256]=np.array([.205,.157,.228])*(1-accent)+np.array([.29,.175,.37])*accent
 im=Image.fromarray(np.clip(colors*255,0,255).astype(np.uint8));bio=io.BytesIO();im.save(bio,format='PNG');payload=bio.getvalue();writer.binary.extend(b'\0'*((-len(writer.binary))%4));view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':len(writer.binary),'byteLength':len(payload)});writer.binary.extend(payload)
 image=len(doc['images']);doc['images'].append({'mimeType':'image/png','bufferView':view,'name':'A03 compact smoke armor blend'});texture=len(doc['textures']);doc['textures'].append({'source':image,'sampler':0});mat['pbrMetallicRoughness']['baseColorTexture']={'index':texture};mid=len(doc['materials']);doc['materials'].append(mat)
 cap={'attributes':{},'material':mid,'mode':4}
 for k,vals in additions.items():
  meta=sd['accessors'][sd['meshes'][0]['primitives'][0]['attributes'][k]];cap['attributes'][k]=writer.add(np.concatenate(vals),meta['type'],meta['componentType'])
 ff=np.concatenate(capfaces);cap['indices']=writer.add(ff.ravel()[:,None],'SCALAR',5125);doc['meshes'][0]['primitives'].append(cap);name='rounded_smoke'+str(round(amp*1000));out=args.output;writer.save(out)
 manifest={'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'original_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'removed_source_face_ids':np.flatnonzero(mask).tolist(),'retained_source_face_ids_by_primitive':sourcefaceids,'new_surface_triangles':len(ff),'loops':rows,'amplitude':amp,'geometry':'exact-source-edge mincut; compact outward smoke swells; no Boolean split; source streams retained'};out.with_suffix('.anatomy.json').write_text(json.dumps(manifest,indent=2));print(name,len(ff),offset,flush=True)
