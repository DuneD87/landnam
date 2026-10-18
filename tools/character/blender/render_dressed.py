"""Renders what tools/character/dump_dressed.gd wrote (a dressed, posed
character) from the front, the side, the back and three quarters, in
Blender's background mode: no window.

    blender -b --factory-startup --python tools/character/blender/render_dressed.py -- \\
        <dump.json> <out.png> [<dump.json> ...] [--views=front,three] [--cell=420x560] [--zoom=1] [--focus=0.62] [--skip=<mesh>,...]

Several dumps go side by side, one row each. --zoom > 1 frames the torso.
"""

import json
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

ARGS = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")]
OPTIONS = dict(a[2:].split("=", 1) for a in sys.argv[sys.argv.index("--") + 1:] if a.startswith("--"))
OUT = ARGS[1]
DUMPS = [ARGS[0]] + ARGS[2:]
CELL = tuple(int(v) for v in OPTIONS.get("cell", "420x560").split("x"))
ZOOM = float(OPTIONS.get("zoom", "1"))
ALL_VIEWS = {"front": (0.0, -1.0, 0.05), "side": (1.0, 0.0, 0.05), "back": (0.0, 1.0, 0.05),
             "three": (0.75, -0.65, 0.2), "above": (0.0, -0.45, 1.0), "low_front": (0.1, -1.0, -0.35), "below": (0.05, -0.3, -1.0)}
VIEWS = {v: ALL_VIEWS[v] for v in OPTIONS.get("views", ",".join(ALL_VIEWS)).split(",")}


def load_dump(path):
    with open(path) as f:
        header = json.load(f)
    blob = np.fromfile(os.path.join(os.path.dirname(path), header["bin"]), dtype=np.uint8)
    objects = []
    images = {}
    skip = OPTIONS.get("skip", "").split(",")
    for entry in header["meshes"]:
        if entry["name"] in skip:
            continue
        at = entry["offset"]
        n = entry["vertices"]
        p = np.frombuffer(blob[at:at + n * 12].tobytes(), dtype=np.float32).reshape(-1, 3)
        at += n * 12
        uv = None
        if entry["uv"]:
            uv = np.frombuffer(blob[at:at + n * 8].tobytes(), dtype=np.float32).reshape(-1, 2)
            at += n * 8
        idx = np.frombuffer(blob[at:at + entry["indices"] * 4].tobytes(), dtype=np.int32).reshape(-1, 3)
        # Godot model space (Y up, +Z forward) -> Blender (Z up, facing -Y);
        # Godot winds front faces clockwise.
        points = np.stack([p[:, 0], -p[:, 2], p[:, 1]], axis=-1)
        mesh = bpy.data.meshes.new(entry["name"])
        mesh.from_pydata(points.tolist(), [], idx[:, [0, 2, 1]].tolist())
        if uv is not None:
            layer = mesh.uv_layers.new()
            loops = np.zeros(len(mesh.loops), dtype=np.int64)
            mesh.loops.foreach_get("vertex_index", loops)
            flipped = uv[loops] * np.array([1.0, -1.0]) + np.array([0.0, 1.0])
            layer.data.foreach_set("uv", flipped.astype(np.float32).ravel())
        material = bpy.data.materials.new(entry["name"])
        color = entry.get("color", [0.8, 0.65, 0.55])
        material.diffuse_color = (*color, 1.0)
        texture = entry.get("texture")
        if texture and uv is not None and os.path.exists(texture):
            material.use_nodes = True
            nodes = material.node_tree.nodes
            node = nodes.new("ShaderNodeTexImage")
            if texture not in images:
                images[texture] = bpy.data.images.load(texture)
            node.image = images[texture]
            material.node_tree.links.new(node.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
            nodes.active = node
        mesh.materials.append(material)
        for poly in mesh.polygons:
            poly.use_smooth = True
        obj = bpy.data.objects.new(entry["name"], mesh)
        obj.color = (*color, 1.0)
        bpy.context.scene.collection.objects.link(obj)
        objects.append(obj)
    return objects


def render(objects, name):
    scene = bpy.context.scene
    points = np.concatenate([np.array([o.matrix_world @ v.co for v in o.data.vertices]) for o in objects])
    low, high = points.min(axis=0), points.max(axis=0)
    centre = Vector((low + high) * 0.5)
    size = max(high[2] - low[2], 1.0) * 1.08 / ZOOM
    if ZOOM > 1.0:
        # What --focus says, as a share of the height (0.62: the torso and thighs).
        centre.z = low[2] + (high[2] - low[2]) * float(OPTIONS.get("focus", "0.62"))
    shots = []
    for view, direction in VIEWS.items():
        camera = bpy.data.cameras.new(view)
        camera.type = "ORTHO"
        camera.ortho_scale = size
        cam = bpy.data.objects.new(view, camera)
        scene.collection.objects.link(cam)
        d = Vector(direction).normalized()
        cam.location = centre + d * 5.0
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        path = os.path.join(os.path.dirname(OUT) or ".", "_%s_%s.png" % (name, view))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        shots.append(path)
        bpy.data.objects.remove(cam)
    return shots


def main():
    scene = bpy.context.scene
    rows = []
    for i, dump in enumerate(DUMPS):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "TEXTURE"
        scene.display.shading.show_cavity = True
        scene.view_settings.view_transform = "Standard"
        scene.render.resolution_x, scene.render.resolution_y = CELL
        scene.render.film_transparent = False
        objects = load_dump(dump)
        rows.append(render(objects, "row%d" % i))
    # One sheet: a row per dump, a column per view.
    sheet = bpy.data.images.new("sheet", CELL[0] * len(VIEWS), CELL[1] * len(rows))
    pixels = np.zeros((CELL[1] * len(rows), CELL[0] * len(VIEWS), 4), dtype=np.float32)
    for r, shots in enumerate(rows):
        for c, shot in enumerate(shots):
            image = bpy.data.images.load(shot)
            cell = np.array(image.pixels[:], dtype=np.float32).reshape(CELL[1], CELL[0], 4)
            # Blender images go bottom-up: the first row ends up on top.
            y = (len(rows) - 1 - r) * CELL[1]
            pixels[y:y + CELL[1], c * CELL[0]:(c + 1) * CELL[0]] = cell
            os.remove(shot)
    sheet.pixels.foreach_set(pixels.ravel())
    sheet.filepath_raw = OUT
    sheet.file_format = "PNG"
    sheet.save()
    print("Saved", OUT)


main()
