"""Verify the six prepared street parts and their reproducible source inputs."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'assets/avatars/street/manifest.json'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--record', action='store_true', help='Record after generation and visual review')
args = parser.parse_args()


def digest(name):
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


outputs = [f'assets/avatars/street/{part}_{model}.res'
           for part in ['bomber', 'ponytail', 'case'] for model in range(2)]
inputs = ['tools/avatars/build_street_set.gd', 'tools/avatars/build_wardrobe_variants.gd',
          'tools/avatars/prepare_vrm_parts.gd']
inputs += [f'assets/avatars/vrm/parts/{name}.res' for name in
           ['body_0_0', 'body_0_1', 'body_1_0', 'body_0_2', 'body_1_3', 'hair_0_0', 'hair_1_0', 'skin_0', 'skin_1', 'wardrobe_cloth']]
inputs += [f'assets/avatars/vrm/{name}.vrm'
           for name in ['Sakurada_Fumiriya', 'Vita', 'HairSample_Male']]
if args.record:
    MANIFEST.write_text(json.dumps({'inputs': {name: digest(name) for name in inputs},
                                    'outputs': {name: digest(name) for name in outputs}},
                                   indent=2) + '\n')
data = json.loads(MANIFEST.read_text())
for group, names in [('inputs', inputs), ('outputs', outputs)]:
    if set(data[group]) != set(names):
        raise ValueError('Street manifest file list differs: ' + group)
    for name, expected in data[group].items():
        if digest(name) != expected:
            raise ValueError('Street set file changed: ' + name)
print('Street set: six prepared parts and source inputs verified')
