"""Narrow structural checks for the new fighter only, independent of Godot import."""
import hashlib
import json
import struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
path=ROOT/'assets/avatars/fighter_mpfb.glb'
raw=path.read_bytes()
assert raw[:4]==b'glTF' and struct.unpack_from('<I',raw,8)[0]==len(raw)
size=struct.unpack_from('<I',raw,12)[0]
doc=json.loads(raw[20:20+size])
binary=raw[28+size:]
components={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}
widths={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
checks=0

def check(condition,message):
    global checks
    checks+=1
    if not condition: raise AssertionError(message)

def array(index):
    a=doc['accessors'][index]
    dtype=np.dtype(components[a['componentType']]);cols=widths[a['type']]
    if 'bufferView' in a:
        v=doc['bufferViews'][a['bufferView']]
        start=v.get('byteOffset',0)+a.get('byteOffset',0)
        result=np.ndarray((a['count'],cols),dtype=dtype,buffer=binary,offset=start,strides=(v.get('byteStride',cols*dtype.itemsize),dtype.itemsize)).copy()
    else:
        result=np.zeros((a['count'],cols),dtype=dtype)
    if 'sparse' in a:
        sparse=a['sparse'];idx=sparse['indices'];val=sparse['values']
        iv=doc['bufferViews'][idx['bufferView']];vv=doc['bufferViews'][val['bufferView']]
        indices=np.frombuffer(binary,dtype=components[idx['componentType']],count=sparse['count'],offset=iv.get('byteOffset',0)+idx.get('byteOffset',0))
        values=np.frombuffer(binary,dtype=dtype,count=sparse['count']*cols,offset=vv.get('byteOffset',0)+val.get('byteOffset',0)).reshape(-1,cols)
        result[indices]=values
    return result

check(len(doc['meshes'])==17,'expected hands, eight authored body/costume layers, head/eyes/brows/lids/mouth and three hair meshes')
check(len(doc['skins'])==1 and len(doc['skins'][0]['joints'])>=100,'full humanoid rig')
check(all('bufferView'in image and 'uri' not in image for image in doc.get('images',[])),'all textures embedded')
check(np.isfinite(array(doc['skins'][0]['inverseBindMatrices'])).all(),'finite bind matrices')
for mesh in doc['meshes']:
    for p in mesh['primitives']:
        attributes=p['attributes'];vertices=array(attributes['POSITION'])
        check(np.isfinite(vertices).all(),mesh['name']+' finite positions')
        check(array(p['indices']).max()<len(vertices),mesh['name']+' valid indices')
        check('TEXCOORD_0'in attributes and np.isfinite(array(attributes['TEXCOORD_0'])).all(),mesh['name']+' UVs')
        weights=array(attributes['WEIGHTS_0']);joints=array(attributes['JOINTS_0'])
        check(np.isfinite(weights).all() and weights.min()>=0,mesh['name']+' nonnegative finite weights')
        check(np.allclose(weights.sum(axis=1),1,atol=.001),mesh['name']+' normalized weights')
        check(joints.max()<len(doc['skins'][0]['joints']),mesh['name']+' valid bone references')
        for target in p.get('targets',[]):
            delta=array(target['POSITION'])
            check(np.isfinite(delta).all() and np.abs(delta).max()>0,mesh['name']+' functional face morph')
manifest=json.loads(path.with_name('fighter_mpfb.manifest.json').read_text())
check(hashlib.sha256(raw).hexdigest()==manifest['sha256'],'matches build manifest')
report={'checks':checks,'failures':0,'sha256':manifest['sha256'],'meshes':len(doc['meshes']),'bones':len(doc['skins'][0]['joints']),'images':len(doc.get('images',[]))}
output=ROOT/'build/checks/avatars';output.mkdir(parents=True,exist_ok=True)
(output/'model.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
