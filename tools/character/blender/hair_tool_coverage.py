"""Measures how much scalp shows through each Hair Tool style, as the game draws it.

    blender -b --factory-startup --python tools/character/blender/hair_tool_coverage.py -- \
        <mh_base.blend> <cards dir> <albedo dir|-> <out dir> [--look] <name> [<name>...]

human_hair.gdshader only hides what is behind with the texels at or over
half alpha (the rest is a blended fringe), so each style's cards
(<cards dir>/<name>.obj) are rendered with that cut over MakeHuman's head,
its scalp painted red. The albedo is the baked one from <albedo dir>
(hair_ht_<name>_albedo.png), or with "-" the atlas next to the cards. The
report is the share of the scalp still red from above and from behind,
against the bare head; the renders are kept to look at (Cycles, CPU, no
window).

With --look the skin is painted instead as the game paints it under a style:
skin colour with the style's cover (hair_ht_<name>_cover.png, in <albedo
dir>) as roots of the hair colour, rendered from the front, three-quarter and
above (<name>_look_<view>.png), to judge the hairline.
"""

import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

SIZE = 320
CUT = 0.5


def emission(name, colour):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    out = tree.nodes.new("ShaderNodeOutputMaterial")
    emit = tree.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = colour
    tree.links.new(emit.outputs[0], out.inputs[0])
    return material, tree, emit, out


def hair_material(texture):
    material, tree, emit, out = emission("Hair", (0.0, 0.0, 0.0, 1.0))
    image = tree.nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(str(texture))
    image.interpolation = "Closest"
    cut = tree.nodes.new("ShaderNodeMath")
    cut.operation = "GREATER_THAN"
    cut.inputs[1].default_value = CUT - 0.001
    mix = tree.nodes.new("ShaderNodeMixShader")
    clear = tree.nodes.new("ShaderNodeBsdfTransparent")
    tree.links.new(image.outputs["Alpha"], cut.inputs[0])
    tree.links.new(cut.outputs[0], mix.inputs[0])
    tree.links.new(clear.outputs[0], mix.inputs[1])
    tree.links.new(emit.outputs[0], mix.inputs[2])
    tree.links.new(mix.outputs[0], out.inputs[0])
    return material


def setup(base_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(base_path), link=False) as (src, dst):
        dst.objects = ["MH_Base"]
    base = dst.objects[0]
    scene = bpy.context.scene
    scene.collection.objects.link(base)
    skin = emission("Skin", (0.5, 0.5, 0.5, 1.0))[0]
    scalp = emission("Scalp", (1.0, 0.0, 0.0, 1.0))[0]
    base.data.materials.append(skin)
    base.data.materials.append(scalp)
    group = base.vertex_groups["scalp"].index
    on_scalp = {v.index for v in base.data.vertices if any(g.group == group and g.weight > 0.5 for g in v.groups)}
    for face in base.data.polygons:
        face.material_index = 1 if all(v in on_scalp for v in face.vertices) else 0
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.cycles.use_denoising = False
    scene.cycles.transparent_max_bounces = 64
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 8
    scene.render.resolution_x = scene.render.resolution_y = SIZE
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("Black")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    scene.world = world
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 0.32
    scene.collection.objects.link(camera)
    scene.camera = camera
    return base


VIEWS = {"top": Vector((0.0, 0.0, 1.0)), "back": Vector((0.0, 1.0, 0.25))}


def red_share(path):
    image = bpy.data.images.load(str(path))
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(-1, 4)
    bpy.data.images.remove(image)
    return int(((pixels[:, 0] > 0.5) & (pixels[:, 1] < 0.3)).sum())


def render_views(out, tag):
    scene = bpy.context.scene
    camera = scene.camera
    centre = Vector((0.0, -0.06, 1.6))
    reds = {}
    for view, direction in VIEWS.items():
        direction = direction.normalized()
        camera.location = centre + direction * 1.0
        camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        path = out / ("%s_%s.png" % (tag, view))
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        reds[view] = red_share(path)
    return reds


HAIR = (0.12, 0.07, 0.035, 1.0)
SKIN = (0.8, 0.55, 0.42, 1.0)
LOOK_VIEWS = {"front": Vector((0.0, -1.0, 0.05)), "three": Vector((0.7, -0.7, 0.15)), "top": Vector((0.0, -0.3, 1.0))}


def look(base, cards_dir, albedo_dir, out, names):
    """Skin with each style's cover as roots, its cards over it."""
    material, tree, emit, _ = emission("Look", SKIN)
    cover = tree.nodes.new("ShaderNodeTexImage")
    mix = tree.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = SKIN
    mix.inputs["B"].default_value = HAIR
    tree.links.new(cover.outputs["Color"], mix.inputs["Factor"])
    tree.links.new(mix.outputs["Result"], emit.inputs["Color"])
    base.data.materials.clear()
    base.data.materials.append(material)
    scene = bpy.context.scene
    scene.camera.data.ortho_scale = 0.36
    for name in names:
        path = Path(albedo_dir) / ("hair_ht_%s_cover.png" % name)
        cover.image = bpy.data.images.load(str(path)) if path.exists() else None
        if cover.image:
            cover.image.colorspace_settings.name = "Non-Color"
        bpy.ops.wm.obj_import(filepath=str(cards_dir / (name + ".obj")), forward_axis="NEGATIVE_Z", up_axis="Y")
        cards = bpy.context.selected_objects[0]
        hair = hair_material(Path(albedo_dir) / ("hair_ht_%s_albedo.png" % name))
        hair.node_tree.nodes["Emission"].inputs["Color"].default_value = (0.07, 0.04, 0.02, 1.0)
        cards.data.materials.append(hair)
        for view, direction in LOOK_VIEWS.items():
            direction = direction.normalized()
            scene.camera.location = Vector((0.0, -0.06, 1.6)) + direction * 1.0
            scene.camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = str(out / ("%s_look_%s.png" % (name, view)))
            bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cards)
        print("LOOK", name, "cover" if cover.image else "no cover", flush=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    if "--look" in args:
        args.remove("--look")
        out = Path(args[3])
        out.mkdir(parents=True, exist_ok=True)
        base = setup(Path(args[0]))
        look(base, Path(args[1]), args[2], out, args[4:])
        return
    base_path, cards_dir, albedo_dir, out = Path(args[0]), Path(args[1]), args[2], Path(args[3])
    out.mkdir(parents=True, exist_ok=True)
    setup(base_path)
    bare = render_views(out, "_bare")
    report = {}
    for name in args[4:]:
        bpy.ops.wm.obj_import(filepath=str(cards_dir / (name + ".obj")), forward_axis="NEGATIVE_Z", up_axis="Y")
        cards = bpy.context.selected_objects[0]
        texture = (cards_dir / (name + "_atlas.png") if albedo_dir == "-"
                   else Path(albedo_dir) / ("hair_ht_%s_albedo.png" % name))
        cards.data.materials.append(hair_material(texture))
        reds = render_views(out, name)
        report[name] = {view: round(100.0 * reds[view] / max(bare[view], 1), 1) for view in VIEWS}
        print("COVERAGE %-16s top %5.1f%%  back %5.1f%% scalp showing" % (name, report[name]["top"],
                                                                         report[name]["back"]), flush=True)
        bpy.data.objects.remove(cards)
    (out / "coverage.json").write_text(json.dumps(report, indent=1))


main()
