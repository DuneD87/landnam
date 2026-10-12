#!/usr/bin/env python3
"""Hornea la consola de la barra rápida: textures/ui/hotbar_console.png.

Consola compacta de hierro forjado: un riel biselado conecta dos cápsulas circulares para
vida y aguante. Cada engaste lleva una banda de runas, los canales de necesidades y sus
medallones. En el centro asoma el engaste de la media orbe de cordura. Las abrazaderas y la
trenza quedan talladas en el metal. Aparte sale hotbar_breath_runes.png: las runas del aguante
solas, que BreathRing enciende como medidor del oxígeno.

El hierro y el bronce llevan biseles iluminados desde arriba a la izquierda, pátina tenue y
sombras en los engastes. Las runas y las ramas quedan por debajo del brillo de los objetos.
Las formas son campos de distancia con signo, así que los bordes salen suavizados sin
sobremuestrear. Las medidas son las de la barra a 1440 px
de alto (las de Hotbar y GameTheme: diez cartuchos de 88 × 108 px, orbes de radio 76...) y la imagen va a
ART píxeles por cada uno, para que a 4K siga nítida. Si cambian, hay que cambiarlas aquí, en Hotbar
(ORB_*, SANITY_RADIUS, GAUGE_*, MEDALLION_*, GAUGES), en VitalsPlate (BAR_ORIGIN, REACH) y en
breath_runes.gdshader (band_in, band_out), que este script imprime al acabar.

    build/fauna_tools/bin/python -I tools/ui/bake_hotbar_console.py
    godot --headless --editor --quit --path .   # importa las texturas
"""

import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "textures", "ui", "hotbar_console.png")
MASK_OUT = os.path.join(os.path.dirname(OUT), "hotbar_breath_runes.png")

ART = 2.0
# La barra (el panel con sus huecos), en píxeles base relativos a su esquina de arriba a la
# izquierda, y el borde de abajo de la pantalla.
BAR_W, BAR_H = 976.0, 132.0
SCREEN_Y = BAR_H + 28.0
CENTRE_X = BAR_W * 0.5
# Orbes (Hotbar.ORB_*) y sus engastes.
ORB_R, ORB_GAP, ORB_DROP = 76.0, 16.0, 12.0
HOUSING = 96.0
LEFT = (-(ORB_GAP + ORB_R), BAR_H - ORB_R + ORB_DROP)
RIGHT = (BAR_W - LEFT[0], LEFT[1])
# Banda de runas entre dos filetes, por fuera del aro de la orbe.
RUNE_IN, RUNE_OUT = 79.0, 91.0
# Media orbe de la cordura (Hotbar.SANITY_RADIUS), con el centro en el borde de arriba de la
# barra, y su engaste con media banda de runas.
SANITY_R = 35.0
DOME_CENTRE = (BAR_W * 0.5, -6.0)
DOME_RUNE_IN, DOME_RUNE_OUT = 37.5, 45.5
DOME = 48.5
# Medidores de las necesidades (Hotbar.GAUGE_*): el canal alrededor de cada engaste, de radio
# GAUGE_R y medio ancho GAUGE_HALF, y los medallones de sus iconos, a MEDALLION_AT del centro.
GAUGE_R, GAUGE_HALF = 101.0, 4.5
MEDALLION_AT, MEDALLION_R = 111.0, 16.0
# Los iconos se dibujan en una caja de unos 18 px y se agrandan esto.
ICON_SCALE = 1.1
# La máscara de las runas del aguante, para el oxígeno (BreathRing): medio lado.
MASK_HALF = 100.0
# La placa asoma un poco por encima de la barra; el filete interior va a INSET del borde.
BAND_TOP = -9.0
INSET = 7.0
# Lienzo, en píxeles base.
X0, X1 = -240.0, BAR_W + 240.0
# Dos píxeles base de sangrado evitan rendijas por el redondeo de la escala de la ventana.
Y0, Y1 = -82.0, SCREEN_Y + 2.0
W = int(round((X1 - X0) * ART))
H = int(round((Y1 - Y0) * ART))


def rgb(hex_code):
    return np.array([int(hex_code[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


# Cara iluminada del hierro de Saga y bronce envejecido.
IRON = rgb("2a2e34")
IRON_ALPHA = 0.93
IRON_DEEP = np.array([0.02, 0.022, 0.027], np.float32)
# Lo que va encima de la placa (tallos, raíces): el mismo hierro, apenas más claro.
IRON_RAISED = rgb("34383e")
BRONZE = rgb("c9a46a")
BRONZE_DARK = rgb("6e5a38")
INK = rgb("16130f")

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
BX = (xx + 0.5) / ART + X0
BY = (yy + 0.5) / ART + Y0
del xx, yy

# Lienzo con alfa premultiplicado.
CANVAS = np.zeros((H, W, 4), np.float32)
# Textura determinista y de bajo contraste: cada horneado produce el mismo acabado.
PATINA = (np.sin(BX * 0.021 + BY * 0.031) * np.sin(BX * 0.009 - BY * 0.037)).astype(np.float32)
GRAIN = (np.sin(BX * 2.13 + BY * 3.79) * np.sin(BX * 5.17 - BY * 1.63)).astype(np.float32)


# --- Campos de distancia --------------------------------------------------------------------------

def coverage(d):
    """Cuánto de cada píxel cae dentro (d < 0), con el borde suavizado un píxel."""
    return np.clip(0.5 - d * ART, 0.0, 1.0)


def band_of(d, width, offset=0.0):
    """Filete de [width] píxeles base por dentro del borde, metido [offset]."""
    return np.clip(coverage(d + offset) - coverage(d + offset + width), 0.0, 1.0)


def sd_circle(c, r):
    return np.hypot(BX - c[0], BY - c[1]) - r


def sd_box(a, b):
    cx, cy = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
    hx, hy = (b[0] - a[0]) * 0.5, (b[1] - a[1]) * 0.5
    dx = np.abs(BX - cx) - hx
    dy = np.abs(BY - cy) - hy
    return np.hypot(np.maximum(dx, 0), np.maximum(dy, 0)) + np.minimum(np.maximum(dx, dy), 0)


def sd_chamfer(a, b, cut):
    box = sd_box(a, b)
    cx, cy = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
    hx, hy = (b[0] - a[0]) * 0.5, (b[1] - a[1]) * 0.5
    corner = (np.abs(BX - cx) + np.abs(BY - cy) - hx - hy + cut) * 0.7071
    return np.maximum(box, corner)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def sd_stroke(points, radii, reach=10.0):
    """Trazo de grosor variable: la distancia a la polilínea menos el radio en cada punto. Solo
    se calcula hasta [reach] píxeles base del trazo (más allá queda infinito)."""
    d = np.full((H, W), np.inf, np.float32)
    for i in range(len(points) - 1):
        a, b = points[i], points[i + 1]
        ra, rb = radii[i], radii[i + 1]
        m = max(ra, rb) + reach
        x0 = max(0, int((min(a[0], b[0]) - m - X0) * ART))
        x1 = min(W, int((max(a[0], b[0]) + m - X0) * ART) + 1)
        y0 = max(0, int((min(a[1], b[1]) - m - Y0) * ART))
        y1 = min(H, int((max(a[1], b[1]) + m - Y0) * ART) + 1)
        if x0 >= x1 or y0 >= y1:
            continue
        px = BX[y0:y1, x0:x1] - a[0]
        py = BY[y0:y1, x0:x1] - a[1]
        ex, ey = b[0] - a[0], b[1] - a[1]
        length2 = ex * ex + ey * ey
        h = np.clip((px * ex + py * ey) / length2, 0.0, 1.0) if length2 > 1e-9 else 0.0
        dist = np.hypot(px - ex * h, py - ey * h) - (ra + (rb - ra) * h)
        np.minimum(d[y0:y1, x0:x1], dist, out=d[y0:y1, x0:x1])
    return d


def paint(cov, color, alpha=1.0):
    a = cov * alpha
    CANVAS[..., :3] = CANVAS[..., :3] * (1.0 - a)[..., None] + color * a[..., None]
    CANVAS[..., 3] = CANVAS[..., 3] * (1.0 - a) + a


def forge(d, color, alpha=1.0, bevel=2.5, grain=0.002):
    """Pátina, grano fino y bisel con luz arriba a la izquierda. Limitar el campo evita
    infinitos en los trazos sin alterar la silueta ni su suavizado."""
    field = np.clip(d, -16.0, 16.0)
    gy, gx = np.gradient(field, 1.0 / ART)
    norm = np.maximum(np.hypot(gx, gy), 1e-4)
    light = (-gx * 0.45 - gy * 0.89) / norm
    edge = np.clip(1.0 + d / bevel, 0.0, 1.0)
    face = color[None, None, :] * (1.0 + PATINA[..., None] * 0.055)
    face = face + GRAIN[..., None] * grain
    face = face + (edge * light)[..., None] * (color * 0.3 + 0.045)
    paint(coverage(d), np.clip(face, 0.0, 1.0), alpha)


def metal_line(d, width, offset=0.0, alpha=1.0):
    """Filete de bronce envejecido con una cara clara y otra oscura."""
    field = np.clip(d, -16.0, 16.0)
    gy, gx = np.gradient(field, 1.0 / ART)
    norm = np.maximum(np.hypot(gx, gy), 1e-4)
    light = (-gx * 0.45 - gy * 0.89) / norm
    tint = BRONZE[None, None, :] * (0.72 + 0.28 * light[..., None])
    tint = tint * (1.0 + PATINA[..., None] * 0.065)
    paint(band_of(d, width, offset), tint, alpha)


# --- Trazados -------------------------------------------------------------------------------------

def resample(points, step=1.25):
    points = np.asarray(points, np.float64)
    seg = np.hypot(*np.diff(points, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    n = max(2, int(math.ceil(s[-1] / step)) + 1)
    t = np.linspace(0.0, s[-1], n)
    return np.stack([np.interp(t, s, points[:, 0]), np.interp(t, s, points[:, 1])], axis=1)


def spline(ctrl, step=1.25):
    """Catmull-Rom centrípeta por los puntos de control (sin bucles ni picos)."""
    p = np.asarray(ctrl, np.float64)
    p = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        t0 = 0.0
        t1 = t0 + max(np.linalg.norm(p1 - p0), 1e-6) ** 0.5
        t2 = t1 + max(np.linalg.norm(p2 - p1), 1e-6) ** 0.5
        t3 = t2 + max(np.linalg.norm(p3 - p2), 1e-6) ** 0.5
        n = max(4, int(np.linalg.norm(p2 - p1) / 0.5))
        for t in np.linspace(t1, t2, n, endpoint=False):
            a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            out.append((t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2)
    out.append(p[-2])
    return resample(out, step)


def on_ring(centre, r, degrees):
    """Punto del círculo a [degrees] de lo alto, en el sentido de las agujas del reloj."""
    a = math.radians(degrees)
    return (centre[0] + r * math.sin(a), centre[1] - r * math.cos(a))


def spiral(centre, r0, r1, a0, a1, n=24):
    """Voluta de [a0] a [a1] grados (los de la pantalla, con y hacia abajo), cerrándose de r0 a r1."""
    out = []
    for i in range(n + 1):
        t = i / n
        a = math.radians(a0 + (a1 - a0) * t)
        r = r0 + (r1 - r0) * t ** 0.8
        out.append((centre[0] + r * math.cos(a), centre[1] + r * math.sin(a)))
    return out


def profile(points, keys):
    """Radio a lo largo del trazado, interpolando [(t, radio)] por la longitud recorrida (0-1)."""
    seg = np.hypot(*np.diff(points, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    t = s / s[-1]
    kt, kr = zip(*keys)
    return np.interp(t, kt, kr)


def mirror(points):
    p = np.array(points, np.float64)
    p[:, 0] = BAR_W - p[:, 0]
    return p


# --- Piezas ---------------------------------------------------------------------------------------

# Cómo se pinta lo que va encima de la placa: un halo oscuro que lo separa de lo que tapa, el
# relleno y su filete. Los tallos son de hierro y las hojas de bronce viejo.
RIBBON = dict(halo=1.5, fill=IRON_RAISED, line=BRONZE, line_alpha=0.52, line_w=1.2, bevel=1.8)
LEAF = dict(halo=1.4, fill=BRONZE_DARK * 0.9 + BRONZE * 0.1, line=BRONZE, line_alpha=0.6, line_w=1.0, bevel=2.0)
WIRE = dict(halo=1.1, fill=BRONZE_DARK, fill_alpha=0.65, line=None, bevel=0.8)


def draw(d, style):
    halo = style.get("halo", 0.0)
    if halo > 0.0:
        paint(coverage(d - halo), IRON * 0.7, IRON_ALPHA)
    if "bevel" in style:
        forge(d, style["fill"], style.get("fill_alpha", 1.0), style["bevel"])
    else:
        paint(coverage(d), style["fill"], style.get("fill_alpha", 1.0))
    if style.get("line") is not None:
        metal_line(d, style["line_w"], alpha=style["line_alpha"])


def stroke(points, keys, style, mirrored=False):
    p = mirror(points) if mirrored else np.asarray(points)
    draw(sd_stroke(p, profile(p, keys)), style)


def leaf_shape(base, angle, length, width, bend=0.0, curl=0.0):
    """Hoja de punta curvada a lo Ringerike: el nervio sale de [base] hacia [angle] grados y se
    va doblando ([bend]) y, cerca de la punta, enroscando ([curl]). Devuelve el nervio y su radio."""
    n = max(12, int(length / 0.8))
    heading = math.radians(angle)
    x, y = base
    points = [(x, y)]
    for i in range(1, n + 1):
        t = i / n
        a = heading + math.radians(bend) * t + math.radians(curl) * t ** 3
        x += math.cos(a) * length / n
        y += math.sin(a) * length / n
        points.append((x, y))
    points = np.array(points)
    t = np.linspace(0.0, 1.0, len(points))
    radii = width * 0.5 * np.sin(np.pi * t ** 0.72) ** 0.85
    radii = np.maximum(radii, np.where(t < 0.1, 0.9, 0.0))
    return points, radii


def leaf(base, angle, length, width, bend=0.0, curl=0.0, mirrored=False):
    if mirrored:
        base = (BAR_W - base[0], base[1])
        angle, bend, curl = 180.0 - angle, -bend, -curl
    points, radii = leaf_shape(base, angle, length, width, bend, curl)
    draw(sd_stroke(points, radii), LEAF)
    # Nervio: una raya hundida que no llega a la punta.
    vein = points[: int(len(points) * 0.78)]
    draw(sd_stroke(vein, np.full(len(vein), 0.45)), dict(fill=INK, fill_alpha=0.85))


def rivet(centre, half, mirrored=False):
    """El remache de SagaFrame: un rombo de bronce con otro de tinta dentro."""
    if mirrored:
        centre = (BAR_W - centre[0], centre[1])
    d = (np.abs(BX - centre[0]) + np.abs(BY - centre[1]) - half) * 0.7071
    paint(coverage(d - 1.4), IRON * 0.7, IRON_ALPHA)
    forge(d, BRONZE_DARK * 0.45 + BRONZE * 0.55, bevel=1.5)
    paint(coverage(d + half * 0.45), INK, 0.8)


# --- La placa -------------------------------------------------------------------------------------

def housing_sdf(centre):
    # El engaste sigue redondo por arriba y apoya en el borde inferior por debajo del centro.
    circle = sd_circle(centre, HOUSING)
    footing = sd_box((centre[0] - HOUSING, centre[1]),
                     (centre[0] + HOUSING, SCREEN_Y + 24.0))
    return np.minimum(circle, footing)


def plate():
    # Los biseles inferiores y el borde final quedan fuera de pantalla: el metal continúa
    # hasta el marco, en lugar de cerrar como una placa flotante.
    band = sd_chamfer((-16.0, BAND_TOP), (BAR_W + 16.0, SCREEN_Y + 24.0), 18.0)
    d = smin(band, housing_sdf(LEFT), 12.0)
    d = smin(d, housing_sdf(RIGHT), 12.0)
    d = smin(d, sd_circle(DOME_CENTRE, DOME), 10.0)
    paint(coverage(d - 5.0), IRON_DEEP, 0.4)
    forge(d, IRON, 0.98, bevel=7.0, grain=0.003)
    metal_line(d, 3.5, alpha=0.9)
    paint(band_of(d, 2.0, 4.0), INK, 0.8)
    metal_line(d, 1.0, INSET + 1.0, 0.3)
    for centre in (LEFT, RIGHT):
        r = sd_circle(centre, 0.0)
        # Banda fina de bronce viejo, dejando más espacio al cristal.
        annulus = np.maximum(RUNE_IN - r, r - RUNE_OUT)
        forge(annulus, BRONZE_DARK * 0.72, 0.98, bevel=3.0, grain=0.003)
        # Hueco de la orbe, más oscuro según se acerca a ella.
        paint(coverage(r - RUNE_IN), IRON_DEEP, np.clip(1.0 - (r - ORB_R) / (RUNE_IN - ORB_R), 0.4, 1.0))
        metal_line(r - RUNE_IN - 1.0, 1.5, alpha=0.95)
        metal_line(r - RUNE_OUT, 1.5, alpha=0.9)
        # Remaches de acero y escalones en la cara de cada cápsula.
        for angle in (-35.0, 35.0, 145.0, 215.0):
            rivet(on_ring(centre, 93.5, angle), 1.8)
    # El engaste de la cordura: media banda, solo por encima de la barra.
    above = (BY < DOME_CENTRE[1] - 0.5).astype(np.float32)
    r = sd_circle(DOME_CENTRE, 0.0)
    annulus = np.maximum(DOME_RUNE_IN - r, r - DOME_RUNE_OUT)
    forge(np.maximum(annulus, BY - DOME_CENTRE[1]), BRONZE_DARK * 0.72, 0.98, bevel=3.0)
    paint(coverage(r - DOME_RUNE_IN) * above, IRON_DEEP,
          np.clip(1.0 - (r - SANITY_R) / (DOME_RUNE_IN - SANITY_R), 0.4, 1.0))
    metal_line(np.maximum(r - DOME_RUNE_IN - 1.0, BY - DOME_CENTRE[1]), 1.5, alpha=0.9)
    metal_line(np.maximum(r - DOME_RUNE_OUT, BY - DOME_CENTRE[1]), 1.5, alpha=0.8)
    # Un filo oscuro alrededor de la barra, como si estuviera hundida.
    bar = sd_chamfer((0.0, 0.0), (BAR_W, BAR_H), 12.0)
    paint(np.clip(coverage(bar - 5.0) - coverage(bar), 0, 1), IRON_DEEP, 0.8)
    lower_lip = sd_box((8.0, BAR_H + 1.0), (BAR_W - 8.0, BAR_H + 3.0))
    forge(lower_lip, BRONZE_DARK, 0.85, bevel=1.0)
    # El nombre del objeto va sobre una franja hundida del mismo zócalo.
    footer = sd_chamfer((12.0, BAR_H + 4.0), (BAR_W - 12.0, SCREEN_Y + 16.0), 5.0)
    paint(coverage(footer), IRON_DEEP, 0.6)


def fittings():
    """Abrazaderas cortas de hierro en los extremos y un grabado trenzado en el labio superior.
    El ornamento está en el metal, en lugar de crecer por encima de los iconos."""
    for mirrored in (False, True):
        x = BAR_W + 9.0 if mirrored else -9.0
        collar = sd_chamfer((x - 6.0, 12.0), (x + 6.0, BAR_H - 10.0), 5.0)
        draw(collar, dict(halo=1.5, fill=IRON_RAISED, bevel=3.0, line=BRONZE, line_w=1.0, line_alpha=0.5))
        for y in (21.0, BAR_H - 19.0):
            rivet((x, y), 3.0)
        # Dos bandas de nudo; dejan espacio al engaste central.
        xs = np.arange(20.0, CENTRE_X - DOME - 12.0, 1.0)
        for phase in (0.0, math.pi):
            ys = -4.5 + 1.8 * np.sin(xs / 34.0 * math.tau + phase)
            points = np.stack([xs, ys], axis=1)
            if mirrored:
                points = mirror(points)
            draw(sd_stroke(points, np.full(len(points), 0.55), reach=2.0),
                 dict(fill=BRONZE_DARK, fill_alpha=0.7))
    rivet((CENTRE_X, DOME_CENTRE[1] - DOME + 3.0), 3.0)


# --- Runas ----------------------------------------------------------------------------------------

# Fuþark joven de ramas largas, en una caja de alto 1 (y hacia abajo, 0 es el lado de fuera del
# aro). "|" es la separación entre palabras (un rombo, como los remaches).
RUNES = {
    "f": [[(0, 0), (0, 1)], [(0, 0.32), (0.5, 0.02)], [(0, 0.62), (0.5, 0.32)]],
    "u": [[(0, 1), (0, 0), (0.5, 0.34), (0.5, 1)]],
    "th": [[(0, 0), (0, 1)], [(0, 0.28), (0.42, 0.5), (0, 0.72)]],
    "r": [[(0, 1), (0, 0), (0.44, 0.24), (0, 0.5), (0.48, 1)]],
    "k": [[(0, 0), (0, 1)], [(0, 0.46), (0.46, 0.1)]],
    "h": [[(0.3, 0), (0.3, 1)], [(0, 0.3), (0.6, 0.7)], [(0.6, 0.3), (0, 0.7)]],
    "n": [[(0.3, 0), (0.3, 1)], [(0.04, 0.34), (0.56, 0.66)]],
    "i": [[(0, 0), (0, 1)]],
    "a": [[(0.3, 0), (0.3, 1)], [(0.56, 0.34), (0.04, 0.66)]],
    "s": [[(0.44, 0), (0.04, 0.36), (0.44, 0.64), (0.04, 1)]],
    "t": [[(0.3, 0), (0.3, 1)], [(0, 0.3), (0.3, 0), (0.6, 0.3)]],
    "b": [[(0, 0), (0, 1)], [(0, 0), (0.42, 0.25), (0, 0.5), (0.42, 0.75), (0, 1)]],
    "m": [[(0.3, 0), (0.3, 1)], [(0, 0), (0.3, 0.3), (0.6, 0)]],
    "l": [[(0, 0), (0, 1)], [(0, 0), (0.44, 0.34)]],
}
RUNE_TEXT = {
    "left": ["l", "i", "f", "|", "a", "u", "k", "|", "b", "l", "u", "th", "|"],
    "right": ["th", "r", "i", "k", "|", "a", "u", "k", "|", "a", "n", "t", "i", "|"],
}
RUNE_H = 8.2
RUNE_STROKE = 0.8
# Las de la cordura, en su media banda: «hugr auk minni» (pensamiento y memoria, Huginn y Muninn).
SANITY_TEXT = ["h", "u", "k", "r", "|", "a", "u", "k", "|", "m", "i", "n", "i"]


def glyph_width(token):
    if token == "|":
        return 0.36
    return max(x for line in RUNES[token] for x, _ in line)


def runes(centre, tokens, r_in, r_out, height, arc=None):
    """Runas en la banda entre [r_in] y [r_out], con el pie hacia dentro. Sin [arc] dan la vuelta
    entera repitiendo la frase; con [arc] = (desde, hasta) en grados desde lo alto, la frase va una
    vez repartida por ese arco. Devuelve cuánto cubren (para la máscara del aliento)."""
    mid = (r_in + r_out) * 0.5
    top = mid + height * 0.5
    space = 0.5
    phrase = sum(glyph_width(t) + space for t in tokens) * height
    if arc is None:
        start = 0.0
        length = 2.0 * math.pi * mid
        repeats = max(1, round(length / phrase))
        # Se reparte el hueco que sobra entre las letras para que la frase cierre el círculo.
        space += (length / repeats - phrase) / (len(tokens) * height)
    else:
        start = math.radians(arc[0])
        length = math.radians(arc[1] - arc[0]) * mid
        repeats = 1
        space += (length - phrase) / (max(len(tokens) - 1, 1) * height)
    d = np.full((H, W), np.inf, np.float32)
    along = 0.0
    for _ in range(repeats):
        for token in tokens:
            width = glyph_width(token) * height
            # Ángulo del centro de la letra; se escribe en el sentido de las agujas del reloj.
            a = start + (along + width * 0.5) / mid
            along += width + space * height
            out = np.array([math.sin(a), -math.cos(a)])
            tangent = np.array([math.cos(a), math.sin(a)])
            if token == "|":
                at = np.array(centre) + out * mid
                d = np.minimum(d, (np.abs(BX - at[0]) + np.abs(BY - at[1]) - 2.2) * 0.7071)
                continue
            for line in RUNES[token]:
                pts = [np.array(centre) + out * (top - gy * height) + tangent * (gx * height - width * 0.5)
                       for gx, gy in line]
                pts = resample(pts, 0.75)
                d = np.minimum(d, sd_stroke(pts, np.full(len(pts), RUNE_STROKE), reach=3.0))
    cov = coverage(d)
    # Las incisiones cálidas quedan en segundo plano. El aliento conserva su máscara original.
    paint(coverage(d - 0.5), INK, 0.7)
    paint(cov, BRONZE, 0.52)
    return cov


# --- Medidores ------------------------------------------------------------------------------------

# Canal tallado por el que corre cada medidor (lo llena NeedGauge) y el medallón de su icono.
CHANNEL = dict(halo=1.5, fill=IRON_DEEP, line=BRONZE, line_alpha=0.75, line_w=1.0)
MEDALLION = dict(halo=1.5, fill=IRON, line=BRONZE, line_alpha=0.8, line_w=1.0)


def gauge(centre, medallion, end, icon):
    """El medallón del icono y, saliendo de él en el sentido de las agujas del reloj, el canal del
    medidor hasta [end]: una sola pieza con un solo filete."""
    points = resample([on_ring(centre, GAUGE_R, a) for a in np.linspace(medallion, end, 48)], 1.0)
    channel = np.minimum(sd_stroke(points, np.full(len(points), GAUGE_HALF)), 1e3)
    at = on_ring(centre, MEDALLION_AT, medallion)
    disc = sd_circle(at, MEDALLION_R)
    draw(smin(channel, disc, 6.0), CHANNEL)
    forge(disc, IRON, bevel=3.0)
    metal_line(disc, 1.5, alpha=0.8)
    paint(band_of(disc, 1.0, 3.5), BRONZE, 0.15)
    icon(at, ICON_SCALE)


def icon_grain(c, k):
    # Espiga: el tallo y tres pares de granos, con uno en la punta.
    x, y = c
    stem = resample([(x, y + 9 * k), (x, y - 6 * k)], 0.75)
    paint(coverage(sd_stroke(stem, np.full(len(stem), 0.75 * k))), BRONZE, 0.95)
    for i, gy in enumerate((3.5, -0.5, -4.5)):
        for side in (-1, 1):
            pts, radii = leaf_shape((x, y + gy * k), -90 + side * 38, (6.0 - i * 0.4) * k, 3.6 * k, 0, 0)
            paint(coverage(sd_stroke(pts, radii)), BRONZE, 0.95)
    pts, radii = leaf_shape((x, y - 5.5 * k), -90, 5.0 * k, 3.4 * k, 0, 0)
    paint(coverage(sd_stroke(pts, radii)), BRONZE, 0.95)


def icon_drop(c, k):
    x, y = c
    d = sd_stroke(np.array([(x, y - 9.0 * k), (x, y + 2.5 * k)]), np.array([0.2, 5.6]) * k)
    d = np.minimum(d, sd_circle((x, y + 2.5 * k), 5.6 * k))
    paint(coverage(d), BRONZE, 0.95)
    shine = resample([on_ring((x, y + 2.5 * k), 3.2 * k, a) for a in (200, 230, 260)], 0.5)
    paint(coverage(sd_stroke(shine, np.full(len(shine), 0.6 * k))), INK, 0.8)


def icon_thermometer(c, k):
    x, y = c
    tube = sd_stroke(np.array([(x, y - 8.5 * k), (x, y + 3.0 * k)]), np.array([2.6, 2.6]) * k)
    bulb = sd_circle((x, y + 4.5 * k), 4.4 * k)
    body = np.minimum(tube, bulb)
    paint(band_of(body, 1.1 * k), BRONZE, 0.95)
    paint(coverage(sd_circle((x, y + 4.5 * k), 2.4 * k)), BRONZE, 0.95)
    paint(coverage(sd_stroke(np.array([(x, y - 3.0 * k), (x, y + 3.0 * k)]), np.array([0.9, 0.9]) * k)), BRONZE, 0.95)
    for ty in (-6.0, -3.0, 0.0):
        tick = np.array([(x + 4.2 * k, y + ty * k), (x + 6.4 * k, y + ty * k)])
        paint(coverage(sd_stroke(tick, np.array([0.5, 0.5]) * k)), BRONZE, 0.8)


def icon_moon(c, k):
    x, y = c
    d = np.maximum(sd_circle((x - 1.0 * k, y + 0.5 * k), 7.6 * k), -sd_circle((x + 2.6 * k, y - 2.2 * k), 6.4 * k))
    paint(coverage(d), BRONZE, 0.95)
    star = (np.abs(BX - (x + 5.2 * k)) + np.abs(BY - (y + 4.6 * k)) - 2.0 * k) * 0.7071
    paint(coverage(star), BRONZE, 0.95)


# Por medidor: engaste, grados (desde lo alto, en el sentido de las agujas del reloj) del medallón,
# donde arranca la barra, y de donde acaba. Hotbar.GAUGES lleva lo mismo.
GAUGES = (
    (LEFT, -126.0, -84.0, icon_drop),
    (LEFT, -70.0, -16.0, icon_grain),
    (RIGHT, 26.0, 72.0, icon_thermometer),
    (RIGHT, 84.0, 138.0, icon_moon),
)


def breath_mask(cov):
    """Las runas del engaste del aguante solas, en blanco y centradas en él: BreathRing las
    enciende como medidor del oxígeno."""
    x0 = int(round((RIGHT[0] - MASK_HALF - X0) * ART))
    y0 = int(round((RIGHT[1] - MASK_HALF - Y0) * ART))
    side = int(round(MASK_HALF * 2 * ART))
    # Lo de debajo del borde de la pantalla no está en el lienzo: queda vacío.
    alpha = cov[y0:y0 + side, x0:x0 + side]
    out = np.zeros((side, side, 4), np.float32)
    out[..., :3] = 1.0
    out[:alpha.shape[0], :alpha.shape[1], 3] = alpha
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA").save(MASK_OUT)
    print(f"{MASK_OUT}: {side}x{side}, banda {RUNE_IN / (2 * MASK_HALF):.4f}-{RUNE_OUT / (2 * MASK_HALF):.4f}")


def main():
    plate()
    runes(LEFT, RUNE_TEXT["left"], RUNE_IN, RUNE_OUT, RUNE_H)
    breath = runes(RIGHT, RUNE_TEXT["right"], RUNE_IN, RUNE_OUT, RUNE_H)
    runes(DOME_CENTRE, SANITY_TEXT, DOME_RUNE_IN, DOME_RUNE_OUT, 5.5, (-80.0, 80.0))
    for centre, medallion, end, icon in GAUGES:
        gauge(centre, medallion, end, icon)
    fittings()

    alpha = CANVAS[..., 3]
    colour = np.where(alpha[..., None] > 1e-5, CANVAS[..., :3] / np.maximum(alpha, 1e-5)[..., None], 0.0)
    out = np.concatenate([colour, alpha[..., None]], axis=2)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT)
    print(f"{OUT}: {W}x{H}")
    print(f"VitalsPlate.BAR_ORIGIN = Vector2({-X0 * ART:g}, {-Y0 * ART:g}), REACH = {-X0:g}")
    breath_mask(breath)


if __name__ == "__main__":
    main()
