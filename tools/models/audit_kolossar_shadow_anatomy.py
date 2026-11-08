"""Narrow A03 raw/actual-Godot-pose BVH, exact face/body/skin calibration.

Blender CPU: -- SOURCE_GLB CANDIDATE_GLB MANIFEST REPORT [SOURCE_POSES CANDIDATE_POSES]
No graphics/GPU claim; only the new local patch versus retained body and itself.
"""
import hashlib,json,os,sys
from pathlib import Path
import numpy as np
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from inspect_geometry import accessor,read_glb
from review_kolossar_shadow_posed_scope import read_export,skin
from project_kolossar_shadow_exported_palettes import calibrate

def check(source,candidate,manifest,output,source_poses=None,candidate_poses=None):
 m=json.loads(manifest.read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assert sha(candidate)==m['candidate_sha256'];assert sha(source)==m['source_sha256']
 d,b=read_glb(candidate);ps=d['meshes'][0]['primitives'];assert len(ps)==3
 bodyids=sum(m['retained_source_face_ids_by_primitive'],[]);nbody=len(bodyids);ncap=m['new_surface_triangles'];sourceids=np.r_[bodyids,np.full(ncap,-1)]
 if source_poses:
  sd,_dd,_bb=calibrate(source_poses,source);cd,_dd,_bb=calibrate(candidate_poses,candidate);sd,sm=read_export(source_poses);cd,meshes=read_export(candidate_poses)
  assert len(sd['poses'])==len(cd['poses'])==46
  assert sd['poses']==cd['poses'],'Actual post-support bone palettes must remain identical'
  for key in ['height','normalization_scale','normalization_offset']:assert sd[key]==cd[key],key
  assert not cd['export_kind'].startswith('CPU_'),'Must be actual imported candidate, not projected'
  palettes=np.asarray([pose['palettes']for pose in cd['poses']]);assert np.max(abs(palettes-palettes[0]))>.01,'A hidden/static fixture is not motion evidence'
  vs=[mesh[1]for mesh in meshes];fs=[mesh[2]for mesh in meshes];poses=cd['poses']
 else:
  vs=[accessor(d,b,p['attributes']['POSITION'])for p in ps];fs=[accessor(d,b,p['indices']).reshape(-1,3)for p in ps];poses=[{'action':'raw_rest','frame':0}]
 vertices=np.concatenate(vs);offset=0;faces=[]
 for v,f in zip(vs,fs):faces.append(f+offset);offset+=len(v)
 faces=np.concatenate(faces);assert len(faces)==nbody+ncap;_,uid=np.unique(np.round(vertices,6),axis=0,return_inverse=True)
 rows=[];allpairs=[]
 for pose in poses:
  pv=np.concatenate([skin(mesh,pose)for mesh in meshes])if source_poses else vertices
  body=BVHTree.FromPolygons(pv.tolist(),faces[:nbody].tolist(),all_triangles=True,epsilon=0);cap=BVHTree.FromPolygons(pv.tolist(),faces[nbody:].tolist(),all_triangles=True,epsilon=0)
  pairs=np.array([(a,b+nbody)for b,a in cap.overlap(body)]+[(a+nbody,b+nbody)for a,b in cap.overlap(cap)if a<b],int).reshape(-1,2);excluded=0
  if len(pairs):
   adjacent=(uid[faces[pairs[:,0]]][:,:,None]==uid[faces[pairs[:,1]]][:,None,:]).any((1,2));excluded=int(adjacent.sum());pairs=pairs[~adjacent]
  details=[{'candidate_face_pair':[int(a),int(b)],'source_face_pair':[int(sourceids[a]),int(sourceids[b])],'body_cap':bool(a<nbody),'new_local_face_pair':[int(a-nbody)if a>=nbody else None,int(b-nbody)if b>=nbody else None]}for a,b in pairs]
  row={'action':pose['action'],'frame':pose['frame'],'body_cap_pairs':int((pairs[:,0]<nbody).sum()),'new_self_pairs':int((pairs[:,0]>=nbody).sum()),'adjacent_exclusions':excluded,'pairs':details};rows.append(row);allpairs.extend([{'action':pose['action'],'frame':pose['frame'],**p}for p in details]);print(row['action'],row['frame'],'new/body',row['body_cap_pairs'],'self',row['new_self_pairs'],flush=True)
 result={'status':'PASS_NO_NEW_INTERSECTIONS'if not allpairs else 'FAIL_NEW_INTERSECTIONS','candidate_sha256':sha(candidate),'source_sha256':sha(source),'actual_candidate_Godot_import':bool(source_poses),'source_candidate_actual_palettes_and_frame_exact':bool(source_poses),'imported_positions_face_order_bone_mapping_quantized8weights_calibrated':bool(source_poses),'pose_count':len(rows),'body_triangles':nbody,'new_triangles':ncap,'new_nonadjacent_pairs':len(allpairs),'raw_nonadjacent_pairs':len(allpairs)if not source_poses else None,'poses':rows,'pairs':allpairs,'scope':'CPU local BVH after actual post-support imported poses when supplied. No GPU/visual/match claim. Only candidate geometric adjacency is excluded; every nonadjacent pair involving new geometry is reported, with no inheritance exemption.'}
 if source_poses:result.update(source_pose_json_sha256=sha(source_poses/'poses.json'),candidate_pose_json_sha256=sha(candidate_poses/'poses.json'))
 output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n');print(result['status'],len(allpairs),'pairs',flush=True)
if __name__=='__main__':
 try:check(*map(Path,sys.argv[sys.argv.index('--')+1:]));code=0
 except Exception:
  import traceback;traceback.print_exc();code=1
 sys.stdout.flush();sys.stderr.flush();os._exit(code)
