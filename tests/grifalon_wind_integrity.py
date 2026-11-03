"""Focused contract for removal of the baked Gale Grifalon wind only.

Usage: python tests/grifalon_wind_integrity.py BASE.glb CANDIDATE.glb [REMOVAL.json]
"""
import hashlib
import json
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools/models'))
from inspect_geometry import accessor, read_glb
from remove_grifalon_gale_wind import boundary_edges, components


def image_bytes(doc,binary,image):
    view=doc['bufferViews'][image['bufferView']]
    start=view.get('byteOffset',0)
    return binary[start:start+view['byteLength']]


def check(base_path,candidate_path,report_path):
    base,bb=read_glb(base_path)
    candidate,cb=read_glb(candidate_path)
    report=json.loads(report_path.read_text())
    assert hashlib.sha256(base_path.read_bytes()).hexdigest()==report['source_sha256']
    assert hashlib.sha256(candidate_path.read_bytes()).hexdigest()==report['output_sha256']
    assert base['nodes']==candidate['nodes'],'node transforms/hierarchy changed'
    assert base['materials']==candidate['materials'],'material changed'
    assert base['textures']==candidate['textures'],'texture reference changed'
    assert len(base['images'])==len(candidate['images'])
    for a,b in zip(base['images'],candidate['images']):
        assert image_bytes(base,bb,a)==image_bytes(candidate,cb,b),'embedded image changed'
    assert len(base['skins'])==len(candidate['skins'])
    for a,b in zip(base['skins'],candidate['skins']):
        assert a['joints']==b['joints']
        assert np.array_equal(accessor(base,bb,a['inverseBindMatrices']),accessor(candidate,cb,b['inverseBindMatrices']))
    assert len(base['animations'])==len(candidate['animations'])
    for a,b in zip(base['animations'],candidate['animations']):
        assert a['name']==b['name'] and a['channels']==b['channels']
        assert len(a['samplers'])==len(b['samplers'])
        for x,y in zip(a['samplers'],b['samplers']):
            assert x.get('interpolation')==y.get('interpolation')
            for key in ['input','output']:
                assert np.array_equal(accessor(base,bb,x[key]),accessor(candidate,cb,y[key])),'animation data changed'
    bp=base['meshes'][0]['primitives'][0]
    cp=candidate['meshes'][0]['primitives'][0]
    ids=np.array(report['retained_source_vertex_ids'],dtype=int)
    cap_ids=np.array(report['cap_vertex_source_ids'],dtype=int)
    original={key:accessor(base,bb,index)for key,index in bp['attributes'].items()}
    result={key:accessor(candidate,cb,index)for key,index in cp['attributes'].items()}
    assert set(original)==set(result)
    for key in original:
        assert np.array_equal(result[key][:len(ids)],original[key][ids]),'retained attribute changed: '+key
        if key!='TEXCOORD_0':
            assert np.array_equal(result[key][len(ids):],original[key][cap_ids]),'cap attachment changed: '+key
    bf=accessor(base,bb,bp['indices']).reshape(-1,3)
    cf=accessor(candidate,cb,cp['indices']).reshape(-1,3)
    retained=np.array(report['retained_source_face_ids'],dtype=int)
    assert len(retained)==127686 and report['removed_wind_triangles']==22312
    assert len(cf)-len(retained)==128
    inverse=np.full(len(original['POSITION']),-1,dtype=int)
    inverse[ids]=np.arange(len(ids))
    assert np.array_equal(cf[:len(retained)],inverse[bf[retained]]),'true retained triangles changed'
    _, weld=np.unique(np.round(result['POSITION'],6),axis=0,return_inverse=True)
    assert len(boundary_edges(weld[cf]))==0,'unsealed ribbon attachment'
    labels=components(weld[cf],int(weld.max())+1)
    assert len(np.unique(labels[weld[cf[:,0]]]))==1,'floating geometry remains'
    tri=result['POSITION'][cf]
    areas=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)*.5
    assert np.isfinite(areas).all() and np.min(areas)>1e-12,'degenerate caps'
    # A seam must follow all original influences, not a rigid replacement bone.
    joints=np.concatenate([result['JOINTS_0'],result['JOINTS_1']],axis=1).astype(int)
    weights=np.concatenate([result['WEIGHTS_0'],result['WEIGHTS_1']],axis=1)
    assert np.allclose(weights.sum(axis=1),1,atol=2e-6)
    rng=np.random.default_rng(31)
    matrices=rng.normal(0,.1,(len(candidate['skins'][0]['joints']),3,4))
    matrices[:,:,:3]+=np.eye(3)[None,:,:]
    points=np.c_[result['POSITION'],np.ones(len(result['POSITION']))]
    deformed=np.sum(np.einsum('nijk,nk->nij',matrices[joints],points)*weights[:,:,None],axis=1)
    lookup={source:i for i,source in enumerate(ids)}
    assert np.max(np.abs(deformed[len(ids):]-deformed[[lookup[i]for i in cap_ids]]))==0,'animated cap seam disconnects'
    print(json.dumps({'failures':0,'retained_triangles':len(retained),'removed_wind_triangles':22312,
                      'cap_triangles':128,'closed_components':1,'boundary_edges':0,
                      'all_retained_attributes_exact':True,'cap_skin_weights_exact':True,
                      'skeleton_binds_clips_images_exact':True,'animated_seam_error':0}))


if __name__=='__main__':
    base,candidate=map(Path,sys.argv[1:3])
    report=Path(sys.argv[3])if len(sys.argv)>3 else candidate.with_suffix('.removal.json')
    check(base,candidate,report)
