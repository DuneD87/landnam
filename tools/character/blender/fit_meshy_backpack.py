"""Makes a backpack from a Meshy model: decimated, turned into the game's
backpack space, sized, and without its straps, which the game's bake
(tools/items/bake_meshy_backpack.gd) leads over the shoulders instead.

    blender -b --factory-startup --python tools/character/blender/fit_meshy_backpack.py -- \\
        <backpacks.json> <source dir> <output dir> [backpack id ...]

The space is the one BackEquipment places a backpack in, as the hide
backpack (scripts/items/hide_backpack_visual.gd) is made: metres, Y up, +Z
towards the wearer's back, the origin about the middle of the pack, its face
against the back INNER_FACE in front of the origin. Meshy makes a backpack
standing, its straps hanging off its back as on a peg; worn they would go
through the wearer, so they are cut away (cut_straps()): what stands off
its back, hangs under it or out to its sides. The bake puts on straps that
go round the shoulders, as the hide backpack's do, textured with a patch of
the cut straps' own leather ("strap_uv").

Each entry of backpacks.json:
  model      path under the source dir (Meshy's maps next to it).
  decimate   share of its faces kept.
  height     metres from the bottom of the pack to its top (the straps
             left out).
  frame      {"front": axis the pack's face away from the wearer looks
             along, "up": its up}, axes like "-y"; Meshy's default
             {"front": "-y", "up": "+z"}.

Writes <id>.json (positions, normals, uvs, indices and the maps, as
fit_meshy_armor.py does) and <id>_preview_*.png; bake them with
tools/items/bake_meshy_backpack.gd.
"""
import json
import os
import sys

import bmesh
import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fit_meshy_armor import coords, decimate, import_model, preview, set_coords, textures

## Where the pack's face against the back is (+Z, m) and how high its top is
## over the origin, as the hide backpack's.
INNER_FACE = 0.11
TOP = 0.2
## What of the model is strap and is cut away (cut_straps()): what stands
## STRAP_OFF (m) off the pack's back face (the arcs of the straps), and from
## there whatever is joined to it through strap, which is long and narrow:
## within STRAP_RADIUS of each point, the second extent of the points round
## it is under STRAP_NARROW of the first (a flap or a panel is as wide as it
## is long).
STRAP_OFF = 0.03
STRAP_RADIUS = 0.04
STRAP_NARROW = 0.3
## And what is left of them over the pack's top or under its bottom, further
## than STRAP_MARGIN (m) past most of its area, away from the middle (a
## handle stays).
STRAP_MARGIN = 0.015
HANDLE = 0.05
## Pieces left loose by the cut with fewer than this share of its points.
LOOSE = 0.01

AXES = {"x": 0, "y": 1, "z": 2}


def axis(name):
    v = np.zeros(3)
    v[AXES[name[-1]]] = -1.0 if name.startswith("-") else 1.0
    return v


def to_pack(p, frame):
    """Model axes to the pack's: X to the wearer's left... any handed way
    round as long as it is a rotation; Y up; +Z towards the wearer."""
    up = axis(frame.get("up", "+z"))
    toward = -axis(frame.get("front", "-y"))
    side = np.cross(up, toward)
    return p @ np.stack([side, up, toward], axis=1)


def inner_face(obj, frame):
    """The pack's face against the back, along +Z: where most of the area
    facing the wearer is (the straps are thin), a little past its middle
    as the panel bulges."""
    mesh = obj.data
    n = len(mesh.polygons)
    centres, normals, areas = np.zeros(n * 3), np.zeros(n * 3), np.zeros(n)
    mesh.polygons.foreach_get("center", centres)
    mesh.polygons.foreach_get("normal", normals)
    mesh.polygons.foreach_get("area", areas)
    centres = to_pack(centres.reshape(-1, 3), frame)
    normals = to_pack(normals.reshape(-1, 3), frame)
    facing = normals[:, 2] > 0.7
    z, w = centres[facing, 2], areas[facing]
    order = np.argsort(z)
    cumulative = np.cumsum(w[order]) / w.sum()
    return z[order][np.searchsorted(cumulative, 0.7)]


def narrow(p):
    """Per point, whether the points round it lie along a line (a strap)."""
    from mathutils import Vector
    from mathutils.kdtree import KDTree
    tree = KDTree(len(p))
    for i, q in enumerate(p):
        tree.insert(Vector(q), i)
    tree.balance()
    result = np.zeros(len(p), dtype=bool)
    for i, q in enumerate(p):
        found = [j for _, j, _ in tree.find_range(Vector(q), STRAP_RADIUS)]
        if len(found) < 5:
            result[i] = True
            continue
        spread = np.sort(np.linalg.eigvalsh(np.cov(p[found].T)))[::-1]
        result[i] = spread[1] < STRAP_NARROW * spread[0]
    return result


def cut_straps(obj, face):
    """Deletes the straps (see STRAP_OFF); returns a patch of their leather
    in the texture (u0, v0, u1, v1, in the exported UVs): the one face of
    them nearest the middle of all of them there, so it is on one of them."""
    along = narrow(coords(obj))
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    mesh.faces.ensure_lookup_table()
    uv = mesh.loops.layers.uv.active
    strap = {f.index for f in mesh.faces if f.calc_center_median().z > face + STRAP_OFF}
    pending = list(strap)
    while pending:
        f = mesh.faces[pending.pop()]
        for edge in f.edges:
            for other in edge.link_faces:
                if other.index not in strap and sum(along[v.index] for v in other.verts) * 2 > len(other.verts):
                    strap.add(other.index)
                    pending.append(other.index)
    # What is left of them over its top (away from a handle) and under its
    # bottom, as most of its area is high and low.
    rest = [f for f in mesh.faces if f.index not in strap]
    heights = np.array([f.calc_center_median().y for f in rest])
    areas = np.array([f.calc_area() for f in rest])
    order = np.argsort(heights)
    cumulative = np.cumsum(areas[order]) / areas.sum()
    low, high = heights[order][np.searchsorted(cumulative, [0.02, 0.97])]
    for f in rest:
        c = f.calc_center_median()
        if c.y < low - STRAP_MARGIN or (c.y > high + STRAP_MARGIN and abs(c.x) > HANDLE):
            strap.add(f.index)
    cut = [mesh.faces[i] for i in sorted(strap)]
    uvs = np.array([[np.mean([l[uv].uv[k] for l in f.loops]) for k in (0, 1)] for f in cut])
    middle = np.median(uvs, axis=0)
    nearest = cut[int(np.argmin(np.linalg.norm(uvs - middle, axis=1)))]
    corners = np.array([[l[uv].uv[0], 1.0 - l[uv].uv[1]] for l in nearest.loops])
    patch = np.concatenate([corners.min(axis=0), corners.max(axis=0)]).round(6).tolist()
    bmesh.ops.delete(mesh, geom=cut, context="FACES")
    # And the bits of them the cut left loose.
    islands, seen = [], set()
    for v in mesh.verts:
        if v.index in seen or not v.link_faces:
            continue
        island, pending = [], [v]
        seen.add(v.index)
        while pending:
            a = pending.pop()
            island.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    pending.append(b)
        islands.append(island)
    loose = [v for v in mesh.verts if not v.link_faces]
    loose += [v for island in islands if len(island) < LOOSE * len(mesh.verts) for v in island]
    bmesh.ops.delete(mesh, geom=loose, context="VERTS")
    mesh.to_mesh(obj.data)
    mesh.free()
    obj.data.update()
    return patch, len(cut)


def fit(backpack_id, entry, source_dir, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    model = os.path.join(source_dir, entry["model"])
    obj = import_model(model)
    maps = textures(model)
    if entry.get("decimate"):
        decimate(obj, entry["decimate"])
    frame = entry.get("frame", {})
    p = to_pack(coords(obj), frame)
    if np.linalg.det(to_pack(np.eye(3), entry.get("frame", {}))) < 0:
        raise ValueError(backpack_id + ": its frame is a mirror")
    face = inner_face(obj, frame)
    core = p[p[:, 2] <= face]
    low, high = np.percentile(core[:, 1], [2, 98])
    left, right = np.percentile(core[:, 0], [1, 99])
    scale = entry["height"] / (high - low)
    shift = np.array([(left + right) * 0.5 * scale, high * scale - TOP, face * scale - INNER_FACE])
    p = p * scale - shift
    set_coords(obj, p)
    patch, cut = cut_straps(obj, INNER_FACE)
    # Sized again without them, which stood over its top.
    p = coords(obj)
    sides = p[np.abs(p[:, 0]) > HANDLE]
    low, high = np.percentile(p[:, 1], 0.5), np.percentile(sides[:, 1], 99.5)
    p = (p - np.array([0.0, high, INNER_FACE])) * (entry["height"] / (high - low)) + np.array([0.0, TOP, INNER_FACE])
    set_coords(obj, p)
    export(obj, maps, os.path.join(out_dir, backpack_id + ".json"), patch, TOP - entry["height"])
    print("%s: %d vertices (%d strap faces cut); %s..%s" % (backpack_id, len(p), cut, p.min(axis=0).round(3),
                                                           p.max(axis=0).round(3)))
    # Previewed in Blender's axes (Z up, the pack's face away from the wearer to -Y).
    set_coords(obj, p[:, [0, 2, 1]] * np.array([-1.0, 1.0, 1.0]))
    preview(obj, os.path.join(out_dir, backpack_id + "_preview.png"))


def export(obj, maps, path, strap_uv, bottom):
    """Its one surface, vertices split where the UVs are, Godot's winding;
    the patch of leather for its straps and how low it hangs."""
    mesh = obj.data
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers.active.data
    p = coords(obj)
    normals = np.zeros(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("normal", normals)
    normals = normals.reshape(-1, 3)
    keys, out_index, out_uv, indices = {}, [], [], []
    for tri in mesh.loop_triangles:
        corners = []
        for loop in tri.loops:
            v = mesh.loops[loop].vertex_index
            u = uv[loop].uv
            key = (v, round(u[0], 5), round(u[1], 5))
            if key not in keys:
                keys[key] = len(out_index)
                out_index.append(v)
                out_uv.append((u[0], 1.0 - u[1]))
            corners.append(keys[key])
        indices.extend([corners[0], corners[2], corners[1]])
    out_index = np.array(out_index)
    with open(path, "w") as f:
        json.dump({"textures": maps, "strap_uv": strap_uv, "bottom": round(float(bottom), 4), "positions": p[out_index].round(6).ravel().tolist(),
                   "normals": normals[out_index].round(5).ravel().tolist(),
                   "uvs": np.array(out_uv).round(6).ravel().tolist(), "indices": indices}, f)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    config, source_dir, out_dir = args[:3]
    only = args[3:]
    with open(config) as f:
        entries = json.load(f)
    os.makedirs(out_dir, exist_ok=True)
    for backpack_id, entry in entries.items():
        if not only or backpack_id in only:
            fit(backpack_id, entry, source_dir, out_dir)


if __name__ == "__main__":
    main()
