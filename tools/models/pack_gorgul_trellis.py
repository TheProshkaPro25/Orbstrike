#!/usr/bin/env python3
"""Fit the legacy Shadow Gorgul rig and motions to the new TRELLIS.2 surface."""

import argparse
from collections import defaultdict
from copy import deepcopy
from pathlib import Path
import sys
import tempfile

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from inspect_geometry import accessor, read_glb
from pack_ratnik_trellis import Package
from upgrade_rigs import globals_of, qconj, qfraction, qmul


CENTRAL_JOINTS = {
    "root": (0, .60, .12),
    "hips": (0, .93, .16),
    "chest": (0, 1.28, .23),
    "neck": (0, 1.52, .28),
    "head": (0, 1.66, .37),
    "tail1": (0, .79, -.04),
    "tail2": (.28, .29, -.40),
}
PAIRED_JOINTS = {
    "arm": (.28, 1.40, .36),
    "forearm": (.52, 1.12, .36),
    "hand": (.64, .88, .44),
    "thigh": (.22, .92, .14),
    "shin": (.34, .62, .29),
    "foot": (.40, .17, .21),
    "wing": (.21, 1.47, -.04),
    "wingtip": (.65, 2.08, -.18),
    "wingfan": (1.22, 1.45, -.58),
}
LEADS = {"root": "hips", "hips": "chest", "chest": "neck", "neck": "head",
         "tail1": "tail2"}
for side in ("L", "R"):
    LEADS.update({f"{first}.{side}": f"{second}.{side}"
                  for first, second in (("arm", "forearm"), ("forearm", "hand"),
                                        ("thigh", "shin"), ("shin", "foot"),
                                        ("wing", "wingtip"), ("wingtip", "wingfan"))})
CLIPS = {"idle", "stance", "roar", "attack", "hit"}


def smooth(value, lower, upper):
    t = np.clip((value - lower) / (upper - lower), 0, 1)
    return t * t * (3 - 2 * t)


def segment_distance(points, start, end):
    offset = points - start
    direction = np.subtract(end, start)
    progress = np.clip(offset @ direction / (direction @ direction), 0, 1)
    return np.linalg.norm(offset - progress[:, None] * direction, axis=1)


def wing_colors(points, colors):
    """Paint the wing rim and rib in the sculpt's rest-space silhouette."""
    x, y, z = points.T
    lateral = abs(x)
    depth = 1 - smooth(z, .045, .19)
    root = smooth(lateral, .29, .52) * smooth(y, 1.25, 1.41) * depth
    outer = smooth(lateral, .58, .80) * smooth(y, .76, .94) * depth
    membrane = np.maximum(root, outer)
    profile = np.column_stack((lateral, y))
    leading_edge = ((.59, 2.14), (.91, 1.98), (1.34, 1.68),
                    (1.56, 1.29), (1.64, .94))
    rim = np.minimum.reduce([segment_distance(profile, a, b)
                             for a, b in zip(leading_edge, leading_edge[1:])])
    middle_rib = ((.60, 2.10), (.79, 1.78), (.94, 1.37), (1.01, .95))
    rib = np.minimum.reduce([segment_distance(profile, a, b)
                             for a, b in zip(middle_rib, middle_rib[1:])])
    line = np.maximum(.46 * (1 - smooth(rim, .016, .068)),
                      .32 * (1 - smooth(rib, .012, .056)))
    purple = np.array((.121, .039, .151)) * (1 - line[:, None])
    rgb = colors + (.62 * membrane[:, None]) * (purple - colors)
    # The game uses inverse alpha as a diffuse-light mask on an opaque mesh.
    return np.column_stack((rgb, 1 - membrane)).astype('<f4')


def decimate(source, destination):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new("Client triangle budget", "DECIMATE")
        modifier.ratio = .16 if "поверхность TRELLIS.2" in obj.name else .28
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.export_scene.gltf(filepath=str(destination), export_format="GLB", export_all_vertex_colors=True)


def quaternion_between(unit_from, unit_to):
    result = np.r_[np.cross(unit_from, unit_to), 1 + np.dot(unit_from, unit_to)]
    assert np.linalg.norm(result) > 1e-4
    return result / np.linalg.norm(result)


def fitted_rig(original):
    output = {key: deepcopy(original[key]) for key in ("asset", "scene", "scenes", "nodes", "skins", "animations")}
    output["asset"]["extras"] = {"source": "Gorgul Shadow TRELLIS.2, 2026-11-15",
                                "motion": "Legacy Gorgul Shadow, fitted rest and binds"}
    old_world = globals_of(original)
    skin = output["skins"][0]
    bones = {output["nodes"][index]["name"]: index for index in skin["joints"]}
    parents = {child: index for index, node in enumerate(original["nodes"])
               for child in node.get("children", ())}
    assert len(bones) == len(CENTRAL_JOINTS) + 2 * len(PAIRED_JOINTS)
    pivots = dict(CENTRAL_JOINTS)
    for side, sign in (("L", -1), ("R", 1)):
        for part, (x, y, z) in PAIRED_JOINTS.items():
            pivots[f"{part}.{side}"] = (sign * x, y, z)

    rotations = {}
    for name, index in bones.items():
        parent = parents.get(index)
        rotation = np.array(original["nodes"][index].get("rotation", (0, 0, 0, 1)))
        if parent in rotations:
            rotation = qmul(rotations[parent], rotation)
        rotations[index] = rotation
    # The hierarchy is ordered from roots to tips in skin.joints.
    fitted_rotation = rotations.copy()
    for name, next_name in LEADS.items():
        index = bones[name]
        old_direction = old_world[bones[next_name]][:3, 3] - old_world[index][:3, 3]
        new_direction = np.subtract(pivots[next_name], pivots[name])
        alignment = quaternion_between(old_direction / np.linalg.norm(old_direction),
                                       new_direction / np.linalg.norm(new_direction))
        fitted_rotation[index] = qmul(alignment, rotations[index])
    for name, index in bones.items():
        parent = parents.get(index)
        rotation = fitted_rotation[index]
        parent_rotation = fitted_rotation.get(parent, np.array((0, 0, 0, 1)))
        if name not in LEADS and parent in rotations:
            # Keep hand, eye/head, wing edge and claw roll relative to their parent.
            rotation = qmul(qmul(parent_rotation, qconj(rotations[parent])), rotations[index])
            fitted_rotation[index] = rotation
        parent_pos = pivots[original["nodes"][parent]["name"]] if parent in rotations else (0, 0, 0)
        delta = np.subtract(pivots[name], parent_pos)
        rotation_inverse = qconj(parent_rotation)
        local_position = qmul(qmul(rotation_inverse, np.r_[delta, 0]), parent_rotation)[:3]
        node = output["nodes"][index]
        node["rotation"] = qmul(rotation_inverse, rotation).tolist()
        node["translation"] = local_position.tolist()
        node.pop("scale", None)
    fitted_world = globals_of(output)
    assert all(np.linalg.norm(fitted_world[index][:3, 3] - pivots[name]) < 1e-5
               for name, index in bones.items())
    return output, {output["nodes"][index]["name"]: slot for slot, index in enumerate(skin["joints"])}


def skin_weights(pos, name, slots):
    x, y, z = pos.T
    lateral = np.abs(x)
    weights = np.zeros((len(pos), len(slots)), dtype=np.float32)
    if name.startswith(("Глаз", "Нависшее", "Нижнее веко", "Скуловая")):
        weights[:, slots["head"]] = 1
    elif name.startswith(("Пясть", "Коготь", "Боковая подушка стопы", "Подушка пальца")):
        part = "foot" if any(word in name for word in ("стоп", "Подушка пальца")) else "hand"
        side = "L" if np.median(x) < 0 else "R"
        weights[:, slots[f"{part}.{side}"]] = 1
    else:
        # The wing plane sweeps farther back as the span increases. Use depth
        # to distinguish it from the front arms over the whole shared silhouette.
        wing_plane = .14 - .48 * np.clip((lateral - .25) / .9, 0, 1)
        wings = smooth(lateral, .22, .44) * smooth(y, .73, 1.13) * (1 - smooth(z - wing_plane, -.11, .09))
        wings = np.maximum(wings, smooth(lateral, .79, .97) * smooth(y, .63, .81))
        feathers = smooth(lateral, .89, 1.50)
        elbow_of_wing = smooth(lateral + .41 * (y - 1.40), .35, 1.05)
        # The tail is behind and below the pelvis, next to the rear-facing heel.
        tail = (1 - smooth(y, .52, .86)) * (1 - smooth(z, -.20, .07))
        tail = np.maximum(tail, .94 * (1 - smooth(z, -.24, -.04)) * (1 - smooth(y, .76, .95)))
        tail *= 1 - wings
        tail_bend = smooth(lateral + (.10 - z) * .8, .17, .54)
        # The arms flare diagonally from the shoulder. A constant X mask picks
        # up the outside of the thighs and pulls it along with the upper arm.
        medial_arm = np.interp(y, (.80, .88, .98, 1.08, 1.18, 1.28, 1.38, 1.56),
                              (.55, .48, .34, .27, .24, .24, .25, .26))
        arm = smooth(lateral - medial_arm, -.025, .055) * smooth(z, .08, .17)
        arm *= smooth(y, .70, .80) * (1 - smooth(y, 1.42, 1.59))
        arm *= 1 - wings - tail
        # Cross sections around the joint follow the forearm's oblique axis.
        elbow_depth = .45 * (lateral - .52) - .86 * (y - 1.12) + .28 * (z - .36)
        wrist_depth = .45 * (lateral - .64) - .86 * (y - .88) + .28 * (z - .44)
        elbow = smooth(elbow_depth, -.12, .105)
        wrist = smooth(wrist_depth, -.10, .015)
        leg = (1 - smooth(y, .76, 1.00)) * smooth(lateral, .07, .23)
        leg *= 1 - wings - tail - arm
        knee = 1 - smooth(y, .46, .71)
        ankle = 1 - smooth(y, .14, .27)
        for side, side_mask in (("L", x < 0), ("R", x >= 0)):
            for part, factor in (("wing", wings * (1 - elbow_of_wing)),
                                 ("wingtip", wings * elbow_of_wing * (1 - feathers)),
                                 ("wingfan", wings * elbow_of_wing * feathers),
                                 ("arm", arm * (1 - elbow)),
                                 ("forearm", arm * elbow * (1 - wrist)),
                                 ("hand", arm * elbow * wrist),
                                 ("thigh", leg * (1 - knee)),
                                 ("shin", leg * knee * (1 - ankle)),
                                 ("foot", leg * knee * ankle)):
                weights[:, slots[f"{part}.{side}"]] = factor * side_mask
        weights[:, slots["tail1"]] = tail * (1 - tail_bend)
        weights[:, slots["tail2"]] = tail * tail_bend
        torso = 1 - wings - tail - arm - leg
        breast = smooth(y, 1.00, 1.32)
        neck = smooth(y, 1.42, 1.57)
        head = smooth(y, 1.52, 1.64)
        for part, factor in (("hips", 1 - breast), ("chest", breast * (1 - neck)),
                             ("neck", breast * neck * (1 - head)), ("head", breast * neck * head)):
            weights[:, slots[part]] = torso * factor
    joints = np.argsort(-weights, axis=1, kind="stable")[:, :4]
    selected = np.take_along_axis(weights, joints, axis=1)
    selected /= selected.sum(axis=1, keepdims=True)
    return joints.astype("<u2"), selected.astype("<f4")


def pack_surface(source, binary, output, package, slots):
    grouped = defaultdict(list)
    for node in source["nodes"]:
        assert set(node) == {"name", "mesh"}, node
        for primitive in source["meshes"][node["mesh"]]["primitives"]:
            attrs = primitive["attributes"]
            assert attrs.keys() == {"POSITION", "NORMAL", "COLOR_0"}, node
            points, normals, colors = (accessor(source, binary, attrs[key])
                                       for key in ("POSITION", "NORMAL", "COLOR_0"))
            if colors.dtype.kind == "u":
                colors = colors.astype("<f4") / np.iinfo(colors.dtype).max
            ids = accessor(source, binary, primitive["indices"]).astype("<u4")
            joints, weights = skin_weights(points, node["name"], slots)
            assert np.isfinite(weights).all()
            material = primitive["material"]
            colors = colors[:, :3]
            if source["materials"][material]["name"] == "Skin · Горгул":
                colors = wing_colors(points, colors)
            grouped[material].append((points, normals, colors, joints, weights, ids))
    output["materials"] = source["materials"]
    output["meshes"] = [{"name": "GorgulTRELLIS", "primitives": []}]
    total = 0
    for material, parts in sorted(grouped.items()):
        attributes = {}
        color_dimensions = "VEC4" if parts[0][2].shape[1] == 4 else "VEC3"
        fields = (("POSITION", "VEC3", 5126), ("NORMAL", "VEC3", 5126),
                  ("COLOR_0", color_dimensions, 5126), ("JOINTS_0", "VEC4", 5123), ("WEIGHTS_0", "VEC4", 5126))
        for column, (name, dimensions, component) in enumerate(fields):
            attributes[name] = package.add_array(np.concatenate([row[column] for row in parts]),
                                                 {"type": dimensions, "componentType": component}, 34962)
        offsets = np.cumsum([0] + [len(row[0]) for row in parts[:-1]], dtype="<u4")
        indices = np.concatenate([row[-1] + offset for row, offset in zip(parts, offsets, strict=True)])
        index_accessor = package.add_array(indices, {"type": "SCALAR", "componentType": 5125}, 34963)
        output["meshes"][0]["primitives"].append({"attributes": attributes, "indices": index_accessor,
                                                 "material": material})
        total += len(indices) // 3
    mesh_node = next(node for node in output["nodes"] if "mesh" in node)
    mesh_node["name"] = "GorgulTRELLIS"
    assert 140_000 < total < 185_000, total
    return total


def pack_motion(original, binary, output, package):
    skin = output["skins"][0]
    worlds = globals_of(output)
    inverse = np.array([np.linalg.inv(worlds[index]).T.reshape(16) for index in skin["joints"]], dtype="<f4")
    skin["inverseBindMatrices"] = package.add(inverse.tobytes(),
                                              {"type": "MAT4", "componentType": 5126, "count": len(inverse)})
    copied_times = {}
    assert {a["name"] for a in output["animations"]} == CLIPS
    for original_clip, animation in zip(original["animations"], output["animations"], strict=True):
        animation["samplers"] = []
        for channel in animation["channels"]:
            index = channel["target"]["node"]
            path = channel["target"]["path"]
            sampler = dict(original_clip["samplers"][channel["sampler"]])
            channel["sampler"] = len(animation["samplers"])
            animation["samplers"].append(sampler)
            times_index = sampler["input"]
            if times_index not in copied_times:
                times = accessor(original, binary, times_index)
                copied_times[times_index] = package.add(times.tobytes(), {key: value
                    for key, value in original["accessors"][times_index].items() if key != "bufferView"})
            sampler["input"] = copied_times[times_index]
            values = accessor(original, binary, sampler["output"])
            old = original["nodes"][index]
            new = output["nodes"][index]
            if path == "rotation":
                original_rest = old.get(path, (0, 0, 0, 1))
                delta = qmul(qconj(original_rest), values)
                if old["name"].startswith("wingtip."):
                    # With the new backwards sweep, the former full flex
                    # collapses the membrane's inner fold during the cry.
                    delta = qfraction(delta, .60)
                values = qmul(new[path], delta)
                values /= np.linalg.norm(values, axis=1, keepdims=True)
            elif path == "translation":
                values = new[path] + (values - old.get(path, (0, 0, 0))) * 2.76
            else:
                assert path == "scale"
                values /= old.get(path, (1, 1, 1))
            sampler["output"] = package.add(values.astype("<f4").tobytes(),
                {"type": "VEC4" if path == "rotation" else "VEC3", "componentType": 5126, "count": len(values)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("master", type=Path)
    parser.add_argument("legacy", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--decimated", type=Path, help="Reuse an existing intermediate GLB")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else None)
    with tempfile.TemporaryDirectory(prefix="gorgul-mesh-") as directory:
        intermediate = args.decimated or Path(directory) / "budget.glb"
        if args.decimated is None:
            decimate(args.master.resolve(), intermediate)
        master, master_payload = read_glb(intermediate)
    legacy, legacy_payload = read_glb(args.legacy)
    output, slots = fitted_rig(legacy)
    package = Package()
    count = pack_surface(master, master_payload, output, package, slots)
    pack_motion(legacy, legacy_payload, output, package)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    package.write(args.output, output)
    print(f"{count:,} triangles, {len(slots)} fitted joints, {len(output['materials'])} color surfaces, five clips")


if __name__ == "__main__":
    main()
