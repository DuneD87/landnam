"""Turns cards exported by hair_tool_convert.py into MakeHuman hair assets.

Run with Blender 4.5 and MPFB:

    blender -b --python tools/character/blender/hair_tool_mhclo.py -- <cards dir> <name> [<name>...]

For every name, <cards dir>/<name>.obj and <name>_atlas.png become the asset
`ht_<name>` (.mhclo, .obj, .mhmat and texture) in MPFB's user data, in hair/
(beard_* names go to clothes/, as the beards of export_mpfb_human.py), where
the exporter finds it like any other proxy. The fit is MakeClothes' own, on
the neutral human of hair_tool_base.py, the one the cards were wrapped on,
except that no card is anchored to the eyelids: hair falling over the face
would follow every blink (HumanShape.proxy_blink).
"""

import gzip
import os
import shutil
import sys
import uuid

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(__file__))
from hair_tool_base import neutral_human  # noqa: E402

from bl_ext.blender_org.mpfb.services import ClothesService, LocationService  # noqa: E402
from bl_ext.blender_org.mpfb.services import clothesservice  # noqa: E402

## The blink of export_mpfb_human.py (BLINK_TARGETS): what it moves anchors no hair.
BLINK_TARGETS = ["expression/units/caucasian/eye-left-closure", "expression/units/caucasian/eye-right-closure"]
## Base mesh group the cards are matched to: the body but the eyelids.
ANCHOR_GROUP = "hair_anchor"
## MakeHuman draws hair after the body by z_depth; the system hair uses 50.
Z_DEPTH = 50
MHMAT = """# Hair Tool library cards, converted by tools/character/blender/hair_tool_mhclo.py
name {name}
diffuseColor 1.0 1.0 1.0
transparent True
alphaToCoverage True
backfaceCull False
diffuseTexture {texture}
"""


def asset_dir(name):
    folder = "clothes" if name.startswith("beard_") else "hair"
    return os.path.join(LocationService.get_user_data(folder), "ht_" + name)


def import_cards(path, basemesh):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.obj_import(filepath=path, forward_axis="NEGATIVE_Z", up_axis="Y")
    cards = bpy.context.selected_objects[0]
    # Into the base mesh's space (MPFB scales it by 0.1): MakeClothes matches
    # local coordinates.
    cards.data.transform(basemesh.matrix_world.inverted() @ cards.matrix_world)
    cards.matrix_world = basemesh.matrix_world
    # MakeClothes wants faces of one size; halved cards mix quads and triangles.
    bm = bmesh.new()
    bm.from_mesh(cards.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(cards.data)
    bm.free()
    group = cards.vertex_groups.new(name=ANCHOR_GROUP)
    group.add(range(len(cards.data.vertices)), 1.0, "REPLACE")
    return cards


def add_anchor_group(basemesh):
    blinking = set()
    for target in BLINK_TARGETS:
        path = os.path.join(LocationService.get_mpfb_data("targets"), target + ".target.gz")
        with gzip.open(path, "rt") as f:
            for line in f:
                words = line.split()
                if len(words) == 4 and not line.startswith("#"):
                    blinking.add(int(words[0]))
    body = basemesh.vertex_groups["body"].index
    anchors = [v.index for v in basemesh.data.vertices if v.index not in blinking
               and any(g.group == body and g.weight > 0.5 for g in v.groups)]
    basemesh.vertex_groups.new(name=ANCHOR_GROUP).add(anchors, 1.0, "REPLACE")


class _NoXrefCache:
    """MPFB caches the base mesh's groups, without ANCHOR_GROUP."""

    @staticmethod
    def get_user_cache(name):
        return os.path.join(LocationService.get_user_cache(name), "__none__")


def convert(cards_dir, name, basemesh):
    asset = "ht_" + name
    out = asset_dir(name)
    os.makedirs(out, exist_ok=True)
    cards = import_cards(os.path.join(cards_dir, name + ".obj"), basemesh)
    cards.name = asset
    properties = {"name": asset, "uuid": str(uuid.uuid5(uuid.NAMESPACE_URL, "hair_tool/" + name)),
                  "author": "Hair Tool library (converted)", "license": "Hair Tool library license",
                  "description": "Hair Tool preset %s on MakeHuman's head" % name}
    cached, clothesservice.LocationService = clothesservice.LocationService, _NoXrefCache
    try:
        mhclo = ClothesService.create_mhclo_from_clothes_matching(basemesh, cards, properties_dict=properties,
                                                                  allow_exact=False)
    finally:
        clothesservice.LocationService = cached
    mhclo.zdepth = Z_DEPTH
    texture = asset + "_diffuse.png"
    shutil.copyfile(os.path.join(cards_dir, name + "_atlas.png"), os.path.join(out, texture))
    with open(os.path.join(out, asset + ".mhmat"), "w") as f:
        f.write(MHMAT.format(name=asset, texture=texture))
    mhclo.write_mhclo(os.path.join(out, asset + ".mhclo"), also_export_mhmat=True,
                      reference_scale=ClothesService.get_reference_scale(basemesh, "Head"))
    bpy.data.objects.remove(cards)
    print("HAIR_TOOL_ASSET", asset, out)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    basemesh = neutral_human()
    add_anchor_group(basemesh)
    for name in args[1:]:
        convert(args[0], name, basemesh)


main()
