"""Prove A04 final finish changes only new underside crown normals, not motion."""
import argparse,hashlib,json,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import accessor,read_glb


def run(baseline,final,output):
    d,b=read_glb(baseline);e,c=read_glb(final)
    assert d==e and len(b)==len(c)
    p=d['meshes'][0]['primitives'][0];a=d['accessors'][p['attributes']['NORMAL']];v=d['bufferViews'][a['bufferView']]
    assert a['componentType']==5126 and a['type']=='VEC3' and 'byteStride'not in v
    start=v.get('byteOffset',0)+a.get('byteOffset',0);end=start+a['count']*12
    assert b[:start]==c[:start] and b[end:]==c[end:]
    x=accessor(d,b,p['attributes']['NORMAL']);y=accessor(e,c,p['attributes']['NORMAL']);changed=np.flatnonzero((x!=y).any(1))
    assert len(changed)==920 and changed.min()==86783 and changed.max()==87702
    assert np.max(abs(np.linalg.norm(y[changed],axis=1)-1))<1e-5
    report={'status':'PASS','baseline_sha256':hashlib.sha256(baseline.read_bytes()).hexdigest(),'final_sha256':hashlib.sha256(final.read_bytes()).hexdigest(),'json_exact':True,'binary_outside_main_normal_accessor_exact':True,'all_positions_indices_joints_weights_UV_CapeGPU_exact':True,'changed_NORMAL_vertices':len(changed),'changed_NORMAL_first_id':int(changed.min()),'changed_NORMAL_last_id':int(changed.max()),'new_underside_crown_normals_only':True,'body_motion_and_BVH_geometry_equivalence':True}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('baseline',type=Path);p.add_argument('final',type=Path);p.add_argument('output',type=Path);a=p.parse_args();run(a.baseline,a.final,a.output)
