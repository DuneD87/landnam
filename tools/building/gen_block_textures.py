#!/usr/bin/env python3
"""Genera las texturas de los bloques de construcción: troncos apilados y muro de piedra.

Cada material sale en textures/build_materials/<nombre>/ con cuatro mapas que tilean en los dos
ejes y cubren TILE_METERS de lado:

  <nombre>_albedo.png   color, sRGB
  <nombre>_normal.png   normales en convención OpenGL (Y+), la que usa Godot
  <nombre>_orm.png      R = oclusión, G = roughness, B = metalness (siempre 0)
  <nombre>_height.png   altura, blanco = más saliente; es la que lee el parallax

La altura es la propia geometría con la que se dibujan troncos y piedras, no una estimación a partir
del color, y de ella salen la normal y la oclusión: los tres mapas casan exactamente, que es lo que
hace que el parallax no "flote".

Requiere numpy, scipy y Pillow:

    python3 tools/building/gen_block_textures.py
    python3 tools/building/gen_block_textures.py --only logs --preview /tmp/prev
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "textures" / "build_materials"

## Metros que cubre una repetición de la textura. El material lo replica en uv1_scale (1/TILE),
## porque el mallador de las grids emite las UV en metros.
TILE_METERS = 2.0

IMPORT_SETTINGS = '''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{resource}"

[params]

compress/mode=2
compress/high_quality={high_quality}
compress/normal_map={normal_map}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/size_limit=0
detect_3d/compress_to=0
'''

# Paleta de la madera (sRGB 0-1).
WOOD_LIGHT = np.array([0.66, 0.47, 0.30])
WOOD_DARK = np.array([0.36, 0.23, 0.13])
WOOD_WEATHERED = np.array([0.50, 0.45, 0.39])
WOOD_GAP = np.array([0.10, 0.072, 0.052])
WOOD_CRACK = np.array([0.11, 0.065, 0.035])
KNOT_DARK = np.array([0.20, 0.10, 0.05])
KNOT_MID = np.array([0.42, 0.24, 0.12])

# Paleta de la piedra: los tonos de un canto rodado de río, del gris azulado al ocre.
STONE_PALETTE = np.array([
    [0.68, 0.62, 0.52],  # arenisca
    [0.63, 0.57, 0.47],  # beige cálido
    [0.56, 0.55, 0.53],  # gris
    [0.50, 0.50, 0.49],  # gris frío
    [0.55, 0.48, 0.40],  # pardo
    [0.74, 0.70, 0.62],  # claro
    [0.40, 0.40, 0.39],  # gris oscuro
    [0.64, 0.55, 0.42],  # ocre
])
STONE_WEIGHTS = np.array([0.17, 0.15, 0.17, 0.13, 0.12, 0.08, 0.08, 0.10])
STONE_GAP = np.array([0.15, 0.135, 0.115])


@dataclass
class Maps:
    albedo: np.ndarray     # (H, W, 3) sRGB 0-1
    height: np.ndarray     # (H, W) 0-1
    roughness: np.ndarray  # (H, W) 0-1
    ao: np.ndarray         # (H, W) 0-1
    normal: np.ndarray     # (H, W, 3) unitarias, OpenGL
    relief_m: float        # metros que separan altura 0 de altura 1


# --- Utilidades ---------------------------------------------------------------------------------

def periodic_blur(img: np.ndarray, sx: float, sy: float | None = None) -> np.ndarray:
    """Desenfoque gaussiano por FFT: el resultado tilea igual que la entrada."""
    sy = sx if sy is None else sy
    h, w = img.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2.0 * np.pi ** 2 * ((fx * sx) ** 2 + (fy * sy) ** 2))
    return np.fft.irfft2(np.fft.rfft2(img) * g, s=img.shape)


def noise(rng: np.random.Generator, shape: tuple[int, int], sx: float, sy: float | None = None) -> np.ndarray:
    """Ruido gaussiano periódico de desviación 1, con rasgos de sx×sy píxeles."""
    n = periodic_blur(rng.standard_normal(shape), sx, sy)
    return (n / (n.std() + 1e-12)).astype(np.float32)


def sample(field: np.ndarray, rows: np.ndarray, cols: np.ndarray) -> np.ndarray:
    """Lee un campo periódico en coordenadas fraccionarias, envolviendo los bordes."""
    return ndimage.map_coordinates(field, [rows, cols], order=1, mode="grid-wrap")


def periodic_wave(rng: np.random.Generator, x: np.ndarray, period: float, amps: list[float]) -> np.ndarray:
    """Suma de senos de frecuencia entera sobre el periodo: ondula sin romper el tileado."""
    out = np.zeros_like(x, dtype=np.float64)
    for j, a in enumerate(amps):
        out += a * np.sin(2.0 * np.pi * (j + 1) * x / period + rng.uniform(0, 2.0 * np.pi))
    return out


def wrap(d: np.ndarray, period: float) -> np.ndarray:
    """Diferencia periódica en [-period/2, period/2)."""
    return np.mod(d + period * 0.5, period) - period * 0.5


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def normal_from_height(height_m: np.ndarray, px_m: float) -> np.ndarray:
    """Normal en convención OpenGL: +Y apunta hacia arriba de la imagen."""
    dx = (np.roll(height_m, -1, 1) - np.roll(height_m, 1, 1)) / (2.0 * px_m)
    drow = (np.roll(height_m, -1, 0) - np.roll(height_m, 1, 0)) / (2.0 * px_m)
    n = np.stack([-dx, drow, np.ones_like(dx)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def cavity_ao(height: np.ndarray, terms: list[tuple[float, float]], floor: float) -> np.ndarray:
    """Oclusión por cavidad: lo que queda por debajo de la media de su entorno se oscurece."""
    occ = np.zeros_like(height)
    for sigma, gain in terms:
        occ += gain * np.clip(periodic_blur(height, sigma) - height, 0.0, None)
    return np.clip(1.0 - occ, floor, 1.0)


# --- Troncos apilados ---------------------------------------------------------------------------

def make_logs(size: int, seed: int) -> Maps:
    rng = np.random.default_rng(seed)
    k = size / 2048.0  # las medidas en píxeles están pensadas para 2048
    W = H = size
    n_logs = 8  # 25 cm por tronco con TILE_METERS = 2
    S = H / n_logs
    R0 = 0.5 * S
    px_m = TILE_METERS / size
    x = np.arange(W, dtype=np.float64)

    # Campos que cada tronco lee en su coordenada de superficie: las vetas siguen el tronco.
    # Ninguno pasa de unas 15:1 de alargamiento: más, y la madera parece un tablón barnizado.
    broad = noise(rng, (H, W), 110 * k, 12 * k)  # bandas claras y oscuras a lo largo
    grain = noise(rng, (H, W), 34 * k, 2.2 * k)  # vetas
    fiber = noise(rng, (H, W), 7 * k, 0.8 * k)   # fibra fina
    tears = noise(rng, (H, W), 18 * k, 1.0 * k)  # desgarros cortos de la fibra
    blotch = noise(rng, (H, W), 35 * k, 25 * k)  # manchas de intemperie
    warp = noise(rng, (H, W), 45 * k, 18 * k)    # ondulación de las vetas
    wear = noise(rng, (H, W), 3.5 * k)           # picado fino de la superficie gastada
    specks = noise(rng, (H, W), 1.2 * k)         # motas oscuras sueltas
    gap_n = noise(rng, (H, W), 2.5 * k)

    # Fondo: la junta entre troncos, honda y oscura.
    height = (0.02 + 0.012 * gap_n).astype(np.float64)
    albedo = WOOD_GAP * (1.0 + 0.2 * gap_n)[..., None]
    rough = np.full((H, W), 0.97)

    for i in range(n_logs):
        yc = (i + 0.5) * S + rng.uniform(-0.025, 0.025) * S
        R = R0 * rng.uniform(0.935, 0.985)
        c = yc + periodic_wave(rng, x, W, [0.018 * S, 0.01 * S, 0.004 * S])
        r = R * (1.0 + periodic_wave(rng, x, W, [0.028, 0.015, 0.008]))
        tint = rng.uniform(0.86, 1.1) * np.array([1.0, 1.0, 1.0]) + rng.uniform(-0.05, 0.06) * np.array([1.0, 0.0, -1.0])
        weather_amt = rng.uniform(0.15, 0.75)

        rows = np.arange(int(np.floor(yc - 0.62 * S)), int(np.ceil(yc + 0.62 * S)))
        t = (rows[:, None] - c[None, :]) / r[None, :]
        inside = np.abs(t) < 1.0
        tt = np.clip(t, -1.0, 1.0)
        prof = np.sqrt(1.0 - tt * tt)
        s = np.arcsin(tt) * r[None, :]  # coordenada sobre la superficie del tronco, en píxeles
        X = np.broadcast_to(x[None, :], s.shape)

        # Nudos. Las vetas se abren a su alrededor desplazando la coordenada con la que se leen.
        s_flow = s.copy()
        knot_q = np.full(s.shape, 9.0)
        for _ in range(rng.integers(1, 5)):
            xk = rng.uniform(0, W)
            sk = rng.uniform(-0.8, 0.8) * R
            ay = rng.uniform(10, 26) * k
            ax = ay * rng.uniform(0.85, 1.25)
            dx = wrap(X - xk, W)
            q = np.hypot(dx / ax, (s - sk) / ay)
            knot_q = np.minimum(knot_q, q)
            f = np.exp(-(dx / (2.2 * ax)) ** 2 - ((s - sk) / (2.0 * ay)) ** 2)
            s_flow -= np.sign(s - sk) * ay * 1.1 * f

        ox, oy = rng.uniform(0, W), rng.uniform(0, H)
        cols = X + ox
        w = sample(warp, oy + s, cols)
        sg = oy + s_flow + 6.0 * k * w
        g_broad = sample(broad, sg, cols)
        g_grain = sample(grain, sg, cols)
        g_fiber = sample(fiber, sg, cols)
        g_tears = sample(tears, sg, cols)
        g_blotch = sample(blotch, oy + s, cols)
        g_wear = sample(wear, oy + s, cols)
        speck = smoothstep(2.2, 3.0, sample(specks, oy + s, cols))
        tear = smoothstep(1.8, 2.7, g_tears)

        # Grietas de secado: surcos finos a lo largo de la veta, que se afinan en las puntas.
        crack = np.zeros(s.shape)
        for _ in range(rng.integers(3, 9)):
            sc = rng.uniform(-0.65, 0.65) * R
            x0 = rng.uniform(0, W)
            length = W * (rng.uniform(0.05, 0.3) if rng.random() < 0.8 else rng.uniform(0.4, 0.8))
            w0 = rng.uniform(1.2, 3.2) * k
            along = np.mod(X - x0, W) / length
            taper = np.sqrt(np.sin(np.pi * np.clip(along, 0.0, 1.0)))
            path = sc + periodic_wave(rng, x, W, [3.0 * k, 2.0 * k, 1.2 * k, 0.8 * k])[None, :] + 1.5 * k * w
            d = np.abs(s - path) / np.maximum(w0 * taper, 1e-3)
            crack = np.maximum(crack, np.where(along < 1.0, np.clip(1.0 - d, 0.0, 1.0), 0.0))

        knot_mask = smoothstep(1.05, 0.8, knot_q)
        rings = 0.5 + 0.5 * np.cos(knot_q * 2.0 * np.pi * 2.5)

        tone = np.clip(0.5 + 0.24 * g_broad + 0.15 * g_grain + 0.1 * g_fiber, 0.0, 1.0)
        col = lerp(WOOD_DARK, WOOD_LIGHT, tone[..., None]) * tint
        col *= (1.0 + 0.06 * g_wear - 0.35 * tear - 0.5 * speck)[..., None]
        wthr = (smoothstep(0.3, 1.8, g_blotch) * weather_amt)[..., None]
        col = lerp(col, WOOD_WEATHERED * (0.8 + 0.4 * tone[..., None]), wthr * 0.45)
        # Más oscuro hacia las juntas, en todo el canto y no solo al borde: es lo que hace que se lea
        # redondo con luz ambiente, donde la normal apenas cuenta.
        col *= (0.45 + 0.55 * prof ** 1.2)[..., None]
        knot_col = lerp(KNOT_DARK, KNOT_MID, (rings * smoothstep(0.0, 0.9, knot_q))[..., None])
        col = lerp(col, knot_col, knot_mask[..., None] * 0.9)
        col = lerp(col, WOOD_CRACK, (crack ** 0.6 * 0.92)[..., None])

        relief = smoothstep(0.0, 0.3, prof)  # el detalle se apaga donde el tronco se va de canto
        h = (prof * (r / R0)[None, :]
                + relief * (0.014 * g_broad + 0.0045 * g_grain + 0.0025 * g_fiber + 0.003 * g_wear
                            - 0.006 * tear - 0.006 * speck)
                + 0.012 * knot_mask * np.clip(1.0 - knot_q ** 2, 0.0, 1.0)
                - 0.05 * crack ** 0.7)
        rgh = np.clip(0.82 + 0.04 * g_grain + 0.06 * wthr[..., 0] - 0.1 * knot_mask + 0.2 * crack, 0.0, 1.0)

        rr = np.mod(rows, H)
        cur = height[rr]
        win = inside & (h > cur)
        height[rr] = np.where(win, h, cur)
        albedo[rr] = np.where(win[..., None], col, albedo[rr])
        rough[rr] = np.where(win, rgh, rough[rr])

    height = np.clip(height, 0.0, 1.0)
    ao = cavity_ao(height, [(90 * k, 0.5), (28 * k, 1.1), (4 * k, 3.0)], 0.2)
    relief_m = R0 * px_m
    return Maps(np.clip(albedo, 0, 1), height, np.clip(rough, 0, 1), ao,
            normal_from_height(height * relief_m, px_m), relief_m)


# --- Muro de piedra -----------------------------------------------------------------------------

class StoneCanvas:
    """Lienzo periódico donde cada piedra se suma por máximo: la que sobresale más tapa a la otra."""

    def __init__(self, size: int, fields: dict[str, np.ndarray]):
        self.size = size
        self.height = np.zeros((size, size))
        self.label = np.full((size, size), -1, dtype=np.int32)
        self.prof = np.zeros((size, size))   # perfil de la piedra ganadora, 0 en su borde
        self.vlocal = np.zeros((size, size))  # altura relativa dentro de la piedra (-1 arriba)
        self.fields = fields
        self.count = 0

    def add(self, rng: np.random.Generator, cx: float, cy: float, a: float, b: float, ang: float,
            p: float, hs: float) -> int:
        n = self.size
        ext = max(a, b) * 1.2 + 4
        xs = np.arange(int(np.floor(cx - ext)), int(np.ceil(cx + ext)))
        ys = np.arange(int(np.floor(cy - ext)), int(np.ceil(cy + ext)))
        X = xs[None, :] - cx
        Y = ys[:, None] - cy
        ca, sa = np.cos(ang), np.sin(ang)
        u = X * ca + Y * sa
        v = -X * sa + Y * ca
        q = (np.abs(u / a) ** p + np.abs(v / b) ** p) ** (1.0 / p)
        theta = np.arctan2(v / b, u / a)
        lump = np.ones_like(q)
        for harm in range(2, 6):
            lump += rng.uniform(0.0, 0.07) / harm * 2.0 * np.cos(harm * theta + rng.uniform(0, 2 * np.pi))
        rr, cc = np.mod(ys, n), np.mod(xs, n)
        edge = self.fields["edge"][np.ix_(rr, cc)]
        q = q / lump + 0.02 * edge
        inside = q < 1.0
        prof = (1.0 - np.clip(q, 0.0, 1.0) ** 2.2) ** 0.45
        bumps = self.fields["bumps"][np.ix_(rr, cc)]
        grit = self.fields["grit"][np.ix_(rr, cc)]
        h = hs * prof + smoothstep(0.0, 0.35, prof) * (0.025 * bumps + 0.0015 * grit)

        cur = self.height[np.ix_(rr, cc)]
        win = inside & (h > cur)
        if not win.any():
            return -1
        idx = self.count
        self.count += 1
        sub = np.ix_(rr, cc)
        self.height[sub] = np.where(win, h, cur)
        self.label[sub] = np.where(win, idx, self.label[sub])
        self.prof[sub] = np.where(win, prof, self.prof[sub])
        self.vlocal[sub] = np.where(win, np.clip(v / b, -1, 1), self.vlocal[sub])
        return idx


def make_stone(size: int, seed: int) -> Maps:
    rng = np.random.default_rng(seed)
    k = size / 2048.0
    W = H = size
    px_m = TILE_METERS / size

    fields = {
        "edge": noise(rng, (H, W), 14 * k),
        "bumps": noise(rng, (H, W), 32 * k),
        "grit": noise(rng, (H, W), 1.2 * k),
    }
    canvas = StoneCanvas(size, fields)
    sizes: list[float] = []  # tamaño relativo de cada piedra, para su color

    # Hiladas de piedras alargadas, cada una con su altura, y juntas que no se alinean.
    course_h: list[float] = []
    while sum(course_h) < H:
        course_h.append(rng.uniform(115, 190) * k)
    course_h = list(np.array(course_h) * H / sum(course_h))
    y = rng.uniform(0, H)
    for ch in course_h:
        cy = y + ch * 0.5
        widths: list[float] = []
        while sum(widths) < W:
            widths.append(rng.uniform(170, 440) * k * (ch / (152 * k)) ** 0.5)
        widths = list(np.array(widths) * W / sum(widths))
        x = rng.uniform(0, W)
        for wd in widths:
            cx = x + wd * 0.5 + rng.normal(0, 0.04) * wd
            if rng.random() < 0.14 and wd > 200 * k:
                # Dos piedras pequeñas una encima de otra en vez de una grande.
                for sgn in (-1, 1):
                    bb = ch * 0.25 * rng.uniform(0.9, 1.05)
                    aa = wd * 0.5 * rng.uniform(0.6, 0.9)
                    canvas.add(rng, cx + rng.normal(0, 8 * k), cy + sgn * ch * 0.25, aa, bb,
                            rng.normal(0, 0.1), rng.uniform(2.0, 2.6), rng.uniform(0.6, 0.8))
                    sizes.append(0.4)
            else:
                aa = wd * 0.5 * rng.uniform(0.93, 1.04)
                bb = ch * 0.5 * rng.uniform(0.88, 1.06)
                rel = (aa * bb) / (200 * 68 * k * k)
                hs = np.clip(0.62 + 0.25 * rel ** 0.5 + rng.normal(0, 0.06), 0.55, 1.0)
                canvas.add(rng, cx, cy + rng.normal(0, 0.07) * ch, aa, bb, rng.normal(0, 0.07),
                        rng.uniform(2.0, 3.0), hs)
                sizes.append(rel)
            x += wd
        y += ch

    # Guijarros en los huecos que dejan las grandes: cada uno del tamaño de su hueco.
    pad = int(160 * k)
    bg = np.pad(canvas.label < 0, pad, mode="wrap")
    dist = ndimage.distance_transform_edt(bg)[pad:-pad, pad:-pad]
    cand = np.argwhere(dist > 6 * k)
    order = np.argsort(-(dist[cand[:, 0], cand[:, 1]] + rng.uniform(0, 8 * k, len(cand))))
    placed = 0
    for yy, xx in cand[order]:
        if placed >= 900:
            break
        if canvas.label[yy, xx] >= 0:
            continue
        rad = dist[yy, xx] * rng.uniform(1.0, 1.35)
        aa = rad * rng.uniform(1.0, 1.6)
        bb = rad * rng.uniform(0.75, 1.0)
        hs = rng.uniform(0.32, 0.55) * min(1.0, (rad / (35 * k)) ** 0.3)
        if canvas.add(rng, xx, yy, aa, bb, rng.uniform(0, np.pi), rng.uniform(2.0, 2.5), hs) >= 0:
            sizes.append(0.15)
            placed += 1

    n = canvas.count
    base = STONE_PALETTE[rng.choice(len(STONE_PALETTE), n, p=STONE_WEIGHTS / STONE_WEIGHTS.sum())]
    base = base * rng.uniform(0.86, 1.1, (n, 1))
    second = STONE_PALETTE[rng.choice(len(STONE_PALETTE), n)]
    mix_amt = rng.uniform(0.0, 0.45, n)
    stone_rough = rng.uniform(0.62, 0.88, n)

    label = canvas.label
    is_stone = label >= 0
    li = np.where(is_stone, label, 0)
    mottle = noise(rng, (H, W), 24 * k)
    patch = noise(rng, (H, W), 45 * k)
    fine = noise(rng, (H, W), 5 * k)
    speck = noise(rng, (H, W), 1.0 * k)

    col = lerp(base[li], second[li], (smoothstep(0.2, 1.4, patch) * mix_amt[li])[..., None])
    col = col * (1.0 + 0.07 * mottle + 0.05 * fine + 0.05 * speck)[..., None]
    col = col * (1.0 - 0.07 * canvas.vlocal)[..., None]  # algo más claras arriba, más sucias abajo
    col = col * (0.6 + 0.4 * smoothstep(0.0, 0.55, canvas.prof))[..., None]

    gap_n = noise(rng, (H, W), 2.0 * k)
    gap_col = STONE_GAP * (1.0 + 0.3 * gap_n + 0.1 * mottle)[..., None]
    albedo = np.where(is_stone[..., None], col, gap_col)

    height = np.where(is_stone, canvas.height, 0.03 + 0.02 * gap_n + 0.01 * mottle)
    height = np.clip(height, 0.0, 1.0)
    rough = np.where(is_stone, stone_rough[li] + 0.04 * fine, 0.96)
    ao = cavity_ao(height, [(22 * k, 1.0), (4 * k, 2.5)], 0.2)
    relief_m = 0.07
    return Maps(np.clip(albedo, 0, 1), height, np.clip(rough, 0, 1), ao,
            normal_from_height(height * relief_m, px_m), relief_m)


# --- Salida -------------------------------------------------------------------------------------

def to_u8(x: np.ndarray) -> np.ndarray:
    return np.clip(np.round(x * 255.0), 0, 255).astype(np.uint8)


def write_maps(name: str, maps: Maps) -> None:
    folder = OUT_DIR / name
    folder.mkdir(parents=True, exist_ok=True)
    orm = np.stack([maps.ao, maps.roughness, np.zeros_like(maps.ao)], axis=-1)
    images = {
        "albedo": (Image.fromarray(to_u8(maps.albedo), "RGB"), False),
        "normal": (Image.fromarray(to_u8(maps.normal * 0.5 + 0.5), "RGB"), True),
        "orm": (Image.fromarray(to_u8(orm), "RGB"), False),
        "height": (Image.fromarray(to_u8(maps.height), "L"), False),
    }
    for kind, (img, is_normal) in images.items():
        path = folder / f"{name}_{kind}.png"
        img.save(path, optimize=True)
        imp = path.with_name(path.name + ".import")
        # Godot añade el uid al importar: no se pisa un .import que ya exista.
        if not imp.exists():
            res = "res://" + path.relative_to(ROOT).as_posix()
            imp.write_text(IMPORT_SETTINGS.format(resource=res, normal_map=1 if is_normal else 0,
                    high_quality="true" if kind == "albedo" else "false"))
        print(f"  {path.relative_to(ROOT)}")
    print(f"  relieve {maps.relief_m:.3f} m -> heightmap_scale ~ {maps.relief_m / (0.01 * TILE_METERS):.2f}")


def write_preview(name: str, maps: Maps, folder: Path) -> None:
    """Render plano con luz rasante, sin parallax: para revisar el relieve y el tileado."""
    folder.mkdir(parents=True, exist_ok=True)
    light = np.array([-0.5, 0.55, 0.67])
    light /= np.linalg.norm(light)
    diff = np.clip(maps.normal @ light, 0.0, 1.0)
    lin = maps.albedo ** 2.2
    shade = lin * (0.3 * maps.ao + 1.0 * diff)[..., None]
    img = to_u8(np.clip(shade, 0, 1) ** (1 / 2.2))
    full = Image.fromarray(img, "RGB")
    half = full.resize((full.width // 2, full.height // 2), Image.LANCZOS)
    tiled = Image.new("RGB", (half.width * 2, half.height * 2))
    for oy in (0, half.height):
        for ox in (0, half.width):
            tiled.paste(half, (ox, oy))
    tiled.resize((1024, 1024), Image.LANCZOS).save(folder / f"{name}_tiled.png")
    c = full.width // 2
    full.crop((c - 384, c - 384, c + 384, c + 384)).save(folder / f"{name}_crop.png")
    Image.fromarray(to_u8(maps.albedo)).resize((1024, 1024), Image.LANCZOS).save(folder / f"{name}_albedo.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--size", type=int, default=2048)
    parser.add_argument("--only", choices=["logs", "stone"])
    parser.add_argument("--preview", type=Path, help="carpeta donde dejar renders de revisión")
    args = parser.parse_args()

    jobs = {
        "stacked_logs": lambda: make_logs(args.size, 7),
        "stacked_stone": lambda: make_stone(args.size, 11),
    }
    for name, job in jobs.items():
        if args.only and not name.endswith(args.only):
            continue
        print(name)
        maps = job()
        write_maps(name, maps)
        if args.preview:
            write_preview(name, maps, args.preview)


if __name__ == "__main__":
    main()
