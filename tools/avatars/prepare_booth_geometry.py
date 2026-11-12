#!/usr/bin/env python3
"""Prepare weighted meshes from the pinned BOOTH sources for build_booth_outfits.gd."""
import argparse
from hashlib import sha256
import io
import json
from pathlib import Path
import re
import struct
import subprocess
from zipfile import ZipFile

import numpy as np
from PIL import Image


KIMONO_HASH = '78ab498bdee61b8314d752a7d3244f85088bbbf7cf382b826e8a45934c90a05f'
COAT_HASH = '2f695f395b70679554c7070d8ac3bfb3e308a2bd4b2a93002b74c9ef53fcc288'
HUMANOID = ['Hips', 'LeftUpperLeg', 'RightUpperLeg', 'LeftLowerLeg', 'RightLowerLeg', 'LeftFoot', 'RightFoot',
            'Spine', 'Chest', 'Neck', 'Head', 'LeftShoulder', 'RightShoulder', 'LeftUpperArm', 'RightUpperArm',
            'LeftLowerArm', 'RightLowerArm', 'LeftHand', 'RightHand', 'LeftToes', 'RightToes', 'LeftEye', 'RightEye',
            'Jaw'] + [side + finger + level for side in ('Left', 'Right')
                      for finger in ('Thumb', 'Index', 'Middle', 'Ring', 'Little')
                      for level in ('Proximal', 'Intermediate', 'Distal')] + ['UpperChest']
for _side in ('Left', 'Right'):
    # Unity ThumbProximal / Intermediate / Distal are Godot Metacarpal / Proximal / Distal.
    HUMANOID[HUMANOID.index(_side + 'ThumbProximal')] = _side + 'ThumbMetacarpal'
    HUMANOID[HUMANOID.index(_side + 'ThumbIntermediate')] = _side + 'ThumbProximal'


def checked_archive(path, digest):
    if sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f'{path.name}: unrecognized source SHA-256')
    return ZipFile(path)


def read_xwear(path):
    # XWear v2 serialization layout cross-checked against the public direct exporter:
    # froz3ncore/VRoid-Character-MCP, pipeline/blender-addons/vroid_xwear_direct/__init__.py.
    with checked_archive(path, KIMONO_HASH) as z:
        item = json.loads(z.read('Body\\XItem.json\\XItem.json'))
        assert item['XItemVersion'] == 2
        item_info, = item['XResourceInfoList']
        resource = json.loads(z.read('Body\\XResources\\' + item_info['Guid']))
        renderer, = [c for c in resource['Components'] if 'XResourceSkinnedMeshRenderer' in c['$type']]
        f = io.BytesIO(z.read('Mesh\\' + renderer['MeshGuid']))
        assert renderer['Mesh']['IndexFormat'] == 0
        textures = {m['Guid']: z.read('Textures\\' + m['Guid'] + '.png') for m in item['XResourceTextures']}
    def i32():
        return struct.unpack('<i', f.read(4))[0]
    def arr(dtype, width):
        length = i32()
        return np.frombuffer(f.read(length * 4 * width), dtype=dtype).reshape(length, width)
    assert i32() == 0
    length = shift = 0
    while True:
        byte = f.read(1)[0]
        length |= (byte & 127) << shift
        shift += 7
        if byte < 128:
            break
    assert f.read(length).decode() == renderer['Mesh']['Name']
    vertex_count = i32()
    points, normals = arr('<f4', 3), arr('<f4', 3)
    arr('<f4', 4)  # tangents regenerated after the pose bake
    arr('<f4', 4)  # vertex colors absent in the pinned item
    uv = arr('<f4', 2).copy()
    for _ in range(3):
        assert not len(arr('<f4', 2))
    influences = arr('<f4', 8)
    weights, joints = influences[:, :4], influences.view('<i4')[:, 4:]
    bind_matrices = arr('<f4', 16).reshape(-1, 4, 4).transpose(0, 2, 1)
    by_material = []
    for _ in range(i32()):
        assert i32() == 0  # triangle topology
        by_material.append(arr('<i4', 1).reshape(-1, 3))
    assert i32() == i32() == 0 and not f.read()
    assert len(points) == len(normals) == len(uv) == len(joints) == vertex_count == 11770
    assert sum(map(len, by_material)) == 20360
    parent = {}
    def record(node, parent_id=None):
        parent[node['Guid']] = parent_id
        for child in node['Children']:
            record(child, node['Guid'])
    record(resource['RootGameObject'])
    avatar = {b['BoneGuid']: HUMANOID[b['HumanBodyBones']] for b in resource['XResourceHumanoidMap']['HumanoidBones']}
    def mapped(bone):
        return avatar[bone] if bone in avatar else mapped(parent[bone]) if parent.get(bone) else 'Hips'
    names = [None] * len(bind_matrices)
    heads = {}
    to_godot = np.array([-1., 1., 1.])
    for entry in renderer['Bones']:
        index, bone = entry['Index'], entry['BoneGuid']
        names[index] = mapped(bone)
        if bone in avatar:
            heads[avatar[bone]] = np.linalg.inv(bind_matrices[index])[:3, 3] * to_godot
    # Coordinates change handedness and Unity texture UVs start at the lower left.
    points, normals, uv[:, 1] = points * to_godot, normals * to_godot, 1.0 - uv[:, 1]
    raw_materials = {m['Guid']: m for m in item['XResourceMaterials']}
    materials = [raw_materials[g] for g in renderer['RefMaterialGuids']]
    return ((points, normals, uv, weights, joints, names, heads,
             by_material), materials, textures)


def read_coat(path, output):
    with checked_archive(path, COAT_HASH) as z:
        # Copy only the source blend and maps used in the game; never load bundled scripts.
        files = ('Silvers Coat.blend', 'Tex/Coat_AlbedoTransparency.png', 'Tex/Coat_NormalGL.png',
                 'Tex/Coat_AmbientOcclusion.png')
        for name in files:
            p = output / Path(name).name
            p.write_bytes(z.read("Silver's Coat/" + name))
    read = Path(__file__).with_name('read_booth_coat.py')
    result = output / 'coat.npz'
    if result.exists():
        result.unlink()
    subprocess.run(['blender', '--background', '--factory-startup', '--disable-autoexec', str(output / files[0]),
                    '--python-exit-code', '1', '--python', str(read), '--', str(result)], check=True)
    d = np.load(result)
    assert d['indices'].size // 3 == 17811
    heads = dict(zip(d['bones'], d['head']))
    for i, side in enumerate('LR'):
        heads['Hand_' + side] = d['wrists'][i]
    return d['points'], d['normals'], d['uv'], d['weights'], d['joints'], d['names'], heads, [d['indices'].reshape(-1, 3)]


def unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-10)


def segment_frame(a, b):
    longitudinal = unit(b - a)
    front = np.array([0., 0., 1.])
    forward = unit(front - longitudinal * np.dot(front, longitudinal))
    return np.stack((longitudinal, np.cross(forward, longitudinal), forward), axis=1)


def segment(src_a, src_b, a, b, radius, depth=None):
    scale = np.diag([np.linalg.norm(b - a) / np.linalg.norm(src_b - src_a), radius, depth or radius])
    matrix = segment_frame(a, b) @ scale @ segment_frame(src_a, src_b).T
    return matrix, a - matrix @ src_a


def lerp_map(values, xs, ys):
    i = np.clip(np.searchsorted(xs, values) - 1, 0, len(xs) - 2)
    xs, ys = np.asarray(xs), np.asarray(ys)
    t = (values - xs[i]) / (xs[i + 1] - xs[i])
    return ys[i] + t * (ys[i + 1] - ys[i])


def retarget(raw, target, coat=False):
    points, normals, uv, weights, joints, names, source, triangles = raw
    target_pose = {k: np.asarray(v[2]) for k, v in target.items()}
    mapped = []
    transforms = {}
    for side, suffix in [('Left', 'L'), ('Right', 'R')]:
        sequence = ['Shoulder', 'UpperArm', 'LowerArm', 'Hand']
        src_names = [k + '_' + suffix for k in ('Shoulder', 'Arm', 'Elbow', 'Hand')] if coat else [side + k for k in sequence]
        dest_names = [side + k for k in sequence]
        src_arm = [source[k] for k in src_names]
        dest_arm = [target_pose[k] for k in dest_names]
        for k in range(3):
            radius = [.41, .47, .46][k] if coat else [1.0, .89, .91][k]
            transforms[dest_names[k]] = segment(*src_arm[k:k+2], *dest_arm[k:k+2], radius)
        transforms[dest_names[-1]] = transforms[dest_names[-2]]
    for raw_name in names:
        name = str(raw_name)
        if coat:
            # Preserve original bending on the shoulder and elbow. The source's
            # twist/strap bones use the corresponding target arm segment.
            arm = re.match(r'^(Shoulder|Arm|Elbow|WristTwist|ArmTwist)_([LR])', name)
            if arm:
                piece, side = arm.groups()
                name = {'L': 'Left', 'R': 'Right'}[side] + dict(Shoulder='Shoulder', Arm='UpperArm',
                       ArmTwist='UpperArm', Elbow='LowerArm', WristTwist='LowerArm')[piece]
            elif name == 'Head' or name == 'Neck':
                name = 'Neck'
            elif name == 'Upper_Chest' or name == 'Shoulder Coat Control':
                name = 'UpperChest'
            elif name.startswith('Coat_') or name.startswith('Pouch_'):
                name = 'Hem'
            else:
                name = 'Chest'
        elif 'Hand' in name or re.match(r'^(Left|Right)(Thumb|Index|Middle|Ring|Little)', name):
            name = ('Left' if name.startswith('Left') else 'Right') + 'Hand'
        mapped.append(name)
    if coat:
        landmarks = [source[k][1] for k in ('Chest', 'Upper_Chest', 'Neck')]
        elevations = [target_pose[k][1] for k in ('Chest', 'UpperChest', 'Neck')]
        # Keep the shape of the coat tails, while fitting the upper block to Vita.
        ys = lerp_map(points[:, 1], [0., *landmarks, 3.75], [.09, *elevations, 1.49])
        depths = np.interp(points[:, 1], landmarks, [target_pose['Chest'][2], target_pose['UpperChest'][2], target_pose['Neck'][2]])
        source_depths = np.interp(points[:, 1], landmarks, [source['Chest'][2], source['Upper_Chest'][2], source['Neck'][2]])
        trunk = np.column_stack((points[:, 0] * .43, ys, (points[:, 2] - source_depths) * .53 + depths))
        trunk_normals = unit(normals / np.array([.43, .41, .53]))
    else:
        anchors = ['LeftFoot', 'LeftLowerLeg', 'Hips', 'Chest', 'UpperChest', 'Neck', 'Head']
        ys = lerp_map(points[:, 1], [source[k][1] for k in anchors], [target_pose[k][1] for k in anchors])
        ds = np.interp(points[:, 1], [source[k][1] for k in anchors], [target_pose[k][2] - source[k][2] for k in anchors])
        trunk = np.column_stack((points[:, 0] * 1.01, ys, points[:, 2] * 1.01 + ds))
        trunk_normals = normals
    p, n = np.zeros_like(points), np.zeros_like(normals)
    remapped = np.zeros((len(points), len(target)), dtype=np.float32)
    active = weights > 1e-8
    for joint in np.unique(joints[active]):
        name = mapped[joint]
        w = np.where(joints == joint, weights, 0.).sum(1)
        vertices = np.flatnonzero(w > 1e-8)
        amount = w[vertices, None]
        if name in transforms:
            a, b = transforms[name]
            pos, norm = points[vertices] @ a.T + b, normals[vertices] @ np.linalg.inv(a)
        else:
            pos, norm = trunk[vertices], trunk_normals[vertices]
        p[vertices] += pos * amount
        n[vertices] += unit(norm) * amount
        if name == 'Hem':
            chest = np.clip((trunk[vertices, 1] - .94) / .32, 0., 1.)
            remapped[vertices, target['UpperChest'][0]] += w[vertices] * chest
            remapped[vertices, target['Hips'][0]] += w[vertices] * (1. - chest)
        else:
            remapped[vertices, target[name][0]] += w[vertices]
    p /= weights.sum(1)[:, None]
    assert np.isfinite(p).all() and np.isfinite(n).all()
    fitted_joints = np.argsort(-remapped, axis=1)[:, :4]
    fitted_weights = np.take_along_axis(remapped, fitted_joints, axis=1)
    fitted_weights /= fitted_weights.sum(1)[:, None]
    return p, unit(n), uv, fitted_weights, fitted_joints, triangles


def save_mesh(path, fitted):
    p, n, uv, weights, joints, surfaces = fitted
    with path.open('wb') as f:
        f.write(struct.pack('<I', len(surfaces)))
        for surface in surfaces:
            used, inverse = np.unique(surface, return_inverse=True)
            f.write(struct.pack('<II', len(used), surface.size))
            for array, dtype in ((p[used], '<f4'), (n[used], '<f4'), (uv[used], '<f4'),
                                 (weights[used], '<f4'), (joints[used], '<i4'), (inverse, '<i4')):
                f.write(np.asarray(array, dtype=dtype).tobytes())
    print(path.name, len(p), sum(map(len, surfaces)), p.min(0), p.max(0))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('targets', type=Path)
    parser.add_argument('kimono', type=Path)
    parser.add_argument('coat', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    targets = json.loads(args.targets.read_text())
    raw, mats, textures = read_xwear(args.kimono)
    save_mesh(args.output / 'haori.meshdata', retarget(raw, targets[0]["bones"]))
    mat_data = []
    for i, mat in enumerate(mats):
        props = {p['PropertyName']: p for p in mat['ShaderProperties']}
        texture = f'haori_{i}.png'
        (args.output / texture).write_bytes(textures[props['_MainTex']['TextureGuid']])
        assert textures[props['_MainTex']['TextureGuid']] == textures[props['_ShadeTex']['TextureGuid']]
        mat_data.append({'texture': texture, 'shade': list(props['_ShadeColor']['Color'].values()),
                         'cutoff': props['_Cutoff']['Value']})
    (args.output / 'haori.json').write_text(json.dumps(mat_data, indent=2))
    raw = read_coat(args.coat, args.output)
    save_mesh(args.output / 'operator.meshdata', retarget(raw, targets[1]["bones"], coat=True))
    for suffix, size in [('AlbedoTransparency', 2048), ('NormalGL', 1024), ('AmbientOcclusion', 1024)]:
        with Image.open(args.output / f'Coat_{suffix}.png') as image:
            image.resize((size, size), Image.Resampling.LANCZOS).save(args.output / f'operator_{suffix}.png')


if __name__ == '__main__':
    main()
