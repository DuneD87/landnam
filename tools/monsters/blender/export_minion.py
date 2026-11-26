"""Exporta el esbirro de Cthulhu (Abyssal Maw) del .blend de trabajo a GLB para el juego.

Uso:
    blender -b ~/Documents/Codex/2026-11-26/bue/outputs/Abyssal_Maw_v2_1_Clips.blend \
        -P tools/monsters/blender/export_minion.py -- models/monsters/minion/minion.glb

Deja solo el rig y la malla. Las acciones salen con nombres cortos y con su rango completo: los ciclos
cierran con una copia de la primera pose (lo dice el LEEME del .blend), así que en Godot su duración es
la del bucle. A 30 fps, como el .blend. Mide 1,58 m y mira a -Y en Blender (a +Z en Godot).
"""

import sys

import bpy

RIG = "Abyssal Maw · Rig"
MESH = "Abyssal Maw · Malla"
ACTIONS = {
    "Idle_Tierra": "idle",
    "Idle_Agua": "idle_water",
    "Nado_Rapido": "swim",
    "Carrera_Cuadrupeda": "run",
    "Escalada": "climb",
    "Remonte_Borda": "board",
    "Salto_Cthulhu": "leap",
    "Zarpazos": "claws",
    "Agarre": "grab",
    "Devorar": "devour",
}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        raise SystemExit("falta la ruta del .glb de salida")
    out = argv[0]

    rig = bpy.data.objects[RIG]
    mesh = bpy.data.objects[MESH]
    for ob in list(bpy.data.objects):
        if ob not in (rig, mesh):
            bpy.data.objects.remove(ob, do_unlink=True)

    keep = set()
    for old, new in ACTIONS.items():
        act = bpy.data.actions[old]
        act.name = new
        act.use_fake_user = True
        keep.add(act)
    for act in list(bpy.data.actions):
        if act not in keep:
            bpy.data.actions.remove(act)

    rig.animation_data.action = bpy.data.actions["idle"]
    rig.name = "MinionRig"
    mesh.name = "MinionBody"

    for ob in (rig, mesh):
        ob.hide_set(False)
        ob.hide_viewport = False
        ob.hide_render = False
        for col in ob.users_collection:
            col.hide_viewport = False
            col.hide_render = False
    bpy.context.scene.render.fps = 30
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=False,
        use_visible=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_frame_step=1,
        export_anim_single_armature=True,
        export_reset_pose_bones=True,
        # Los anclajes (Anclaje.Presa, Anclaje.Agarre) no deforman pero hacen falta en el juego.
        export_def_bones=False,
        export_skins=True,
        export_yup=True,
        export_apply=False,
        export_tangents=True,
    )
    print("EXPORTED", out)


main()
