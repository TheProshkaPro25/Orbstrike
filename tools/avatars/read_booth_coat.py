"""Run in background Blender with the original Silvers Coat.blend already open."""
from pathlib import Path
import sys

import bpy
import numpy as np


def export(output: Path) -> None:
    garment = bpy.data.objects['Silver Coat']
    armature = garment.parent
    mesh = garment.data
    mesh.calc_loop_triangles()
    # Blender +Z up, -Y forward; the avatar has +Y up and +Z forward.
    def coordinates(point):
        return point.x, point.z, -point.y

    matrix = garment.matrix_world
    normal_matrix = matrix.to_3x3().inverted().transposed()
    points = []
    normals = []
    uvs = []
    joints = []
    weights = []
    indices = []
    uv = mesh.uv_layers.active.data
    cache = {}
    for triangle in mesh.loop_triangles:
        # Godot's front face is clockwise.
        for loop_id in reversed(triangle.loops):
            vert = mesh.vertices[mesh.loops[loop_id].vertex_index]
            t = uv[loop_id].uv
            normal = mesh.corner_normals[loop_id].vector
            key = (vert.index, tuple(t), tuple(normal))
            if key not in cache:
                cache[key] = len(points)
                points.append(coordinates(matrix @ vert.co))
                normals.append(coordinates((normal_matrix @ normal).normalized()))
                uvs.append((t.x, 1.0 - t.y))
                influences = sorted(((g.weight, g.group) for g in vert.groups if g.weight > 1e-7), reverse=True)[:8]
                assert influences, vert.index
                weights.append([w for w, _ in influences] + [0.] * (8 - len(influences)))
                joints.append([j for _, j in influences] + [0] * (8 - len(influences)))
            indices.append(cache[key])
    names = [g.name for g in garment.vertex_groups]
    bones = list(armature.data.bones)
    positions = {b.name: coordinates(armature.matrix_world @ b.head_local) for b in bones}
    wrists = {side: coordinates(armature.matrix_world @ armature.data.bones['Elbow_' + side].tail_local)
              for side in 'LR'}
    np.savez_compressed(output, points=points, normals=normals, uv=uvs, joints=joints, weights=weights,
                        indices=indices, names=names, bones=[b.name for b in bones],
                        head=[positions[b.name] for b in bones], wrists=list(wrists.values()))
    print(f'Silver Coat: {len(points)} UV/normal vertices; {len(indices) // 3} source triangles')


if __name__ == '__main__':
    export(Path(sys.argv[sys.argv.index('--') + 1]))
