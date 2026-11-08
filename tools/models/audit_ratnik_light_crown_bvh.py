"""Blender background CPU BVH for A04 new crown and bounded source collar.

blender -b --factory-startup -P tools/models/audit_ratnik_light_crown_bvh.py -- SOURCE CANDIDATE REPORT
No GUI, GPU render, Godot or asset writes. Excludes common geometric vertices.
"""
import hashlib,json,os,sys
from pathlib import Path
import numpy as np
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from inspect_geometry import read_glb,accessor


def pairs_between(vertices,faces_a,faces_b,same=False):
    if not len(faces_a) or not len(faces_b):return set()
    a=BVHTree.FromPolygons(vertices.tolist(),faces_a.tolist(),all_triangles=True,epsilon=0)
    b=a if same else BVHTree.FromPolygons(vertices.tolist(),faces_b.tolist(),all_triangles=True,epsilon=0)
    _,weld=np.unique(np.round(vertices,6),axis=0,return_inverse=True)
    result=set()
    for i,j in a.overlap(b):
        if same and i>=j:continue
        if np.intersect1d(weld[faces_a[i]],weld[faces_b[j]]).size:continue
        result.add((i,j))
    return result


def audit(source,candidate,output):
    s,sb=read_glb(source);d,db=read_glb(candidate)
    m=json.loads(candidate.with_suffix('.manifest.json').read_text())
    sp=s['meshes'][0]['primitives'][0];cp=d['meshes'][0]['primitives'][0]
    sv=accessor(s,sb,sp['attributes']['POSITION']);v=accessor(d,db,cp['attributes']['POSITION'])
    faces=accessor(d,db,cp['indices']).reshape(-1,3);retained=faces[:m['retained_triangles']];caps=faces[m['retained_triangles']:]
    # Only the head can overlap the new surfaces; include a 0.02 safety margin.
    lower=v[np.unique(caps)].min(0);upper=v[np.unique(caps)].max(0)
    tri=v[retained];near=((tri.max(1)>lower-.02)&(tri.min(1)<upper+.02)).all(1)
    near_ids=np.flatnonzero(near);body=retained[near]
    cap_body=pairs_between(v,caps,body);cap_self=pairs_between(v,caps,caps,True)
    collar_ids=np.array(m['collar']['source_vertex_ids']);changed_ids=np.flatnonzero(np.isin(retained,collar_ids).any(1));changed=retained[changed_ids]
    current=pairs_between(v,changed,body);baseline=pairs_between(sv,changed,body)
    introduced=current-baseline
    report={'kind':'Blender CPU raw-rest BVH, common geometric vertices excluded; not actual Godot poses/cloth/GPU acceptance','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'caps':len(caps),'nearby_retained_source_triangles':len(body),'collar_source_triangles':len(changed),'cap_body_nonshared_intersections':len(cap_body),'cap_self_nonshared_intersections':len(cap_self),'collar_body_current':len(current),'collar_body_baseline':len(baseline),'collar_body_introduced':len(introduced),'cap_body_pairs':[[int(i),int(near_ids[j])]for i,j in sorted(cap_body)],'cap_self_pairs':[list(map(int,p))for p in sorted(cap_self)],'collar_introduced_source_face_pairs':[[int(changed_ids[i]),int(near_ids[j])]for i,j in sorted(introduced)]}
    report['status']='PASS' if not cap_body and not cap_self and not introduced else 'FAIL'
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items()if not k.endswith('pairs')},indent=2),flush=True)
    sys.stdout.flush();os._exit(0 if report['status']=='PASS' else 1)

args=sys.argv[sys.argv.index('--')+1:];audit(*map(Path,args))
