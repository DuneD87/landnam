#!/usr/bin/env python3
"""Texturas de las menas, hechas sobre las rocas que ya hay: las vetas del terreno (albedo, normal y
rugosidad, que repiten sin costura) y los afloramientos que se pican (albedo y rugosidad de las rocas
ProceduralRock). Cada mena es su roca de base, recoloreada, con su mineral encima donde le toca: en las
grietas (lo bajo del mapa de altura), en las crestas o en manchas, vetas y vetas de ruido periódico.

    python3 tools/terrain/make_ore_textures.py [--only=tin,copper] [--size=1024]

Salen en textures/planet/ores/<mena>/ (vetas) y textures/planet/outcrops/ (afloramientos). Después,
abrir el proyecto (o --headless --editor --quit) para importarlas. Python 3, numpy y Pillow.
"""

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAVINE = "textures/planet/ores/ravine-rock1-bl/ravine-rock1"
CAVERN = "textures/planet/ores/cavern-deposits-bl/cavern-deposits"
JAGGED = "textures/terrain/jagged-rocky-ground1-bl/jagged-rocky-ground"

SIZE = 1024


def _load(path, mode="RGB"):
    im = Image.open(os.path.join(ROOT, path)).convert(mode)
    if im.size != (SIZE, SIZE):
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def base(prefix, height_name="_height.png", normal_name="_normal-ogl.png", rough_name="_roughness.png"):
    albedo = _load(prefix + "_albedo.png")
    height = _load(prefix + height_name, "L")
    normal = _load(prefix + normal_name)
    rough = _load(prefix + rough_name, "L")
    return albedo, _norm(height), normal, rough


def _norm(a):
    lo, hi = np.percentile(a, 1), np.percentile(a, 99)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def noise(seed, scale, beta=2.0, size=None):
    """Ruido periódico (repite sin costura): ruido blanco filtrado en frecuencia como 1/f^beta, sin
    lo más fino que [scale] (en píxeles de longitud de onda). Normalizado a 0..1."""
    n = size or SIZE
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((n, n))
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spectrum = np.fft.fft2(white) / f ** (beta * 0.5)
    spectrum *= np.exp(-(f * scale) ** 2)
    spectrum[0, 0] = 0.0
    return _norm(np.real(np.fft.ifft2(spectrum)))


def band(seed, wavelength):
    """Ruido periódico de una sola escala (manchas de [wavelength] píxeles, redondeadas). 0..1."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((SIZE, SIZE))
    fx = np.fft.fftfreq(SIZE)[:, None]
    fy = np.fft.fftfreq(SIZE)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f0 = 1.0 / wavelength
    spectrum = np.fft.fft2(white) * np.exp(-((f - f0) / (0.45 * f0)) ** 2)
    spectrum[0, 0] = 0.0
    return _norm(np.real(np.fft.ifft2(spectrum)))


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def gray(rgb):
    return rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def tint(rgb, color, amount):
    """Lleva [rgb] hacia [color] conservando su luz (el relieve de la roca sigue viéndose)."""
    lum = gray(rgb)[..., None]
    target = np.array(color, dtype=np.float32) * (0.45 + 1.1 * lum)
    if isinstance(amount, np.ndarray):
        amount = amount[..., None]
    return rgb + (target - rgb) * amount


def paint(rgb, color, mask, light=0.3):
    """Mineral encima: [color] donde [mask], con algo de la luz de debajo."""
    lum = gray(rgb)[..., None]
    shaded = np.array(color, dtype=np.float32) * (1.0 - light + 2.0 * light * lum)
    m = mask[..., None]
    return rgb * (1.0 - m) + shaded * m


def ridge(n, width):
    """Vetas finas donde el ruido cruza su mitad."""
    return np.clip(1.0 - np.abs(n - 0.5) / width, 0.0, 1.0) ** 2


def save(rgb, path, mode="RGB"):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    data = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(data, mode).save(full, optimize=True)
    print("saved", path)


def save_vein(name, albedo, normal, rough):
    folder = f"textures/planet/ores/{name}"
    save(albedo, f"{folder}/{name}_albedo.png")
    save(normal, f"{folder}/{name}_normal-ogl.png")
    save(rough, f"{folder}/{name}_roughness.png", "L")


def save_outcrop(name, albedo, rough):
    save(albedo, f"textures/planet/outcrops/{name}_albedo.png")
    save(rough, f"textures/planet/outcrops/{name}_roughness.png", "L")


# --- Vetas del terreno ----------------------------------------------------------------------------

def tin():
    """Casiterita: granito gris rosado con cristales pardos casi negros y brillantes en las crestas."""
    albedo, height, normal, rough = base(RAVINE)
    rgb = tint(albedo, (0.62, 0.56, 0.54), 0.75)
    grain = noise(11, 3.0, 1.2)
    rgb = paint(rgb, (0.86, 0.80, 0.76), smooth(0.72, 0.8, grain) * 0.6)
    clusters = smooth(0.48, 0.6, noise(12, 24.0)) * smooth(0.35, 0.6, height)
    crystals = clusters * smooth(0.42, 0.55, noise(13, 4.0, 1.0))
    rgb = paint(rgb, (0.17, 0.11, 0.08), crystals, 0.45)
    rough = rough * (1.0 - crystals * 0.6)
    save_vein("tin", rgb, normal, rough)


def bog_iron():
    """Limonita: terrones herrumbrosos ocres y pardos, terrosos, con nódulos oscuros."""
    albedo, height, normal, rough = base(CAVERN)
    rgb = tint(albedo, (0.62, 0.36, 0.14), 0.85)
    patches = noise(21, 40.0)
    rgb = tint(rgb, (0.78, 0.52, 0.2), smooth(0.55, 0.75, patches) * 0.5)
    nodules = smooth(0.62, 0.7, noise(22, 10.0)) * smooth(0.4, 0.65, height)
    rgb = paint(rgb, (0.26, 0.13, 0.06), nodules, 0.35)
    rust = smooth(0.65, 0.4, height) * smooth(0.45, 0.7, noise(23, 6.0))
    rgb = paint(rgb, (0.66, 0.30, 0.09), rust * 0.6, 0.3)
    rough = np.clip(rough * 0.3 + 0.68, 0.0, 1.0)
    save_vein("bog_iron", rgb, normal, rough)


def coal():
    """Carbón: pizarra parda y gris oscura cruzada por capas negras algo brillantes."""
    albedo, height, normal, rough = base(CAVERN)
    rgb = tint(albedo, (0.26, 0.24, 0.23), 0.85) * 0.85
    y = np.linspace(0.0, 1.0, SIZE, endpoint=False)[:, None] * np.ones((1, SIZE))
    warp = noise(31, 120.0) * 0.6 + noise(32, 12.0) * 0.05
    bands = 0.5 + 0.5 * np.sin((y * 9.0 + warp) * 2.0 * np.pi)
    thickness = noise(34, 90.0)
    seams = smooth(0.78 - thickness * 0.25, 0.86 - thickness * 0.25, bands)
    rgb = paint(rgb, (0.035, 0.035, 0.04), seams, 0.5)
    glints = seams * smooth(0.75, 0.85, noise(33, 3.0, 1.0))
    rgb = rgb + glints[..., None] * 0.08
    rough = np.clip(rough * (1.0 - seams * 0.55), 0.0, 1.0)
    save_vein("coal", rgb, normal, rough)


def silver():
    """Galena argentífera: roca gris con cubos y manchas gris plomo que brillan como metal."""
    albedo, height, normal, rough = base(RAVINE)
    rgb = tint(albedo, (0.5, 0.49, 0.5), 0.8)
    veins = ridge(noise(41, 30.0), 0.05) * smooth(0.4, 0.6, noise(42, 80.0))
    specks = smooth(0.66, 0.72, noise(43, 5.0, 1.0)) * smooth(0.5, 0.65, noise(44, 40.0))
    galena = np.clip(veins + specks, 0.0, 1.0)
    rgb = paint(rgb, (0.62, 0.64, 0.68), galena, 0.6)
    rough = rough * (1.0 - galena * 0.75)
    save_vein("silver", rgb, normal, rough)


def sulfur():
    """Azufre: roca volcánica clara y gastada con costras amarillas en las grietas, naranjas al borde."""
    albedo, height, normal, rough = base(JAGGED)
    rgb = tint(albedo, (0.74, 0.70, 0.62), 0.8)
    crevice = smooth(0.6, 0.3, height)
    crust = crevice * smooth(0.4, 0.6, noise(51, 18.0))
    edge = np.clip(crust * (1.0 - crust) * 4.0, 0.0, 1.0)
    rgb = paint(rgb, (0.92, 0.80, 0.16), crust, 0.25)
    rgb = paint(rgb, (0.82, 0.52, 0.12), edge * 0.5, 0.25)
    rough = np.clip(rough * 0.6 + 0.3, 0.0, 1.0)
    save_vein("sulfur", rgb, normal, rough)


# --- Afloramientos (rocas que se pican) -----------------------------------------------------------

def obsidian():
    """Obsidiana: vidrio volcánico negro, con ondas de fractura y alguna veta parda."""
    albedo, height, normal, rough = base(RAVINE)
    lum = gray(albedo)[..., None]
    rgb = np.ones_like(albedo) * np.array([0.04, 0.04, 0.05], dtype=np.float32) + lum * 0.06
    ripples = (0.5 + 0.5 * np.sin(noise(71, 20.0) * 55.0)) ** 3
    shell = smooth(0.45, 0.7, noise(73, 60.0))
    rgb = rgb + (ripples * shell)[..., None] * np.array([0.09, 0.09, 0.1], dtype=np.float32)
    streak = ridge(noise(72, 50.0), 0.08) * 0.5
    rgb = paint(rgb, (0.2, 0.13, 0.1), streak, 0.2)
    rough = np.clip(0.12 + streak * 0.3 + (1.0 - ripples) * 0.06, 0.0, 1.0)
    save_outcrop("obsidian", rgb, rough)


def copper():
    """Cobre: roca parda con costras verdes de malaquita y alguna azul de azurita en grietas y vetas."""
    albedo, height, normal, rough = base(RAVINE)
    rgb = tint(albedo, (0.46, 0.38, 0.32), 0.7)
    crevice = smooth(0.55, 0.3, height)
    veins = ridge(noise(81, 50.0), 0.06)
    stain = np.clip(crevice * smooth(0.55, 0.7, noise(82, 26.0)) + veins * 0.8, 0.0, 1.0) * 0.9
    banding = 0.5 + 0.5 * np.sin(noise(83, 14.0) * 24.0)
    malachite = np.array([0.16, 0.48, 0.32], dtype=np.float32)
    dark = np.array([0.05, 0.25, 0.16], dtype=np.float32)
    color = (dark + (malachite - dark) * banding[..., None]) * (0.7 + 0.6 * gray(albedo)[..., None])
    rgb = rgb * (1.0 - stain[..., None]) + color * stain[..., None]
    azurite = stain * smooth(0.8, 0.86, noise(84, 18.0))
    rgb = paint(rgb, (0.12, 0.2, 0.45), azurite, 0.35)
    rough = np.clip(rough * (1.0 - stain * 0.3), 0.0, 1.0)
    save_outcrop("copper", rgb, rough)


ALL = {"tin": tin, "bog_iron": bog_iron, "coal": coal, "silver": silver, "sulfur": sulfur,
       "obsidian": obsidian, "copper": copper}


def main():
    global SIZE
    only = None
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            only = arg[7:].split(",")
        elif arg.startswith("--size="):
            SIZE = int(arg[7:])
    for name, make in ALL.items():
        if only is None or name in only:
            make()


if __name__ == "__main__":
    main()
