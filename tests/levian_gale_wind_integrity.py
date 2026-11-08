"""Byte contract for the uninstalled A02 Gale Levian candidate only.

python tests/levian_gale_wind_integrity.py SOURCE CANDIDATE MANIFEST REPORT
No renderer, Godot, model mutation or all-catalog geometry checks.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools/models'))
from inspect_geometry import accessor, read_glb
from remove_grifalon_gale_wind import boundary_edges, components

EXPECTED_SOURCE_SHA = 'fe5c04377285353b7a95bdb723612464824aaaed05f9b499acb732e858db2ddc'


def check(source, candidate, manifest_path, report_path):
    source_raw, candidate_raw = source.read_bytes(), candidate.read_bytes()
    manifest = json.loads(manifest_path.read_text())
    assert hashlib.sha256(source_raw).hexdigest() == EXPECTED_SOURCE_SHA == manifest['source_sha256']
    assert hashlib.sha256(candidate_raw).hexdigest() == manifest['candidate_sha256']
    base, bb = read_glb(source)
    after, cb = read_glb(candidate)
    expected_json = json.loads(json.dumps(base))
    expected_json['accessors'][218]['count'] = 425478
    assert after == expected_json, 'Change beyond sole JSON accessor count'
    assert len(source_raw) == len(candidate_raw)
    json_length = struct.unpack_from('<I', source_raw, 12)[0]
    assert source_raw[:20] == candidate_raw[:20], 'GLB header/layout changed'
    old_json = source_raw[20:20+json_length]
    assert candidate_raw[20:20+json_length] == old_json.replace(b'"count":433092', b'"count":425478')
    assert len(bb) == len(cb)
    a = base['accessors'][218]
    view = base['bufferViews'][a['bufferView']]
    start = view.get('byteOffset', 0)
    retained_bytes = 425478 * 4
    assert bb[:start] == cb[:start] and bb[start+retained_bytes:] == cb[start+retained_bytes:], 'Non-index binary changed'
    # Every accessor except the active index stream must remain byte-for-byte equal.
    unchanged_accessors = 0
    for i in range(len(base['accessors'])):
        if i == 218:
            continue
        assert accessor(base, bb, i).tobytes() == accessor(after, cb, i).tobytes(), f'Accessor {i} changed'
        unchanged_accessors += 1
    prim = base['meshes'][0]['primitives'][0]
    faces = accessor(base, bb, 218).reshape(-1, 3)
    kept = accessor(after, cb, 218).reshape(-1, 3)
    removed = np.asarray(manifest['removed_source_face_ids'], dtype=int)
    assert len(removed) == 2538 and np.all(np.diff(removed) > 0)
    mask = np.ones(len(faces),dtype=bool)
    mask[removed] = False
    assert np.array_equal(kept, faces[mask]), 'Retained triangles reordered/changed'
    expected_raw = bytearray(source_raw)
    expected_raw[20:20+json_length] = old_json.replace(b'"count":433092', b'"count":425478')
    absolute_index_start = 20+json_length+8+start
    expected_raw[absolute_index_start:absolute_index_start+retained_bytes] = np.asarray(faces[mask],dtype='<u4').tobytes()
    assert candidate_raw == expected_raw, 'File bytes changed beyond count digits and retained index prefix'
    positions = accessor(base, bb, prim['attributes']['POSITION'])
    unique, inv = np.unique(np.round(positions,6),axis=0,return_inverse=True)
    labels = components(inv[faces],len(unique))
    assert len(np.unique(labels[inv[faces[removed]].ravel()])) == 1
    assert not (set(inv[faces[removed]].ravel()) & set(inv[kept].ravel()))
    assert len(boundary_edges(inv[faces[removed]])) == 0
    tail = base['meshes'][0]['primitives'][1]
    assert np.array_equal(accessor(base,bb,tail['indices']),accessor(after,cb,tail['indices']))
    assert np.array_equal(positions,accessor(base,bb,tail['attributes']['POSITION']))
    tail_faces = accessor(base,bb,tail['indices']).reshape(-1,3)
    assert len(tail_faces) == 530
    assert len(boundary_edges(inv[np.concatenate([kept,tail_faces])])) == 0
    triangles = positions[kept]
    area = np.linalg.norm(np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]),axis=1)*.5
    result = {
        'failures': 0, 'source_sha256': EXPECTED_SOURCE_SHA,
        'candidate_sha256': manifest['candidate_sha256'],
        'source_main_triangles': len(faces), 'removed_wind_triangles': len(removed),
        'retained_main_triangles': len(kept), 'tail_repair_triangles_exact': 530,
        'unchanged_accessors_byte_exact': unchanged_accessors,
        'all_original_attributes_byte_exact': True,
        'all_non_index_binary_bytes_exact': True,
        'only_json_change': '/accessors/218/count:433092->425478',
        'nodes_rest_skin_binds_clips_uv_images_materials_extras_exact': True,
        'retained_faces_exact_original_order': True,
        'retained_body_plus_tail_repair_boundary_edges': 0, 'caps': 0,
        'retained_nondegenerate_triangles': int((area>1e-12).sum()),
        'retained_degenerate_triangles_unchanged': int((area<=1e-12).sum()),
        'finite_positions': bool(np.isfinite(positions).all()),
        'runtime_gpu_or_animation_execution': False,
        'mathematical_scope': 'Identical retained triangles, vertex attributes, skeleton/binds and animation imply identical retained skin surface for identical bone matrices; actual runtime/support/cloth not executed.',
    }
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report_path.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))


if __name__ == '__main__':
    check(*map(Path,sys.argv[1:5]))
