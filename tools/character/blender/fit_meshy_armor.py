"""Fits garments made with Meshy (or any loose, unrigged model) onto the
player scan and skins them to the player skeleton.

    blender -b --factory-startup --python tools/character/blender/fit_meshy_armor.py -- \\
        <body.json> <pieces.json> <source dir> <output dir> [piece id ...]

<body.json> is written by tools/character/dump_skeleton.gd: the scan, its
triangles and weights, and the joints, in the space of the player skin (Y up,
+Z forward, metres). <pieces.json> lists the pieces (see stone_age_armor.json);
their models are looked up under <source dir>. For every piece the output dir
gets <id>.json (the mesh in skin space with its skeleton influences), its
textures and <id>_preview.png; tools/character/bake_meshy_armor.gd turns them
into equipable scenes, which ArmorFit then carries from the scan onto each
character, as it does with every armour.

A piece is fitted by its slot:
 - chest: scaled, its collar on the neck, centred on the torso.
 - legs: waist and hem at the given heights; each trouser leg is sheared
   onto the scan's leg (unless it is a skirt).
 - hands, feet: one model placed on each hand or foot, mirrored for the other
   side; its frame (which way the fingers, thumb, palm or toes point) is given
   in the entry. A mitten is centred on the hand's flesh, made as thick as
   the hand and its thumb turned onto the scan's (spread) thumb, so it takes
   the thumb's weights; a shoe's underside is laid flat under the foot and its
   shaft follows the shin.
Then the garment is pushed off the skin to its clearance: where its vertices
are inside the body or too close, where the skin pokes through between them
and, on hands and feet, where a point of the hand or foot has no garment in
front of it. The push spreads smoothly to the garment around it so loose
layers move together. Then it is relaxed like cloth back towards the shape
its triangles had when placed, off the skin (each vertex pushed by its own
amount stretches the texture between them), and pushed once more. The
weights are the scan's at the nearest point of its skin, limited to the
bones the slot may follow (the rest go to their nearest allowed parent) and
smoothed over the garment.

Entry keys (all optional but "model" and "slot"):
  model      path of the FBX/GLB under <source dir>
  slot       chest | legs | hands | feet
  scale      chest: uniform scale. hands/feet: multiplier on the automatic one.
  top        chest: collar height over the neck joint; legs: waist height (m, ground 0).
  hem        legs: hem height (m, ground 0).
  offset     [x, y, z] metres added after placing (Blender axes: +X left, -Y front, +Z up).
  width      legs, chest: extra scale of X and Y over the uniform one.
  turn       chest, legs: degrees the model is turned about the vertical first.
  length     chest, legs: times as long below the armpits (chest) or the waist
             (legs), as wide as it was.
  floor      chest, legs: nothing goes lower (m, ground 0): the deepest part is
             lengthened less, so it just reaches it.
  over       chest: ids of the pieces (legs) it is worn over; it is pushed off
             them (fitted first, their JSON in the output dir).
  ease       chest: [side, front, over] metres it may stand off the body: below
             the armpits at the sides and in front and behind, above them
             anywhere; more is taken in (a poncho made on a broad mannequin).
             legs: [side, front], null leaves that way as it is.
  skirt      legs: no per-leg shear; hanging parts follow the hips more.
  flare      legs: how much wider (to the sides) it is at the hem than at the
             waist (0.3: 30 %).
  forward    legs: metres its front comes forward, from the waist down to the
             crotch, hanging on from there.
  thighs     chest, legs (skirt): [front, back] share of the thigh weights kept
             below the crotch (SKIRT_FRONT/BACK, or HANG_THIGHS if it hangs);
             with the skirt's bones, the share that rides the thighs (HANG_RIDE).
  hang       legs (skirt): it hangs from the skirt's bones (body.json "skirt"),
             which the game swings, or without them from the hips, the thighs
             going through it (HANG_THIGHS); its lining stays on the hips.
  frame      hands: {"up", "thumb", "palm"}; feet: {"up", "toe"}; axes like "-x".
  tip        hands: how far the mitten reaches past the fingertips (m).
  sole       feet: height of the underside (m, ground 0).
  liner      chest, legs: line it (see LINER_OFFSET).
  decimate   ratio of faces kept.
  clearance  metres off the skin (default CLEARANCE).
"""

import json
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ARGS = sys.argv[sys.argv.index("--") + 1:]
BODY_JSON, PIECES_JSON, SOURCE_DIR, OUT_DIR = ARGS[:4]
ONLY = set(ARGS[4:])

## Height of the soles in skin space.
SOLE_HEIGHT = -0.9506
BONE_PREFIX = "mixamorig_"
CLEARANCE = 0.008
## How far the push off the skin spreads over the garment, in metres, by slot
## (a hand is thin: a wider push would reach the other side of it).
PUSH_SPREAD = {"chest": 0.05, "legs": 0.05, "hands": 0.015, "feet": 0.03}
## Deeper than this inside the body a vertex is taken to be past a thin part
## (a finger), not inside it, by slot. A chest piece made on a mannequin can
## have its shoulders well inside a broader body's.
PUSH_REACH = {"chest": 0.10, "legs": 0.035, "hands": 0.035, "feet": 0.035}
PUSH_PASSES = 4
## After the pushes the garment is relaxed (relax()): how many rounds, how
## much of what its edges want each vertex takes per round, how much it is
## held where the pushes left it, and how near the skin (m) a vertex must be
## to be checked against it every round (all are, every RELAX_RECHECK).
RELAX_STEPS = 300
RELAX_RATE = 1.5
RELAX_HOLD = 0.005
RELAX_NEAR = 0.03
RELAX_RECHECK = 10
## "over": how far past the skin-to-vertex distance an under-garment is
## still looked for (a pouch on it standing out).
UNDER_REACH = 0.10
## "ease" on a chest piece (take_in): it is taken in from this far below the
## shoulder joints, fully TAKE_IN_FADE lower, bending over from TAKE_IN_KNEE
## inside the body's outline.
TAKE_IN_ARMPIT = 0.08
## "floor": the part that would go lower keeps this share of its height
## (squashed flatter it would lie like a shelf).
FLOOR_SLOPE = 0.7
## What of a chest piece is deeper than NECK_DEPTH inside the body under the
## skin of these bones is cut away (open_neck).
NECK_BONES = ("Neck", "Head")
NECK_DEPTH = 0.005
TAKE_IN_FADE = 0.12
TAKE_IN_KNEE = 0.04
WEIGHT_SMOOTHING_STEPS = 24
WEIGHT_SMOOTHING = 0.5
## Up to this far from the skin a vertex keeps the skin's weights, smoothed
## only by NEAR_SMOOTHING of the rate (it must move as the skin under it, or
## the skin pokes through); from LOOSE out it takes them from the garment
## around it, which is what a loose flap hangs from.
HUGGING = 0.04
LOOSE = 0.10
NEAR_SMOOTHING = 0.1
## A vertex whose nearest skin follows the upper arm by more than the second
## of these keeps the skin's weights however far it is (from the first, partly).
SLEEVE_ARM = (0.3, 0.6)
## Share of the thigh weights a skirt or hanging hem keeps below the crotch
## (the rest go to the hips): in front it rides on the thighs, or a thigh
## coming forward goes through it; behind, a thigh going back pushes less.
## It is shared between both thighs by how far to each side it hangs: the
## middle follows both alike, so it does not split when they part.
SKIRT_FRONT = 0.95
SKIRT_BACK = 0.65
## The same, front and back, for a skirt that hangs ("hang": true): from the
## hips, barely swayed by the thighs (which go through it).
HANG_THIGHS = (0.15, 0.05)
## A hanging skirt with the skirt's bones (body.json "skirt") hangs from them
## instead, which the game swings: from SKIRT_BLEND over their ring down to as
## far under it, it goes from the skin's weights to theirs.
SKIRT_PREFIX = "skirt_"
SKIRT_BLEND = 0.05
## What of it rides the thighs as well, [front, back] (on_thighs()): from the
## chains alone, a thigh coming forward goes through it between two of them.
HANG_RIDE = (0.5, 0.0)

## The lining ("liner": true): the scan's own skin where the garment covers
## it, LINER_OFFSET off it, in the garment's colour darkened. It moves just as
## the skin does, so where the garment has a hole or a tear, or the skin pokes
## through it in a pose, leather shows instead of flesh. Skin counts as
## covered when LINER_HITS of nine rays (along its normal and tilted
## LINER_TILT around it) meet the garment within LINER_REACH: holes are lined,
## openings (a neckline, an armhole) are not. Gaps in what is covered up to
## LINER_CLOSE rings across are closed, and the edge is pulled one ring in
## from that, under the garment. It sits LINER_OFFSET off the skin (by slot:
## a chest lining over the legs one where both line the hips), or LINER_UNDER
## of the garment's clearance if that is less.
LINER_OFFSET = {"chest": 0.012, "legs": 0.009}
LINER_UNDER = 0.6
LINER_REACH = 0.2
LINER_TILT = 0.7
LINER_HITS = 4
LINER_CLOSE = 4
LINER_DARKEN = 0.7
LINER_KEPT = 0.5
## How the character's body weights were smoothed (export_mpfb_human.py).
BODY_SMOOTHING_STEPS = 24
BODY_SMOOTHING = 0.5
LINER_BONES = {
    "chest": ["Hips", "Spine", "Spine1", "Spine2", "Neck"] + [s + b for s in ("Left", "Right") for b in ("Shoulder", "Arm")],
    "legs": ["Hips", "Spine"] + [s + b for s in ("Left", "Right") for b in ("UpLeg", "Leg")],
}

## Bones each slot may follow; others hand their weight to the nearest
## allowed ancestor.
SIDES = ("Left", "Right")
FINGERS = [s + "Hand" + f + str(i) for s in SIDES for f in ("Thumb", "Index", "Middle", "Ring", "Pinky")
           for i in (1, 2, 3)]
ALLOWED = {
    "chest": ["Hips", "Spine", "Spine1", "Spine2", "Neck"] + [s + b for s in SIDES for b in ("Shoulder", "Arm", "UpLeg")],
    "legs": ["Hips", "Spine"] + [s + b for s in SIDES for b in ("UpLeg", "Leg", "Foot")],
    "hands": [s + b for s in SIDES for b in ("ForeArm", "Hand")] + FINGERS,
    "feet": [s + b for s in SIDES for b in ("Leg", "Foot", "ToeBase")],
}
AXES = {"x": 0, "y": 1, "z": 2}


# --- Spaces --------------------------------------------------------------------

## Skin space (Y up, +Z forward) <-> Blender (Z up, facing -Y, soles at 0).
def to_blender(p):
    return np.stack([p[..., 0], -p[..., 2], p[..., 1] - SOLE_HEIGHT], axis=-1)


def to_blender_dir(d):
    return np.stack([d[..., 0], -d[..., 2], d[..., 1]], axis=-1)


def to_skin(p):
    return np.stack([p[..., 0], p[..., 2] + SOLE_HEIGHT, -p[..., 1]], axis=-1)


def to_skin_dir(d):
    return np.stack([d[..., 0], d[..., 2], -d[..., 1]], axis=-1)


def axis_vector(name):
    v = np.zeros(3)
    v[AXES[name[-1]]] = -1.0 if name.startswith("-") else 1.0
    return v


def normalized(v):
    return v / max(np.linalg.norm(v), 1e-12)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --- The body ------------------------------------------------------------------

class Body:
    def __init__(self, path):
        with open(path) as f:
            data = json.load(f)
        self.bones = data["bones"]
        self.names = [b["name"] for b in self.bones]
        self.index = {n: i for i, n in enumerate(self.names)}
        self.parents = [b["parent"] for b in self.bones]
        self.joints = {b["name"]: to_blender(np.array(b["mesh_joint"])) for b in self.bones}
        mesh = data["mesh"]
        self.points = to_blender(np.array(mesh["positions"]).reshape(-1, 3))
        self.normals = to_blender_dir(np.array(mesh["normals"]).reshape(-1, 3))
        # Godot winds front faces clockwise, Blender counter-clockwise.
        self.triangles = np.array(mesh["indices"], dtype=np.int64).reshape(-1, 3)[:, [0, 2, 1]]
        bones = np.array(mesh["bones"], dtype=np.int64).reshape(-1, 4)
        weights = np.array(mesh["weights"]).reshape(-1, 4)
        self.dense = np.zeros((len(self.points), len(self.names)), dtype=np.float32)
        rows = np.repeat(np.arange(len(self.points)), 4)
        np.add.at(self.dense, (rows, bones.ravel()), weights.ravel())
        self.top = self.dense.argmax(axis=1)
        self.bvh = BVHTree.FromPolygons([Vector(p) for p in self.points], self.triangles.tolist())
        # The skirt's bones (SkirtBones), after the skeleton's: chains of
        # joints from the ring round the hips down, which the skin does not use.
        self.chains = []
        for bone in data.get("skirt", []):
            self.index[bone["name"]] = len(self.names)
            self.names.append(bone["name"])
            self.parents.append(self.index[bone["parent"]])
            self.joints[bone["name"]] = to_blender(np.array(bone["joint"]))
            if not bone["parent"].startswith(SKIRT_PREFIX):
                self.chains.append([])
            self.chains[-1].append(self.index[bone["name"]])
        if self.chains:
            self.dense = np.pad(self.dense, ((0, 0), (0, len(self.names) - self.dense.shape[1])))

    def joint(self, short):
        return self.joints[BONE_PREFIX + short]

    def region(self, shorts):
        """Points whose strongest bone is one of `shorts`."""
        ids = [self.index[BONE_PREFIX + s] for s in shorts]
        return self.points[np.isin(self.top, ids)]

    def nearest(self, p):
        """(location, normal, triangle) of the nearest skin point."""
        location, normal, face, _ = self.bvh.find_nearest(Vector(p))
        return np.array(location), np.array(normal), face

    def weights_at(self, p):
        """The skin's weights at its nearest point, and how far that is."""
        location, _, face = self.nearest(p)
        a, b, c = self.triangles[face]
        bary = barycentric(np.array(location), self.points[a], self.points[b], self.points[c])
        weights = bary[0] * self.dense[a] + bary[1] * self.dense[b] + bary[2] * self.dense[c]
        return weights, np.linalg.norm(np.asarray(p) - location)


def barycentric(p, a, b, c):
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11 = v0 @ v0, v0 @ v1, v1 @ v1
    d20, d21 = v2 @ v0, v2 @ v1
    den = d00 * d11 - d01 * d01
    if abs(den) < 1e-18:
        return np.array([1.0, 0.0, 0.0])
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    return np.clip(np.array([1.0 - v - w, v, w]), 0.0, 1.0)


# --- Garments ------------------------------------------------------------------

def import_model(path):
    before = set(bpy.data.objects)
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.data.objects):
        if o not in before and o != obj:
            bpy.data.objects.remove(o)
    return obj


def coords(obj):
    v = np.zeros(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", v)
    return v.reshape(-1, 3)


def set_coords(obj, points):
    obj.data.vertices.foreach_set("co", points.ravel())
    obj.data.update()


def edges_of(obj):
    e = np.zeros(len(obj.data.edges) * 2, dtype=np.int64)
    obj.data.edges.foreach_get("vertices", e)
    return e.reshape(-1, 2)


def decimate(obj, ratio):
    modifier = obj.modifiers.new("decimate", "DECIMATE")
    modifier.ratio = ratio
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def duplicate(obj):
    copy = obj.copy()
    copy.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(copy)
    return copy


def mirror_x(obj):
    """Mirrors across X, keeping the faces facing out."""
    set_coords(obj, coords(obj) * np.array([-1.0, 1.0, 1.0]))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.flip_normals()
    bpy.ops.object.mode_set(mode="OBJECT")


def join(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return objects[0]


# --- Placing -------------------------------------------------------------------

def turned(p, entry):
    """`p` turned entry["turn"] degrees about the vertical (seen from above,
    anticlockwise): for a model made facing the other way."""
    a = np.radians(entry.get("turn", 0.0))
    c, s = np.cos(a), np.sin(a)
    return p @ np.array([[c, s, 0.0], [-s, c, 0.0], [0.0, 0.0, 1.0]])


def place_chest(obj, body, entry):
    p = turned(coords(obj), entry)
    scale = entry.get("scale", 0.5)
    width = entry.get("width", 1.0)
    p = p * np.array([scale * width, scale * width, scale])
    top = p[:, 2].max()
    upper = p[p[:, 2] > top - 0.3 * (top - p[:, 2].min())]
    centre = (upper.min(axis=0) + upper.max(axis=0)) * 0.5
    torso = body.region(["Spine1", "Spine2"])
    torso_centre = (torso.min(axis=0) + torso.max(axis=0)) * 0.5
    target = np.array([torso_centre[0], torso_centre[1], body.joint("Neck")[2] + entry.get("top", 0.0)])
    p += target - np.array([centre[0], centre[1], top])
    p = lengthened(p, body.joint("LeftArm")[2] - TAKE_IN_ARMPIT, entry)
    if "ease" in entry:
        p = take_in(p, body, *entry["ease"][:2])
    set_coords(obj, p + np.array(entry.get("offset", [0.0, 0.0, 0.0])))


def lengthened(p, pivot, entry):
    """`p` with what is below `pivot` (the armpits, the waist) made
    entry["length"] times as long, its width as it was. If its lowest point
    would then go below entry["floor"], what is deepest is lengthened less
    (FLOOR_SLOPE of its height: squashed flatter it would lie like a shelf),
    from as low as that lets it reach the floor."""
    out = p.copy()
    depth = np.maximum(pivot - out[:, 2], 0.0)
    length = entry.get("length", 1.0)
    reach = depth * length
    deepest = depth.max()
    if "floor" in entry and deepest * length > pivot - entry["floor"]:
        room = pivot - entry["floor"]
        bend = 0.0 if length <= FLOOR_SLOPE else np.clip((room - FLOOR_SLOPE * deepest) / (length - FLOOR_SLOPE), 0.0, deepest)
        reach = np.where(depth <= bend, depth * length,
                         bend * length + (depth - bend) * (room - bend * length) / max(deepest - bend, 1e-9))
    below = out[:, 2] < pivot
    out[below, 2] = pivot - reach[below]
    return out


def open_neck(obj, body):
    """Cuts away what of a chest piece is inside the body under the neck or
    the head (straight up from it, the skin it comes out through is theirs): a
    model made on a mannequin is closed over the shoulders, and pushed out of
    the neck that cap would stand up round it like a funnel."""
    neck = [body.index[BONE_PREFIX + b] for b in NECK_BONES]
    up = Vector((0.0, 0.0, 1.0))

    def under_neck(v, location, face):
        hit = body.bvh.ray_cast(v.co, up, 1.0)[2]
        return hit is not None and body.top[body.triangles[hit][0]] in neck
    cut_inside(obj, body, under_neck, "open_neck")


def cut_inside(obj, body, where, name):
    """Cuts away the vertices of `obj` deeper than NECK_DEPTH inside the body
    for which where(vertex, nearest skin point, its triangle) holds."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    cut = []
    for v in bm.verts:
        location, normal, face = body.nearest(np.array(v.co))
        if (np.array(v.co) - location) @ normal < -NECK_DEPTH and where(v, location, face):
            cut.append(v)
    bmesh.ops.delete(bm, geom=cut, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    print("%s: %d vertices cut" % (name, len(cut)))


def take_in(p, body, side, front):
    """Takes in what a chest piece made on a broad mannequin (a poncho) has
    over the body below the armpits: its sides come to `side` off the torso,
    so a lowered arm hangs outside them rather than through them, and its
    front and back to `front` off the most the chest or back stands out above
    them (cloth hangs from there). What is over the torso keeps its shape."""
    trunk = ["Hips", "Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder", "LeftUpLeg", "RightUpLeg"]
    ids = [body.index[BONE_PREFIX + b] for b in trunk]
    torso = body.points[np.isin(body.top, ids)]
    armpit = body.joint("LeftArm")[2] - TAKE_IN_ARMPIT
    levels = np.arange(p[:, 2].min() - 0.01, min(armpit, p[:, 2].max()) + 0.02, 0.01)
    rows = []
    for z in levels:
        s = torso[np.abs(torso[:, 2] - z) < 0.015]
        rows.append([s[:, 0].min(), s[:, 0].max(), s[:, 1].min(), s[:, 1].max()] if len(s) else [np.nan] * 4)
    rows = np.array(rows)
    # Gaps (below the knees): the nearest level that has torso.
    known = np.flatnonzero(~np.isnan(rows[:, 0]))
    rows = rows[known[np.abs(levels[:, None] - levels[known][None, :]).argmin(axis=1)]]
    # Front and back: the most they stand out from that level up.
    rows[:, 2] = np.minimum.accumulate(rows[::-1, 2])[::-1]
    rows[:, 3] = np.maximum.accumulate(rows[::-1, 3])[::-1]
    at = np.clip(np.round((p[:, 2] - levels[0]) / 0.01).astype(int), 0, len(levels) - 1)
    left, right, fore, back = rows[at].T
    cx, cy = (left + right) * 0.5, (fore + back) * 0.5
    strength = smoothstep(armpit, armpit - TAKE_IN_FADE, p[:, 2])
    out = p.copy()
    for axis, low, high, ease in ((0, left, right, side), (1, fore, back, front)):
        if ease is None:
            continue
        centre = (low + high) * 0.5
        r = p[:, axis] - centre
        reach = np.where(r < 0.0, centre - low, high - centre)
        taken = soft_limit(np.abs(r), reach, ease)
        out[:, axis] = centre + np.sign(r) * (np.abs(r) + (taken - np.abs(r)) * strength)
    return out


def draw_in(obj, body, over):
    """Above the armpits, after the push off the skin: nothing of a chest
    piece stands more than `over` off the skin (a thick pelt on the
    shoulders, or what went out with a cap pushed out of the trapezius); from
    half that it is drawn in along the way to the skin, so its layers keep
    their order."""
    p = coords(obj)
    armpit = body.joint("LeftArm")[2] - TAKE_IN_ARMPIT
    strength = 1.0 - smoothstep(armpit, armpit - TAKE_IN_FADE, p[:, 2])
    knee = over * 0.5
    for i, q in enumerate(p):
        if strength[i] <= 0.0:
            continue
        location, normal, _ = body.nearest(q)
        offset = q - location
        distance = np.linalg.norm(offset)
        if distance <= knee or offset @ normal <= 0.0:
            continue
        drawn = knee + (over - knee) * np.tanh((distance - knee) / (over - knee))
        p[i] = location + offset * (1.0 + (drawn / distance - 1.0) * strength[i])
    set_coords(obj, p)


def soft_limit(r, reach, ease):
    """r up to reach - TAKE_IN_KNEE as it is; past that it bends over towards
    reach + ease and never passes it."""
    knee = reach - TAKE_IN_KNEE
    span = TAKE_IN_KNEE + ease
    return np.where(r <= knee, r, knee + span * np.tanh((r - knee) / span))


def place_legs(obj, body, entry):
    p = turned(coords(obj), entry)
    top, bottom = p[:, 2].max(), p[:, 2].min()
    waist = entry.get("top", body.joint("Hips")[2] + 0.06)
    hem = entry.get("hem", body.joint("LeftFoot")[2] + 0.03)
    scale = (waist - hem) / (top - bottom)
    width = entry.get("width", 1.0)
    p = (p - np.array([0.0, 0.0, bottom])) * np.array([scale * width, scale * width, scale]) + np.array([0, 0, hem])
    hips = body.region(["Hips"])
    upper = p[p[:, 2] > waist - 0.1]
    centre = (upper.min(axis=0) + upper.max(axis=0)) * 0.5
    hips_centre = (hips.min(axis=0) + hips.max(axis=0)) * 0.5
    p[:, :2] += hips_centre[:2] - centre[:2]
    p = lengthened(p, waist, entry)
    if "ease" in entry:
        p = take_in(p, body, *entry["ease"][:2])
    if "flare" in entry:
        # Wider and wider to the sides down to the hem, the waist as it was
        # (in front it would stand out from the legs).
        down = np.clip((waist - p[:, 2]) / (waist - p[:, 2].min()), 0.0, 1.0)
        p[:, 0] = hips_centre[0] + (p[:, 0] - hips_centre[0]) * (1.0 + entry["flare"] * down)
    if "forward" in entry:
        # The front comes forward from the waist down to the crotch and
        # hangs on from there (a thigh coming forward goes through it less).
        crotch = body.joint("LeftUpLeg")[2] - 0.08
        front = smoothstep(body.joint("Hips")[1] + 0.03, body.joint("Hips")[1] - 0.05, p[:, 1])
        p[:, 1] -= entry["forward"] * front * smoothstep(waist, crotch, p[:, 2])
    if not entry.get("skirt", False):
        p = shear_legs(p, body)
    set_coords(obj, p + np.array(entry.get("offset", [0.0, 0.0, 0.0])))


def shear_legs(p, body):
    """Moves each trouser leg, slice by slice, onto the scan's leg."""
    crotch = body.joint("LeftUpLeg")[2] - 0.08
    out = p.copy()
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        flesh = body.region([side + "UpLeg", side + "Leg"])
        mine = (p[:, 0] * sign) > 0.0
        heights = np.linspace(p[:, 2].min(), crotch, 12)
        step = heights[1] - heights[0]
        garment_c, body_c = [], []
        for h in heights:
            g = p[mine & (np.abs(p[:, 2] - h) < step)]
            b = flesh[np.abs(flesh[:, 2] - h) < step]
            if len(b) < 10:
                b = body.region([side + "Leg", side + "Foot"])
                b = b[np.abs(b[:, 2] - h) < step * 2] if len(b) else b
            garment_c.append((g.min(axis=0)[:2] + g.max(axis=0)[:2]) * 0.5 if len(g) else None)
            body_c.append((b.min(axis=0)[:2] + b.max(axis=0)[:2]) * 0.5 if len(b) else None)
        shift = np.array([(b - g) if g is not None and b is not None else np.zeros(2)
                          for g, b in zip(garment_c, body_c)])
        z = p[mine, 2]
        delta = np.stack([np.interp(z, heights, shift[:, 0]), np.interp(z, heights, shift[:, 1])], axis=-1)
        ramp = 1.0 - smoothstep(crotch - 0.12, crotch + 0.04, z)
        out[mine, :2] += delta * ramp[:, None]
    return out


def frame_matrix(columns):
    return np.stack(columns, axis=1)


def place_hand(obj, body, entry, side):
    """Rigidly puts a mitten on one hand; returns whether it was mirrored."""
    frame = entry["frame"]
    up, thumb, palm = (axis_vector(frame[k]) for k in ("up", "thumb", "palm"))
    # A left hand has thumb x palm = fingers.
    left_model = np.dot(np.cross(thumb, palm), up) > 0.0
    p = coords(obj)
    mirrored = left_model != (side == "Left")
    if mirrored:
        mirror_x(obj)
        p = coords(obj)
        up, thumb, palm = (v * np.array([-1.0, 1.0, 1.0]) for v in (up, thumb, palm))
    wrist = body.joint(side + "Hand")
    tip = body.joint(side + "HandMiddle4")
    axis_t = normalized(tip - wrist)
    thumb_t = body.joint(side + "HandThumb2") - wrist
    thumb_t = normalized(thumb_t - axis_t * (thumb_t @ axis_t))
    palm_t = np.cross(axis_t, thumb_t) if side == "Left" else np.cross(thumb_t, axis_t)
    source = frame_matrix([up, thumb, palm])
    target = frame_matrix([axis_t, thumb_t, palm_t])
    # The hand's flesh (palm and the four fingers) and the mitten, each in
    # its own frame: along the fingers, towards the thumb, out of the palm.
    flesh = [side + "Hand"] + [side + "Hand" + f + str(i) for f in ("Index", "Middle", "Ring", "Pinky")
                               for i in (1, 2, 3)]
    hand = (body.region(flesh) - wrist) @ target
    hand_centre = (hand.min(axis=0) + hand.max(axis=0)) * 0.5
    local = p @ source
    length = local[:, 0].max() - local[:, 0].min()
    # Its fingers: a band under the rounded tip, above the thumb.
    top = local[:, 0].max()
    upper = local[(local[:, 0] > top - 0.25 * length) & (local[:, 0] < top - 0.1 * length)]
    low, high = np.percentile(upper, 2, axis=0), np.percentile(upper, 98, axis=0)
    width = high[1] - low[1]
    scale = (hand[:, 1].max() - hand[:, 1].min()) * 1.25 / width * entry.get("scale", 1.0)
    local *= scale
    low, high = low * scale, high * scale
    centre = np.array([top * scale, (low[1] + high[1]) * 0.5, (low[2] + high[2]) * 0.5])
    # Its tip past the fingertips, its fingers around the hand's.
    anchor = np.array([hand[:, 0].max() + entry.get("tip", 0.015), hand_centre[1], hand_centre[2]])
    local -= centre
    # As thick as the hand and a bit more, if it is flatter.
    thickness = high[2] - low[2]
    needed = hand[:, 2].max() - hand[:, 2].min() + 2.0 * entry.get("clearance", CLEARANCE) + 0.008
    local[:, 2] *= max(needed / thickness, 1.0)
    thumb_onto(local, high[1] - centre[1],
               (body.joint(side + "HandThumb1") - wrist) @ target - anchor,
               (body.joint(side + "HandThumb4") - wrist) @ target - anchor)
    placed = local @ target.T + wrist + target @ anchor
    placed += np.array(entry.get("offset", [0.0, 0.0, 0.0])) * np.array([1.0 if side == "Left" else -1.0, 1.0, 1.0])
    set_coords(obj, placed)
    return mirrored


def rotation_between(a, b):
    a, b = normalized(a), normalized(b)
    v = np.cross(a, b)
    c = a @ b
    k = np.array([[0.0, -v[2], v[1]], [v[2], 0.0, -v[0]], [-v[1], v[0], 0.0]])
    return np.eye(3) + k + k @ k / (1.0 + c)


def thumb_onto(local, edge, base, tip):
    """Turns the mitten's thumb (what sticks out past the fingers' `edge` on
    the thumb side; frame: along, thumb side, palm side) about where it
    leaves the mitten, so it points from the hand's thumb `base` to its
    `tip`: the thumb then takes the thumb's weights and follows it."""
    out = local[:, 1] - edge
    # Between the hand's thumb root and the mitten's tip, not the cuff.
    lower = (local[:, 0] < local[:, 0].max() - 0.04) & (local[:, 0] > base[0] - 0.03)
    thumb = (out > 0.004) & lower
    if thumb.sum() < 20:
        return
    points = local[thumb]
    root = points[out[thumb] < np.percentile(out[thumb], 20)]
    pivot = np.array([root[:, 0].mean(), edge, root[:, 2].mean()])
    far = points[np.argmax(np.linalg.norm(points - pivot, axis=1))]
    turn = rotation_between(far - pivot, tip - base)
    # Fully turned a little past the edge, not at all inside the mitten.
    blend = smoothstep(0.0, 0.02, out) * lower
    turned = (local - pivot) @ turn.T + pivot
    local[:] = local + (turned - local) * blend[:, None]


def flatten_sole(obj, placed, foot, sole):
    """Lays the underside of the shoe flat at `sole` under the foot: a sole
    that curves up at the toes would leave the scan's flat toes out."""
    normals = np.zeros(len(obj.data.vertices) * 3)
    set_coords(obj, placed)
    obj.data.vertices.foreach_get("normal", normals)
    down = -normals.reshape(-1, 3)[:, 2]
    low, high = foot[:, :2].min(axis=0) - 0.015, foot[:, :2].max(axis=0) + 0.015
    under = np.all((placed[:, :2] > low) & (placed[:, :2] < high), axis=1)
    bottom = foot[:, 2].min()
    weight = smoothstep(0.2, 0.6, down) * (1.0 - smoothstep(bottom + 0.03, bottom + 0.05, placed[:, 2])) * under
    out = placed.copy()
    out[:, 2] = np.where(placed[:, 2] > sole, placed[:, 2] + (sole - placed[:, 2]) * weight, placed[:, 2])
    return out


def place_foot(obj, body, entry, side):
    frame = entry["frame"]
    up, toe = axis_vector(frame["up"]), axis_vector(frame["toe"])
    across = np.cross(up, toe)
    if side == "Right":
        mirror_x(obj)
        up, toe = (v * np.array([-1.0, 1.0, 1.0]) for v in (up, toe))
        across = np.cross(up, toe)
    p = coords(obj)
    ankle = body.joint(side + "Foot")
    toe_end = body.joint(side + "Toe_End")
    forward = toe_end - ankle
    forward[2] = 0.0
    forward = normalized(forward)
    up_t = np.array([0.0, 0.0, 1.0])
    across_t = np.cross(up_t, forward)
    source = frame_matrix([up, toe, across])
    target = frame_matrix([up_t, forward, across_t])
    local = p @ source
    sole = local[local[:, 0] < local[:, 0].min() + 0.15 * (local[:, 0].max() - local[:, 0].min())]
    foot = body.region([side + "Foot", side + "ToeBase", side + "Toe_End"])
    along = foot @ forward
    foot_length = along.max() - along.min()
    sole_length = sole[:, 1].max() - sole[:, 1].min()
    scale = (foot_length + 0.035) / sole_length * entry.get("scale", 1.0)
    local *= scale
    sole = sole * scale
    heel_local = sole[:, 1].min()
    across_mid = (sole[:, 2].min() + sole[:, 2].max()) * 0.5
    foot_across = foot @ across_t
    heel = along.min() - 0.018
    placed = np.outer(local[:, 0] - local[:, 0].min(), up_t) + np.outer(local[:, 1] - heel_local + heel, forward) \
        + np.outer(local[:, 2] - across_mid + (foot_across.min() + foot_across.max()) * 0.5, across_t)
    placed[:, 2] += entry.get("sole", -0.008)
    placed = flatten_sole(obj, placed, foot, entry.get("sole", -0.008))
    # The shaft follows the shin.
    knee = body.joint(side + "Leg")
    rise = smoothstep(ankle[2], ankle[2] + 0.12, placed[:, 2])
    lean = (knee[:2] - ankle[:2]) / (knee[2] - ankle[2])
    placed[:, :2] += np.outer(np.maximum(placed[:, 2] - ankle[2], 0.0) * rise, lean)
    placed += np.array(entry.get("offset", [0.0, 0.0, 0.0])) * np.array([1.0 if side == "Left" else -1.0, 1.0, 1.0])
    set_coords(obj, placed)


# --- Off the skin --------------------------------------------------------------

def push_out(obj, body, clearance, spread, reach, cover=None, under=None):
    """Pushes the garment off the body to `clearance`: where its vertices are
    inside or too close, where the skin pokes through between them (a ray
    from the skin inwards meets the garment before leaving the body) and,
    for the skin points `cover` (indices) it must enclose, where one has no
    garment over it (a toe under a sole that curves up). Off the garments
    `under` it (a BVH) too: a vertex goes `clearance` past the last of them
    on the way from the skin to it. Every vertex takes
    the pushes needed within `spread` of it, fading with distance, so loose
    layers move together (as ArmorFit does with what is left)."""
    for _ in range(PUSH_PASSES):
        p = coords(obj)
        needed, at = [], []
        for q in p:
            location, normal, _ = body.nearest(q)
            depth = clearance - (q - location) @ normal
            if 0.0 < depth < reach + clearance:
                needed.append(normal * depth)
                at.append(q)
            elif under is not None and depth < 0.0:
                lift = past_under(under, location, q, clearance)
                if lift is not None:
                    needed.append(lift)
                    at.append(q)
        garment = BVHTree.FromPolygons([Vector(q) for q in p], [list(f.vertices) for f in obj.data.polygons])
        low, high = p.min(axis=0) - reach, p.max(axis=0) + reach
        near = np.all((body.points > low) & (body.points < high), axis=1)
        for q, n in zip(body.points[near], body.normals[near]):
            inward = Vector(-n)
            location, _, _, distance = garment.ray_cast(Vector(q), inward, reach)
            if location is None:
                continue
            exit_at = body.bvh.ray_cast(Vector(q) + inward * 1e-4, inward, distance)[0]
            if exit_at is None:
                needed.append(n * (distance + clearance))
                at.append(np.array(location))
        if cover is not None:
            for q, n in zip(body.points[cover], body.normals[cover]):
                if garment.ray_cast(Vector(q + n * 1e-4), Vector(n), 0.1)[0] is not None:
                    continue
                location = np.array(garment.find_nearest(Vector(q))[0])
                depth = (q - location) @ n + clearance
                if depth > 0.0:
                    needed.append(n * depth)
                    at.append(location)
        if not needed:
            return
        set_coords(obj, spread_push(p, np.array(needed), np.array(at), spread))


def spread_push(p, needed, at, spread):
    """`p` with the pushes `needed` at the points `at`: every point takes
    those within `spread` of it, fading with distance."""
    kd = KDTree(len(at))
    for i, q in enumerate(at):
        kd.insert(q, i)
    kd.balance()
    # Full push within `slack` of a source, so a vertex next to one gets all it needs.
    slack = spread * 0.2
    shifted = p.copy()
    for i, q in enumerate(p):
        found = kd.find_range(q, spread)
        if not found:
            continue
        idx = np.array([f[1] for f in found])
        d = np.maximum(np.array([f[2] for f in found]) - slack, 0.0) / (spread - slack)
        fade = (1.0 - d * d) ** 2
        direction = (needed[idx] * fade[:, None]).sum(axis=0)
        amount = (np.linalg.norm(needed[idx], axis=1) * fade).max()
        if amount > 0.0 and np.linalg.norm(direction) > 1e-9:
            shifted[i] = q + normalized(direction) * amount
    return shifted


def off_legs(obj, body, clearance, spread):
    """Takes a hanging skirt out of the legs outwards from the hips, as cloth
    lies over both legs, before the push off the skin: pushed out along the
    skin it would wrap round a leg, and the skirt not following the legs,
    that would be left as a band across the leg once the leg moves."""
    legs = [body.index[BONE_PREFIX + s + b] for s in SIDES for b in ("UpLeg", "Leg", "Foot")]
    hips = body.joint("Hips")
    for _ in range(PUSH_PASSES):
        p = coords(obj)
        needed, at = [], []
        for q in p:
            location, normal, face = body.nearest(q)
            if (q - location) @ normal > clearance or body.top[body.triangles[face][0]] not in legs:
                continue
            out = np.array([q[0] - hips[0], q[1] - hips[1], 0.0])
            if np.linalg.norm(out) < 1e-6:
                continue
            out = normalized(out)
            # Where the ray outwards leaves the leg: from a little further in,
            # the first leg skin it meets if that is inside the leg, else the
            # second (it went in by the first).
            start = q - out * (clearance + 0.002)
            hits = []
            origin = Vector(start)
            while len(hits) < 2:
                hit = body.bvh.ray_cast(origin, Vector(out), 0.4)
                if hit[0] is None or body.top[body.triangles[hit[2]][0]] not in legs:
                    break
                hits.append((np.array(hit[0]), Vector(hit[1]).dot(Vector(out)) > 0.0))
                origin = hit[0] + Vector(out) * 1e-4
            exits = [h for h, leaving in hits if leaving]
            if not exits:
                continue
            reach = (exits[0] - q) @ out + clearance
            if reach > 0.0:
                needed.append(out * reach)
                at.append(q)
        if not needed:
            return
        set_coords(obj, spread_push(p, np.array(needed), np.array(at), spread))


def relax(obj, body, rest, clearance, reach, legs=True):
    """Lets the garment take back, as cloth would, the shape its triangles
    had at `rest` (placed, before the pushes): each push moves its vertices
    by its own amount, which stretches the triangles between them and the
    texture on them. Every edge eases towards its rest length (RELAX_STEPS
    rounds, each vertex by the mean of its edges' wants, RELAX_RATE of it)
    while nothing goes closer to the skin than `clearance` (what is deeper
    than `reach` is past a thin part, as for the push; with `legs` False the
    legs' skin does not count, off_legs() takes it out of them) and every
    vertex is held RELAX_HOLD towards where the pushes left it, so the
    garment does not drift."""
    edges = edges_of(obj)
    length = np.linalg.norm(rest[edges[:, 1]] - rest[edges[:, 0]], axis=1)
    p = coords(obj)
    held = p.copy()
    count = np.maximum(np.bincount(edges.ravel(), minlength=len(p)), 1).astype(float)[:, None]
    leg_bones = [body.index[BONE_PREFIX + s + b] for s in SIDES for b in ("UpLeg", "Leg", "Foot")]
    near = np.arange(len(p))
    for step in range(RELAX_STEPS):
        d = p[edges[:, 1]] - p[edges[:, 0]]
        current = np.linalg.norm(d, axis=1)
        want = ((current - length) / np.maximum(current, 1e-12))[:, None] * d * 0.5
        shift = np.zeros_like(p)
        np.add.at(shift, edges[:, 0], want)
        np.add.at(shift, edges[:, 1], -want)
        p += RELAX_RATE * shift / count
        p += RELAX_HOLD * (held - p)
        # Only what was near the skin a few rounds ago can have reached it.
        check = np.arange(len(p)) if step % RELAX_RECHECK == 0 else near
        close = []
        for i in check:
            location, normal, face = body.nearest(p[i])
            if not legs and body.top[body.triangles[face][0]] in leg_bones:
                continue
            gap = (p[i] - location) @ normal
            if gap < clearance + RELAX_NEAR:
                close.append(i)
            if -reach < gap < clearance:
                p[i] += normal * (clearance - gap)
        if step % RELAX_RECHECK == 0:
            near = np.array(close, dtype=np.int64)
    set_coords(obj, p)


def past_under(under, skin, q, clearance):
    """How far `q` has to go out (a vector) to be `clearance` past the last
    surface of `under` between the skin point `skin` and it, or None."""
    offset = q - skin
    distance = np.linalg.norm(offset)
    direction = Vector(offset / distance)
    origin = Vector(skin)
    last = None
    travelled = 0.0
    while True:
        hit = under.ray_cast(origin + direction * 1e-4, direction, distance + UNDER_REACH - travelled)
        if hit[0] is None:
            break
        travelled += hit[3] + 1e-4
        origin = hit[0]
        last = travelled
    if last is None or last + clearance <= distance:
        return None
    return offset / distance * (last + clearance - distance)


def under_garments(ids):
    """The fitted garments `ids` (their JSON in the output dir), as one BVH."""
    points, faces = [], []
    for piece_id in ids:
        with open(os.path.join(OUT_DIR, piece_id + ".json")) as f:
            garment = json.load(f)["surfaces"][0]
        start = sum(len(p) for p in points)
        points.append(to_blender(np.array(garment["positions"]).reshape(-1, 3)))
        faces.append(np.array(garment["indices"]).reshape(-1, 3) + start)
    points, faces = np.concatenate(points), np.concatenate(faces)
    return BVHTree.FromPolygons([Vector(p) for p in points], faces.tolist())


# --- Lining --------------------------------------------------------------------

def liner(garment, body, bones, offset):
    """The lining under `garment` where the skin follows `bones`, `offset` off
    it: a new object, or None if it covers no skin."""
    mesh = bpy.data.meshes.new("liner")
    mesh.from_pydata(body.points.tolist(), [], body.triangles.tolist())
    bm = bmesh.new()
    bm.from_mesh(mesh)
    # Godot splits the skin at its UV seams.
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.normal_update()
    points = coords(garment)
    cover = BVHTree.FromPolygons([Vector(q) for q in points], [list(f.vertices) for f in garment.data.polygons])
    allowed = {body.index[BONE_PREFIX + b] for b in bones}
    kd = KDTree(len(body.points))
    for i, q in enumerate(body.points):
        kd.insert(q, i)
    kd.balance()
    covered = set()
    candidates = set()
    for v in bm.verts:
        if body.top[kd.find(v.co)[1]] not in allowed:
            continue
        candidates.add(v)
        n = v.normal
        side = n.orthogonal().normalized()
        other = n.cross(side)
        hits = 0
        for a, b in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            d = (n + (side * a + other * b) * LINER_TILT).normalized()
            if cover.ray_cast(v.co + n * 0.002, d, LINER_REACH)[0] is not None:
                hits += 1
        if hits >= LINER_HITS:
            covered.add(v)
    # Close the gaps (grow, then shrink one ring more, so the edge stays under the garment).
    for _ in range(LINER_CLOSE):
        covered |= {e.other_vert(v) for v in covered for e in v.link_edges} & candidates
    kept = covered
    for _ in range(LINER_CLOSE + 1):
        kept = {v for v in kept if all(e.other_vert(v) in kept for e in v.link_edges)}
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v not in kept], context="VERTS")
    if not bm.verts:
        bm.free()
        return None
    for v in bm.verts:
        v.co += v.normal * offset
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("liner", mesh)
    bpy.context.scene.collection.objects.link(obj)
    decimate(obj, LINER_KEPT)
    return obj


def liner_color(maps):
    """The garment's mean albedo, darkened (sRGB)."""
    if "albedo" not in maps:
        return [0.12, 0.09, 0.07]
    image = bpy.data.images.load(maps["albedo"])
    pixels = np.zeros(image.size[0] * image.size[1] * image.channels, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    mean = pixels.reshape(-1, image.channels)[:, :3].mean(axis=0)
    bpy.data.images.remove(image)
    return (mean * LINER_DARKEN).round(4).tolist()


def skin_liner(obj, body, slot, offset):
    """The skin's own weights, each vertex where it was on the skin, smoothed
    as the character's body had them smoothed when they were carried onto it
    (tools/character/blender/export_mpfb_human.py), so it bends as that skin."""
    p = coords(obj)
    normals = np.zeros(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("normal", normals)
    p = p - normals.reshape(-1, 3) * offset
    remap = allowed_map(body, slot)
    folded = np.zeros((len(p), len(body.names)), dtype=np.float32)
    for i, q in enumerate(p):
        dense, _ = body.weights_at(q)
        np.add.at(folded[i], remap, dense)
    edges = edges_of(obj)
    degree = np.zeros(len(p))
    np.add.at(degree, edges.ravel(), 1.0)
    for _ in range(BODY_SMOOTHING_STEPS):
        neighbours = np.zeros_like(folded)
        np.add.at(neighbours, edges[:, 0], folded[edges[:, 1]])
        np.add.at(neighbours, edges[:, 1], folded[edges[:, 0]])
        mean = neighbours / np.maximum(degree, 1.0)[:, None]
        folded += BODY_SMOOTHING * (degree[:, None] > 0) * (mean - folded)
    return top_four(folded)


# --- Skinning ------------------------------------------------------------------

def allowed_map(body, slot, skirt=False):
    """For every bone, the allowed bone that takes its weight. A skirt does
    not follow the shins or the feet (its hem hangs from the thighs, and they
    hand it to the hips)."""
    names = ALLOWED[slot]
    if skirt:
        names = [b for b in names if b.endswith("UpLeg") or not b.endswith(("Leg", "Foot"))]
    allowed = {body.index[BONE_PREFIX + s] for s in names}
    result = []
    for b in range(len(body.names)):
        a = b
        while a >= 0 and a not in allowed:
            a = body.parents[a]
        if a < 0:
            # No allowed ancestor (the hips for a mitten): the nearest allowed joint.
            joint = body.joints[body.names[b]]
            a = min(allowed, key=lambda k: np.linalg.norm(body.joints[body.names[k]] - joint))
        result.append(a)
    return np.array(result)


def skin(obj, body, entry, slot):
    p = coords(obj)
    n = len(p)
    dense = np.zeros((n, len(body.names)), dtype=np.float32)
    distance = np.zeros(n)
    for i, q in enumerate(p):
        dense[i], distance[i] = body.weights_at(q)
    remap = allowed_map(body, slot, entry.get("skirt", False))
    folded = np.zeros_like(dense)
    for b in range(dense.shape[1]):
        folded[:, remap[b]] += dense[:, b]
    edges = edges_of(obj)
    degree = np.zeros(n)
    np.add.at(degree, edges.ravel(), 1.0)
    loose = smoothstep(HUGGING, LOOSE, distance)
    # What hangs from the upper arm (a sleeve) follows it as the skin does
    # (followed by half, it stands out like an epaulette when the arm drops).
    arms = [body.index[BONE_PREFIX + s + "Arm"] for s in SIDES]
    loose *= 1.0 - smoothstep(SLEEVE_ARM[0], SLEEVE_ARM[1], dense[:, arms].sum(axis=1))
    rate = WEIGHT_SMOOTHING * (NEAR_SMOOTHING + (1.0 - NEAR_SMOOTHING) * loose) * (degree > 0)
    for _ in range(WEIGHT_SMOOTHING_STEPS):
        neighbours = np.zeros_like(folded)
        np.add.at(neighbours, edges[:, 0], folded[edges[:, 1]])
        np.add.at(neighbours, edges[:, 1], folded[edges[:, 0]])
        mean = neighbours / np.maximum(degree, 1.0)[:, None]
        folded += rate[:, None] * (mean - folded)
    hips = body.index[BONE_PREFIX + "Hips"]
    left = body.index[BONE_PREFIX + "LeftUpLeg"]
    right = body.index[BONE_PREFIX + "RightUpLeg"]
    if entry.get("hang") and body.chains:
        ring = body.joints[body.names[body.chains[0][0]]][2]
        below = smoothstep(ring + SKIRT_BLEND, ring - SKIRT_BLEND, p[:, 2])
        hanging = chain_weights(p, body)
        on_left, on_right = on_thighs(p, body, entry.get("thighs", HANG_RIDE))
        hanging *= (1.0 - on_left - on_right)[:, None]
        hanging[:, left] += on_left
        hanging[:, right] += on_right
        folded += (hanging - folded) * below[:, None]
    elif slot == "chest" or entry.get("skirt", False):
        # Below the crotch (after smoothing, so the thighs do not seep back).
        crotch = body.joint("LeftUpLeg")[2] - 0.08
        hang = entry.get("hang", False)
        # A hanging skirt from the hip joints down, or it would hang from the thighs.
        below = smoothstep(body.joint("Hips")[2] if hang else crotch + 0.06, crotch - 0.08, p[:, 2])
        on_left, on_right = on_thighs(p, body, entry.get("thighs", HANG_THIGHS if hang else (SKIRT_FRONT, SKIRT_BACK)))
        thighs = folded[:, left] + folded[:, right]
        hanging = folded.copy()
        hanging[:, left] = thighs * on_left
        hanging[:, right] = thighs * on_right
        hanging[:, hips] += thighs * (1.0 - on_left - on_right)
        folded += (hanging - folded) * below[:, None]
    return top_four(folded)


def on_thighs(p, body, shares):
    """Per point, how much of it follows each thigh, (left, right): the
    `shares` [front, back] of it, from the front of the hips to the back,
    split between the two by how far to each side it hangs (the middle
    follows both alike, so it does not split when they part)."""
    half = abs(body.joint("LeftUpLeg")[0] - body.joint("RightUpLeg")[0]) * 0.5 + 0.06
    centre = (body.joint("LeftUpLeg")[0] + body.joint("RightUpLeg")[0]) * 0.5
    side = np.clip((p[:, 0] - centre) / half, -1.0, 1.0)
    # Blender's front is -Y.
    front = smoothstep(body.joint("Hips")[1] + 0.03, body.joint("Hips")[1] - 0.05, p[:, 1])
    share = shares[1] + (shares[0] - shares[1]) * front
    return share * (0.5 + 0.5 * side), share * (0.5 - 0.5 * side)


def chain_weights(p, body):
    """Weights of the points `p` on the skirt's chains: the two chains either
    side of each round the hips, by angle, and along them the two joints
    whose bones the point is between (each bone holds the middle of its span
    to the next joint; past the last, the last)."""
    tops = np.array([body.joints[body.names[chain[0]]] for chain in body.chains])
    centre = tops.mean(axis=0)
    angles = np.arctan2(tops[:, 1] - centre[1], tops[:, 0] - centre[0])
    order = np.argsort(angles)
    angles = angles[order]
    chains = [body.chains[k] for k in order]
    a = np.arctan2(p[:, 1] - centre[1], p[:, 0] - centre[0])
    # The chain at or before each angle, and how far towards the next.
    k = np.searchsorted(angles, a, side="right") - 1
    span = np.diff(np.append(angles, angles[0] + 2 * np.pi))
    t = np.mod(a - angles[k % len(angles)], 2 * np.pi) / span[k % len(angles)]
    k = k % len(angles)
    dense = np.zeros((len(p), len(body.names)), dtype=np.float32)
    rows = np.arange(len(p))
    for side, share in ((k, 1.0 - t), ((k + 1) % len(angles), t)):
        heights = np.array([[body.joints[body.names[j]][2] for j in chains[c]] for c in range(len(chains))])
        top = heights[side, 0]
        drop = heights[side, 0] - heights[side, 1]
        along = np.clip((top - p[:, 2]) / drop - 0.5, 0.0, heights.shape[1] - 1.0)
        first = np.floor(along).astype(int)
        second = np.minimum(first + 1, heights.shape[1] - 1)
        blend = along - first
        bones = np.array([chains[c] for c in range(len(chains))])
        np.add.at(dense, (rows, bones[side, first]), share * (1.0 - blend))
        np.add.at(dense, (rows, bones[side, second]), share * blend)
    return dense


def top_four(dense):
    """The four largest weights per vertex, normalised: (bones, weights)."""
    dense = dense / np.maximum(dense.sum(axis=1, keepdims=True), 1e-12)
    bones = np.argsort(-dense, axis=1)[:, :4]
    weights = np.take_along_axis(dense, bones, axis=1)
    weights[weights < 0.01] = 0.0
    weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-12)
    return bones, weights


# --- Output --------------------------------------------------------------------

def textures(model_path):
    """The model's PBR maps, as Meshy names them next to it."""
    base = os.path.splitext(model_path)[0]
    found = {}
    for kind, suffix in (("albedo", ""), ("normal", "_normal"), ("roughness", "_roughness")):
        if os.path.exists(base + suffix + ".png"):
            found[kind] = base + suffix + ".png"
    return found


def surface(obj, bones, weights):
    """One surface: vertices split where the UVs are, in skin space."""
    mesh = obj.data
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers.active.data if mesh.uv_layers.active else None
    p = coords(obj)
    normals = np.zeros(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("normal", normals)
    normals = normals.reshape(-1, 3)
    keys, out_index, indices = {}, [], []
    out_uv = []
    for tri in mesh.loop_triangles:
        corners = []
        for loop in tri.loops:
            v = mesh.loops[loop].vertex_index
            u = uv[loop].uv if uv is not None else (0.0, 0.0)
            key = (v, round(u[0], 5), round(u[1], 5))
            if key not in keys:
                keys[key] = len(out_index)
                out_index.append(v)
                out_uv.append((u[0], 1.0 - u[1]))
            corners.append(keys[key])
        # Godot winds front faces clockwise.
        indices.extend([corners[0], corners[2], corners[1]])
    out_index = np.array(out_index)
    data = {
        "positions": to_skin(p[out_index]).round(6).ravel().tolist(),
        "normals": to_skin_dir(normals[out_index]).round(5).ravel().tolist(),
        "indices": indices,
        "influences": bones[out_index].ravel().tolist(),
        "weights": weights[out_index].round(5).ravel().tolist(),
    }
    if uv is not None:
        data["uvs"] = np.array(out_uv).round(6).ravel().tolist()
    return data


def export(surfaces, body, path, maps):
    """The piece: its surfaces (the garment, textured with `maps`, first;
    then a plain one with its "color"), and the bone names they index."""
    with open(path, "w") as f:
        json.dump({"bones": list(body.names), "textures": maps, "surfaces": surfaces}, f)
    return sum(len(s["positions"]) // 3 for s in surfaces), sum(len(s["indices"]) // 3 for s in surfaces)


# --- Preview -------------------------------------------------------------------

def body_object(body):
    mesh = bpy.data.meshes.new("body")
    mesh.from_pydata(body.points.tolist(), [], body.triangles.tolist())
    mesh.update()
    obj = bpy.data.objects.new("body", mesh)
    bpy.context.scene.collection.objects.link(obj)
    material = bpy.data.materials.new("skin")
    material.diffuse_color = (0.75, 0.6, 0.5, 1.0)
    mesh.materials.append(material)
    obj.color = (0.75, 0.6, 0.5, 1.0)
    return obj


def preview(obj, path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 480
    scene.render.film_transparent = False
    p = coords(obj)
    low, high = p.min(axis=0), p.max(axis=0)
    centre = (low + high) * 0.5
    size = max(high[2] - low[2], (high[0] - low[0]) * 0.75, 0.25) * 1.25
    shots = []
    for name, direction in (("front", (0, -1, 0)), ("side", (1, 0, 0)), ("back", (0, 1, 0)),
                            ("three", (0.7, -0.7, 0.25))):
        camera = bpy.data.cameras.new(name)
        camera.type = "ORTHO"
        camera.ortho_scale = size
        cam = bpy.data.objects.new(name, camera)
        scene.collection.objects.link(cam)
        d = Vector(direction).normalized()
        cam.location = Vector(centre) + d * 4.0
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        shot = path.replace(".png", "_%s.png" % name)
        scene.render.filepath = shot
        bpy.ops.render.render(write_still=True)
        shots.append(shot)
        bpy.data.objects.remove(cam)
    return shots


# --- Main ----------------------------------------------------------------------

def fit_piece(piece_id, entry, body):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    slot = entry["slot"]
    model = os.path.join(SOURCE_DIR, entry["model"])
    source = import_model(model)
    maps = textures(model)
    if entry.get("decimate"):
        decimate(source, entry["decimate"])
    clearance = entry.get("clearance", CLEARANCE)
    if slot in ("hands", "feet"):
        parts = []
        for side in SIDES:
            part = duplicate(source)
            if slot == "hands":
                place_hand(part, body, entry, side)
                inside = [side + "Hand"] + [f for f in FINGERS if f.startswith(side)]
            else:
                place_foot(part, body, entry, side)
                inside = [side + "Foot", side + "ToeBase", side + "Toe_End"]
            cover = np.flatnonzero(np.isin(body.top, [body.index[BONE_PREFIX + b] for b in inside]))
            push_out(part, body, clearance, PUSH_SPREAD[slot], PUSH_REACH[slot], cover)
            parts.append(part)
        bpy.data.objects.remove(source)
        obj = join(parts)
    else:
        obj = source
        if slot == "chest":
            place_chest(obj, body, entry)
            open_neck(obj, body)
        else:
            place_legs(obj, body, entry)
        placed = coords(obj)
        under = under_garments(entry["over"]) if entry.get("over") else None
        # Pushed, relaxed back towards its placed shape and pushed again for
        # what the relaxing let near the skin, the legs or the garments under it.
        for final in (False, True):
            if entry.get("hang"):
                off_legs(obj, body, clearance, PUSH_SPREAD[slot])
            push_out(obj, body, clearance, PUSH_SPREAD[slot], PUSH_REACH[slot], under=under)
            if not final:
                relax(obj, body, placed, clearance, PUSH_REACH[slot], legs=not entry.get("hang"))
        if len(entry.get("ease", [])) > 2:
            draw_in(obj, body, entry["ease"][2])
    bones, weights = skin(obj, body, entry, slot)
    surfaces = [surface(obj, bones, weights)]
    offset = min(LINER_OFFSET.get(slot, 0.0), clearance * LINER_UNDER)
    bones = LINER_BONES[slot]
    if entry.get("hang"):
        # The legs go through a hanging skirt: lined, they would look in tights.
        bones = [b for b in bones if not b.endswith("Leg")]
    lining = liner(obj, body, bones, offset) if entry.get("liner") else None
    if lining is not None:
        lined = surface(lining, *skin_liner(lining, body, slot, offset))
        lined["color"] = liner_color(maps)
        surfaces.append(lined)
    os.makedirs(OUT_DIR, exist_ok=True)
    vertices, triangles = export(surfaces, body, os.path.join(OUT_DIR, piece_id + ".json"), maps)
    print("%s: %d vertices, %d triangles (%d surfaces), maps %s" % (piece_id, vertices, triangles, len(surfaces),
                                                                    sorted(maps)))
    body_object(body)
    preview(obj, os.path.join(OUT_DIR, piece_id + "_preview.png"))


def main():
    body = Body(BODY_JSON)
    with open(PIECES_JSON) as f:
        pieces = json.load(f)
    # What goes over other pieces after them (it is pushed off them).
    for piece_id, entry in sorted(pieces.items(), key=lambda item: "over" in item[1]):
        if piece_id.startswith("_") or (ONLY and piece_id not in ONLY):
            continue
        fit_piece(piece_id, entry, body)


main()
