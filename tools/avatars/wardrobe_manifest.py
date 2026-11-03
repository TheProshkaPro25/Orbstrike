"""Record/verify the derived wardrobe without touching accepted original parts."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PARTS = ROOT / 'assets/avatars/vrm/parts'
MANIFEST = PARTS / 'wardrobe_manifest.json'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--record', action='store_true', help='Record after offline generation and review')
args = parser.parse_args()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

original = json.loads((PARTS / 'manifest.json').read_text())
for name, expected in original['files'].items():
    if digest(PARTS / name) != expected:
        raise ValueError('Accepted part changed: ' + name)

for name, expected in original['model_sha256'].items():
    if digest(ROOT / name) != expected:
        raise ValueError('Original VRM changed: ' + name)

names = ['wardrobe_cloth.res']
names += [f'hair_{model}_{style}.res' for model in range(2) for style in [5, 6]]
names += ['body_0_2.res', 'body_0_3.res', 'body_1_3.res', 'body_1_4.res']
generators = ['tools/avatars/build_wardrobe_variants.gd', 'tools/avatars/prepare_vrm_parts.gd']
if args.record:
    data = dict(generators={name: digest(ROOT / name) for name in generators},
                base_manifest_sha256=digest(PARTS / 'manifest.json'),
                files={name: digest(PARTS / name) for name in names},
                license='Derivatives of the pinned CC0 VRM samples; see ../README.md',
                counts=dict(hair_per_model=7, outfits=[4, 5]))
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
else:
    data = json.loads(MANIFEST.read_text())
    for name, expected in data['generators'].items():
        if digest(ROOT / name) != expected:
            raise ValueError('Generator changed: ' + name)
    for name, expected in data['files'].items():
        if digest(PARTS / name) != expected:
            raise ValueError('Derived part changed: ' + name)
    if digest(PARTS / 'manifest.json') != data['base_manifest_sha256']:
        raise ValueError('Base manifest changed')
print('Wardrobe: 9 derived resources verified; accepted parts unchanged')
