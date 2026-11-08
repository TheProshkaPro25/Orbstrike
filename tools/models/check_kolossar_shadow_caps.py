"""Blender CPU BVH diagnostic for new A03 cap triangles only.

blender -b --factory-startup -P tools/models/check_kolossar_shadow_caps.py -- CANDIDATE REPORT
No rendering, Godot, production mutation or full-model intersection sweep.
"""
import hashlib
import json
import os
import sys
from pathlib import Path
import numpy as np
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from inspect_geometry import accessor,read_glb


def check(candidate,output):
    doc,binary=read_glb(candidate);primitives=doc['meshes'][0]['primitives']
    assert len(primitives)==2
    positions=[accessor(doc,binary,p['attributes']['POSITION'])for p in primitives]
    faces=[accessor(doc,binary,p['indices']).reshape(-1,3)for p in primitives]
    main_count=len(faces[0]);faces[1]=faces[1]+len(positions[0])
    v=np.concatenate(positions);f=np.concatenate(faces)
    _,uid=np.unique(np.round(v,6),axis=0,return_inverse=True)
    # Separate trees limit the work to cap/body and cap/cap, excluding the
    # unchanged source body/body intersections from this acceptance decision.
    body=BVHTree.FromPolygons(v.tolist(),f[:main_count].tolist(),all_triangles=True,epsilon=0)
    caps=BVHTree.FromPolygons(v.tolist(),f[main_count:].tolist(),all_triangles=True,epsilon=0)
    raw=[(a,b+main_count)for b,a in caps.overlap(body)]
    raw += [(a+main_count,b+main_count)for a,b in caps.overlap(caps)if a<b]
    pairs=np.asarray(raw,dtype=int).reshape(-1,2)
    if len(pairs):
        adjacent=(uid[f[pairs[:,0]]][:,:,None]==uid[f[pairs[:,1]]][:,None,:]).any((1,2));pairs=pairs[~adjacent]
    result={'kind':'Blender mathutils CPU BVH raw-rest only','candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),
            'new_cap_triangles':len(f)-main_count,'nonadjacent_pairs_touching_caps':len(pairs),
            'body_cap_pairs':int((pairs[:,0]<main_count).sum()),'cap_cap_pairs':int((pairs[:,0]>=main_count).sum()),
            'accepted_geometry':len(pairs)==0,'pairs':pairs.tolist(),
            'scope':'Adjacent geometric vertices excluded. Raw rest only; no skinned/runtime/GPU acceptance.'}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items()if k!='pairs'},indent=2),flush=True)

if __name__=='__main__':
    try:
        args=sys.argv[sys.argv.index('--')+1:];check(*map(Path,args[:2]));code=0
    except Exception as error:
        import traceback;traceback.print_exc();code=1
    # Blender audio/backend teardown may otherwise hang in this environment.
    sys.stdout.flush();sys.stderr.flush();os._exit(code)
