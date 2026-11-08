"""Exact-byte contract for A01 only; no Godot/GPU or animation execution.

python tests/klykar_wind_integrity.py SOURCE CANDIDATE MANIFEST REPORT
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import accessor, read_glb
from remove_grifalon_gale_wind import boundary_edges,components

BASE_SHA='f16e61d615e7897ed513d3abb73aa941cb335827d7f43c07961fd8e277ab4c28'


def check(source,candidate,manifest_path,report_path):
    sr,cr=source.read_bytes(),candidate.read_bytes()
    manifest=json.loads(manifest_path.read_text())
    assert hashlib.sha256(sr).hexdigest()==BASE_SHA==manifest['source_sha256']
    assert hashlib.sha256(cr).hexdigest()==manifest['candidate_sha256']
    before,bb=read_glb(source);after,cb=read_glb(candidate)
    expected=json.loads(json.dumps(before));expected['accessors'][5]['count']=396438
    assert after==expected and len(sr)==len(cr)
    jl=struct.unpack_from('<I',sr,12)[0]
    old_json=sr[20:20+jl];new_json=old_json.replace(b'"count":449988',b'"count":396438')
    assert cr[:20]==sr[:20] and cr[20:20+jl]==new_json
    index=before['accessors'][5];view=before['bufferViews'][index['bufferView']]
    start=view.get('byteOffset',0);length=396438*4
    assert bb[:start]==cb[:start] and bb[start+length:]==cb[start+length:]
    unchanged=0
    for aid in range(len(before['accessors'])):
        if aid==5:continue
        assert accessor(before,bb,aid).tobytes()==accessor(after,cb,aid).tobytes(),aid
        unchanged+=1
    prim=before['meshes'][0]['primitives'][0]
    v=accessor(before,bb,prim['attributes']['POSITION'])
    faces=accessor(before,bb,5).reshape(-1,3)
    kept=accessor(after,cb,5).reshape(-1,3)
    w,inv=np.unique(np.round(v,6),axis=0,return_inverse=True)
    labels=components(inv[faces],len(w))[inv[faces[:,0]]]
    keys,counts=np.unique(labels,return_counts=True)
    assert sorted(counts.tolist())==[1974,2304,13572,132146]
    retained=labels==keys[np.flatnonzero(counts==132146)[0]]
    removed=np.flatnonzero(~retained)
    assert np.array_equal(removed,np.asarray(manifest['removed_source_face_ids']))
    assert len(removed)==17850 and np.array_equal(kept,faces[retained])
    assert not (set(inv[faces[removed]].ravel()) & set(inv[kept].ravel()))
    for key,count in zip(keys,counts):
        assert len(boundary_edges(inv[faces[labels==key]]))==0
        if count!=132146:
            got=hashlib.sha256(np.asarray(faces[labels==key],dtype='<u4').tobytes()).hexdigest()
            assert got==manifest['reviewed_removed_components'][str(count)]['source_indices_sha256']
    assert len(boundary_edges(inv[kept]))==0
    expected_raw=bytearray(sr);expected_raw[20:20+jl]=new_json
    absolute=20+jl+8+start
    expected_raw[absolute:absolute+length]=np.asarray(faces[retained],dtype='<u4').tobytes()
    assert cr==expected_raw,'File changes beyond count digits and retained index prefix'
    area=np.linalg.norm(np.cross(v[kept[:,1]]-v[kept[:,0]],v[kept[:,2]]-v[kept[:,0]]),axis=1)*.5
    result={'failures':0,'source_sha256':BASE_SHA,'candidate_sha256':manifest['candidate_sha256'],
        'source_triangles':len(faces),'retained_body_triangles_exact':len(kept),'removed_wind_triangles':len(removed),
        'removed_closed_components':[13572,2304,1974],
        'unchanged_accessors_byte_exact':unchanged,'all_non_index_binary_bytes_exact':True,
        'only_json_change':'/accessors/5/count:449988->396438',
        'retained_faces_original_order_exact':True,'body_boundary_edges':0,'caps':0,'vertices_moved':0,
        'nodes_rest_skin_binds_clips_uv_images_materials_extras_exact':True,
        'finite_positions':bool(np.isfinite(v).all()),
        'retained_degenerate_triangles_unchanged':int((area<=1e-12).sum()),
        'runtime_gpu_or_animation_execution':False,
        'scope':'Identical retained indices/attributes and skeleton/binds/clips imply identical skin surface for identical bone matrices. Does not execute runtime support/materials/animation.'}
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))


if __name__=='__main__':check(*map(Path,sys.argv[1:5]))
