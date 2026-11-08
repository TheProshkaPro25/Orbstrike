"""Read-only CPU raw-rest contact sheets; no Godot, graphics session or asset writes.

Output is a technical preview of GLB POSITION/NORMAL/baseColor in mesh-node rest
transforms. It does not reproduce Godot's shader, skeleton/support, cloth, arena,
camera, or gameplay. PNG portrait sheets use the shipped images without alteration.
"""
from __future__ import annotations

import io
import hashlib
import json
import math
import struct
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/checks/ui-model-audit-2026-11-06"
SIZE = 320
DTYPES = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path, stats=None):
    blob = path.read_bytes()
    length, _ = struct.unpack_from("<II", blob, 12)
    doc = json.loads(blob[20:20 + length])
    offset = 20 + length
    binary_length, _ = struct.unpack_from("<II", blob, offset)
    binary = blob[offset + 8:offset + 8 + binary_length]

    def accessor(index):
        a = doc["accessors"][index]
        v = doc["bufferViews"][a["bufferView"]]
        dtype = np.dtype(DTYPES[a["componentType"]])
        width = WIDTHS[a["type"]]
        offset = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = v.get("byteStride", dtype.itemsize * width)
        return np.ndarray((a["count"], width), dtype=dtype, buffer=binary,
                          offset=offset, strides=(stride, dtype.itemsize)).copy()

    parents = {child: index for index, node in enumerate(doc["nodes"]) for child in node.get("children", [])}
    matrices = {}

    def transform(index):
        if index in matrices:
            return matrices[index]
        node = doc["nodes"][index]
        if "matrix" in node:
            m = np.array(node["matrix"]).reshape(4, 4).T
        else:
            x, y, z, w = node.get("rotation", [0, 0, 0, 1])
            r = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                          [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                          [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
            m = np.eye(4)
            m[:3, :3] = r @ np.diag(node.get("scale", [1, 1, 1]))
            m[:3, 3] = node.get("translation", [0, 0, 0])
        if index in parents:
            m = transform(parents[index]) @ m
        matrices[index] = m
        return m

    primitives = []
    for index, node in enumerate(doc["nodes"]):
        if "mesh" not in node:
            continue
        matrix = transform(index)
        if stats is not None and "skin" in node:
            skin = doc["skins"][node["skin"]]
            inverse_binds = accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
            deviations = [float(np.max(abs(transform(joint) @ inverse_bind-matrix)))
                          for joint, inverse_bind in zip(skin["joints"], inverse_binds)]
            stats.setdefault("rest_skin_max_matrix_error", []).append(max(deviations))
        for primitive in doc["meshes"][node["mesh"]]["primitives"]:
            attrs = primitive["attributes"]
            positions = accessor(attrs["POSITION"]).astype(np.float64)
            positions = positions @ matrix[:3, :3].T + matrix[:3, 3]
            normals = accessor(attrs["NORMAL"]).astype(np.float64)
            normals = normals @ np.linalg.inv(matrix[:3, :3])
            normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
            uv = accessor(attrs["TEXCOORD_0"])
            faces = accessor(primitive["indices"]).reshape(-1, 3)
            material = doc["materials"][primitive.get("material", 0)]
            pbr = material.get("pbrMetallicRoughness", {})
            factor = np.array(pbr.get("baseColorFactor", [1, 1, 1, 1])[:3])
            tex = None
            if "baseColorTexture" in pbr:
                image_index = doc["textures"][pbr["baseColorTexture"]["index"]]["source"]
                view = doc["bufferViews"][doc["images"][image_index]["bufferView"]]
                start = view.get("byteOffset", 0)
                tex = np.asarray(Image.open(io.BytesIO(binary[start:start+view["byteLength"]])).convert("RGB"))
            primitives.append((positions, normals, uv, faces, tex, factor))
    return primitives


def render(primitives, azimuth, elevation=.15):
    eye = np.array([math.sin(azimuth), elevation, math.cos(azimuth)])
    eye /= np.linalg.norm(eye)
    right = np.cross([0, 1, 0], eye)
    right /= np.linalg.norm(right)
    up = np.cross(eye, right)
    projection = np.stack([right, -up, eye], axis=1)
    all_positions = np.concatenate([x[0] for x in primitives])
    projected = all_positions @ projection
    low, high = projected[:, :2].min(axis=0), projected[:, :2].max(axis=0)
    center = (low + high) / 2
    scale = (SIZE - 32) / max(high - low)
    depth = np.full(SIZE*SIZE, -np.inf)
    canvas = np.full((SIZE*SIZE, 3), [27, 34, 44], dtype=np.uint8)
    light = np.array([-.4, .7, .8]); light /= np.linalg.norm(light)
    for positions, normals, uv, faces, texture, factor in primitives:
        points = positions @ projection
        points[:, :2] = (points[:, :2] - center) * scale + SIZE/2
        triangles = points[faces]
        shades = .40 + .60*np.maximum(0, normals @ light)
        shades = shades[faces]
        triangle_uv = uv[faces]
        bounds0 = np.maximum(np.floor(triangles[:, :, :2].min(axis=1)).astype(int), 0)
        bounds1 = np.minimum(np.ceil(triangles[:, :, :2].max(axis=1)).astype(int), SIZE-1)
        widths = bounds1[:, 0] - bounds0[:, 0] + 1
        heights = bounds1[:, 1] - bounds0[:, 1] + 1
        bins = np.ceil(np.log2(np.maximum(widths, 1))).astype(int)*16 + np.ceil(np.log2(np.maximum(heights, 1))).astype(int)
        for key in np.unique(bins):
            selected = np.flatnonzero((bins == key) & (widths > 0) & (heights > 0))
            w, h = 2**(key//16), 2**(key % 16)
            batch = max(1, 2_000_000//(w*h))
            grid_y, grid_x = np.mgrid[:h, :w]
            for begin in range(0, len(selected), batch):
                s = selected[begin:begin+batch]
                tri = triangles[s]
                xx = bounds0[s, 0, None, None] + grid_x[None] + .5
                yy = bounds0[s, 1, None, None] + grid_y[None] + .5
                a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
                denominator = (b[:, 1]-c[:, 1])*(a[:, 0]-c[:, 0])+(c[:, 0]-b[:, 0])*(a[:, 1]-c[:, 1])
                denominator = np.where(abs(denominator)>1e-14, denominator, np.nan)[:, None, None]
                u = ((b[:, 1]-c[:, 1])[:, None, None]*(xx-c[:, 0,None,None])+(c[:, 0]-b[:, 0])[:,None,None]*(yy-c[:,1,None,None]))/denominator
                v = ((c[:, 1]-a[:, 1])[:, None, None]*(xx-c[:, 0,None,None])+(a[:, 0]-c[:, 0])[:,None,None]*(yy-c[:,1,None,None]))/denominator
                z = u*a[:,2,None,None]+v*b[:,2,None,None]+(1-u-v)*c[:,2,None,None]
                mask = (u >= -1e-6) & (v >= -1e-6) & (u+v <= 1.000001) & (xx < SIZE) & (yy < SIZE)
                fi, gy, gx = np.nonzero(mask)
                if not len(fi): continue
                pixels = (yy[fi,gy,gx].astype(int)*SIZE + xx[fi,gy,gx].astype(int))
                zz = z[fi,gy,gx]
                np.maximum.at(depth, pixels, zz)
                visible = zz >= depth[pixels]-1e-10
                fi, gy, gx, pixels = fi[visible],gy[visible],gx[visible],pixels[visible]
                shade = (u[fi,gy,gx]*shades[s[fi],0]+v[fi,gy,gx]*shades[s[fi],1]+(1-u[fi,gy,gx]-v[fi,gy,gx])*shades[s[fi],2])
                if texture is not None:
                    uu, vv = u[fi,gy,gx,None], v[fi,gy,gx,None]
                    # All 145 shipped GLB texture samplers use CLAMP_TO_EDGE.
                    fragment_uv = np.clip(uu*triangle_uv[s[fi],0]+vv*triangle_uv[s[fi],1]+(1-uu-vv)*triangle_uv[s[fi],2],0.,1.)
                    coords = fragment_uv*np.array([texture.shape[1],texture.shape[0]])-.5
                    low = np.floor(coords).astype(int); frac = coords-low
                    x0,x1 = np.clip(low[:,0],0,texture.shape[1]-1), np.clip(low[:,0]+1,0,texture.shape[1]-1)
                    y0,y1 = np.clip(low[:,1],0,texture.shape[0]-1), np.clip(low[:,1]+1,0,texture.shape[0]-1)
                    fx,fy=frac[:,0,None],frac[:,1,None]
                    colors = (texture[y0,x0]*(1-fx)+texture[y0,x1]*fx)*(1-fy)+(texture[y1,x0]*(1-fx)+texture[y1,x1]*fx)*fy
                else:
                    colors = np.full((len(fi),3),190.)
                canvas[pixels] = np.clip(colors*factor*shade[:,None],0,255).astype(np.uint8)
    return Image.fromarray(canvas.reshape(SIZE, SIZE, 3))


def contact(items, path, title, cell=(220, 250), columns=7):
    width, height = cell
    sheet = Image.new("RGB", (columns*width, 58+math.ceil(len(items)/columns)*height), "#111821")
    draw = ImageDraw.Draw(sheet)
    draw.text((14, 12), title, fill="white")
    draw.text((14, 30), "2026-11-06 | current source assets | raw rest != Godot gameplay", fill="#b8c4d4")
    for i, (label, image) in enumerate(items):
        x, y = (i % columns)*width, 58+(i//columns)*height
        image = image.convert("RGB"); image.thumbnail((width-10, height-32), Image.Resampling.LANCZOS)
        sheet.paste(image, (x+(width-image.width)//2, y+(height-32-image.height)//2))
        draw.text((x+5, y+height-25), label, fill="white")
    sheet.save(path)


def main():
    global SIZE
    OUT.mkdir(parents=True, exist_ok=True)
    portraits = sorted((ROOT/"assets/portraits/creatures").glob("*.png"))
    contact([(p.stem, Image.open(p)) for p in portraits], OUT/"portraits49.png", "49 SHIPPED 2D PORTRAITS (256px source; composition sheet)")
    report = {"date": "2026-11-06", "kind": "CPU raw-rest technical preview; no Godot/animation/cloth/support/arena", "models": []}
    front, back = [], []
    for path in sorted((ROOT/"assets/creatures_hd").glob("*.glb")):
        start = time.monotonic()
        stats = {}
        primitives = read_glb(path, stats)
        a = render(primitives, .35)
        b = render(primitives, math.pi+.45)
        a.save(OUT/(path.stem+"_raw_front.png"))
        b.save(OUT/(path.stem+"_raw_back.png"))
        front.append((path.stem, a)); back.append((path.stem, b))
        count = sum(len(p[3]) for p in primitives)
        report["models"].append({"id": path.stem, "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                 "triangles": count, "seconds": round(time.monotonic()-start, 2), **stats})
        print(path.stem, count, round(time.monotonic()-start, 2), flush=True)
    contact(front, OUT/"raw49-front.png", "49 RAW GLB REST | FRONT THREE-QUARTER | CPU ALBEDO + NORMAL LIGHT")
    contact(back, OUT/"raw49-back.png", "49 RAW GLB REST | REAR THREE-QUARTER | CPU ALBEDO + NORMAL LIGHT")
    comparisons = []
    for name, raw in front:
        art = Image.open(ROOT/"assets/portraits/creatures"/(name+".png")).convert("RGB")
        row = Image.new("RGB", (640, 320), "#1b222c")
        art.thumbnail((320,320));row.paste(art,((320-art.width)//2,(320-art.height)//2));row.paste(raw,(320,0))
        comparisons.append((name,row))
    contact(comparisons,OUT/"reference-raw49.png","49 PAIRS: SHIPPED 2D CONCEPT / CPU RAW REST",cell=(440,250),columns=4)
    # Large source-form comparisons. These are source diagnostics, not GPU tests.
    picks = ["rogozhuk_fire","rogozhuk_light","rogozhuk_tide","levian_gale",
             "klykar_gale","kolossar_shadow","kolossar_gale","ratnik_light"]
    details = []
    SIZE = 768
    for name in picks:
        primitives = read_glb(ROOT/"assets/creatures_hd"/(name+".glb"))
        for azimuth, label in [(.8,"front"),(2.35,"side"),(3.6,"back")]:
            image = render(primitives, azimuth)
            image.save(OUT/(name+"_raw_detail_"+label+".png"))
            details.append((name+" "+label,image))
    contact(details,OUT/"raw-details.png","RAW REST CLOSEUPS: 8 SOURCE DESIGNS; NO RUNTIME",cell=(330,360),columns=3)
    focused=[]
    for name in ["ratnik_light","kolossar_shadow","klykar_gale","levian_gale"]:
        art=Image.open(ROOT/"assets/portraits/creatures"/(name+".png")).convert("RGB")
        art.thumbnail((380,380)); pair=Image.new("RGB",(768,384),"#1b222c")
        pair.paste(art,((384-art.width)//2,(384-art.height)//2))
        raw=Image.open(OUT/(name+"_raw_detail_front.png"));raw.thumbnail((384,384));pair.paste(raw,(384,0))
        focused.append((name+" | concept / raw rest",pair))
    contact(focused,OUT/"source-design-four-pairs.png","4 SOURCE DESIGN COMPARISONS | LEFT: 2D; RIGHT: CPU GLB REST",cell=(768,416),columns=2)
    report["portrait_sha256"] = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in portraits}
    report["script_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    (OUT/"raw-report.json").write_text(json.dumps(report,indent=2))


if __name__ == "__main__":
    main()
