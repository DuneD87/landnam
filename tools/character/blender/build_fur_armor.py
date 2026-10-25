"""Builds the Stone Age fur garments on the player scan, as layered
clothing: the mantle (a wolf's pelt over the shoulders, on a hide jerkin
gathered by a belt, with a pouch), the loincloth (a fur skirt wrapped round
the hips over two long hide flaps and a leather loincloth), the mittens
(leather with a fur cuff) and the moccasins (leather, with a pelt wrapped
round each shin and bound with crossed thongs); and the heavy set for the
winter: the coat (caribou hides with the hair out, long sleeves, a ruff of
wolverine over the shoulders), the breeches (bearskin to under the knee),
the gauntlets (fur mittens with a long cuff) and the boots (a moccasin with
a fur leg to under the knee). Each set has three variants (*_SET: other
animals, with bone plates, antler lamellae, ivory beads or boar's tusks).
See docs/character_creation.md, "Prendas de pieles con pelo". Nothing is
imported: every piece is made here
on the scan's own skin. The output is what fit_meshy_armor.py writes
(tools/character/bake_meshy_armor.gd bakes it), with a material named on
every surface instead of a model's own maps.

    blender -b --factory-startup --python tools/character/blender/build_fur_armor.py -- \\
        <body.json> <output dir> [piece id ...]

<body.json> is written by tools/character/dump_skeleton.gd. Each piece gets
<id>.json and previews <id>_preview_<view>.png in the output dir.

How a piece is made:
 - The body is the scan remeshed into even cells (ENVELOPE_VOXEL), which also
   closes the gaps between toes. A pelt or a hide is a region of it, cut along
   a field (a scalar on the skin: what is positive goes), with the lobes and
   points of a pelt's edge, split into panels along more fields and inflated
   off the skin (smoothed and pushed out by turns, so it bridges hollows as
   hide does). What hangs (skirts, flaps) falls plumb from the most the body
   stands out above it; hide gathered by a belt blouses over it and falls in
   flutes under it.
 - A pelt is hide (the coat seen between the hair, "pelt"), its flesh side
   along its edges and the rim between them, and hair cards: locks combed
   down it, a short coat between them and locks hanging over its edges. Bare
   hide is "leather".
 - Belts, straps, thongs and stitches are strips and tubes along curves on it.
 - A mitten is the convex hull of the palm and the four fingers (a pouch)
   joined to the thumb and the cuff by remeshing. Mittens and moccasins are
   lined with the skin of the hand or the foot, so what bulges through them
   in a pose shows leather.
 - Shadows between the layers (ambient occlusion from the body and every
   part) darken the vertex colours; the cards take the pelt's under them.
 - Weights: fit_meshy_armor.skin(), as for the Meshy garments, from the skin
   under each point. The loincloth's skirt and flaps hang from the skirt's
   bones; its belt and the leather under it follow the hips.
 - UVs are in metres: every panel is unwrapped on its own (a tube is cut
   first) and turned so that +v (Godot) runs down its slope, the way the hair
   falls. The cards pick a lock of the atlas (render_fur_maps.py).
"""

import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit_meshy_armor as fit  # noqa: E402  (Body, skin weights, spaces)

if __name__ == "__main__":
    ARGS = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")]
    BODY_JSON, OUT_DIR = ARGS[:2]
    ONLY = set(ARGS[2:])

## Size of the cells the scan is remeshed into for each garment (m):
## coarse for the torso, finer for the feet; mittens are made without it.
ENVELOPE_VOXEL = {"mantle": 0.014, "loincloth": 0.016, "mittens": None, "moccasins": 0.013,
                  "coat": 0.017, "breeches": 0.013, "gauntlets": None, "boots": 0.013}
## Rounds of inflate(): smoothing, then pushing off the skin.
INFLATE_ROUNDS = 24
INFLATE_RATE = 0.5
## Leather of a pelt's flesh side, along its edges, this wide (m) and this
## far inside it.
FLESH_BAND = 0.06
FLESH_DEPTH = 0.004
LACE_SIDES = 6
## Seed of the lobes and the colour noise: the same garments every time.
SEED = 7

# Colours: linear multipliers of the hair (fur_common.gdshaderinc) or of the
# light leather map. Godot keeps vertex colours in 8 bits: at most 1.
WOLF = (0.282, 0.254, 0.218)
WOLF_STRIPE = (0.106, 0.0912, 0.0774)
TAWNY = (0.352, 0.254, 0.169)
CREAM = (0.45, 0.408, 0.345)
FLESH = (0.669, 0.607, 0.528)
BELT = (0.317, 0.238, 0.185)
SOLE = (0.396, 0.326, 0.264)
HIDE = (0.493, 0.422, 0.361)
SINEW = (0.704, 0.634, 0.528)
BONE = (1.0, 1.0, 1.0)


def smoothstep(e0, e1, x):
    return fit.smoothstep(e0, e1, x)


def normalized(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


def lobes(angle, spec):
    """A pelt's edge: for each (centre, width, depth) in `spec`, a rounded
    point `depth` long, `width` radians wide, at `centre` (radians, wrapped)."""
    out = np.zeros_like(angle)
    for centre, width, depth in spec:
        d = np.angle(np.exp(1j * (angle - centre)))
        out += depth * np.exp(-(d / width) ** 2 * 2.0)
    return out


def wobble(points, seed, scale, amount):
    """Smooth noise over space: a few waves in random directions."""
    rng = np.random.default_rng(seed)
    out = np.zeros(len(points))
    for k in range(6):
        direction = normalized(rng.normal(size=3))
        frequency = scale * (0.6 + 0.8 * rng.random()) * (1.0 + k * 0.5)
        out += np.sin(points @ direction * frequency * 2.0 * np.pi + rng.uniform(0, 2 * np.pi)) / (1.0 + k * 0.5)
    return out * amount / 2.2


# --- Meshes --------------------------------------------------------------------

class Mesh:
    """Triangles with per-vertex attributes (interpolated along cuts) and a
    label per triangle (its panel)."""

    def __init__(self, points, triangles, attrs=None, labels=None):
        self.points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
        self.triangles = np.asarray(triangles, dtype=np.int64).reshape(-1, 3)
        self.attrs = dict(attrs or {})
        self.labels = (np.zeros(len(self.triangles), dtype=np.int64) if labels is None
                       else np.asarray(labels, dtype=np.int64))

    def copy(self):
        return Mesh(self.points.copy(), self.triangles.copy(), {k: v.copy() for k, v in self.attrs.items()},
                    self.labels.copy())

    def cut(self, field, label=None, inside=None):
        """Cuts along field == 0 (a value per vertex). Without `label` what is
        positive goes; with it, the positive side of the triangles labelled
        one of `inside` (all, if None) gets `label`, sharing the new vertices."""
        f = np.where(np.abs(field) < 1e-9, 1e-9, np.asarray(field, dtype=np.float64))
        positive = f > 0.0
        tris = self.triangles
        active = np.ones(len(tris), bool) if inside is None else np.isin(self.labels, inside)
        count = positive[tris].sum(axis=1)
        mixed = active & (count > 0) & (count < 3)
        whole_positive = active & (count == 3)
        keep = ~mixed & ~(whole_positive & (label is None))
        out_tris = [tris[keep]]
        out_labels = [np.where(whole_positive[keep], label if label is not None else 0, self.labels[keep])]
        points = list(self.points)
        attrs = {k: list(v) for k, v in self.attrs.items()}
        cache = {}

        def cross(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                t = f[a] / (f[a] - f[b])
                cache[key] = len(points)
                points.append(self.points[a] + t * (self.points[b] - self.points[a]))
                for k, v in self.attrs.items():
                    attrs[k].append(v[a] + t * (v[b] - v[a]))
            return cache[key]
        extra_tris, extra_labels = [], []
        for k in np.flatnonzero(mixed):
            corners = tris[k]
            odd_positive = count[k] == 1
            odd = [i for i in range(3) if positive[corners[i]] == odd_positive][0]
            a, b, c = corners[odd], corners[(odd + 1) % 3], corners[(odd + 2) % 3]
            ab, ca = cross(a, b), cross(c, a)
            alone = [(a, ab, ca)]
            pair = [(ab, b, c), (ab, c, ca)]
            pos, neg = (alone, pair) if odd_positive else (pair, alone)
            for t in neg:
                extra_tris.append(t)
                extra_labels.append(self.labels[k])
            if label is not None:
                for t in pos:
                    extra_tris.append(t)
                    extra_labels.append(label)
        if extra_tris:
            out_tris.append(np.array(extra_tris, dtype=np.int64))
            out_labels.append(np.array(extra_labels, dtype=np.int64))
        self.points = np.array(points)
        self.attrs = {k: np.array(v) for k, v in attrs.items()}
        self.triangles = np.concatenate(out_tris)
        self.labels = np.concatenate(out_labels)
        self.compact()
        return self

    def compact(self):
        used = np.zeros(len(self.points), bool)
        used[self.triangles.ravel()] = True
        remap = np.cumsum(used) - 1
        self.points = self.points[used]
        self.attrs = {k: v[used] for k, v in self.attrs.items()}
        self.triangles = remap[self.triangles]
        return self

    def keep(self, tri_mask):
        self.triangles = self.triangles[tri_mask]
        self.labels = self.labels[tri_mask]
        return self.compact()

    def edges(self):
        e = np.sort(np.concatenate([self.triangles[:, [0, 1]], self.triangles[:, [1, 2]],
                                    self.triangles[:, [2, 0]]]), axis=1)
        return np.unique(e, axis=0)

    def neighbours(self):
        edges = self.edges()
        lists = [[] for _ in range(len(self.points))]
        for a, b in edges:
            lists[a].append(b)
            lists[b].append(a)
        return lists

    def boundary(self):
        """Boundary edges, oriented as their triangle has them."""
        directed = np.concatenate([self.triangles[:, [0, 1]], self.triangles[:, [1, 2]], self.triangles[:, [2, 0]]])
        key = np.sort(directed, axis=1)
        _, inverse, counts = np.unique(key, axis=0, return_inverse=True, return_counts=True)
        return directed[counts[inverse.ravel()] == 1]

    def loops(self):
        """Closed boundary loops, each a list of vertices in order."""
        nxt = {a: b for a, b in self.boundary()}
        loops = []
        seen = set()
        for start in nxt:
            if start in seen:
                continue
            loop = [start]
            seen.add(start)
            v = nxt[start]
            while v != start and v in nxt and v not in seen:
                loop.append(v)
                seen.add(v)
                v = nxt[v]
            if len(loop) > 2:
                loops.append(loop)
        return loops

    def seams(self):
        """Edges between triangles of different labels: (a, b, label one, label two)."""
        directed = np.concatenate([self.triangles[:, [0, 1]], self.triangles[:, [1, 2]], self.triangles[:, [2, 0]]])
        labels = np.tile(self.labels, 3)
        key = np.sort(directed, axis=1)
        order = np.lexsort((key[:, 1], key[:, 0]))
        key, labels = key[order], labels[order]
        same = (key[1:] == key[:-1]).all(axis=1)
        out = []
        for i in np.flatnonzero(same):
            if labels[i] != labels[i + 1]:
                out.append((key[i][0], key[i][1], labels[i], labels[i + 1]))
        return out

    def normals(self):
        p = self.points
        t = self.triangles
        face = np.cross(p[t[:, 1]] - p[t[:, 0]], p[t[:, 2]] - p[t[:, 0]])
        n = np.zeros_like(p)
        for i in range(3):
            np.add.at(n, t[:, i], face)
        return normalized(n)

    def smooth(self, rate, rounds, pinned=None):
        """Laplacian smoothing; a boundary vertex only moves along the boundary."""
        nb = self.neighbours()
        on_edge = np.zeros(len(self.points), bool)
        b = self.boundary()
        on_edge[b.ravel()] = True
        edge_nb = [[] for _ in range(len(self.points))]
        for a, c in b:
            edge_nb[a].append(c)
            edge_nb[c].append(a)
        lists = [edge_nb[i] if on_edge[i] else nb[i] for i in range(len(self.points))]
        idx = np.concatenate([np.array(l, dtype=np.int64) for l in lists])
        owner = np.repeat(np.arange(len(lists)), [len(l) for l in lists])
        degree = np.maximum(np.bincount(owner, minlength=len(lists)), 1)
        for _ in range(rounds):
            mean = np.zeros_like(self.points)
            np.add.at(mean, owner, self.points[idx])
            mean /= degree[:, None]
            step = rate * (mean - self.points)
            if pinned is not None:
                step[pinned] = 0.0
            self.points += step
        return self

    def merged(self, other):
        n = len(self.points)
        attrs = {k: np.concatenate([v, other.attrs[k]]) for k, v in self.attrs.items() if k in other.attrs}
        return Mesh(np.concatenate([self.points, other.points]), np.concatenate([self.triangles, other.triangles + n]),
                    attrs, np.concatenate([self.labels, other.labels]))


def welded(points, triangles, tolerance=1e-6):
    keys, inverse = np.unique(np.round(points / tolerance).astype(np.int64), axis=0, return_inverse=True)
    out = np.zeros((len(keys), 3))
    np.add.at(out, inverse.ravel(), points)
    out /= np.bincount(inverse.ravel())[:, None]
    tris = inverse.ravel()[triangles]
    good = (tris[:, 0] != tris[:, 1]) & (tris[:, 1] != tris[:, 2]) & (tris[:, 2] != tris[:, 0])
    return out, tris[good]


# --- The body ------------------------------------------------------------------

class Envelope:
    """The scan remeshed into even cells, with the skin's weights per vertex."""

    def __init__(self, body, voxel):
        self.body = body
        points, triangles = welded(body.points, body.triangles)
        mesh = bpy.data.meshes.new("envelope")
        mesh.from_pydata(points.tolist(), [], triangles.tolist())
        obj = bpy.data.objects.new("envelope", mesh)
        bpy.context.scene.collection.objects.link(obj)
        modifier = obj.modifiers.new("remesh", "REMESH")
        modifier.mode = "VOXEL"
        modifier.voxel_size = voxel
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.verts.ensure_lookup_table()
        self.points = np.array([v.co for v in bm.verts])
        self.triangles = np.array([[v.index for v in f.verts] for f in bm.faces], dtype=np.int64)
        bm.free()
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(mesh)
        # The skin's weights at the nearest point (a voxel away at most).
        self.weights = np.zeros((len(self.points), len(body.names)), dtype=np.float32)
        for i, p in enumerate(self.points):
            self.weights[i], _ = body.weights_at(p)
        print("envelope: %d vertices, %d triangles" % (len(self.points), len(self.triangles)))

    def mesh(self):
        return Mesh(self.points.copy(), self.triangles.copy(), {"weights": self.weights.copy()})


def limb_bones(body, side, *names):
    """The bones of one side whose names hold any of `names` ("Arm", "Hand")."""
    prefix = fit.BONE_PREFIX + side
    return [i for n, i in body.index.items() if n.startswith(prefix) and any(k in n[len(prefix):] for k in names)]


def on_limb(mesh, body, side, *names):
    """How much each vertex follows those bones (its weights' share)."""
    return mesh.attrs["weights"][:, limb_bones(body, side, *names)].sum(axis=1)


def inflate(mesh, body, clearance, rounds=INFLATE_ROUNDS, rate=INFLATE_RATE, start=None):
    """Off the skin by `clearance` (per vertex, m), smoothed by turns so it
    bridges the body's hollows as hide would. `start` (per vertex, m) is the
    first offset, along the normals."""
    if start is not None:
        mesh.points += mesh.normals() * start[:, None]
    for _ in range(rounds):
        mesh.smooth(rate, 2)
        push_off(mesh, body, clearance)
    return mesh


def push_off(mesh, body, clearance):
    for i, p in enumerate(mesh.points):
        location, normal, _ = body.nearest(p)
        depth = (p - location) @ normal
        if depth < clearance[i]:
            mesh.points[i] = p + normal * (clearance[i] - depth)


def distance_to(points, targets):
    """Distance from each point to the nearest of `targets`."""
    if len(targets) == 0:
        return np.full(len(points), np.inf)
    tree = KDTree(len(targets))
    for i, q in enumerate(targets):
        tree.insert(Vector(q), i)
    tree.balance()
    return np.array([tree.find(Vector(p))[2] for p in points])


def seam_lines(mesh, pairs):
    """The seams between `pairs` of labels as polylines (vertex chains)."""
    links = {}
    for a, b, la, lb in mesh.seams():
        if (la, lb) in pairs or (lb, la) in pairs:
            links.setdefault(a, []).append(b)
            links.setdefault(b, []).append(a)
    lines = []
    seen = set()
    ends = [v for v, l in links.items() if len(l) == 1] + list(links)
    for start in ends:
        if start in seen:
            continue
        line = [start]
        seen.add(start)
        while True:
            nxt = [v for v in links[line[-1]] if v not in seen]
            if not nxt:
                break
            line.append(nxt[0])
            seen.add(nxt[0])
        if len(line) > 1:
            lines.append(mesh.points[line])
    return lines


def resample(polyline, step, closed=False):
    p = np.asarray(polyline)
    if closed:
        p = np.concatenate([p, p[:1]])
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    n = max(int(round(s[-1] / step)), 2)
    at = np.linspace(0.0, s[-1], n + (0 if closed else 1), endpoint=not closed)
    return np.stack([np.interp(at, s, p[:, k]) for k in range(3)], axis=1)


def smooth_polyline(p, rounds, closed=False):
    p = p.copy()
    for _ in range(rounds):
        if closed:
            p = 0.5 * p + 0.25 * (np.roll(p, 1, axis=0) + np.roll(p, -1, axis=0))
        else:
            p[1:-1] = 0.5 * p[1:-1] + 0.25 * (p[:-2] + p[2:])
    return p


# --- Parts ---------------------------------------------------------------------

class Part:
    """Geometry for the output: vertices, triangles (Blender winding), UVs and
    colours per corner, a material, and whether it is unwrapped later (its
    labels are its islands)."""

    def __init__(self, material, points, triangles, normals=None, uvs=None, colors=None, labels=None, unwrap=False):
        self.material = material
        self.points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
        self.triangles = np.asarray(triangles, dtype=np.int64).reshape(-1, 3)
        self.normals = normals
        self.uvs = uvs
        self.colors = colors
        self.labels = labels if labels is not None else np.zeros(len(self.triangles), dtype=np.int64)
        self.unwrap = unwrap


def mesh_normals(points, triangles):
    return Mesh(points, triangles).normals()


def tube(curve, radius, sides=LACE_SIDES, closed=False, caps=True, twist=0.0):
    """A tube along `curve` (radius per point or one), parallel-transported
    frames; UVs: u along it (m), v round it (0..1)."""
    curve = np.asarray(curve, dtype=np.float64)
    n = len(curve)
    radius = np.broadcast_to(np.asarray(radius, dtype=np.float64), (n,))
    tangents = normalized(np.gradient(curve, axis=0)) if not closed else \
        normalized(np.roll(curve, -1, axis=0) - np.roll(curve, 1, axis=0))
    up = np.array([0.0, 0.0, 1.0]) if abs(tangents[0][2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    normal = normalized(np.cross(np.cross(tangents[0], up), tangents[0]))
    frames = []
    for i in range(n):
        if i:
            normal = normal - tangents[i] * (normal @ tangents[i])
            normal = normal / max(np.linalg.norm(normal), 1e-9)
        frames.append((normal, np.cross(tangents[i], normal)))
    points, normals, uvs = [], [], []
    length = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(curve, axis=0), axis=1))])
    for i in range(n):
        nrm, bi = frames[i]
        for k in range(sides + 1):
            a = 2.0 * np.pi * k / sides + twist * length[i]
            d = nrm * np.cos(a) + bi * np.sin(a)
            points.append(curve[i] + d * radius[i])
            normals.append(d)
            uvs.append((length[i], k / sides))
    rows = n + (1 if closed else 0)
    tris = []
    for i in range(rows - 1):
        i0, i1 = i % n, (i + 1) % n
        for k in range(sides):
            a, b = i0 * (sides + 1) + k, i0 * (sides + 1) + k + 1
            c, d = i1 * (sides + 1) + k + 1, i1 * (sides + 1) + k
            tris += [(a, b, c), (a, c, d)]
    points, normals, uvs = list(points), list(normals), list(uvs)
    if caps and not closed:
        for end, sign in ((0, -1.0), (n - 1, 1.0)):
            centre = len(points)
            points.append(curve[end])
            normals.append(tangents[end] * sign)
            uvs.append((length[end], 0.5))
            for k in range(sides):
                a, b = end * (sides + 1) + k, end * (sides + 1) + k + 1
                tris.append((centre, b, a) if sign < 0 else (centre, a, b))
    tris = np.array(tris, dtype=np.int64)
    uv = np.array(uvs)[tris]
    return np.array(points), tris, np.array(normals), uv


def tube_part(material, curve, radius, color, **kwargs):
    points, tris, normals, uvs = tube(curve, radius, **kwargs)
    colors = np.broadcast_to(np.array([*color, 1.0]), (len(tris), 3, 4)).copy()
    return Part(material, points, tris, normals, uvs, colors)


def strap(curve, normals, width, thickness, color, closed=False, material="leather"):
    """A flat strap lying on a surface: `curve` along it, `normals` the
    surface's (its flat side faces them). Flat faces, square edges; UVs in
    metres."""
    curve = np.asarray(curve)
    n = len(curve)
    t = normalized(np.roll(curve, -1, axis=0) - np.roll(curve, 1, axis=0)) if closed else \
        normalized(np.gradient(curve, axis=0))
    up = normalized(normals - t * np.sum(normals * t, axis=1, keepdims=True))
    side = np.cross(t, up)
    length = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(curve, axis=0), axis=1))])
    if closed:
        length = np.append(length, length[-1] + np.linalg.norm(curve[0] - curve[-1]))
    corner = [(-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)]
    face_out = [lambda i: -up[i], lambda i: side[i], lambda i: up[i], lambda i: -side[i]]
    span = [width, thickness, width, thickness]
    v_start = np.concatenate([[0.0], np.cumsum(span)])
    rows = n + 1 if closed else n
    points, normals_out, tris, uvs = [], [], [], []

    def at(i, k):
        a, h = corner[k % 4]
        return curve[i % n] + side[i % n] * width * a + up[i % n] * thickness * h
    for k in range(4):
        base = len(points)
        for i in range(rows):
            for e in range(2):
                points.append(at(i, k + e))
                normals_out.append(face_out[k](i % n))
        for i in range(rows - 1):
            a, b = base + i * 2, base + i * 2 + 1
            c, d = base + (i + 1) * 2 + 1, base + (i + 1) * 2
            u0, u1 = length[i], length[i + 1]
            v0, v1 = v_start[k], v_start[k + 1]
            tris += [(a, b, c), (a, c, d)]
            uvs += [[(u0, v0), (u0, v1), (u1, v1)], [(u0, v0), (u1, v1), (u1, v0)]]
    if not closed:
        for i, sign in ((0, -1.0), (n - 1, 1.0)):
            base = len(points)
            for k in range(4):
                points.append(at(i, k))
                normals_out.append(t[i] * sign)
            tris += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
            uvs += [[(0, 0), (width, 0), (width, thickness)], [(0, 0), (width, thickness), (0, thickness)]]
    points = np.array(points)
    normals_out = np.array(normals_out)
    tris = np.array(tris, dtype=np.int64)
    uvs = np.array(uvs, dtype=np.float64)
    # Each face towards its own normal.
    face = np.cross(points[tris[:, 1]] - points[tris[:, 0]], points[tris[:, 2]] - points[tris[:, 0]])
    flip = np.sum(face * normals_out[tris[:, 0]], axis=1) < 0
    tris[flip] = tris[flip][:, [0, 2, 1]]
    uvs[flip] = uvs[flip][:, [0, 2, 1]]
    colors = np.broadcast_to(np.array([*color, 1.0]), (len(tris), 3, 4)).copy()
    return Part(material, points, tris, normals_out, uvs, colors)


def ellipsoid(centre, axes, color, material="bone", rings=6, segments=10):
    """A small ellipsoid (beads, knots): `axes` its three half-axes as vectors."""
    points, tris = [], []
    for i in range(rings + 1):
        phi = np.pi * i / rings
        for k in range(segments + 1):
            theta = 2 * np.pi * k / segments
            d = np.array([np.sin(phi) * np.cos(theta), np.sin(phi) * np.sin(theta), np.cos(phi)])
            points.append(centre + axes[0] * d[0] + axes[1] * d[1] + axes[2] * d[2])
    for i in range(rings):
        for k in range(segments):
            a = i * (segments + 1) + k
            b, c, d = a + 1, a + segments + 2, a + segments + 1
            tris += [(a, c, b), (a, d, c)]
    tris = np.array(tris, dtype=np.int64)
    points = np.array(points)
    uv = np.stack([points[:, 0] + points[:, 1], points[:, 2]], axis=1)[tris]
    colors = np.broadcast_to(np.array([*color, 1.0]), (len(tris), 3, 4)).copy()
    return Part(material, points, tris, None, uv, colors)


# --- Pelts ---------------------------------------------------------------------

def pelt_parts(mesh, colors, flesh=FLESH_BAND, double=False, flesh_color=FLESH, bare=()):
    """A pelt from `mesh` (inflated, panels as labels): the hide with its
    hair (the coat under the cards, "pelt"; bare hide, "leather", for the
    panels labelled one of `bare`), its flesh side along its edges (all of it
    if `double`: it swings free) and the rim between them. `colors(points,
    labels)` gives its colour per corner."""
    normals = mesh.normals()
    parts = []
    col = colors(mesh.points[mesh.triangles].reshape(-1, 3), np.repeat(mesh.labels, 3)).reshape(-1, 3, 3)
    rgba = np.concatenate([col, np.ones(col.shape[:2] + (1,))], axis=-1)
    hairless = np.isin(mesh.labels, bare)
    for material, rows in (("pelt", ~hairless), ("leather", hairless)):
        if rows.any():
            parts.append(Part(material, mesh.points, mesh.triangles[rows], normals, None, rgba[rows],
                              mesh.labels[rows], unwrap=True))
    # The flesh side: under the hide along the edges (or all), facing in.
    loops = mesh.loops()
    edge_points = mesh.points[np.concatenate(loops)] if loops else np.zeros((0, 3))
    near = distance_to(mesh.points, edge_points)
    band = np.ones(len(mesh.triangles), bool) if double else (near[mesh.triangles].min(axis=1) < flesh)
    inner = mesh.points - normals * FLESH_DEPTH
    tris = mesh.triangles[band][:, [0, 2, 1]]
    if len(tris):
        flesh_rgba = np.broadcast_to(np.array([*flesh_color, 1.0]), (len(tris), 3, 4)).copy()
        parts.append(Part("leather", inner, tris, -normals, None, flesh_rgba, mesh.labels[band], unwrap=True))
    # The rim: each boundary edge to its copy underneath.
    rim_points, rim_tris, rim_uv = [], [], []
    for loop in loops:
        p = mesh.points[loop]
        q = inner[loop]
        length_along = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(np.vstack([p, p[:1]]), axis=0), axis=1))])
        base = len(rim_points)
        m = len(loop)
        rim_points.extend(p)
        rim_points.extend(q)
        for i in range(m):
            j = (i + 1) % m
            a, b, c, d = base + i, base + j, base + m + j, base + m + i
            # Boundary edges run as their triangles have them: outward is to the right.
            rim_tris += [(a, d, c), (a, c, b)]
            u0, u1 = length_along[i], length_along[i + 1]
            rim_uv += [[(u0, 0), (u0, FLESH_DEPTH), (u1, FLESH_DEPTH)], [(u0, 0), (u1, FLESH_DEPTH), (u1, 0)]]
    if rim_tris:
        rim_tris = np.array(rim_tris, dtype=np.int64)
        rgba = np.broadcast_to(np.array([*flesh_color, 1.0]), (len(rim_tris), 3, 4)).copy()
        parts.append(Part("leather", np.array(rim_points), rim_tris, None, np.array(rim_uv), rgba))
    return parts


# --- Hair cards ----------------------------------------------------------------

## The card atlas (render_fur_maps.py): columns of cells, a row of long locks
## (0) and one of tufts (1); UV v (Godot) runs from the root to the tip.
CARD_COLUMNS = 8
CARD_SEGMENTS = 3


def scatter(mesh, normals, density, rng):
    """Points spread over a mesh by area: (points, normals, labels)."""
    p, t = mesh.points, mesh.triangles
    areas = 0.5 * np.linalg.norm(np.cross(p[t[:, 1]] - p[t[:, 0]], p[t[:, 2]] - p[t[:, 0]]), axis=1)
    count = max(int(areas.sum() * density), 1)
    pick = rng.choice(len(t), count, p=areas / areas.sum())
    r1, r2 = np.sqrt(rng.random(count)), rng.random(count)
    bary = np.stack([1.0 - r1, r1 * (1.0 - r2), r1 * r2], axis=1)
    corners = t[pick]
    points = np.einsum("ij,ijk->ik", bary, p[corners])
    nrm = normalized(np.einsum("ij,ijk->ik", bary, normals[corners]))
    return points, nrm, mesh.labels[pick]


def card_part(roots, normals, directions, lengths, widths, lift, roll, colors, row, rng, droop=0.25,
              segments=CARD_SEGMENTS):
    """Hair cards: each a bent strip from its root along `directions` (on the
    surface), rising `lift` radians off it and settling back as it goes,
    sagging `droop` of its length under its weight, turned `roll` radians
    about its spine so they show from every side. UVs pick a random lock of
    the atlas `row`; the normals are the surface's (fur shades as a coat,
    not as flat strips)."""
    count = len(roots)
    s = np.linspace(0.0, 1.0, segments + 1)
    side = normalized(np.cross(normals, directions))
    across = side * np.cos(roll)[:, None] + normals * np.sin(roll)[:, None]
    # The spine, integrated from its angle off the surface.
    spine = roots.copy()
    step = 1.0 / segments
    spines = [spine.copy()]
    for k in range(segments):
        angle = lift * (1.0 - (s[k] + step * 0.5) * 1.6)
        heading = directions * np.cos(angle)[:, None] + normals * np.sin(angle)[:, None]
        spine = spine + heading * (lengths * step)[:, None]
        spine = spine + np.array([0.0, 0.0, -1.0]) * (droop * lengths * step * (s[k] + step) * 2.0)[:, None]
        spines.append(spine.copy())
    cell = rng.integers(CARD_COLUMNS, size=count)
    flip = rng.random(count) < 0.5
    u0 = (cell + 0.02) / CARD_COLUMNS
    u1 = (cell + 0.98) / CARD_COLUMNS
    u0, u1 = np.where(flip, u1, u0), np.where(flip, u0, u1)
    v0, v1 = 0.5 * row + 0.004, 0.5 * row + 0.496
    vertices = []
    for k, spine in enumerate(spines):
        half = (widths * 0.5 * (1.0 - 0.15 * s[k]))[:, None]
        vertices.append(spine - across * half)
        vertices.append(spine + across * half)
    # Per card: left and right at each point of the spine.
    vertices = np.stack(vertices, axis=1).reshape(-1, 3)
    per = 2 * (segments + 1)
    base = (np.arange(count) * per)[:, None]
    quad = []
    for k in range(segments):
        a, b, c, d = 2 * k, 2 * k + 1, 2 * k + 3, 2 * k + 2
        # Front faces out of the pelt (across x along points into it).
        quad += [(a, c, b), (a, d, c)]
    quad = np.array(quad)
    tris = (base[:, None, :] + quad[None, :, :]).reshape(-1, 3)
    uv = np.zeros((count, per, 2))
    for k in range(segments + 1):
        v = v0 + (v1 - v0) * s[k]
        uv[:, 2 * k] = np.stack([u0, np.full(count, -v)], axis=1)
        uv[:, 2 * k + 1] = np.stack([u1, np.full(count, -v)], axis=1)
    uv = uv.reshape(-1, 2)
    vertex_normals = np.repeat(normals, per, axis=0)
    col = np.repeat(colors, per, axis=0)
    rgba = np.concatenate([col, np.ones((len(col), 1))], axis=1)
    return Part("fur_card", vertices, tris, vertex_normals, uv[tris], rgba[tris])


def comb_down(points, normals, centre=None, outward=0.4):
    """Down the slope of the surface, and away from a vertical axis through
    `centre` where it is level (over the shoulders): the way hair lies on a
    pelt hung on a body."""
    down = np.array([0.0, 0.0, -1.0])
    slope = down - normals * (normals @ down)[:, None]
    if centre is not None:
        away = points - np.array([centre[0], centre[1], 0.0])
        away[:, 2] = 0.0
        away = away - normals * np.sum(away * normals, axis=1)[:, None]
        slope = slope + normalized(away) * outward
    return normalized(slope)


def edge_roots(mesh, normals, loop, spacing):
    """Points along a boundary loop, `spacing` apart: (points, normals,
    outward across the edge, labels)."""
    p = mesh.points[loop]
    n = normals[loop]
    along = normalized(np.roll(p, -1, axis=0) - np.roll(p, 1, axis=0))
    out = normalized(np.cross(along, n))
    lengths = np.linalg.norm(np.roll(p, -1, axis=0) - p, axis=1)
    cum = np.concatenate([[0.0], np.cumsum(lengths)])
    at = np.arange(0.0, cum[-1], spacing)
    k = np.clip(np.searchsorted(cum, at, side="right") - 1, 0, len(p) - 1)
    f = ((at - cum[k]) / np.maximum(lengths[k], 1e-9))[:, None]
    nxt = (k + 1) % len(p)
    tri_label = {}
    for t, tri in enumerate(mesh.triangles):
        for v in tri:
            tri_label.setdefault(v, mesh.labels[t])
    labels = np.array([tri_label.get(loop[i], 0) for i in k])
    return (p[k] * (1 - f) + p[nxt] * f, normalized(n[k] * (1 - f) + n[nxt] * f),
            normalized(out[k] * (1 - f) + out[nxt] * f), labels)


# --- UVs -----------------------------------------------------------------------

def islands(triangles, count):
    """The triangles of each connected piece, as boolean masks."""
    parent = np.arange(count)

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for a, b, c in triangles:
        for x, y in ((a, b), (b, c)):
            rx, ry = find(x), find(y)
            if rx != ry:
                parent[rx] = ry
    roots = np.array([find(t[0]) for t in triangles])
    return [roots == r for r in np.unique(roots)]


def tube_seams(points, tris):
    """Edges to cut so that every island lies flat: a tube (a ring round a
    limb, the ruff) has two edges, and is cut along the shortest way from
    one to each other."""
    import heapq
    seams = []
    for island in islands(tris, len(points)):
        loops = Mesh(points, tris[island]).loops()
        if len(loops) < 2:
            continue
        nb = {}
        for a, b, c in tris[island]:
            for x, y in ((a, b), (b, c), (c, a)):
                nb.setdefault(x, set()).add(y)
                nb.setdefault(y, set()).add(x)
        start = set(loops[0])
        for target in loops[1:]:
            goal = set(target)
            dist = {v: 0.0 for v in start}
            back = {}
            heap = [(0.0, v) for v in start]
            heapq.heapify(heap)
            end = None
            while heap:
                d, v = heapq.heappop(heap)
                if d > dist.get(v, np.inf):
                    continue
                if v in goal:
                    end = v
                    break
                for w in nb[v]:
                    nd = d + np.linalg.norm(points[v] - points[w])
                    if nd < dist.get(w, np.inf):
                        dist[w] = nd
                        back[w] = v
                        heapq.heappush(heap, (nd, w))
            while end is not None and end in back:
                seams.append((end, back[end]))
                end = back[end]
    return seams


def unwrap(part, seed):
    """Per-corner UVs in metres for a part unwrapped by islands (its labels):
    each one Blender's conformal unwrap, scaled back to metres, turned so
    that its slope runs down +v in Godot (the hair falls that way) and
    shifted at random, so neighbouring islands do not repeat each other."""
    corner_v = part.triangles.ravel()
    corner_l = np.repeat(part.labels, 3)
    pairs, inverse = np.unique(np.stack([corner_v, corner_l], axis=1), axis=0, return_inverse=True)
    points = part.points[pairs[:, 0]]
    tris = inverse.ravel().reshape(-1, 3)
    mesh = bpy.data.meshes.new("unwrap")
    mesh.from_pydata(points.tolist(), [], tris.tolist())
    mesh.uv_layers.new()
    edge_index = {tuple(sorted(e.vertices)): e.index for e in mesh.edges}
    for a, b in tube_seams(points, tris):
        mesh.edges[edge_index[(min(a, b), max(a, b))]].use_seam = True
    obj = bpy.data.objects.new("unwrap", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.unwrap(method="CONFORMAL", margin=0.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = np.zeros(len(mesh.loops) * 2)
    mesh.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 3, 2)
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    rng = np.random.default_rng(seed)
    corners = part.points[part.triangles]
    for island in islands(tris, len(points)):
        rows = island
        p = corners[rows]
        t = uv[rows]
        area3 = 0.5 * np.linalg.norm(np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0]), axis=1).sum()
        e1, e2 = t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]
        area2 = 0.5 * np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]).sum()
        if area2 < 1e-9:
            # Blender could not unwrap it: laid flat across its mean normal.
            n = normalized(np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0]).sum(axis=0))
            side = normalized(np.cross([0.0, 0.0, 1.0], n)) if abs(n[2]) < 0.95 else np.array([1.0, 0.0, 0.0])
            up = np.cross(n, side)
            t = np.stack([p @ side, p @ up], axis=-1)
            area2 = area3
        t = t * math.sqrt(area3 / max(area2, 1e-12))
        # z ~ a u + b v + c: (a, b) is uphill in UV. Uphill goes to +v in
        # Blender, which is -v in Godot: down the slope is +v there.
        flat = t.reshape(-1, 2)
        z = p.reshape(-1, 3)[:, 2]
        design = np.column_stack([flat, np.ones(len(flat))])
        (a, b, _), *_ = np.linalg.lstsq(design, z, rcond=None)
        if math.hypot(a, b) > 0.15:
            turn = math.pi * 0.5 - math.atan2(b, a)
            c, s = math.cos(turn), math.sin(turn)
            flat = flat @ np.array([[c, s], [-s, c]])
        flat = flat - flat.min(axis=0) + rng.uniform(0.0, 4.0, 2)
        uv[rows] = flat.reshape(-1, 3, 2)
    return uv


# --- Weights and output --------------------------------------------------------

def skin_parts(parts, body, entry, slot):
    """fit_meshy_armor.skin() over the parts together: (bones, weights) per part."""
    points = np.concatenate([p.points for p in parts])
    offsets = np.cumsum([0] + [len(p.points) for p in parts])
    tris = np.concatenate([p.triangles + o for p, o in zip(parts, offsets[:-1])])
    mesh = bpy.data.meshes.new("skin")
    mesh.from_pydata(points.tolist(), [], tris.tolist())
    obj = bpy.data.objects.new("skin", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bones, weights = fit.skin(obj, body, entry, slot)
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    for part, a, b in zip(parts, offsets[:-1], offsets[1:]):
        part.bones = bones[a:b]
        part.weights = weights[a:b]


def surfaces(parts, seed):
    """The parts as surfaces, one per material, vertices split where their
    UVs or colours are."""
    by_material = {}
    for i, part in enumerate(parts):
        if len(part.triangles) == 0:
            continue
        if part.unwrap:
            part.uvs = unwrap(part, seed + i)
        if part.normals is None:
            part.normals = mesh_normals(part.points, part.triangles)
        by_material.setdefault(part.material, []).append(part)
    out = []
    for material, group in by_material.items():
        positions, normals, uvs, colors, influences, weights, indices = [], [], [], [], [], [], []
        base = 0
        for part in group:
            keys = {}
            for t, tri in enumerate(part.triangles):
                corners = []
                for c in range(3):
                    v = tri[c]
                    u = part.uvs[t, c]
                    col = part.colors[t, c]
                    key = (v, round(u[0], 5), round(u[1], 5), *np.round(col, 3))
                    if key not in keys:
                        keys[key] = base + len(keys)
                        positions.append(part.points[v])
                        normals.append(part.normals[v])
                        uvs.append((u[0], -u[1]))
                        colors.append(col)
                        influences.append(part.bones[v])
                        weights.append(part.weights[v])
                    corners.append(keys[key])
                # Godot winds front faces clockwise.
                indices.extend([corners[0], corners[2], corners[1]])
            base += len(keys)
        out.append({
            "material": material,
            "positions": fit.to_skin(np.array(positions)).round(6).ravel().tolist(),
            "normals": fit.to_skin_dir(normalized(np.array(normals))).round(5).ravel().tolist(),
            "uvs": np.array(uvs).round(5).ravel().tolist(),
            "colors": np.clip(np.array(colors), 0.0, 1.0).round(4).ravel().tolist(),
            "indices": indices,
            "influences": np.array(influences).ravel().tolist(),
            "weights": np.array(weights).round(5).ravel().tolist(),
        })
    return out


def export(piece_id, parts, body, seed):
    data = {"bones": list(body.names), "surfaces": surfaces(parts, seed)}
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, piece_id + ".json"), "w") as f:
        json.dump(data, f)
    vertices = sum(len(s["positions"]) // 3 for s in data["surfaces"])
    triangles = sum(len(s["indices"]) // 3 for s in data["surfaces"])
    print("%s: %d vertices, %d triangles, %s" % (piece_id, vertices, triangles,
                                                 ", ".join(s["material"] for s in data["surfaces"])))


# --- Preview -------------------------------------------------------------------

## Mean linear colour of each material's map, for the previews.
PREVIEW_SHADE = {"pelt": (0.3, 0.3, 0.3), "fur_card": (0.35, 0.35, 0.35), "leather": (0.478, 0.34, 0.219),
                 "lace": (0.371, 0.259, 0.139), "bone": (0.585, 0.498, 0.347)}


def preview(piece_id, parts, body, views=None):
    """Front, side, back and three-quarter views on the scan (vertex colours)."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 420
    scene.render.resolution_y = 560
    scene.view_settings.view_transform = "Standard"
    objects = []
    body_mesh = bpy.data.meshes.new("body")
    body_mesh.from_pydata(body.points.tolist(), [], body.triangles.tolist())
    attr = body_mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    body_mesh.attributes.active_color_name = "Col"
    body_mesh.attributes.default_color_name = "Col"
    attr.data.foreach_set("color", np.tile([0.48, 0.3, 0.2, 1.0], len(body.points)).astype(np.float32))
    objects.append(bpy.data.objects.new("body", body_mesh))
    everything = []
    for i, part in enumerate(parts):
        mesh = bpy.data.meshes.new("part%d" % i)
        mesh.from_pydata(part.points.tolist(), [], part.triangles.tolist())
        attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        mesh.attributes.active_color_name = "Col"
        mesh.attributes.default_color_name = "Col"
        rgb = np.clip(part.colors[..., :3] * np.array(PREVIEW_SHADE[part.material]), 0.0, 1.0)
        attr.data.foreach_set("color", np.concatenate([rgb, np.ones(rgb.shape[:-1] + (1,))], axis=-1)
                              .astype(np.float32).ravel())
        for poly in mesh.polygons:
            poly.use_smooth = True
        objects.append(bpy.data.objects.new("part%d" % i, mesh))
        everything.append(part.points)
    for obj in objects:
        scene.collection.objects.link(obj)
    p = np.concatenate(everything)
    low, high = p.min(axis=0), p.max(axis=0)
    centre = (low + high) * 0.5
    size = max(high[2] - low[2], (high[0] - low[0]) * 0.75, 0.25) * 1.2
    shots = []
    for name, direction in (views or (("front", (0, -1, 0.05)), ("three", (0.7, -0.7, 0.25)), ("side", (1, 0, 0.05)),
                                      ("back", (0, 1, 0.05)))):
        camera = bpy.data.cameras.new(name)
        camera.type = "ORTHO"
        camera.ortho_scale = size
        cam = bpy.data.objects.new(name, camera)
        scene.collection.objects.link(cam)
        d = Vector(direction).normalized()
        cam.location = Vector(centre) + d * 4.0
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        shot = os.path.join(OUT_DIR, "%s_preview_%s.png" % (piece_id, name))
        scene.render.filepath = shot
        bpy.ops.render.render(write_still=True)
        shots.append(shot)
        bpy.data.objects.remove(cam)
    for obj in objects:
        bpy.data.objects.remove(obj)
    return shots


# --- Seams, stitches and lacing ------------------------------------------------

def surface_frame(bvh, point):
    """Nearest point of a surface and its normal."""
    location, normal, _, _ = bvh.find_nearest(Vector(point))
    return np.array(location), np.array(normal)


def stitches(lines, bvh, spacing, span, radius, lift, color):
    """Whip stitches across seams: short cords every `spacing` m, `span`
    long, lying `lift` over the surface (`bvh`)."""
    parts = []
    placed = []
    for line in lines:
        line = resample(line, spacing * 0.5)
        if len(line) < 3:
            continue
        for i in range(1, len(line) - 1, 2):
            # Where a seam turns back on itself, one stitch is enough.
            if placed and np.min(np.linalg.norm(np.array(placed) - line[i], axis=1)) < spacing * 0.7:
                continue
            placed.append(line[i])
            at, n = surface_frame(bvh, line[i])
            along = normalized(line[i + 1] - line[i - 1])
            across = normalized(np.cross(n, along))
            ends = [at + across * span * 0.5 + along * spacing * 0.15, at - across * span * 0.5 - along * spacing * 0.15]
            curve = []
            for t in np.linspace(0.0, 1.0, 4):
                q = ends[0] + (ends[1] - ends[0]) * t
                q, qn = surface_frame(bvh, q)
                curve.append(q + qn * (lift + radius * (1.0 + math.sin(math.pi * t))))
            parts.append(tube_part("lace", np.array(curve), radius, color, sides=3, caps=False))
    return parts


def ring_on(bvh, centre, heights, count=96, reach=0.6):
    """Where horizontal rays from outside towards a vertical axis through
    `centre` first meet a surface, round it: heights(angle) gives each
    ray's height. Returns points and normals (angle 0 in front, -Y)."""
    points, normals = [], []
    for k in range(count):
        a = 2.0 * math.pi * k / count
        direction = np.array([math.sin(a), -math.cos(a), 0.0])
        z = heights(a)
        origin = np.array([centre[0], centre[1], z]) + direction * reach
        location, normal, _, _ = bvh.ray_cast(Vector(origin), Vector(-direction), reach)
        if location is None:
            continue
        points.append(np.array(location))
        normals.append(np.array(normal))
    return np.array(points), np.array(normals)


def bvh_of(mesh):
    return BVHTree.FromPolygons([Vector(p) for p in mesh.points], mesh.triangles.tolist())


def knot_and_tails(at, n, color, tails, size=1.0):
    """A knot on a belt: a lump of leather and two ends hanging from it
    (`size` scales the lump and the ends' width, for a thong)."""
    side = normalized(np.cross(n, [0.0, 0.0, 1.0]))
    parts = [ellipsoid(at + n * 0.012 * size, [side * 0.022 * size, np.array([0.0, 0.0, 0.016 * size]),
                                               n * 0.014 * size], color, material="leather")]
    for k, (length, spread) in enumerate(tails):
        curve = []
        for t in np.linspace(0.0, 1.0, 10):
            # Out from the body as they fall, clear of a bigger one's belly.
            q = at + n * (0.016 + 0.03 * t) * size + side * spread * t + np.array([0.0, 0.0, -length * t])
            q += n * 0.01 * size * math.sin(math.pi * t)
            curve.append(q)
        curve = np.array(curve)
        normals = np.tile(n, (len(curve), 1))
        parts.append(strap(curve, normals, (0.02 - 0.004 * k) * size, 0.004, color))
    return parts


# --- Trimmings ----------------------------------------------------------------

## Ivory (a mammoth's), antler and a boar's tusk: tints of the bone map.
IVORY = (0.95, 0.9, 0.8)
ANTLER = (0.78, 0.68, 0.54)
TUSK = (0.92, 0.87, 0.76)
## Bone worked into plates, yellowed.
BONE_PLATE = (0.85, 0.79, 0.68)


def merged_part(parts):
    """Parts of one material as one (beads, plates): fewer to shade and export."""
    offsets = np.cumsum([0] + [len(p.points) for p in parts])[:-1]
    normals = None if any(p.normals is None for p in parts) else np.concatenate([p.normals for p in parts])
    return Part(parts[0].material, np.concatenate([p.points for p in parts]),
                np.concatenate([p.triangles + o for p, o in zip(parts, offsets)]), normals,
                np.concatenate([p.uvs for p in parts]), np.concatenate([p.colors for p in parts]))


def beads(curve, spacing, radius, color, closed=False, keep=None):
    """Beads strung along `curve`, `spacing` apart (but where `keep` of
    their centres does not hold)."""
    points = resample(curve, spacing, closed=closed)
    along = normalized(np.roll(points, -1, axis=0) - np.roll(points, 1, axis=0)) if closed else \
        normalized(np.gradient(points, axis=0))
    if keep is not None:
        mask = keep(points)
        points, along = points[mask], along[mask]
    out = []
    for q, t in zip(points, along):
        helper = np.array([1.0, 0.0, 0.0]) if abs(t[2]) > 0.9 else np.array([0.0, 0.0, 1.0])
        u = normalized(np.cross(t, helper))
        out.append(ellipsoid(q, [u * radius, np.cross(t, u) * radius, t * radius * 0.8], color, rings=3,
                             segments=5))
    return [merged_part(out)] if out else []


def plates(rows, size, thickness, color, bvh=None, normals=None, lift=0.003, up=None, laced=True):
    """Plates (bone, antler) sewn in rows: each row an array of the points
    where one is centred, `size` (wide, high) metres, upright (along `up`,
    or +z, on the surface), curved to the surface `bvh` (or flat, facing
    `normals`, rows of them) `lift` off it, and laced along their tops; odd
    rows stand a little further out, over the next. Returns the parts and
    the centres."""
    out, laces, centres = [], [], []
    for k, row in enumerate(rows):
        tops = []
        for i, centre in enumerate(row):
            at, n = surface_frame(bvh, centre) if bvh is not None else (centre, normals[k][i])
            direction = np.array([0.0, 0.0, 1.0]) if up is None else up
            v = normalized(direction - n * (direction @ n))
            curve, curve_n = [], []
            for t in np.linspace(-0.5, 0.5, 4):
                q, qn = surface_frame(bvh, at + v * size[1] * t) if bvh is not None else (at + v * size[1] * t, n)
                curve.append(q + qn * (lift + 0.0018 * (k % 2)))
                curve_n.append(qn)
            out.append(strap(np.array(curve), np.array(curve_n), size[0], thickness, color, material="bone"))
            tops.append(curve[-1] - v * size[1] * 0.16 + n * (thickness + 0.001))
            centres.append(at)
        if laced and len(tops) > 1:
            laces.append(tube_part("lace", np.array(tops), 0.0013, SINEW, sides=4))
    return ([merged_part(out)] if out else []) + laces, np.array(centres).reshape(-1, 3)


def plate_rows(bvh, axis, heights, keep, spacing):
    """Where plates go round a surface (`bvh`) about a vertical axis through
    `axis`: at each height every `spacing` metres where `keep(angle)` holds
    (0 in front), each run of them a row; odd rows shifted half a plate."""
    rows = []
    for k, z in enumerate(heights):
        ring, _ = ring_on(bvh, axis, lambda x, z=z: z, count=720)
        closed = np.vstack([ring, ring[:1]])
        s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(closed, axis=0), axis=1))])
        at = np.arange(spacing * 0.5 * (k % 2), s[-1] - spacing * 0.5, spacing)
        points = np.stack([np.interp(at, s, closed[:, c]) for c in range(3)], axis=1)
        mask = keep(np.arctan2(points[:, 0] - axis[0], -(points[:, 1] - axis[1])))
        # Runs of kept points, the last joined to the first round the back.
        runs, run = [], []
        for i, m in enumerate(mask):
            if m:
                run.append(i)
            elif run:
                runs.append(run)
                run = []
        if run:
            if runs and runs[0][0] == 0:
                runs[0] = run + runs[0]
            else:
                runs.append(run)
        rows += [points[r] for r in runs]
    return rows


def tusk(at, down, out, length, color):
    """A boar's tusk hanging from `at` on a short cord: a tapering crescent
    curling out (`out`) as it goes down."""
    down, out = normalized(np.asarray(down, dtype=np.float64)), normalized(np.asarray(out, dtype=np.float64))
    top = at + down * 0.012
    radius = length * 0.55
    angles = np.linspace(0.0, 2.0, 9)
    curve = np.array([top + down * radius * math.sin(t) + out * radius * (1.0 - math.cos(t)) for t in angles])
    thick = np.linspace(length * 0.1, length * 0.02, len(curve))
    return [tube_part("lace", np.array([at, top]), 0.0014, SINEW, sides=4),
            tube_part("bone", curve, thick, color, sides=6)]


# --- Garments ------------------------------------------------------------------

## Angle round the torso (0 in front, +pi/2 to the character's left).
TORSO_AXIS = (0.0, 0.03)


def torso_angle(p):
    return np.arctan2(p[:, 0] - TORSO_AXIS[0], -(p[:, 1] - TORSO_AXIS[1]))


def arm_field(mesh, env, side, cap):
    """Positive on the arm past `cap(phi)` metres from its shoulder joint
    (phi round the arm, 0 on top): where a sleeve ends."""
    body = env.body
    shoulder = body.joint(side + "Arm")
    axis = normalized(body.joint(side + "ForeArm") - shoulder)
    up = normalized(np.array([0.0, 0.0, 1.0]) - axis * axis[2])
    front = np.cross(axis, up)
    rel = mesh.points - shoulder
    s = rel @ axis
    phi = np.arctan2(rel @ front, rel @ up)
    return np.minimum((on_limb(mesh, body, side, "Arm", "Hand") - 0.5) * 0.2, s - cap(phi))


# --- Occlusion -----------------------------------------------------------------

def occlusion(parts, body, extra=(), rays=24, reach=0.08, seed=1):
    """Ambient occlusion per vertex of `parts` (and per point of `extra`,
    (points, normals) pairs), from the body and every part: the share of a
    cosine-weighted hemisphere of rays that leave within `reach`. A list of
    arrays, one per part (None for hair cards), then one per extra."""
    points = [body.points]
    tris = [body.triangles]
    count = len(body.points)
    for part in parts:
        if part.material == "fur_card":
            continue
        points.append(part.points)
        tris.append(part.triangles + count)
        count += len(part.points)
    bvh = BVHTree.FromPolygons([Vector(q) for q in np.concatenate(points)], np.concatenate(tris).tolist())
    rng = np.random.default_rng(seed)
    r1, r2 = rng.random(rays), rng.random(rays)
    local = np.stack([np.sqrt(r1) * np.cos(2 * np.pi * r2), np.sqrt(r1) * np.sin(2 * np.pi * r2), np.sqrt(1 - r1)], 1)

    def shade(q, n):
        out = np.ones(len(q))
        if len(q) == 0:
            return out
        n = normalized(n)
        helper = np.where(np.abs(n[:, 2:3]) < 0.9, np.array([[0.0, 0.0, 1.0]]), np.array([[1.0, 0.0, 0.0]]))
        tx = normalized(np.cross(helper, n))
        ty = np.cross(n, tx)
        for i in range(len(q)):
            origin = Vector(q[i] + n[i] * 0.003)
            hits = 0
            for d in local:
                direction = tx[i] * d[0] + ty[i] * d[1] + n[i] * d[2]
                if bvh.ray_cast(origin, Vector(direction), reach)[0] is not None:
                    hits += 1
            out[i] = 1.0 - hits / rays
        return out
    result = []
    for part in parts:
        if part.material == "fur_card":
            result.append(None)
            continue
        normals = part.normals if part.normals is not None else mesh_normals(part.points, part.triangles)
        result.append(shade(part.points, normals))
    for q, n in extra:
        result.append(shade(q, n))
    return result


def darken(part, ao, floor=0.35):
    """Multiplies a part's colours by its occlusion (per vertex)."""
    factor = floor + (1.0 - floor) * ao[part.triangles]
    part.colors[..., :3] *= factor[..., None]


# --- The mantle ----------------------------------------------------------------

## Where the torso of the tunic ends and its skirt starts (above the crotch).
SKIRT_TOP = 1.0


def tunic(env, body, belt_z, hem, armhole, over):
    """A sleeveless hide tunic: the torso inflated off the skin, and from the
    hips a skirt hanging plumb from the most the body stands out, opening to
    `hem(angle)`. Folds as hide makes them: blousing over the belt, flutes
    hanging from it. Below the belt it stands `over` metres off the skin,
    room for what is worn under it (fur_loincloth's belt and fur)."""
    centre = body.joint("Hips")[:2]
    m = env.mesh()
    p = m.points
    a = torso_angle(p)
    neck_axis = body.joint("Neck")
    across = np.hypot(p[:, 0] - neck_axis[0], p[:, 1] - neck_axis[1])
    front = np.exp(-(a / 0.4) ** 2)
    opening = np.minimum(0.083 + 0.012 * front - across, p[:, 2] - (1.47 - 0.06 * front))
    field = np.maximum(np.maximum(opening, p[:, 2] - 1.6), SKIRT_TOP - p[:, 2])
    for side in fit.SIDES:
        field = np.maximum(field, arm_field(m, env, side, armhole))
    m.cut(field)
    best = max(islands(m.triangles, len(m.points)), key=lambda k: k.sum())
    m.keep(best)
    z = m.points[:, 2]
    # Snug at the belt, eased elsewhere.
    clearance = 0.012 + 0.006 * smoothstep(belt_z + 0.15, belt_z + 0.3, z) \
        + (over - 0.012) * smoothstep(belt_z - 0.02, belt_z - 0.1, z)
    inflate(m, body, clearance, start=clearance)
    # The skirt, from the lowest loop down.
    loops = m.loops()
    bottom = min(loops, key=lambda l: m.points[l][:, 2].mean())
    bvh = body_bvh(env)
    ring = m.points[bottom]
    angles = np.arctan2(ring[:, 0] - centre[0], -(ring[:, 1] - centre[1]))
    depth = ring[:, 2] - np.array([hem(x) for x in angles])
    rows = int(depth.max() / 0.015) + 1
    points = list(m.points)
    columns = []
    for i, v in enumerate(bottom):
        direction = np.array([math.sin(angles[i]), -math.cos(angles[i]), 0.0])
        r = np.hypot(ring[i, 0] - centre[0], ring[i, 1] - centre[1])
        column = [v]
        for j in range(1, rows + 1):
            zj = ring[i, 2] - depth[i] * j / rows
            r = max(r, radial(bvh, centre, angles[i], zj) + over)
            column.append(len(points))
            points.append(np.array([centre[0], centre[1], zj]) + direction * (r + 0.08 * (ring[i, 2] - zj)))
        columns.append(column)
    tris = list(m.triangles)
    count = len(bottom)
    for i in range(count):
        k = (i + 1) % count
        for j in range(rows):
            a0, b0 = columns[i][j], columns[k][j]
            a1, b1 = columns[i][j + 1], columns[k][j + 1]
            # The loop runs with the torso on its left: the skirt hangs to its right.
            tris += [(a0, a1, b1), (a0, b1, b0)]
    skirt = Mesh(np.array(points), np.array(tris))
    # Columns: no one sticks out from its neighbours.
    grid = np.array(columns)
    for _ in range(3):
        q = skirt.points[grid[:, 1:]]
        q = 0.5 * q + 0.25 * (np.roll(q, 1, axis=0) + np.roll(q, -1, axis=0))
        skirt.points[grid[:, 1:]] = q
    folds(skirt, body, belt_z, hem)
    return skirt


def folds(m, body, belt_z, hem):
    """Hide gathered by a belt: over it the tunic blouses out, under it it
    falls in flutes, deeper to the hem."""
    centre = body.joint("Hips")[:2]
    p = m.points
    a = np.arctan2(p[:, 0] - centre[0], -(p[:, 1] - centre[1]))
    out = np.stack([np.sin(a), -np.cos(a), np.zeros_like(a)], axis=1)
    z = p[:, 2]
    low = np.array([hem(x) for x in a])
    # Flutes: about a dozen round the hips, wandering, sharper outside.
    phase = 0.7 * np.sin(2 * a + 1.3) + 2.5 * (belt_z - z) * np.sin(3 * a + 0.4)
    wave = np.sin(11 * a + phase)
    profile = np.sign(wave) * np.abs(wave) ** 0.7 + 0.35
    below = np.clip((belt_z - z) / np.maximum(belt_z - low, 0.05), 0.0, 1.0)
    p += out * (0.014 * below ** 0.8 * profile)[:, None]
    # Blousing over the belt, with a few soft sags.
    above = np.clip((z - belt_z) / 0.13, 0.0, 1.0)
    blouse = np.sin(np.pi * above) ** 1.5 * (above > 0)
    sag = 0.004 * np.sin(5 * a + 70.0 * (z - belt_z))
    p += out * ((0.012 + sag) * blouse)[:, None]
    # Cinched at the belt.
    p -= out * (0.006 * np.exp(-((z - belt_z) / 0.02) ** 2))[:, None]


def pouch(at, out, down, color):
    """A leather pouch hanging from a belt at `at`: a sack flat against the
    body (`out` faces away from it), a flap over its mouth, a toggle."""
    side = normalized(np.cross(down, out))
    rings, segments = 9, 14
    points = []
    for i in range(rings + 1):
        t = i / rings
        width = 0.05 * math.sin(math.pi * min(t * 1.15, 1.0)) ** 0.6 + 0.012
        depth = 0.022 * math.sin(math.pi * t) ** 0.8 + 0.004
        centre = at + down * (0.012 + 0.11 * t) + out * depth * 0.6
        for k in range(segments):
            ang = 2 * math.pi * k / segments
            bulge = 1.0 + 0.08 * math.sin(3 * ang + t * 4)
            points.append(centre + side * math.cos(ang) * width * bulge + out * math.sin(ang) * depth * bulge)
    tris = []
    for i in range(rings):
        for k in range(segments):
            a, b = i * segments + k, i * segments + (k + 1) % segments
            c, d = b + segments, a + segments
            tris += [(a, b, c), (a, c, d)]
    sack = Mesh(np.array(points), np.array(tris))
    if np.sum(sack.normals() * (sack.points - (at + down * 0.06))) < 0:
        sack.triangles = sack.triangles[:, [0, 2, 1]]
    uv = np.stack([sack.points @ side, sack.points @ down], axis=1)[sack.triangles]
    rgba = np.broadcast_to(np.array([*color, 1.0]), (len(sack.triangles), 3, 4)).copy()
    parts = [Part("leather", sack.points, sack.triangles, sack.normals(), uv, rgba)]
    # The flap over the mouth and a bone toggle on it.
    flap = np.array([at + down * (0.006 + 0.05 * t) + out * (0.03 * math.sin(math.pi * min(t * 1.6, 1.0)) + 0.008)
                     for t in np.linspace(0.0, 1.0, 7)])
    parts.append(strap(flap, np.tile(out, (len(flap), 1)), 0.085, 0.004, tuple(c * 0.85 for c in color)))
    parts.append(ellipsoid(flap[-1] + out * 0.008, [side * 0.012, down * 0.004, out * 0.004], BONE))
    return parts


def wolf_pelt(env, body, low, cap, clearance):
    """A wolf's pelt laid over the shoulders: the region of the body above
    `low(points, angle)`, round the neck and down the arms to `cap(phi)`,
    inflated `clearance` off the skin (over what is under it)."""
    m = env.mesh()
    p = m.points
    a = torso_angle(p)
    neck_axis = body.joint("Neck")
    across = np.hypot(p[:, 0] - neck_axis[0], p[:, 1] - neck_axis[1])
    front = np.exp(-(a / 0.5) ** 2)
    opening = np.minimum(0.098 + 0.02 * front - across, p[:, 2] - (1.47 - 0.04 * front))
    field = np.maximum(low(p, a) - p[:, 2], np.maximum(opening, p[:, 2] - 1.6))
    for side in fit.SIDES:
        field = np.maximum(field, arm_field(m, env, side, cap))
    m.cut(field)
    best = max(islands(m.triangles, len(m.points)), key=lambda k: k.sum())
    m.keep(best)
    inflate(m, body, np.full(len(m.points), clearance), start=np.full(len(m.points), clearance))
    m.labels[:] = 0
    return m


## A grey wolf's pelt (wolf_colors): its back, flanks, belly, the saddle
## down its spine and, if they differ, its forelegs.
WOLF_PELT = {"back": WOLF, "flank": TAWNY, "belly": CREAM, "saddle": WOLF_STRIPE, "legs": None}


def wolf_colors(q, labels, pelt=WOLF_PELT, legs_at=0.3, chest=1.36):
    """A pelt over the shoulders coloured as a grey wolf's (or as `pelt`
    says): a dark saddle down the spine, tawny grey flanks, cream under the
    neck and on the forelegs, which hang over the chest `legs_at` radians
    either side of the front, below `chest`."""
    behind = smoothstep(-0.02, 0.06, q[:, 1])
    saddle = np.exp(-(q[:, 0] / 0.09) ** 2) * behind
    belly = 0.6 * smoothstep(0.0, -0.08, q[:, 1]) * smoothstep(1.4, 1.25, q[:, 2])
    flank = smoothstep(0.1, 0.22, np.abs(q[:, 0]))
    base = np.array(pelt["back"])[None, :] * np.ones((len(q), 1))
    base = base * (1 - 0.45 * flank[:, None]) + np.array(pelt["flank"]) * 0.45 * flank[:, None]
    base = base * (1 - 0.6 * belly[:, None]) + np.array(pelt["belly"]) * 0.6 * belly[:, None]
    base = base * (1 - 0.75 * saddle[:, None]) + np.array(pelt["saddle"]) * 0.75 * saddle[:, None]
    if pelt["legs"] is not None:
        a = torso_angle(q)
        legs = np.exp(-((np.abs(a) - legs_at) / 0.09) ** 2) * smoothstep(chest - 0.07, chest - 0.13, q[:, 2]) \
            * smoothstep(0.3, 0.6, np.cos(a))
        base = base * (1 - legs[:, None]) + np.array(pelt["legs"]) * legs[:, None]
    return base * (1.0 + wobble(q, SEED + 40, 6.0, 0.12))[:, None]


def fur_coat(m, normals, colors, rng, density, length, edge_length, row_long=0, centre=None, skip_edge=None,
             avoid=None, width=1.0):
    """Hair cards over a pelt `m`: long locks combed down it, a short coat
    between them, and locks hanging over its edges (but where `skip_edge`
    of an edge point holds). `length(points)` is how long the locks are,
    `width` how wide for their length (narrow: bristles)."""
    parts = []

    def spread(share):
        roots, rn, labels = scatter(m, normals, density * share, rng)
        if avoid is not None:
            keep = ~avoid(roots)
            roots, rn, labels = roots[keep], rn[keep], labels[keep]
        return roots, rn, labels
    roots, rn, labels = spread(1.0)
    dirs = comb_down(roots, rn, centre)
    dirs = normalized(dirs + rng.normal(0.0, 0.15, dirs.shape))
    dirs = normalized(dirs - rn * np.sum(dirs * rn, axis=1)[:, None])
    long = length(roots) * rng.uniform(0.6, 1.3, len(roots))
    tint = rng.uniform(0.8, 1.2, (len(roots), 1))
    parts.append(card_part(roots - rn * 0.002, rn, dirs, long, long * rng.uniform(0.4, 0.55, len(roots)) * width,
                           rng.uniform(0.05, 0.25, len(roots)),
                           rng.uniform(0.1, 0.6, len(roots)) * rng.choice([-1, 1], len(roots)),
                           colors(roots, labels) * tint, row_long, rng))
    roots, rn, labels = spread(0.45)
    dirs = comb_down(roots, rn, centre)
    short = length(roots) * 0.6 * rng.uniform(0.8, 1.2, len(roots))
    parts.append(card_part(roots - rn * 0.002, rn, dirs, short, short * 0.75 * width, rng.uniform(0.1, 0.3, len(roots)),
                           rng.uniform(-0.3, 0.3, len(roots)), colors(roots, labels) * 0.9, 1, rng, segments=2))
    for loop in m.loops():
        er, en, eo, el = edge_roots(m, normals, loop, 0.014)
        keep = np.ones(len(er), bool) if skip_edge is None else ~skip_edge(er)
        if keep.sum() < 2:
            continue
        er, en, eo, el = er[keep], en[keep], eo[keep], el[keep]
        d = normalized(eo * 0.7 + np.array([0.0, 0.0, -0.5]))
        d = normalized(d - en * np.sum(d * en, axis=1)[:, None] * 0.5)
        reach = edge_length * rng.uniform(0.7, 1.2, len(er))
        parts.append(card_part(er - eo * 0.012, en, d, reach, reach * 0.5 * width, rng.uniform(0.1, 0.4, len(er)),
                               rng.uniform(-0.9, 0.9, len(er)), colors(er, el), row_long, rng, droop=0.35))
    return parts


## How a light set looks (each piece takes the keys it uses; these are
## the grey wolf's, the others are in the variants' sets): the colours of
## its pelts and hides, how long and how wide the hair is (a boar's crest
## of bristles down the spine), where the forelegs hang, and what is sewn
## or hung on it: bone plates, ivory beads or boar's tusks (their colour,
## or None).
MANTLE = {"pelt": WOLF_PELT, "hide": HIDE, "hair": (0.05, 0.02), "crest": 0.0, "bristle": 1.0, "legs_at": 0.3,
          "chest": 1.36, "drop": 0.14, "plates": None, "beads": None, "tusks": None}


def mantle(env, body, style=None):
    """A hide tunic to the hips, belted, with a wolf's pelt over the
    shoulders, its forelegs hanging over the chest and tied across it; a
    pouch on the belt. `style` (MANTLE's keys) changes the animal and adds
    a breastplate and rows of plates on the jerkin, beads or tusks."""
    st = {**MANTLE, **(style or {})}
    rng = np.random.default_rng(SEED)
    belt_z = 1.15
    hem = lambda a: 0.955 + 0.012 * math.cos(2 * a) + 0.006 * math.sin(5 * a + 1)
    shirt = tunic(env, body, belt_z, hem, lambda phi: 0.012 + 0.0 * phi, 0.045)
    shirt.labels[:] = 0
    parts = pelt_parts(shirt, lambda q, l: np.tile(st["hide"], (len(q), 1)), bare=[0], flesh=0.025)
    legs_at, chest = st["legs_at"], st["chest"]

    def low(p, a):
        edge = np.where(np.cos(a) > 0, chest - st["drop"] * (1 - np.cos(a)) ** 1.5, 1.22 - 0.1 * (-np.cos(a)))
        edge -= lobes(a, [(legs_at, 0.085, 0.17), (-legs_at, 0.085, 0.17), (math.pi, 0.07, 0.17),
                          (2.2, 0.12, 0.05), (-2.2, 0.12, 0.05)])
        return edge + wobble(p, SEED + 11, 5.0, 0.012)

    def cap(phi):
        return 0.08 + 0.06 * (0.5 + 0.5 * np.cos(phi)) + lobes(phi, [(0.5, 0.25, 0.03), (-1.2, 0.2, 0.02)])
    pelt = wolf_pelt(env, body, low, cap, 0.034)
    pelt_normals = pelt.normals()
    pelt_colors = lambda q, l: wolf_colors(q, l, st["pelt"], legs_at, chest)
    parts += pelt_parts(pelt, pelt_colors)
    # The belt, wound twice, its knot in front to the left, and a pouch on the right hip.
    bvh = bvh_of(shirt)
    belt_parts = []
    for turn, dz in enumerate((0.0,)):
        ring, ring_n = ring_on(bvh, TORSO_AXIS, lambda x, dz=dz: belt_z + dz - 0.01 * math.cos(x) + 0.006 * turn)
        ring = smooth_polyline(ring + ring_n * (0.003 + 0.004 * turn), 3, closed=True)
        ring_n = normalized(smooth_polyline(ring_n, 3, closed=True))
        belt_parts.append(strap(ring, ring_n, 0.028, 0.004, tuple(c * (1.0 - 0.08 * turn) for c in BELT),
                                closed=True))
    k = int(len(ring) * 0.06)
    belt_parts += knot_and_tails(ring[k] + ring_n[k] * 0.006, ring_n[k], BELT, [(0.2, 0.02), (0.15, -0.012)])
    side = int(len(ring) * 0.7)
    belt_parts += pouch(ring[side] + ring_n[side] * 0.008, ring_n[side], np.array([0.0, 0.0, -1.0]), HIDE)
    parts += belt_parts
    # The forelegs tied across the chest with a thong.
    tips = []
    for sign in (1.0, -1.0):
        legs = pelt.points[np.abs(torso_angle(pelt.points) - legs_at * sign) < 0.12]
        tips.append(legs[np.argmin(legs[:, 2])] + np.array([0.0, 0.0, 0.03]))
    tie = np.array([tips[0] + (tips[1] - tips[0]) * t + np.array([0.0, -0.012, 0.0]) * math.sin(math.pi * t)
                    for t in np.linspace(0.0, 1.0, 9)])
    parts.append(tube_part("lace", tie, 0.003, SINEW))
    parts.append(ellipsoid((tips[0] + tips[1]) * 0.5 + np.array([0.0, -0.016, 0.0]),
                           [np.array([0.014, 0.0, 0.0]), np.array([0.0, 0.008, 0.0]), np.array([0.0, 0.0, 0.01])],
                           BELT, material="leather"))
    # What is sewn on the jerkin or hung on it, clear of the knot and the pouch.
    knot_a, pouch_a = torso_angle(ring[[k, side]])
    clear = lambda a: (np.abs(np.angle(np.exp(1j * (a - knot_a)))) > 0.16) & \
        (np.abs(np.angle(np.exp(1j * (a - pouch_a)))) > 0.42)
    if st["plates"] is not None:
        # A breastplate between the forelegs, and rows of plates down the skirt.
        rows = plate_rows(bvh, TORSO_AXIS, [1.2, 1.245, 1.29, 1.335], lambda a: np.abs(a) < legs_at - 0.17, 0.034)
        rows += plate_rows(bvh, TORSO_AXIS, [1.105, 1.06, 1.015], lambda a: clear(a) & (np.abs(a) < 2.3), 0.035)
        parts += plates(rows, (0.03, 0.044), 0.004, st["plates"], bvh=bvh)[0]
    if st["beads"] is not None:
        # Rows of beads round the skirt, and strung on the forelegs' tie.
        for z in (1.105, 1.08, 1.055):
            row, row_n = ring_on(bvh, TORSO_AXIS, lambda x, z=z: z - 0.01 * math.cos(x), count=192)
            parts += beads(row + row_n * 0.004, 0.011, 0.0038, st["beads"], closed=True,
                           keep=lambda q: clear(torso_angle(q)))
        parts += beads(tie, 0.009, 0.0035, st["beads"])
    if st["tusks"] is not None:
        # A tusk either side of the tie's knot; three hanging from the belt by its knot.
        knot = (tips[0] + tips[1]) * 0.5 + np.array([0.0, -0.016, 0.0])
        for sign in (1.0, -1.0):
            parts += tusk(knot + np.array([0.012 * sign, -0.006, -0.004]), [0.0, -0.3, -1.0], [sign, -0.3, 0.0],
                          0.05, st["tusks"])
        for f in (0.1, 0.135, 0.17):
            j = int(len(ring) * f)
            parts += tusk(ring[j] + ring_n[j] * 0.008 - np.array([0.0, 0.0, 0.012]), [0.0, 0.0, -1.0], ring_n[j],
                          0.06, st["tusks"])
    # Shadows between the layers, then the hair over the pelt.
    ao = occlusion(parts, body)
    for part, shade in zip(parts, ao):
        if shade is not None:
            darken(part, shade)
    neck_axis = body.joint("Neck")
    shade_at = occlusion_field(parts, body, pelt, pelt_normals)
    colors = lambda q, l: pelt_colors(q, l) * shade_at(q)[:, None]
    hair, crest = st["hair"], st["crest"]
    length = lambda q: hair[0] + hair[1] * (q[:, 1] > 0.0)
    if crest:
        length = lambda q: hair[0] + hair[1] * (q[:, 1] > 0.0) \
            + crest * np.exp(-(q[:, 0] / 0.045) ** 2) * (q[:, 1] > 0.02)
    parts += fur_coat(pelt, pelt_normals, colors, rng, 3000, length, 0.06, centre=neck_axis,
                      skip_edge=lambda q: np.hypot(q[:, 0] - neck_axis[0], q[:, 1] - neck_axis[1]) < 0.13,
                      width=st["bristle"])
    return parts, [(parts, {"weight_radius": 0.06}, "chest")]


def occlusion_field(parts, body, mesh, normals):
    """Occlusion over a pelt's surface, for the cards rooted on it: computed
    at its vertices, looked up at the nearest."""
    shade = occlusion(parts, body, extra=[(mesh.points, normals)])[-1]
    tree = KDTree(len(mesh.points))
    for i, q in enumerate(mesh.points):
        tree.insert(Vector(q), i)
    tree.balance()
    return lambda q: np.array([0.35 + 0.65 * shade[tree.find(Vector(x))[1]] for x in q])


def body_bvh(env, mesh=None, exclude=("Arm", "Hand")):
    """The envelope without the arms (they hang by the hips in the scan's pose)."""
    m = mesh or env.mesh()
    away = np.zeros(len(m.points))
    for side in fit.SIDES:
        away += on_limb(m, env.body, side, *exclude)
    keep = away[m.triangles].max(axis=1) < 0.5
    return BVHTree.FromPolygons([Vector(p) for p in m.points], m.triangles[keep].tolist())


def radial(bvh, centre, angle, z, reach=0.5):
    """How far from a vertical axis through `centre` a horizontal ray from
    outside first meets the surface (0 if it does not)."""
    direction = np.array([math.sin(angle), -math.cos(angle), 0.0])
    origin = np.array([centre[0], centre[1], z]) + direction * reach
    location, _, _, distance = bvh.ray_cast(Vector(origin), Vector(-direction), reach)
    return 0.0 if location is None else reach - distance


def hanging(bvh, centre, angles, top, depth, clearance, flare=0.0, step=0.018):
    """A curtain hanging from `top(angle)` down `depth` metres: each column
    falls plumb from the most the body stands out above it (a thigh, the
    buttocks), `clearance(z)` off it, and opens `flare` metres per metre down."""
    rows = max(int(depth / step), 2)
    grid = []
    for a in angles:
        direction = np.array([math.sin(a), -math.cos(a), 0.0])
        z0 = top(a)
        r = 0.0
        column = []
        for j in range(rows + 1):
            z = z0 - depth * j / rows
            r = max(r, radial(bvh, centre, a, z) + clearance(z))
            column.append(np.array([centre[0], centre[1], z]) + direction * (r + flare * (z0 - z)))
        grid.append(column)
    grid = np.array(grid)
    # Cloth: no column sticks out from its neighbours.
    for _ in range(4):
        grid[1:-1, 1:] = 0.5 * grid[1:-1, 1:] + 0.25 * (grid[:-2, 1:] + grid[2:, 1:])
    cols = len(angles)
    points = grid.reshape(-1, 3)
    tris = []
    for i in range(cols - 1):
        for j in range(rows):
            a, b = i * (rows + 1) + j, (i + 1) * (rows + 1) + j
            c, d = b + 1, a + 1
            tris += [(a, d, c), (a, c, b)]
    mesh = Mesh(points, tris)
    centre3 = np.array([centre[0], centre[1], points[:, 2].mean()])
    flat = points - centre3
    flat[:, 2] = 0.0
    if (mesh.normals() * flat).sum() < 0:
        mesh.triangles = mesh.triangles[:, [0, 2, 1]]
    return mesh


def flutes(m, centre, top, count, depth, seed):
    """Folds hanging from `top(angle)`: the hide pushed out and in round a
    vertical axis through `centre`, `count` times a turn, `depth` deep at
    the bottom."""
    p = m.points
    a = np.arctan2(p[:, 0] - centre[0], -(p[:, 1] - centre[1]))
    out = np.stack([np.sin(a), -np.cos(a), np.zeros_like(a)], axis=1)
    drop = np.maximum(np.array([top(x) for x in a]) - p[:, 2], 0.0)
    rng = np.random.default_rng(seed)
    phase = rng.uniform(0, 2 * np.pi) + 0.6 * np.sin(2 * a + rng.uniform(0, 6)) + 6.0 * drop * np.sin(3 * a)
    wave = np.sin(count * a + phase)
    profile = np.sign(wave) * np.abs(wave) ** 0.7 + 0.3
    p += out * (depth * np.clip(drop / 0.3, 0.0, 1.0) ** 0.8 * profile)[:, None]


## Brown pelts (a bear's, a deer's) for the loincloth.
BROWN = (0.254, 0.176, 0.113)
BROWN_DARK = (0.148, 0.106, 0.0704)
SKIRT_HIDE = (0.414, 0.343, 0.282)


## The loincloth's look (as MANTLE): its skirt's fur (and darker to the
## hem), its flaps' hide, the leather under it; on the ends of the flaps,
## below the fur (the belt is under whatever is worn over it): rows of bone
## plates or of beads with strands hanging from them, or tusks.
LOINCLOTH = {"skirt": (BROWN, BROWN_DARK), "flaps": SKIRT_HIDE, "hide": HIDE, "hair": (0.035, 0.015), "bristle": 1.0,
             "plates": None, "beads": None, "tusks": None}


def loincloth(env, body, style=None):
    """A belt at the hips holding two long hide flaps, in front and behind,
    and over them a short skirt of fur wrapped round the hips, all over a
    leather loincloth. `style`: LOINCLOTH's keys."""
    st = {**LOINCLOTH, **(style or {})}
    rng = np.random.default_rng(SEED + 1)
    centre = body.joint("Hips")[:2]
    bvh = body_bvh(env)
    belt_z = lambda a: 1.035 + 0.03 * (1.0 - math.cos(a)) * 0.5

    # The leather under it, round the hips to the groin.
    m = env.mesh()
    a = np.arctan2(m.points[:, 0] - centre[0], -(m.points[:, 1] - centre[1]))
    thighs = on_limb(m, body, "Left", "UpLeg") + on_limb(m, body, "Right", "UpLeg")
    top = np.array([belt_z(x) for x in a]) - 0.004
    field = np.maximum(m.points[:, 2] - top, thighs - 0.72)
    field = np.maximum(field, 0.86 - m.points[:, 2])
    away = on_limb(m, body, "Left", "Arm", "Hand") + on_limb(m, body, "Right", "Arm", "Hand")
    field = np.maximum(field, away - 0.5)
    m.cut(field)
    m.keep(np.ones(len(m.triangles), bool))
    m.labels[:] = 10
    # Its flesh side, under it, keeps clear of a bigger body too.
    clearance = np.full(len(m.points), 0.012)
    inflate(m, body, clearance, rounds=10, start=clearance)
    under = pelt_parts(m, lambda q, l: np.tile(st["hide"], (len(q), 1)), bare=[10], flesh=0.03)

    # The flaps: (centre angle, half width, how far below the belt, label).
    hung = []
    flaps = []
    for k, (ac, half, depth, label) in enumerate([(0.0, 0.34, 0.43, 11), (math.pi, 0.42, 0.4, 12)]):
        angles = np.linspace(ac - half, ac + half, 12)
        flap = hanging(bvh, centre, angles, lambda x: belt_z(x) + 0.012, depth + 0.04,
                       lambda z: 0.016 + 0.006 * smoothstep(0.98, 0.8, z), flare=0.03, step=0.016)
        p = flap.points
        fa = np.arctan2(p[:, 0] - centre[0], -(p[:, 1] - centre[1]))
        off = np.angle(np.exp(1j * (fa - ac)))
        bottom = np.array([belt_z(x) for x in fa]) - depth - 0.015 * (off / half) ** 2 + wobble(p, SEED + 50 + k, 4.0,
                                                                                               0.01)
        flap.cut(bottom - p[:, 2])
        flutes(flap, centre, belt_z, 22, 0.008, SEED + k)
        flap.labels[:] = label
        flaps.append((flap, ac, half, depth))
        hung += pelt_parts(flap, lambda q, l: np.tile(st["flaps"], (len(q), 1)), bare=[label], double=True)
    # The fur skirt, wrapped once round and a little over itself on the left.
    start = math.pi / 2 - 0.25
    angles = np.linspace(start, start + 2 * math.pi + 0.5, 66)
    skirt = hanging(bvh, centre, angles, lambda x: belt_z(x) + 0.006, 0.36,
                    lambda z: 0.032 + 0.008 * smoothstep(0.98, 0.8, z), flare=0.06, step=0.016)
    p = skirt.points
    fa = np.arctan2(p[:, 0] - centre[0], -(p[:, 1] - centre[1]))
    # Its outer end lies over the inner one.
    column = np.repeat(np.arange(len(angles)), len(p) // len(angles))
    outer = smoothstep(len(angles) - 10, len(angles) - 4, column)
    out = np.stack([np.sin(fa), -np.cos(fa), np.zeros_like(fa)], axis=1)
    skirt.points += out * (0.012 * outer)[:, None]
    hem = np.array([belt_z(x) for x in fa]) - 0.29 - lobes(fa, [(0.5, 0.12, 0.05), (-0.6, 0.12, 0.045),
                                                               (2.6, 0.14, 0.05), (-2.4, 0.12, 0.04)]) \
        + wobble(p, SEED + 60, 5.0, 0.012)
    skirt.cut(hem - p[:, 2])
    flutes(skirt, centre, belt_z, 9, 0.01, SEED + 7)
    skirt.labels[:] = 13
    skirt_normals = skirt.normals()

    def brown(q, labels):
        low = smoothstep(0.85, 0.72, q[:, 2])
        base = np.array(st["skirt"][0])[None, :] * (1 - 0.5 * low[:, None]) \
            + np.array(st["skirt"][1]) * 0.5 * low[:, None]
        return base * (1.0 + wobble(q, SEED + 61, 6.0, 0.14))[:, None]
    hung += pelt_parts(skirt, brown, double=True)
    # The belt over the skirt's top, knotted in front to the right.
    ring, ring_n = ring_on(bvh, centre, belt_z)
    ring = smooth_polyline(ring + ring_n * 0.042, 4, closed=True)
    ring_n = normalized(smooth_polyline(ring_n, 4, closed=True))
    fixed = under + [strap(ring, ring_n, 0.03, 0.005, BELT, closed=True)]
    k = int(len(ring) * 0.92)
    fixed += knot_and_tails(ring[k] + ring_n[k] * 0.006, ring_n[k], BELT, [(0.2, -0.015), (0.16, 0.02)])
    # On the ends of the flaps, below the fur skirt.
    axis = (np.array([centre[0], centre[1], 0.0]), np.array([centre[0], centre[1], 1.0]))
    for flap, ac, half, depth in flaps:
        fbvh = bvh_of(flap)
        across = lambda count, z, lift, span=0.62: [
            q for q in (around_leg(fbvh, *axis, a, z, lift) for a in np.linspace(ac - half * span, ac + half * span, count))
            if q is not None]
        bottom = belt_z(ac) - depth
        if st["plates"] is not None:
            # Flat, over the flutes.
            rows = [np.array(across(3 - k % 2, bottom + dz, 0.007, 0.5 - 0.25 * (k % 2)))
                    for k, dz in enumerate((0.11, 0.072, 0.034))]
            out = [normalized(r * np.array([1.0, 1.0, 0.0]) - np.array([centre[0], centre[1], 0.0])) for r in rows]
            hung += plates(rows, (0.021, 0.036), 0.003, st["plates"], normals=out, lift=0.0)[0]
        if st["beads"] is not None:
            for dz in (0.1, 0.085, 0.07, 0.04):
                hung += beads(np.array(across(40, bottom + dz, 0.004)), 0.0085, 0.0032, st["beads"])
            for q in across(9, bottom + 0.04, 0.004):
                strand = np.array([q + np.array([0.0, 0.0, -0.07 * t]) for t in np.linspace(0.0, 1.0, 6)])
                hung += beads(strand, 0.0085, 0.0032, st["beads"])
        if st["tusks"] is not None:
            for q in across(3, bottom + 0.03, 0.004):
                out = np.array([q[0] - centre[0], q[1] - centre[1], 0.0])
                hung += tusk(q, [0.0, 0.0, -1.0], out, 0.065, st["tusks"])
    parts = hung + fixed
    ao = occlusion(parts, body)
    for part, shade in zip(parts, ao):
        if shade is not None:
            darken(part, shade)
    shade_at = occlusion_field(parts, body, skirt, skirt_normals)
    top_band = lambda q: q[:, 2] > np.array([belt_z(x) for x in np.arctan2(q[:, 0] - centre[0],
                                                                          -(q[:, 1] - centre[1]))]) - 0.03
    hair = st["hair"]
    cards = fur_coat(skirt, skirt_normals, lambda q, l: brown(q, l) * shade_at(q)[:, None], rng, 3000,
                     lambda q: hair[0] + hair[1] * smoothstep(0.95, 0.8, q[:, 2]), 0.05, skip_edge=top_band,
                     width=st["bristle"])
    hung += cards
    return hung + fixed, [(hung, {"skirt": True, "hang": True, "weight_radius": 0.05}, "legs"),
                          (fixed, {"weight_radius": 0.05}, "legs")]


def sphere_points(centre, radius, count=40):
    """Points on a sphere (a Fibonacci spiral)."""
    i = np.arange(count) + 0.5
    phi = np.arccos(1.0 - 2.0 * i / count)
    theta = np.pi * (1.0 + 5.0 ** 0.5) * i
    d = np.stack([np.cos(theta) * np.sin(phi), np.sin(theta) * np.sin(phi), np.cos(phi)], axis=1)
    return centre + d * radius


def solid(points_list, voxel, smooth_rounds):
    """The union of closed shapes, each the convex hull of a point cloud,
    remeshed into even cells and smoothed (the joins fill in)."""
    bm = bmesh.new()
    for cloud in points_list:
        part = bmesh.new()
        for q in cloud:
            part.verts.new(q)
        bmesh.ops.convex_hull(part, input=part.verts)
        mesh = bpy.data.meshes.new("hull")
        part.to_mesh(mesh)
        part.free()
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    mesh = bpy.data.meshes.new("solid")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("solid", mesh)
    bpy.context.scene.collection.objects.link(obj)
    modifier = obj.modifiers.new("remesh", "REMESH")
    modifier.mode = "VOXEL"
    modifier.voxel_size = voxel
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.verts.ensure_lookup_table()
    points = np.array([v.co for v in bm.verts])
    tris = np.array([[v.index for v in f.verts] for f in bm.faces], dtype=np.int64)
    bm.free()
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    return Mesh(points, tris).smooth(0.5, smooth_rounds)


def capsule_points(a, b, ra, rb, count=6):
    return np.concatenate([sphere_points(a + (b - a) * t, ra + (rb - ra) * t, 30) for t in np.linspace(0, 1, count)])


def lining(parts, body, bones, slot, offset, color, keep=0.4):
    """Under `parts`, a thin layer of the skin of `bones` itself, `offset`
    off it and weighted as it (fit_meshy_armor's lining): where the body
    bulges through the garment in a pose, leather shows instead of flesh."""
    points = np.concatenate([p.points for p in parts])
    offsets = np.cumsum([0] + [len(p.points) for p in parts])
    tris = np.concatenate([p.triangles + o for p, o in zip(parts, offsets[:-1])])
    mesh = bpy.data.meshes.new("garment")
    mesh.from_pydata(points.tolist(), [], tris.tolist())
    garment = bpy.data.objects.new("garment", mesh)
    bpy.context.scene.collection.objects.link(garment)
    lined = fit.liner(garment, body, bones, offset)
    bpy.data.objects.remove(garment)
    bpy.data.meshes.remove(mesh)
    if lined is None:
        return []
    fit.decimate(lined, keep)
    influences, weights = fit.skin_liner(lined, body, slot, offset)
    lined.data.calc_loop_triangles()
    tris = np.array([list(t.vertices) for t in lined.data.loop_triangles], dtype=np.int64)
    p = fit.coords(lined)
    bpy.data.meshes.remove(lined.data)
    uv = p[:, [0, 2]][tris]
    rgba = np.broadcast_to(np.array([*color, 1.0]), (len(tris), 3, 4)).copy()
    part = Part("leather", p, tris, None, uv, rgba)
    part.bones, part.weights = influences, weights
    return [part]


def mitten(body, side, clearance=0.007, cuff=(0.12, 0.034, 0.042), opening=0.085):
    """One mitten, the palm and the back sewn together round the edge: the
    convex hull of the palm and the four fingers (a pouch) joined to the
    thumb and to the cuff, a capsule `cuff[0]` metres up the forearm
    (radius `cuff[1]` at the wrist, `cuff[2]` at its end), `clearance` off
    the skin and open `opening` metres up the forearm. Labels: 0 the back,
    21 the palm, 22 the cuff. Returns it and the hand's frame (wrist,
    forearm, palm, centre)."""
    j = lambda name: body.joint(side + name)
    wrist = j("Hand")
    knuckles = np.mean([j("Hand" + f + "1") for f in ("Index", "Middle", "Ring", "Pinky")], axis=0)
    tips = {f: j("Hand" + f + "4") for f in ("Index", "Middle", "Ring", "Pinky", "Thumb")}
    along = normalized(knuckles - wrist)
    # The palm faces the side the thumb stands out on.
    hand = body.points[np.isin(body.top, limb_bones(body, side, "Hand"))]
    centre = hand.mean(axis=0)
    _, _, axes = np.linalg.svd(hand - centre)
    palm = axes[2] if axes[2] @ (j("HandThumb3") - centre) > 0 else -axes[2]
    forearm = normalized(j("ForeArm") - wrist)
    # Pouch: palm and the four fingers, as one; the thumb; the cuff.
    cloud = [sphere_points(j("Hand" + f + str(k)), 0.0135, 30)
             for f in ("Index", "Middle", "Ring", "Pinky") for k in (1, 2, 3, 4)]
    cloud.append(sphere_points(tips["Middle"] + along * 0.008, 0.012, 30))
    cloud.append(sphere_points(wrist + along * 0.025 + palm * 0.006, 0.036, 60))
    pouch = np.concatenate(cloud)
    thumb = capsule_points(j("HandThumb1"), tips["Thumb"] + normalized(tips["Thumb"] - j("HandThumb3")) * 0.006,
                           0.02, 0.0145)
    sleeve = capsule_points(wrist + along * 0.015, wrist + forearm * cuff[0], cuff[1], cuff[2])
    m = solid([pouch, thumb, sleeve], 0.0075, 6)
    m.attrs["weights"] = np.zeros((len(m.points), 1))
    clear = np.full(len(m.points), clearance)
    for _ in range(3):
        push_off(m, body, clear)
        m.smooth(0.3, 2)
    push_off(m, body, clear)
    # The opening up the forearm, a little lower on the inside of the wrist.
    s = (m.points - wrist) @ forearm
    m.cut(s - opening - 0.012 * ((m.points - wrist) @ palm > 0))
    # Leather palm (and the inside of the thumb), the back and the cuff.
    across = (m.points - centre) @ palm
    m.cut(across - 0.002 + 0.004 * wobble(m.points, SEED + 20, 8.0, 1.0), 21)
    s = (m.points - wrist) @ forearm
    m.cut(s - 0.03, 22)
    m.keep(np.ones(len(m.triangles), bool))
    return m, wrist, forearm, palm


def wrist_strap(bvh, wrist, forearm, palm, bead_color=None, tusk_color=None):
    """A strap round the wrist of a mitten (`bvh`), knotted on the back;
    with beads strung on it, a tusk hanging from its knot."""
    ring = []
    for k in range(48):
        a = 2 * math.pi * k / 48
        u = normalized(np.cross(forearm, palm))
        d = palm * math.cos(a) + u * math.sin(a)
        origin = wrist + forearm * 0.018 + d * 0.15
        location, normal, _, _ = bvh.ray_cast(Vector(origin), Vector(-d), 0.2)
        if location is not None:
            ring.append((np.array(location), np.array(normal)))
    if len(ring) <= 8:
        return []
    rp = smooth_polyline(np.array([r[0] + r[1] * 0.004 for r in ring]), 3, closed=True)
    rn = normalized(np.array([r[1] for r in ring]))
    k = int(np.argmax(rp @ -palm))
    out = [strap(rp, rn, 0.014, 0.003, BELT, closed=True)] + knot_and_tails(rp[k], rn[k], BELT, [(0.05, 0.006)])
    if bead_color is not None:
        out += beads(rp + rn * 0.0045, 0.0075, 0.0028, bead_color, closed=True)
    if tusk_color is not None:
        out += tusk(rp[k] + rn[k] * 0.012, -forearm, rn[k], 0.035, tusk_color)
    return out


## The mittens' look (as MANTLE): the cuff's fur, the back's and the
## palm's leather; a bone plate on the back, beads on the strap, a tusk.
MITTENS = {"cuff": BROWN, "back": SKIRT_HIDE, "palm": HIDE, "hair": 0.03, "plates": None, "beads": None,
           "tusks": None}


def mittens(env, body, style=None):
    """Leather mittens, the palm and the back sewn together round the edge,
    with a cuff of fur up the forearm and a strap round the wrist.
    `style`: MITTENS's keys."""
    st = {**MITTENS, **(style or {})}
    parts = []
    glove = []
    cuffs = []
    for side in fit.SIDES:
        first = len(parts)
        m, wrist, forearm, palm = mitten(body, side)
        bvh = bvh_of(m)

        def colors(q, labels):
            out = np.where((labels == 21)[:, None], np.array(st["palm"]), np.array(st["back"]))
            out = np.where((labels == 22)[:, None], np.array(st["cuff"]), out)
            return out * (1.0 + wobble(q, SEED + 21, 10.0, 0.1))[:, None]
        parts += pelt_parts(m, colors, flesh=0.02, bare=[0, 21])
        parts += stitches(seam_lines(m, [(0, 21), (22, 21)]), bvh, 0.01, 0.008, 0.0011, 0.0005, SINEW)
        cuffs.append((m, wrist, forearm, colors))
        parts += wrist_strap(bvh, wrist, forearm, palm, st["beads"], st["tusks"])
        if st["plates"] is not None:
            # Two plates side by side on the back of the hand.
            u = normalized(np.cross(forearm, palm))
            row = []
            for off in (-0.019, 0.019):
                location = bvh.ray_cast(Vector(wrist - forearm * 0.06 + u * off - palm * 0.12), Vector(palm), 0.25)[0]
                if location is not None:
                    row.append(np.array(location))
            parts += plates([np.array(row)], (0.034, 0.05), 0.0035, st["plates"], bvh=bvh, up=-forearm)[0]
        hand = [side + "Hand"] + [f for f in fit.FINGERS if f.startswith(side)]
        glove += lining(parts[first:], body, hand, "hands", 0.002, BELT)
    ao = occlusion(parts, body)
    for part, shade in zip(parts, ao):
        if shade is not None:
            darken(part, shade)
    # The fur of the cuffs, over the wrist and hanging from their edge.
    rng = np.random.default_rng(SEED + 2)
    for m, wrist, forearm, colors in cuffs:
        cuff = Mesh(m.points, m.triangles[m.labels == 22], labels=m.labels[m.labels == 22]).compact()
        normals = cuff.normals()
        brown = lambda q, l: np.array(st["cuff"])[None, :] * (1.0 + wobble(q, SEED + 22, 8.0, 0.12))[:, None]
        parts += fur_coat(cuff, normals, brown, rng, 9000, lambda q: np.full(len(q), st["hair"]), 0.03, row_long=1,
                          skip_edge=lambda q, w=wrist, f=forearm: (q - w) @ f < 0.05)
    return parts + glove, [(parts, {"mitten": True, "weight_radius": 0.018}, "hands")]


def around_leg(bvh, ankle, knee, angle, z, lift):
    """The point of a surface round the leg (between `ankle` and `knee`
    joints) at `angle` and height `z`, `lift` off it, or None."""
    t = (z - ankle[2]) / (knee[2] - ankle[2])
    centre = ankle + (knee - ankle) * t
    direction = np.array([math.sin(angle), -math.cos(angle), 0.0])
    origin = np.array([centre[0], centre[1], z]) + direction * 0.3
    location, normal, _, _ = bvh.ray_cast(Vector(origin), Vector(-direction), 0.3)
    if location is None:
        return None
    return np.array(location) + np.array(normal) * lift


def moccasin(env, body, side, top):
    """A leather moccasin on the foot of `side`, up to `top` (m, higher at
    the front): the sole wraps up to a welt (higher at the heel), the vamp
    over the instep gathered into it with a puckered seam. Lined with the
    foot's skin. Returns its parts and the lining's."""
    m = env.mesh()
    mine = on_limb(m, body, side, "Leg", "Foot", "Toe")
    ankle = body.joint(side + "Foot")
    a = np.arctan2(m.points[:, 0] - ankle[0], -(m.points[:, 1] - ankle[1]))
    field = np.maximum(m.points[:, 2] - (top + 0.015 * np.cos(a)), 0.5 - mine)
    m.cut(field)
    m.keep(np.ones(len(m.triangles), bool))
    best = max(islands(m.triangles, len(m.points)), key=lambda mask: mask.sum())
    m.keep(best)
    # Roomy over the toes and the instep: they bend up into it as the foot rolls.
    toes = smoothstep(ankle[1] - 0.03, ankle[1] - 0.12, m.points[:, 1])
    clearance = 0.007 + 0.01 * toes
    inflate(m, body, clearance, rounds=14, start=clearance)
    # A flat sole on the ground.
    z = m.points[:, 2]
    n = m.normals()
    low = smoothstep(0.03, 0.0, z) * smoothstep(-0.2, -0.6, n[:, 2])
    m.points[:, 2] = z * (1.0 - low) + (-0.003) * low
    # The sole wraps up to the welt (higher at the heel); the vamp over
    # the instep is gathered into it.
    toe = body.joint(side + "ToeBase")
    heel_up = smoothstep(ankle[1] - 0.02, ankle[1] + 0.06, m.points[:, 1])
    welt = 0.032 + 0.022 * heel_up + 0.003 * np.sin(m.points[:, 0] * 220.0)
    m.cut(m.points[:, 2] - welt, 31)
    instep = np.hypot(m.points[:, 0] - toe[0], (m.points[:, 1] - toe[1]) * 0.7)
    m.cut(0.065 - instep - 0.5 * np.maximum(m.points[:, 2] - 0.09, 0.0), 32, inside=[31])
    bvh = bvh_of(m)

    def hide(q, labels):
        out = np.array([{0: SOLE, 31: SKIRT_HIDE, 32: HIDE}.get(int(l), HIDE) for l in labels])
        return out * (1.0 + wobble(q, SEED + 31, 8.0, 0.1))[:, None]
    shell = pelt_parts(m, hide, flesh=0.02, bare=[0, 31, 32])
    parts = shell + stitches(seam_lines(m, [(31, 32)]), bvh, 0.009, 0.01, 0.0013, 0.001, SINEW)
    parts += stitches(seam_lines(m, [(0, 31), (0, 32)]), bvh, 0.012, 0.008, 0.0012, 0.0008, SINEW)
    # What of the foot bulges through as the toes bend shows leather.
    foot = [side + b for b in ("Foot", "ToeBase", "Toe_End") if fit.BONE_PREFIX + side + b in body.index]
    return parts, lining(shell, body, foot, "feet", 0.002, SKIRT_HIDE, keep=0.5)



## The moccasins' look (as MANTLE): the wrap's fur; plates down the front
## of the shin, beads on the tie under the knee, a tusk from its knot.
MOCCASINS = {"wrap": BROWN, "hair": 0.032, "plates": None, "beads": None, "tusks": None}


def moccasins(env, body, style=None):
    """Leather moccasins gathered over the instep with a puckered seam, and a
    pelt wrapped round each shin over their tops, bound with two thongs
    that cross up it and tied below the knee. `style`: MOCCASINS's keys."""
    st = {**MOCCASINS, **(style or {})}
    rng = np.random.default_rng(SEED + 3)
    parts = []
    wraps = []
    linings = []
    for side in fit.SIDES:
        ankle = body.joint(side + "Foot")
        knee = body.joint(side + "Leg")
        shell, lined = moccasin(env, body, side, 0.14)
        parts += shell
        linings += lined
        # The pelt round the shin, from over the moccasin to below the knee.
        w = env.mesh()
        mine = on_limb(w, body, side, "Leg", "Foot", "Toe")
        a = np.arctan2(w.points[:, 0] - ankle[0], -(w.points[:, 1] - ankle[1]))
        top = 0.37 + 0.02 * np.cos(a) - lobes(a, [(1.0, 0.25, 0.025), (-2.2, 0.3, 0.02)]) \
            + wobble(w.points, SEED + 32, 5.0, 0.008)
        bottom = 0.095 + 0.015 * np.cos(a) + wobble(w.points, SEED + 33, 6.0, 0.006)
        w.cut(np.maximum(np.maximum(w.points[:, 2] - top, bottom - w.points[:, 2]), 0.5 - mine))
        best = max(islands(w.triangles, len(w.points)), key=lambda mask: mask.sum())
        w.keep(best)
        clearance = np.full(len(w.points), 0.018)
        inflate(w, body, clearance, rounds=16, start=clearance)
        w.labels[:] = 33
        wolf = lambda q, l: np.array(st["wrap"])[None, :] * (1.0 + wobble(q, SEED + 34, 8.0, 0.12))[:, None]
        parts += pelt_parts(w, wolf, flesh=0.03)
        # Two thongs crossing up it, tied round its top.
        wbvh = bvh_of(w)
        lines = []
        for sign in (1.0, -1.0):
            curve = []
            for t in np.linspace(0.0, 1.0, 60):
                q = around_leg(wbvh, ankle, knee, math.pi + sign * 2 * math.pi * 1.75 * t, 0.12 + 0.2 * t, 0.006)
                if q is not None:
                    curve.append(q)
            if len(curve) > 4:
                curve = smooth_polyline(np.array(curve), 2)
                parts.append(tube_part("lace", curve, 0.0028, BELT))
                lines.append(curve)
        ring = [around_leg(wbvh, ankle, knee, 2 * math.pi * k / 40, 0.335, 0.007) for k in range(40)]
        ring = np.array([q for q in ring if q is not None])
        parts.append(tube_part("lace", np.vstack([ring, ring[:1]]), 0.003, BELT, caps=False))
        front = around_leg(wbvh, ankle, knee, 0.0, 0.335, 0.008)
        parts += knot_and_tails(front, normalized(front - np.array([*knee[:2], 0.335])), BELT, [(0.07, 0.008)])
        plated = np.zeros((0, 3))
        if st["plates"] is not None:
            # Two columns of plates down the front of the shin, under the thongs.
            rows = [np.array([q for q in (around_leg(wbvh, ankle, knee, a, z, 0.0) for a in (-0.21, 0.21))
                              if q is not None]) for z in (0.165, 0.215, 0.265)]
            made, plated = plates(rows, (0.03, 0.046), 0.0035, st["plates"], bvh=wbvh)
            parts += made
        if st["beads"] is not None:
            parts += beads(np.vstack([ring, ring[:1]]), 0.0085, 0.0034, st["beads"])
        if st["tusks"] is not None:
            out = normalized(front - np.array([*knee[:2], 0.335]))
            parts += tusk(front + out * 0.008 - np.array([0.0, 0.0, 0.01]), [0.0, 0.0, -1.0], out, 0.05, st["tusks"])
        wraps.append((w, np.concatenate(lines) if lines else np.zeros((0, 3)), plated))
    ao = occlusion(parts, body)
    for part, shade in zip(parts, ao):
        if shade is not None:
            darken(part, shade)
    for w, thongs, plated in wraps:
        normals = w.normals()
        colors = lambda q, l: np.array(st["wrap"])[None, :] * (1.0 + wobble(q, SEED + 34, 8.0, 0.12))[:, None]
        parts += fur_coat(w, normals, colors, rng, 7000, lambda q: np.full(len(q), st["hair"]), 0.04, row_long=1,
                          avoid=lambda q, t=thongs, c=plated: (distance_to(q, t) < 0.012) | (distance_to(q, c) < 0.03))
    return parts + linings, [(parts, {"weight_radius": 0.014}, "feet")]


# --- The heavy set -------------------------------------------------------------

## Caribou hides for the coat, pieced: mid on the front, pale at the sides,
## dark on the back; a wolverine's for the ruff, dark with a pale band.
CARIBOU = (0.3, 0.228, 0.16)
CARIBOU_PALE = (0.43, 0.36, 0.27)
CARIBOU_DARK = (0.165, 0.122, 0.088)
WOLVERINE = (0.11, 0.08, 0.055)
WOLVERINE_BAND = (0.3, 0.22, 0.14)


def sleeve(env, body, side, top, clearance):
    """A long sleeve of the arm on `side`: the arm from `top` metres down it
    to the wrist, `clearance(t)` off the skin (t: 0 at the top, 1 at the
    wrist). Labelled 0; the band round the cuff, 2."""
    m = env.mesh()
    wrist = body.joint(side + "Hand")
    elbow = body.joint(side + "ForeArm")
    shoulder = body.joint(side + "Arm")
    down = normalized(wrist - elbow)
    beyond = (m.points - wrist) @ down - 0.006
    m.cut(np.maximum(-arm_field(m, env, side, lambda phi: top + 0.0 * phi), beyond))
    best = max(islands(m.triangles, len(m.points)), key=lambda k: k.sum())
    m.keep(best)
    reach = np.linalg.norm(wrist - shoulder)
    t = np.clip(np.linalg.norm(m.points - shoulder, axis=1) / reach, 0.0, 1.0)
    clear = clearance(t)
    inflate(m, body, clear, rounds=16, start=clear)
    m.labels[:] = 0
    cuff = (m.points - wrist) @ down + 0.05 + wobble(m.points, SEED + 70, 9.0, 0.006)
    m.cut(cuff, 2)
    return m


## How a heavy set looks (each piece takes the keys it uses; these are the
## caribou's and the wolverine's, the others are in the variants' sets):
## the tones of the coat's panels (front 0, back 1, the bands 2, sides 4),
## the ruff's fur and its band, how long and thick the hair is, how much
## lower the ruff comes, the toggle's colour, and what is sewn on: antler
## lamellae, ivory beads (their colour, or None).
COAT = {"tones": {0: CARIBOU, 1: CARIBOU_DARK, 2: CREAM, 4: CARIBOU_PALE}, "ruff": (WOLVERINE, WOLVERINE_BAND),
        "hair": (0.03, 0.008), "density": 1000, "ruff_hair": 0.07, "ruff_edge": 0.085, "ruff_density": 3200,
        "ruff_drop": 0.0, "toggle": BONE, "lamellae": None, "beads": None}


def coat(env, body, style=None):
    """A pullover coat of caribou hides with the hair out, to mid-thigh,
    with long sleeves: pieced dark on the back and pale at the sides, cream
    bands round the hem and the cuffs. A ruff of long dark fur over the
    shoulders, a wide belt wound twice with a bone toggle, a pouch.
    `style`: COAT's keys (lamellae over the chest, the back and the skirt;
    beads along the bands)."""
    st = {**COAT, **(style or {})}
    rng = np.random.default_rng(SEED + 4)
    belt_z = 1.11
    hem = lambda a: 0.68 + 0.018 * math.cos(a) + 0.006 * math.sin(3 * a + 1)
    shirt = tunic(env, body, belt_z, hem, lambda phi: 0.07 + 0.0 * phi, 0.055)
    shirt.labels[:] = 0
    p = shirt.points
    a = torso_angle(p)
    # Panels: the back, the sides, the band round the hem.
    shirt.cut(math.cos(2.15) - np.cos(a) + wobble(p, SEED + 71, 6.0, 0.04), 1)
    p = shirt.points
    a = torso_angle(p)
    shirt.cut(np.abs(np.sin(a)) - 0.82 + wobble(p, SEED + 72, 6.0, 0.05), 4, inside=[0])
    p = shirt.points
    a = torso_angle(p)
    shirt.cut(np.array([hem(x) for x in a]) + 0.075 + wobble(p, SEED + 73, 7.0, 0.008) - p[:, 2], 2)

    tones = st["tones"]

    def caribou(q, labels):
        tone = np.array([{1: tones[1], 2: tones[2], 4: tones[4]}.get(int(l), tones[0]) for l in labels])
        return tone * (1.0 + wobble(q, SEED + 74, 7.0, 0.12))[:, None]
    hung = pelt_parts(shirt, caribou, flesh=0.03)
    sleeves = [sleeve(env, body, side, 0.03, lambda t: 0.02 + 0.01 * t) for side in fit.SIDES]
    fixed = []
    for m in sleeves:
        fixed += pelt_parts(m, caribou, flesh=0.03)

    # The ruff, over the shoulders and down the upper arms, its edge uneven.
    def low(p, a):
        edge = 1.33 - st["ruff_drop"] - 0.05 * (1.0 - np.cos(a)) * 0.5 \
            - lobes(a, [(0.0, 0.2, 0.03), (1.2, 0.2, 0.025), (-1.3, 0.2, 0.025), (math.pi, 0.25, 0.035)])
        return edge + wobble(p, SEED + 75, 5.0, 0.012)

    def cap(phi):
        return 0.15 + st["ruff_drop"] * 1.5 + 0.03 * np.cos(phi) + lobes(phi, [(0.8, 0.3, 0.025), (-1.5, 0.3, 0.02)])
    ruff = wolf_pelt(env, body, low, cap, 0.042)
    ruff.labels[:] = 5
    ruff_normals = ruff.normals()
    neck_axis = body.joint("Neck")
    neckline = lambda q: np.hypot(q[:, 0] - neck_axis[0], q[:, 1] - neck_axis[1]) < 0.13
    rim = [l for l in ruff.loops() if not neckline(ruff.points[l]).all()]
    rim = ruff.points[np.concatenate(rim)] if rim else np.zeros((0, 3))

    def wolverine(q, labels):
        band = smoothstep(0.07, 0.03, distance_to(q, rim))
        base = np.array(st["ruff"][0])[None, :] * (1 - band[:, None]) + np.array(st["ruff"][1]) * band[:, None]
        return base * (1.0 + wobble(q, SEED + 76, 6.0, 0.12))[:, None]
    fixed += pelt_parts(ruff, wolverine)

    # The belt, wound twice, a bone toggle in front and a pouch on the right hip.
    bvh = bvh_of(shirt)
    belt = []
    for turn, dz in enumerate((0.0, -0.036)):
        ring, ring_n = ring_on(bvh, TORSO_AXIS, lambda x, dz=dz: belt_z + dz - 0.01 * math.cos(x))
        ring = smooth_polyline(ring + ring_n * (0.004 + 0.003 * turn), 3, closed=True)
        ring_n = normalized(smooth_polyline(ring_n, 3, closed=True))
        belt.append(strap(ring, ring_n, 0.032, 0.005, tuple(c * (1.0 - 0.1 * turn) for c in BELT), closed=True))
    ring, ring_n = ring_on(bvh, TORSO_AXIS, lambda x: belt_z - 0.018 - 0.01 * math.cos(x))
    k = int(len(ring) * 0.97)
    at, n = ring[k] + ring_n[k] * 0.012, ring_n[k]
    side = normalized(np.cross(n, [0.0, 0.0, 1.0]))
    belt.append(ellipsoid(at + n * 0.006, [side * 0.026, np.array([0.0, 0.0, 0.007]), n * 0.007], st["toggle"]))
    loop = np.array([at + side * (0.012 * math.cos(t)) + np.array([0.0, 0.0, 0.012 * math.sin(t)]) + n * 0.004
                     for t in np.linspace(0.0, 2 * math.pi, 13)])
    belt.append(tube_part("lace", loop, 0.0025, SINEW, closed=True, caps=False))
    side_k = int(len(ring) * 0.7)
    belt += pouch(ring[side_k] + ring_n[side_k] * 0.012, ring_n[side_k], np.array([0.0, 0.0, -1.0]), HIDE)
    fixed += belt
    sewn = np.zeros((0, 3))
    if st["lamellae"] is not None:
        # Rows of lamellae laced over the chest and the back (not under the
        # arms) and round the skirt, clear of the pouch.
        pouch_a = torso_angle(ring[[side_k]])[0]
        clear = lambda a: np.abs(np.angle(np.exp(1j * (a - pouch_a)))) > 0.45
        rows = plate_rows(bvh, TORSO_AXIS, [1.255, 1.21, 1.165], lambda a: clear(a) & (np.abs(np.sin(a)) < 0.75),
                          0.034)
        made, sewn = plates(rows, (0.031, 0.046), 0.004, st["lamellae"], bvh=bvh, lift=0.006)
        hung += made
        # Round the skirt they hang flat over its flutes, each row clear of
        # the outermost of them near it.
        rows = plate_rows(bvh, TORSO_AXIS, [1.035, 0.99, 0.945, 0.9], clear, 0.034)
        axis = np.array([TORSO_AXIS[0], TORSO_AXIS[1], 0.0])
        out = [normalized((r - axis) * np.array([1.0, 1.0, 0.0])) for r in rows]
        for i, (r, o) in enumerate(zip(rows, out)):
            radius = np.hypot(r[:, 0] - axis[0], r[:, 1] - axis[1])
            reach = np.array([radius[max(j - 1, 0):j + 2].max() for j in range(len(r))])
            rows[i] = axis + o * (reach + 0.007)[:, None] + np.array([0.0, 0.0, 1.0]) * r[:, 2:3]
        made, hanging = plates(rows, (0.031, 0.046), 0.004, st["lamellae"], normals=out, lift=0.0)
        hung += made
        sewn = np.vstack([sewn, hanging])
    if st["beads"] is not None:
        # Beads along the top of the bands round the hem and the cuffs.
        for mesh, labels, group in ((shirt, [(0, 2), (1, 2), (4, 2)], hung), (sleeves[0], [(0, 2)], fixed),
                                    (sleeves[1], [(0, 2)], fixed)):
            mesh_bvh = bvh_of(mesh)
            for line in seam_lines(mesh, labels):
                on = []
                for q in line:
                    location, normal = surface_frame(mesh_bvh, q)
                    on.append(location + normal * 0.005)
                on = np.array(on)
                group += beads(on, 0.01, 0.0036, st["beads"])
                sewn = np.vstack([sewn, on])

    # Shadows between the layers, then the hair.
    parts = hung + fixed
    ao = occlusion(parts, body)
    for part, shade in zip(parts, ao):
        if shade is not None:
            darken(part, shade)
    under_ruff = lambda q: distance_to(q, ruff.points) < 0.04
    on_belt = lambda q: np.abs(q[:, 2] - (belt_z - 0.018)) < 0.045
    shade_at = occlusion_field(parts, body, shirt, shirt.normals())
    on_sewn = lambda q: distance_to(q, sewn) < 0.03
    hair = st["hair"]
    hung += fur_coat(shirt, shirt.normals(), lambda q, l: caribou(q, l) * shade_at(q)[:, None], rng, st["density"],
                     lambda q: hair[0] + hair[1] * (q[:, 1] > 0.0), 0.035,
                     skip_edge=lambda q: q[:, 2] > 1.2, avoid=lambda q: under_ruff(q) | on_belt(q) | on_sewn(q))
    for m, wrist in zip(sleeves, [body.joint(s + "Hand") for s in fit.SIDES]):
        normals = m.normals()
        shade_at = occlusion_field(parts, body, m, normals)
        fixed += fur_coat(m, normals, lambda q, l: caribou(q, l) * shade_at(q)[:, None], rng, st["density"],
                          lambda q: np.full(len(q), hair[0]), 0.028,
                          skip_edge=lambda q, w=wrist: np.linalg.norm(q - w, axis=1) > 0.15,
                          avoid=lambda q: under_ruff(q) | on_sewn(q))
    shade_at = occlusion_field(parts, body, ruff, ruff_normals)
    fixed += fur_coat(ruff, ruff_normals, lambda q, l: wolverine(q, l) * shade_at(q)[:, None], rng,
                      st["ruff_density"], lambda q: np.full(len(q), st["ruff_hair"]), st["ruff_edge"],
                      centre=neck_axis, skip_edge=neckline)
    # Long enough for a thigh coming forward to go through it: its front
    # rides on them, each side on its own.
    return hung + fixed, [(hung, {"hang": True, "thighs": [0.95, 0.3], "split": 0.05, "weight_radius": 0.04},
                           "chest"),
                          (fixed, {"sleeves": True, "weight_radius": 0.05}, "chest")]


## The breeches' look (as COAT): the fur (and darker down the leg), the
## leather inside the legs and on the knees; lamellae down the thighs.
BREECHES = {"fur": (BROWN, BROWN_DARK), "inner": SKIRT_HIDE, "patch": HIDE, "hair": (0.032, 0.01), "density": 2200,
            "lamellae": None}


def breeches(env, body, style=None):
    """Breeches of a bear's hide with the hair out, from the hips to under
    the knees: the inside of the legs and the crotch leather, as are patches
    sewn on the knees; gathered at the waist by a drawstring and tied under
    the knees. `style`: BREECHES's keys."""
    st = {**BREECHES, **(style or {})}
    rng = np.random.default_rng(SEED + 5)
    centre = body.joint("Hips")[:2]
    waist = lambda a: 1.03 + 0.03 * (1.0 - math.cos(a)) * 0.5
    m = env.mesh()
    p = m.points
    a = np.arctan2(p[:, 0] - centre[0], -(p[:, 1] - centre[1]))
    knees = {side: body.joint(side + "Leg") for side in fit.SIDES}
    hem = 0.45 + 0.02 * np.cos(np.arctan2(p[:, 0] - np.where(p[:, 0] > 0, knees["Left"][0], knees["Right"][0]),
                                          -(p[:, 1] - knees["Left"][1]))) + wobble(p, SEED + 80, 6.0, 0.006)
    away = on_limb(m, body, "Left", "Arm", "Hand") + on_limb(m, body, "Right", "Arm", "Hand")
    field = np.maximum(np.maximum(p[:, 2] - np.array([waist(x) for x in a]), hem - p[:, 2]), away - 0.5)
    m.cut(field)
    best = max(islands(m.triangles, len(m.points)), key=lambda k: k.sum())
    m.keep(best)
    # Close at the waist, eased down the thighs, roomy at the hem (over a
    # boot's top or a wrap).
    z = m.points[:, 2]
    clearance = 0.012 + 0.008 * smoothstep(0.98, 0.85, z) + 0.012 * smoothstep(0.6, 0.46, z)
    inflate(m, body, clearance, start=clearance)
    m.labels[:] = 0
    # The leather inside each leg, up into the crotch (where the legs part).
    p = m.points
    between = body.points[(np.abs(body.points[:, 0] - centre[0]) < 0.015) & (body.points[:, 2] > 0.6)]
    crotch = between[:, 2].min()
    inner = np.zeros(len(p))
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        hip, knee = body.joint(side + "UpLeg"), knees[side]
        t = np.clip((p[:, 2] - knee[2]) / (hip[2] - knee[2]), 0.0, 1.0)
        axis = knee + (hip - knee) * t[:, None]
        mine = np.sign(p[:, 0]) == sign
        inner = np.where(mine, sign * (axis[:, 0] - p[:, 0]) / np.maximum(np.hypot(p[:, 0] - axis[:, 0],
                                                                                    p[:, 1] - axis[:, 1]), 1e-6),
                         inner)
    inner = np.maximum(inner - 0.62 + wobble(p, SEED + 81, 6.0, 0.05),
                       np.minimum(0.06 - np.abs(p[:, 0] - centre[0]), crotch + 0.03 - p[:, 2]))
    m.cut(inner, 11)
    # Leather patches on the knees.
    for side in fit.SIDES:
        knee = knees[side]
        p = m.points
        front = np.array([knee[0], knee[1] - 0.06, knee[2] + 0.01])
        d = (p - front) * np.array([1.0, 0.6, 0.85])
        m.cut(0.05 - np.linalg.norm(d, axis=1) + wobble(p, SEED + 82, 14.0, 0.004), 12, inside=[0])
    bvh = bvh_of(m)

    def bear(q, labels):
        low = smoothstep(0.75, 0.5, q[:, 2])
        base = np.array(st["fur"][0])[None, :] * (1 - 0.35 * low[:, None]) + np.array(st["fur"][1]) * 0.35 * low[:, None]
        base = np.where((labels == 11)[:, None], np.array(st["inner"]), base)
        base = np.where((labels == 12)[:, None], np.array(st["patch"]), base)
        return base * (1.0 + wobble(q, SEED + 83, 7.0, 0.12))[:, None]
    parts = pelt_parts(m, bear, flesh=0.03, bare=[11, 12])
    parts += stitches(seam_lines(m, [(0, 11)]), bvh, 0.013, 0.009, 0.0012, 0.0008, SINEW)
    parts += stitches(seam_lines(m, [(0, 12), (11, 12)]), bvh, 0.009, 0.008, 0.0012, 0.0008, SINEW)
    # The drawstring round the waist, its ends hanging in front; a thong
    # round each leg under the knee.
    ring, ring_n = ring_on(bvh, centre, lambda x: waist(x) - 0.022)
    ring = smooth_polyline(ring + ring_n * 0.004, 3, closed=True)
    parts.append(tube_part("lace", np.vstack([ring, ring[:1]]), 0.0032, BELT, caps=False))
    k = int(np.argmin(np.abs(torso_angle(ring))))
    parts += knot_and_tails(ring[k], normalized(smooth_polyline(ring_n, 3, closed=True)[k]), BELT,
                            [(0.09, 0.012), (0.07, -0.01)], size=0.5)
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        ankle, knee = body.joint(side + "Foot"), knees[side]
        leg = (np.sign(m.points[m.triangles, 0]) == sign).all(axis=1) & (m.points[m.triangles, 2] < 0.7).all(axis=1)
        leg_bvh = BVHTree.FromPolygons([Vector(q) for q in m.points], m.triangles[leg].tolist())
        tie = [around_leg(leg_bvh, ankle, knee, 2 * math.pi * k / 48, 0.5, 0.004) for k in range(48)]
        tie = smooth_polyline(np.array([q for q in tie if q is not None]), 2, closed=True)
        parts.append(tube_part("lace", np.vstack([tie, tie[:1]]), 0.003, BELT, caps=False))
        outside = around_leg(leg_bvh, ankle, knee, (math.pi / 2) * sign, 0.5, 0.004)
        parts += knot_and_tails(outside, normalized(outside - np.array([*knee[:2], 0.5])), BELT, [(0.06, 0.006)],
                                size=0.45)
    sewn = np.zeros((0, 3))
    if st["lamellae"] is not None:
        # Rows of lamellae laced down the front of each thigh.
        rows = []
        for side, sign in (("Left", 1.0), ("Right", -1.0)):
            hip, knee = body.joint(side + "UpLeg"), knees[side]
            leg = (np.sign(m.points[m.triangles, 0]) == sign).all(axis=1)
            leg_bvh = BVHTree.FromPolygons([Vector(q) for q in m.points], m.triangles[leg].tolist())
            for k, z in enumerate((0.84, 0.795, 0.75, 0.705, 0.66)):
                row = [around_leg(leg_bvh, knee, hip, a + 0.11 * (k % 2), z, 0.0) for a in np.linspace(-0.55, 0.44, 5)]
                rows.append(np.array([q for q in row if q is not None]))
        made, sewn = plates(rows, (0.03, 0.044), 0.004, st["lamellae"], bvh=bvh, lift=0.006)
        parts += made
    ao = occlusion(parts, body)
    for part, shade in zip(parts, ao):
        if shade is not None:
            darken(part, shade)
    fur = Mesh(m.points, m.triangles[m.labels == 0], labels=m.labels[m.labels == 0]).compact()
    normals = fur.normals()
    shade_at = occlusion_field(parts, body, fur, normals)
    waist_band = lambda q: q[:, 2] > np.array([waist(x) for x in np.arctan2(q[:, 0] - centre[0],
                                                                            -(q[:, 1] - centre[1]))]) - 0.06
    hair = st["hair"]
    parts += fur_coat(fur, normals, lambda q, l: bear(q, l) * shade_at(q)[:, None], rng, st["density"],
                      lambda q: hair[0] + hair[1] * smoothstep(0.7, 0.5, q[:, 2]), 0.04,
                      skip_edge=lambda q: (q[:, 2] > 0.6),
                      avoid=lambda q: waist_band(q) | (np.abs(q[:, 2] - 0.5) < 0.012) | (distance_to(q, sewn) < 0.03))
    return parts, [(parts, {"weight_radius": 0.04}, "legs")]


## The gauntlets' look (as COAT): the back's and the cuff's fur, the palm,
## how long the hair is on each and from the cuff's edge; lamellae on the
## back of the cuff, beads on the strap.
GAUNTLETS = {"back": CARIBOU, "cuff": WOLVERINE, "palm": HIDE, "hair": (0.016, 0.036), "edge": 0.034,
             "lamellae": None, "beads": None}


def gauntlets(env, body, style=None):
    """Mittens with the hair out on the back (caribou) and a long cuff of
    wolverine fur flaring up the forearm, the palm leather sewn round the
    edge, a strap round the wrist. `style`: GAUNTLETS's keys."""
    st = {**GAUNTLETS, **(style or {})}
    parts = []
    glove = []
    furred = []
    for side in fit.SIDES:
        first = len(parts)
        m, wrist, forearm, palm = mitten(body, side, clearance=0.009, cuff=(0.17, 0.036, 0.05), opening=0.15)
        bvh = bvh_of(m)

        def colors(q, labels):
            out = np.where((labels == 21)[:, None], np.array(st["palm"]), np.array(st["back"]))
            out = np.where((labels == 22)[:, None], np.array(st["cuff"]), out)
            return out * (1.0 + wobble(q, SEED + 90, 10.0, 0.1))[:, None]
        parts += pelt_parts(m, colors, flesh=0.02, bare=[21])
        parts += stitches(seam_lines(m, [(0, 21), (22, 21)]), bvh, 0.01, 0.008, 0.0011, 0.0005, SINEW)
        parts += wrist_strap(bvh, wrist, forearm, palm, st["beads"])
        sewn = np.zeros((0, 3))
        if st["lamellae"] is not None:
            # Rows of lamellae laced across the back of the cuff, up the forearm.
            u = normalized(np.cross(forearm, palm))
            rows = []
            for k, s in enumerate((0.06, 0.102, 0.144)):
                row = []
                for t in np.array([-0.5, 0.0, 0.5]) + 0.25 * (k % 2):
                    d = -palm * math.cos(t) + u * math.sin(t)
                    location = bvh.ray_cast(Vector(wrist + forearm * s + d * 0.15), Vector(-d), 0.2)[0]
                    if location is not None:
                        row.append(np.array(location))
                rows.append(np.array(row))
            made, sewn = plates(rows, (0.028, 0.042), 0.0035, st["lamellae"], bvh=bvh, lift=0.005, up=forearm)
            parts += made
        furred.append((m, wrist, forearm, colors, sewn))
        hand = [side + "Hand"] + [f for f in fit.FINGERS if f.startswith(side)]
        glove += lining(parts[first:], body, hand, "hands", 0.002, BELT)
    ao = occlusion(parts, body)
    for part, shade in zip(parts, ao):
        if shade is not None:
            darken(part, shade)
    # Short hair on the back, long on the cuff and hanging from its edge.
    rng = np.random.default_rng(SEED + 6)
    for m, wrist, forearm, colors, sewn in furred:
        for label, density, length, edge in ((0, 7000, st["hair"][0], None), (22, 7000, st["hair"][1], st["edge"])):
            fur = Mesh(m.points, m.triangles[m.labels == label], labels=m.labels[m.labels == label]).compact()
            normals = fur.normals()
            shade_at = occlusion_field(parts, body, fur, normals)
            near_strap = lambda q, w=wrist, f=forearm, c=sewn: (np.abs((q - w) @ f - 0.018) < 0.012) | \
                (distance_to(q, c) < 0.025)
            parts += fur_coat(fur, normals, lambda q, l, c=colors: c(q, l) * shade_at(q)[:, None], rng, density,
                              lambda q, n=length: np.full(len(q), n), edge or 0.0, row_long=1,
                              skip_edge=(lambda q: np.ones(len(q), bool)) if edge is None else
                              (lambda q, w=wrist, f=forearm: (q - w) @ f < 0.1), avoid=near_strap)
    return parts + glove, [(parts, {"mitten": True, "weight_radius": 0.018}, "hands")]


## The boots' look (as COAT): the tones of the leg (40), its stripes (41)
## and its cuff (42), how long the hair is on the leg and the cuff and
## from its edge; lamellae down the shin, beads on the top thong.
BOOTS = {"tones": {40: CARIBOU, 41: CARIBOU_PALE, 42: WOLVERINE}, "hair": (0.024, 0.05), "edge": 0.055,
         "lamellae": None, "beads": None}


def boots(env, body, style=None):
    """Tall boots: a leather moccasin and, sewn over its top, a leg of
    caribou hide with the hair out up to under the knee, dark down the
    front and the back and pale down the sides, with a cuff of wolverine
    fur round its top; a thong wound round the ankle and one tied under the
    cuff. `style`: BOOTS's keys."""
    st = {**BOOTS, **(style or {})}
    tones = st["tones"]
    rng = np.random.default_rng(SEED + 7)
    parts = []
    legs = []
    linings = []
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        ankle = body.joint(side + "Foot")
        knee = body.joint(side + "Leg")
        shell, lined = moccasin(env, body, side, 0.11)
        parts += shell
        linings += lined
        w = env.mesh()
        mine = on_limb(w, body, side, "Leg", "Foot", "Toe")
        a = np.arctan2(w.points[:, 0] - ankle[0], -(w.points[:, 1] - ankle[1]))
        top = 0.48 + 0.015 * np.cos(a) - lobes(a, [(0.9, 0.3, 0.012), (-2.0, 0.3, 0.012)]) \
            + wobble(w.points, SEED + 91, 5.0, 0.006)
        bottom = 0.075 + 0.02 * np.cos(a) + wobble(w.points, SEED + 92, 6.0, 0.004)
        w.cut(np.maximum(np.maximum(w.points[:, 2] - top, bottom - w.points[:, 2]), 0.5 - mine))
        best = max(islands(w.triangles, len(w.points)), key=lambda mask: mask.sum())
        w.keep(best)
        z = w.points[:, 2]
        clearance = 0.016 + 0.006 * smoothstep(0.15, 0.35, z)
        inflate(w, body, clearance, rounds=16, start=clearance)
        w.labels[:] = 40
        p = w.points
        a = np.arctan2(p[:, 0] - ankle[0], -(p[:, 1] - ankle[1]))
        w.cut(np.abs(np.sin(a)) - 0.88 + wobble(p, SEED + 93, 8.0, 0.03), 41)
        p = w.points
        a = np.arctan2(p[:, 0] - ankle[0], -(p[:, 1] - ankle[1]))
        w.cut(p[:, 2] - (0.405 + 0.015 * np.cos(a)) + wobble(p, SEED + 94, 9.0, 0.004), 42)

        def caribou_leg(q, labels):
            tone = np.array([{41: tones[41], 42: tones[42]}.get(int(l), tones[40]) for l in labels])
            return tone * (1.0 + wobble(q, SEED + 95, 8.0, 0.12))[:, None]
        parts += pelt_parts(w, caribou_leg, flesh=0.03)
        wbvh = bvh_of(w)
        parts += stitches(seam_lines(w, [(40, 41)]), wbvh, 0.012, 0.008, 0.0012, 0.0008, SINEW)
        # A thong wound twice round the ankle; one under the cuff, knotted outside.
        thongs = []
        for z0, turns in ((0.11, 2), (0.39, 1)):
            curve = []
            for t in np.linspace(0.0, 1.0, 44 * turns):
                q = around_leg(wbvh, ankle, knee, 2 * math.pi * turns * t, z0 + 0.014 * t * (turns - 1), 0.004)
                if q is not None:
                    curve.append(q)
            curve = smooth_polyline(np.array(curve), 2)
            parts.append(tube_part("lace", curve, 0.0028, BELT))
            thongs.append(curve)
            outside = around_leg(wbvh, ankle, knee, (math.pi / 2) * sign, z0, 0.004)
            parts += knot_and_tails(outside, normalized(outside - np.array([*ankle[:2], z0])), BELT,
                                    [(0.05, 0.006), (0.04, -0.006)], size=0.45)
            if st["beads"] is not None and turns == 1:
                parts += beads(curve, 0.0085, 0.0033, st["beads"])
        sewn = np.zeros((0, 3))
        if st["lamellae"] is not None:
            # Rows of lamellae laced down the front of the shin.
            rows = [np.array([q for q in (around_leg(wbvh, ankle, knee, a + 0.16 * (k % 2), z, 0.0)
                                          for a in (-0.32, 0.0, 0.32)) if q is not None])
                    for k, z in enumerate((0.16, 0.205, 0.25, 0.295, 0.34))]
            made, sewn = plates(rows, (0.03, 0.044), 0.0035, st["lamellae"], bvh=wbvh, lift=0.006)
            parts += made
        legs.append((w, np.vstack([np.concatenate(thongs), sewn])))
    ao = occlusion(parts, body)
    for part, shade in zip(parts, ao):
        if shade is not None:
            darken(part, shade)
    for w, thongs in legs:
        for labels, density, length, edge in (([40, 41], 3200, st["hair"][0], None),
                                              ([42], 9000, st["hair"][1], st["edge"])):
            rows = np.isin(w.labels, labels)
            fur = Mesh(w.points, w.triangles[rows], labels=w.labels[rows]).compact()
            normals = fur.normals()
            shade_at = occlusion_field(parts, body, fur, normals)
            parts += fur_coat(fur, normals, lambda q, l: caribou_leg(q, l) * shade_at(q)[:, None], rng, density,
                              lambda q, n=length: np.full(len(q), n), edge or 0.025, row_long=1,
                              skip_edge=(lambda q: q[:, 2] > 0.3) if edge is None else (lambda q: q[:, 2] < 0.43),
                              avoid=lambda q, t=thongs: distance_to(q, t) < (0.01 if st["lamellae"] is None else 0.028))
    return parts + linings, [(parts, {"weight_radius": 0.014}, "feet")]


# --- Variants ------------------------------------------------------------------

## The other sets, a style per garment over its defaults (MANTLE, COAT...).
## Light: a boar's bristly pelts with tusks; a red deer's, short-haired,
## with bone plates sewn on; a red fox's, long-haired, with ivory beads.
BOAR_SET = {
    "mantle": {"pelt": {"back": (0.17, 0.15, 0.13), "flank": (0.21, 0.185, 0.16), "belly": (0.27, 0.24, 0.205),
                        "saddle": (0.06, 0.055, 0.05), "legs": (0.08, 0.07, 0.062)},
               "hide": (0.38, 0.31, 0.25), "hair": (0.045, 0.015), "crest": 0.05, "bristle": 0.6, "tusks": TUSK},
    "loincloth": {"skirt": ((0.18, 0.16, 0.14), (0.09, 0.08, 0.07)), "flaps": (0.36, 0.3, 0.25),
                  "hide": (0.38, 0.31, 0.25), "bristle": 0.6, "tusks": TUSK},
    "mittens": {"cuff": (0.17, 0.15, 0.13), "back": (0.36, 0.3, 0.25), "tusks": TUSK},
    "moccasins": {"wrap": (0.17, 0.15, 0.13), "tusks": TUSK},
}
DEER_SET = {
    "mantle": {"pelt": {"back": (0.33, 0.2, 0.115), "flank": (0.37, 0.235, 0.135), "belly": (0.5, 0.44, 0.35),
                        "saddle": (0.2, 0.12, 0.07), "legs": None},
               "hide": (0.58, 0.5, 0.4), "hair": (0.035, 0.01), "legs_at": 0.55, "chest": 1.4, "drop": 0.18,
               "plates": BONE_PLATE},
    "loincloth": {"skirt": ((0.34, 0.21, 0.12), (0.22, 0.14, 0.08)), "flaps": (0.5, 0.42, 0.33),
                  "hide": (0.58, 0.5, 0.4), "hair": (0.028, 0.01), "plates": BONE_PLATE},
    "mittens": {"cuff": (0.33, 0.2, 0.115), "back": (0.5, 0.42, 0.33), "palm": (0.58, 0.5, 0.4),
                "plates": BONE_PLATE},
    "moccasins": {"wrap": (0.33, 0.2, 0.115), "hair": 0.026, "plates": BONE_PLATE},
}
FOX_SET = {
    "mantle": {"pelt": {"back": (0.52, 0.19, 0.05), "flank": (0.55, 0.24, 0.07), "belly": (0.62, 0.58, 0.52),
                        "saddle": (0.36, 0.12, 0.035), "legs": (0.06, 0.05, 0.045)},
               "hair": (0.06, 0.02), "beads": IVORY},
    "loincloth": {"skirt": ((0.52, 0.2, 0.055), (0.34, 0.12, 0.035)), "hair": (0.042, 0.015), "beads": IVORY},
    "mittens": {"cuff": (0.52, 0.19, 0.05), "hair": 0.036, "beads": IVORY},
    "moccasins": {"wrap": (0.52, 0.19, 0.05), "hair": 0.038, "beads": IVORY},
}
## Heavy: a steppe bison's dark wool, long and thick, with a great ruff;
## reindeer with lamellae of antler laced on; an arctic fox's white fur,
## the longest, with ivory beads and toggle.
BISON_SET = {
    "coat": {"tones": {0: (0.15, 0.1, 0.065), 1: (0.09, 0.065, 0.045), 2: (0.26, 0.18, 0.11), 4: (0.2, 0.14, 0.09)},
             "ruff": ((0.07, 0.05, 0.035), (0.19, 0.13, 0.085)), "hair": (0.042, 0.01), "density": 1500,
             "ruff_hair": 0.1, "ruff_edge": 0.11, "ruff_drop": 0.05},
    "breeches": {"fur": ((0.13, 0.09, 0.06), (0.08, 0.058, 0.04)), "hair": (0.042, 0.012), "density": 2600},
    "gauntlets": {"back": (0.15, 0.1, 0.065), "cuff": (0.07, 0.05, 0.035), "hair": (0.02, 0.045), "edge": 0.045},
    "boots": {"tones": {40: (0.15, 0.1, 0.065), 41: (0.21, 0.15, 0.095), 42: (0.07, 0.05, 0.035)},
              "hair": (0.03, 0.06), "edge": 0.065},
}
ANTLER_SET = {
    "coat": {"tones": {0: (0.25, 0.21, 0.165), 1: (0.15, 0.12, 0.09), 2: CREAM, 4: (0.36, 0.31, 0.25)},
             "ruff": ((0.26, 0.235, 0.2), (0.42, 0.38, 0.32)), "lamellae": ANTLER},
    "breeches": {"fur": ((0.22, 0.18, 0.14), (0.14, 0.11, 0.085)), "lamellae": ANTLER},
    "gauntlets": {"back": (0.25, 0.21, 0.165), "cuff": (0.26, 0.235, 0.2), "lamellae": ANTLER},
    "boots": {"tones": {40: (0.25, 0.21, 0.165), 41: (0.36, 0.31, 0.25), 42: (0.26, 0.235, 0.2)},
              "lamellae": ANTLER},
}
ARCTIC_SET = {
    "coat": {"tones": {0: (0.66, 0.64, 0.6), 1: (0.57, 0.55, 0.52), 2: (0.2, 0.16, 0.12), 4: (0.72, 0.7, 0.66)},
             "ruff": ((0.74, 0.72, 0.68), (0.55, 0.53, 0.5)), "hair": (0.04, 0.008), "density": 1400,
             "ruff_hair": 0.08, "toggle": IVORY, "beads": IVORY},
    "breeches": {"fur": ((0.64, 0.62, 0.58), (0.52, 0.5, 0.47)), "inner": (0.36, 0.3, 0.25),
                 "patch": (0.3, 0.24, 0.19), "hair": (0.038, 0.01)},
    "gauntlets": {"back": (0.66, 0.64, 0.6), "cuff": (0.74, 0.72, 0.68), "beads": IVORY},
    "boots": {"tones": {40: (0.64, 0.62, 0.58), 41: (0.2, 0.16, 0.12), 42: (0.74, 0.72, 0.68)}, "beads": IVORY},
}


# --- Main ----------------------------------------------------------------------

LIGHT = {"mantle": mantle, "loincloth": loincloth, "mittens": mittens, "moccasins": moccasins}
HEAVY = {"coat": coat, "breeches": breeches, "gauntlets": gauntlets, "boots": boots}
## Every piece, <set>_<garment>: what makes it and its style.
SETS = [("fur", LIGHT, {}), ("fur", HEAVY, {}), ("boar", LIGHT, BOAR_SET), ("deer", LIGHT, DEER_SET),
        ("fox", LIGHT, FOX_SET), ("bison", HEAVY, BISON_SET), ("antler", HEAVY, ANTLER_SET),
        ("arctic", HEAVY, ARCTIC_SET)]
PIECES = {"%s_%s" % (prefix, name): (make, styles.get(name, {}))
          for prefix, garments, styles in SETS for name, make in garments.items()}


def main():
    body = fit.Body(BODY_JSON)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    envelopes = {}
    for piece_id, (make, style) in PIECES.items():
        if ONLY and piece_id not in ONLY:
            continue
        voxel = ENVELOPE_VOXEL[make.__name__]
        if voxel is not None and voxel not in envelopes:
            envelopes[voxel] = Envelope(body, voxel)
        parts, groups = make(envelopes.get(voxel), body, style)
        for group, entry, slot in groups:
            skin_parts(group, body, entry, slot)
        preview(piece_id, parts, body)
        export(piece_id, parts, body, SEED)


if __name__ == "__main__":
    main()
