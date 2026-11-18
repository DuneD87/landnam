"""Blender --python export_fitted_fbx.py -- <dump_skeleton.json> <fit dir> <FBX dir> <piece ids...>

Export single-surface Meshy garments fitted to the scan. Each FBX contains
the player's rest armature in metres, its named weights and embedded PBR maps.
"""
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fit_meshy_armor import to_blender, to_blender_dir


def player_armature(bones):
    data = bpy.data.armatures.new("Player")
    arm = bpy.data.objects.new("Player", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    space = Matrix.Rotation(math.pi / 2, 4, "X")
    joints = [Vector(to_blender(np.array(b["mesh_joint"]))) for b in bones]
    for index, bone in enumerate(bones):
        edit = data.edit_bones.new(bone["name"])
        if bone["parent"] >= 0:
            edit.parent = data.edit_bones[bones[bone["parent"]]["name"]]
        rest = space @ Quaternion(bone["mesh_rotation"]).to_matrix().to_4x4()
        rest.translation = joints[index]
        children = [i for i, child in enumerate(bones) if child["parent"] == index]
        edit.tail = (0, 0.04, 0)
        edit.matrix = rest
        edit.length = max(0.005, min(((joints[i] - joints[index]).length for i in children), default=0.025))
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def add_material(mesh, maps):
    material = bpy.data.materials.new(mesh.name)
    mesh.materials.append(material)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    link = material.node_tree.links.new
    shader = nodes.get("Principled BSDF")
    for kind, socket in [("albedo", "Base Color"), ("metallic", "Metallic"), ("roughness", "Roughness"), ("normal", "Normal")]:
        if kind not in maps:
            continue
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(maps[kind], check_existing=True)
        if kind != "albedo":
            tex.image.colorspace_settings.name = "Non-Color"
        output = tex.outputs["Color"]
        if kind == "normal":
            normal = nodes.new("ShaderNodeNormalMap")
            link(output, normal.inputs["Color"])
            output = normal.outputs["Normal"]
        link(output, shader.inputs[socket])


def export_piece(path, data, skeleton):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    arm = player_armature(skeleton)
    surface, = data["surfaces"]
    points = to_blender(np.array(surface["positions"]).reshape(-1, 3))
    normals = to_blender_dir(np.array(surface["normals"]).reshape(-1, 3))
    uv = np.array(surface["uvs"]).reshape(-1, 2)
    uv[:, 1] = 1 - uv[:, 1]
    faces = np.array(surface["indices"]).reshape(-1, 3)[:, [0, 2, 1]]
    mesh = bpy.data.meshes.new(path.stem)
    mesh.from_pydata(points.tolist(), [], faces.tolist())
    mesh.update()
    mesh.uv_layers.new(name="UVMap").data.foreach_set("uv", uv[faces.ravel()].astype("f").ravel())
    mesh.polygons.foreach_set("use_smooth", np.ones(len(faces), dtype=bool))
    mesh.normals_split_custom_set_from_vertices(normals.tolist())
    obj = bpy.data.objects.new(mesh.name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.parent = arm
    modifier = obj.modifiers.new("Player skin", "ARMATURE")
    modifier.object = arm
    influences = np.array(surface["influences"]).reshape(len(points), -1)
    weights = np.array(surface["weights"]).reshape(influences.shape)
    groups = {}
    for v, (indices, row) in enumerate(zip(influences, weights)):
        for i, weight in zip(indices, row / row.sum()):
            if weight <= 0:
                continue
            name = data["bones"][i]
            if name not in groups:
                if name not in arm.data.bones:
                    raise ValueError("Missing rest bone " + name)
                groups[name] = obj.vertex_groups.new(name=name)
            groups[name].add([v], weight, "REPLACE")
    add_material(mesh, data["textures"])
    bpy.ops.export_scene.fbx(filepath=str(path), object_types={"ARMATURE", "MESH"}, add_leaf_bones=False,
                             bake_anim=False, path_mode="COPY", embed_textures=True)


if __name__ == "__main__":
    rig, fit, output, *pieces = sys.argv[sys.argv.index("--") + 1:]
    bones = json.loads(Path(rig).read_text())["bones"]
    directory = Path(output).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    for piece in pieces:
        export_piece(directory / (piece + ".fbx"), json.loads((Path(fit) / (piece + ".json")).read_text()), bones)
