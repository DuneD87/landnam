"""Moves a Hair Tool library preset onto MakeHuman's head and exports its cards.

Run with Blender 5.2 in background (no window, no Hair Tool addon: the
presets carry their own geometry nodes):

    blender -b --factory-startup <preset.blend> --python \
        tools/character/blender/hair_tool_convert.py -- <mh_base.blend> <out dir> <name> \
        [--extra other.blend ...] [--objects A,B] [--keep 0.6] [--region moustache] [--spread 10] [--noise 3] [--render]

<mh_base.blend> is written by hair_tool_base.py. Every preset was groomed on
the same mannequin head, which the library does not ship; its full scalp cap
(ShortHair_Scalp) is fitted once to MakeHuman's head (scale per axis and
offset, no rotation) and that transform moves every preset. Each preset's
scalp then wraps onto the head with its own Shrinkwrap, whose target the
addon would set on append, and its guides follow the scalp (GN_MeshDeform).

The cards the generators make are written to <out dir>/<name>.obj (in the
space of the base mesh, with the generator's UVs) and the atlas next to it.
Cards are halved along their length (--unsubdivide, one pass by default:
a second one saves nothing); then, over --budget triangles, cards are dropped
at random (whole cards) to fit it, as --keep does by hand; --objects limits
which hair objects are exported (default: every generated one); --extra appends the objects of other presets (subcomponents:
a tail or a bun on a pulled-back base). --render saves a Cycles preview
(front, three-quarter, back). --region keeps only the cards rooted in a
part of the face (FaceRegions: moustache, toothbrush, goatee...), to make
beard styles the library lacks out of its full beards. --noise scales the
generators' noise (roughen()): unkempt versions of a style.

The atlas is the image most of the cards use. A preset that keeps colour and
opacity in two images (Afro) gets them joined: grey from the colour image,
alpha from the one named *opacity*. Cards using any other image are dropped
and counted in the report. Its strands are thickened across (densify()):
Hair Tool draws thin strands with gaps and relies on many blended layers,
but human_hair.gdshader only hides what is behind with the texels over half
alpha, so the scalp showed through and the blended rest let the atmosphere
show over the hair.
"""

import argparse
import json
from pathlib import Path
import random
import re
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

LIBRARY = Path("/home/drive/tools/hair_tool_library/HairLibrary_52")
## The preset whose scalp defines the mannequin head.
CAP_PRESET = LIBRARY / "ShortHair.blend"
CAP_OBJECT = "ShortHair_Scalp"
ICP_STEPS = 40
## densify(): texels the strands are spread across (each side, at 1024 px;
## --spread) and the gain on that spread alpha.
SPREAD = 10
SPREAD_GAIN = 6.0
## Bounds of the per-axis scale of the fit.
SCALE_RANGE = (0.8, 1.2)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("name")
    parser.add_argument("--objects", default="")
    parser.add_argument("--extra", nargs="*", default=[], type=Path)
    parser.add_argument("--keep", type=float, default=1.0)
    parser.add_argument("--unsubdivide", type=int, default=1)
    parser.add_argument("--budget", type=int, default=0)
    parser.add_argument("--region", default="")
    parser.add_argument("--spread", type=float, default=SPREAD)
    parser.add_argument("--noise", type=float, default=1.0)
    parser.add_argument("--render", action="store_true")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def append_object(path, name):
    with bpy.data.libraries.load(str(path), link=False) as (src, dst):
        dst.objects = [name]
    obj = dst.objects[0]
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    return obj


def world_points(obj):
    return np.array([tuple(obj.matrix_world @ v.co) for v in obj.data.vertices])


def head_tree(base):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    bm.from_object(base, depsgraph)
    bm.transform(base.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def fit_cap(points, tree, top):
    """Per-axis scale and offset taking the cap onto the head surface."""
    scale = np.ones(3)
    # Start with the crowns together; the cap is centred in X already.
    offset = np.array([0.0, 0.0, top[2] - points[:, 2].max()])
    crown = points[points[:, 2].argmax()]
    offset[1] = top[1] - crown[1]
    for _ in range(ICP_STEPS):
        moved = points * scale + offset
        nearest = np.array([tuple(tree.find_nearest(Vector(p))[0]) for p in moved])
        for axis in range(3):
            a = points[:, axis]
            b = nearest[:, axis]
            if axis == 0:
                # Symmetric: no offset across the head.
                s = float((a * b).sum() / (a * a).sum())
            else:
                s = float(np.polyfit(a, b, 1)[0])
            scale[axis] = min(max(s, SCALE_RANGE[0]), SCALE_RANGE[1])
            if axis:
                offset[axis] = float((b - a * scale[axis]).mean())
    moved = points * scale + offset
    gaps = np.array([tree.find_nearest(Vector(p))[3] for p in moved])
    return scale, offset, float(gaps.mean()), float(np.percentile(gaps, 95))


def mannequin_transform(base, tree):
    if Path(bpy.data.filepath) == CAP_PRESET:
        points = world_points(bpy.data.objects[CAP_OBJECT])
    else:
        cap = append_object(CAP_PRESET, CAP_OBJECT)
        points = world_points(cap)
        bpy.data.objects.remove(cap)
    vertices = world_points(base)
    top = vertices[vertices[:, 2].argmax()]
    scale, offset, mean_gap, gap95 = fit_cap(points, tree, top)
    return Matrix.Translation(offset) @ Matrix.Diagonal((*scale, 1.0)), {
        "scale": scale.tolist(), "offset": offset.tolist(), "mean_gap": mean_gap, "gap95": gap95}


def _smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


class FaceRegions:
    """Parts of MakeHuman's face, 0-1 at a point on it, from landmarks of the
    base head (the rules of make_skin_masks.py, in Blender axes: X across, Z
    up, -Y forward). Feathered regions thin out at their edge; crisp ones
    (CRISP) are cut clean."""

    CRISP = {"toothbrush"}

    def __init__(self, base):
        points = world_points(base)
        def group(name):
            index = base.vertex_groups[name].index
            return np.array([any(g.group == index and g.weight > 0.5 for g in v.groups) for v in base.data.vertices])
        lips = points[group("lips")]
        ears = points[group("ears")]
        self.mouth = lips.mean(axis=0)
        self.mouth_half = np.abs(lips[:, 0]).max()
        up, fwd = points[:, 2], -points[:, 1]
        m_up, m_fwd = self.mouth[2], -self.mouth[1]
        front = (np.abs(points[:, 0]) < 0.006) & (up > m_up + 0.01) & (up < m_up + 0.07)
        self.nose = points[front][np.argmax(fwd[front])]
        below = (np.abs(points[:, 0]) < 0.01) & (up < m_up) & (up > m_up - 0.09) & (fwd > m_fwd - 0.06)
        self.chin = points[below][np.argmin(up[below])]
        self.ear = ears[ears[:, 0] > 0].mean(axis=0)
        print("FACE mouth", self.mouth.round(3), "nose", self.nose.round(3), "chin", self.chin.round(3),
              "ear", self.ear.round(3))

    def _axes(self, p):
        return abs(p[0]), p[2], -p[1]

    def full(self, p):
        ax, up, fwd = self._axes(p)
        nose_up, ear_up, chin_up = self.nose[2], self.ear[2], self.chin[2]
        side = min(ax / abs(self.ear[0]), 1.0)
        top = nose_up - 0.012 + (ear_up - 0.028 - (nose_up - 0.012)) * side ** 1.4
        value = 1.0 - _smooth(top - 0.008, top + 0.004, up)
        value *= _smooth(chin_up - 0.03, chin_up - 0.01, up)
        value *= _smooth(-self.ear[1] - 0.012, -self.ear[1] + 0.004, fwd)
        return value

    def moustache(self, p):
        ax, up, fwd = self._axes(p)
        m_up = self.mouth[2]
        value = _smooth(m_up + 0.001, m_up + 0.006, up) * (1.0 - _smooth(self.nose[2] - 0.016, self.nose[2] - 0.006, up))
        value *= 1.0 - _smooth(self.mouth_half + 0.004, self.mouth_half + 0.016, ax)
        return value * _smooth(-self.mouth[1] - 0.035, -self.mouth[1] - 0.015, fwd)

    def toothbrush(self, p):
        ax, up, _ = self._axes(p)
        return float(self.moustache(p) > 0.5 and ax < 0.014 and up > self.mouth[2] + 0.004)

    def goatee(self, p, width=0.03):
        ax, up, fwd = self._axes(p)
        value = (1.0 - _smooth(width - 0.012, width, ax)) * (1.0 - _smooth(self.mouth[2] - 0.012, self.mouth[2] - 0.005, up))
        return value * _smooth(self.chin[2] - 0.02, self.chin[2] - 0.004, up) * _smooth(-self.chin[1] - 0.04, -self.chin[1] - 0.015, fwd)

    def soul_patch(self, p):
        ax, up, fwd = self._axes(p)
        m_up = self.mouth[2]
        return (1.0 - _smooth(0.006, 0.011, ax)) * _smooth(m_up - 0.032, m_up - 0.026, up) \
            * (1.0 - _smooth(m_up - 0.012, m_up - 0.006, up)) * _smooth(-self.mouth[1] - 0.03, -self.mouth[1] - 0.012, fwd)

    def horseshoe(self, p):
        ax, up, fwd = self._axes(p)
        bars = _smooth(self.mouth_half - 0.006, self.mouth_half - 0.001, ax) \
            * (1.0 - _smooth(self.mouth_half + 0.01, self.mouth_half + 0.016, ax))
        bars *= _smooth(self.chin[2] - 0.012, self.chin[2] - 0.002, up) * (1.0 - _smooth(self.mouth[2], self.mouth[2] + 0.006, up))
        bars *= _smooth(-self.mouth[1] - 0.04, -self.mouth[1] - 0.02, fwd)
        return max(self.moustache(p), bars)

    def van_dyke(self, p):
        return max(self.moustache(p), self.goatee(p, width=0.02))

    def chin_strap(self, p):
        ax, up, _ = self._axes(p)
        side = min(ax / abs(self.ear[0]), 1.0)
        jaw = self.chin[2] + (self.ear[2] - 0.035 - self.chin[2]) * side ** 1.6
        return self.full(p) * (1.0 - _smooth(jaw + 0.016, jaw + 0.028, up)) * (1.0 - self.moustache(p))

    def mutton_chops(self, p):
        ax, _, _ = self._axes(p)
        return self.full(p) * _smooth(self.mouth_half + 0.012, self.mouth_half + 0.026, ax)

    def no_moustache(self, p):
        return self.full(p) * (1.0 - _smooth(0.2, 0.6, self.moustache(p)))


def island_faces(bm):
    """Faces of each card (connected island)."""
    bm.faces.index_update()
    islands, seen = [], set()
    for face in bm.faces:
        if face.index in seen:
            continue
        stack, island = [face], []
        seen.add(face.index)
        while stack:
            f = stack.pop()
            island.append(f)
            for edge in f.edges:
                for other in edge.link_faces:
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        islands.append(island)
    return islands


def roots(objects):
    return [o for o in objects if o.parent is None and o.type in ("MESH", "CURVES")]


def roughen(factor):
    """Scales the generators' noise (HD_Noise_Deform's Global Scale) by
    factor: unkempt versions of a style. Returns how many it changed."""
    changed = 0
    for group in bpy.data.node_groups:
        if not group.name.startswith("Hair_System_Main"):
            continue
        for node in group.nodes:
            if node.type == "GROUP" and node.node_tree and node.node_tree.name.startswith("HD_Noise_Deform"):
                socket = node.inputs.get("Global Scale")
                if socket is not None and not socket.is_linked:
                    socket.default_value *= factor
                    changed += 1
    return changed


def hair_objects():
    """Objects whose evaluated geometry is a card mesh: hair curves, or meshes
    the generator builds on (Dreadlocks' tubes), but not the helper mesh the
    addon takes smooth normals from (SmoothNorm_SRC_mesh), left at the feet,
    nor the profiles it previews (curves with only HT_Curves_Profile_Preview)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    found = []
    for obj in bpy.data.objects:
        groups = [m.node_group.name for m in obj.modifiers if m.type == "NODES" and m.node_group]
        if groups and all(g.startswith("HT_Curves_Profile") for g in groups):
            continue
        generated = obj.type == "MESH" and not obj.name.startswith("SmoothNorm") and any(
            g.startswith("Hair_System_Main") for g in groups)
        if (obj.type != "CURVES" and not generated) or obj.hide_render:
            continue
        geometry = obj.evaluated_get(depsgraph).evaluated_geometry()
        if geometry.mesh and len(geometry.mesh.polygons):
            found.append(obj)
    return found


## Image name (without copy suffix) -> image.
IMAGES = {}


def material_images(material):
    if not material or not material.node_tree:
        return ()
    images = []
    pending = [material.node_tree]
    while pending:
        tree = pending.pop()
        for node in tree.nodes:
            if node.type == "TEX_IMAGE" and node.image and node.image.size[0]:
                images.append(node.image)
            elif node.type == "GROUP" and node.node_tree:
                pending.append(node.node_tree)
    # Appended presets bring copies of the same atlas ("X.png.001").
    unique = {}
    for image in images:
        unique.setdefault(re.sub(r"\.\d{3}$", "", image.name), image)
    return tuple(unique[k] for k in sorted(unique))


def face_images(mesh):
    """Per face, the names of its material's images."""
    materials = list(mesh.materials)
    indices = [0] * len(mesh.polygons)
    if materials:
        mesh.polygons.foreach_get("material_index", indices)
    keys = [tuple(re.sub(r"\.\d{3}$", "", i.name) for i in material_images(m)) for m in materials]
    for m in materials:
        for image in material_images(m):
            IMAGES.setdefault(re.sub(r"\.\d{3}$", "", image.name), image)
    return [keys[i] if materials else () for i in indices]


def export_cards(objects, path, keep, unsubdivide=0, region=None, tree=None, seed=1):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    # The atlas: the image set most faces use.
    counts = {}
    for obj in objects:
        geometry = obj.evaluated_get(depsgraph).evaluated_geometry()
        for images in face_images(geometry.mesh):
            counts[images] = counts.get(images, 0) + 1
    atlas = max(counts, key=counts.get) if counts else ()
    dropped = sum(n for images, n in counts.items() if images != atlas)
    joined = bmesh.new()
    uv_out = joined.loops.layers.uv.new("UVMap")
    rng = random.Random(seed)
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        # The geometry set owns the mesh: keep it alive while reading.
        geometry = evaluated.evaluated_geometry()
        images = face_images(geometry.mesh)
        bm = bmesh.new()
        bm.from_mesh(geometry.mesh)
        bm.transform(evaluated.matrix_world)
        bm.faces.ensure_lookup_table()
        other = [f for f in bm.faces if images[f.index] != atlas]
        if other:
            bmesh.ops.delete(bm, geom=other, context="FACES")
        uv = bm.loops.layers.uv.get("UVMapGN")
        if keep < 1.0 or region:
            # Cards are islands; drop whole ones: by chance, and by where
            # they grow (their vertex nearest the skin).
            drop = []
            for island in island_faces(bm):
                chance = keep
                if region:
                    root = min({v for f in island for v in f.verts}, key=lambda v: tree.find_nearest(v.co)[3])
                    value = region(root.co)
                    crisp = value if region.__name__ in FaceRegions.CRISP else value * value * (3.0 - 2.0 * value)
                    chance *= crisp
                if rng.random() >= chance:
                    drop.extend(island)
            bmesh.ops.delete(bm, geom=drop, context="FACES_ONLY")
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        remap = {v: joined.verts.new(v.co) for v in bm.verts}
        for face in bm.faces:
            try:
                new = joined.faces.new([remap[v] for v in face.verts])
            except ValueError:
                continue
            for loop, src in zip(new.loops, face.loops):
                loop[uv_out].uv = src[uv].uv if uv else (0.0, 0.0)
        bm.free()
    mesh = bpy.data.meshes.new(path.stem)
    joined.to_mesh(mesh)
    joined.free()
    obj = bpy.data.objects.new(path.stem, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if unsubdivide:
        # Cards are quad strips: halving their rows keeps every card.
        modifier = obj.modifiers.new("Unsubdivide", "DECIMATE")
        modifier.decimate_type = "UNSUBDIV"
        modifier.iterations = unsubdivide
        depsgraph = bpy.context.evaluated_depsgraph_get()
        reduced = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
        obj.modifiers.clear()
        obj.data = reduced
        mesh = reduced
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.obj_export(filepath=str(path), export_selected_objects=True, export_materials=False,
                          export_normals=True, export_uv=True, forward_axis="NEGATIVE_Z", up_axis="Y",
                          apply_modifiers=False)
    mesh.calc_loop_triangles()
    return obj, len(mesh.loop_triangles), atlas, dropped


def _box(a, radius, axis):
    pad = [(0, 0)] * a.ndim
    pad[axis] = (radius + 1, radius)
    total = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
    n = a.shape[axis]
    return (np.take(total, range(2 * radius + 1, 2 * radius + 1 + n), axis=axis)
            - np.take(total, range(0, n), axis=axis)) / (2 * radius + 1)


def densify(alpha, spread=SPREAD):
    """Strands spread across (the atlas strands run along V, its rows) into a
    solid core where they are dense; lone strands and tips stay thin."""
    radius = max(1, round(spread * alpha.shape[1] / 1024))
    across = _box(alpha, radius, 1)
    along = _box(alpha, 1, 0)
    return np.clip(np.maximum(alpha, np.minimum(across, along * 2.0) * SPREAD_GAIN), 0.0, 1.0)


def save_atlas(images, out, name, spread=SPREAD):
    path = out / (name + "_atlas.png")
    if not images:
        return None
    opacity = [i for i in images if "opacity" in i.name.lower()]
    colour = [i for i in images if i not in opacity]
    if len(images) == 1 or not opacity or not colour:
        image = images[0]
    else:
        w, h = opacity[0].size
        alpha = np.array(opacity[0].pixels[:], dtype=np.float32).reshape(h, w, 4)[..., 0]
        source = colour[0]
        if tuple(source.size) != (w, h):
            source = source.copy()
            source.scale(w, h)
        grey = np.array(source.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3].mean(axis=2)
        image = bpy.data.images.new(name + "_atlas", w, h, alpha=True)
        image.pixels.foreach_set(np.stack([grey, grey, grey, alpha], axis=2).ravel())
    w, h = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    pixels[..., 3] = densify(pixels[..., 3], spread)
    dense = bpy.data.images.new(name + "_dense", w, h, alpha=True)
    dense.pixels.foreach_set(pixels.ravel())
    dense.filepath_raw = str(path)
    dense.file_format = "PNG"
    dense.save()
    return path


def render(base, cards, atlas, out, name):
    scene = bpy.context.scene
    for obj in list(scene.collection.all_objects):
        if obj not in (base, cards):
            obj.hide_render = True
    skin = bpy.data.materials.new("PreviewSkin")
    skin.use_nodes = True
    skin.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.6, 0.5, 1)
    base.data.materials.clear()
    base.data.materials.append(skin)
    hair = bpy.data.materials.new("PreviewHair")
    hair.use_nodes = True
    tree = hair.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.12, 0.07, 0.035, 1)
    bsdf.inputs["Roughness"].default_value = 0.6
    if atlas:
        image = tree.nodes.new("ShaderNodeTexImage")
        image.image = bpy.data.images.load(str(atlas))
        tree.links.new(image.outputs["Alpha"], bsdf.inputs["Alpha"])
    cards.data.materials.clear()
    cards.data.materials.append(hair)
    world = bpy.data.worlds.new("Preview")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.37, 0.4, 1)
    scene.world = world
    light = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
    light.data.energy = 3.0
    light.rotation_euler = (0.9, 0.0, -0.6)
    scene.collection.objects.link(light)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 8
    scene.render.resolution_x = scene.render.resolution_y = 420
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.lens = 85
    scene.collection.objects.link(camera)
    scene.camera = camera
    centre = Vector((0.0, -0.06, 1.56))
    for view, angle in (("front", 0.0), ("three", 0.7), ("back", 3.1416)):
        direction = Vector((np.sin(angle), -np.cos(angle), 0.08)).normalized()
        camera.location = centre + direction * 1.25
        camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(out / ("%s_%s.png" % (name, view)))
        bpy.ops.render.render(write_still=True)


def main():
    args = parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    preset_objects = list(bpy.data.objects)
    for obj in preset_objects:
        if obj.name not in bpy.context.scene.collection.all_objects:
            bpy.context.scene.collection.objects.link(obj)
    for extra in args.extra:
        with bpy.data.libraries.load(str(LIBRARY / extra) if not extra.is_absolute() else str(extra),
                                     link=False) as (src, dst):
            dst.objects = list(src.objects)
        for obj in dst.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
                preset_objects.append(obj)
    bpy.context.view_layer.update()
    base = append_object(args.base, "MH_Base")
    tree = head_tree(base)
    transform, fit = mannequin_transform(base, tree)
    for obj in roots(preset_objects):
        obj.matrix_world = transform @ obj.matrix_world
    for obj in preset_objects:
        for modifier in obj.modifiers:
            if modifier.type == "SHRINKWRAP":
                modifier.target = base
    noised = roughen(args.noise) if args.noise != 1.0 else 0
    bpy.context.view_layer.update()
    objects = hair_objects()
    if args.objects:
        wanted = set(args.objects.split(","))
        objects = [o for o in objects if o.name in wanted]
    path = args.out / (args.name + ".obj")
    keep = args.keep
    region = getattr(FaceRegions(base), args.region) if args.region else None
    cards, triangles, images, dropped = export_cards(objects, path, keep, args.unsubdivide, region, tree)
    if args.budget and triangles > args.budget:
        # Over budget once the cards are halved: drop just enough of them.
        keep *= args.budget / triangles * 0.97
        bpy.data.objects.remove(cards)
        cards, triangles, images, dropped = export_cards(objects, path, keep, args.unsubdivide, region, tree)
    atlas = save_atlas([IMAGES[i] for i in images], args.out, args.name, args.spread)
    report = {"name": args.name, "preset": bpy.data.filepath, "extra": [str(e) for e in args.extra],
              "objects": [o.name for o in objects], "triangles": triangles,
              "keep": keep, "region": args.region, "noise": [args.noise, noised], "atlas": list(images), "dropped_faces": dropped, "fit": fit}
    (args.out / (args.name + ".json")).write_text(json.dumps(report, indent=1))
    print("HAIR_TOOL_REPORT " + json.dumps(report))
    if args.render:
        render(base, cards, atlas, args.out, args.name)


main()
