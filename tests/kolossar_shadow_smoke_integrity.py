"""A03 preservation contract; geometry safety remains a separate explicit verdict.

python tests/kolossar_shadow_smoke_integrity.py SOURCE CANDIDATE MANIFEST BVH_REPORT REPORT
No Godot, rendering or model mutation.
"""
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import accessor,read_glb
from remove_grifalon_gale_wind import boundary_edges,components
from remove_kolossar_shadow_smoke import BASE_SHA


def check(source,candidate,manifest_path,bvh_path,output):
    assert hashlib.sha256(source.read_bytes()).hexdigest()==BASE_SHA
    sha=hashlib.sha256(candidate.read_bytes()).hexdigest();manifest=json.loads(manifest_path.read_text());bvh=json.loads(bvh_path.read_text())
    assert sha==manifest['candidate_sha256']==bvh['candidate_sha256']
    before,bb=read_glb(source);after,cb=read_glb(candidate)
    assert cb[:len(bb)]==bb, 'Original binary prefix changed'
    for key in before:
        if key not in ('meshes','accessors','bufferViews','buffers'):assert before[key]==after[key],key
    assert before['accessors']==after['accessors'][:len(before['accessors'])]
    assert before['bufferViews']==after['bufferViews'][:len(before['bufferViews'])]
    p=before['meshes'][0]['primitives'][0];kept=after['meshes'][0]['primitives'][0];cap=after['meshes'][0]['primitives'][1]
    assert {k:v for k,v in p.items()if k!='indices'}=={k:v for k,v in kept.items()if k!='indices'}
    assert p['attributes']==kept['attributes']
    for i in range(len(before['accessors'])):assert accessor(before,bb,i).tobytes()==accessor(after,cb,i).tobytes(),i
    f=accessor(before,bb,p['indices']).reshape(-1,3);kf=accessor(after,cb,kept['indices']).reshape(-1,3)
    removed=np.asarray(manifest['removed_source_face_ids']);m=np.ones(len(f),bool);m[removed]=False
    assert np.array_equal(kf,f[m]) and len(removed)==15169 and len(kf)==134825
    ids=np.asarray(manifest['cap_vertex_source_ids'])
    for key in ('POSITION','JOINTS_0','WEIGHTS_0','JOINTS_1','WEIGHTS_1'):
        a=accessor(before,bb,p['attributes'][key]);c=accessor(after,cb,cap['attributes'][key]);assert np.array_equal(a[ids],c),key
    v=accessor(before,bb,p['attributes']['POSITION']);cv=accessor(after,cb,cap['attributes']['POSITION']);cf=accessor(after,cb,cap['indices']).reshape(-1,3)
    allv=np.concatenate([v,cv]);allf=np.concatenate([kf,cf+len(v)]);welded,inverse=np.unique(np.round(allv,6),axis=0,return_inverse=True)
    assert len(boundary_edges(inverse[allf]))==0
    labels=components(inverse[allf],len(welded));assert len(np.unique(labels[inverse[allf]].ravel()))==1
    edge=np.concatenate([allf[:,[0,1]],allf[:,[1,2]],allf[:,[2,0]]]);_,counts=np.unique(np.sort(inverse[edge],axis=1),axis=0,return_counts=True)
    source_edges=np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]])
    _,source_counts=np.unique(np.sort(inverse[source_edges],axis=1),axis=0,return_counts=True)
    source_nonmanifold=int((source_counts>2).sum());candidate_nonmanifold=int((counts>2).sum())
    areas=np.linalg.norm(np.cross(cv[cf[:,1]]-cv[cf[:,0]],cv[cf[:,2]]-cv[cf[:,0]]),axis=1)*.5
    assert (areas>1e-12).all() and np.isfinite(allv).all()
    assert np.array_equal(v.min(0),allv.min(0)) and np.array_equal(v.max(0),allv.max(0))
    result={'source_sha256':BASE_SHA,'candidate_sha256':sha,'preservation_contract':'PASS',
            'unchanged_source_accessors_byte_exact':len(before['accessors']),'source_binary_prefix_exact':True,
            'source_nodes_rest_binds_skin_clips_uv_images_materials_extras_exact':True,
            'retained_original_triangles':len(kf),'removed_original_triangles':len(removed),
            'new_cap_triangles':len(cf),'new_cap_vertices':len(cv),'cap_boundary_positions_and_8_weights_exact':True,
            'boundary_edges':0,'maximum_welded_edge_face_count':int(counts.max()),'active_components':1,
            'source_nonmanifold_edges':source_nonmanifold,'candidate_nonmanifold_edges':candidate_nonmanifold,
            'new_nonmanifold_edges':candidate_nonmanifold-source_nonmanifold,
            'new_cap_degenerate_triangles':int((areas<=1e-12).sum()),'all_accessor_bounds_exact':True,
            'geometry_safety':'PASS' if bvh['accepted_geometry'] and candidate_nonmanifold<=source_nonmanifold else 'REJECTED',
            'new_nonadjacent_cap_intersections':bvh['nonadjacent_pairs_touching_caps'],
            'approved_for_installation':False,'runtime_import_animation_gpu_executed':False,
            'note':'Preservation PASS cannot override intersecting reconstructed caps. This is a rejected prototype.'}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':check(*map(Path,sys.argv[1:6]))
