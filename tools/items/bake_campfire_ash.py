#!/usr/bin/env python3
"""Hornea las texturas de la calcomanía de ceniza de la hoguera (CampfireVisual):

- textures/props/campfire_ash_albedo.png: ceniza gris y carbón, opaca en el centro y que se va
  difuminando hacia fuera (tizna el suelo de alrededor);
- textures/props/campfire_ash_emission.png: las brasas, que solo brillan con el fuego encendido.

    build/fauna_tools/bin/python -I tools/items/bake_campfire_ash.py
"""

import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "textures", "props")
N = 512
rng = np.random.default_rng(11)


def noise(scale, octaves=5):
    """Ruido de valor por octavas (suave, sin costuras que importen: la calcomanía es redonda)."""
    out = np.zeros((N, N), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = int(scale * 2 ** o)
        grid = rng.random((cells + 1, cells + 1)).astype(np.float32)
        ys, xs = np.linspace(0, cells, N, endpoint=False), np.linspace(0, cells, N, endpoint=False)
        y0, x0 = ys.astype(int), xs.astype(int)
        fy, fx = ys - y0, xs - x0
        fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
        a = grid[y0][:, x0]
        b = grid[y0][:, x0 + 1]
        c = grid[y0 + 1][:, x0]
        d = grid[y0 + 1][:, x0 + 1]
        top = a + (b - a) * fx[None, :]
        bottom = c + (d - c) * fx[None, :]
        out += amp * (top + (bottom - top) * fy[:, None])
        total += amp
        amp *= 0.5
    return out / total


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
u = (xx + 0.5) / N * 2 - 1
v = (yy + 0.5) / N * 2 - 1
r = np.hypot(u, v)
n1 = noise(4)
n2 = noise(16, 3)
# Borde irregular: el radio del tiznado cambia con el ruido.
edge = r + (n1 - 0.5) * 0.18

# Ceniza: gris oscuro a manchas, con grano fino y trocitos de carbón negro.
grain = noise(96, 2)
ash = 0.09 + 0.16 * n1 + 0.07 * n2 + 0.06 * (grain - 0.5)
charcoal = smoothstep(0.6, 0.72, noise(48, 2)) * smoothstep(0.8, 0.25, r)
grey = ash * (1 - 0.8 * charcoal) * (0.75 + 0.25 * smoothstep(0.0, 0.6, r))
albedo = np.stack([grey * 1.04, grey * 0.98, grey * 0.92], axis=2)
# Lleno dentro del corro (r < 0,62 de la calcomanía) y tizne que se apaga hacia fuera.
alpha = np.maximum(smoothstep(0.7, 0.5, edge), 0.6 * smoothstep(1.0, 0.6, edge) * (0.45 + 0.55 * n2))

# Brasas: puntitos naranjas en el centro, entre la ceniza, y un rescoldo difuso debajo.
specks = smoothstep(0.7, 0.8, noise(80, 2)) + 0.6 * smoothstep(0.74, 0.86, noise(140, 1))
glow = np.clip(specks * smoothstep(0.5, 0.05, r) + 0.28 * smoothstep(0.35, 0.0, r) * n1, 0, 1)
emission = np.stack([glow, glow * 0.36, glow * 0.07], axis=2)

os.makedirs(OUT, exist_ok=True)
rgba = np.concatenate([np.clip(albedo, 0, 1), alpha[..., None]], axis=2)
Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "campfire_ash_albedo.png"))
Image.fromarray((np.clip(emission, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(
    os.path.join(OUT, "campfire_ash_emission.png"))
print("ok", OUT)
