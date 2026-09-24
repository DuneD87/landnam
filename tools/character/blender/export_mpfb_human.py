"""Exports the MakeHuman (MPFB) human the character creator is built on.

Run with Blender 4.5 and the MPFB extension, with the MakeHuman system assets
and the community packs listed in docs/character_creation.md installed:

    blender -b --python tools/character/blender/export_mpfb_human.py -- \
        <skeleton.json> <output dir>

<skeleton.json> is written by tools/character/dump_skeleton.gd: the joints of
the player skeleton in the space of its skin. The output is one JSON header
and one binary blob that tools/character/bake_character_human.gd turns into
Godot resources, plus the skin masks of make_skin_masks.py.

The human is built once (male, Mixamo rig, every proxy: eyes, eyebrows,
eyelashes, teeth, tongue, hair styles and beards); every other body is a
*state* evaluated numerically. For every state:

 1. the base mesh coordinates are the mix of MPFB's shape keys;
 2. proxies are refitted with the MakeHuman clothes formula (three weighted
    body vertices plus a scaled offset); eyeballs follow their eyelids;
 3. the joints of the Mixamo rig are found from the mesh (joint cubes or
    vertex means, as the MPFB rig file says);
 4. the limbs are re-posed, bone by bone, so each bone points the way the
    player skeleton's bone points in its rest pose, and the player animations
    drive it without retargeting (the trunk keeps MakeHuman's natural curve;
    its joints are only spaced like the player's). A base body measures its own re-pose; every
    other state reuses its sex's, so a morph changes shape and joints but not
    bone directions;
 5. the soles are put back on the ground and it is moved to the player skin
    space: Y up, +Z forward, soles at the height the original model had them.

Joints follow the morphs. Each morph stores how much it moves every joint and,
per vertex, only the *residual*: the displacement left once the vertex has
moved with the joints it is skinned to. At runtime the skeleton is shifted to
the weighted joints and the skin supplies that rigid part, so a morph that
lengthens a leg also moves the knee, and hair that just rides on a taller
body stores almost nothing.

The body keeps every morph as sparse residuals (and normal changes). Proxies
(hair, beards, eyebrows...) keep no morphs: at runtime they are refitted
exactly as here, in raw MakeHuman space, from the anchors they reference
(three weighted vertices, possibly extrapolated, plus an offset scaled by
the body), then posed with their sex's bone transforms. Anchors are exported
as raw points with raw sparse displacements per morph; eyeballs follow their
eyelid rings instead. Proxies keep their base normals.

Morph kinds:
 - sex_female: the female base against the male one.
 - macros (muscle, weight, age, height, bust...): per sex, "<id>@<sex>" for
   the positive side and "<id>-@<sex>" for the negative one.
 - crosses: the bilinear correction of two macros moved together, per sex
   and quadrant ("muscle&body_weight-@male").
 - head morphs (ancestry): only the head changes, normalised to the head
   joint and size, so they change features but not height or head size.
 - targets: MakeHuman's anatomical targets, sex independent, "<id>" and
   "<id>-".
"""

import json
import os
import sys
import types

import bpy
import numpy as np
from mathutils.kdtree import KDTree

from bl_ext.blender_org.mpfb.services import HumanService, TargetService, AssetService, LocationService
from bl_ext.blender_org.mpfb.entities.objectproperties import HumanObjectProperties
from bl_ext.blender_org.mpfb.entities.clothes.mhclo import Mhclo

ARGS = sys.argv[sys.argv.index("--") + 1:]
SKELETON_JSON = ARGS[0]
OUT_DIR = ARGS[1]

SYSTEM_DATA = LocationService.get_mpfb_data()
RIG_FILE = os.path.join(SYSTEM_DATA, "rigs", "standard", "rig.mixamo.json")

## Height of the soles in the player skin space (the scanned model's rest pose).
SOLE_HEIGHT = -0.9506
## Bone name prefix of the player skeleton (MPFB uses "mixamorig:").
BONE_PREFIX = "mixamorig_"
HEAD = BONE_PREFIX + "Head"
HEAD_TOP = BONE_PREFIX + "HeadTop_End"

## Base body. proportions 1 is MakeHuman's "idealistic" body.
BASE_MACROS = {"age": 0.5, "muscle": 0.5, "weight": 0.5, "proportions": 1.0, "height": 0.5,
               "cupsize": 0.5, "firmness": 0.5, "caucasian": 1.0, "african": 0.0, "asian": 0.0}
SEXES = {"male": 1.0, "female": 0.0}


def _sides(path, weight=1.0):
    folder, name = path.split("/")
    return {folder + "/l-" + name: weight, folder + "/r-" + name: weight}


def _merge(*parts):
    result = {}
    for part in parts:
        result.update(part)
    return result


## Local muscles added to the muscle macro: the macro alone barely builds the arms.
_MUSCLE_LOCAL = _merge(
    _sides("arms/upperarm-muscle-incr", 0.7), _sides("arms/lowerarm-muscle-incr", 0.7),
    _sides("arms/upperarm-shoulder-muscle-incr", 0.7), _sides("legs/upperleg-muscle-incr", 0.6),
    _sides("legs/lowerleg-muscle-incr", 0.6), {"torso/torso-muscle-dorsi-incr": 0.5})
MUSCLE_TARGETS = {
    "male": _merge(_MUSCLE_LOCAL, {"torso/torso-muscle-pectoral-incr": 0.5}),
    "female": _MUSCLE_LOCAL,
}

## Macro morphs, per sex: id -> (macros at +1, macros at -1, sexes). A
## "targets" entry adds targets to that side (per sex when it is a dict of sexes).
MACRO_MORPHS = {
    "muscle": ({"muscle": 1.0, "targets": MUSCLE_TARGETS}, {"muscle": 0.0}, ("male", "female")),
    "body_weight": ({"weight": 1.0}, {"weight": 0.1}, ("male", "female")),
    "age": ({"age": 0.82}, {"age": 0.42}, ("male", "female")),
    "height": ({"height": 0.85}, {"height": 0.15}, ("male", "female")),
    "breast_size": ({"cupsize": 1.0}, {"cupsize": 0.0}, ("female",)),
    "breast_firmness": ({"firmness": 1.0}, {"firmness": 0.0}, ("female",)),
}
## Pairs of macro morphs whose combination gets a bilinear correction.
CROSS_MORPHS = [("muscle", "body_weight")]
## Face-only macro morphs, per sex, from 0 to 1.
HEAD_MORPHS = {
    "race_african": {"african": 1.0, "caucasian": 0.0},
    "race_asian": {"asian": 1.0, "caucasian": 0.0},
}

## Target morphs, sex independent: id -> (targets at +1, targets at -1 or None).
TARGET_MORPHS = {
    # Head and neck.
    "head_size": ({"head/head-scale-horiz-incr": 1, "head/head-scale-vert-incr": 1, "head/head-scale-depth-incr": 1},
                  {"head/head-scale-horiz-decr": 1, "head/head-scale-vert-decr": 1, "head/head-scale-depth-decr": 1}),
    "head_width": ({"head/head-scale-horiz-incr": 1}, {"head/head-scale-horiz-decr": 1}),
    "head_round": ({"head/head-round": 1}, None),
    "head_square": ({"head/head-square": 1}, None),
    "head_oval": ({"head/head-oval": 1}, None),
    "head_diamond": ({"head/head-diamond": 1}, None),
    "head_triangular": ({"head/head-triangular": 1}, {"head/head-invertedtriangular": 1}),
    "head_fat": ({"head/head-fat-incr": 1}, {"head/head-fat-decr": 1}),
    "forehead": ({"forehead/forehead-scale-vert-incr": 1}, {"forehead/forehead-scale-vert-decr": 1}),
    "forehead_slope": ({"forehead/forehead-trans-backward": 1}, {"forehead/forehead-trans-forward": 1}),
    "temples": ({"forehead/forehead-temple-incr": 1}, {"forehead/forehead-temple-decr": 1}),
    "neck_thickness": ({"neck/neck-scale-horiz-incr": 1, "neck/neck-scale-depth-incr": 1},
                       {"neck/neck-scale-horiz-decr": 1, "neck/neck-scale-depth-decr": 1}),
    "neck_length": ({"neck/neck-scale-vert-incr": 1}, {"neck/neck-scale-vert-decr": 1}),
    # Jaw, chin and cheeks.
    "jaw_width": ({"chin/chin-bones-incr": 1}, {"chin/chin-bones-decr": 1}),
    "jaw_angle": ({"chin/chin-jaw-drop-incr": 1}, {"chin/chin-jaw-drop-decr": 1}),
    "chin_width": ({"chin/chin-width-incr": 1}, {"chin/chin-width-decr": 1}),
    "chin_length": ({"chin/chin-height-incr": 1}, {"chin/chin-height-decr": 1}),
    "chin_projection": ({"chin/chin-prominent-incr": 1}, {"chin/chin-prominent-decr": 1}),
    "chin_cleft": ({"chin/chin-cleft-incr": 1}, None),
    "cheekbones": (_sides("cheek/cheek-bones-incr"), _sides("cheek/cheek-bones-decr")),
    "cheekbone_height": (_sides("cheek/cheek-trans-up"), _sides("cheek/cheek-trans-down")),
    "cheeks": (_sides("cheek/cheek-volume-incr"), _sides("cheek/cheek-volume-decr")),
    "cheeks_inner": (_sides("cheek/cheek-inner-incr"), _sides("cheek/cheek-inner-decr")),
    # Ears.
    "ear_size": (_sides("ears/ear-scale-incr"), _sides("ears/ear-scale-decr")),
    "ear_angle": (_sides("ears/ear-flap-incr"), _sides("ears/ear-flap-decr")),
    "ear_lobe": (_sides("ears/ear-lobe-incr"), _sides("ears/ear-lobe-decr")),
    "ear_pointed": (_sides("ears/ear-shape-pointed"), None),
    # Eyes and brows.
    "eye_size": (_sides("eyes/eye-scale-incr"), _sides("eyes/eye-scale-decr")),
    "eye_spacing": (_sides("eyes/eye-trans-out"), _sides("eyes/eye-trans-in")),
    "eye_height": (_sides("eyes/eye-trans-up"), _sides("eyes/eye-trans-down")),
    "eye_tilt": (_sides("eyes/eye-corner2-up"), _sides("eyes/eye-corner2-down")),
    "eye_depth": (_sides("eyes/eye-push1-in"), _sides("eyes/eye-push1-out")),
    "eye_opening": (_sides("eyes/eye-height2-incr"), _sides("eyes/eye-height2-decr")),
    "eye_bags": (_sides("eyes/eye-bag-incr"), _sides("eyes/eye-bag-decr")),
    "eyelid": (_sides("eyes/eye-eyefold-down"), _sides("eyes/eye-eyefold-up")),
    "epicanthus": (_sides("eyes/eye-epicanthus-in"), _sides("eyes/eye-epicanthus-out")),
    "brow_height": ({"eyebrows/eyebrows-trans-up": 1}, {"eyebrows/eyebrows-trans-down": 1}),
    "brow_angle": ({"eyebrows/eyebrows-angle-up": 1}, {"eyebrows/eyebrows-angle-down": 1}),
    "brow_depth": ({"eyebrows/eyebrows-trans-forward": 1}, {"eyebrows/eyebrows-trans-backward": 1}),
    # Nose.
    "nose_size": ({"nose/nose-volume-incr": 1}, {"nose/nose-volume-decr": 1}),
    "nose_width": ({"nose/nose-scale-horiz-incr": 1}, {"nose/nose-scale-horiz-decr": 1}),
    "nose_length": ({"nose/nose-scale-vert-incr": 1}, {"nose/nose-scale-vert-decr": 1}),
    "nose_projection": ({"nose/nose-trans-forward": 1}, {"nose/nose-trans-backward": 1}),
    "nose_bridge": ({"nose/nose-hump-incr": 1}, {"nose/nose-hump-decr": 1}),
    "nose_bridge_width": ({"nose/nose-width1-incr": 1}, {"nose/nose-width1-decr": 1}),
    "nose_curve": ({"nose/nose-curve-convex": 1}, {"nose/nose-curve-concave": 1}),
    "nose_tip": ({"nose/nose-point-up": 1}, {"nose/nose-point-down": 1}),
    "nose_tip_width": ({"nose/nose-point-width-incr": 1}, {"nose/nose-point-width-decr": 1}),
    "nostrils": ({"nose/nose-nostrils-width-incr": 1}, {"nose/nose-nostrils-width-decr": 1}),
    "nose_flaring": ({"nose/nose-flaring-incr": 1}, {"nose/nose-flaring-decr": 1}),
    # Mouth.
    "mouth_width": ({"mouth/mouth-scale-horiz-incr": 1}, {"mouth/mouth-scale-horiz-decr": 1}),
    "mouth_height": ({"mouth/mouth-trans-up": 1}, {"mouth/mouth-trans-down": 1}),
    "mouth_projection": ({"mouth/mouth-trans-forward": 1}, {"mouth/mouth-trans-backward": 1}),
    "upper_lip": ({"mouth/mouth-upperlip-volume-incr": 1}, {"mouth/mouth-upperlip-volume-decr": 1}),
    "lower_lip": ({"mouth/mouth-lowerlip-volume-incr": 1}, {"mouth/mouth-lowerlip-volume-decr": 1}),
    "mouth_corners": ({"mouth/mouth-angles-up": 1}, {"mouth/mouth-angles-down": 1}),
    "cupids_bow": ({"mouth/mouth-cupidsbow-incr": 1}, {"mouth/mouth-cupidsbow-decr": 1}),
    "philtrum": ({"mouth/mouth-philtrum-volume-incr": 1}, {"mouth/mouth-philtrum-volume-decr": 1}),
    # Body.
    "shoulder_width": ({"torso/measure-shoulder-dist-incr": 1}, {"torso/measure-shoulder-dist-decr": 1}),
    "torso_vshape": ({"torso/torso-vshape-incr": 1}, {"torso/torso-vshape-decr": 1}),
    "pectorals": ({"torso/torso-muscle-pectoral-incr": 1}, {"torso/torso-muscle-pectoral-decr": 1}),
    "chest_depth": ({"torso/torso-scale-depth-incr": 1}, {"torso/torso-scale-depth-decr": 1}),
    "torso_width": ({"torso/torso-scale-horiz-incr": 1}, {"torso/torso-scale-horiz-decr": 1}),
    "lats": ({"torso/torso-muscle-dorsi-incr": 1}, {"torso/torso-muscle-dorsi-decr": 1}),
    "nape": ({"neck/neck-back-scale-depth-incr": 1}, {"neck/neck-back-scale-depth-decr": 1}),
    "breast_position": ({"breast/breast-trans-up": 1}, {"breast/breast-trans-down": 1}),
    "breast_spacing": ({"breast/breast-dist-incr": 1}, {"breast/breast-dist-decr": 1}),
    "abdomen": ({"stomach/stomach-pregnant-incr": 1}, {"stomach/stomach-pregnant-decr": 1}),
    "waist": ({"torso/measure-waist-circ-incr": 1}, {"torso/measure-waist-circ-decr": 1}),
    "hips": ({"hip/hip-scale-horiz-incr": 1}, {"hip/hip-scale-horiz-decr": 1}),
    "glutes": ({"buttocks/buttocks-volume-incr": 1}, {"buttocks/buttocks-volume-decr": 1}),
    "arms": (_merge(_sides("arms/upperarm-fat-incr"), _sides("arms/lowerarm-fat-incr")),
             _merge(_sides("arms/upperarm-fat-decr"), _sides("arms/lowerarm-fat-decr"))),
    "legs": (_merge(_sides("legs/upperleg-fat-incr"), _sides("legs/lowerleg-fat-incr")),
             _merge(_sides("legs/upperleg-fat-decr"), _sides("legs/lowerleg-fat-decr"))),
    # Male genitals (the genitals helper).
    "penis_length": ({"genitals/penis-length-incr": 1}, {"genitals/penis-length-decr": 1}),
    "penis_girth": ({"genitals/penis-circ-incr": 1}, {"genitals/penis-circ-decr": 1}),
    "testicles": ({"genitals/penis-testicles-incr": 1}, {"genitals/penis-testicles-decr": 1}),
}

## The blink, baked per sex as "blink@<sex>": MakeHuman's eyelid closure
## units. It is no slider: the rig animates it (HumanBlink) and fits the
## eyelashes to it, while the eyeballs stay put.
BLINK_TARGETS = {"expression/units/caucasian/eye-left-closure": 1, "expression/units/caucasian/eye-right-closure": 1}

## Morphs whose proxies are checked against the runtime fit.
VALIDATION_MORPHS = {"sex_female", "muscle@male", "body_weight@female", "height-@female", "race_african@male",
                     "head_size", "head_fat", "forehead", "jaw_width", "neck_thickness", "shoulder_width"}
## Float quantization before writing, so the compressed resources shrink:
## positions to 1/65536 m (15 microns), normal changes to 1/4096.
POSITION_STEP = 1.0 / 65536.0
NORMAL_STEP = 1.0 / 4096.0

## Eyeballs follow the eyelids: MakeHuman anchors them to helper vertices
## that eye targets (scale, for one) do not move. Body vertices within this
## factor of an eyeball's radius form its eyelid ring.
EYELID_RING = 1.35

## Skin weights come from the player's own mesh (dumped with the skeleton),
## since the player animations were made for it: MakeHuman's weights fold the
## back and shoulders in them. Hands, feet and the head keep MakeHuman's,
## finer there; a vertex's share of these bones says how much of its own it
## keeps. The re-pose itself uses MakeHuman's weights.
KEEP_WEIGHT_BONES = ("Hand", "Foot", "Toe", "Head")
## Player vertices each MakeHuman vertex takes its weights from.
TRANSFER_NEIGHBOURS = 16
## Diffusion of the transferred weights over the body's surface: a weight that
## changes bone within one ring of vertices folds into a step when the spine
## bends (the idle showed one across the lower back).
WEIGHT_SMOOTHING_STEPS = 24
WEIGHT_SMOOTHING = 0.5
## The spine joints are spaced between hips and neck as the player's are:
## MakeHuman's sit lower, and the longer upper spine that leaves swings neck,
## shoulders and head far forward whenever an animation bends it (the idle
## looked hunched).
SPINE_CHAIN = ["Hips", "Spine", "Spine1", "Spine2", "Neck"]
## Bones the re-pose leaves as MakeHuman has them. Straightening its S-curved
## spine to the player's (over 20 degrees a joint) folded the lower back into
## a step and pushed the chest out; the trunk needs no re-pose, since animations
## rotate each bone from the player's rest orientation whatever its shape.
TRUNK_BONES = SPINE_CHAIN + ["Head"]

## Proxies: part name -> (MPFB asset folder, asset name).
PROXIES = {"eyes": ("eyes", "high-poly"), "teeth": ("teeth", "teeth_base"), "tongue": ("tongue", "tongue01")}
for _i in range(1, 13):
    PROXIES["eyebrows_%03d" % _i] = ("eyebrows", "eyebrow%03d" % _i)
for _i in range(1, 3):
    PROXIES["eyelashes_%02d" % _i] = ("eyelashes", "eyelashes%02d" % _i)
HAIRS = [
    # Male cuts.
    "short01", "short03", "culturalibre_hair_02", "elvs_maxwell_hair", "culturalibre_hair_14",
    "elvs_short_side_do", "elvs_grump_hair", "faydaen_hair_1", "rehmanpolanski_hair_bun_brown",
    "punkduck_alpha7_long",
    # Female cuts.
    "long01", "elvs_adrienne_hair", "elvs_that_80s_babe_hair", "elvs_katherine_hair", "punkduck_alpha7_curly",
    "braid01", "elvs_unkempt_french_braid", "elvs_double_mh_braid", "elvs_keylth_hair", "elvs_50s_updo",
    "toigo_blunt_bob_with_bangs", "elvs_wavy_bob", "elvs_braided_rows", "elvs_micky_afro",
    "grinsegold_wig_bun_blonde_braids",
]
for _name in HAIRS:
    PROXIES["hair_" + _name] = ("hair", _name)
BEARDS = ["grinsegold_full_beard", "elvs_scruffy_beard1", "rehmanpolanski_beard_viking", "culturalibre_faun_beard",
          "grinsegold_moustache", "rehmanpolanski_moustache_viking"]
for _name in BEARDS:
    PROXIES["beard_" + _name] = ("clothes", _name)
## Parts that are MakeHuman helper geometry (hidden in MPFB) rather than
## assets: part name -> vertex group. They ride on the body like proxies whose
## every vertex is its own anchor, and MakeHuman's targets shape them.
HELPERS = {"genitals": "helper-genital"}
## Helpers are mapped on a plain corner of the skin atlas; they get a patch of
## body skin instead, this many times their corner's size, so they show its
## tone, pores and relief: the inner thigh by the groin (HELPER_SKIN_OFFSET
## from the helper's root, Blender axes), which no skin paints hair on.
HELPER_UV_SCALE = 1.5
HELPER_SKIN_OFFSET = (0.07, 0.0, -0.06)

## Skins offered per sex: id -> (MPFB skin asset, sex).
SKINS = {
    "light_m": ("young_caucasian_male", "male"),
    "freckles_m": ("toigo_light_skin_male_freckles", "male"),
    "bronze_m": ("toigo_light_skin_male_bronze", "male"),
    "rugged_m": ("jartur69_middleage_slavic_male_with_genitals_and_beard", "male"),
    "mature_m": ("middleage_caucasian_male", "male"),
    "tattoo_m": ("rehmanpolanski_skin_viking_tattoos", "male"),
    "dark_m": ("young_african_male", "male"),
    "asian_m": ("young_asian_male", "male"),
    "light_f": ("young_caucasian_female", "female"),
    "freckles_f": ("toigo_light_skin_female_freckles", "female"),
    "bronze_f": ("toigo_light_skin_female_bronze", "female"),
    "ginger_f": ("toigo_light_skin_female_ginger", "female"),
    "midtone_f": ("callharvey3d_midtoned_female", "female"),
    "zoey_f": ("nyloseth_zoeyskin", "female"),
    "dark_f": ("young_african_female", "female"),
    "asian_f": ("young_asian_female", "female"),
}
## Skin relief for every skin (MakeHuman skins share one UV layout).
NORMAL_SKIN = "mindfront_skin_male_african_middleage"
EYE_MATERIAL = "lightblue"


# --- Player skeleton ---------------------------------------------------------

def load_skeleton():
    with open(SKELETON_JSON) as f:
        data = json.load(f)
    bones = data["bones"]
    return bones, {b["name"]: b for b in bones}, data.get("mesh")


## For each MPFB bone, the player bone its direction is aligned to (its child
## along the chain; the hand points at the middle finger).
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
    for key, value in BASE_MACROS.items():
        if key in macro["race"]:
            macro["race"][key] = value
        else:
            macro[key] = value
    macro["gender"] = SEXES["male"]
    human = HumanService.create_human(macro_detail_dict=macro)
    rig = HumanService.add_builtin_rig(human, "mixamo", import_weights=True)
    proxies = {}
    for part, (folder, asset) in PROXIES.items():
        path = AssetService.find_asset_absolute_path(asset + ".mhclo", asset_subdir=folder)
        if path is None:
            raise IOError("Missing asset %s/%s" % (folder, asset))
        obj = HumanService.add_mhclo_asset(path, human, asset_type="Clothes" if folder == "clothes" else folder,
                                           subdiv_levels=0, material_type="MAKESKIN", import_subrig=False,
                                           import_weights=False)
        mhclo = Mhclo()
        mhclo.load(path)
        proxies[part] = {"object": obj, "mhclo": mhclo, "path": path, "folder": folder, "asset": asset}
    for part, group in HELPERS.items():
        proxies[part] = helper_part(human, group)
    return human, rig, proxies


def helper_part(human, group_name):
    """A helper vertex group of the human as a proxy of its own: a mesh with
    those vertices, faces, UVs and bone weights, fitted to itself."""
    group = human.vertex_groups[group_name].index
    members = [v.index for v in human.data.vertices if any(g.group == group for g in v.groups)]
    local = {v: i for i, v in enumerate(members)}
    faces = [p for p in human.data.polygons if all(v in local for v in p.vertices)]
    mesh = bpy.data.meshes.new(group_name)
    mesh.from_pydata([human.data.vertices[v].co[:] for v in members], [],
                     [[local[v] for v in p.vertices] for p in faces])
    source_uv = human.data.uv_layers.active.data
    corner = np.array([source_uv[loop].uv[:] for p in faces for loop in p.loop_indices])
    # The body vertex nearest the skin patch, beside the helper's root (its
    # highest vertices).
    co = np.array([v.co[:] for v in human.data.vertices])
    root = co[members][co[members][:, 2] >= np.percentile(co[members][:, 2], 90)].mean(axis=0)
    body_group = human.vertex_groups["body"].index
    body = np.array([v.index for v in human.data.vertices if any(g.group == body_group for g in v.groups)])
    nearest = body[np.argmin(np.linalg.norm(co[body] - (root + np.array(HELPER_SKIN_OFFSET)), axis=1))]
    anchor = np.mean([source_uv[loop.index].uv[:] for loop in human.data.loops if loop.vertex_index == nearest], axis=0)
    centre = (corner.min(axis=0) + corner.max(axis=0)) * 0.5
    uv = mesh.uv_layers.new(name="UVMap").data
    for face, p in zip(mesh.polygons, faces):
        for target, loop in zip(face.loop_indices, p.loop_indices):
            uv[target].uv = anchor + (np.array(source_uv[loop].uv[:]) - centre) * HELPER_UV_SCALE
    obj = bpy.data.objects.new(group_name, mesh)
    names = {g.index: g.name for g in human.vertex_groups}
    for v in members:
        for g in human.data.vertices[v].groups:
            if names[g.group].startswith("mixamorig:"):
                target = obj.vertex_groups.get(names[g.group]) or obj.vertex_groups.new(name=names[g.group])
                target.add([local[v]], g.weight, "REPLACE")
    refs = np.repeat(np.array(members, dtype=np.int64)[:, None], 3, axis=1)
    weights = np.tile([1.0, 0.0, 0.0], (len(members), 1))
    return {"object": obj, "mhclo": types.SimpleNamespace(x_scale=None, material=None), "path": None,
            "folder": "helper", "asset": group_name, "fit": (refs, weights, np.zeros((len(members), 3)))}


_current_macros = {}


def set_macros(human, values):
    if values == _current_macros:
        return
    for key, value in values.items():
        HumanObjectProperties.set_value(key, value, entity_reference=human)
    TargetService.reapply_macro_details(human, remove_zero_weight_targets=True)
    _current_macros.clear()
    _current_macros.update(values)


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
    folder, name = fragment.rsplit("/", 1)
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
    """Top four bone influences per vertex, as player-skeleton bone indices."""
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
            bones[v.index, 0] = index[HEAD]
    return bones, weights


def transfer_skin_weights(points, normals, joints, bones, weights, bone_names, skeleton, mesh, tri_vertices):
    """Dense (vertex, bone) skin weights for MakeHuman vertices in the player
    rest pose (skin space), from the player mesh. Each vertex first moves by its
    bones' joint differences, so limbs line up with the player's, then takes the
    weights of its nearest player vertices that face its way."""
    n, bone_count = len(points), len(bone_names)
    rows = np.repeat(np.arange(n), 4)
    own = np.zeros((n, bone_count))
    np.add.at(own, (rows, bones.ravel()), weights.ravel())
    player_joints = np.array([b["mesh_joint"] for b in skeleton])
    warped = points + ((player_joints - joints)[bones] * weights[..., None]).sum(axis=1)
    target = np.array(mesh["positions"]).reshape(-1, 3)
    target_normals = np.array(mesh["normals"]).reshape(-1, 3)
    target_bones = np.array(mesh["bones"], dtype=np.int64).reshape(-1, 4)
    target_weights = np.array(mesh["weights"]).reshape(-1, 4)
    kd = KDTree(len(target))
    for i, p in enumerate(target):
        kd.insert(p, i)
    kd.balance()
    transferred = np.zeros((n, bone_count))
    for i in range(n):
        found = kd.find_n(warped[i], TRANSFER_NEIGHBOURS)
        near = np.array([f[1] for f in found])
        score = 1.0 / (np.array([f[2] for f in found]) + 0.003) ** 2
        if normals[i].any():
            score *= np.clip(target_normals[near] @ normals[i], 0.05, 1.0) ** 2
        np.add.at(transferred[i], target_bones[near].ravel(), (score[:, None] * target_weights[near]).ravel())
    transferred /= np.maximum(transferred.sum(axis=1, keepdims=True), 1e-12)
    keep = np.array([any(k in name for k in KEEP_WEIGHT_BONES) for name in bone_names])
    kept = own[:, keep].sum(axis=1, keepdims=True)
    blended = transferred * (1.0 - kept) + own * kept
    # Smooth over the surface, leaving what MakeHuman's weights keep.
    edges = np.concatenate([tri_vertices[:, [0, 1]], tri_vertices[:, [1, 2]], tri_vertices[:, [2, 0]]])
    edges = np.unique(np.sort(edges, axis=1), axis=0)
    degree = np.zeros(n)
    np.add.at(degree, edges.ravel(), 1.0)
    rate = WEIGHT_SMOOTHING * (1.0 - kept) * (degree[:, None] > 0)
    for _ in range(WEIGHT_SMOOTHING_STEPS):
        neighbours = np.zeros_like(blended)
        np.add.at(neighbours, edges[:, 0], blended[edges[:, 1]])
        np.add.at(neighbours, edges[:, 1], blended[edges[:, 0]])
        mean = neighbours / np.maximum(degree, 1.0)[:, None]
        blended += rate * (mean - blended)
    return blended


def top_influences(dense):
    """The four largest weights per row, normalised: (bones, weights)."""
    bones = np.argsort(-dense, axis=1)[:, :4]
    weights = np.take_along_axis(dense, bones, axis=1)
    weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-12)
    return bones.astype(np.int32), weights.astype(np.float32)


def spine_fractions(skeleton_by_name):
    """Where the player's inner spine joints sit along its hips-neck chain (0-1)."""
    points = np.array([skeleton_by_name[BONE_PREFIX + n]["mesh_joint"] for n in SPINE_CHAIN])
    lengths = np.linalg.norm(np.diff(points, axis=0), axis=1)
    return np.cumsum(lengths)[:-1] / lengths.sum()


def respace_spine(heads, fractions):
    """Moves the inner spine joints along MakeHuman's own hips-neck polyline
    (so its curve stays) to the player's fractions of its length."""
    names = [BONE_PREFIX + n for n in SPINE_CHAIN]
    points = np.array([heads[n] for n in names])
    lengths = np.linalg.norm(np.diff(points, axis=0), axis=1)
    along = np.concatenate([[0.0], np.cumsum(lengths)]) / lengths.sum()
    for name, f in zip(names[1:-1], fractions):
        k = min(np.searchsorted(along, f, side="right") - 1, len(lengths) - 1)
        t = (f - along[k]) / (along[k + 1] - along[k])
        heads[name] = points[k] + (points[k + 1] - points[k]) * t


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
    """Per bone (R, t) mapping MakeHuman space to the player rest pose."""
    transforms = {}
    for name in order:
        head = heads[name]
        parent = parents[name]
        R_parent, t_parent = transforms[parent] if parent else (np.eye(3), np.zeros(3))
        head_posed = R_parent @ head + t_parent
        child = direction_child(name)
        if name[len(BONE_PREFIX):] in TRUNK_BONES:
            transforms[name] = (R_parent, head_posed - R_parent @ head)
            continue
        tail = heads[child] if child in heads else tails[name]
        current = R_parent @ (tail - head)
        wanted = skin_dir_to_blender(np.array(skeleton_by_name[child]["mesh_joint"])
                                     - np.array(skeleton_by_name[name]["mesh_joint"]))
        R = rotation_between(current, wanted) @ R_parent
        transforms[name] = (R, head_posed - R @ head)
    return transforms


def pose_joints(order, parents, heads, tails, transforms):
    """Joint positions (bone heads, and the tips of chain ends) after the re-pose."""
    posed = {}
    for name in order:
        parent = parents[name]
        R, t = transforms[parent] if parent else (np.eye(3), np.zeros(3))
        posed[name] = R @ heads[name] + t
        child = direction_child(name)
        if child is not None and child not in heads:
            Rb, tb = transforms[name]
            posed[child] = Rb @ tails[name] + tb
    return posed


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
    uv per output vertex, triangles as output indices (clockwise), triangles
    as source vertices)."""
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
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    loop_to_out = np.full(loop_count, -1, dtype=np.int64)
    loop_to_out[used] = inverse.reshape(-1)
    source = loop_vertex[used[first]]
    uvs = loop_uv[used[first]]
    # Blender fronts are counter-clockwise, Godot's clockwise.
    triangles = loop_to_out[tri_loops][:, [0, 2, 1]]
    return source, uvs, triangles, loop_vertex[tri_loops]


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


def strand_axis(texture_path):
    """0 when the strands of a hair texture run along U, 1 along V."""
    image = bpy.data.images.load(texture_path, check_existing=False)
    w, h = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(image)
    luma = pixels[..., :3].mean(axis=2) * pixels[..., 3]
    along_u = np.abs(np.diff(luma, axis=0)).sum()   # changes across V: strands run along U
    along_v = np.abs(np.diff(luma, axis=1)).sum()   # changes across U: strands run along V
    return 0 if along_u > along_v else 1


# --- Main --------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    skeleton, skeleton_by_name, player_mesh = load_skeleton()
    bone_names = [b["name"] for b in skeleton]
    bone_index = {name: i for i, name in enumerate(bone_names)}
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

    spine = spine_fractions(skeleton_by_name)
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
        part["head_weight"] = (part["weights"] * (part["bones"] == bone_index[HEAD])).sum(axis=1)

    eye_rest = {}

    def eyes_following_lids(coords):
        """The base eyeballs moved and scaled with their eyelid rings."""
        result = eye_rest["points"].copy()
        for lids, mask in eye_rest["sides"]:
            before = eye_rest["coords"][lids]
            after = coords[lids]
            b_mean = before.mean(axis=0)
            a_mean = after.mean(axis=0)
            scale = np.sqrt(((after - a_mean) ** 2).sum() / ((before - b_mean) ** 2).sum())
            result[mask] = a_mean + (result[mask] - b_mean) * scale
        return result

    def evaluate(macros, targets=None, transforms=None):
        """A state: raw MakeHuman coordinates, posed points per part and posed
        joints. Without `transforms` the re-pose is measured on this state."""
        set_macros(human, macros)
        keys = [TargetService.load_target(human, target_path(t), weight=w) for t, w in (targets or {}).items()]
        coords = mixed_coords(human)
        for key in keys:
            human.shape_key_remove(key)
        if not eye_rest:
            eyes = fit_proxy(parts["eyes"], coords)
            sides = []
            for mask in (eyes[:, 0] > 0, eyes[:, 0] <= 0):
                center = eyes[mask].mean(axis=0)
                radius = np.linalg.norm(eyes[mask] - center, axis=1).max()
                near = np.linalg.norm(coords - center, axis=1) < radius * EYELID_RING
                sides.append((np.nonzero(near & body_filter)[0], mask))
            eye_rest.update(points=eyes, coords=coords.copy(), sides=sides)
        heads, tails = joint_positions(rig_bones, groups, coords)
        respace_spine(heads, spine)
        if transforms is None:
            transforms = repose_transforms(order, parents, heads, tails, skeleton_by_name)
        joints = pose_joints(order, parents, heads, tails, transforms)
        points = {}
        for name, part in parts.items():
            if name == "body":
                raw = coords
            elif name == "eyes":
                raw = eyes_following_lids(coords)
            else:
                raw = fit_proxy(part, coords)
            points[name] = pose_points(raw, part["bones"], part["weights"], bone_names, transforms)
        # Soles back on the ground after the re-pose.
        ground = points["body"][body_filter, 2].min()
        for name in points:
            points[name][:, 2] -= ground
        joint_array = np.array([joints[b] for b in bone_names]) - np.array([0.0, 0.0, ground])
        return {"raw": coords, "ground": ground, "points": points, "joints": joint_array, "transforms": transforms}

    def macro_values(sex, extra=None):
        values = dict(BASE_MACROS)
        values["gender"] = SEXES[sex]
        for key, value in (extra or {}).items():
            if key != "targets":
                values[key] = value
        return values

    def side_targets(side, sex):
        targets = side.get("targets", {})
        return targets.get(sex, {}) if targets and isinstance(next(iter(targets.values())), dict) else targets

    def diff(a, b):
        return {"raw": a["raw"] - b["raw"], "ground": a["ground"] - b["ground"],
                "points": {p: a["points"][p] - b["points"][p] for p in a["points"]},
                "joints": a["joints"] - b["joints"]}

    def normals_of(state):
        if "_normals" not in state:
            state["_normals"] = {p: smooth_normals(state["points"][p], parts[p]["layout"][3]) for p in parts}
        return state["_normals"]

    def with_normals(delta, a, b, c=None, d=None):
        """Attaches the body's normal deltas a - b (- c + d for crosses)."""
        normals = normals_of(a)["body"] - normals_of(b)["body"]
        if c is not None:
            normals = normals - normals_of(c)["body"] + normals_of(d)["body"]
        delta["normals"] = normals
        return delta

    def quantize(values, step):
        return np.round(values / step) * step

    # Base bodies.
    bases = {}
    for sex in SEXES:
        bases[sex] = evaluate(macro_values(sex))
        print("Base", sex, "height %.3f" % bases[sex]["points"]["body"][body_filter, 2].max())
    base = bases["male"]

    # Skin weights: the player mesh's, for the body and, through their fitting
    # vertices, the proxies (the eyes follow their lids and keep their own).
    for part in parts.values():
        part["skin_bones"], part["skin_weights"] = part["bones"], part["weights"]
    if player_mesh:
        body_skin = transfer_skin_weights(
            to_skin_space(base["points"]["body"]), to_skin_dir(normals_of(base)["body"]),
            to_skin_space(base["joints"]), parts["body"]["bones"], parts["body"]["weights"],
            bone_names, skeleton, player_mesh, parts["body"]["layout"][3])
        parts["body"]["skin_bones"], parts["body"]["skin_weights"] = top_influences(body_skin)
        for name, part in proxies.items():
            if part["folder"] == "helper":
                # Helpers stand off the body, nearer the scan's thighs than its
                # pelvis: they ride the pelvis alone.
                dense = np.zeros((len(part["fit"][0]), len(bone_names)))
                dense[:, bone_index[BONE_PREFIX + "Hips"]] = 1.0
                part["skin_bones"], part["skin_weights"] = top_influences(dense)
            elif name != "eyes":
                refs, fit_weights, _ = part["fit"]
                dense = np.clip((body_skin[refs] * fit_weights[..., None]).sum(axis=1), 0.0, None)
                part["skin_bones"], part["skin_weights"] = top_influences(dense)
        print("Skin weights transferred from the player mesh")

    # Anchors: the raw MakeHuman vertices proxies are fitted to (body or helper
    # geometry), the eyelid rings and the pairs MakeHuman scales offsets by.
    needed = set()
    for name, part in proxies.items():
        if name == "eyes":
            for lids, _ in eye_rest["sides"]:
                needed.update(int(i) for i in lids)
            continue
        needed.update(int(r) for r in part["fit"][0].ravel())
        mhclo = part["mhclo"]
        if mhclo.x_scale:
            for pair in (mhclo.x_scale, mhclo.y_scale, mhclo.z_scale):
                needed.update((int(pair[0]), int(pair[1])))
    anchors = np.array(sorted(needed), dtype=np.int64)
    anchor_of = np.full(len(base["raw"]), -1, dtype=np.int64)
    anchor_of[anchors] = np.arange(len(anchors))

    blob = Blob()
    header = {"bones": bone_names, "body": {}, "proxies": {}, "morphs": [], "joint_deltas": {},
              "ground": {sex: float(bases[sex]["ground"]) for sex in SEXES}, "ground_deltas": {},
              "anchors": {"count": int(len(anchors)), "raw": blob.add(base["raw"][anchors], np.float32), "morphs": {}},
              "textures": {}, "skins": {}}
    header["joints"] = to_skin_space(base["joints"]).tolist()
    # Per sex and bone, raw MakeHuman space -> skin space (before subtracting the ground).
    to_skin = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]])
    header["pose"] = {}
    for sex in SEXES:
        transforms = {}
        for name, (R, t) in bases[sex]["transforms"].items():
            transforms[name] = {"basis": (to_skin @ R).ravel().tolist(),
                                "origin": (to_skin @ t + np.array([0.0, SOLE_HEIGHT, 0.0])).tolist()}
        header["pose"][sex] = transforms
    validation = {}

    def add_morph(name, delta, reference, sex):
        """Stores a morph from its full displacement against `reference`."""
        header["morphs"].append(name)
        jd = delta["joints"]
        if np.abs(jd).max() > 1e-6:
            header["joint_deltas"][name] = to_skin_dir(jd).tolist()
        if abs(delta["ground"]) > 1e-7:
            header["ground_deltas"][name] = float(delta["ground"])
        # Body: residual after the joints' rigid part, and normal changes.
        body = parts["body"]
        rigid = (jd[body["skin_bones"]] * body["skin_weights"][..., None]).sum(axis=1)
        source = body["layout"][0]
        residual = to_skin_dir(delta["points"]["body"] - rigid)[source]
        normal_delta = to_skin_dir(delta["normals"][source])
        # Below 0.1 mm and 0.1 degrees nothing shows; keeping them only grows the data.
        moved = np.nonzero((np.abs(residual).max(axis=1) > 1e-4) | (np.abs(normal_delta).max(axis=1) > 2e-3))[0]
        if len(moved):
            header["body"]["morphs"][name] = {
                "indices": blob.add(moved, np.int32),
                "positions": blob.add(quantize(residual[moved], POSITION_STEP), np.float32),
                "normals": blob.add(quantize(normal_delta[moved], NORMAL_STEP), np.float32),
            }
        # Anchors: raw displacement.
        raw = delta["raw"][anchors]
        moved = np.nonzero(np.abs(raw).max(axis=1) > 1e-5)[0]
        if len(moved):
            header["anchors"]["morphs"][name] = {
                "indices": blob.add(moved, np.int32),
                "positions": blob.add(quantize(raw[moved], POSITION_STEP), np.float32),
            }
        if name in VALIDATION_MORPHS:
            validation[name] = {
                "raw": reference["raw"] + delta["raw"], "ground": reference["ground"] + delta["ground"], "sex": sex,
                "points": {p: to_skin_space(reference["points"][p] + delta["points"][p]) for p in proxies}}

    # Base surfaces (male).
    kd = KDTree(int(body_filter.sum()))
    body_indices = np.nonzero(body_filter)[0]
    for i, v in zip(body_indices, base["points"]["body"][body_indices]):
        kd.insert(v, int(i))
    kd.balance()
    for name, part in parts.items():
        source, uvs, triangles, tri_vertices = part["layout"]
        points = base["points"][name]
        positions = to_skin_space(points[source])
        normals = to_skin_dir(normals_of(base)[name][source])
        entry = {
            "vertex_count": int(len(source)),
            "positions": blob.add(positions, np.float32),
            "normals": blob.add(normals, np.float32),
            "uvs": blob.add(np.stack([uvs[:, 0], 1.0 - uvs[:, 1]], axis=1), np.float32),
            "bones": blob.add(part["skin_bones"][source], np.int32),
            "weights": blob.add(part["skin_weights"][source], np.float32),
            "indices": blob.add(triangles, np.int32),
        }
        if name == "body":
            # Groups the skin masks are drawn from.
            for group in ("scalp", "lips", "ears"):
                member = np.zeros(len(points), dtype=np.float32)
                for i, w in groups.get(group, []):
                    member[i] = w
                entry["group_" + group] = blob.add(member[source], np.float32)
            entry["morphs"] = {}
            header["body"] = entry
            continue
        entry["folder"] = part["folder"]
        entry["asset"] = part["asset"]
        # Runtime refit, per source (Blender) vertex; `source` maps output vertices to them.
        entry["source"] = blob.add(source, np.int32)
        entry["pose_bones"] = blob.add(part["bones"], np.int32)
        entry["pose_weights"] = blob.add(part["weights"], np.float32)
        # UV2.x: distance to the body, for hair ambient occlusion near the scalp.
        distance = np.array([kd.find(p)[2] for p in points[source]], dtype=np.float32)
        entry["uv2"] = blob.add(np.stack([distance, np.zeros_like(distance)], axis=1), np.float32)
        if name == "eyes":
            side = np.zeros(len(points), dtype=np.int32)
            rings = []
            for index, (lids, mask) in enumerate(eye_rest["sides"]):
                rings.append(blob.add(anchor_of[lids], np.int32))
                side[mask] = index
            entry["lids"] = {"rings": rings, "side": blob.add(side, np.int32),
                             "raw": blob.add(eye_rest["points"], np.float32)}
        else:
            refs, weights, offsets = part["fit"]
            fit = {"refs": blob.add(anchor_of[refs], np.int32), "weights": blob.add(weights, np.float32),
                   "offsets": blob.add(offsets, np.float32)}
            mhclo = part["mhclo"]
            if mhclo.x_scale:
                fit["scales"] = [[int(anchor_of[pair[0]]), int(anchor_of[pair[1]]), float(pair[2])]
                                 for pair in (mhclo.x_scale, mhclo.y_scale, mhclo.z_scale)]
            entry["fit"] = fit
        header["proxies"][name] = entry

    # Sex.
    add_morph("sex_female", with_normals(diff(bases["female"], base), bases["female"], base), base, "female")

    # Macros, per sex.
    macro_states = {}
    for morph, (high, low, sexes) in MACRO_MORPHS.items():
        for sex in sexes:
            for suffix, side in (("", high), ("-", low)):
                state = evaluate(macro_values(sex, side), side_targets(side, sex), bases[sex]["transforms"])
                macro_states[(morph, suffix, sex)] = (state, side)
                add_morph("%s%s@%s" % (morph, suffix, sex), with_normals(diff(state, bases[sex]), state, bases[sex]),
                          bases[sex], sex)
                if morph == "height":
                    print("  height%s@%s %.3f" % (suffix, sex, state["points"]["body"][body_filter, 2].max()))
        print("Macro morph", morph)

    # Crosses: the bilinear term of two macros moved together.
    for a, b in CROSS_MORPHS:
        for sex in SEXES:
            if (a, "", sex) not in macro_states or (b, "", sex) not in macro_states:
                continue
            for sa in ("", "-"):
                for sb in ("", "-"):
                    state_a, side_a = macro_states[(a, sa, sex)]
                    state_b, side_b = macro_states[(b, sb, sex)]
                    macros = macro_values(sex, _merge(side_a, side_b))
                    targets = _merge(side_targets(side_a, sex), side_targets(side_b, sex))
                    both = evaluate(macros, targets, bases[sex]["transforms"])
                    delta = diff(diff(diff(both, bases[sex]), diff(state_a, bases[sex])), diff(state_b, bases[sex]))
                    add_morph("%s%s&%s%s@%s" % (a, sa, b, sb, sex),
                              with_normals(delta, both, state_a, state_b, bases[sex]), bases[sex], sex)
        print("Cross morph", a, b)

    # Head-only macros: the head's shape relative to its joint, at the base head
    # size. Raw anchor displacements are the posed ones un-rotated by each
    # vertex's blended bone rotation, so the runtime refit poses them back.
    head_index = bone_index[HEAD]
    top_index = bone_index[HEAD_TOP]
    body_bones, body_weights = parts["body"]["bones"], parts["body"]["weights"]
    for morph, macros in HEAD_MORPHS.items():
        for sex in SEXES:
            ref = bases[sex]
            state = evaluate(macro_values(sex, macros), None, ref["transforms"])
            j_new, j_ref = state["joints"][head_index], ref["joints"][head_index]
            core = parts["body"]["head_weight"] > 0.99
            spread_new = np.sqrt(((state["points"]["body"][core] - j_new) ** 2).sum())
            spread_ref = np.sqrt(((ref["points"]["body"][core] - j_ref) ** 2).sum())
            scale = spread_new / spread_ref
            points = {}
            for p in parts:
                target = (state["points"][p] - j_new) / scale + j_ref
                points[p] = (target - ref["points"][p]) * parts[p]["head_weight"][:, None]
            joints = np.zeros_like(ref["joints"])
            joints[top_index] = (state["joints"][top_index] - j_new) / scale + j_ref - ref["joints"][top_index]
            rotations = np.stack([ref["transforms"].get(b, (np.eye(3), None))[0] for b in bone_names])
            blended = (rotations[body_bones] * body_weights[..., None, None]).sum(axis=1)
            raw = np.linalg.solve(blended, points["body"][..., None])[..., 0]
            shaped_normals = smooth_normals(ref["points"]["body"] + points["body"], parts["body"]["layout"][3])
            delta = {"raw": raw, "ground": 0.0, "points": points, "joints": joints,
                     "normals": shaped_normals - normals_of(ref)["body"]}
            add_morph("%s@%s" % (morph, sex), delta, ref, sex)
        print("Head morph", morph)

    # Anatomical targets, on the male base.
    base_macros = macro_values("male")
    for morph, (increase, decrease) in TARGET_MORPHS.items():
        for suffix, targets in (("", increase), ("-", decrease)):
            if targets is None:
                continue
            state = evaluate(base_macros, targets, base["transforms"])
            add_morph(morph + suffix, with_normals(diff(state, base), state, base), base, "male")
        print("Target morph", morph)

    # Blink, on each sex's base.
    for sex in SEXES:
        state = evaluate(macro_values(sex), BLINK_TARGETS, bases[sex]["transforms"])
        add_morph("blink@" + sex, with_normals(diff(state, bases[sex]), state, bases[sex]), bases[sex], sex)
    print("Blink")

    # The runtime refit (see header) against the exact proxies.
    print("Fit check")
    for name, check in validation.items():
        raw_anchors = check["raw"]
        worst = (0.0, "")
        for part_name, part in proxies.items():
            if part_name == "eyes":
                fitted = eye_rest["points"].copy()
                for lids, mask in eye_rest["sides"]:
                    before = base["raw"][lids]
                    after = raw_anchors[lids]
                    b_mean, a_mean = before.mean(axis=0), after.mean(axis=0)
                    s = np.sqrt(((after - a_mean) ** 2).sum() / ((before - b_mean) ** 2).sum())
                    fitted[mask] = a_mean + (fitted[mask] - b_mean) * s
            else:
                fitted = fit_proxy(part, raw_anchors)
            posed = np.zeros_like(fitted)
            pose = header["pose"][check["sex"]]
            for k in range(4):
                for b in np.unique(part["bones"][:, k]):
                    bone = bone_names[b]
                    if bone not in pose:
                        continue
                    mask = part["bones"][:, k] == b
                    basis = np.array(pose[bone]["basis"]).reshape(3, 3)
                    origin = np.array(pose[bone]["origin"])
                    posed[mask] += (fitted[mask] @ basis.T + origin) * part["weights"][mask, k:k + 1]
            posed[:, 1] -= check["ground"]
            error = np.abs(posed - check["points"][part_name]).max()
            if error > worst[0]:
                worst = (error, part_name)
        print("  %-24s worst %.2f mm (%s)" % (name, worst[0] * 1000.0, worst[1]))

    # Textures and materials.
    for skin_id, (asset, sex) in SKINS.items():
        path = AssetService.find_asset_absolute_path(asset + ".mhmat", asset_subdir="skins")
        textures = mhmat_textures(path)
        if "diffuseTexture" not in textures:
            raise IOError("Skin %s has no diffuse texture" % asset)
        header["skins"][skin_id] = {"sex": sex, "asset": asset, "diffuse": textures["diffuseTexture"]}
    normal_skin = mhmat_textures(AssetService.find_asset_absolute_path(NORMAL_SKIN + ".mhmat", asset_subdir="skins"))
    header["textures"]["skin_normal"] = normal_skin.get("normalmapTexture")
    header["textures"]["skin_specular"] = normal_skin.get("specularTexture")
    header["textures"]["eyes"] = mhmat_textures(
        AssetService.find_asset_absolute_path(EYE_MATERIAL + ".mhmat", asset_subdir="eyes"))
    for name, part in proxies.items():
        if part["folder"] in ("eyes", "helper"):
            continue
        textures = mhmat_textures(part["mhclo"].material)
        header["textures"][name] = textures
        if part["folder"] in ("hair", "clothes", "eyebrows", "eyelashes") and "diffuseTexture" in textures:
            header["proxies"][name]["strand_axis"] = strand_axis(textures["diffuseTexture"])
    header["masks"] = {name: os.path.join(SYSTEM_DATA, "textures", "mpfb_%s.jpg" % name)
                       for name in ("lips", "eyelids")}

    blob.write(os.path.join(OUT_DIR, "human.bin"))
    with open(os.path.join(OUT_DIR, "human.json"), "w") as f:
        json.dump(header, f, indent=1)
    print("EXPORTED", len(header["morphs"]), "morphs,", blob.size, "bytes")


main()
