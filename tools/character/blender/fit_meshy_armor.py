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

With --reweight after the four positional arguments, <source dir> contains the
positions and triangles exported by bake_meshy_armor.gd --export-weights.
Only weights are written; bake_meshy_armor.gd --weights applies them to the
existing meshes, preserving their geometry, UVs, materials and lining.

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
  slot       chest | legs | hands | feet | head | cloak (placed as a chest
             piece; hangs from the cloak's bones, cloak_weights())
  scale      chest: uniform scale. hands/feet: multiplier on the automatic one.
  top        chest: collar height over the neck joint; legs: waist height (m, ground 0);
             head: how far its crown stands over the scalp.
  hem        legs: hem height (m, ground 0).
  offset     [x, y, z] metres added after placing (Blender axes: +X left, -Y front, +Z up).
  width      legs, chest: extra scale of X and Y over the uniform one.
  turn       chest, legs: degrees the model is turned about the vertical first.
  hang_width cloak: how far (m) past the hips to the sides it reaches from
             the waist down, straight to the hem (Meshy sculpts cloaks belled
             out); from the armpits it narrows to that.
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
  pauldrons  chest: keep the outer shell of each shoulder on the upper arm.
  pauldron_scale  chest: what stands out past each shoulder joint is scaled
             this much towards it (smaller pauldrons, the torso as it was).
  skirt      legs: no per-leg shear; hanging parts follow the hips more.
  rigid_belt legs (skirt): anchor the belt to the hips, transitioning to the thigh weights below it.
  swing      legs (rigid_belt): share of the hem (less higher up, none at the
             belt) that hangs from the skirt's bones, which the game swings.
  flare      legs: how much wider (to the sides) it is at the hem than at the
             waist (0.3: 30 %).
  forward    legs: metres its front comes forward, from the waist down to the
             crotch, hanging on from there.
  thighs     chest, legs (skirt): [front, back] share of the thigh weights kept
             below the crotch (SKIRT_FRONT/BACK, or HANG_THIGHS if it hangs);
             with the skirt's bones, the share that rides the thighs (HANG_RIDE).
  split      (skirt) metres either side of the middle over which its front goes
             from following one thigh to the other: narrower, each side rides
             its own thigh and the middle stretches between them.
  hang       legs (skirt): it hangs from the skirt's bones (body.json "skirt"),
             which the game swings, or without them from the hips, the thighs
             going through it (HANG_THIGHS); its lining stays on the hips.
  frame      hands: {"up", "thumb", "palm"}; feet: {"up", "toe"}; axes like "-x".
  tip        hands: how far the mitten reaches past the fingertips (m).
  finger_rig hands: source wrist and finger joint landmarks for sculpted gloves.
  push       hands (finger_rig): push it off the hand as a mitten is.
  canon      hands (finger_rig): each landmark axis as a signed model axis
             ({"x": "-z", ...}), when the model's fingers do not point to -X,
             its thumb to +Z and its palm to -Y; a rotation (no mirror).
  mitten     hands: the four enclosed fingers bend together with the middle
             finger; the thumb stays independent.
  weight_radius  metres over which nearby garment weights are averaged;
             defaults to WEIGHT_RADIUS for the slot.
  sole       feet: height of the underside (m, ground 0).
  liner      chest, legs: line it (see LINER_OFFSET).
  tights     legs: [r, g, b] (sRGB) of tights under it: the skin from its hem
             to its waist is painted that colour in game (human_skin.gdshader),
             so it shows between the plates and never comes through them.
  sleeves    chest: it has long sleeves, which bend at the elbow (the
             forearms' bones too).
  stand      remove the isolated display post containing the lowest vertex.
  decimate   ratio of faces kept.
  clearance  metres off the skin (default CLEARANCE).
  outer_only chest, legs: remove the shell's inner wall (drop_inner()).
  relax      chest, legs: false leaves it as pushed, without relax() (a rigid
             plate barely pushed: relaxing the edges a dropped inner wall
             leaves loose raises flaps).
  weights    "heat": Blender's automatic weights from the slot's bones
             (heat_weights()) instead of the skin's under it; with
             --reweight also for a glove fitted with finger_rig.
  heat_smoothing  with "heat": rounds its weights are averaged along the
             surface's edges.
             "bones": by distance to the slot's bones (bone_weights()), for
             a rigid chest piece.
"""

import copy
import json
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

# Only when run as the script: build_fur_armor.py imports the rest.
if __name__ == "__main__":
    ARGS = sys.argv[sys.argv.index("--") + 1:]
    BODY_JSON, PIECES_JSON, SOURCE_DIR, OUT_DIR = ARGS[:4]
    REWEIGHT = "--reweight" in ARGS[4:]
    ONLY = set(ARGS[4:]) - {"--reweight"}

## Height of the soles in skin space.
SOLE_HEIGHT = -0.9506
BONE_PREFIX = "mixamorig_"
CLEARANCE = 0.008
## How far the push off the skin spreads over the garment, in metres, by slot
## (a hand is thin: a wider push would reach the other side of it).
PUSH_SPREAD = {"chest": 0.05, "legs": 0.05, "hands": 0.015, "feet": 0.03, "head": 0.04, "cloak": 0.05}
## Deeper than this inside the body a vertex is taken to be past a thin part
## (a finger), not inside it, by slot. A chest piece made on a mannequin can
## have its shoulders well inside a broader body's.
PUSH_REACH = {"chest": 0.10, "legs": 0.035, "hands": 0.035, "feet": 0.035, "head": 0.10, "cloak": 0.10}
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
## Average over a distance, rather than only over mesh edges: Meshy's fur
## has tiny triangles and detached tufts, so a fixed number of edge passes
## leaves neighbouring points following very different bones. Metres.
WEIGHT_RADIUS = {"chest": 0.08, "legs": 0.05, "hands": 0.018, "feet": 0.02, "cloak": 0.05, "head": 0.05}
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
## A pelt's forelegs' bones (body.json "pelt"), which the game swings too.
PELT_PREFIX = "pelt_"
## A cloak's bones (CloakBones), likewise.
CLOAK_PREFIX = "cloak_"
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
    "cloak": ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"] + [s + b for s in SIDES for b in ("Shoulder", "Arm")],
    "head": ["Spine2", "Neck", "Head"] + [s + "Shoulder" for s in SIDES],
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
        # And a pelt's forelegs' (PeltBones): a chain down each side of the chest.
        self.chains = self.added(data.get("skirt", []), SKIRT_PREFIX)
        self.pelt = self.added(data.get("pelt", []), PELT_PREFIX)
        self.cloak = self.added(data.get("cloak", []), CLOAK_PREFIX)
        # How a cloak's arms hang (CloakBones.ARM_HANG): it is made for them so.
        self.arm_hang = data.get("cloak_arm_hang", 0.0)
        if len(self.names) > self.dense.shape[1]:
            self.dense = np.pad(self.dense, ((0, 0), (0, len(self.names) - self.dense.shape[1])))

    def added(self, bones, prefix):
        """Takes in bones added to the skeleton (their joints, after the
        skeleton's own); returns their chains, as lists of bone indices."""
        chains = []
        for bone in bones:
            self.index[bone["name"]] = len(self.names)
            self.names.append(bone["name"])
            self.parents.append(self.index[bone["parent"]])
            self.joints[bone["name"]] = to_blender(np.array(bone["joint"]))
            if not bone["parent"].startswith(prefix):
                chains.append([])
            chains[-1].append(self.index[bone["name"]])
        return chains

    def joint(self, short):
        return self.joints[BONE_PREFIX + short]

    def region(self, shorts):
        """Points whose strongest bone is one of `shorts`."""
        ids = [self.index[BONE_PREFIX + s] for s in shorts]
        return self.points[np.isin(self.top, ids)]

    def hanging_arm(self, side):
        """The upper arm's direction hanging as a cloak is made for
        (arm_hang degrees out from straight down; CloakBones.arm_hang()), and
        the turn about its shoulder joint from the rest pose to there."""
        sign = 1.0 if side == "Left" else -1.0
        angle = np.radians(self.arm_hang)
        hang = np.array([sign * np.sin(angle), 0.0, -np.cos(angle)])
        return hang, rotation_between(self.joint(side + "ForeArm") - self.joint(side + "Arm"), hang)

    def arms_down(self, cap=None):
        """This body for pushes only (push_out(), relax()) with its arms
        hanging (hanging_arm()) instead of spread as at rest: each arm's skin
        turned about its shoulder joint. With `cap` (m), only the shoulder
        caps of the arms: what is further down them than that is left out."""
        other = copy.copy(self)
        other.points, other.normals = self.points.copy(), self.normals.copy()
        kept = np.ones(len(self.points), dtype=bool)
        for side in SIDES:
            shoulder = self.joint(side + "Arm")
            hang, turn = self.hanging_arm(side)
            arm = np.array([name.startswith(BONE_PREFIX + side) and ("Arm" in name or "Hand" in name)
                            for name in self.names])[self.top]
            other.points[arm] = (self.points[arm] - shoulder) @ turn.T + shoulder
            other.normals[arm] = self.normals[arm] @ turn.T
            if cap is not None:
                kept &= ~(arm & ((other.points - shoulder) @ hang > cap))
        other.points, other.normals = other.points[kept], other.normals[kept]
        other.triangles = self.triangles[kept[self.triangles].all(axis=1)]
        positions = self.points.copy()
        positions[kept] = other.points
        other.bvh = BVHTree.FromPolygons([Vector(p) for p in positions], other.triangles.tolist())
        return other

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


def remove_stand(obj):
    """Remove the small disconnected post below a garment made on a stand."""
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    lowest = min(mesh.verts, key=lambda v: v.co.z)
    post = {lowest}
    pending = [lowest]
    while pending:
        v = pending.pop()
        for edge in v.link_edges:
            other = edge.other_vert(v)
            if other not in post:
                post.add(other)
                pending.append(other)
    if len(post) > len(mesh.verts) * 0.05:
        raise ValueError("Expected a separate display post below " + obj.name)
    bmesh.ops.delete(mesh, geom=list(post), context="VERTS")
    mesh.to_mesh(obj.data)
    mesh.free()


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
    if "pauldron_scale" in entry:
        # What stands out past each shoulder joint, towards it: smaller
        # pauldrons on the same shoulders (the torso as it was).
        for side, sign in (("Left", 1.0), ("Right", -1.0)):
            arm = body.joint(side + "Arm")
            shell = smoothstep(0.0, 0.05, (p[:, 0] - arm[0]) * sign)
            p = arm + (p - arm) * (1.0 - (1.0 - entry["pauldron_scale"]) * shell)[:, None]
    if "ease" in entry:
        p = take_in(p, body, *entry["ease"][:2])
    set_coords(obj, p + np.array(entry.get("offset", [0.0, 0.0, 0.0])))


def place_head(obj, body, entry):
    """A hood or a helm: scaled, its upper part (what goes round the head)
    centred on the head, its crown `top` over the scalp; what hangs below
    (a mantle) falls over the shoulders."""
    p = turned(coords(obj), entry)
    scale = entry.get("scale", 0.3)
    width = entry.get("width", 1.0)
    p = p * np.array([scale * width, scale * width, scale])
    head = body.region(["Head"])
    top = p[:, 2].max()
    crown = p[p[:, 2] > top - 0.35 * (head[:, 2].max() - head[:, 2].min())]
    centre = (crown.min(axis=0) + crown.max(axis=0)) * 0.5
    head_centre = (head.min(axis=0) + head.max(axis=0)) * 0.5
    target = np.array([head_centre[0], head_centre[1] + entry.get("back", 0.0), head[:, 2].max() + entry.get("top", 0.02)])
    p += target - np.array([centre[0], centre[1], top])
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

## "outer_only": a face is the shell's inner wall when it faces the skin
## this squarely (cosine).
INNER_FACING = 0.3


def drop_inner(obj, body):
    """Removes a thick shell's inner wall (Meshy models solid pieces as a
    closed skin): the faces that face the skin. Pushed off the body each by
    its own amount, the two walls cross where the shell is near it (a fold
    down the sternum and the spine); the outer one alone shows from inside
    too (the material draws both sides)."""
    mesh = obj.data
    inner = []
    for f in mesh.polygons:
        c = np.array(f.center)
        location, _, _ = body.nearest(c)
        towards = normalized(location - c)
        if np.array(f.normal) @ towards > INNER_FACING:
            inner.append(f.index)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in inner], context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print("  inner wall: %d of %d faces removed" % (len(inner), len(mesh.polygons) + len(inner)))


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


def arm_slits(obj, body):
    """Opens a cloak where its arms go through it, hanging (Body.hanging_arm(),
    CloakBones.arm_hang()): what of it is within CLOAK_SLIT of an arm's bones
    further down it than CLOAK_CAP from the shoulder joint (the shoulder cap
    stays; it follows the arm). Moving, they come and go through there
    instead of pushing a closed bell out."""
    mesh = obj.data
    centres = np.array([f.center for f in mesh.polygons])
    cut = np.zeros(len(centres), dtype=bool)
    for side in SIDES:
        shoulder = body.joint(side + "Arm")
        hang, turn = body.hanging_arm(side)
        joints = [shoulder] + [(body.joint(side + b) - shoulder) @ turn.T + shoulder for b in ("ForeArm", "Hand")]
        for (a, b), radius in zip(((joints[0], joints[1]), (joints[1], joints[2])), CLOAK_SLIT):
            d = b - a
            t = np.clip((centres - a) @ d / (d @ d), 0.0, 1.0)
            near = np.linalg.norm(centres - (a + t[:, None] * d), axis=1) < radius
            cut |= near & ((centres - shoulder) @ hang > CLOAK_CAP)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.flatnonzero(cut)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print("  arm slits: %d faces cut" % cut.sum())


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
    return strongest_weights(folded)


# --- Skinning ------------------------------------------------------------------

def allowed_map(body, slot, skirt=False, sleeves=False):
    """For every bone, the allowed bone that takes its weight. A skirt does
    not follow the shins or the feet (its hem hangs from the thighs, and they
    hand it to the hips); long sleeves follow the forearms."""
    names = ALLOWED[slot]
    if sleeves:
        names = names + [s + "ForeArm" for s in SIDES]
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


def reinforce_pauldrons(points, body, weights, scale=1.0):
    """Keep the shell on the arm, blending back to the cuirass at its straps.
    Out past the torso, how far below the arm a point is goes across the
    arm's axis (it slopes down in the rest pose), so a pauldron reaching down
    the upper arm stays on it whole. `scale`: the pauldrons were shrunk this
    much towards the shoulder ("pauldron_scale"); measured as they were."""
    for side, sign in (("Left", 1), ("Right", -1)):
        arm = body.joint(side + "Arm")
        along = normalized(body.joint(side + "ForeArm") - arm)
        up = np.array([0.0, 0.0, 1.0])
        up = normalized(up - along * (along @ up))
        across = (points[:, 0] - arm[0]) * sign / scale
        # Beside the torso, by height (its sides under the armpit stay on
        # it); further out, across the arm's axis.
        above = np.maximum(smoothstep(-0.125, -0.035, (points[:, 2] - arm[2]) / scale),
                           smoothstep(-0.125, -0.035, (points - arm) @ up / scale) * smoothstep(0.04, 0.10, across))
        shell = above * smoothstep(-0.005, 0.082, across)
        weights *= (1 - shell)[:, None]
        weights[:, body.index[BONE_PREFIX + side + "Arm"]] += shell
    return weights


def belted_skirt_weights(points, body, entry):
    """Keep the belt on the hips and blend both thighs below the belt seam.
    With "swing", that share of it is handed to the skirt's bones instead
    (which the game swings and the legs push aside), none at the belt seam
    and all of it at the hem, so its strips sway over what the thighs do."""
    weights = np.zeros((len(points), len(body.names)))
    waist = entry.get("top", body.joint("Hips")[2] + 0.06)
    drape = 1 - smoothstep(waist - 0.20, waist - 0.055, points[:, 2])
    shares = entry.get("thighs", (SKIRT_FRONT, SKIRT_BACK))
    left, right = on_thighs(points, body, shares, entry.get("split"))
    swing = np.zeros(len(points))
    if entry.get("swing") and body.chains:
        hem = points[:, 2].min()
        swing = entry["swing"] * drape * smoothstep(waist - 0.055, hem, points[:, 2])
        weights += chain_weights(points, body) * swing[:, None]
    weights[:, body.index[BONE_PREFIX + "LeftUpLeg"]] = left * drape * (1 - swing)
    weights[:, body.index[BONE_PREFIX + "RightUpLeg"]] = right * drape * (1 - swing)
    weights[:, body.index[BONE_PREFIX + "Hips"]] = 1 - (left + right) * drape * (1 - swing) - swing
    return weights


def skin(obj, body, entry, slot):
    p = coords(obj)
    if entry.get("rigid_belt"):
        return strongest_weights(belted_skirt_weights(p, body, entry))
    n = len(p)
    dense = np.zeros((n, len(body.names)), dtype=np.float32)
    distance = np.zeros(n)
    for i, q in enumerate(p):
        dense[i], distance[i] = body.weights_at(q)
    remap = allowed_map(body, slot, entry.get("skirt", False), entry.get("sleeves", False))
    if entry.get("mitten"):
        # One pouch encloses these four fingers. Different finger weights
        # across that pouch pull neighbouring tufts in different directions
        # when the hand closes; keep one bend for each phalanx instead.
        for side in SIDES:
            for finger in ("Index", "Ring", "Pinky"):
                for joint in (1, 2, 3):
                    remap[body.index[BONE_PREFIX + side + "Hand" + finger + str(joint)]] = \
                        body.index[BONE_PREFIX + side + "HandMiddle" + str(joint)]
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
        on_left, on_right = on_thighs(p, body, entry.get("thighs", HANG_RIDE), entry.get("split"))
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
        shares = entry.get("thighs", HANG_THIGHS if hang else (SKIRT_FRONT, SKIRT_BACK))
        on_left, on_right = on_thighs(p, body, shares, entry.get("split"))
        thighs = folded[:, left] + folded[:, right]
        hanging = folded.copy()
        hanging[:, left] = thighs * on_left
        hanging[:, right] = thighs * on_right
        hanging[:, hips] += thighs * (1.0 - on_left - on_right)
        folded += (hanging - folded) * below[:, None]
    folded = smooth_weights(p, folded, entry.get("weight_radius", WEIGHT_RADIUS[slot]))
    if entry.get("pauldrons"):
        reinforce_pauldrons(p, body, folded, entry.get("pauldron_scale", 1.0))
    return strongest_weights(folded)


## Bones whose tail goes to this child when they have several (the rest: the
## mean of their children), as an artist would lay the rig out.
TAIL_CHILD = ("Spine", "Neck", "Head", "HandMiddle1")


def bone_segments(body):
    """Each skeleton bone's (head, tail): from its joint to its child's (a
    leaf continues its parent), the added bones left out."""
    added = (SKIRT_PREFIX, PELT_PREFIX, CLOAK_PREFIX)
    children = {}
    for i, parent in enumerate(body.parents):
        if parent >= 0 and not body.names[i].startswith(added):
            children.setdefault(parent, []).append(i)
    segments = {}
    for i, name in enumerate(body.names):
        if name.startswith(added):
            continue
        head = body.joints[name]
        kids = children.get(i, [])
        preferred = [k for k in kids if body.names[k][len(BONE_PREFIX):].startswith(TAIL_CHILD)]
        if preferred:
            tail = body.joints[body.names[preferred[0]]]
        elif kids:
            tail = np.mean([body.joints[body.names[k]] for k in kids], axis=0)
        elif body.parents[i] >= 0:
            along = head - body.joints[body.names[body.parents[i]]]
            tail = head + normalized(along) * max(0.5 * np.linalg.norm(along), 0.01)
        else:
            tail = head + np.array([0.0, 0.0, 0.1])
        if np.linalg.norm(tail - head) < 0.002:
            tail = head + np.array([0.0, 0.0, 0.01])
        segments[i] = (head, tail)
    return segments


def rig_object(body):
    """The player's skeleton as a Blender armature (bone_segments())."""
    data = bpy.data.armatures.new("skeleton")
    rig = bpy.data.objects.new("skeleton", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}
    for i, (head, tail) in bone_segments(body).items():
        bone = data.edit_bones.new(body.names[i])
        bone.head, bone.tail = Vector(head), Vector(tail)
        bones[i] = bone
    for i, bone in bones.items():
        if body.parents[i] in bones:
            bone.parent = bones[body.parents[i]]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


## "weights": "bones": how sharply a vertex prefers its nearest bone (the
## power of the distance), and the radius the result is then smoothed over.
BONES_POWER = 8
BONES_SMOOTHING = 0.04
## A rigid piece's bones by slot (sleeves add the forearms, as in ALLOWED).
RIGID = {"chest": ["Hips", "Spine", "Spine1", "Spine2", "Neck"] + [s + "Shoulder" for s in SIDES],
         "head": ["Spine2", "Neck", "Head"] + [s + "Shoulder" for s in SIDES]}
## Distances to these bones count as this many times longer: the clavicles
## keep the straps over the shoulders, not the breastplate under them (each
## pulling its half, they would stretch it down the middle), and the neck
## the very rim of the collar (it would twist the plate as the head turns).
RIGID_FAR = {"Shoulder": 1.7, "Neck": 1.7}


def bone_weights(obj, body, entry, slot):
    """Weights by distance to the slot's bones, for a rigid shell (a bronze
    cuirass): each vertex follows the bones nearest it, by the inverse of
    the distance to them to BONES_POWER, so it bends only between them and
    not where the skin under it is pulled by the arms. Bone heat does not do
    for a thick shell: its inner wall hides the bones from its outer face.
    Its pauldrons ("pauldrons") follow the upper arms."""
    p = coords(obj)
    names = RIGID[slot] + ([s + "ForeArm" for s in SIDES] + [s + "Arm" for s in SIDES]
                           if entry.get("sleeves") else [])
    segments = bone_segments(body)
    ids = [body.index[BONE_PREFIX + n] for n in names]
    distance = np.zeros((len(p), len(ids)))
    for k, b in enumerate(ids):
        head, tail = segments[b]
        d = tail - head
        t = np.clip((p - head) @ d / (d @ d), 0.0, 1.0)
        far = next((v for k2, v in RIGID_FAR.items() if body.names[b].endswith(k2)), 1.0)
        distance[:, k] = far * np.linalg.norm(p - (head + t[:, None] * d), axis=1)
    near = (np.maximum(distance, 1e-3) / np.maximum(distance.min(axis=1, keepdims=True), 1e-3)) ** -BONES_POWER
    dense = np.zeros((len(p), len(body.names)))
    dense[:, ids] = near / near.sum(axis=1, keepdims=True)
    dense = smooth_weights(p, dense, entry.get("weight_radius", BONES_SMOOTHING))
    if entry.get("pauldrons"):
        reinforce_pauldrons(p, body, dense, entry.get("pauldron_scale", 1.0))
    return strongest_weights(dense)


## own_digit(): how much nearer (m) another finger may be than a point's own
## before its bones stop reaching the point.
DIGIT_BLEND = (0.004, 0.012)


def own_digit(p, body, dense):
    """A glove in one piece (Meshy fuses touching fingers): keeps each
    finger's bones off the points nearer another finger, so heat does not
    carry a fingertip along with its neighbour's. The hand and the forearm
    are left as they are; between two fingers (the knuckles) both stay."""
    segments = bone_segments(body)
    for side in SIDES:
        digits = []
        for digit in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
            ids = [body.index[BONE_PREFIX + f"{side}Hand{digit}{j}"] for j in (1, 2, 3)]
            distance = np.full(len(p), np.inf)
            for b in ids:
                head, tail = segments[b]
                d = tail - head
                t = np.clip((p - head) @ d / (d @ d), 0.0, 1.0)
                distance = np.minimum(distance, np.linalg.norm(p - (head + t[:, None] * d), axis=1))
            digits.append((ids, distance))
        nearest = np.min([d for _, d in digits], axis=0)
        for ids, distance in digits:
            dense[:, ids] *= (1.0 - smoothstep(*DIGIT_BLEND, distance - nearest))[:, None]
    return dense / np.maximum(dense.sum(axis=1, keepdims=True), 1e-12)


## phalanges(): the blend across each knuckle, as a share of the shorter
## phalanx either side of it.
KNUCKLE_BAND = 0.45


def phalanges(p, body, dense):
    """Heat says which finger a point follows (its share of that finger's
    bones), not which phalanx: through the gaps between a gauntlet's plates
    it reaches the fingertip's bone from the finger's root. Each finger's
    share is handed to its phalanges by how far along the finger the point
    is, across a plane bisecting the phalanges at each knuckle (continuous
    round the outside of a bent finger), blended over KNUCKLE_BAND."""
    for side in SIDES:
        for digit in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
            names = [BONE_PREFIX + f"{side}Hand{digit}{j}" for j in (1, 2, 3, 4)]
            if names[3] not in body.joints:
                continue
            ids = [body.index[n] for n in names[:3]]
            joints = np.array([body.joints[n] for n in names])
            segments = np.diff(joints, axis=0)
            lengths = np.linalg.norm(segments, axis=1)
            directions = segments / lengths[:, None]
            share = dense[:, ids].sum(axis=1)
            gates = [np.ones(len(p))]
            for k in (1, 2):
                axis = normalized(directions[k - 1] + directions[k])
                band = KNUCKLE_BAND * min(lengths[k - 1], lengths[k])
                gates.append(np.minimum(gates[-1], smoothstep(-band, band, (p - joints[k]) @ axis)))
            gates.append(np.zeros(len(p)))
            for k, b in enumerate(ids):
                dense[:, b] = share * (gates[k] - gates[k + 1])
    return dense


## cloak_weights(): what follows the body (the collar and the shoulders)
## and how it counts distance to each bone (RIGID_FAR), and from how far
## below the shoulders (m) it starts and ends handing over to the cloak's
## bones. It is made over the arms hanging (Body.arms_down(); its Skin binds
## the upper arms there, CloakBones.arm_hang()), and what lies on an upper
## arm, within CLOAK_ARM[0] of it and no further than CLOAK_ARM[1] (m),
## follows it; the rest moves over them (CloakSwing pushes its bones off
## them; ArmorFit does not push it off them at rest, where they are spread).
CLOAK_RIGID = ["Spine1", "Spine2", "Neck"] + [s + "Shoulder" for s in SIDES]
CLOAK_FAR = {"Shoulder": 1.7, "Neck": 1.7}
CLOAK_ARM = (0.07, 0.15)
## ... and from CLOAK_ARM_DOWN[0] of the way down the upper arm less and
## less, none from [1].
CLOAK_ARM_DOWN = (0.3, 0.75)
## arm_slits(): how far down an arm from its shoulder joint the cloak is cut
## for it (above, it lies on the shoulder cap and is pushed off it), and
## how far round the upper arm and the forearm (m).
CLOAK_CAP = 0.09
CLOAK_SLIT = (0.075, 0.06)
## narrow_hang(): how far above the hip joint (m) a cloak starts narrowing
## (about the armpits) and from where it is as narrow as "hang_width" says.
CLOAK_NARROW = (0.3, 0.05)


def narrow_hang(obj, body, margin):
    """Brings a cloak's sides in to `margin` past the hips' from the waist
    down (CLOAK_NARROW), so it hangs straight instead of belling out: at each
    height scaled towards the middle by what its widest point there needs,
    the same for every point at that height, so both of its walls and its
    folds move together."""
    p = coords(obj)
    hips = body.joint("Hips")
    # The hips' and thighs' own skin: the hands are at that height too at rest.
    pelvis = body.region(["Hips", "LeftUpLeg", "RightUpLeg"])
    near = pelvis[np.abs(pelvis[:, 2] - (hips[2] - 0.08)) < 0.1]
    target = np.abs(near[:, 0] - hips[0]).max() + margin
    bins = np.arange(p[:, 2].min(), p[:, 2].max() + 0.02, 0.02)
    which = np.clip(np.digitize(p[:, 2], bins) - 1, 0, len(bins) - 1)
    widest = np.zeros(len(bins))
    np.maximum.at(widest, which, np.abs(p[:, 0] - hips[0]))
    # The widest within a few centimetres up and down, so a tatter does not
    # make one height narrower than the next.
    widest = np.max([np.roll(widest, k) for k in range(-2, 3)], axis=0)
    scale = np.minimum(1.0, target / np.maximum(widest, 1e-3))[which]
    down = smoothstep(hips[2] + CLOAK_NARROW[0], hips[2] + CLOAK_NARROW[1], p[:, 2])
    p[:, 0] = hips[0] + (p[:, 0] - hips[0]) * (1.0 + (scale - 1.0) * down)
    set_coords(obj, p)


CLOAK_HANG = (0.15, 0.45)
## Radius (m) the cloak's weights are smoothed over at the end.
CLOAK_SMOOTHING = 0.04


def cloak_weights(obj, body, entry):
    """A cloak: its collar and shoulders follow the neck, the upper spine
    and the clavicles, by distance to them (as bone_weights()); below the
    shoulders it hangs more and more from the cloak's bones (CloakBones),
    all of it CLOAK_HANG[1] down. Its "swing" (1 by default) scales how
    much hangs. Over the garments it "follow"s it moves with them
    (follow_weights())."""
    p = coords(obj)
    segments = bone_segments(body)
    ids = [body.index[BONE_PREFIX + n] for n in CLOAK_RIGID]
    distance = np.zeros((len(p), len(ids)))
    for k, b in enumerate(ids):
        head, tail = segments[b]
        d = tail - head
        t = np.clip((p - head) @ d / (d @ d), 0.0, 1.0)
        far = next((v for k2, v in CLOAK_FAR.items() if body.names[b].endswith(k2)), 1.0)
        distance[:, k] = far * np.linalg.norm(p - (head + t[:, None] * d), axis=1)
    near = (np.maximum(distance, 1e-3) / np.maximum(distance.min(axis=1, keepdims=True), 1e-3)) ** -BONES_POWER
    rigid = np.zeros((len(p), len(body.names)))
    rigid[:, ids] = near / near.sum(axis=1, keepdims=True)
    rigid = smooth_weights(p, rigid, entry.get("weight_radius", BONES_SMOOTHING))
    shoulders = max(body.joint("LeftArm")[2], body.joint("RightArm")[2])
    swing = entry.get("swing", 1.0) * smoothstep(shoulders - CLOAK_HANG[0], shoulders - CLOAK_HANG[1], p[:, 2])
    # On the upper arms, as they hang: they carry it.
    on_arm = np.zeros((len(p), len(body.names)))
    for side in SIDES:
        joint = body.joint(side + "Arm")
        hang, _ = body.hanging_arm(side)
        length = np.linalg.norm(body.joint(side + "ForeArm") - joint)
        t = np.clip((p - joint) @ hang, 0.0, length)
        d = np.linalg.norm(p - (joint + t[:, None] * hang), axis=1)
        # The shoulder cap; further down the arm goes through its slit.
        on_arm[:, body.index[BONE_PREFIX + side + "Arm"]] = (1.0 - smoothstep(*CLOAK_ARM, d)) \
            * smoothstep(CLOAK_ARM_DOWN[1] * length, CLOAK_ARM_DOWN[0] * length, t)
    arm_share = np.clip(on_arm.sum(axis=1), 0.0, 1.0)
    dense = rigid * (1.0 - swing)[:, None] + open_chain_weights(p, body, body.cloak) * swing[:, None]
    dense = dense * (1.0 - arm_share)[:, None] + on_arm
    if entry.get("follow"):
        # Where it does not hang yet: lower down it hangs off what it is over.
        under, share = follow_weights(p, body, entry["follow"])
        share *= 1.0 - smoothstep(shoulders - CLOAK_HANG[0], shoulders - CLOAK_HANG[1], p[:, 2])
        dense += (under - dense) * share[:, None]
    # Its parts (the body's, the chains', what it is over) blended.
    dense = smooth_weights(p, dense, CLOAK_SMOOTHING)
    return strongest_weights(dense)


## cloak_weights() "follow": within how far (m) of a garment under it a
## point takes that garment's weights, all of them nearer than the first.
FOLLOW_REACH = (0.03, 0.08)


def follow_weights(p, body, ids):
    """For the points `p` over the garments `ids` (fitted already, their JSON
    in the output dir): the weights of the nearest of their vertices, and how
    much to take them (FOLLOW_REACH): a layer over another moves with it
    instead of parting from it."""
    points, dense = [], []
    for piece_id in ids:
        with open(os.path.join(OUT_DIR, piece_id + ".json")) as f:
            data = json.load(f)
        for s in data.get("surfaces", [data])[:1]:
            q = to_blender(np.array(s["positions"]).reshape(-1, 3))
            inf = np.array(s["influences"], dtype=np.int64).reshape(-1, 8)
            wt = np.array(s["weights"]).reshape(-1, 8)
            d = np.zeros((len(q), len(body.names)))
            for k in range(8):
                np.add.at(d, (np.arange(len(q)), [body.index[data["bones"][i]] for i in inf[:, k]]), wt[:, k])
            points.append(q)
            dense.append(d)
    points, dense = np.concatenate(points), np.concatenate(dense)
    tree = KDTree(len(points))
    for i, q in enumerate(points):
        tree.insert(Vector(q), i)
    tree.balance()
    nearest = [tree.find(Vector(q)) for q in p]
    share = 1.0 - smoothstep(*FOLLOW_REACH, np.array([n[2] for n in nearest]))
    return dense[[n[1] for n in nearest]], share


def open_chain_weights(p, body, chains):
    """Weights of the points `p` on an open ring of chains (a cloak's, open
    in front): by angle round the ring from behind, between the two chains
    either side (past the ends, the end one), and along them between the two
    joints whose bones the point is between, as chain_weights()."""
    tops = np.array([body.joints[body.names[chain[0]]] for chain in chains])
    centre = tops.mean(axis=0)
    # From straight behind (+Y), positive to the left (+X).
    angle_of = lambda q: np.arctan2(q[..., 0] - centre[0], q[..., 1] - centre[1])
    angles = angle_of(tops)
    order = np.argsort(angles)
    angles = angles[order]
    chains = [chains[k] for k in order]
    a = np.clip(angle_of(p), angles[0], angles[-1])
    k = np.clip(np.searchsorted(angles, a, side="right") - 1, 0, len(angles) - 2)
    t = (a - angles[k]) / (angles[k + 1] - angles[k])
    dense = np.zeros((len(p), len(body.names)), dtype=np.float32)
    rows = np.arange(len(p))
    heights = np.array([[body.joints[body.names[j]][2] for j in chain] for chain in chains])
    bones = np.array(chains)
    for side, share in ((k, 1.0 - t), (k + 1, t)):
        top = heights[side, 0]
        drop = heights[side, 0] - heights[side, 1]
        along = np.clip((top - p[:, 2]) / drop - 0.5, 0.0, heights.shape[1] - 1.0)
        first = np.floor(along).astype(int)
        second = np.minimum(first + 1, heights.shape[1] - 1)
        blend = along - first
        np.add.at(dense, (rows, bones[side, first]), share * (1.0 - blend))
        np.add.at(dense, (rows, bones[side, second]), share * blend)
    return dense


def heat_weights(obj, body, entry, slot):
    """Blender's automatic weights (Parent > With Automatic Weights: bone
    heat) on the fitted garment, from the bones its slot may follow. Heat
    spreads through the garment itself, so each finger of a glove follows its
    own bones and a plate bends where its bones do, not where the skin under
    it happens to. A chest piece that ends above the crotch leaves the thighs
    out. Vertices the heat does not reach (loose buckles, straps standing
    off) keep the weights skin() gives them."""
    names = list(ALLOWED[slot])
    if entry.get("sleeves"):
        names += [s + "ForeArm" for s in SIDES]
    p = coords(obj)
    if slot == "chest" and p[:, 2].min() > body.joint("LeftUpLeg")[2] - 0.08:
        names = [n for n in names if not n.endswith("UpLeg")]
    allowed = {BONE_PREFIX + n for n in names}
    obj.vertex_groups.clear()
    rig = rig_object(body)
    for bone in rig.data.bones:
        bone.use_deform = bone.name in allowed
    for other in bpy.context.view_layer.objects:
        other.select_set(False)
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    dense = np.zeros((len(p), len(body.names)))
    groups = {g.index: body.index[g.name] for g in obj.vertex_groups if g.name in body.index}
    for v in obj.data.vertices:
        for influence in v.groups:
            if influence.group in groups:
                dense[v.index, groups[influence.group]] += influence.weight
    reached = dense.sum(axis=1) > 1e-4
    if not reached.all():
        bones, weights = skin(obj, body, entry, slot)
        fallback = np.zeros_like(dense)
        np.put_along_axis(fallback, bones, weights, axis=1)
        dense[~reached] = fallback[~reached]
    print("  heat reached %.1f %% of the vertices" % (100.0 * reached.mean()))
    if slot == "hands":
        dense = own_digit(p, body, dense)
    edges = edges_of(obj)
    a, b = np.concatenate([edges, edges[:, ::-1]]).T
    degree = np.maximum(np.bincount(a, minlength=len(p)), 1)[:, None]

    def smooth(rounds):
        # Blender's Smooth on the groups, along the surface (fingers that
        # touch do not mix).
        nonlocal dense
        for _ in range(rounds):
            summed = np.zeros_like(dense)
            np.add.at(summed, a, dense[b])
            dense += 0.5 * (summed / degree - dense)

    # Heat leaves sharp steps where a thick shell's walls meet (the web of
    # the thumb).
    smooth(entry.get("heat_smoothing", 0))
    if slot == "hands":
        # After the smoothing, which would carry a fingertip's bone along
        # the finger to its root.
        dense = phalanges(p, body, dense)
    obj.parent = None
    obj.modifiers.clear()
    bpy.data.objects.remove(rig)
    return strongest_weights(dense)


def smooth_weights(points, dense, radius):
    """A compact, smooth field shared by seams and nearby loose fur layers.

    Average coincident vertices first, so a UV seam or a dense patch does
    not count several times. The kernel and its slope vanish at its edge.
    This is an offline operation; the game still uses ordinary skinning.
    """
    unique, inverse = np.unique(points.round(6), axis=0, return_inverse=True)
    values = np.zeros((len(unique), dense.shape[1]), dtype=np.float32)
    np.add.at(values, inverse, dense)
    values /= np.bincount(inverse)[:, None]
    tree = KDTree(len(unique))
    for i, point in enumerate(unique):
        tree.insert(Vector(point), i)
    tree.balance()
    result = np.zeros_like(values)
    for i, point in enumerate(unique):
        neighbours = tree.find_range(Vector(point), radius)
        indices = np.array([n[1] for n in neighbours], dtype=np.int64)
        distances = np.array([n[2] for n in neighbours])
        kernel = np.maximum(1.0 - (distances / radius) ** 2, 0.0) ** 2
        result[i] = (values[indices] * kernel[:, None]).sum(axis=0) / kernel.sum()
    return result[inverse]


def on_thighs(p, body, shares, half=None):
    """Per point, how much of it follows each thigh, (left, right): the
    `shares` [front, back] of it, from the front of the hips to the back,
    split between the two by how far to each side it hangs (the middle
    follows both alike, so it does not split when they part), over `half`
    metres either side of the middle (by default, past the hip joints)."""
    half = half or abs(body.joint("LeftUpLeg")[0] - body.joint("RightUpLeg")[0]) * 0.5 + 0.06
    centre = (body.joint("LeftUpLeg")[0] + body.joint("RightUpLeg")[0]) * 0.5
    side = np.clip((p[:, 0] - centre) / half, -1.0, 1.0)
    # Blender's front is -Y.
    # Blend across the whole side of the skirt. An 8 cm band makes the
    # thigh-driven front and the hanging back shear apart when running.
    front = smoothstep(body.joint("Hips")[1] + 0.10, body.joint("Hips")[1] - 0.14, p[:, 1])
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


def strongest_weights(dense):
    """Eight influences, preserving the skirt's chains AND its thigh blend.

    Four cut the fifth influence abruptly as it changes rank, making a
    crease even though the original field is smooth. Do not threshold small
    influences either: they should fade continuously to zero.
    """
    dense = dense / np.maximum(dense.sum(axis=1, keepdims=True), 1e-12)
    bones = np.argsort(-dense, axis=1, kind="stable")[:, :8]
    weights = np.take_along_axis(dense, bones, axis=1)
    weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-12)
    return bones, weights


# --- Output --------------------------------------------------------------------

def textures(model_path):
    """The model's PBR maps, as Meshy names them next to it."""
    base = os.path.splitext(model_path)[0]
    found = {}
    for kind, suffix in (("albedo", ""), ("normal", "_normal"), ("roughness", "_roughness"), ("metallic", "_metallic")):
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


def export(surfaces, body, path, maps, tights=None):
    """The piece: its surfaces (the garment, textured with `maps`, first;
    then a plain one with its "color"), the bone names they index and the
    colour of its tights, if it has them."""
    data = {"bones": list(body.names), "textures": maps, "surfaces": surfaces}
    if tights:
        data["tights"] = tights
    with open(path, "w") as f:
        json.dump(data, f)
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
    if entry.get("stand"):
        remove_stand(source)
    if entry.get("decimate"):
        decimate(source, entry["decimate"])
    clearance = entry.get("clearance", CLEARANCE)
    if entry.get("canon"):
        # Into the axes the finger landmarks are given in (fit_fingered_glove:
        # fingers -X, thumb +Z, palm -Y), e.g. {"x": "-z", "y": "-y", "z": "-x"}.
        q = coords(source)
        set_coords(source, np.stack([q[:, AXES[a[-1]]] * (-1.0 if a.startswith("-") else 1.0)
                                     for a in (entry["canon"][k] for k in "xyz")], axis=1))
    if entry.get("finger_rig"):
        # Import alongside this script also when Blender starts from the project root.
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import fit_fingered_glove
        parts = []
        for side in SIDES:
            part = duplicate(source)
            fit_fingered_glove.place(part, body, side, entry["finger_rig"])
            if entry.get("push", False):
                # Off the hand it encloses, as a mitten is.
                inside = [side + "Hand"] + [f for f in FINGERS if f.startswith(side)]
                cover = np.flatnonzero(np.isin(body.top, [body.index[BONE_PREFIX + b] for b in inside]))
                push_out(part, body, clearance, PUSH_SPREAD["hands"], PUSH_REACH["hands"], cover)
            parts.append(part)
        bpy.data.objects.remove(source)
        obj = join(parts)
    elif slot in ("hands", "feet"):
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
        if slot in ("chest", "cloak"):
            place_chest(obj, body, entry)
            open_neck(obj, body)
        elif slot == "head":
            place_head(obj, body, entry)
        else:
            place_legs(obj, body, entry)
        # A cloak hangs from the shoulders over the arms as they hang, not
        # as they are spread in the rest pose.
        pushed = body.arms_down(CLOAK_CAP) if slot == "cloak" else body
        if slot == "cloak":
            if "hang_width" in entry:
                narrow_hang(obj, body, entry["hang_width"])
            arm_slits(obj, body)
        if entry.get("outer_only"):
            drop_inner(obj, pushed)
        placed = coords(obj)
        under = under_garments(entry["over"]) if entry.get("over") else None
        # Pushed, relaxed back towards its placed shape and pushed again for
        # what the relaxing let near the skin, the legs or the garments under it.
        for final in (False, True):
            if entry.get("hang"):
                off_legs(obj, body, clearance, PUSH_SPREAD[slot])
            push_out(obj, pushed, clearance, PUSH_SPREAD[slot], PUSH_REACH[slot], under=under)
            if not final and entry.get("relax", True):
                relax(obj, pushed, placed, clearance, PUSH_REACH[slot], legs=not entry.get("hang"))
        if len(entry.get("ease", [])) > 2:
            draw_in(obj, body, entry["ease"][2])
    if slot == "cloak":
        bones, weights = cloak_weights(obj, body, entry)
    elif entry.get("weights") == "heat":
        bones, weights = heat_weights(obj, body, entry, slot)
    elif entry.get("weights") == "bones":
        bones, weights = bone_weights(obj, body, entry, slot)
    elif entry.get("finger_rig"):
        bones, weights = fit_fingered_glove.read_weights(obj, body)
    else:
        bones, weights = skin(obj, body, entry, slot)
    surfaces = [surface(obj, bones, weights)]
    offset = min(LINER_OFFSET.get(slot, 0.0), clearance * LINER_UNDER)
    bones = LINER_BONES.get(slot, [])
    if entry.get("hang"):
        # The legs go through a hanging skirt: lined, they would look in tights.
        bones = [b for b in bones if not b.endswith("Leg")]
    lining = liner(obj, body, bones, offset) if entry.get("liner") else None
    if lining is not None:
        lined = surface(lining, *skin_liner(lining, body, slot, offset))
        lined["color"] = liner_color(maps)
        surfaces.append(lined)
    os.makedirs(OUT_DIR, exist_ok=True)
    vertices, triangles = export(surfaces, body, os.path.join(OUT_DIR, piece_id + ".json"), maps,
                                 entry.get("tights"))
    print("%s: %d vertices, %d triangles (%d surfaces), maps %s" % (piece_id, vertices, triangles, len(surfaces),
                                                                    sorted(maps)))
    body_object(body)
    preview(obj, os.path.join(OUT_DIR, piece_id + "_preview.png"))


def reweight_piece(piece_id, entry, body):
    """Rebuild weights on an existing garment, without the Meshy downloads."""
    if entry.get("finger_rig") and entry.get("weights") != "heat":
        raise ValueError(f"{piece_id}: fit from the original mesh to use its finger landmarks")
    with open(os.path.join(SOURCE_DIR, piece_id + ".json")) as f:
        data = json.load(f)
    points = np.array(data["positions"]).reshape(-1, 3)
    triangles = np.array(data["indices"], dtype=np.int64).reshape(-1, 3)
    # Reconnect UV seams for the edge smoothing. Map back to the original
    # vertex order afterwards; the baked geometry and UVs are left intact.
    unique, inverse = np.unique(points.round(6), axis=0, return_inverse=True)
    mesh = bpy.data.meshes.new(piece_id)
    mesh.from_pydata(to_blender(unique).tolist(), [], inverse[triangles[:, [0, 2, 1]]].tolist())
    obj = bpy.data.objects.new(piece_id, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if entry.get("weights") == "heat":
        bones, weights = heat_weights(obj, body, entry, entry["slot"])
    elif entry.get("weights") == "bones":
        bones, weights = bone_weights(obj, body, entry, entry["slot"])
    else:
        bones, weights = skin(obj, body, entry, entry["slot"])
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, piece_id + ".json"), "w") as f:
        json.dump({"bones": body.names, "influences": bones[inverse].ravel().tolist(),
                   "weights": weights[inverse].round(7).ravel().tolist()}, f)
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    print("%s: reweighted %d vertices" % (piece_id, len(points)))


def main():
    body = Body(BODY_JSON)
    with open(PIECES_JSON) as f:
        pieces = json.load(f)
    # What goes over other pieces after them (it is pushed off them).
    for piece_id, entry in sorted(pieces.items(), key=lambda item: "over" in item[1]):
        if piece_id.startswith("_") or (ONLY and piece_id not in ONLY):
            continue
        if REWEIGHT:
            reweight_piece(piece_id, entry, body)
        else:
            fit_piece(piece_id, entry, body)


if __name__ == "__main__":
    main()
