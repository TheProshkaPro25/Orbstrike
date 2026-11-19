"""Bake Vivi's clean face into Vita's skin palette. Run from the project root."""
import io

import numpy as np
from PIL import Image

from fit_vivi_face import Avatar, ROOT


def skin_pixels(avatar):
    material = avatar.doc["extensions"]["VRM"]["materialProperties"][7]
    assert material["name"] == "F00_000_00_Face_00_SKIN"
    texture = material["textureProperties"]["_MainTex"]
    source = avatar.doc["textures"][texture]["source"]
    view = avatar.doc["bufferViews"][avatar.doc["images"][source]["bufferView"]]
    start = view.get("byteOffset", 0)
    image = Image.open(io.BytesIO(avatar.data[start:start + view["byteLength"]]))
    assert image.size == (1024, 1024)
    return np.array(image.convert("RGBA"))


def smoothstep(start, end, value):
    t = np.clip((value - start) / (end - start), 0, 1)
    return t * t * (3 - 2 * t)


def bake():
    vita = skin_pixels(Avatar("Vita"))
    vivi = skin_pixels(Avatar("Vivi"))
    # The forehead, ears and lower neck have the same shading pattern in both
    # sources. Sample paired texels there to match Vivi's shadows and midtones.
    y = (np.arange(vita.shape[0]) + 0.5) / vita.shape[0]
    reference = (y < 0.35) | (y > 0.91)
    # Vita's cheek ornaments extend to the sides of the UV island. Cover the
    # whole width, feather above the brows and below the chin, and retain the
    # original neck, ears and crown outside this strip.
    weight = (smoothstep(0.35, 0.42, y) * (1 - smoothstep(0.85, 0.91, y)))[:, None]
    result = vita.copy()
    for channel in range(3):
        donor = vivi[..., channel]
        base = vita[..., channel]
        samples = donor[reference]
        levels = np.unique(np.percentile(samples, [1, 10, 30, 50, 70, 90, 99],
                                         method="nearest")).astype(float)
        target = np.array([np.median(base[reference][samples == level]) for level in levels])
        shift = np.interp(np.arange(256), levels, target - levels)
        matched = np.clip(donor + shift[donor], 0, 255)
        result[..., channel] = np.rint(base + weight * (matched - base))
    Image.fromarray(result).save(ROOT / "parts/vivi_face_skin.png")


if __name__ == "__main__":
    bake()
