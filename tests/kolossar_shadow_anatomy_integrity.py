"""Exact A03 source/material/anatomy contract; no production writes or GPU claims."""
import copy,hashlib,json,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools/models'))
from inspect_geometry import accessor,read_glb
from remove_grifalon_gale_wind import boundary_edges
from tint_kolossar_shadow_smoke import material_mask
ORIGINAL_SHA='6ea6f89a1f2632961e66821d504c57a219952f27e8f0974b4ebc07503ab1462c'
MATERIAL_SHA='ca2580a32b502635b15193141c6b71b388ebdde75c04ac10e1646c733c8b4e0f'

def check(original,source,candidate,manifest,raw_report,output):
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 assert sha(original)==ORIGINAL_SHA;assert sha(source)==MATERIAL_SHA
 m=json.loads(manifest.read_text());assert m['source_sha256']==sha(source);assert m['candidate_sha256']==sha(candidate);assert m['original_sha256']==sha(original)
 od,ob=read_glb(original);sd,sb=read_glb(source);d,b=read_glb(candidate)
 for key in ['nodes','skins','animations','scenes','scene','samplers','asset']:
  assert d.get(key)==sd.get(key)==od.get(key),key
 assert b[:len(sb)]==sb and sb[:len(ob)]==ob,'Immutable source BIN prefix'
 assert d['accessors'][:len(sd['accessors'])]==sd['accessors'],'Every source accessor metadata exact'
 assert d['bufferViews'][:len(sd['bufferViews'])]==sd['bufferViews'],'Every source view metadata exact'
 for key in ['images','textures','materials']:
  assert d[key][0:len(sd[key])]==sd[key],key
 op=od['meshes'][0]['primitives'][0];sf=accessor(od,ob,op['indices']).reshape(-1,3)
 tint=material_mask(od,ob);source_ids=[]
 for i,sp in enumerate(sd['meshes'][0]['primitives']):
  assert sp['attributes']==op['attributes'];assert np.array_equal(accessor(sd,sb,sp['indices']).reshape(-1,3),sf[tint if i==1 else ~tint]);source_ids.append(np.flatnonzero(tint if i==1 else ~tint))
 ps=d['meshes'][0]['primitives'];assert len(ps)==3
 removed=np.asarray(m['removed_source_face_ids']);assert len(removed)==14241 and len(set(removed))==len(removed)
 retained=[];allv=[];allf=[];offset=0
 for i,(sp,cp) in enumerate(zip(sd['meshes'][0]['primitives'],ps[:2])):
  assert cp['attributes']==sp['attributes'] and cp['material']==sp['material'],'Retained UV/8skin/NORMAL/POSITION/material exact'
  ids=np.asarray(m['retained_source_face_ids_by_primitive'][i]);expected=source_ids[i][~np.isin(source_ids[i],removed)];assert np.array_equal(ids,expected)
  faces=accessor(d,b,cp['indices']).reshape(-1,3);assert np.array_equal(faces,sf[ids]);retained.extend(ids.tolist())
 assert len(retained)==135753 and sorted(retained+removed.tolist())==list(range(149994)),'Source face partition'
 cap=ps[2];attrs={k:accessor(d,b,i)for k,i in cap['attributes'].items()};cf=accessor(d,b,cap['indices']).reshape(-1,3);assert len(cf)==m['new_surface_triangles']==35403
 vertex_offset=face_offset=0;boundarytotal=0;v=accessor(od,ob,op['attributes']['POSITION'])
 for row in m['loops']:
  ids=np.array(row['source_boundary_ids']);count=len(ids);sl=slice(vertex_offset,vertex_offset+count)
  for key in ['POSITION','JOINTS_0','JOINTS_1','WEIGHTS_0','WEIGHTS_1']:
   original_array=accessor(od,ob,op['attributes'][key]);assert np.array_equal(attrs[key][sl],original_array[ids]),'Exact collar '+key
  vertex_offset+=row['vertices'];face_offset+=row['faces'];boundarytotal+=count
 assert vertex_offset==len(attrs['POSITION'])==17797 and face_offset==len(cf)
 weights=np.concatenate([attrs['WEIGHTS_0'],attrs['WEIGHTS_1']],axis=1);joints=np.concatenate([attrs['JOINTS_0'],attrs['JOINTS_1']],axis=1)
 assert np.isfinite(weights).all() and (weights>=0).all() and np.max(abs(weights.sum(1)-1))<2e-6
 assert joints.min()>=0 and joints.max()<len(d['skins'][0]['joints'])
 assert all(np.isfinite(x).all()for x in attrs.values())
 areas=np.linalg.norm(np.cross(attrs['POSITION'][cf[:,1]]-attrs['POSITION'][cf[:,0]],attrs['POSITION'][cf[:,2]]-attrs['POSITION'][cf[:,0]]),axis=1)*.5;assert (areas>1e-12).all()
 normal_lengths=np.linalg.norm(attrs['NORMAL'],axis=1);assert np.max(abs(normal_lengths-1))<2e-6
 for cp in ps:
  vp=accessor(d,b,cp['attributes']['POSITION']);fp=accessor(d,b,cp['indices']).reshape(-1,3);allv.append(vp);allf.append(fp+offset);offset+=len(vp)
 av=np.concatenate(allv);af=np.concatenate(allf);_,uid=np.unique(np.round(av,6),axis=0,return_inverse=True)
 assert len(boundary_edges(uid[af]))==0,'No new mesh openings'
 raw=json.loads(raw_report.read_text());assert raw['candidate_sha256']==sha(candidate) and raw['raw_nonadjacent_pairs']==0
 result={'status':'PASS','candidate_sha256':sha(candidate),'material_source_sha256':sha(source),'original_sha256':sha(original),'source_BIN_and_all_accessors_exact':True,'retained_source_faces_exact':len(retained),'removed_whitelisted_source_faces':len(removed),'new_triangles':len(cf),'new_vertices':len(attrs['POSITION']),'exact_collar_vertices':boundarytotal,'closed_mesh_boundary_edges':0,'new_degenerate_faces':0,'raw_new_nonadjacent_intersections':0,'source_rig_rest_bind_UV8weights_images_materials_clips_exact':True,'scope':'Raw contract and local BVH only; actual poses, source frame guard and independent art are separate required gates.'}
 output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':check(*map(Path,sys.argv[1:7]))
