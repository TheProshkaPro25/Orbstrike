"""Derive quieter game textures from the pinned ScaerieTale denim originals."""
from pathlib import Path
import zipfile
from PIL import Image, ImageFilter, ImageOps
import io

ROOT = Path(__file__).resolve().parents[2]
PALETTE = {'Blue': (70, 100, 145), 'Green': (69, 105, 83),
           'Pink': (159, 99, 119), 'Purple': (108, 87, 137),
           'Yellow': (168, 151, 91), 'Gold': (154, 122, 66)}
with zipfile.ZipFile(ROOT / 'build/itch-character-source/denim/Denim_ALL.zip') as files:
    for name in files.namelist():
        if not name.endswith('.png'):
            continue
        image = Image.open(io.BytesIO(files.read(name))).convert('RGBA')
        variant, _, color = Path(name).stem.split('_')
        base = PALETTE[color]
        factor = {'Dark': .65, 'Bright': 1.05, 'Faded': 1.22}[variant]
        base = tuple(min(255, round(v * factor)) for v in base)
        # Preserve drawn pockets/seams while filtering per-pixel rainbow noise.
        luminance = ImageOps.grayscale(image).filter(ImageFilter.GaussianBlur(1.2))
        texture = ImageOps.colorize(luminance,
                    tuple(round(v*.35) for v in base),
                    tuple(min(255, round(v*1.6)) for v in base)).convert('RGBA')
        texture.putalpha(image.getchannel('A'))
        # Belt and buckle are separate from the dyed denim fabric.
        texture.paste(image.crop((0,0,image.width,105)), (0,0))
        texture.save(ROOT / 'assets/avatars/itch/denim' / Path(name).name)
print('Prepared 14 denim variants; original archive unchanged')
