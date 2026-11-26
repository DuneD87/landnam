"""Exporta Cthulhu (Abyssal Dreadwing) del .blend de trabajo a GLB para el juego.

Uso:
    blender -b ~/Descargas/Cthulhu_Abyssal_Dreadwing_v6.blend \
        -P tools/monsters/blender/export_cthulhu.py -- models/monsters/cthulhu/cthulhu.glb

Deja solo el rig "Cthulhu · Rig" y su malla de Meshy: la toma del jugador, las formas de guía, el
suelo y la cámara son de la escena de revisión. Las acciones salen con nombres cortos (idle, walk...)
y con su rango completo: los bucles cierran con una copia de la primera pose, así que en Godot su
duración exacta es la del bucle sin repetir fotograma. La escala (1,7 m) se pone en el juego.
"""

import sys

import bpy

RIG = "Cthulhu · Rig"
MESH = "Abyssal Dreadwing · Meshy"
ACTIONS = {
    "Reposo · Idle": "idle",
    "Andar · Walk": "walk",
    "Alerta · Alert": "alert",
    "Despliegue de amenaza · Threat": "threat",
    "La mirada del abismo · Abyssal Gaze": "gaze",
    "Zarpazo de barrido · Sweep": "sweep",
    "Giro izquierda 90° · Turn L": "turn_l",
    "Giro derecha 90° · Turn R": "turn_r",
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
    rig.name = "CthulhuRig"
    mesh.name = "CthulhuBody"

    # El rig suele estar oculto en la vista: sin hacerlo visible el exportador lo salta y la malla
    # sale sin piel. Solo quedan estos dos objetos, así que se exporta la escena entera.
    for ob in (rig, mesh):
        ob.hide_set(False)
        ob.hide_viewport = False
        ob.hide_render = False
        for col in ob.users_collection:
            col.hide_viewport = False
            col.hide_render = False
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=False,
        use_visible=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        # Los bucles empiezan en el fotograma 1: sin esto el primer key cae en 1/24 s y el bucle se
        # engancha un fotograma.
        export_anim_slide_to_zero=True,
        export_frame_step=1,
        export_anim_single_armature=True,
        export_reset_pose_bones=True,
        export_def_bones=False,
        export_skins=True,
        export_yup=True,
        export_apply=False,
        export_tangents=True,
    )
    print("EXPORTED", out)


main()
