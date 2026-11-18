"""Refine the right-hand grip of Ratnik and tuck Armat's hind thighs under the shell."""

import argparse
import json
from pathlib import Path
import struct

import numpy as np

from inspect_geometry import read_glb


ELEMENTS = ("fire", "gale", "light", "stone", "shadow", "tide")
COMPONENT_TYPES = {5126: "<f4", 5123: "<u2", 5121: "u1"}
WIDTHS = {"VEC2": 2, "VEC3": 3, "VEC4": 4}


def _smoothstep(y, low, high):
    amount = np.clip((y - low) / (high - low), 0., 1.)
    value = amount ** 2 * (3. - 2. * amount)
    derivative = 6. * amount * (1. - amount) / (high - low)
    return value, derivative


def _warp(arrays, mask, offset, derivative):
    arrays["POSITION"][mask] += offset
    # The offset varies along Y. Transform normals with the inverse transpose
    # of the local derivative so the old texture keeps its original shading.
    normals = arrays["NORMAL"][mask]
    normals[:, 1] = (normals[:, 1] - normals[:, 0] * derivative[:, 0]
                      - normals[:, 2] * derivative[:, 2]) / (1. + derivative[:, 1])
    arrays["NORMAL"][mask] = normals / np.linalg.norm(normals, axis=1)[:, None]
    if "TANGENT" in arrays:
        tangents = arrays["TANGENT"][mask, :3]
        tangents += tangents[:, 1, None] * derivative
        arrays["TANGENT"][mask, :3] = tangents / np.linalg.norm(tangents, axis=1)[:, None]


def fit_ratnik_grip(arrays, sword_joint):
    """Seat the crossguard against the fingers and join the grip at the palm."""
    y = arrays["POSITION"][:, 1]
    sword_weight = np.where(arrays["JOINTS_0"] == sword_joint, arrays["WEIGHTS_0"], 0.).sum(axis=1)
    mask = (sword_weight > .999) & (y < .951)
    if not mask.any():
        return
    taper, derivative = _smoothstep(y[mask], .852, .951)
    offset = np.broadcast_to((.012, .042, -.006), (int(mask.sum()), 3))
    _warp(arrays, mask, offset * (1. - taper[:, None]), -offset * derivative[:, None])


def _accessor_view(document, binary, index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    dtype = np.dtype(COMPONENT_TYPES[accessor["componentType"]])
    width = WIDTHS[accessor["type"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", width * dtype.itemsize)
    return np.ndarray((accessor["count"], width), dtype, binary, offset, (stride, dtype.itemsize))


def refine_armat_hips(source, output):
    document, binary = read_glb(source)
    binary = bytearray(binary)
    joints = {document["nodes"][node]["name"]: index for index, node in enumerate(document["skins"][0]["joints"])}
    hind_joints = (joints["hind_upper.L"], joints["hind_upper.R"])
    moved = 0
    for primitive in document["meshes"][0]["primitives"]:
        attributes = primitive["attributes"]
        arrays = {name: _accessor_view(document, binary, attributes[name])
                  for name in ("POSITION", "NORMAL", "TANGENT", "JOINTS_0", "WEIGHTS_0") if name in attributes}
        points = arrays["POSITION"]
        rear = np.isin(arrays["JOINTS_0"], hind_joints)
        mask = (np.where(rear, arrays["WEIGHTS_0"], 0.).sum(axis=1) > .01) & (points[:, 1] > .34)
        if not mask.any():
            continue
        y = points[mask, 1]
        inward = -np.sign(points[mask, 0])
        taper, derivative = _smoothstep(y, .34, .575)
        directions = np.column_stack((.145 * inward, np.full_like(y, -.085), np.zeros_like(y)))
        offset = directions * taper[:, None]
        gradient = directions * derivative[:, None]
        # An extra tuck at the lower fold keeps the side scute in front while roaring.
        enter, enter_gradient = _smoothstep(y, .34, .385)
        leave, leave_gradient = _smoothstep(y, .42, .505)
        offset[:, 0] += .075 * inward * enter * (1. - leave)
        gradient[:, 0] += .075 * inward * (enter_gradient * (1. - leave) - enter * leave_gradient)
        if document["materials"][primitive["material"]]["name"] == "MAT_Armat_Stone":
            # Keep the hard scute on the outside of its underlying thigh.
            offset *= .8
            gradient *= .8
        _warp(arrays, mask, offset, gradient)
        accessor = document["accessors"][attributes["POSITION"]]
        accessor["min"], accessor["max"] = points.min(axis=0).tolist(), points.max(axis=0).tolist()
        moved += int(mask.sum())
    assert moved > 0, source
    encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()
    encoded += b" " * (-len(encoded) % 4)
    with output.open("wb") as target:
        target.write(struct.pack("<4sIII4s", b"glTF", 2, len(encoded) + len(binary) + 28, len(encoded), b"JSON"))
        target.write(encoded)
        target.write(struct.pack("<I4s", len(binary), b"BIN\0"))
        target.write(binary)
    return moved


def main():
    parser = argparse.ArgumentParser(description="Refine the hind-hip seam in Armat's six baked GLBs.")
    parser.add_argument("source", type=Path, help="directory containing the six master palette exports")
    parser.add_argument("output", type=Path, help="destination for the revised GLBs")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for element in ELEMENTS:
        name = f"armat_{element}.glb"
        source, output = args.source / name, args.output / name
        if source.resolve() == output.resolve():
            parser.error("use the unchanged master exports as inputs")
        print(name, refine_armat_hips(source, output), "adjusted vertices")


if __name__ == "__main__":
    main()
