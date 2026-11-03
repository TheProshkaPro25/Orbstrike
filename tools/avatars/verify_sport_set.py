"""Verify four prepared sports parts and every direct geometry/source input."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'assets/avatars/sport/manifest.json'
OUTPUTS = [f'assets/avatars/sport/{part}_{model}.res'
           for part in ['tracksuit', 'swept_hair'] for model in range(2)]
INPUTS = [f'tools/avatars/{name}.gd' for name in
          ['build_sport_set', 'build_street_set', 'build_wardrobe_variants', 'prepare_vrm_parts']]
INPUTS += [f'assets/avatars/vrm/parts/body_{model}_{outfit}.res'
           for model, count in [(0, 4), (1, 5)] for outfit in range(count)]
INPUTS += [f'assets/avatars/itch/parts/body_{model}.res' for model in range(2)]
INPUTS += [f'assets/avatars/vrm/parts/{name}.res'
           for name in ['hair_0_2', 'hair_1_2', 'skin_0', 'skin_1', 'wardrobe_cloth']]
INPUTS += [f'assets/avatars/vrm/{name}.vrm'
           for name in ['Sakurada_Fumiriya', 'Vita', 'HairSample_Male']]


def digest(name):
    return hashlib.sha256((ROOT / name).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', action='store_true',
                        help='Record after generation and visual acceptance')
    args = parser.parse_args()
    expected_groups = {'inputs': INPUTS, 'outputs': OUTPUTS}
    if args.record:
        MANIFEST.write_text(json.dumps({group: {name: digest(name) for name in names}
                                        for group, names in expected_groups.items()}, indent=2) + '\n')
    data = json.loads(MANIFEST.read_text())
    for group, names in expected_groups.items():
        if set(data[group]) != set(names):
            raise ValueError('Sport manifest file list differs: ' + group)
        for name, expected in data[group].items():
            if digest(name) != expected:
                raise ValueError('Sport set file changed: ' + name)
    print('Sport set: four prepared parts and all source inputs verified')


if __name__ == '__main__':
    main()
