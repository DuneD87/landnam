"""Exports the MakeHuman (MPFB) human the character creator is built on.

Run with Blender 4.5 and the MPFB extension plus the MakeHuman system assets
installed (see docs/character_creation.md):

    blender -b --python tools/character/blender/export_mpfb_human.py -- \
        <skeleton.json> <output dir>

<skeleton.json> is written by tools/character/dump_skeleton.gd: the joints of
the player skeleton in the space of its skin. The output is one JSON header
and one binary blob that tools/character/bake_character_human.gd turns into
Godot resources.

The human is built once (male, Mixamo rig, eyes, eyebrows, eyelashes, teeth,
tongue and every hair style); every other body is a *state* evaluated
numerically: female, each macro (muscle, weight, bust...) at both ends for
both sexes, and each MakeHuman target the creator exposes. For every state:

 1. the base mesh coordinates are the mix of MPFB's shape keys;
 2. proxies (eyes, hair...) are refitted with the MakeHuman clothes formula,
    three weighted body vertices plus a scaled offset;
 3. the joints of the Mixamo rig are found from the mesh (joint cubes or
    vertex means, as the MPFB rig file says);
 4. the whole thing is re-posed, bone by bone, so each bone points the way
    the player skeleton's bone points in its rest pose. The player animations
    can then drive the mesh without retargeting. The re-pose (and the ground
    height) of a sex's base body is used for all its other states, since the
    skeleton only changes joints per sex: a morph changes the surface, not
    where the body bends;
 5. it is moved to the player skin space: Y up, +Z forward, soles at the
    height the original model had them.

A morph is the difference between a state and the base state of its sex, kept
only where it is not zero.
"""

import json
import os
import struct
import sys
import gzip

import bpy
import numpy as np

from bl_ext.blender_org.mpfb.services import HumanService, TargetService, AssetService, LocationService
from bl_ext.blender_org.mpfb.entities.objectproperties import HumanObjectProperties
from bl_ext.blender_org.mpfb.entities.clothes.mhclo import Mhclo

ARGS = sys.argv[sys.argv.index("--") + 1:]
SKELETON_JSON = ARGS[0]
OUT_DIR = ARGS[1]

SYSTEM_DATA = LocationService.get_mpfb_data()
USER_DATA = LocationService.get_user_data()
RIG_FILE = os.path.join(SYSTEM_DATA, "rigs", "standard", "rig.mixamo.json")

## Height of the soles in the player skin space (the scanned model's rest pose).
SOLE_HEIGHT = -0.9506
## Bone name prefix of the player skeleton (MPFB uses "mixamorig:").
BONE_PREFIX = "mixamorig_"

MACROS = {"age": 0.5, "muscle": 0.5, "weight": 0.5, "proportions": 0.5, "height": 0.5,
          "cupsize": 0.5, "firmness": 0.5}
RACE = {"caucasian": 1.0, "african": 0.0, "asian": 0.0}
SEXES = {"male": 1.0, "female": 0.0}

## Morphs from macros: option id -> (macro, value at +1, value at -1). They
## depend on the rest of the body, so they are exported per sex.
MACRO_MORPHS = {
    "muscle": ("muscle", 1.0, 0.0),
    "body_weight": ("weight", 1.0, 0.1),
    "breast_size": ("cupsize", 1.0, 0.0),
    "breast_firmness": ("firmness", 1.0, 0.0),
    "age": ("age", 0.82, 0.42),
}

## Morphs from MakeHuman targets: option id -> (targets at +1, targets at -1).
## "l-/r-" pairs are both listed so one slider moves both sides.
def _sides(path):
    folder, name = path.split("/")
    return [folder + "/l-" + name, folder + "/r-" + name]

TARGET_MORPHS = {
    "head_width": (["head/head-scale-horiz-incr"], ["head/head-scale-horiz-decr"]),
    "forehead": (["forehead/forehead-scale-vert-incr"], ["forehead/forehead-scale-vert-decr"]),
    "jaw_width": (["chin/chin-bones-incr"], ["chin/chin-bones-decr"]),
    "chin_width": (["chin/chin-width-incr"], ["chin/chin-width-decr"]),
    "chin_length": (["chin/chin-height-incr"], ["chin/chin-height-decr"]),
    "chin_projection": (["chin/chin-prominent-incr"], ["chin/chin-prominent-decr"]),
    "cheekbones": (_sides("cheek/cheek-bones-incr"), _sides("cheek/cheek-bones-decr")),
    "cheeks": (_sides("cheek/cheek-volume-incr"), _sides("cheek/cheek-volume-decr")),
    "ear_size": (_sides("ears/ear-scale-incr"), _sides("ears/ear-scale-decr")),
    "ear_angle": (_sides("ears/ear-flap-incr"), _sides("ears/ear-flap-decr")),
    "eye_size": (_sides("eyes/eye-scale-incr"), _sides("eyes/eye-scale-decr")),
    "eye_spacing": (_sides("eyes/eye-trans-out"), _sides("eyes/eye-trans-in")),
    "eye_height": (_sides("eyes/eye-trans-up"), _sides("eyes/eye-trans-down")),
    "eye_tilt": (_sides("eyes/eye-corner2-up"), _sides("eyes/eye-corner2-down")),
    "brow_height": (["eyebrows/eyebrows-trans-up"], ["eyebrows/eyebrows-trans-down"]),
    "brow_angle": (["eyebrows/eyebrows-angle-up"], ["eyebrows/eyebrows-angle-down"]),
    "brow_depth": (["eyebrows/eyebrows-trans-forward"], ["eyebrows/eyebrows-trans-backward"]),
    "nose_size": (["nose/nose-volume-incr"], ["nose/nose-volume-decr"]),
    "nose_width": (["nose/nose-scale-horiz-incr"], ["nose/nose-scale-horiz-decr"]),
    "nose_length": (["nose/nose-scale-vert-incr"], ["nose/nose-scale-vert-decr"]),
    "nose_projection": (["nose/nose-trans-forward"], ["nose/nose-trans-backward"]),
    "nose_bridge": (["nose/nose-hump-incr"], ["nose/nose-hump-decr"]),
    "nose_tip": (["nose/nose-point-up"], ["nose/nose-point-down"]),
    "nostrils": (["nose/nose-nostrils-width-incr"], ["nose/nose-nostrils-width-decr"]),
    "mouth_width": (["mouth/mouth-scale-horiz-incr"], ["mouth/mouth-scale-horiz-decr"]),
    "mouth_height": (["mouth/mouth-trans-up"], ["mouth/mouth-trans-down"]),
    "mouth_projection": (["mouth/mouth-trans-forward"], ["mouth/mouth-trans-backward"]),
    "upper_lip": (["mouth/mouth-upperlip-volume-incr"], ["mouth/mouth-upperlip-volume-decr"]),
    "lower_lip": (["mouth/mouth-lowerlip-volume-incr"], ["mouth/mouth-lowerlip-volume-decr"]),
    "mouth_corners": (["mouth/mouth-angles-up"], ["mouth/mouth-angles-down"]),
    "neck_thickness": (["neck/neck-scale-horiz-incr", "neck/neck-scale-depth-incr"],
                       ["neck/neck-scale-horiz-decr", "neck/neck-scale-depth-decr"]),
    "torso_vshape": (["torso/torso-vshape-incr"], ["torso/torso-vshape-decr"]),
    "pectorals": (["torso/torso-muscle-pectoral-incr"], ["torso/torso-muscle-pectoral-decr"]),
    "abdomen": (["stomach/stomach-pregnant-incr"], ["stomach/stomach-pregnant-decr"]),
    "waist": (["torso/measure-waist-circ-incr"], ["torso/measure-waist-circ-decr"]),
    "hips": (["hip/hip-scale-horiz-incr"], ["hip/hip-scale-horiz-decr"]),
    "glutes": (["buttocks/buttocks-volume-incr"], ["buttocks/buttocks-volume-decr"]),
}

## Eyeballs follow the eyelids: MakeHuman anchors them to helper vertices
## that eye targets (scale, for one) do not move. Body vertices within this
## factor of an eyeball's radius form its eyelid ring.
EYELID_RING = 1.35

## Proxies: part name -> (MPFB asset type, asset name).
PROXIES = {"eyes": ("eyes", "high-poly"), "teeth": ("teeth", "teeth_base"), "tongue": ("tongue", "tongue01")}
for _i in range(1, 13):
    PROXIES["eyebrows_%03d" % _i] = ("eyebrows", "eyebrow%03d" % _i)
for _i in range(1, 3):
    PROXIES["eyelashes_%02d" % _i] = ("eyelashes", "eyelashes%02d" % _i)
# afro01 is left out: its texture tiles visibly on the Godot shader.
for _name in ["short01", "short02", "short03", "short04", "bob01", "bob02", "ponytail01", "long01",
              "braid01"]:
    PROXIES["hair_" + _name] = ("hair", _name)

SKINS = {"male": "young_caucasian_male", "female": "young_caucasian_female"}
EYE_MATERIAL = "lightblue"


# --- Player skeleton ---------------------------------------------------------

def load_skeleton():
    with open(SKELETON_JSON) as f:
        bones = json.load(f)["bones"]
    by_name = {b["name"]: b for b in bones}
    return bones, by_name


## For each MPFB bone, the player bone its direction is aligned to (its
## child along the chain; the hand points at the middle finger).
def direction_child(name):
    short = name[len(BONE_PREFIX):]
    table = {"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
             "Head": "HeadTop_End"}
    if short in table:
        return BONE_PREFIX + table[short]
    for side in ("Left", "Right"):
        chain = {"Shoulder": "Arm", "Arm": "ForeArm", "ForeArm": "Hand", "Hand": "HandMiddle1",
                 "UpLeg": "Leg", "Leg": "Foot", "Foot": "ToeBase", "ToeBase": "Toe_End"}
        for a, b in chain.items():
            if short == side + a:
                return BONE_PREFIX + side + b
        for finger in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
            for i in (1, 2, 3):
                if short == "%sHand%s%d" % (side, finger, i):
                    return BONE_PREFIX + "%sHand%s%d" % (side, finger, i + 1)
    return None


## Blender world (Z up, character facing -Y) <-> player skin space.
def to_skin_space(p):
    return np.stack([p[..., 0], p[..., 2] + SOLE_HEIGHT, -p[..., 1]], axis=-1)


def to_skin_dir(d):
    return np.stack([d[..., 0], d[..., 2], -d[..., 1]], axis=-1)


def skin_dir_to_blender(d):
    return np.array([d[0], -d[2], d[1]])


# --- Building the human ------------------------------------------------------

def build_human():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    macro = TargetService.get_default_macro_info_dict()
    macro.update(MACROS)
    macro["gender"] = SEXES["male"]
    macro["race"] = dict(RACE)
    human = HumanService.create_human(macro_detail_dict=macro)
    rig = HumanService.add_builtin_rig(human, "mixamo", import_weights=True)
    proxies = {}
    for part, (asset_type, asset) in PROXIES.items():
        path = AssetService.find_asset_absolute_path(asset + ".mhclo", asset_subdir=asset_type)
        obj = HumanService.add_mhclo_asset(path, human, asset_type=asset_type, subdiv_levels=0,
                                           material_type="MAKESKIN")
        mhclo = Mhclo()
        mhclo.load(path)
        proxies[part] = {"object": obj, "mhclo": mhclo, "path": path, "asset_type": asset_type, "asset": asset}
    return human, rig, proxies


def set_macros(human, values):
    for key, value in values.items():
        HumanObjectProperties.set_value(key, value, entity_reference=human)
    TargetService.reapply_macro_details(human, remove_zero_weight_targets=True)


def mixed_coords(human):
    keys = human.data.shape_keys.key_blocks
    n = len(human.data.vertices)
    basis = np.empty(n * 3, dtype=np.float64)
    keys[0].data.foreach_get("co", basis)
    basis = basis.reshape(-1, 3)
    result = basis.copy()
    buf = np.empty(n * 3, dtype=np.float64)
    for key in keys[1:]:
        if key.value == 0.0 or key.mute:
            continue
        key.data.foreach_get("co", buf)
        result += (buf.reshape(-1, 3) - basis) * key.value
    return result


def target_path(fragment):
    folder, name = fragment.split("/")
    for ext in (".target.gz", ".target"):
        path = os.path.join(SYSTEM_DATA, "targets", folder, name + ext)
        if os.path.exists(path):
            return path
    raise IOError("Missing target " + fragment)


# --- Proxies, joints, weights ------------------------------------------------

def fit_proxy(proxy, coords):
    mhclo = proxy["mhclo"]
    info = proxy.get("fit")
    if info is None:
        count = len(mhclo.verts)
        refs = np.zeros((count, 3), dtype=np.int64)
        weights = np.zeros((count, 3))
        offsets = np.zeros((count, 3))
        for i in range(count):
            v = mhclo.verts[i]
            refs[i] = v["verts"]
            weights[i] = v["weights"]
            offsets[i] = tuple(v["offsets"])
        info = proxy["fit"] = (refs, weights, offsets)
    refs, weights, offsets = info
    if mhclo.x_scale:
        x = abs(coords[mhclo.x_scale[0], 0] - coords[mhclo.x_scale[1], 0]) / mhclo.x_scale[2]
        y = abs(coords[mhclo.y_scale[0], 2] - coords[mhclo.y_scale[1], 2]) / mhclo.y_scale[2]
        z = abs(coords[mhclo.z_scale[0], 1] - coords[mhclo.z_scale[1], 1]) / mhclo.z_scale[2]
    else:
        x = y = z = 0.1
    scaled = offsets * np.array([x, z, y])
    return (coords[refs] * weights[..., None]).sum(axis=1) + scaled


def vertex_groups(obj):
    names = {g.index: g.name for g in obj.vertex_groups}
    groups = {}
    for v in obj.data.vertices:
        for g in v.groups:
            groups.setdefault(names[g.group], []).append((v.index, g.weight))
    return groups


def joint_positions(rig_bones, groups, coords):
    def resolve(spec):
        strategy = spec.get("strategy")
        if strategy == "CUBE":
            indices = [i for i, _ in groups[spec["cube_name"]]]
            return coords[indices].mean(axis=0)
        if strategy == "MEAN":
            return coords[spec["vertex_indices"]].mean(axis=0)
        if strategy == "VERTEX":
            return coords[spec["vertex_index"]]
        return np.array(spec["default_position"])
    heads = {}
    tails = {}
    for name, bone in rig_bones.items():
        short = name.replace("mixamorig:", BONE_PREFIX)
        heads[short] = resolve(bone["head"])
        tails[short] = resolve(bone["tail"])
    return heads, tails


def skin_weights(obj, bone_names):
    """Top four bone influences per vertex, as player-skeleton bone names."""
    names = {g.index: g.name.replace("mixamorig:", BONE_PREFIX) for g in obj.vertex_groups}
    n = len(obj.data.vertices)
    bones = np.zeros((n, 4), dtype=np.int32)
    weights = np.zeros((n, 4), dtype=np.float32)
    index = {name: i for i, name in enumerate(bone_names)}
    for v in obj.data.vertices:
        influences = [(g.weight, index[names[g.group]]) for g in v.groups
                      if names[g.group] in index and g.weight > 0.0]
        influences.sort(reverse=True)
        influences = influences[:4]
        total = sum(w for w, _ in influences)
        for k, (w, b) in enumerate(influences):
            bones[v.index, k] = b
            weights[v.index, k] = w / total if total > 0 else 0.0
        if not influences:
            weights[v.index, 0] = 1.0
            bones[v.index, 0] = index[BONE_PREFIX + "Head"]
    return bones, weights


# --- Re-posing ---------------------------------------------------------------

def rotation_between(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.999999:
        axis = np.cross(a, [1.0, 0.0, 0.0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0.0, 1.0, 0.0])
        axis /= np.linalg.norm(axis)
        return 2.0 * np.outer(axis, axis) - np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1.0 / (1.0 + c))


def repose_transforms(order, parents, heads, tails, skeleton_by_name):
    """Per bone (R, t) mapping MPFB rest to the player rest pose, and the posed joints."""
    transforms = {}
    posed = {}
    for name in order:
        head = heads[name]
        parent = parents[name]
        R_parent, t_parent = transforms[parent] if parent else (np.eye(3), np.zeros(3))
        head_posed = R_parent @ head + t_parent
        child = direction_child(name)
        tail = heads[child] if child in heads else tails[name]
        current = R_parent @ (tail - head)
        ours = skeleton_by_name[name]["mesh_joint"]
        wanted = skin_dir_to_blender(np.array(skeleton_by_name[child]["mesh_joint"]) - np.array(ours))
        R = rotation_between(current, wanted) @ R_parent
        t = head_posed - R @ head
        transforms[name] = (R, t)
        posed[name] = head_posed
        if child not in heads:
            posed[child] = R @ tails[name] + t
    return transforms, posed


def pose_points(points, bones, weights, bone_names, transforms):
    result = np.zeros_like(points)
    for k in range(4):
        w = weights[:, k:k + 1]
        for bone_index in np.unique(bones[:, k]):
            name = bone_names[bone_index]
            if name not in transforms:
                continue
            mask = bones[:, k] == bone_index
            R, t = transforms[name]
            result[mask] += (points[mask] @ R.T + t) * w[mask]
    return result


# --- Export geometry ---------------------------------------------------------

def surface_layout(obj, vertex_filter=None):
    """Splits Blender vertices by UV. Returns (source vertex per output vertex,
    uv per output vertex, triangles as output indices, clockwise)."""
    mesh = obj.data
    mesh.calc_loop_triangles()
    uv_layer = mesh.uv_layers.active
    loop_count = len(mesh.loops)
    loop_vertex = np.empty(loop_count, dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", loop_vertex)
    loop_uv = np.empty(loop_count * 2, dtype=np.float64)
    uv_layer.data.foreach_get("uv", loop_uv)
    loop_uv = loop_uv.reshape(-1, 2)
    tri_loops = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int64)
    mesh.loop_triangles.foreach_get("loops", tri_loops)
    tri_loops = tri_loops.reshape(-1, 3)
    if vertex_filter is not None:
        keep = vertex_filter[loop_vertex[tri_loops]].all(axis=1)
        tri_loops = tri_loops[keep]
    used = np.unique(tri_loops)
    keys = np.stack([loop_vertex[used], np.round(loop_uv[used, 0] * 1e5), np.round(loop_uv[used, 1] * 1e5)], axis=1)
    unique_keys, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    loop_to_out = np.full(loop_count, -1, dtype=np.int64)
    loop_to_out[used] = inverse.reshape(-1)
    source = loop_vertex[used[first]]
    uvs = loop_uv[used[first]]
    triangles = loop_to_out[tri_loops]
    # Blender fronts are counter-clockwise, Godot's clockwise.
    triangles = triangles[:, [0, 2, 1]]
    tri_vertices = loop_vertex[tri_loops]
    return source, uvs, triangles, tri_vertices


def smooth_normals(points, tri_vertices):
    a = points[tri_vertices[:, 0]]
    face = np.cross(points[tri_vertices[:, 1]] - a, points[tri_vertices[:, 2]] - a)
    normals = np.zeros_like(points)
    for k in range(3):
        np.add.at(normals, tri_vertices[:, k], face)
    length = np.linalg.norm(normals, axis=1, keepdims=True)
    return normals / np.maximum(length, 1e-12)


class Blob:
    def __init__(self):
        self.parts = []
        self.size = 0

    def add(self, array, dtype):
        data = np.ascontiguousarray(array, dtype=dtype).tobytes()
        entry = {"offset": self.size, "count": int(np.asarray(array).size), "type": np.dtype(dtype).name}
        self.parts.append(data)
        self.size += len(data)
        pad = (-len(data)) % 4
        if pad:
            self.parts.append(b"\0" * pad)
            self.size += pad
        return entry

    def write(self, path):
        with open(path, "wb") as f:
            for part in self.parts:
                f.write(part)


def mhmat_textures(path):
    textures = {}
    if not path or not os.path.exists(path):
        return textures
    folder = os.path.dirname(path)
    with open(path) as f:
        for line in f:
            words = line.split()
            if len(words) >= 2 and words[0].endswith("Texture"):
                textures[words[0]] = os.path.normpath(os.path.join(folder, words[1]))
    return textures


# --- Main --------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    skeleton, skeleton_by_name = load_skeleton()
    bone_names = [b["name"] for b in skeleton]
    with open(RIG_FILE) as f:
        rig_bones = json.load(f)["bones"]
    parents = {}
    for name, bone in rig_bones.items():
        short = name.replace("mixamorig:", BONE_PREFIX)
        parents[short] = bone["parent"].replace("mixamorig:", BONE_PREFIX) if bone["parent"] else ""
    order = []
    while len(order) < len(parents):
        for name, parent in parents.items():
            if name not in order and (not parent or parent in order):
                order.append(name)

    human, rig, proxies = build_human()
    groups = vertex_groups(human)
    body_filter = np.zeros(len(human.data.vertices), dtype=bool)
    body_filter[[i for i, _ in groups["body"]]] = True

    parts = {"body": {"object": human}}
    parts.update(proxies)
    for name, part in parts.items():
        obj = part["object"]
        part["bones"], part["weights"] = skin_weights(obj, bone_names)
        part["layout"] = surface_layout(obj, body_filter if name == "body" else None)

    eye_rest = {}

    def eyes_following_lids(coords):
        """The base eyeballs moved and scaled with their eyelid rings."""
        result = eye_rest["points"].copy()
        for side, (lids, mask) in eye_rest["sides"].items():
            before = eye_rest["coords"][lids]
            after = coords[lids]
            b_mean = before.mean(axis=0)
            a_mean = after.mean(axis=0)
            scale = np.sqrt(((after - a_mean) ** 2).sum() / ((before - b_mean) ** 2).sum())
            result[mask] = a_mean + (result[mask] - b_mean) * scale
        return result

    def evaluate(macros, targets, base=None):
        """A state. `base` is the (transforms, ground) of its sex's base body;
        without it they are measured on this state (base bodies)."""
        set_macros(human, macros)
        keys = [TargetService.load_target(human, target_path(t), weight=1.0) for t in targets]
        coords = mixed_coords(human)
        for key in keys:
            human.shape_key_remove(key)
        if not eye_rest:
            eyes = fit_proxy(parts["eyes"], coords)
            sides = {}
            for side, mask in (("left", eyes[:, 0] > 0), ("right", eyes[:, 0] <= 0)):
                center = eyes[mask].mean(axis=0)
                radius = np.linalg.norm(eyes[mask] - center, axis=1).max()
                near = np.linalg.norm(coords - center, axis=1) < radius * EYELID_RING
                lids = np.nonzero(near & body_filter)[0]
                sides[side] = (lids, mask)
            eye_rest.update(points=eyes, coords=coords.copy(), sides=sides)
        heads, tails = joint_positions(rig_bones, groups, coords)
        if base is None:
            transforms, posed_joints = repose_transforms(order, parents, heads, tails, skeleton_by_name)
        else:
            transforms, posed_joints = base[0], {}
        state = {}
        for name, part in parts.items():
            if name == "body":
                points = coords
            elif name == "eyes":
                points = eyes_following_lids(coords)
            else:
                points = fit_proxy(part, coords)
            state[name] = pose_points(points, part["bones"], part["weights"], bone_names, transforms)
        # Soles back on the ground after the re-pose.
        ground = state["body"][body_filter, 2].min() if base is None else base[1]
        for name in state:
            state[name][:, 2] -= ground
        joints = {k: v - np.array([0.0, 0.0, ground]) for k, v in posed_joints.items()}
        state["_repose"] = (transforms, ground)
        return state, joints

    def macro_values(sex, extra=None):
        values = dict(MACROS)
        values.update(RACE)
        values["gender"] = SEXES[sex]
        if extra:
            values.update(extra)
        return values

    blob = Blob()
    header = {"bones": bone_names, "parts": {}, "morphs": [], "joints": {}, "textures": {}}
    bases = {}
    for sex in SEXES:
        state, joints = evaluate(macro_values(sex), [])
        bases[sex] = state
        header["joints"][sex] = {name: to_skin_space(np.array(p)).tolist() for name, p in joints.items()}
        print("Base", sex, "height", state["body"][body_filter, 2].max())

    base = bases["male"]
    for name, part in parts.items():
        source, uvs, triangles, tri_vertices = part["layout"]
        positions = to_skin_space(base[name][source])
        normals = to_skin_dir(smooth_normals(base[name], tri_vertices)[source])
        entry = {
            "vertex_count": int(len(source)),
            "positions": blob.add(positions, np.float32),
            "normals": blob.add(normals, np.float32),
            "uvs": blob.add(np.stack([uvs[:, 0], 1.0 - uvs[:, 1]], axis=1), np.float32),
            "bones": blob.add(part["bones"][source], np.int32),
            "weights": blob.add(part["weights"][source], np.float32),
            "indices": blob.add(triangles, np.int32),
            "morphs": {},
        }
        if name == "body":
            arm = np.zeros(len(human.data.vertices))
            arm_bones = [i for i, b in enumerate(bone_names) if "Arm" in b or "Hand" in b or "Shoulder" in b]
            for k in range(4):
                arm += np.isin(part["bones"][:, k], arm_bones) * part["weights"][:, k]
            # UV2: rest height and arm weight, for the underwear bands.
            entry["uv2"] = blob.add(np.stack([positions[:, 1], arm[source]], axis=1), np.float32)
        if name != "body":
            entry["asset_type"] = part["asset_type"]
            entry["asset"] = part["asset"]
        header["parts"][name] = entry

    def add_morph(morph_name, state, reference):
        header["morphs"].append(morph_name)
        for name, part in parts.items():
            source, _, _, tri_vertices = part["layout"]
            delta = to_skin_dir(state[name][source] - reference[name][source])
            normal_delta = to_skin_dir(smooth_normals(state[name], tri_vertices)[source]
                                       - smooth_normals(reference[name], tri_vertices)[source])
            # Below 0.05 mm and 0.06 degrees nothing shows; keeping them only grows the data.
            moved = np.nonzero((np.abs(delta).max(axis=1) > 5e-5) | (np.abs(normal_delta).max(axis=1) > 1e-3))[0]
            if len(moved) == 0:
                continue
            header["parts"][name]["morphs"][morph_name] = {
                "indices": blob.add(moved, np.int32),
                "positions": blob.add(delta[moved], np.float32),
                "normals": blob.add(normal_delta[moved], np.float32),
            }

    add_morph("sex_female", bases["female"], bases["male"])
    for option, (macro, high, low) in MACRO_MORPHS.items():
        for sex in SEXES:
            for suffix, value in (("", high), ("-", low)):
                state, _ = evaluate(macro_values(sex, {macro: value}), [], bases[sex]["_repose"])
                add_morph("%s%s@%s" % (option, suffix, sex), state, bases[sex])
        print("Macro morph", option)
    for option, (increase, decrease) in TARGET_MORPHS.items():
        for suffix, targets in (("", increase), ("-", decrease)):
            state, _ = evaluate(macro_values("male"), targets, base["_repose"])
            add_morph(option + suffix, state, base)
        print("Target morph", option)

    # Textures and materials.
    for sex, skin in SKINS.items():
        path = AssetService.find_asset_absolute_path(skin + ".mhmat", asset_subdir="skins")
        header["textures"]["skin_" + sex] = mhmat_textures(path)
    header["textures"]["eyes"] = mhmat_textures(
        AssetService.find_asset_absolute_path(EYE_MATERIAL + ".mhmat", asset_subdir="eyes"))
    for name, part in proxies.items():
        if part["asset_type"] == "eyes":
            continue
        header["textures"][name] = mhmat_textures(part["mhclo"].material)
    header["masks"] = {name: os.path.join(SYSTEM_DATA, "textures", "mpfb_%s.jpg" % name)
                       for name in ("lips", "eyelids", "face", "aureolae", "crotch", "fingernails", "toenails")}

    blob.write(os.path.join(OUT_DIR, "human.bin"))
    with open(os.path.join(OUT_DIR, "human.json"), "w") as f:
        json.dump(header, f, indent=1)
    print("EXPORTED", len(header["morphs"]), "morphs,", blob.size, "bytes")


main()
