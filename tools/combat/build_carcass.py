"""La canal de un animal despiezado (Carcass), para todas las especies: un esqueleto de caballo
tumbado panza arriba, sin cabeza, sin cola y sin las patas de abajo, con la carne modelada sobre
sus huesos (el lomo, los cuartos, las paletillas y una pared de músculo entre las costillas, abierta
por el vientre), las texturas horneadas y exportado a models/animals/carcass/carcass.glb.

El esqueleto es "Lowpoly Horse Skeleton (Rigged)", de Azazel750
(https://sketchfab.com/3d-models/lowpoly-horse-skeleton-rigged-0a35814ed7e34c05875081ed12266d35),
CC-BY 4.0. Se descarga de Sketchfab (glTF) y se pasa su scene.gltf:

    blender -b --factory-startup -P tools/combat/build_carcass.py -- \\
        ~/Downloads/lowpoly_horse_skeleton_rigged/scene.gltf [--preview DIR]

Con --preview deja renders de cada paso en DIR (y el .blend).

El modelo, de pie, va con Z arriba, el cuello hacia +Y y los lados en X. La canal sale a lo largo
de -Y (el cuello delante: +Z en Godot), panza arriba, con el suelo en z = 0 y el origen bajo el
centro del tronco.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SOURCE = ARGS[0] if ARGS else os.path.expanduser("~/Downloads/lowpoly_horse_skeleton_rigged/scene.gltf")
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else ""
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTPUT = os.path.join(ROOT, "models/animals/carcass/carcass.glb")

# Lo que se va con la piel: la cabeza, las patas por debajo del codo y del corvejón.
DROP_PARTS = ("skull", "jaw", "radius", "cannon", "pastern", "pedal")
# De la columna (Object_7), los huesos del cuello (menos el último, que queda de muñón) y de la cola.
DROP_GROUPS = ("atlas_", "axis_", "v1_", "v2_", "v3_", "t1_", "t2_", "t3_", "t4_", "t5_")
# Las patas, abiertas: cuánto se separan del cuerpo y cuánto se doblan (grados).
HIND_SPREAD = 65.0
HIND_FOLD = 35.0
KNEE_FOLD = 55.0
FORE_SPREAD = 55.0
FORE_FOLD = -25.0


def load_parts():
    """Las piezas del esqueleto, de pie y en coordenadas del mundo: {nombre: Mesh}. La columna con
    las costillas (Object_7, con huesos) se reparte en 'spine' y 'ribs' por su hueso dominante."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    dg = bpy.context.evaluated_depsgraph_get()
    parts = {}
    for ob in list(bpy.context.scene.objects):
        if ob.type != "MESH" or ob.name == "Icosphere":
            continue
        name = ob.name.replace("_Skeleton_0", "").replace("_teeth_0", "_teeth")
        if name.startswith(DROP_PARTS) or "teeth" in name:
            continue
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(ob.matrix_world)
        if ob.name == "Object_7":
            groups = {g.index: g.name for g in ob.vertex_groups}
            parts.update(split_spine(me, groups))
        else:
            parts[name] = me
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    return parts


def split_spine(me, groups):
    """La columna en 'spine' (vértebras, sin cuello ni cola) y 'ribs' (costillas)."""
    kind = []
    for v in me.vertices:
        name = groups[max(v.groups, key=lambda g: g.weight).group] if v.groups else ""
        if name.startswith(DROP_GROUPS):
            kind.append(None)
        elif name.startswith(("rib", "rb1", "rb2")):
            kind.append("ribs")
        else:
            kind.append("spine")
    out = {}
    for part in ("spine", "ribs"):
        out[part] = submesh(me, [k == part for k in kind], part)
    return out


def submesh(me, keep, name):
    """Una malla con las caras de [me] cuyos vértices están todos en [keep]."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    drop = [v for v in bm.verts if not keep[v.index]]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    out = bpy.data.meshes.new(name)
    bm.to_mesh(out)
    bm.free()
    for i, mat in enumerate(me.materials):
        out.materials.append(mat)
    return out


def bounds(meshes):
    pts = [v.co for me in meshes for v in me.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def top_point(me, share=0.12):
    """La articulación de arriba de un hueso de la pata: la media de su parte más alta."""
    zs = sorted(v.co.z for v in me.vertices)
    cut = zs[int(len(zs) * (1.0 - share))]
    pts = [v.co for v in me.vertices if v.co.z >= cut]
    return sum(pts, Vector()) / len(pts)


def rotate_about(meshes, pivot, axis, degrees):
    m = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(degrees), 4, axis) @ Matrix.Translation(-pivot)
    for me in meshes:
        me.transform(m)


def pose(parts):
    """Abre las patas (de pie todavía) y lo tumba panza arriba, con el cuello hacia -Y."""
    for side in (".001", ""):
        # Las traseras: el fémur y la tibia, desde la cadera; la tibia, doblada por la rodilla.
        femur = parts["femur" + side]
        tibia = parts["tibia" + side]
        hip = top_point(femur)
        sign = 1.0 if hip.x > 0.0 else -1.0
        knee = top_point(tibia)
        rotate_about([tibia], knee, Vector((1, 0, 0)), -KNEE_FOLD)
        rotate_about([femur, tibia], hip, Vector((1, 0, 0)), HIND_FOLD)
        rotate_about([femur, tibia], hip, Vector((0, 1, 0)), HIND_SPREAD * sign)
    for side in (".001", ""):
        humerus = parts["humerus" + side]
        shoulder = top_point(humerus)
        sign = 1.0 if shoulder.x > 0.0 else -1.0
        rotate_about([humerus], shoulder, Vector((1, 0, 0)), FORE_FOLD)
        rotate_about([humerus], shoulder, Vector((0, 1, 0)), FORE_SPREAD * sign)
    # Panza arriba y el cuello hacia -Y: media vuelta alrededor de Z y otra alrededor de Y.
    flip = Matrix.Rotation(math.pi, 4, "Y") @ Matrix.Rotation(math.pi, 4, "Z")
    for me in parts.values():
        me.transform(flip)
    lo, hi = bounds(parts.values())
    spine_lo, spine_hi = bounds([parts["spine"], parts["ribs"]])
    center = Vector(((spine_lo.x + spine_hi.x) / 2, (spine_lo.y + spine_hi.y) / 2, lo.z))
    for me in parts.values():
        me.transform(Matrix.Translation(-center))


# La carne: un campo de distancias a los huesos (OpenVDB), cada uno con su grosor, unidos con un
# mínimo suave y convertidos en malla. Medidas en unidades del modelo (de pie mide unos 7,9 de alto).
VOXEL = 0.05
BAND = 16.0
BLEND = 0.12
# Grosor de la carne sobre cada hueso: (desde la articulación de arriba, hasta la otra punta).
MEAT = {
    "spine": (0.3, 0.3),
    "pelvis": (0.24, 0.24),
    "scapula": (0.16, 0.16),
    "humerus": (0.26, 0.06),
    "femur": (0.28, 0.16),
    "tibia": (0.2, -0.06),
    "ribs": (0.16, 0.16),
}
# La pared se aparta de las costillas hacia fuera (de lado): por dentro asoma el hueso.
RIB_SHIFT = 0.19
# La pared de las costillas llega a esta parte de su alto: por encima asoman las puntas.
RIM = 0.72
# Por delante, el cuello se corta aquí (unidades por detrás de la punta de su última vértebra).
NECK_CUT = 0.18
# Bultos de los músculos: (tamaño de celda, cuánto).
LUMPS = ((0.45, 0.05), (0.15, 0.02))


def mesh_arrays(me):
    import numpy as np
    me.calc_loop_triangles()
    pts = np.array([v.co[:] for v in me.vertices], dtype=np.float32)
    tris = np.array([t.vertices[:] for t in me.loop_triangles], dtype=np.uint32)
    return pts, tris


def bone_axis(me, center):
    """Los extremos de un hueso largo a lo largo de su eje principal: (el más cercano a [center],
    el otro)."""
    import numpy as np
    pts = np.array([v.co[:] for v in me.vertices])
    mean = pts.mean(axis=0)
    _, _, vt = np.linalg.svd(pts - mean, full_matrices=False)
    axis = vt[0]
    proj = (pts - mean) @ axis
    a = mean + axis * proj.min()
    b = mean + axis * proj.max()
    c = np.array(center[:])
    return (a, b) if np.linalg.norm(a - c) < np.linalg.norm(b - c) else (b, a)


def value_noise(shape, cell, seed):
    """Ruido suave (0-1) de celda [cell] vóxeles sobre una rejilla de [shape]."""
    import numpy as np
    rng = np.random.default_rng(seed)
    coarse = rng.random([int(math.ceil(n / cell)) + 2 for n in shape])
    out = coarse
    for axis, n in enumerate(shape):
        x = np.arange(n) / cell
        i = np.floor(x).astype(int)
        t = x - i
        t = t * t * (3.0 - 2.0 * t)
        a = np.take(out, i, axis=axis)
        b = np.take(out, i + 1, axis=axis)
        shape_t = [1] * out.ndim
        shape_t[axis] = n
        t = t.reshape(shape_t)
        out = a * (1.0 - t) + b * t
    return out


def smin(a, b, k):
    import numpy as np
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def meat(parts):
    """La malla de la carne sobre los huesos de [parts] (ya tumbados)."""
    import numpy as np
    import openvdb as vdb
    lo, hi = bounds(parts.values())
    lo -= Vector((1.0, 1.0, 1.0))
    hi += Vector((1.0, 1.0, 1.0))
    i0 = [int(math.floor(c / VOXEL)) for c in lo]
    dims = [int(math.ceil((h - l) / VOXEL)) + 1 for l, h in zip(lo, hi)]
    xform = vdb.createLinearTransform(voxelSize=VOXEL)
    axes = [(np.arange(n) + o) * VOXEL for n, o in zip(dims, i0)]
    X, Y, Z = np.meshgrid(*axes, indexing="ij")
    P = np.stack([X, Y, Z], axis=-1)
    trunk_lo, trunk_hi = bounds([parts["spine"], parts["ribs"]])
    trunk = (trunk_lo + trunk_hi) / 2
    field = np.full(dims, 10.0, dtype=np.float32)
    for name, me in parts.items():
        kind = name.split(".")[0]
        if kind not in MEAT:
            continue
        pts, tris = mesh_arrays(me)
        if kind == "ribs":
            pts[:, 0] += np.sign(pts[:, 0]) * RIB_SHIFT
        grid = vdb.FloatGrid.createLevelSetFromPolygons(pts, triangles=tris, transform=xform, halfWidth=BAND)
        dist = np.empty(dims, dtype=np.float32)
        grid.copyToArray(dist, ijk=tuple(i0))
        dist = np.abs(dist)
        r0, r1 = MEAT[kind]
        if r0 == r1:
            radius = r0
        else:
            a, b = bone_axis(me, trunk)
            t = np.clip(((P - a) @ (b - a)) / np.dot(b - a, b - a), 0.0, 1.0)
            radius = r0 + (r1 - r0) * t
        part = dist - radius
        if kind == "ribs":
            part = np.maximum(part, Z - rim_height(me, Y))
        field = smin(field, part.astype(np.float32), BLEND)
        print("MEAT", name, round(float(part.min()), 3))
    # El cuello, cortado a lo ancho.
    neck = min(v.co.y for v in parts["spine"].vertices) + NECK_CUT
    field = np.maximum(field, neck - Y)
    for size, amount in LUMPS:
        field += ((value_noise(dims, size / VOXEL, int(size * 1000)) - 0.5) * 2.0 * amount).astype(np.float32)
    grid = vdb.FloatGrid()
    grid.transform = xform
    grid.copyFromArray(field.astype(np.float32), ijk=tuple(i0))
    points, triangles, quads = grid.convertToPolygons(isovalue=0.0, adaptivity=0.1)
    faces = [tuple(int(i) for i in f) for f in triangles] + [tuple(int(i) for i in f) for f in quads]
    me = bpy.data.meshes.new("meat")
    me.from_pydata([tuple(p) for p in points.tolist()], [], faces)
    me.update()
    # Las caras, hacia fuera (volumen positivo).
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    if bm.calc_volume(signed=True) < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(me)
    bm.free()
    print("MEAT faces", len(me.polygons))
    return me


def rim_height(ribs, Y):
    """La altura (z) del borde de la pared de carne a lo largo de Y: RIM del alto de las costillas
    sobre su punto más bajo, suavizado."""
    import numpy as np
    pts = np.array([v.co[:] for v in ribs.vertices])
    lo_z = pts[:, 2].min()
    edges = np.linspace(pts[:, 1].min() - 0.5, pts[:, 1].max() + 0.5, 24)
    tops = []
    for a, b in zip(edges[:-1], edges[1:]):
        sel = pts[(pts[:, 1] >= a) & (pts[:, 1] < b)]
        tops.append(sel[:, 2].max() if len(sel) else lo_z)
    centers = (edges[:-1] + edges[1:]) / 2
    tops = np.convolve(np.pad(tops, 2, mode="edge"), np.ones(5) / 5, mode="valid")
    return np.interp(Y, centers, lo_z + (tops - lo_z) * RIM)


# Texturas horneadas (Cycles): la carne con fibras, vetas de grasa y fascia, coágulos en las
# hondonadas y hueso donde roza las costillas; los huesos, con su textura y sangre.
TEXTURE_SIZE = 2048
BAKE_SAMPLES = 24
# Triángulos de la carne, al final.
MEAT_TRIANGLES = 14000
# Unidades del modelo a metros: un caballo de 1,6 m a la cruz.
TO_METERS = 1.6 / 5.9
# Lo que se hunde en el suelo (m).
SINK = 0.03


def proximity(me, others, reach, name):
    """En cada vértice de [me], lo cerca que está de las mallas [others] (1 tocándolas, 0 a [reach]
    o más), como atributo de color [name]."""
    from mathutils.bvhtree import BVHTree
    trees = [BVHTree.FromPolygons([v.co for v in o.vertices], [p.vertices[:] for p in o.polygons]) for o in others]
    attr = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        best = reach
        for tree in trees:
            hit = tree.find_nearest(v.co, reach)
            if hit[0] is not None:
                best = min(best, hit[3])
        f = 1.0 - best / reach
        attr.data[i].color = (f, f, f, 1.0)


def drop_hidden(me, meat_me, margin=0.03):
    """Quita de [me] las caras metidas del todo dentro de la carne."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons([v.co for v in meat_me.vertices], [p.vertices[:] for p in meat_me.polygons])
    inside = []
    for v in me.vertices:
        loc, normal, _, dist = tree.find_nearest(v.co)
        inside.append(loc is not None and (v.co - loc).dot(normal) < 0.0 and dist > margin)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    gone = [f for f in bm.faces if all(inside[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(me)
    bm.free()


def nodes_for(mat):
    mat.use_nodes = True
    tree = mat.node_tree
    for n in list(tree.nodes):
        tree.nodes.remove(n)
    return tree, tree.nodes, tree.links


def ramp(nodes, stops):
    node = nodes.new("ShaderNodeValToRGB")
    els = node.color_ramp.elements
    while len(els) > len(stops):
        els.remove(els[-1])
    while len(els) < len(stops):
        els.new(0.5)
    for el, (pos, color) in zip(els, stops):
        el.position = pos
        el.color = color
    return node


def mix(nodes, links, a, b, fac=1.0, blend="MIX"):
    """[a] y [b] (colores o salidas) mezclados por [fac] (número o salida)."""
    node = nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    node.blend_type = blend
    for socket, value in ((node.inputs["Factor"], fac), (node.inputs[6], a), (node.inputs[7], b)):
        if isinstance(value, bpy.types.NodeSocket):
            links.new(value, socket)
        else:
            socket.default_value = value
    return node.outputs[2]


def meat_material():
    mat = bpy.data.materials.new("Meat")
    tree, nodes, links = nodes_for(mat)
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs[0], out.inputs[0])
    coord = nodes.new("ShaderNodeTexCoord").outputs["Object"]
    # El músculo: granate apagado a manchas, de casi negro a rojo oscuro (la canal lleva un rato al
    # aire, no es carne recién cortada), y a parches más seco y pardo.
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 6.0
    links.new(coord, noise.inputs["Vector"])
    base = ramp(nodes, [(0.3, (0.03, 0.006, 0.006, 1)), (0.5, (0.075, 0.015, 0.013, 1)),
        (0.72, (0.13, 0.026, 0.022, 1))])
    links.new(noise.outputs["Fac"], base.inputs[0])
    dry_noise = nodes.new("ShaderNodeTexNoise")
    dry_noise.inputs["Scale"].default_value = 0.9
    dry_noise.inputs["Detail"].default_value = 3.0
    links.new(coord, dry_noise.inputs["Vector"])
    dry = ramp(nodes, [(0.42, (0, 0, 0, 1)), (0.66, (0.7, 0.7, 0.7, 1))])
    links.new(dry_noise.outputs["Fac"], dry.inputs[0])
    color = mix(nodes, links, base.outputs[0], (0.06, 0.022, 0.015, 1), dry.outputs[0])
    # Las fibras: estrías finas y torcidas, apenas más oscuras.
    wave = nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 9.0
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 3.0
    wave.inputs["Detail Scale"].default_value = 1.5
    links.new(coord, wave.inputs["Vector"])
    fibers = ramp(nodes, [(0.0, (0.82, 0.82, 0.82, 1)), (1.0, (1.0, 1.0, 1.0, 1))])
    links.new(wave.outputs["Fac"], fibers.inputs[0])
    color = mix(nodes, links, color, fibers.outputs[0], 1.0, "MULTIPLY")
    # La fascia: un velo plateado a parches.
    veil_noise = nodes.new("ShaderNodeTexNoise")
    veil_noise.inputs["Scale"].default_value = 1.6
    veil_noise.inputs["Detail"].default_value = 4.0
    links.new(coord, veil_noise.inputs["Vector"])
    veil = ramp(nodes, [(0.6, (0, 0, 0, 1)), (0.72, (0.2, 0.2, 0.2, 1))])
    links.new(veil_noise.outputs["Fac"], veil.inputs[0])
    color = mix(nodes, links, color, (0.22, 0.17, 0.18, 1), veil.outputs[0])
    # La grasa: vetas finas y onduladas (las curvas de nivel de un ruido), solo en algunos sitios.
    vein_noise = nodes.new("ShaderNodeTexNoise")
    vein_noise.inputs["Scale"].default_value = 3.0
    vein_noise.inputs["Detail"].default_value = 2.0
    vein_noise.inputs["Distortion"].default_value = 0.6
    links.new(coord, vein_noise.inputs["Vector"])
    veins = ramp(nodes, [(0.47, (0, 0, 0, 1)), (0.5, (1, 1, 1, 1)), (0.53, (0, 0, 0, 1))])
    links.new(vein_noise.outputs["Fac"], veins.inputs[0])
    patches = nodes.new("ShaderNodeTexNoise")
    patches.inputs["Scale"].default_value = 1.1
    links.new(coord, patches.inputs["Vector"])
    patch = ramp(nodes, [(0.55, (0, 0, 0, 1)), (0.68, (1, 1, 1, 1))])
    links.new(patches.outputs["Fac"], patch.inputs[0])
    fat_fac = mix(nodes, links, veins.outputs[0], patch.outputs[0], 1.0, "MULTIPLY")
    color = mix(nodes, links, color, (0.5, 0.4, 0.28, 1), fat_fac)
    # Hueso donde roza las costillas.
    bone_attr = nodes.new("ShaderNodeVertexColor")
    bone_attr.layer_name = "Bone"
    bone_fac = ramp(nodes, [(0.5, (0, 0, 0, 1)), (0.75, (1, 1, 1, 1))])
    links.new(bone_attr.outputs["Color"], bone_fac.inputs[0])
    color = mix(nodes, links, color, (0.45, 0.33, 0.28, 1), bone_fac.outputs[0])
    # Coágulos y sangre oscura en las hondonadas.
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.5
    ao.samples = 16
    clot = ramp(nodes, [(0.35, (1, 1, 1, 1)), (0.8, (0, 0, 0, 1))])
    links.new(ao.outputs["AO"], clot.inputs[0])
    color = mix(nodes, links, color, (0.025, 0.002, 0.004, 1), clot.outputs[0])
    links.new(color, bsdf.inputs["Base Color"])
    # Mojado: poca rugosidad, más en la grasa, menos en los coágulos.
    rough = mix(nodes, links, (0.4, 0.4, 0.4, 1), (0.68, 0.68, 0.68, 1), dry.outputs[0])
    rough = mix(nodes, links, rough, (0.6, 0.6, 0.6, 1), fat_fac)
    rough = mix(nodes, links, rough, (0.18, 0.18, 0.18, 1), clot.outputs[0])
    links.new(rough, bsdf.inputs["Roughness"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.02
    links.new(wave.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def bone_material(source):
    """La textura de los huesos, manchada de sangre, más cerca de la carne."""
    mat = bpy.data.materials.new("Bone")
    tree, nodes, links = nodes_for(mat)
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs[0], out.inputs[0])
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = source
    links.new(nodes.new("ShaderNodeUVMap").outputs[0], tex.inputs[0])
    coord = nodes.new("ShaderNodeTexCoord").outputs["Object"]
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.0
    noise.inputs["Detail"].default_value = 5.0
    links.new(coord, noise.inputs["Vector"])
    near = nodes.new("ShaderNodeVertexColor")
    near.layer_name = "Meat"
    add = nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    links.new(noise.outputs["Fac"], add.inputs[0])
    links.new(near.outputs["Color"], add.inputs[1])
    blood = ramp(nodes, [(0.85, (0, 0, 0, 1)), (1.15, (0.85, 0.85, 0.85, 1))])
    links.new(add.outputs[0], blood.inputs[0])
    fresh = mix(nodes, links, tex.outputs["Color"], (0.82, 0.62, 0.55, 1), 1.0, "MULTIPLY")
    color = mix(nodes, links, fresh, (0.1, 0.008, 0.01, 1), blood.outputs[0])
    links.new(color, bsdf.inputs["Base Color"])
    rough = mix(nodes, links, (0.55, 0.55, 0.55, 1), (0.25, 0.25, 0.25, 1), blood.outputs[0])
    links.new(rough, bsdf.inputs["Roughness"])
    return mat


def bake(ob, mat, kinds, size):
    """Hornea [kinds] ('DIFFUSE', 'ROUGHNESS', 'NORMAL') de [mat] sobre [ob] (con UV) y deja en su
    lugar un material con las imágenes."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = BAKE_SAMPLES
    scene.render.bake.margin = 8
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    images = {}
    nodes = mat.node_tree.nodes
    for kind in kinds:
        # El color, a [size]; la rugosidad y el relieve, a la mitad.
        side = size if kind == "DIFFUSE" else size // 2
        img = bpy.data.images.new(f"{mat.name}_{kind.lower()}", side, side, alpha=False,
            is_data=kind != "DIFFUSE")
        node = nodes.new("ShaderNodeTexImage")
        node.image = img
        nodes.active = node
        if kind == "DIFFUSE":
            bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
        else:
            bpy.ops.object.bake(type=kind, use_clear=True)
        nodes.remove(node)
        images[kind] = img
        print("BAKED", mat.name, kind)
    baked = bpy.data.materials.new(mat.name)
    tree, bn, bl = nodes_for(baked)
    out = bn.new("ShaderNodeOutputMaterial")
    bsdf = bn.new("ShaderNodeBsdfPrincipled")
    bl.new(bsdf.outputs[0], out.inputs[0])
    for kind, img in images.items():
        tex = bn.new("ShaderNodeTexImage")
        tex.image = img
        if kind == "DIFFUSE":
            bl.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        elif kind == "ROUGHNESS":
            bl.new(tex.outputs["Color"], bsdf.inputs["Roughness"])
        else:
            nm = bn.new("ShaderNodeNormalMap")
            bl.new(tex.outputs["Color"], nm.inputs["Color"])
            bl.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    ob.data.materials.clear()
    ob.data.materials.append(baked)
    return baked


def link(name, me):
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def render(path, objects, view=(1.0, -0.6, 0.7), engine="BLENDER_WORKBENCH"):
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for ob in objects:
        for c in ob.bound_box:
            p = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    center = (lo + hi) / 2
    size = (hi - lo).length
    print("RENDER", os.path.basename(path), tuple(round(c, 2) for c in lo), tuple(round(c, 2) for c in hi))
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        scene.collection.objects.link(cam)
        sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
        sun.data.energy = 3.0
        sun.rotation_euler = (0.7, 0.2, 0.9)
        scene.collection.objects.link(sun)
    cam.location = center + Vector(view).normalized() * size * 1.25
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 40
    scene.camera = cam
    scene.render.engine = engine
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.25, 0.25, 0.27)
    if engine == "BLENDER_WORKBENCH":
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    parts = load_parts()
    pose(parts)
    meat_me = meat(parts)
    # Lo que queda dentro de la carne no se ve: fuera.
    bones_me = bpy.data.meshes.new("bones")
    import bmesh
    bm = bmesh.new()
    for me in parts.values():
        bm.from_mesh(me)
    bm.to_mesh(bones_me)
    bm.free()
    proximity(meat_me, [bones_me], 0.07, "Bone")
    drop_hidden(bones_me, meat_me)
    source = next(n.image for n in parts["spine"].materials[0].node_tree.nodes if n.type == "TEX_IMAGE")
    for p in list(parts.values()):
        bpy.data.meshes.remove(p)
    # Menos triángulos en la carne.
    flesh = link("Meat", meat_me)
    dec = flesh.modifiers.new("decimate", "DECIMATE")
    meat_me.calc_loop_triangles()
    dec.ratio = min(1.0, MEAT_TRIANGLES / max(1, len(meat_me.loop_triangles)))
    bpy.context.view_layer.objects.active = flesh
    bpy.ops.object.modifier_apply(modifier="decimate")
    for poly in flesh.data.polygons:
        poly.use_smooth = True
    bones = link("Bones", bones_me)
    for poly in bones.data.polygons:
        poly.use_smooth = True
    proximity(bones.data, [flesh.data], 0.25, "Meat")
    # UV de la carne.
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    flesh.select_set(True)
    bpy.context.view_layer.objects.active = flesh
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    bake(flesh, meat_material(), ("DIFFUSE", "ROUGHNESS", "NORMAL"), TEXTURE_SIZE)
    bake(bones, bone_material(source), ("DIFFUSE",), TEXTURE_SIZE // 2)
    # A metros, con el suelo bajo la carne (un poco hundida).
    lo, hi = bounds([flesh.data, bones.data])
    floor = min(v.co.z for v in flesh.data.vertices)
    for ob in (flesh, bones):
        ob.data.transform(Matrix.Scale(TO_METERS, 4) @ Matrix.Translation((0.0, 0.0, -floor)))
        ob.data.transform(Matrix.Translation((0.0, 0.0, -SINK)))
    lo, hi = bounds([flesh.data, bones.data])
    print("SIZE (m)", tuple(round(c, 3) for c in (hi - lo)), "lo", tuple(round(c, 3) for c in lo))
    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
        for name, view in (("3_baked", (1.0, -0.6, 0.7)), ("3_baked_top", (0.15, -0.3, 1.0)),
                ("3_baked_low", (1.0, 0.4, 0.3))):
            render(os.path.join(PREVIEW, name + ".png"), [flesh, bones], view=view, engine="CYCLES")
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(PREVIEW, "carcass.blend"))
    export([flesh, bones])


def export(objects):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = "Carcass"
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUTPUT, use_selection=True, export_format="GLB",
        export_attributes=False, export_vertex_color="NONE", export_image_format="JPEG", export_image_quality=90,
        export_yup=True, export_apply=True)
    print("EXPORTED", OUTPUT)


main()
