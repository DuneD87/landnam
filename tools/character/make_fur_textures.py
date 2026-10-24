#!/usr/bin/env python3
"""Tileable maps for the Stone Age fur garments, which
tools/character/blender/build_fur_armor.py builds and
tools/character/bake_meshy_armor.gd gives their materials (docs/character_creation.md,
"Prendas de pieles con pelo"). The hair is rendered from real strands by
tools/character/blender/render_fur_maps.py; these are the rest. Every map
repeats seamlessly; the garments' UVs are in metres and each material says
how many times a map repeats per metre.

    python3 tools/character/make_fur_textures.py [--only=leather,lace,bone,pelt_albedo]

 - leather: tanned hide, a fine pebbled grain, creases, a soft mottle.
   Albedo, normal, roughness; light, vertex colours darken it.
 - lace: twisted sinew for cords and lacing (u along the cord). Albedo, normal.
 - bone: toggles and beads. Albedo.
 - pelt_albedo: the rendered pelt (fur_pelt.png) as grey colour, for a
   StandardMaterial3D (the backpack's flap).

Written to models/equipable/stone_age/fur/. Python 3, numpy and Pillow.
"""

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "models/equipable/stone_age/fur")


# --- Noise and drawing ---------------------------------------------------------

def norm(a):
    lo, hi = np.percentile(a, 1), np.percentile(a, 99)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def noise(seed, shape, scale, beta=2.0, stretch=(1.0, 1.0)):
    """Periodic noise: white noise filtered as 1/f^beta, nothing finer than
    `scale` pixels of wavelength. `stretch` (rows, columns) makes it longer
    one way. 0..1."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal(shape)
    fy = np.fft.fftfreq(shape[0])[:, None] * stretch[0]
    fx = np.fft.fftfreq(shape[1])[None, :] * stretch[1]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spectrum = np.fft.fft2(white) / f ** (beta * 0.5)
    spectrum *= np.exp(-(f * scale) ** 2)
    spectrum[0, 0] = 0.0
    return norm(np.real(np.fft.ifft2(spectrum)))


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def normal_map(height, strength):
    """OpenGL-style (green up the image), as Godot takes them."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(height)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save(name, pixels, mode="RGB"):
    os.makedirs(OUT, exist_ok=True)
    data = np.clip(pixels * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(data, mode).save(os.path.join(OUT, name + ".png"), optimize=True)
    print("Saved", os.path.join(OUT, name + ".png"))


# --- Maps ----------------------------------------------------------------------

def pelt_albedo():
    """The pelt tile (render_fur_maps.py) as plain grey colour, for what
    shows it through a StandardMaterial3D (the backpack's flap), coloured as
    fur_common.gdshaderinc colours it."""
    data = np.asarray(Image.open(os.path.join(OUT, "fur_pelt.png")).convert("RGBA")).astype(np.float64) / 255.0
    t, strand, occlusion = data[..., 0], data[..., 1], data[..., 2]
    along = np.where(t < 0.55, 0.45 + (1.0 - 0.45) * t / 0.55, 1.0 + (0.6 - 1.0) * (t - 0.55) / 0.45)
    linear = along * (1.0 + 0.75 * (strand - 0.5)) * (0.3 + 0.7 * occlusion) * 0.7
    srgb = np.where(linear <= 0.0031308, linear * 12.92, 1.055 * np.power(np.maximum(linear, 0.0), 1 / 2.4) - 0.055)
    save("fur_pelt_albedo", np.clip(np.repeat(srgb[..., None], 3, axis=2), 0, 1))


def cells(seed, n, size):
    """Periodic Worley noise on an n x n tile: distance to the nearest and
    second nearest of jittered points `size` pixels apart (F1, F2)."""
    rng = np.random.default_rng(seed)
    count = n // size
    jitter = rng.random((count, count, 2))
    y, x = np.mgrid[0:n, 0:n] + 0.5
    cy, cx = (y // size).astype(int), (x // size).astype(int)
    f1 = np.full((n, n), 1e9)
    f2 = np.full((n, n), 1e9)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            gy, gx = cy + dy, cx + dx
            point = jitter[gy % count, gx % count]
            py = (gy + point[..., 0]) * size
            px = (gx + point[..., 1]) * size
            d = np.hypot(y - py, x - px)
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    return f1, f2


def leather():
    """Tanned hide: a fine pebbled grain (the cells a skin dries into),
    creases where it bends, a soft mottle, darker in every hollow. Light, so
    vertex colours can darken it into belts and soles."""
    n = 1024
    f1, f2 = cells(41, n, 6)
    grain = smooth(0.0, 3.0, f2 - f1)
    coarse1, coarse2 = cells(42, n, 40)
    plates = smooth(0.0, 6.0, coarse2 - coarse1)
    crease_field = noise(45, (n, n), 7.0, beta=2.2, stretch=(1.0, 0.3))
    creases = smooth(0.9, 0.985, 1.0 - np.abs(2.0 * crease_field - 1.0))
    fine = noise(46, (n, n), 3.0, beta=1.8, stretch=(0.35, 1.0))
    wrinkles = smooth(0.86, 0.97, 1.0 - np.abs(2.0 * fine - 1.0))
    mottle = noise(43, (n, n), 90.0, beta=2.4)
    wear = smooth(0.55, 0.85, noise(44, (n, n), 60.0, beta=2.0))
    scratch = smooth(0.965, 0.995, 1.0 - np.abs(2.0 * noise(47, (n, n), 2.0, beta=1.5, stretch=(1.0, 0.08)) - 1.0))
    height = 0.22 * grain + 0.2 * plates - 0.6 * creases - 0.3 * wrinkles + 0.15 * mottle - 0.2 * scratch
    hollow = 1.0 - grain
    shade = 0.92 + 0.12 * (mottle - 0.5) - 0.04 * hollow - 0.12 * creases - 0.05 * wrinkles + 0.06 * wear \
        + 0.05 * scratch - 0.04 * (1.0 - plates)
    base = np.array([0.78, 0.68, 0.56])
    warm = np.array([1.0, 0.97, 0.93]) + 0.05 * (noise(48, (n, n), 160.0)[..., None] - 0.5) * np.array([1.0, 0.2, -0.8])
    color = base * shade[..., None] * warm
    rough = 0.8 + 0.08 * hollow + 0.06 * creases - 0.12 * wear * (1.0 - hollow)
    save("leather_albedo", np.clip(color, 0, 1))
    save("leather_normal", normal_map(height, 2.5))
    save("leather_roughness", np.clip(np.repeat(rough[..., None], 3, axis=2), 0, 1))


def lace():
    h, w = 128, 512
    v, u = np.meshgrid(np.arange(h) / h, np.arange(w) / w, indexing="ij")
    # Three plies twisted round the cord: u along it, v round it.
    twist = np.mod(u * 12.0 + v * 3.0, 1.0)
    ply = np.sin(np.pi * twist) ** 0.6
    fibres = noise(51, (h, w), 1.2, beta=0.8, stretch=(0.25, 1.0))
    height = 0.6 * ply + 0.25 * fibres
    shade = 0.75 + 0.3 * ply + 0.15 * (fibres - 0.5)
    color = np.array([0.66, 0.56, 0.42]) * shade[..., None]
    save("lace_albedo", np.clip(color, 0, 1))
    save("lace_normal", normal_map(height, 4.0))


def bone():
    n = 256
    base = noise(61, (n, n), 12.0)
    pits = smooth(0.78, 0.9, noise(62, (n, n), 1.5, beta=0.3))
    cracks = smooth(0.9, 0.97, 1.0 - np.abs(2.0 * noise(63, (n, n), 6.0, beta=2.0, stretch=(1.0, 0.3)) - 1.0))
    shade = 0.88 + 0.1 * base - 0.12 * pits - 0.15 * cracks
    color = np.array([0.86, 0.80, 0.68]) * shade[..., None]
    save("bone_albedo", np.clip(color, 0, 1))


MAPS = {"leather": leather, "lace": lace, "bone": bone, "pelt_albedo": pelt_albedo}


def main():
    only = None
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            only = arg.split("=", 1)[1].split(",")
    for name, make in MAPS.items():
        if only is None or name in only:
            make()


if __name__ == "__main__":
    main()
