"""SHA-locked, indices-only removal of the isolated Gale Levian wind ribbon.

Writes an uninstalled candidate. All original attribute arrays, materials,
images, bones, bind matrices, clips, tail repair and binary layout survive.
Only the active prefix of the main indices and its accessor count change.
Unused vertex/index storage deliberately stays in the file; no re-export.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

import numpy as np

from inspect_geometry import accessor, read_glb
from remove_grifalon_gale_wind import boundary_edges, components

BASE_SHA = 'fe5c04377285353b7a95bdb723612464824aaaed05f9b499acb732e858db2ddc'


def build(source, output):
    raw = source.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == BASE_SHA, 'Expected accepted035 Gale Levian source'
    assert source.resolve() != output.resolve(), 'Refusing to overwrite source'
    root = Path(__file__).resolve().parents[2]
    assert not output.resolve().is_relative_to((root / 'assets').resolve()), 'Candidate must stay outside assets'
    doc, binary = read_glb(source)
    primitive = doc['meshes'][0]['primitives'][0]
    index_id = primitive['indices']
    index = doc['accessors'][index_id]
    view = doc['bufferViews'][index['bufferView']]
    assert index_id == 218 and index['count'] == 433092 and index['componentType'] == 5125
    assert 'byteStride' not in view and 'byteOffset' not in index
    positions = accessor(doc, binary, primitive['attributes']['POSITION'])
    faces = accessor(doc, binary, index_id).reshape(-1, 3)
    welded, inverse = np.unique(np.round(positions, 6), axis=0, return_inverse=True)
    labels = components(inverse[faces], len(welded))[inverse[faces[:, 0]]]
    keys, counts = np.unique(labels, return_counts=True)
    assert sorted(counts.tolist()) == [2538, 141826]
    removed = np.flatnonzero(labels == keys[np.flatnonzero(counts == 2538)[0]])
    retained = np.flatnonzero(labels != keys[np.flatnonzero(counts == 2538)[0]])
    assert not (set(inverse[faces[removed]].ravel()) & set(inverse[faces[retained]].ravel()))
    assert len(boundary_edges(inverse[faces[removed]])) == 0, 'Wind component is not closed'
    tail = doc['meshes'][0]['primitives'][1]
    assert np.array_equal(positions, accessor(doc, binary, tail['attributes']['POSITION']))
    tail_faces = accessor(doc, binary, tail['indices']).reshape(-1, 3)
    assert len(tail_faces) == 530
    assert len(boundary_edges(inverse[np.concatenate([faces[retained], tail_faces])])) == 0, 'Body plus accepted tail repair is not closed'
    json_length = struct.unpack_from('<I', raw, 12)[0]
    json_bytes = raw[20:20+json_length]
    count_from = b'"count":433092'
    count_to = b'"count":425478'
    assert json_bytes.count(count_from) == 1
    new_json = json_bytes.replace(count_from, count_to)
    expected = json.loads(json_bytes)
    expected['accessors'][index_id]['count'] = len(retained)*3
    assert json.loads(new_json) == expected
    new_indices = np.asarray(faces[retained], dtype='<u4').tobytes()
    index_start = view.get('byteOffset', 0)
    bin_start = 20+json_length+8
    modified = bytearray(raw)
    modified[20:20+json_length] = new_json
    modified[bin_start+index_start:bin_start+index_start+len(new_indices)] = new_indices
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(modified)
    manifest = {
        'kind': 'Uninstalled A02 candidate; no GPU/runtime acceptance',
        'source_sha256': BASE_SHA,
        'candidate_sha256': hashlib.sha256(modified).hexdigest(),
        'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'index_accessor': index_id,
        'removed_triangles': len(removed), 'retained_main_triangles': len(retained),
        'tail_repair_triangles': 530,
        'removed_source_face_ids': removed.tolist(),
        'removed_face_bytes_sha256': hashlib.sha256(np.asarray(faces[removed],dtype='<u4').tobytes()).hexdigest(),
        'retained_face_bytes_sha256': hashlib.sha256(new_indices).hexdigest(),
        'json_whitelist': ['/accessors/218/count: 433092 -> 425478'],
        'binary_whitelist': {'start': index_start, 'length': len(new_indices)},
        'source_file_bytes': len(raw), 'candidate_file_bytes': len(modified),
        'new_boundary_edges': 0, 'caps_added': 0, 'vertices_moved': 0,
    }
    output.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items() if k != 'removed_source_face_ids'},indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    build(args.source, args.output)
