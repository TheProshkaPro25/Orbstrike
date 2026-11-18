#!/usr/bin/env python3
"""Package the six animated Ratnik GLBs as one rig/mesh and six color atlases."""

import argparse
from collections import defaultdict
from copy import deepcopy
import json
from pathlib import Path
import struct

import numpy as np

from refine_creature_attachments import fit_ratnik_grip


ELEMENTS = ("fire", "gale", "light", "stone", "shadow", "tide")
ATLAS_SLOTS = (11, 12, 13)
DTYPES = {5121: "<u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
CAPE_FABRIC_SLOT = 12
CAPE_GRID = (21, 27)


def read_glb(path):
    raw = path.read_bytes()
    assert struct.unpack_from("<4sII", raw) == (b"glTF", 2, len(raw)), path
    size, tag = struct.unpack_from("<I4s", raw, 12)
    binary_size, binary_tag = struct.unpack_from("<I4s", raw, 20 + size)
    assert tag == b"JSON" and binary_tag == b"BIN\0" and 28 + size + binary_size == len(raw), path
    return json.loads(raw[20:20 + size]), memoryview(raw)[28 + size:]


def view_bytes(document, binary, index):
    view = document["bufferViews"][index]
    start = view.get("byteOffset", 0)
    return binary[start:start + view["byteLength"]]


def unpack(document, binary, index):
    info = document["accessors"][index]
    assert not info.get("normalized") and "sparse" not in info
    assert "byteStride" not in document["bufferViews"][info["bufferView"]]
    shape = (info["count"], WIDTHS[info["type"]])
    return np.frombuffer(view_bytes(document, binary, info["bufferView"]),
                         dtype=DTYPES[info["componentType"]], count=np.prod(shape),
                         offset=info.get("byteOffset", 0)).reshape(shape)


class Package:
    def __init__(self):
        self.binary = bytearray()
        self.accessors = []
        self.views = []

    def add(self, payload, info, target=None):
        view = {"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(payload)}
        if target is not None:
            view["target"] = target
        index = len(self.accessors)
        self.accessors.append(dict(info, bufferView=len(self.views), byteOffset=0))
        self.views.append(view)
        self.binary.extend(payload)
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        return index

    def add_array(self, values, info, target):
        info = {key: info[key] for key in ("type", "componentType")}
        info["count"] = len(values)
        if target == 34963:
            info["componentType"] = 5123 if values.max() <= 65535 else 5125
            values = values.astype(DTYPES[info["componentType"]])
        elif values.dtype.kind == "f" and info["type"] == "VEC3":
            info["min"] = values.min(axis=0).tolist()
            info["max"] = values.max(axis=0).tolist()
        return self.add(values.tobytes(), info, target)

    def write(self, path, document):
        document.update(accessors=self.accessors, bufferViews=self.views,
                        buffers=[{"byteLength": len(self.binary)}])
        content = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()
        content += b" " * (-len(content) % 4)
        with path.open("wb") as stream:
            stream.write(struct.pack("<4sIII4s", b"glTF", 2, len(content) + len(self.binary) + 28,
                                     len(content), b"JSON"))
            stream.write(content)
            stream.write(struct.pack("<I4s", len(self.binary), b"BIN\0"))
            stream.write(self.binary)


def bake_cape_grid(positions, joints, weights, directory):
    """Sample the long drape in rest space without reducing the rendered mesh."""
    columns, rows = CAPE_GRID
    ymin, ymax = positions[:, 1].min(), positions[:, 1].max()
    heights = np.linspace(ymin, ymax, rows)
    stride = heights[1] - heights[0]
    bounds = np.array([
        np.quantile(positions[np.abs(positions[:, 1] - height) < stride / 2, 0], [0, 1])
        for height in heights
    ])
    grid = []
    influences = np.unique(joints[weights > 0])
    assert len(influences) == 4
    grid_weights = []
    for row, height in enumerate(heights):
        for x in np.linspace(*bounds[row], columns):
            distance = np.square(positions[:, :2] - [x, height]).sum(axis=1)
            nearest = np.argpartition(distance, 7)[:8]
            blend = 1 / (distance[nearest] + 1e-7)
            blend /= blend.sum()
            z = positions[nearest, 2] @ blend
            grid.append((x, height, z))
            grid_weights.extend(np.sum(
                ((joints[nearest, :, None] == influences) * weights[nearest, :, None]).sum(axis=1)
                * blend[:, None], axis=0))
    grid = np.array(grid)
    # Keep the neckline and shoulders fixed. The lower folds get most of the travel.
    mobility = np.clip((1.43 - grid[:, 1]) / 1.04, 0, 1)
    mobility = 0.88 * mobility * mobility * (3 - 2 * mobility)
    floats = lambda values: ", ".join(f"{value:.8f}" for value in np.ravel(values))
    resource = '[gd_resource type="Resource" format=3]\n\n[resource]\n'
    resource += f"metadata/size = Vector2i({columns}, {rows})\n"
    resource += f"metadata/points = PackedVector3Array({floats(grid)})\n"
    resource += f"metadata/mobility = PackedFloat32Array({floats(mobility)})\n"
    resource += f"metadata/binds = PackedInt32Array({', '.join(map(str, influences))})\n"
    resource += f"metadata/weights = PackedFloat32Array({floats(grid_weights)})\n"
    (directory / "cape_grid.tres").write_text(resource)
    return heights, bounds


def cape_grid_uv(positions, heights, bounds):
    y = positions[:, 1]
    left = np.interp(y, heights, bounds[:, 0])
    right = np.interp(y, heights, bounds[:, 1])
    u = (positions[:, 0] - left) / (right - left)
    v = (y - heights[0]) / (heights[-1] - heights[0])
    return np.clip(np.stack((u, v), axis=1), 0, 1).astype("<f4")


def pack_meshes(original, binary, output, package, directory):
    rig = original["scenes"][0]["nodes"][0]
    joints = original["skins"][0]["joints"]
    assert len(joints) == len(set(joints)) == 23 and sorted(joints) == list(range(23))
    sword_joint = next(index for index, node in enumerate(joints) if original["nodes"][node]["name"] == "sword")
    root_bones = []
    groups = {"RatnikBody": defaultdict(list), "RatnikCape": defaultdict(list)}
    for index in original["nodes"][rig]["children"]:
        node = original["nodes"][index]
        if index in joints:
            root_bones.append(index)
            continue
        assert set(node) == {"name", "mesh", "skin"} and node["skin"] == 0
        name = "RatnikCape" if node["name"] == "Ратник · Плащ" else "RatnikBody"
        for primitive in original["meshes"][node["mesh"]]["primitives"]:
            assert set(primitive) == {"attributes", "indices", "material"}
            groups[name][primitive["material"]].append(primitive)

    output["nodes"] = [deepcopy(original["nodes"][i]) for i in range(len(joints))]
    output["scenes"] = [{"name": "Ratnik TRELLIS.2", "nodes": [len(joints)]}]
    rig_nodes = root_bones.copy()
    output["nodes"].append({"name": "RatnikRig", "children": rig_nodes})
    output["meshes"] = []
    triangles = 0
    for name, surfaces in groups.items():
        mapping = None
        if name == "RatnikCape":
            cape = surfaces[CAPE_FABRIC_SLOT]
            mapping = bake_cape_grid(*[
                np.concatenate([unpack(original, binary, p["attributes"][key]) for p in cape])
                for key in ("POSITION", "JOINTS_0", "WEIGHTS_0")
            ], directory)
        packed_primitives = []
        for material, primitives in sorted(surfaces.items()):
            attributes = primitives[0]["attributes"]
            assert all(p["attributes"].keys() == attributes.keys() for p in primitives)
            streams = {attribute: [] for attribute in attributes}
            indices = []
            offset = 0
            for primitive in primitives:
                for attribute, index in primitive["attributes"].items():
                    streams[attribute].append(unpack(original, binary, index))
                indices.append(unpack(original, binary, primitive["indices"]).astype("<u4") + offset)
                offset += len(streams["POSITION"][-1])
            arrays = {attribute: np.concatenate(values) for attribute, values in streams.items()}
            if name == "RatnikBody":
                fit_ratnik_grip(arrays, sword_joint)
            packed = {}
            for attribute, values in arrays.items():
                info = original["accessors"][attributes[attribute]]
                packed[attribute] = package.add_array(values, info, 34962)
            if mapping is not None:
                assert "TEXCOORD_1" not in packed
                grid_uv = cape_grid_uv(arrays["POSITION"], *mapping)
                packed["TEXCOORD_1"] = package.add_array(grid_uv, {"type": "VEC2", "componentType": 5126}, 34962)
            joined = np.concatenate(indices)
            triangles += len(joined) // 3
            packed_primitives.append({"attributes": packed, "material": material,
                                      "indices": package.add_array(joined, {"type": "SCALAR",
                                                                          "componentType": 5125}, 34963)})
        rig_nodes.append(len(output["nodes"]))
        output["nodes"].append({"name": name, "mesh": len(output["meshes"]), "skin": 0})
        output["meshes"].append({"name": name, "primitives": packed_primitives})
    assert triangles == 250760
    return triangles


def copy_animation_accessors(document, binary, animations, package):
    copied = {}
    animations = deepcopy(animations)
    for animation in animations:
        for sampler in animation["samplers"]:
            for field in ("input", "output"):
                index = sampler[field]
                if index not in copied:
                    info = document["accessors"][index]
                    assert not info.get("byteOffset")
                    copied[index] = package.add(view_bytes(document, binary, info["bufferView"]), info)
                sampler[field] = copied[index]
    return animations


def pack_motion(original, binary, output, package, guard_motion=None):
    for skin in output["skins"]:
        info = original["accessors"][skin["inverseBindMatrices"]]
        assert not info.get("byteOffset")
        skin["inverseBindMatrices"] = package.add(view_bytes(original, binary, info["bufferView"]), info)
    names = {a["name"] for a in original["animations"]}
    assert names == {"idle", "stance", "roar", "attack", "hit"}
    retained = original["animations"]
    updated = []
    if guard_motion is not None:
        guard, guard_binary = read_glb(guard_motion)
        joints = original["skins"][0]["joints"]
        assert guard["skins"][0]["joints"] == joints
        assert all(guard["nodes"][index] == original["nodes"][index] for index in joints)
        for source_skin, revised_skin in zip(original["skins"], guard["skins"], strict=True):
            np.testing.assert_array_equal(unpack(original, binary, source_skin["inverseBindMatrices"]),
                                          unpack(guard, guard_binary, revised_skin["inverseBindMatrices"]))
        guard_clips = {"idle", "stance"}
        retained = [clip for clip in retained if clip["name"] not in guard_clips]
        updated = [clip for clip in guard["animations"] if clip["name"] in guard_clips]
        assert {clip["name"] for clip in updated} == guard_clips
        assert all(channel["target"]["node"] in joints for clip in updated for channel in clip["channels"])
        updated = copy_animation_accessors(guard, guard_binary, updated, package)
    clips = copy_animation_accessors(original, binary, retained, package) + updated
    by_name = {clip["name"]: clip for clip in clips}
    output["animations"] = [by_name[clip["name"]] for clip in original["animations"]]


def encode_srgb(value):
    return value * 12.92 if value <= .0031308 else 1.055 * value ** (1 / 2.4) - .055


def pack_palettes(source, directory, original, binary):
    headers, entries = [], []
    image_views = {image["bufferView"] for image in original["images"]}
    for element in ELEMENTS:
        document, payload = read_glb(source / f"ratnik_{element}.glb")
        for section in ("nodes", "skins", "animations", "meshes", "accessors"):
            assert document[section] == original[section], (element, section)
        for index in range(len(original["bufferViews"])):
            if index not in image_views:
                assert view_bytes(document, payload, index) == view_bytes(original, binary, index), (element, index)
        assert len(document["materials"]) == 19
        slots = set()
        colors = []
        for index, material in enumerate(document["materials"]):
            pbr = material["pbrMetallicRoughness"]
            linear = pbr.get("baseColorFactor", [1, 1, 1, 1])
            color = [encode_srgb(value) for value in linear[:3]] + linear[3:]
            colors.extend(f"{value:.8f}" for value in color)
            if "baseColorTexture" in pbr:
                slot = pbr["baseColorTexture"]
                assert set(slot) == {"index"}
                assert index in ATLAS_SLOTS
                slots.add(document["textures"][slot["index"]]["source"])
        assert len(slots) == 1
        atlas = document["images"][slots.pop()]
        assert atlas["mimeType"] == "image/png"
        (directory / f"{element}.png").write_bytes(view_bytes(document, payload, atlas["bufferView"]))
        headers.append(f'[ext_resource type="Texture2D" path="res://assets/creatures_hd/ratnik_trellis/{element}.png" id="{element}"]')
        entries.append(f'"{element}": [ExtResource("{element}"), PackedColorArray({", ".join(colors)})]')
    resource = '[gd_resource type="Resource" format=3]\n\n' + "\n".join(headers)
    resource += "\n\n[resource]\nmetadata/element_palettes = {\n" + ",\n".join(entries) + "\n}\n"
    (directory / "palettes.tres").write_text(resource)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="directory containing the six animated GLBs")
    parser.add_argument("output", type=Path, help="assets/creatures_hd/ratnik_trellis directory")
    parser.add_argument("--guard-motion", type=Path, help="GLB with revised idle and stance on the same rig")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    original, binary = read_glb(args.source / "ratnik_light.glb")
    pack_palettes(args.source, args.output, original, binary)
    output = {k: deepcopy(original[k]) for k in ("asset", "scene", "skins", "animations")}
    # The game uses the color atlas and converts all HD surfaces to the anime shader.
    output["materials"] = [{"name": f"RatnikSlot{index:02}", "doubleSided": True}
                           for index in range(len(original["materials"]))]
    package = Package()
    triangles = pack_meshes(original, binary, output, package, args.output)
    pack_motion(original, binary, output, package, args.guard_motion)
    package.write(args.output / "ratnik.glb", output)
    print(f"{triangles:,} triangles, two skinned meshes, five clips, six unchanged color atlases")


if __name__ == "__main__":
    main()
