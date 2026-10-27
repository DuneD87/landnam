"""Saves MakeHuman's base head for tools/character/blender/hair_tool_convert.py.

Run with Blender 4.5 and MPFB:

    blender -b --python tools/character/blender/hair_tool_base.py -- <out.blend>

The human is the neutral one MakeHuman assets are made on (sex 0.5), with
the base body of export_mpfb_human.py otherwise. The mesh is saved without
helpers, its shape keys applied, as `MH_Base` (vertex groups kept), so
Blender 5.2 can wrap hair onto it without MPFB.
"""

import sys

import bpy

from bl_ext.blender_org.mpfb.services import HumanService, TargetService

## export_mpfb_human.BASE_MACROS with a neutral sex.
MACROS = {"gender": 0.5, "age": 0.5, "muscle": 0.5, "weight": 0.5, "proportions": 1.0, "height": 0.5,
          "cupsize": 0.5, "firmness": 0.5}
RACE = {"caucasian": 1.0, "african": 0.0, "asian": 0.0}


def neutral_human():
    """The human MakeHuman assets are fitted on; also used by hair_tool_mhclo.py."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    macro = TargetService.get_default_macro_info_dict()
    macro.update(MACROS)
    macro["race"].update(RACE)
    return HumanService.create_human(macro_detail_dict=macro)


def main(out):
    human = neutral_human()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for modifier in list(human.modifiers):
        human.modifiers.remove(modifier)
    mesh = bpy.data.meshes.new_from_object(human.evaluated_get(depsgraph), preserve_all_data_layers=True,
                                           depsgraph=depsgraph)
    base = bpy.data.objects.new("MH_Base", mesh)
    base.matrix_world = human.matrix_world
    for group in human.vertex_groups:
        base.vertex_groups.new(name=group.name)
    body = human.vertex_groups["body"].index
    keep = set()
    for vertex in human.data.vertices:
        for element in vertex.groups:
            base.vertex_groups[element.group].add([vertex.index], element.weight, "REPLACE")
            if element.group == body and element.weight > 0.5:
                keep.add(vertex.index)
    # Original indices, for the asset fit to find its anchors back.
    index = mesh.attributes.new("mh_index", "INT", "POINT")
    index.data.foreach_set("value", range(len(mesh.vertices)))
    bpy.context.scene.collection.objects.link(base)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    bpy.data.objects.remove(human)
    for obj in list(bpy.data.objects):
        if obj != base:
            bpy.data.objects.remove(obj)
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print("MH_Base vertices", len(mesh.vertices), "dims", tuple(base.dimensions))


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1])
