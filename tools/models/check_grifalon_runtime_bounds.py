#!/usr/bin/env python3
"""Read-only CPU skin bounds from the actual CreatureAnim/renderer fixture."""
import json
import sys
from pathlib import Path
import numpy as np

root = Path(__file__).resolve().parents[2]
folder = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'build/checks/grifalon-fullset'
report = json.loads((folder / 'report.json').read_text())
results = []
failures = []
for row in report['variants']:
    meshes = []
    for mesh in row['meshes']:
        prefix = folder / mesh['prefix']
        n, stride = mesh['vertices'], int(mesh['stride'])
        points = np.fromfile(str(prefix) + '-vertices.bin', '<f4').reshape(n, 3)
        joints = np.fromfile(str(prefix) + '-joints.bin', '<i4').reshape(n, stride)
        weights = np.fromfile(str(prefix) + '-weights.bin', '<f4').reshape(n, stride)
        meshes.append((points, joints, weights, np.array(mesh['world'])))
    low = float('inf')
    high = float('-inf')
    crop_vertices = 0
    cam = row.get('camera')
    if cam:
        camera_matrix = np.eye(4)
        camera_matrix[:3] = cam['world']
        inverse_camera = np.linalg.inv(camera_matrix)
        tangent = np.tan(np.radians(cam['fov']) / 2)
    samples = []
    for sample in row['samples']:
        sample_low, sample_high = float('inf'), float('-inf')
        for index, (points, joints, weights, world) in enumerate(meshes):
            palette = np.array(sample['palettes'][index])
            posed = np.zeros_like(points, dtype=np.float64)
            for influence in range(weights.shape[1]):
                selected = palette[joints[:, influence]]
                posed += (np.einsum('nij,nj->ni', selected[:, :, :3], points) + selected[:, :, 3]) * weights[:, influence, None]
            actual = posed @ world[:, :3].T + world[:, 3]
            sample_low = min(sample_low, float(actual[:, 1].min()))
            sample_high = max(sample_high, float(actual[:, 1].max()))
            if cam:
                view = actual @ inverse_camera[:3, :3].T + inverse_camera[:3, 3]
                depth = -view[:, 2]
                outside = (depth <= 0) | (np.abs(view[:, 1]) > depth * tangent) | (np.abs(view[:, 0]) > depth * tangent * cam['aspect'])
                crop_vertices += int(outside.sum())
        low, high = min(low, sample_low), max(high, sample_high)
        samples.append({'clip': sample['clip'], 'phase': sample['phase'], 'min_y': sample_low, 'max_y': sample_high})
    if low < -.001: failures.append(row['id'] + ': penetrates floor')
    if high > row['visual_top'] + .001: failures.append(row['id'] + ': exceeds camera/label envelope')
    if crop_vertices: failures.append(row['id'] + ': cropped vertices')
    results.append({'id': row['id'], 'min_y': low, 'max_y': high, 'envelope_top': row['visual_top'], 'cropped_vertex_samples': crop_vertices, 'samples': samples})
output = {'scope': 'Actual exported runtime skins, 25 sampled poses per variant; not continuous collision validation', 'failures': failures, 'variants': results}
(folder / 'bounds-report.json').write_text(json.dumps(output, indent=2))
print(json.dumps({'variants': len(results), 'failures': failures, 'bounds': [(x['id'], x['min_y'], x['max_y'], x['envelope_top']) for x in results]}, indent=2))
raise SystemExit(bool(failures))
