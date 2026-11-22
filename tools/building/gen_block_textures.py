#!/usr/bin/env python3
"""Genera texturas de construcción: troncos apilados, muro de piedra, paja, enlucido, tablas,
tejuelas, tepe, sillería y lona.

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
    from scipy import ndimage

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
    from scipy import ndimage

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


# --- Paja ---------------------------------------------------------------------------------------

def make_thatch(size: int, seed: int) -> Maps:
    """Haces secos con tallos a lo largo de V. Solo necesita numpy y Pillow."""
    rng = np.random.default_rng(seed)
    k = size / 1024.0
    y, x = np.mgrid[:size, :size] / size
    shape = (size, size)
    warp = noise(rng, shape, 28 * k, 85 * k)
    stems = x * 300 + 0.55 * noise(rng, shape, 3 * k, 65 * k) + 0.20 * warp
    stem_id = np.floor(stems).astype(int) % 300
    strand = (0.5 - 0.5 * np.cos(stems * np.pi * 2)) ** 0.7
    bundles = (0.5 + 0.5 * np.cos((x * 14 + 0.08 * warp) * np.pi * 2)) ** 0.7
    tint = noise(rng, shape, 1.6 * k, 55 * k)
    weather = noise(rng, shape, 38 * k, 45 * k)
    stem_tint = rng.uniform(0.72, 1.16, 300)[stem_id]
    phase = rng.uniform(0, 2 * np.pi, 300)[stem_id]
    ends = smoothstep(0.78, 0.97, np.cos(y * 12 * np.pi + phase + 0.18 * warp))
    grit = noise(rng, shape, 0.55 * k, 1.8 * k)
    height = np.clip(0.22 + 0.42 * strand + 0.20 * bundles + 0.04 * tint - 0.07 * ends, 0, 1)
    dark = np.array([0.38, 0.29, 0.15])
    light = np.array([0.74, 0.64, 0.41])
    value = np.clip(0.28 + 0.44 * strand + 0.12 * bundles + 0.10 * tint, 0, 1)
    albedo = lerp(dark, light, value[..., None])
    albedo *= (stem_tint + 0.055 * weather - 0.16 * ends + 0.035 * grit)[..., None]
    ao = cavity_ao(height, [(4 * k, 1.3), (1.2 * k, 0.8)], 0.60)
    rough = np.clip(0.92 + 0.025 * grit, 0.82, 1)
    relief_m = 0.012
    return Maps(np.clip(albedo, 0, 1), height, rough, ao,
                normal_from_height(height * relief_m, TILE_METERS / size), relief_m)


# --- Enlucido de cal ----------------------------------------------------------------------------

def make_plaster(size: int, seed: int) -> Maps:
    """Barro enlucido y encalado: blanco roto a manchas, pasadas de llana, grietas finas y algún
    desconchón donde asoma el barro."""
    rng = np.random.default_rng(seed)
    k = size / 1024.0
    shape = (size, size)
    broad = noise(rng, shape, 60 * k)
    mottle = noise(rng, shape, 14 * k)
    trowel = noise(rng, shape, 22 * k, 6 * k)
    fine = noise(rng, shape, 1.2 * k)
    pits = noise(rng, shape, 0.8 * k)
    # Grietas: las crestas de un ruido de grano medio, finas y solo en parte de la pared.
    crack_field = noise(rng, shape, 9 * k)
    crack = smoothstep(0.93, 1.0, 1.0 - np.abs(crack_field) * 3.2)
    crack *= smoothstep(0.3, 1.2, noise(rng, shape, 45 * k))
    # Desconchones: manchas donde falta la cal y se ve el barro, con el borde algo levantado.
    flake_field = noise(rng, shape, 40 * k) + 0.3 * noise(rng, shape, 5 * k)
    flake = smoothstep(2.5, 2.65, flake_field)
    rim = smoothstep(2.3, 2.5, flake_field) * (1.0 - flake)
    streaks = smoothstep(0.4, 2.0, noise(rng, shape, 5 * k, 70 * k)) * smoothstep(-0.5, 1.0, broad)

    lime = np.array([0.86, 0.83, 0.76])
    lime_dirty = np.array([0.74, 0.70, 0.61])
    daub = np.array([0.50, 0.40, 0.29])
    t = np.clip(0.45 + 0.45 * broad + 0.15 * mottle, 0, 1)
    albedo = lerp(lime, lime_dirty, t[..., None] * 0.55)
    albedo *= (1.0 + 0.025 * fine + 0.03 * trowel - 0.10 * streaks)[..., None]
    albedo = lerp(albedo, daub * (1.0 + 0.08 * mottle)[..., None], flake[..., None])
    albedo *= (1.0 - 0.45 * crack)[..., None]

    height = 0.55 + 0.10 * trowel + 0.05 * mottle + 0.015 * fine - 0.03 * smoothstep(1.6, 2.6, -pits)
    height = height - 0.35 * flake + 0.06 * rim - 0.25 * crack
    height = np.clip(height, 0, 1)
    rough = np.clip(0.9 + 0.04 * fine - 0.04 * flake, 0.75, 1.0)
    ao = cavity_ao(height, [(6 * k, 1.2), (1.5 * k, 1.5)], 0.45)
    relief_m = 0.012
    return Maps(np.clip(albedo, 0, 1), height, rough, ao,
                normal_from_height(height * relief_m, TILE_METERS / size), relief_m)


# --- Tablas -------------------------------------------------------------------------------------

def make_planks(size: int, seed: int) -> Maps:
    """Tablas de pie, de anchos sueltos, con su veta, nudos, juntas y una pátina de brea."""
    rng = np.random.default_rng(seed)
    k = size / 1024.0
    shape = (size, size)
    y, x = np.mgrid[:size, :size].astype(np.float64)
    # Anchos de 16 a 28 cm que suman la tesela.
    widths = []
    while sum(widths) < size:
        widths.append(rng.uniform(0.16, 0.28) / TILE_METERS * size)
    widths = np.array(widths) * size / sum(widths)
    edges = np.concatenate([[0.0], np.cumsum(widths)])
    col_id = np.clip(np.searchsorted(edges, x[0], side="right") - 1, 0, len(widths) - 1)
    board = np.broadcast_to(col_id[None, :], shape)
    left = edges[board]
    across = (x - left) / widths[board]  # 0-1 dentro de la tabla
    n = len(widths)
    tint = rng.uniform(0.82, 1.15, n)[board]
    lift = rng.uniform(-0.06, 0.06, n)[board]
    # Veta: líneas a lo largo de V que ondulan, distintas en cada tabla.
    phase = rng.uniform(0, 100, n)[board]
    warp = noise(rng, shape, 6 * k, 90 * k)
    grain = np.sin((across * 9.0 + phase + 0.6 * warp) * np.pi * 2)
    grain_fine = noise(rng, shape, 0.7 * k, 30 * k)
    # Nudos: unas pocas manchas elípticas oscuras.
    knots = np.zeros(shape)
    for _ in range(int(14)):
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        rx, ry = rng.uniform(5, 9) * k, rng.uniform(9, 16) * k
        dx = wrap(x - cx, size) / rx
        dy = wrap(y - cy, size) / ry
        knots = np.maximum(knots, np.clip(1.0 - (dx * dx + dy * dy), 0, 1))
    gap = 1.0 - smoothstep(0.0, 0.035, np.minimum(across, 1.0 - across))
    edge_round = smoothstep(0.0, 0.12, np.minimum(across, 1.0 - across))
    weather = noise(rng, shape, 40 * k)

    light = np.array([0.46, 0.33, 0.22])
    dark = np.array([0.24, 0.16, 0.10])
    grey = np.array([0.42, 0.39, 0.35])
    v = np.clip(0.5 + 0.22 * grain + 0.18 * grain_fine, 0, 1)
    albedo = lerp(dark, light, v[..., None]) * tint[..., None]
    albedo = lerp(albedo, grey * tint[..., None], np.clip(0.25 + 0.2 * weather, 0, 0.6)[..., None])
    albedo = lerp(albedo, np.array([0.12, 0.07, 0.04]), (knots ** 0.6 * 0.85)[..., None])
    albedo = lerp(albedo, np.array([0.06, 0.045, 0.03]), gap[..., None])

    height = 0.6 + lift + 0.06 * grain + 0.03 * grain_fine - 0.05 * knots
    height = height * (0.55 + 0.45 * edge_round)
    height = np.clip(height * (1.0 - gap), 0, 1)
    rough = np.clip(0.8 + 0.08 * grain_fine, 0.6, 1.0)
    ao = cavity_ao(height, [(5 * k, 1.5), (1.2 * k, 1.0)], 0.3)
    relief_m = 0.02
    return Maps(np.clip(albedo, 0, 1), height, rough, ao,
                normal_from_height(height * relief_m, TILE_METERS / size), relief_m)


# --- Tejuelas -----------------------------------------------------------------------------------

def make_shingles(size: int, seed: int) -> Maps:
    """Tejuelas de madera en hiladas de 25 cm (las del faldón), con la punta redondeada como en
    las iglesias de madera: cada hilada tapa la cabeza de la de abajo. V baja por la pendiente."""
    rng = np.random.default_rng(seed)
    k = size / 1024.0
    shape = (size, size)
    rows = 8  # 2 m / 25 cm
    row_h = size / rows
    y, x = np.mgrid[:size, :size].astype(np.float64)
    grain_n = noise(rng, shape, 0.8 * k, 20 * k)
    weather = noise(rng, shape, 35 * k)
    moss = smoothstep(1.2, 2.2, noise(rng, shape, 20 * k)) * 0.6

    # Cada hilada: anchos sueltos y desfase propio.
    per_row = []
    for r in range(rows):
        widths = []
        while sum(widths) < size:
            widths.append(rng.uniform(0.11, 0.17) / TILE_METERS * size)
        widths = np.array(widths) * size / sum(widths)
        per_row.append((np.concatenate([[0.0], np.cumsum(widths)]), rng.uniform(0, size),
                        rng.uniform(0.8, 1.15, len(widths)), rng.uniform(-0.04, 0.04, len(widths))))

    def locate(r: int, xx: np.ndarray):
        edges, offset, tints, lifts = per_row[r % rows]
        xs = np.mod(xx - offset, size)
        i = np.clip(np.searchsorted(edges, xs, side="right") - 1, 0, len(edges) - 2)
        w = edges[i + 1] - edges[i]
        s = (xs - edges[i]) / w
        return i, s, tints[i], lifts[i]

    height = np.zeros(shape)
    albedo = np.zeros(shape + (3,))
    tint_map = np.ones(shape)
    edge_dark = np.zeros(shape)
    row_idx = np.floor(y / row_h).astype(int)
    t = y / row_h - row_idx  # 0 arriba de la hilada, 1 abajo
    BULGE = 0.38
    for r in range(rows):
        m = row_idx == r
        xx = x[m]
        tt = t[m]
        # ¿Lo tapa la punta de la tejuela de la hilada de encima?
        _, s_up, tint_up, lift_up = locate(r - 1, xx)
        tip_up = 1.0 + BULGE * np.sqrt(np.clip(1.0 - (2 * s_up - 1) ** 2, 0, 1))
        covered = (tt + 1.0) < tip_up
        _, s_own, tint_own, lift_own = locate(r, xx)
        # Altura: crece hacia la punta; la de encima va más alta.
        h_own = 0.25 + 0.45 * tt + lift_own
        h_up = 0.25 + 0.45 * np.clip(tt + 1.0, 0, 1.0 + BULGE) / (1.0 + BULGE) * (1.0 + BULGE) * 0.75 + 0.25 + lift_up
        s_use = np.where(covered, s_up, s_own)
        side = smoothstep(0.0, 0.06, np.minimum(s_use, 1.0 - s_use))
        h = np.where(covered, h_up, h_own) * (0.6 + 0.4 * side)
        # La sombra justo bajo la punta de la de encima.
        under = np.where(covered, 0.0, smoothstep(0.25, 0.0, (tt + 1.0) - tip_up + 0.0))
        height[m] = h
        tint_map[m] = np.where(covered, tint_up, tint_own)
        edge_dark[m] = np.maximum(1.0 - side, under * 0.8)
    height = np.clip(height / height.max(), 0, 1)

    fresh = np.array([0.52, 0.40, 0.28])
    grey = np.array([0.45, 0.42, 0.38])
    dark = np.array([0.20, 0.15, 0.11])
    a = np.clip(0.45 + 0.2 * weather, 0, 1)
    albedo = lerp(fresh, grey, a[..., None]) * (tint_map * (1.0 + 0.10 * grain_n))[..., None]
    albedo = lerp(albedo, dark, (edge_dark * 0.75)[..., None])
    albedo = lerp(albedo, np.array([0.30, 0.34, 0.17]), (moss * smoothstep(0.3, 0.8, height))[..., None])
    rough = np.clip(0.85 + 0.06 * grain_n, 0.7, 1.0)
    ao = cavity_ao(height, [(8 * k, 1.4), (2 * k, 1.0)], 0.3)
    relief_m = 0.03
    return Maps(np.clip(albedo, 0, 1), height, rough, ao,
                normal_from_height(height * relief_m, TILE_METERS / size), relief_m)


# --- Tepe ---------------------------------------------------------------------------------------

def make_turf(size: int, seed: int) -> Maps:
    """Tepe de los tejados de hierba: matas de hierba que caen por la pendiente (a lo largo de V),
    entre verde y pajiza, con musgo, tierra en los claros y alguna flor."""
    rng = np.random.default_rng(seed)
    k = size / 1024.0
    shape = (size, size)
    clumps = noise(rng, shape, 18 * k)
    patches = noise(rng, shape, 55 * k)
    dry = noise(rng, shape, 30 * k)
    # Hojas: ruido muy alargado a lo largo de V, en dos escalas, algo torcido.
    blades = np.zeros(shape)
    for sx, sy, gain in [(1.0, 9.0, 1.0), (1.6, 16.0, 0.8), (0.7, 5.0, 0.6)]:
        b = noise(rng, shape, sx * k, sy * k)
        blades = np.maximum(blades, gain * smoothstep(0.6, 1.8, b))
    density = smoothstep(-2.6, -0.6, clumps + 0.4 * patches)
    blades = np.clip(blades * (0.55 + 0.45 * density) + 0.25 * smoothstep(-0.5, 1.5, noise(rng, shape, 0.6 * k, 4 * k)), 0, 1)
    soil = 1.0 - smoothstep(0.0, 0.5, density)
    moss = smoothstep(0.2, 1.4, -clumps) * (1.0 - soil) * 0.6
    flowers_n = noise(rng, shape, 1.4 * k)
    flowers = smoothstep(3.1, 3.4, flowers_n) * smoothstep(0.0, 1.0, patches)

    green = np.array([0.36, 0.44, 0.18])
    deep = np.array([0.20, 0.27, 0.10])
    straw = np.array([0.60, 0.55, 0.32])
    mossc = np.array([0.32, 0.38, 0.15])
    soilc = np.array([0.24, 0.18, 0.12])
    tip = np.clip(0.45 + 0.35 * dry + 0.25 * patches, 0, 1)
    grass = lerp(deep, lerp(green, straw, (tip * 0.6)[..., None]), np.clip(blades, 0, 1)[..., None])
    albedo = lerp(grass, mossc * (1.0 + 0.1 * patches)[..., None], (moss * (1.0 - blades) * 0.8)[..., None])
    albedo = lerp(albedo, soilc, (soil * (1.0 - blades))[..., None])
    albedo = lerp(albedo, np.array([0.85, 0.82, 0.55]), flowers[..., None])

    height = 0.25 + 0.45 * blades + 0.15 * moss + 0.1 * density + 0.1 * flowers
    height = np.clip(height, 0, 1)
    rough = np.clip(0.88 + 0.05 * blades, 0.8, 1.0)
    ao = cavity_ao(height, [(4 * k, 1.6), (1 * k, 1.0)], 0.35)
    relief_m = 0.03
    return Maps(np.clip(albedo, 0, 1), height, rough, ao,
                normal_from_height(height * relief_m, TILE_METERS / size), relief_m)


# --- Sillería -----------------------------------------------------------------------------------

def make_ashlar(size: int, seed: int) -> Maps:
    """Sillares labrados en hiladas de 33 a 50 cm, con el canto biselado, huellas de cincel y
    juntas de argamasa."""
    rng = np.random.default_rng(seed)
    k = size / 1024.0
    shape = (size, size)
    y, x = np.mgrid[:size, :size].astype(np.float64)
    # Hiladas que suman la tesela.
    heights = []
    while sum(heights) < size:
        heights.append(rng.choice([0.33, 0.4, 0.5]) / TILE_METERS * size)
    heights = np.array(heights) * size / sum(heights)
    yedges = np.concatenate([[0.0], np.cumsum(heights)])
    row = np.clip(np.searchsorted(yedges, y[:, 0], side="right") - 1, 0, len(heights) - 1)
    row = np.broadcast_to(row[:, None], shape)
    down = (y - yedges[row]) / heights[row]
    label = np.zeros(shape, dtype=np.int64)
    across = np.zeros(shape)
    width_px = np.zeros(shape)
    count = 0
    for r in range(len(heights)):
        widths = []
        while sum(widths) < size:
            widths.append(rng.uniform(0.45, 0.9) / TILE_METERS * size)
        widths = np.array(widths) * size / sum(widths)
        xedges = np.concatenate([[0.0], np.cumsum(widths)])
        offset = rng.uniform(0, size)
        m = row == r
        xs = np.mod(x[m] - offset, size)
        i = np.clip(np.searchsorted(xedges, xs, side="right") - 1, 0, len(widths) - 1)
        across[m] = (xs - xedges[i]) / widths[i]
        width_px[m] = widths[i]
        label[m] = count + i
        count += len(widths)
    hpx = heights[row]
    # Distancia al borde del sillar, en píxeles.
    edge_px = np.minimum(np.minimum(across, 1 - across) * width_px, np.minimum(down, 1 - down) * hpx)
    joint = 1.0 - smoothstep(2.0 * k, 3.5 * k, edge_px)
    bevel = smoothstep(2.5 * k, 12 * k, edge_px)
    chisel = noise(rng, shape, 1.0 * k, 3.0 * k)
    face = noise(rng, shape, 20 * k)
    grit = noise(rng, shape, 0.7 * k)

    palette = np.array([[0.62, 0.60, 0.56], [0.56, 0.55, 0.52], [0.66, 0.62, 0.55],
                        [0.52, 0.50, 0.47], [0.60, 0.56, 0.49]])
    base = palette[rng.integers(0, len(palette), count)] * rng.uniform(0.9, 1.08, (count, 1))
    col = base[label] * (1.0 + 0.05 * face + 0.04 * chisel + 0.04 * grit)[..., None]
    col *= (0.75 + 0.25 * bevel)[..., None]
    mortar = np.array([0.70, 0.67, 0.60]) * (1.0 + 0.06 * grit)[..., None]
    albedo = lerp(col, mortar, joint[..., None])

    height = 0.35 + 0.55 * bevel + 0.03 * chisel + 0.03 * face
    height = np.where(joint > 0.5, 0.15 + 0.03 * grit, height)
    height = np.clip(height, 0, 1)
    rough = np.where(joint > 0.5, 0.95, np.clip(0.8 + 0.05 * chisel, 0.6, 1.0))
    ao = cavity_ao(height, [(10 * k, 1.0), (2 * k, 1.5)], 0.3)
    relief_m = 0.035
    return Maps(np.clip(albedo, 0, 1), height, rough, ao,
                normal_from_height(height * relief_m, TILE_METERS / size), relief_m)


# --- Lona ---------------------------------------------------------------------------------------

def make_cloth(size: int, seed: int) -> Maps:
    """Lona de lana tejida a rayas rojas y crudas de 25 cm, a lo largo de V (bajan por el toldo)."""
    rng = np.random.default_rng(seed)
    k = size / 1024.0
    shape = (size, size)
    y, x = np.mgrid[:size, :size].astype(np.float64)
    stripe = np.floor(x / (size / 8)).astype(int) % 2
    weave_f = size / 2.0 / 0.004 / (size / 2.0)  # un hilo cada 4 mm
    warp_t = np.sin(x / size * TILE_METERS / 0.004 * np.pi)
    weft_t = np.sin(y / size * TILE_METERS / 0.004 * np.pi)
    weave = warp_t * weft_t
    slub = noise(rng, shape, 0.6 * k, 8 * k)
    fade = noise(rng, shape, 50 * k)
    dirt = smoothstep(1.5, 3.0, noise(rng, shape, 60 * k))
    red = np.array([0.55, 0.13, 0.09])
    cream = np.array([0.80, 0.74, 0.60])
    albedo = np.where(stripe[..., None] == 1, red, cream)
    albedo = albedo * (1.0 + 0.06 * weave + 0.05 * slub + 0.04 * fade)[..., None]
    albedo = lerp(albedo, np.array([0.35, 0.30, 0.24]), (dirt * 0.35)[..., None])
    height = np.clip(0.5 + 0.25 * weave + 0.1 * slub, 0, 1)
    rough = np.full(shape, 0.95)
    ao = cavity_ao(height, [(1 * k, 0.8)], 0.7)
    relief_m = 0.002
    return Maps(np.clip(albedo, 0, 1), height, rough, ao,
                normal_from_height(height * relief_m, TILE_METERS / size), relief_m)


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
    parser.add_argument("--size", type=int, default=0, help="lado en píxeles (0: el de cada material)")
    parser.add_argument("--only", choices=["logs", "stone", "thatch", "plaster", "planks", "shingles", "turf",
                                           "ashlar", "cloth"])
    parser.add_argument("--preview", type=Path, help="carpeta donde dejar renders de revisión")
    args = parser.parse_args()

    def px(default: int) -> int:
        return args.size or default

    jobs = {
        "stacked_logs": lambda: make_logs(px(2048), 7),
        "stacked_stone": lambda: make_stone(px(2048), 11),
        "thatch": lambda: make_thatch(px(1024), 23),
        "plaster": lambda: make_plaster(px(1024), 31),
        "planks": lambda: make_planks(px(1024), 37),
        "shingles": lambda: make_shingles(px(1024), 41),
        "turf": lambda: make_turf(px(1024), 43),
        "ashlar": lambda: make_ashlar(px(1024), 47),
        "cloth": lambda: make_cloth(px(1024), 53),
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
