#!/usr/bin/env python3
"""Genera el grafo de las vetas de superficie (data/graph_functions/earth_ore_field.tres) desde
"ore_settings" de data/planet/planet_earth.json, y conecta cada una a su capa de peso en el grafo
de la Tierra (earth_terrain_terraces.tres, OutputWeight con layer = type_id).

Cada veta de superficie (las que no llevan "depth_min", que son de cueva) es:

    manchas (Spots3D "ore_spots_<id>", o "ore_spots_<grupo>" si lleva "spot_group") sobre las
    coordenadas deformadas por un ruido común
      × cerca de la superficie (|planet_sdf| / "ore_depth_<id>": de 1 en la superficie a 0 a
        surface_depth metros)
      × su banda de altura, si la lleva ("ore_alt_lo_<id>", "ore_alt_hi_<id>": smoothsteps sobre
        la distancia al centro)

Las de un mismo "spot_group" comparten las manchas (las pone la primera del grupo: semilla, celdas,
radio) y se reparten el sitio por alturas, que no deben pisarse: así cinco vetas cuestan dos redes de
manchas y no cinco (cada Spots3D es lo más caro de la veta).

Los valores (semilla, celdas, radio, profundidad, alturas) los pone Planet._apply_ore_params al
cargar desde el JSON; aquí solo cuenta qué vetas hay, cómo se agrupan y si llevan banda de altura
(se escriben también aquí, para que el fichero sirva tal cual). Después de cambiar eso:

    python3 tools/terrain/build_ore_field.py

El orden de "ore_settings" tiene que ser el de type_id (1, 2, 3...): el shader del terreno coge
la textura de cada mena por su posición (Planet._setup_ore_shader_parameters).
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLANET = os.path.join(ROOT, "data/planet/planet_earth.json")
ORE_FIELD = os.path.join(ROOT, "data/graph_functions/earth_ore_field.tres")
TERRACES = os.path.join(ROOT, "data/graph_functions/earth_terrain_terraces.tres")
ORE_FIELD_UID = "uid://b3rp22i5ldnk8"
# Nodo Function del grafo de la Tierra que llama a earth_ore_field, y donde empiezan los ids de
# sus OutputWeight.
ORE_FUNCTION_NODE = 85
FIRST_WEIGHT_NODE = 83


class Graph:
    def __init__(self):
        self.nodes = {}
        self.connections = []

    def add(self, node_id, kind, gx, gy, **params):
        node = {"auto_connect": False, "gui_position": f"Vector2({gx}, {gy})", "type": kind}
        node.update(params)
        self.nodes[node_id] = node
        return node_id

    def link(self, src, dst, port, src_port=0):
        self.connections.append([src, src_port, dst, port])


def _value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        text = repr(v)
        return text if "." in text or "e" in text else text + ".0"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str) and (v.startswith("Vector2(") or v.startswith("&\"") or v.startswith("SubResource(")):
        return v
    return json.dumps(v)


def _name(text):
    return f'&"{text}"'


def build(surface_ores, radius):
    g = Graph()
    g.add(1, "InputX", 0, 0)
    g.add(2, "InputY", 0, 80)
    g.add(3, "InputZ", 0, 160)
    g.add(4, "CustomInput", 0, 420, name=_name("planet_sdf"))
    # Deformación común: las manchas no salen redondas.
    g.add(10, "FastNoise3D", 200, -120, auto_connect=True, noise='SubResource("ZN_FastNoiseLite_qhap6")',
          x=0.0, y=0.0, z=0.0)
    g.add(11, "Multiply", 420, -120, b=12.0)
    g.link(10, 11, 0)
    for i, axis in enumerate((1, 2, 3)):
        g.add(12 + i, "Add", 620, i * 100)
        g.link(11, 12 + i, 0)
        g.link(axis, 12 + i, 1)
    # Cerca de la superficie: |sdf|.
    g.add(15, "Abs", 620, 480)
    g.link(4, 15, 0)
    # Distancia al centro, solo si alguna veta va por alturas.
    if any("min_height" in ore or "max_height" in ore for ore in surface_ores):
        for i, axis in enumerate((1, 2, 3)):
            g.add(16 + i, "Multiply", 200, 700 + i * 80)
            g.link(axis, 16 + i, 0)
            g.link(axis, 16 + i, 1)
        g.add(19, "Add", 400, 720)
        g.link(16, 19, 0)
        g.link(17, 19, 1)
        g.add(20, "Add", 560, 760)
        g.link(19, 20, 0)
        g.link(18, 20, 1)
        g.add(21, "Sqrt", 720, 760, name=_name("altitude"))
        g.link(20, 21, 0)
    weights = {}
    groups = {}
    for ore in surface_ores:
        if "spot_group" in ore:
            groups.setdefault(ore["spot_group"], []).append(ore)
    row = 0
    for key, members in groups.items():
        _build_group(g, key, members, radius, 100 + row * 20, weights)
        row += len(members) + 1
    for ore in surface_ores:
        if "spot_group" not in ore:
            _build_single(g, ore, radius, 100 + row * 20, weights)
            row += 1
    outputs = []
    for ore in surface_ores:
        tid = int(ore["type_id"])
        out_name = f"ore_{tid:02d}_weight"
        out = g.add(1000 + tid, "CustomOutput", 2200, tid * 120, name=_name(out_name))
        g.link(weights[tid], out, 0)
        outputs.append(out_name)
    return g, outputs


def _gate(g, node_id, gx, gy, depth, name, spots):
    """Las manchas, solo cerca de la superficie: spots · max(0, 1 - |sdf| / depth)."""
    div = g.add(node_id, "Divide", gx, gy, b=float(depth), name=_name(name))
    g.link(15, div, 0)
    near = g.add(node_id + 1, "Subtract", gx + 180, gy, a=1.0)
    g.link(div, near, 1)
    gate = g.add(node_id + 2, "Max", gx + 360, gy, b=0.0)
    g.link(near, gate, 0)
    gated = g.add(node_id + 3, "Multiply", gx + 540, gy)
    g.link(spots, gated, 0)
    g.link(gate, gated, 1)
    return gated


def _spots(g, node_id, gx, gy, ore, name):
    spots = g.add(node_id, "Spots3D", gx, gy, auto_connect=True, cell_size=float(ore.get("cell_size", 400.0)),
                  jitter=float(ore.get("jitter", 0.9)), name=_name(name), seed=int(ore.get("noise_seed", 0)),
                  spot_radius=float(ore.get("spot_radius", 20.0)))
    for i in range(3):
        g.link(12 + i, spots, i)
    return spots


def _build_group(g, key, members, radius, base, weights):
    """Vetas que comparten manchas y se reparten las alturas en franjas seguidas: escalones en cada
    borde ("ore_step_<grupo>_<k>", de abajo arriba) y cada franja es la resta de los suyos. La
    primera del grupo (en el JSON) pone las manchas, la profundidad y la suavidad."""
    first = members[0]
    y = (base - 100) * 13
    spots = _spots(g, base, 880, y, first, f"ore_spots_{key}")
    gated = _gate(g, base + 1, 1060, y + 120, first.get("surface_depth", 10.0), f"ore_depth_{key}", spots)
    ordered = sorted(members, key=lambda o: float(o["min_height"]))
    for low, high in zip(ordered, ordered[1:]):
        if float(low["max_height"]) != float(high["min_height"]):
            sys.exit(f"{key}: las franjas de altura tienen que ir seguidas ({low['name']} acaba en "
                     f"{low['max_height']} y {high['name']} empieza en {high['min_height']})")
    edges = [float(o["min_height"]) for o in ordered] + [float(ordered[-1]["max_height"])]
    soft = max(float(first.get("height_softness", 12.0)), 0.001)
    steps = []
    for k, edge in enumerate(edges):
        steps.append(g.add(base + 5 + k, "Smoothstep", 1060, y + 240 + k * 60,
                           edge0=radius + edge - soft * 0.5, edge1=radius + edge + soft * 0.5,
                           name=_name(f"ore_step_{key}_{k}")))
        g.link(21, steps[-1], 0)
    for k, ore in enumerate(ordered):
        band = g.add(base + 5 + len(edges) + k * 2, "Subtract", 1420, y + 240 + k * 60)
        g.link(steps[k], band, 0)
        g.link(steps[k + 1], band, 1)
        weight = g.add(base + 6 + len(edges) + k * 2, "Multiply", 1780, y + 240 + k * 60)
        g.link(gated, weight, 0)
        g.link(band, weight, 1)
        weights[int(ore["type_id"])] = weight


def _build_single(g, ore, radius, base, weights):
    """Una veta con sus manchas, su profundidad y, si la lleva, su banda de altura."""
    tid = int(ore["type_id"])
    y = (base - 100) * 13
    spots = _spots(g, base, 880, y, ore, f"ore_spots_{tid}")
    gated = _gate(g, base + 1, 1060, y + 120, ore.get("surface_depth", 10.0), f"ore_depth_{tid}", spots)
    if "min_height" in ore or "max_height" in ore:
        lo_edges, hi_edges = height_band(ore, radius)
        lo = g.add(base + 5, "Smoothstep", 1060, y + 200, edge0=lo_edges[0], edge1=lo_edges[1],
                   name=_name(f"ore_alt_lo_{tid}"))
        g.link(21, lo, 0)
        hi = g.add(base + 6, "Smoothstep", 1060, y + 260, edge0=hi_edges[0], edge1=hi_edges[1],
                   name=_name(f"ore_alt_hi_{tid}"))
        g.link(21, hi, 0)
        band = g.add(base + 7, "Multiply", 1240, y + 230)
        g.link(lo, band, 0)
        g.link(hi, band, 1)
        banded = g.add(base + 8, "Multiply", 1600, y + 160)
        g.link(gated, banded, 0)
        g.link(band, banded, 1)
        gated = banded
    weights[tid] = gated


def height_band(ore, radius):
    """Bordes de los dos smoothsteps de altura (distancia al centro), como Planet._apply_ore_params:
    sube de min_height - softness a min_height y baja de max_height a max_height + softness. Las
    alturas, sobre el radio del planeta, como las de la vegetación."""
    soft = max(float(ore.get("height_softness", 20.0)), 0.001)
    low = radius + float(ore.get("min_height", -1.0e6))
    high = radius + float(ore.get("max_height", 1.0e6))
    return (low - soft, low), (high + soft, high)


def write_ore_field(g, outputs):
    lines = [f'[gd_resource type="VoxelGraphFunction" format=3 uid="{ORE_FIELD_UID}"]', "",
             '[sub_resource type="ZN_FastNoiseLite" id="ZN_FastNoiseLite_qhap6"]', "period = 20.0001", "",
             "[resource]", "graph_data = {"]
    conns = ", ".join(f"[{a}, {b}, {c}, {d}]" for a, b, c, d in g.connections)
    lines.append(f'"connections": [{conns}],')
    lines.append('"nodes": {')
    entries = []
    for node_id in sorted(g.nodes, key=lambda n: str(n)):
        node = g.nodes[node_id]
        body = ",\n".join(f'"{k}": {_value(node[k])}' for k in sorted(node))
        entries.append(f'"{node_id}": {{\n{body}\n}}')
    lines.append(",\n".join(entries))
    lines.append("},")
    lines.append('"version": 2')
    lines.append("}")
    lines.append('input_definitions = [["x", "InputX", 0], ["y", "InputY", 0], ["z", "InputZ", 0], '
                 '["planet_sdf", "CustomInput", 0]]')
    outs = ", ".join(f'["{name}", "CustomOutput", 0]' for name in outputs)
    lines.append(f"output_definitions = [{outs}]")
    with open(ORE_FIELD, "w") as f:
        f.write("\n".join(lines) + "\n")


def patch_terraces(surface_ores):
    """Una OutputWeight por salida del nodo de las vetas, con su type_id de capa."""
    text = open(TERRACES).read()
    start = text.index("graph_data = {")
    head, body = text[:start], text[start:]
    # Quita las OutputWeight que colgaban de las vetas y sus conexiones.
    conns = json.loads(re.search(r'"connections": (\[.*?\]),\n', body).group(1))
    old = {c[2] for c in conns if c[0] == ORE_FUNCTION_NODE}
    conns = [c for c in conns if c[0] != ORE_FUNCTION_NODE]
    for node_id in old:
        body = re.sub(r'"%d": \{\n.*?\n\},?\n' % node_id, "", body, flags=re.S)
    ids = []
    taken = {int(m) for m in re.findall(r'^"(\d+)": \{', body, flags=re.M)}
    candidate = FIRST_WEIGHT_NODE
    for k, ore in enumerate(surface_ores):
        while candidate in taken:
            candidate += 1
        ids.append(candidate)
        taken.add(candidate)
        conns.append([ORE_FUNCTION_NODE, k, candidate, 0])
    new_nodes = []
    for k, (node_id, ore) in enumerate(zip(ids, surface_ores)):
        new_nodes.append(f'"{node_id}": {{\n"auto_connect": false,\n"gui_position": Vector2(3540, {1080 - 90 * k}),\n'
                         f'"layer": {int(ore["type_id"])},\n"type": "OutputWeight"\n}},\n')
    body = re.sub(r'"connections": \[.*?\],\n', '"connections": ' + json.dumps(conns, separators=(", ", ": ")) + ",\n",
                  body, count=1)
    body = body.replace('"nodes": {\n', '"nodes": {\n' + "".join(new_nodes), 1)
    # Una coma de más antes de cerrar los nodos, si la quitada era la última.
    body = re.sub(r"\},\n\},\n\"version\"", '}\n},\n"version"', body)
    with open(TERRACES, "w") as f:
        f.write(head + body)


def main():
    planet = json.load(open(PLANET))
    ores = planet.get("ore_settings", [])
    ids = [int(o["type_id"]) for o in ores]
    if ids != list(range(1, len(ids) + 1)):
        sys.exit(f"ore_settings tiene que ir por type_id 1, 2, 3... y va {ids}")
    surface = [o for o in ores if "depth_min" not in o]
    g, outputs = build(surface, float(planet["terrain_settings"]["radius"]))
    write_ore_field(g, outputs)
    patch_terraces(surface)
    print(f"{len(surface)} vetas de superficie: " + ", ".join(f"{o['name']} ({int(o['type_id'])})" for o in surface))


if __name__ == "__main__":
    main()
