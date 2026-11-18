"""Paint the source textures for Orbstrike's illustrated harbor using Pillow and NumPy."""
from pathlib import Path
import re

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUTPUT = Path(__file__).resolve().parents[2] / "assets/experiments/illustrated_harbor"
SIZE = 1536
SPAN = 3200
LEVELS = 9
ISLANDS = [
    (-400, -255, 245, 146, -.45, 0), (257, -398, 184, 123, .34, 1),
    (-40, -675, 250, 116, -.55, 2), (652, -191, 258, 154, -.32, 3),
    (-615, 182, 267, 141, .71, 4), (572, 380, 194, 122, .12, 5),
    (-245, 509, 211, 163, -.17, 6), (93, 761, 191, 104, -.17, 7),
    (468, -775, 151, 87, .28, 8), (1019, -480, 173, 97, -.64, 9),
    (-956, -594, 263, 103, .38, 10), (-804, 672, 228, 163, -.28, 11),
    (1043, 575, 291, 121, .78, 12), (1128, 113, 90, 52, .15, 13),
    (-1088, -42, 125, 56, .35, 14), (869, -993, 258, 109, .41, 15),
    (-333, -1138, 316, 167, .13, 16), (224, -1200, 216, 120, 1.04, 17),
    (-1200, 966, 204, 123, .22, 18), (588, 980, 214, 111, -.46, 19),
    (-308, 1070, 141, 84, .18, 20), (994, 1098, 103, 102, .6, 21),
    (278, 233, 57, 32, -.45, 22), (-211, 227, 54, 38, -.37, 23),
    (-194, -328, 31, 21, -.47, 24), (131, -263, 50, 38, -.41, 25),
    (338, 79, 75, 39, .31, 26), (-413, 184, 58, 30, .25, 27),
    (307, -622, 66, 34, -.91, 28), (547, 622, 72, 26, -.11, 29),
]
CLOUD_SCRIPT = OUTPUT.parents[2] / "scenes/experiments/illustrated_harbor/harbor_canvas.gd"
CLOUDS = [
    tuple(map(int, cloud))
    for cloud in re.findall(r"Vector4\((-?\d+), (-?\d+), (\d+), (\d+)\)", CLOUD_SCRIPT.read_text().split("const CLOUDS := [", 1)[1].split("]", 1)[0])
]
GRASS = np.array([
    (84, 142, 81), (109, 161, 81), (133, 181, 89), (145, 188, 96),
    (154, 193, 110), (155, 186, 111), (135, 162, 106), (130, 149, 113), (145, 158, 124),
], dtype=np.float32)


def world_axis() -> np.ndarray:
    return (np.arange(SIZE, dtype=np.float32) + .5) * SPAN / SIZE - SPAN / 2


def island_field(x: np.ndarray, z: np.ndarray) -> np.ndarray:
    depth = np.full((SIZE, SIZE), -9.0, dtype=np.float32)
    for cx, cz, rx, rz, angle, seed in ISLANDS:
        dx, dz = x - cx, z - cz
        u = (dx * np.cos(angle) + dz * np.sin(angle)) / rx
        v = (-dx * np.sin(angle) + dz * np.cos(angle)) / rz
        theta = np.arctan2(v, u)
        rough = .11 * np.sin(3 * theta + seed) + .095 * np.cos(5 * theta + seed * .67)
        # Large bays and headlands, without a pixel-sized sawtooth on the coast.
        rough += .035 * np.sin(9 * theta + seed * .72)
        shore = (1.0 + rough - np.hypot(u, v)) * min(rx, rz)
        ridge = (np.sin(u * 3.5 + seed * .61) + np.cos(v * 4.1 + seed)) * .33
        peak = 2.4 * np.tanh(np.minimum(rx, rz) / 110.0) + .5
        beach_ramp = np.clip(shore / 9.0, 0, 1)
        beach_ramp = beach_ramp * beach_ramp * (3 - 2 * beach_ramp)
        height = np.where(
            shore > 0, np.maximum(.0, .49 + np.maximum(shore, 0) ** .58 * peak / 7.0 + ridge) * beach_ramp,
            shore / 4.6,
        )
        depth = np.maximum(depth, height)
    return depth


def paint_coast(x: np.ndarray, z: np.ndarray, depth: np.ndarray) -> np.ndarray:
    tone = .5 + .5 * np.sin(x * .013) * np.cos(z * .017)
    deep = np.full((*depth.shape, 3), (28, 116, 155), dtype=np.float32)
    deep += tone[..., None] * (3, 5, 6)
    shelf = np.clip((depth + 3.1) / 3.0, 0.0, 1.0)[..., None] ** 1.25
    shallow = np.array([57, 173, 172]) + tone[..., None] * (5, 7, 5)
    sea = deep * (1.0 - shelf) + shallow * shelf
    # The animated shader paints surf; keep the source shore a soft sandy wash.
    sand = np.clip((depth + .05) / .7, 0, 1)[..., None]
    sea = sea * (1 - sand) + np.array([225, 218, 172]) * sand
    return sea


def paint_terrain(x: np.ndarray, z: np.ndarray, depth: np.ndarray) -> Image.Image:
    elevation = np.clip(depth - .7, 0, 8)
    lower = np.int16(elevation)
    blend = (elevation - lower)[..., None]
    color = GRASS[lower] * (1 - blend) + GRASS[np.minimum(lower + 1, 8)] * blend
    # Broad clean meadows meet hard stone outcrops; trees are upright sprites.
    patches = np.sin(x * .051 + np.sin(z * .038) * 1.4) + np.cos(z * .054 - x * .018)
    dark_meadow = np.clip((patches - .30) * 7.0, 0, 1)[..., None]
    pale_meadow = np.clip((-patches - 1.02) * 8.0, 0, 1)[..., None]
    color = color * (1 - dark_meadow * .36) + np.array([91, 151, 79]) * dark_meadow * .36
    color = color * (1 - pale_meadow * .27) + np.array([176, 194, 115]) * pale_meadow * .27
    slope_z, slope_x = np.gradient(depth, SPAN / SIZE)
    slope = np.hypot(slope_x, slope_z)
    stone = np.clip((slope - .12) * 9, 0, 1) * (depth > .8)
    # Restrict rock to steep sections of headlands rather than brown all shores.
    stone *= np.clip((np.sin(x * .018 - z * .023) + .55) * 2, 0, 1)
    rock = np.array([157, 158, 125]) + (np.sin(x * .11 + z * .04) > .3)[..., None] * (15, 13, 9)
    color = color * (1 - stone[..., None]) + rock * stone[..., None]
    return Image.fromarray(np.uint8(np.clip(color, 0, 255)))


def paint_details() -> None:
    atlas = Image.new("RGBA", (128 * 6, 192))
    for variant in range(6):
        # Supersampling antialiases drawn edges without blurring their interior.
        tile = Image.new("RGBA", (256, 384))
        b = ImageDraw.Draw(tile)
        def poly(points, color):
            b.polygon([(x * 2, y * 2) for x, y in points], fill=color)
        if variant < 3:
            poly([(59, 177), (61, 106), (68, 105), (71, 177)], "#665d40")
            poly([(65, 148), (42, 124), (45, 121), (65, 136), (87, 113), (90, 117), (69, 146)], "#665d40")
            if variant == 1:
                poly([(20, 136), (45, 105), (28, 108), (51, 79), (40, 81), (65, 39), (85, 76), (78, 77), (100, 109), (85, 107), (108, 137), (67, 151)], "#286454")
                poly([(20, 136), (45, 105), (28, 108), (51, 79), (40, 81), (65, 39), (62, 115), (76, 135), (53, 133), (46, 143)], "#548b57")
                poly([(41, 83), (65, 39), (63, 68), (53, 82)], "#86ad65")
                poly([(29, 109), (49, 86), (43, 102), (59, 109)], "#76a15e")
            else:
                lobes = [(41, 116, 25), (79, 117, 29), (34, 87, 25), (71, 81, 34), (94, 99, 22), (55, 62, 23)]
                if variant == 2:
                    lobes = [(43, 128, 22), (81, 120, 24), (30, 102, 20), (65, 96, 33), (89, 83, 24), (58, 62, 25)]
                for x, y, r in lobes:
                    b.ellipse(((x-r)*2, (y-r)*2, (x+r)*2, (y+r)*2), fill="#2e7056")
                for x, y, r in lobes[2:]:
                    b.ellipse(((x-r)*2, (y-r)*2, (x+r-6)*2, (y+r-10)*2), fill="#548e58")
                for x, y, r in lobes[3:]:
                    b.ellipse(((x-r+2)*2, (y-r)*2, (x+r-12)*2, (y+r-19)*2), fill="#84ad65")
        else:
            points = [(21, 176), (15, 153), (36, 123), (78, 114), (105, 137), (115, 170), (91, 181), (48, 183)]
            if variant == 4:
                points = [(20, 177), (31, 139), (50, 127), (66, 92), (84, 120), (95, 119), (113, 171), (86, 181)]
            poly(points, "#697a71")
            poly([points[0], points[1], points[2], points[3], (70, 150), (42, 166)], "#b6b799")
            poly([points[3], points[4], points[5], (70, 174), (70, 150)], "#8f9a86")
            b.line([(x*2,y*2) for x,y in [(38,155),(57,151),(62,136)]], fill="#596e65", width=2)
        atlas.paste(tile.resize((128, 192), Image.Resampling.LANCZOS), (variant * 128, 0))
    atlas.save(OUTPUT / "details.png", optimize=True)


def paint_clouds() -> None:
    rng = np.random.default_rng(538)
    atlas = Image.new("RGBA", (768, 144))
    for sprite in range(4):
        cloud = Image.new("RGBA", (192, 144))
        brush = ImageDraw.Draw(cloud)
        lobes = []
        for index in range(9):
            x = 25 + index * 17 + int(rng.integers(-5, 6))
            y = 91 - int((14 + sprite * 6) * np.sin(index * np.pi / 8)) + int(rng.integers(-9, 10))
            radius = int(rng.integers(14, 25))
            lobes.append((x, y, radius))
        lobes += [(72 + sprite * 12, 56 + sprite * 5, 29 - sprite * 2)]
        brush.ellipse((17, 75, 181, 114), fill=(159, 188, 216, 255))
        for x, y, radius in sorted(lobes, key=lambda lobe: lobe[1]):
            brush.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(159, 188, 216, 255))
        brush.polygon([(15, 98), (54, 104), (102, 103), (157, 94), (181, 99), (160, 109), (73, 115), (28, 110)], fill=(204, 225, 233, 255))
        pixels = np.asarray(cloud).copy()
        yy, xx = np.mgrid[:144, :192]
        light = np.clip((102 - yy) / 57 + np.sin(xx * .055 + sprite) * .16, 0, 1)
        pixels[:, :, :3] = np.uint8(
            np.array([169, 202, 219]) + light[:, :, None] * (80, 45, 16)
        )
        cloud = Image.fromarray(pixels)
        brush = ImageDraw.Draw(cloud)
        brush.line([(30, 106), (67, 111), (104, 110), (149, 105)], fill=(202, 225, 232, 255), width=2)
        brush.line([(48, 95), (72, 97), (102, 95)], fill=(231, 239, 233, 255), width=2)
        atlas.paste(cloud.filter(ImageFilter.GaussianBlur(.7)), (sprite * 192, 0))
    atlas.save(OUTPUT / "clouds.png", optimize=True)


def paint_landmarks() -> None:
    image = Image.new("RGBA", (512, 256))
    brush = ImageDraw.Draw(image)
    brush.polygon([(59, 238), (72, 222), (178, 222), (197, 239)], fill="#677c70")
    brush.polygon([(84, 222), (95, 69), (145, 69), (160, 222)], fill="#faf0cc")
    brush.polygon([(132, 69), (145, 69), (160, 222), (132, 222)], fill="#b9c5b7")
    brush.polygon([(91, 118), (148, 118), (152, 151), (89, 151)], fill="#d87855")
    brush.rectangle((90, 60, 149, 80), fill="#264454")
    brush.rectangle((98, 34, 141, 61), fill="#f3d87e")
    brush.polygon([(87, 34), (120, 14), (151, 34)], fill="#b65f4b")
    brush.line([(120, 12), (120, 5)], fill="#304958", width=3)
    for x in [99, 119, 140]:
        brush.line([(x, 35), (x, 61)], fill="#355363", width=3)
    brush.rounded_rectangle((114, 187, 133, 222), radius=7, fill="#365566")
    brush.rectangle((112, 88, 126, 104), fill="#416976")
    brush.rectangle((115, 163, 129, 179), fill="#416976")
    brush.polygon([(284, 210), (467, 210), (434, 232), (311, 232)], fill="#854e43")
    brush.line([(285, 211), (463, 211)], fill="#f8dca0", width=5)
    brush.line([(368, 50), (368, 213)], fill="#654e48", width=4)
    brush.polygon([(361, 62), (361, 195), (291, 195)], fill="#faf1d0")
    brush.polygon([(377, 89), (377, 197), (448, 197)], fill="#e5b584")
    brush.line([(300, 196), (360, 196)], fill="#c6b98c", width=3)
    brush.line([(305, 237), (392, 242), (447, 236)], fill="#c4f4e6", width=3)
    image.save(OUTPUT / "landmarks.png", optimize=True)


def cloud_shadows() -> Image.Image:
    shadows = Image.new("L", (SIZE, SIZE))
    brush = ImageDraw.Draw(shadows)
    for index, (x, z, altitude, width) in enumerate(CLOUDS):
        px = (x + .55 * altitude + SPAN / 2) * SIZE / SPAN
        py = (z + .43 * altitude + SPAN / 2) * SIZE / SPAN
        radius = width * SIZE / SPAN * .37
        for lobe in range(7):
            u = (lobe - 3) / 4
            wx = radius * (.37 + .13 * np.cos(lobe * 1.7 + index))
            wy = radius * (.37 + .18 * np.sin(lobe * .96 + index))
            bx = px + u * radius
            by = py + np.sin(lobe * .86 + index) * radius * .21
            brush.ellipse((bx - wx, by - wy, bx + wx, by + wy), fill=205)
    return shadows.filter(ImageFilter.GaussianBlur(5.5))


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    x, z = np.meshgrid(world_axis(), world_axis())
    depth = island_field(x, z)
    coast = paint_coast(x, z, depth)
    Image.fromarray(np.uint8(np.clip(coast, 0, 255))).save(OUTPUT / "coast.png", optimize=True)
    paint_terrain(x, z, depth).save(OUTPUT / "terrain.png", optimize=True)
    # Keep sub-centimetre elevation in red + alpha; alpha is data, not opacity.
    packed_height = np.uint16(np.clip(depth, 0, LEVELS) * (65535 / LEVELS))
    height = Image.fromarray(np.uint8(packed_height >> 8))
    fine_height = Image.fromarray(np.uint8(packed_height & 255))
    # Blue is a signed shore field for a moving, antialiased surf line.
    shore = Image.fromarray(np.uint8((np.clip(depth, -9, 9) + 9) * (255 / 18)))
    Image.merge("RGBA", (height, cloud_shadows(), shore, fine_height)).save(
        OUTPUT / "map.png", optimize=True,
    )
    paint_clouds()
    paint_landmarks()
    paint_details()


if __name__ == "__main__":
    main()
