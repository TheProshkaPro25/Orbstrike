"""Record after review, or verify the prepared itch.io asset manifest offline."""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'assets/avatars/itch'
MANIFEST = BASE / 'manifest.json'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--record', action='store_true')
args = parser.parse_args()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

generators = ['tools/avatars/prepare_itch_parts.gd', 'tools/avatars/export_modular_hair.py',
              'tools/avatars/prepare_denim.py', 'tools/avatars/itch_character_sources.json']
if args.record:
    paths = sorted(p for p in BASE.rglob('*') if p.suffix in ['.res', '.vrm', '.glb', '.png'])
    data = dict(files={p.relative_to(ROOT).as_posix(): digest(p) for p in paths},
                generators={p: digest(ROOT / p) for p in generators},
                active=dict(hair_per_base=9, costumes=[5,6], denim=14),
                library_only=['Boz short/pony/twins need better fit', 'Unrigged modular body/clothes in source archives'],
                licenses='See README.md and CREDITS.md; not all content is CC0')
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
else:
    data = json.loads(MANIFEST.read_text())
    for group in ['files','generators']:
        for name, expected in data[group].items():
            if digest(ROOT / name) != expected:
                raise ValueError('Changed dependency: ' + name)
print(f'Itch wardrobe: {len(data["files"])} assets verified')
