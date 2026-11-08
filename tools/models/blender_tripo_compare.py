"""Isolated, CPU-only Blender comparison. Never writes production assets.

blender -b --factory-startup -t 4 -P tools/models/blender_tripo_compare.py --
  --old assets/creatures_hd/levian_gale.glb --output docs/audits/2026-11-06-blender-tripo
  [--new build/blender-tripo-2026-11-06/levian_gale_tripo.glb]

Each model is normalized to height 2, with shared cameras, light, ground and
orthographic scale. Imports retain original materials, rig and rest pose.
No animation/support/runtime acceptance is implied by these still renders.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(meshes):
    # Accepted GLBs deliberately retain unused POSITION entries. Their extrema
    # must not shrink the visible creature (A02 also preserves those entries).
    points = [o.matrix_world @ o.data.vertices[i].co for o in meshes
              for i in {i for polygon in o.data.polygons for i in polygon.vertices}]
    return (Vector(tuple(min(p[i] for p in points) for i in range(3))),
            Vector(tuple(max(p[i] for p in points) for i in range(3))))


def setup_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.world.use_nodes = True
    bg = next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (.32, .35, .40, 1)
    bg.inputs[1].default_value = .65
    for name, pos, power, size in [
        ("Comparison_Key", (-3, -4, 6), 550, 4),
        ("Comparison_Fill", (4, -1, 3), 220, 4),
        ("Comparison_Rim", (0, 4, 4), 330, 3),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size = power, "DISK", size
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = pos
        obj.rotation_euler = (Vector((0, 0, 1)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.012))
    ground = bpy.context.object
    ground.name = "Comparison_Ground"
    mat = bpy.data.materials.new("Comparison_Ground_Material")
    mat.use_nodes = True
    node = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node.inputs["Base Color"].default_value = (.055, .068, .085, 1)
    node.inputs["Roughness"].default_value = .9
    ground.data.materials.append(mat)
    camera = bpy.data.objects.new("Comparison_Camera", bpy.data.cameras.new("Comparison_Camera"))
    scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.7
    camera.data.lens = 50
    scene.camera = camera
    return scene, camera


def import_model(path, label, z_rotation):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    objects = set(bpy.data.objects) - before
    custom_shapes = {b.custom_shape for o in objects if o.type == "ARMATURE"
                     for b in o.pose.bones if b.custom_shape is not None}
    # glTF importer creates hidden Icosphere bone widgets. They are tooling,
    # not part of the model, and must never influence size or face counts.
    objects -= custom_shapes
    meshes = [o for o in objects if o.type == "MESH" and not o.hide_render]
    for obj in objects:
        if obj.type == "ARMATURE":
            obj.data.pose_position = "REST"
    bpy.context.view_layer.update()
    low, high = bounds(meshes)
    height = high.z - low.z
    root = bpy.data.objects.new("Comparison_" + label, None)
    bpy.context.scene.collection.objects.link(root)
    for obj in objects:
        if obj.parent not in objects:
            matrix = obj.matrix_world.copy()
            obj.parent = root
            obj.matrix_world = matrix
    factor = 2 / height
    center = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
    root.matrix_world = Matrix.Rotation(math.radians(z_rotation), 4, "Z") @ Matrix.Diagonal((factor, factor, factor, 1)) @ Matrix.Translation(-center)
    bpy.context.view_layer.update()
    stats = {
        "path": str(path), "sha256": sha(path), "bytes": path.stat().st_size,
        "mesh_objects": len(meshes), "vertices": sum(len(o.data.vertices) for o in meshes),
        "triangles": sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes),
        "bones": sum(len(o.data.bones) for o in objects if o.type == "ARMATURE"),
        "materials": sorted({m.name for o in meshes for m in o.data.materials if m}),
        "source_bbox_min": list(low), "source_bbox_max": list(high),
        "normalization": {"height": 2, "scale": factor, "z_rotation_degrees": z_rotation},
    }
    return objects | {root}, stats


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--new", type=Path)
    parser.add_argument("--new-z-rotation", type=float, default=0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.output.mkdir(parents=True, exist_ok=True)
    scene, camera = setup_scene()
    specs = [("old", args.old, 0)]
    if args.new:
        specs.append(("tripo", args.new, args.new_z_rotation))
    models = {}
    stats = {"blender": bpy.app.version_string, "engine": "Cycles CPU", "samples": 24,
             "resolution": [640, 640], "ortho_scale": camera.data.ortho_scale,
             "models": {}, "views": {}}
    for label, path, rotation in specs:
        models[label], stats["models"][label] = import_model(path, label, rotation)
    for label, objects in models.items():
        for other_label, other_objects in models.items():
            for obj in other_objects:
                obj.hide_render = other_label != label
        for view, degrees in [("front", 0), ("three_quarter", 45), ("side", 90), ("back", 180)]:
            a = math.radians(degrees)
            target = Vector((0, 0, 1))
            camera.location = Vector((6 * math.sin(a), -6 * math.cos(a), 2.25))
            camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
            stats["views"][view] = {"camera_position": list(camera.location), "target": list(target)}
            scene.render.filepath = str((args.output / f"{label}_{view}.png").resolve())
            bpy.ops.render.render(write_still=True)
    for obj in models["old"]:
        obj.hide_render = False
    for label, objects in models.items():
        if label != "old":
            for obj in objects:
                obj.hide_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str((args.output / "comparison_scene.blend").resolve()))
    (args.output / "render_manifest.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n")
    print("COMPARISON_SAVED", args.output, flush=True)
    # Avoid audio/backend shutdown hanging in restricted headless sessions.
    # All requested files have been synchronously saved above.
    os._exit(0)


if __name__ == "__main__":
    try:
        main()
    except BaseException:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(1)
