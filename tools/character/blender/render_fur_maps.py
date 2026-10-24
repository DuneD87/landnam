"""Renders the maps of the fur garments' hair from real strands, in Cycles
(no window): thousands of curves grouped in locks, tapered, curled and
occluding each other, the way hair cards are made for games.

    blender -b --factory-startup --python tools/character/blender/render_fur_maps.py -- [--only=cards,pelt] [--samples=64]

 - fur_cards (2048 x 2048, 2 rows of 8 cells of 256 x 1024): locks for the
   hair cards of build_fur_armor.py, the root at the top of a cell and the
   tip below. Row 1 holds long locks (pointed, split, wavy), row 2 tufts,
   undercoat and loose wisps.
 - fur_pelt (1024 x 1024, repeats): hair combed down the image (+v) and lying
   on the hide, for the pelt seen between the cards.

Each gets <name>.png in models/equipable/stone_age/fur/, and the pelt
<name>_normal.png.
The first is data, not colour: R is how far along its strand a texel is (0
root, 1 tip), G a random value per strand, B the occlusion between strands
(and from the hide) and A the coverage. The shader colours it
(fur_common.gdshaderinc). The pelt's normal map is OpenGL-style, from the
strands' own round normals.
"""

import math
import os
import sys

import bpy
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "models/equipable/stone_age/fur")
OPTIONS = dict(a[2:].split("=", 1) for a in sys.argv[sys.argv.index("--") + 1:] if a.startswith("--")) \
    if "--" in sys.argv else {}
SAMPLES = int(OPTIONS.get("samples", "64"))

## A card cell, in metres: 1.6 cm across, 6.4 cm from root to tip.
CELL = (0.016, 0.064)
CELL_PIXELS = (256, 1024)
COLUMNS = 8
## The pelt's tile (m) and its pixels.
PELT_TILE = 0.08
PELT_PIXELS = 1024
## Strand radius at the root (m); it tapers to a tenth at the tip.
RADIUS = 0.00005
POINTS = 16


# --- Strands -------------------------------------------------------------------

class Strands:
    """Polylines with a radius per point, and how far along each point is."""

    def __init__(self):
        self.curves = []

    def add(self, points, radius):
        self.curves.append((np.asarray(points, dtype=np.float64), np.asarray(radius, dtype=np.float64)))

    def object(self, name, material):
        data = bpy.data.hair_curves.new(name)
        data.add_curves([len(c[0]) for c in self.curves])
        positions = np.concatenate([c[0] for c in self.curves])
        data.position_data.foreach_set("vector", positions.astype(np.float32).ravel())
        radius = data.attributes.new("radius", "FLOAT", "POINT")
        radius.data.foreach_set("value", np.concatenate([c[1] for c in self.curves]).astype(np.float32))
        data.materials.append(material)
        obj = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def strand(root, direction, length, side, lift, clump_to, clump, frizz, rng, curl=0.0, curl_freq=2.0):
    """One strand: from `root` along `direction` (unit, in the card's plane),
    pulled towards the polyline `clump_to(t)` by `clump(t)`, waving across by
    `frizz` and in and out of the plane by `curl`."""
    t = np.linspace(0.0, 1.0, POINTS)
    base = root[None, :] + direction[None, :] * (length * t)[:, None] + lift(t)[:, None] * np.array([0.0, 0.0, 1.0])
    target = clump_to(t)
    pull = clump(t)[:, None]
    p = base * (1.0 - pull) + target * pull
    phase = rng.uniform(0.0, 2.0 * np.pi)
    wave = np.sin(t * np.pi * rng.uniform(1.0, 3.0) + phase) * t
    p += side[None, :] * (frizz * wave)[:, None]
    if curl:
        p[:, 2] += curl * np.sin(t * np.pi * curl_freq + phase) * t
    return p


# --- Cards ---------------------------------------------------------------------

## Kinds of lock: guard hairs and how far they reach (share of the cell),
## how many points they gather into, how wide the lock is at the root (share
## of the cell), how much it bends to a side, and woolly underfur: how many
## hairs, how far they reach.
LOCKS = {
    "point": (300, 0.94, 1, 0.62, 0.12, 200, 0.42),
    "bent": (280, 0.9, 1, 0.58, -0.22, 190, 0.4),
    "split": (360, 0.88, 2, 0.72, 0.08, 220, 0.4),
    "fork": (400, 0.84, 3, 0.8, -0.06, 250, 0.38),
    "slim": (190, 0.96, 1, 0.42, 0.18, 120, 0.45),
    "wide": (440, 0.8, 2, 0.86, -0.14, 280, 0.4),
    "tuft": (340, 0.6, 3, 0.82, 0.1, 340, 0.36),
    "short": (300, 0.48, 2, 0.8, -0.1, 400, 0.34),
    "wool": (110, 0.5, 2, 0.9, 0.05, 650, 0.42),
    "wisp": (60, 0.9, 2, 0.5, 0.25, 30, 0.3),
}


def lock(strands, rng, origin, kind):
    """A lock in the cell whose top left corner is `origin` (x right, y up:
    the root is at the top): guard hairs gathering into pointed tips that
    bend a little, over crimped underfur. Nothing leaves the cell."""
    w, l = CELL
    guard, reach, points, width, bend, under, under_reach = LOCKS[kind]
    left, right = origin[0] + w * 0.06, origin[0] + w * 0.94
    cx = origin[0] + w * 0.5
    top = origin[1] - l * 0.02
    span = l * reach
    offsets = np.linspace(-1.0, 1.0, points) * w * 0.2 if points > 1 else np.zeros(1)
    tips = np.stack([cx + offsets + bend * w + rng.normal(0.0, w * 0.03, points),
                     top - span * rng.uniform(0.85, 1.0, points)], axis=1)
    t = np.linspace(0.0, 1.0, POINTS)
    for _ in range(guard):
        x0 = cx + np.clip(rng.normal(0.0, w * width * 0.3), -w * width * 0.5, w * width * 0.5)
        root = np.array([x0, top + rng.uniform(-0.015, 0.015) * l])
        tip = tips[np.argmin(np.abs(tips[:, 0] - x0)) if rng.random() < 0.8 else rng.integers(points)]
        tip = tip + rng.normal(0.0, 1.0, 2) * np.array([w * 0.05, l * 0.05])
        # A curve that leaves the root straight down and bends to its tip.
        control = np.array([x0 + (tip[0] - x0) * 0.25 + bend * w * 0.3, root[1] - span * 0.5])
        end = rng.uniform(0.55, 1.0) ** 0.5
        u = t * end
        xy = ((1 - u) ** 2)[:, None] * root + (2 * (1 - u) * u)[:, None] * control + (u ** 2)[:, None] * tip
        xy[:, 0] += rng.normal(0.0, 0.00025) * np.sin(u * np.pi * rng.uniform(1.0, 2.5) + rng.uniform(0, 6)) * u
        z = rng.uniform(-0.0012, 0.0012) + rng.normal(0.0, 0.0004) * u
        p = np.column_stack([np.clip(xy[:, 0], left, right), xy[:, 1], np.full(POINTS, z)])
        strands.add(p, RADIUS * rng.uniform(0.9, 1.4) * (1.0 - 0.9 * u ** 1.2))
    for _ in range(under):
        x0 = cx + np.clip(rng.normal(0.0, w * width * 0.34), -w * 0.44, w * 0.44)
        length = l * under_reach * rng.uniform(0.5, 1.0)
        toward = cx + bend * w * 0.4
        crimp = rng.uniform(0.0003, 0.0008)
        frequency = rng.uniform(5.0, 9.0)
        phase = rng.uniform(0, 2 * np.pi)
        x = x0 + (toward - x0) * 0.35 * t ** 1.5 + crimp * np.sin(t * frequency * np.pi + phase)
        y = top - l * 0.01 + rng.uniform(-0.01, 0.01) * l - length * t
        z = rng.uniform(-0.0015, 0.0005) + crimp * np.cos(t * frequency * np.pi + phase)
        p = np.column_stack([np.clip(x, left, right), y, z])
        strands.add(p, RADIUS * rng.uniform(0.5, 0.8) * (1.0 - 0.8 * t))


def normalized(v):
    return v / max(np.linalg.norm(v), 1e-12)


def cards():
    rng = np.random.default_rng(5)
    strands = Strands()
    kinds = [["point", "bent", "split", "slim", "fork", "wide", "point", "bent"],
             ["tuft", "short", "wool", "wisp", "tuft", "short", "wool", "split"]]
    w, l = CELL
    for row, names in enumerate(kinds):
        for column, kind in enumerate(names):
            lock(strands, rng, np.array([column * w, -row * l]), kind)
    size = (COLUMNS * w, 2 * l)
    render("fur_cards", strands, None, centre=(size[0] * 0.5, -size[1] * 0.5 + l * 0.0), span=size,
           pixels=(COLUMNS * CELL_PIXELS[0], 2 * CELL_PIXELS[1]))


# --- The pelt ------------------------------------------------------------------

def pelt():
    rng = np.random.default_rng(9)
    strands = Strands()
    tile = PELT_TILE
    down = np.array([0.0, -1.0, 0.0])
    side = np.array([1.0, 0.0, 0.0])
    # Locks of hair lying down the hide: a centre each, hairs round it
    # converging to its tip.
    for _ in range(1100):
        centre = rng.uniform(0.0, tile, 2)
        angle = rng.normal(0.0, 0.18) + 0.25 * math.sin(centre[0] / tile * 2 * math.pi * 2 + centre[1] * 30)
        direction = normalized(down * math.cos(angle) + side * math.sin(angle))
        across = normalized(np.cross(np.array([0.0, 0.0, 1.0]), direction))
        reach = rng.uniform(0.018, 0.034)
        tip = np.array([*centre, 0.0]) + direction * reach + np.array([0.0, 0.0, 0.0015])
        stand = rng.uniform(0.002, 0.005)
        for _ in range(rng.integers(25, 45)):
            root = np.array([*centre, 0.0]) + across * rng.normal(0.0, 0.0012) + direction * rng.normal(0.0, 0.001)
            length = reach * rng.uniform(0.6, 1.05)
            p = strand(root, direction, length, across,
                       lambda t, s=stand: s * np.sin(np.pi * np.minimum(t * 0.9, 1.0)) ** 0.7,
                       lambda t, a=np.array([*centre, 0.0]), b=tip: a[None, :] + (b - a)[None, :] * t[:, None],
                       lambda t: 0.7 * t ** 1.6, 0.0006, rng)
            radius = RADIUS * rng.uniform(0.8, 1.4) * (1.0 - 0.9 * np.linspace(0.0, 1.0, POINTS) ** 1.5)
            # Wrapped round the tile: copies where it crosses an edge.
            for dx in (-tile, 0.0, tile):
                for dy in (-tile, 0.0, tile):
                    q = p + np.array([dx, dy, 0.0])
                    if (q[:, 0].max() >= 0 and q[:, 0].min() <= tile and q[:, 1].max() >= 0
                            and q[:, 1].min() <= tile):
                        strands.add(q, radius)
    render("fur_pelt", strands, tile, centre=(tile * 0.5, tile * 0.5), span=(tile, tile),
           pixels=(PELT_PIXELS, PELT_PIXELS))


# --- Rendering -----------------------------------------------------------------

def emission(name, build):
    """A material that only emits what build(nodes, links) returns."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    links.new(build(nodes, links), em.inputs["Color"])
    links.new(em.outputs[0], out.inputs["Surface"])
    return material


def combine(nodes, links, r, g, b):
    node = nodes.new("ShaderNodeCombineColor")
    for i, socket in enumerate((r, g, b)):
        if socket is not None:
            links.new(socket, node.inputs[i])
    return node.outputs[0]


def data_material(nodes, links):
    info = nodes.new("ShaderNodeHairInfo")
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.004
    ao.samples = 16
    return combine(nodes, links, info.outputs["Intercept"], info.outputs["Random"], ao.outputs["AO"])


def normal_material(nodes, links):
    geometry = nodes.new("ShaderNodeNewGeometry")
    half = nodes.new("ShaderNodeVectorMath")
    half.operation = "MULTIPLY_ADD"
    half.inputs[1].default_value = (0.5, 0.5, 0.5)
    half.inputs[2].default_value = (0.5, 0.5, 0.5)
    links.new(geometry.outputs["Normal"], half.inputs[0])
    return half.outputs[0]


def render(name, strands, floor, centre, span, pixels):
    """Renders the strands from above (ortho, Raw: the values as they are)
    twice: data and normals. `floor` (a tile size) puts the hide under them."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.cycles.transparent_max_bounces = 0
    scene.render.film_transparent = True
    scene.render.filter_size = 1.0
    scene.view_settings.view_transform = "Raw"
    scene.view_settings.look = "None"
    scene.render.resolution_x, scene.render.resolution_y = pixels
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_depth = "16"
    scene.render.image_settings.color_mode = "RGBA"
    scene.cycles_curves.shape = "THICK"
    scene.cycles_curves.subdivisions = 2
    data = emission(name + "_data", data_material)
    normal = emission(name + "_normal", normal_material)
    obj = strands.object(name, data)
    hide = None
    if floor is not None:
        # The hide under the hair (at the roots' depth): what shows between
        # them, occluding them; root (0), no strand, flat.
        mesh = bpy.data.meshes.new("hide")
        pad = floor * 0.5
        mesh.from_pydata([(-pad, -pad, -0.0002), (floor + pad, -pad, -0.0002), (floor + pad, floor + pad, -0.0002),
                          (-pad, floor + pad, -0.0002)], [], [(0, 1, 2, 3)])
        hide = bpy.data.objects.new("hide", mesh)
        scene.collection.objects.link(hide)
        flat = emission("hide_data", lambda n, k: combine(n, k, None, None, ao_socket(n, k)))
        mesh.materials.append(flat)
    camera = bpy.data.cameras.new("top")
    camera.type = "ORTHO"
    camera.ortho_scale = max(span)
    cam = bpy.data.objects.new("top", camera)
    scene.collection.objects.link(cam)
    cam.location = (centre[0], centre[1], 0.5)
    cam.rotation_euler = (0.0, 0.0, 0.0)
    camera.clip_start = 0.01
    camera.clip_end = 2.0
    scene.camera = cam
    os.makedirs(OUT, exist_ok=True)
    results = {}
    passes = (("data", data), ("normal", normal)) if floor is not None else (("data", data),)
    for kind, material in passes:
        obj.data.materials[0] = material
        if hide is not None:
            hide.data.materials[0] = flat if kind == "data" else emission("hide_normal", lambda n, k: flat_normal(n))
        path = os.path.join(OUT, "_%s_%s.png" % (name, kind))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(path)
        image.colorspace_settings.name = "Non-Color"
        pixels_array = np.array(image.pixels[:], dtype=np.float32).reshape(pixels[1], pixels[0], 4)
        bpy.data.images.remove(image)
        os.remove(path)
        results[kind] = pixels_array
    rgba = results["data"]
    if floor is not None:
        # The pelt is opaque, and lit by its strands' relief (the cards by the
        # coat's normal: fur_card.gdshader). PNGs keep straight alpha: the
        # normal fades to flat where there is no hair.
        alpha = rgba[..., 3:4]
        nrm = results["normal"][..., :3] * alpha + np.array([0.5, 0.5, 1.0]) * (1.0 - alpha)
        save(name + "_normal", np.concatenate([nrm, np.ones_like(alpha)], axis=-1))
        rgba[..., 3] = 1.0
    save(name, rgba)
    for o in (obj, hide, cam):
        if o is not None:
            bpy.data.objects.remove(o)


def ao_socket(nodes, links):
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.004
    ao.samples = 16
    return ao.outputs["AO"]


def flat_normal(nodes):
    rgb = nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = (0.5, 0.5, 1.0, 1.0)
    return rgb.outputs[0]


def save(name, pixels):
    """An 8-bit PNG of raw values (rows top first)."""
    h, w = pixels.shape[:2]
    image = bpy.data.images.new(name, w, h, alpha=True)
    image.colorspace_settings.name = "Non-Color"
    image.pixels.foreach_set(np.clip(pixels, 0.0, 1.0).astype(np.float32).ravel())
    image.filepath_raw = os.path.join(OUT, name + ".png")
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    print("Saved", os.path.join(OUT, name + ".png"))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    only = OPTIONS.get("only", "cards,pelt").split(",")
    if "cards" in only:
        cards()
    if "pelt" in only:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        pelt()


main()
