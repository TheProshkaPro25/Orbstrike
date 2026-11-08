"""SHA-locked indices-only removal of three personally reviewed A01 wind pieces.

Writes a separate candidate, never production. Source attributes, skeleton,
rest/binds, clips, UV, textures and original binary layout remain byte-exact.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

import numpy as np

from inspect_geometry import accessor
from remove_grifalon_gale_wind import boundary_edges
from review_klykar_gale_wind import BASE_SHA, locate


def build(source, output):
    root=Path(__file__).resolve().parents[2]
    assert source.resolve()!=output.resolve()
    assert not output.resolve().is_relative_to((root/'assets').resolve())
    raw=source.read_bytes()
    doc,binary,prim,v,faces,inv,groups=locate(source)
    index_id=prim['indices'];assert index_id==5
    index=doc['accessors'][index_id];view=doc['bufferViews'][index['bufferView']]
    assert index['count']==449988 and index['componentType']==5125
    assert 'byteStride' not in view and 'byteOffset' not in index
    removed=np.sort(np.concatenate([groups[n] for n in [13572,2304,1974]]))
    retained=groups[132146]
    assert len(removed)==17850 and len(retained)==132146
    assert not (set(inv[faces[removed]].ravel()) & set(inv[faces[retained]].ravel()))
    assert len(boundary_edges(inv[faces[retained]]))==0
    for count in [13572,2304,1974]:
        assert len(boundary_edges(inv[faces[groups[count]]]))==0
    json_length=struct.unpack_from('<I',raw,12)[0]
    json_bytes=raw[20:20+json_length]
    old,new=b'"count":449988',b'"count":396438'
    assert json_bytes.count(old)==1
    new_json=json_bytes.replace(old,new)
    expected=json.loads(json_bytes);expected['accessors'][5]['count']=396438
    assert json.loads(new_json)==expected
    new_indices=np.asarray(faces[retained],dtype='<u4').tobytes()
    index_start=view.get('byteOffset',0);bin_start=20+json_length+8
    modified=bytearray(raw);modified[20:20+json_length]=new_json
    modified[bin_start+index_start:bin_start+index_start+len(new_indices)]=new_indices
    output.parent.mkdir(parents=True,exist_ok=True);output.write_bytes(modified)
    manifest={'kind':'Separate A01 wind-removal candidate; GPU/runtime acceptance pending',
        'source_sha256':BASE_SHA,'candidate_sha256':hashlib.sha256(modified).hexdigest(),
        'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'index_accessor':5,'removed_triangles':17850,'retained_triangles':132146,
        'removed_source_face_ids':removed.tolist(),
        'reviewed_removed_components':{str(n):{'triangles':n,
            'source_indices_sha256':hashlib.sha256(np.asarray(faces[groups[n]],dtype='<u4').tobytes()).hexdigest(),
            'classification':{13572:'Main continuous white wind ribbon in front of chest and face',
                              2304:'Detached pale end of wind arc above/behind ear; not an ear',
                              1974:'Detached wind loop hovering behind shoulder/body; not tail'}[n]}
            for n in [13572,2304,1974]},
        'retained_face_bytes_sha256':hashlib.sha256(new_indices).hexdigest(),
        'json_whitelist':['/accessors/5/count: 449988 -> 396438'],
        'binary_whitelist':{'start':index_start,'length':len(new_indices)},
        'file_bytes':len(raw),'new_boundary_edges':0,'caps_added':0,'vertices_moved':0}
    output.with_suffix('.manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items() if k!='removed_source_face_ids'},indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();build(args.source,args.output)
