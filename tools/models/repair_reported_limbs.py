"""Targeted post-0.2.8 repair: keep flight knees within the soft skin's bend range.

Original GLBs are retained in tools/_tmp/limbs029-base. Does not change the
mesh, texture, rests or animation times. Re-running always reads that baseline.
"""
from pathlib import Path
import shutil
import numpy as np
from inspect_geometry import read_glb, accessor
from upgrade_rigs import Writer, qmul, qconj, qfraction
from compact_glb import compact


def repair(path, backup):
    backup.mkdir(parents=True, exist_ok=True)
    source = backup / path.name
    if not source.exists():
        shutil.copy2(path, source)
    doc, binary = read_glb(source)
    writer = Writer(doc, binary)
    nodes = doc['nodes']
    # The generated clips already bend the knee; adding the full hang pose to
    # their large stance deltas collapses the inner thigh/shin surface.
    for animation in doc['animations']:
        for channel in animation['channels']:
            target = channel['target']
            name = nodes[target['node']].get('name', '')
            if target['path'] != 'rotation' or not name.startswith(('thigh.', 'shin.')):
                continue
            rest = np.asarray(nodes[target['node']].get('rotation', [0, 0, 0, 1]))
            sampler = animation['samplers'][channel['sampler']]
            values = accessor(doc, binary, sampler['output'])
            sampler['output'] = writer.add(qmul(rest, qfraction(qmul(qconj(rest), values), .45)), 'VEC4')
    doc['asset'].setdefault('extras', {})['sfery_flight_leg_range'] = 1
    writer.save(path)
    compact(path)


if __name__ == '__main__':
    for species in ('dragnar', 'gorgul'):
        for path in sorted(Path('assets/creatures_hd').glob(species + '_*.glb')):
            repair(path, Path('tools/_tmp/limbs029-base'))
