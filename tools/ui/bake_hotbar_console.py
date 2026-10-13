#!/usr/bin/env python3
"""Hornea la consola de la barra rápida: textures/ui/hotbar_console.png.

La placa de hierro de Saga (la de las ventanas: hierro casi negro, filete de bronce por fuera y otro
más tenue por dentro) en la que encaja la barra rápida, a lo Diablo: sostiene la barra desde el
borde de abajo de la pantalla y se levanta a cada lado en el engaste de una orbe (vida y aguante).
Cada engaste lleva una banda de runas, como las de las piedras rúnicas: «líf auk blóð» (vida y
sangre) en la de la vida y «þrek auk andi» (aguante y aliento) en la del aguante. Por fuera de cada
uno van dos medidores de las necesidades (hambre y sed en el de la vida, temperatura y descanso en
el del aguante; los llena NeedGauge): un medallón con su icono del que sale un canal en el sentido
de las agujas del reloj. De debajo salen las raíces del fresno, que se atan en un nudo de tres
lóbulos y se agarran al borde de la pantalla, y encima hay una copa de hojas. Una sierpe a lo Urnes
muerde cada engaste donde se junta con la barra y recorre su borde de arriba a jorobas, hundiéndose
en la placa (su cuerpo es parte de ella), hasta que la cola sale hecha zarcillo de hojas. En el
centro se levanta el engaste de la media orbe de la cordura, con media banda de runas («hugr auk
minni»), una voluta doble a cada lado con un cuervo posado (Huginn y Muninn, el pensamiento y la
memoria) y tres hojas. Por debajo de la barra corre una trenza de hilo de bronce. Aparte sale
hotbar_breath_runes.png: las runas del aguante solas, que BreathRing enciende como medidor del
oxígeno.

Todo se dibuja como en GameTheme y SagaFrame: rellenos lisos y filetes de un píxel, sin luces ni
relieve, para que case con el resto de la interfaz. Las formas son campos de distancia con signo,
así que los bordes salen suavizados sin sobremuestrear. Las medidas son las de la barra a 1440 px
de alto (las de Hotbar y GameTheme: diez huecos de 92 px, orbes de radio 75...) y la imagen va a
ART píxeles por cada uno, para que a 4K siga nítida. Si cambian, hay que cambiarlas aquí, en Hotbar
(PANEL_SIZE, ORB_*, SANITY_RADIUS, GAUGE_*, MEDALLION_*, GAUGES), en VitalsPlate (BAR_ORIGIN, REACH) y en
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
BAR_W, BAR_H = 1048.0, 112.0
SCREEN_Y = BAR_H + 22.0
CENTRE_X = BAR_W * 0.5
# Orbes (Hotbar.ORB_*) y sus engastes.
ORB_R, ORB_GAP, ORB_DROP = 75.0, 38.0, 0.0
HOUSING = 101.0
LEFT = (-(ORB_GAP + ORB_R), BAR_H - ORB_R + ORB_DROP)
RIGHT = (BAR_W - LEFT[0], LEFT[1])
# Banda de runas entre dos filetes, por fuera del aro de la orbe.
RUNE_IN, RUNE_OUT = 79.0, 94.5
# Media orbe de la cordura (Hotbar.SANITY_RADIUS), con el centro en el borde de arriba de la
# barra, y su engaste con media banda de runas.
SANITY_R = 48.0
DOME_CENTRE = (BAR_W * 0.5, 0.0)
DOME_RUNE_IN, DOME_RUNE_OUT = 51.5, 64.0
DOME = 70.0
# Medidores de las necesidades (Hotbar.GAUGE_*): el canal alrededor de cada engaste, de radio
# GAUGE_R y medio ancho GAUGE_HALF, y los medallones de sus iconos, a MEDALLION_AT del centro.
GAUGE_R, GAUGE_HALF = 106.5, 5.5
MEDALLION_AT, MEDALLION_R = 118.0, 21.0
# Los iconos se dibujan en una caja de unos 18 px y se agrandan esto.
ICON_SCALE = 1.4
# La máscara de las runas del aguante, para el oxígeno (BreathRing): medio lado.
MASK_HALF = 102.0
# La placa asoma un poco por encima de la barra; el filete interior va a INSET del borde.
BAND_TOP = -14.0
INSET = 7.0
# Lienzo, en píxeles base.
X0, X1 = -300.0, BAR_W + 300.0
Y0, Y1 = -112.0, SCREEN_Y
W = int(round((X1 - X0) * ART))
H = int(round((Y1 - Y0) * ART))


def rgb(hex_code):
    return np.array([int(hex_code[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


# La paleta de GameTheme.
IRON = np.array([0.043, 0.047, 0.054], np.float32)
IRON_ALPHA = 0.93
IRON_DEEP = np.array([0.02, 0.022, 0.027], np.float32)
# Lo que va encima de la placa (tallos, raíces): el mismo hierro, apenas más claro.
IRON_RAISED = np.array([0.072, 0.075, 0.083], np.float32)
BRONZE = rgb("c9a46a")
BRONZE_DARK = rgb("6e5a38")
INK = rgb("16130f")

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
BX = (xx + 0.5) / ART + X0
BY = (yy + 0.5) / ART + Y0
del xx, yy

# Lienzo con alfa premultiplicado.
CANVAS = np.zeros((H, W, 4), np.float32)


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
RIBBON = dict(halo=1.5, fill=IRON_RAISED, line=BRONZE, line_alpha=0.8, line_w=1.0)
LEAF = dict(halo=1.4, fill=BRONZE_DARK * 0.82 + BRONZE * 0.18, line=BRONZE, line_alpha=0.95, line_w=1.0)
WIRE = dict(halo=1.1, fill=BRONZE, fill_alpha=0.5, line=None)


def draw(d, style, mask=1.0):
    halo = style.get("halo", 0.0)
    if halo > 0.0:
        paint(coverage(d - halo) * mask, IRON * 0.7, IRON_ALPHA)
    paint(coverage(d) * mask, style["fill"], style.get("fill_alpha", 1.0))
    if style.get("line") is not None:
        paint(band_of(d, style["line_w"]) * mask, style["line"], style["line_alpha"])


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
    paint(coverage(d), BRONZE)
    paint(coverage(d + half * 0.3), INK)


# --- La placa -------------------------------------------------------------------------------------

def housing_sdf(centre):
    # El engaste: el círculo y, debajo de su centro, recto hasta abajo.
    circle = sd_circle(centre, HOUSING)
    below = sd_box((centre[0] - HOUSING, centre[1]), (centre[0] + HOUSING, SCREEN_Y + 40))
    return np.minimum(circle, below)


def plate_sdf():
    band = sd_box((LEFT[0], BAND_TOP), (RIGHT[0], SCREEN_Y + 40))
    d = smin(band, housing_sdf(LEFT), 18.0)
    d = smin(d, housing_sdf(RIGHT), 18.0)
    return smin(d, sd_circle(DOME_CENTRE, DOME), 14.0)


def plate():
    d = plate_sdf()
    # Las sierpes se echan sobre el borde de arriba con la panza hundida en la placa: su cuerpo es
    # parte de ella, con el mismo filete por fuera.
    body = np.minimum.reduce([sd_stroke(*serpent_body(mirrored)) for mirrored in (False, True)])
    whole = smin(d, np.minimum(body, 1e3), 3.0)
    paint(coverage(whole), IRON, IRON_ALPHA)
    # Filetes de SagaFrame: el de fuera, que rodea también a las sierpes, y el de dentro, más tenue,
    # que sigue el borde de la placa sola.
    paint(band_of(whole, 1.0), BRONZE, 0.55)
    paint(band_of(d, 1.0, INSET), BRONZE, 0.16)
    for centre in (LEFT, RIGHT):
        r = sd_circle(centre, 0.0)
        # Hueco de la orbe, más oscuro según se acerca a ella.
        paint(coverage(r - RUNE_IN), IRON_DEEP, np.clip(1.0 - (r - ORB_R) / (RUNE_IN - ORB_R), 0.4, 1.0))
        paint(band_of(r - RUNE_IN - 1.0, 1.0), BRONZE, 0.5)
        paint(band_of(r - RUNE_OUT, 1.0), BRONZE, 0.5)
    # El engaste de la cordura: media banda, solo por encima de la barra.
    above = (BY < -0.5).astype(np.float32)
    r = sd_circle(DOME_CENTRE, 0.0)
    paint(coverage(r - DOME_RUNE_IN) * above, IRON_DEEP,
          np.clip(1.0 - (r - SANITY_R) / (DOME_RUNE_IN - SANITY_R), 0.4, 1.0))
    paint(band_of(r - DOME_RUNE_IN - 1.0, 1.0) * above, BRONZE, 0.5)
    paint(band_of(r - DOME_RUNE_OUT, 1.0) * above, BRONZE, 0.5)
    # Un filo oscuro alrededor de la barra, como si estuviera hundida.
    bar = sd_box((0.0, 0.0), (BAR_W, BAR_H))
    paint(np.clip(coverage(bar - 3.0) - coverage(bar), 0, 1), IRON_DEEP, 0.6)


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
RUNE_H = 9.5
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
    paint(cov, BRONZE, 0.62)
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
    paint(coverage(disc), IRON)
    paint(band_of(disc, 1.0), BRONZE, 0.75)
    paint(band_of(disc, 1.0, 3.5), BRONZE, 0.2)
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


# --- Nudos ----------------------------------------------------------------------------------------

def crossings(points, gap):
    """Dónde se cruza consigo misma una polilínea: pares de índices de segmentos que se cortan y
    que están a más de [gap] píxeles base de recorrido el uno del otro."""
    a, b = points[:-1], points[1:]
    s = np.concatenate([[0.0], np.cumsum(np.hypot(*(b - a).T))])
    d = b - a
    ox = a[None, :, 0] - a[:, None, 0]
    oy = a[None, :, 1] - a[:, None, 1]
    den = d[:, None, 0] * d[None, :, 1] - d[:, None, 1] * d[None, :, 0]
    with np.errstate(divide="ignore", invalid="ignore"):
        u = (ox * d[None, :, 1] - oy * d[None, :, 0]) / den
        v = (ox * d[:, None, 1] - oy * d[:, None, 0]) / den
    hit = (u >= 0) & (u < 1) & (v >= 0) & (v < 1) & (np.abs(s[:-1, None] - s[None, :-1]) > gap)
    return [(i, j) for i, j in zip(*np.nonzero(np.triu(hit)))]


def interlace(points, heights, keys, style):
    """Cinta que se cruza consigo misma por encima y por debajo: la entera y, en cada cruce, otra
    vez el tramo que va más alto, solo dentro de un disco alrededor del cruce (así sus puntas no se
    ven)."""
    points = np.asarray(points)
    heights = np.asarray(heights)
    radii = profile(points, keys)
    draw(sd_stroke(points, radii), style)
    reach = max(radii) + style.get("halo", 0.0)
    s = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(points, axis=0).T))])
    for i, j in crossings(points, 4.0 * reach):
        over = i if heights[i] > heights[j] else j
        near = np.abs(s - s[over]) < 4.0 * reach
        disc = sd_circle(points[over], 2.6 * reach)
        draw(sd_stroke(points[near], radii[near]), style, coverage(disc))


def trefoil(centre, size, mirrored):
    """Nudo de tres lóbulos (el trébol de las piedras rúnicas), de cinta de hierro como las raíces."""
    t = np.linspace(0.0, math.tau, 240, endpoint=False)
    x = np.sin(t) + 2.0 * np.sin(2.0 * t)
    y = np.cos(t) - 2.0 * np.cos(2.0 * t)
    z = -np.sin(3.0 * t)
    cx = BAR_W - centre[0] if mirrored else centre[0]
    pts = np.stack([cx + x * size / 3.0, centre[1] - y * size / 3.0], axis=1)
    interlace(np.vstack([pts, pts[:1]]), np.append(z, z[0]), [(0, 2.9), (1, 2.9)], RIBBON)


# --- El fresno de cada engaste --------------------------------------------------------------------

# El nudo en que se atan las raíces de cada lado, y su tamaño.
ROOT_KNOT, ROOT_KNOT_SIZE = (-262.0, 90.0), 20.0


def ash_roots(mirrored):
    # Raíces que salen de debajo del engaste (se pintan antes que la placa): la gruesa se ata en un
    # nudo de tres lóbulos y de él salen las que se agarran al borde de la pantalla, cada una
    # afinándose hasta la punta.
    for root, rk in (
        ([(-190, 92), (-212, 97), (-232, 96), (-248, 92)], [(0, 6.6), (0.5, 5.2), (1, 4.2)]),
        ([(-196, 108), (-216, 114), (-229, 124), (-235, 133), (-239, 141)], [(0, 5.0), (0.5, 3.0), (1, 0.5)]),
        ([(-200, 118), (-208, 126), (-210, 141)], [(0, 3.6), (1, 0.5)]),
        ([(-262, 102), (-264, 118), (-270, 130), (-272, 141)], [(0, 4.0), (0.5, 3.0), (1, 0.5)]),
        ([(-272, 94), (-286, 104), (-294, 116), (-299, 122)], [(0, 3.6), (1, 0.6)]),
        ([(-254, 108), (-247, 124), (-250, 141)], [(0, 2.4), (1, 0.4)]),
        ([(-268, 116), (-282, 128), (-288, 141)], [(0, 1.8), (1, 0.4)]),
    ):
        stroke(spline(root), rk, RIBBON, mirrored)
    trefoil(ROOT_KNOT, ROOT_KNOT_SIZE, mirrored)


def crown(mirrored):
    # La copa de hojas del fresno sobre cada engaste, asentada en un remache.
    top = on_ring(LEFT, HOUSING + 3.0, -2)
    leaf((top[0] - 3, top[1] - 3), -128, 26, 10.5, -14, -40, mirrored)
    leaf((top[0] + 2, top[1] - 4), -92, 33, 12.0, 10, 28, mirrored)
    leaf((top[0] + 9, top[1] - 1), -55, 25, 10.0, 18, 36, mirrored)
    rivet((top[0] + 2, top[1] - 1), 4.5, mirrored)


def crest():
    # El engaste de la cordura asienta en una voluta doble y lo coronan un remache y tres hojas.
    x = CENTRE_X
    for mirrored in (False, True):
        ctrl = [(x - DOME + 2, -15), (x - DOME - 16, -18), (x - DOME - 32, -24)]
        ctrl += spiral((x - DOME - 26, -34), 11.0, 3.0, 150, 420, 16)[1:]
        stroke(spline(ctrl), [(0, 3.2), (0.5, 2.6), (1.0, 1.0)], RIBBON, mirrored)
        leaf((x - DOME + 6, -19), -128, 20, 8.0, -12, -30, mirrored)
        leaf((x - 6, -DOME + 1), -124, 18, 7.5, -10, -28, mirrored)
    leaf((x, -DOME - 2), -90, 26, 11.0, 0, 0)
    rivet((x, -DOME), 5.0)


def braid():
    # Dos hilos de bronce embutidos que se cruzan por debajo de la barra, de engaste a engaste.
    y = (BAR_H + SCREEN_Y) * 0.5
    x0, x1 = -10.0, BAR_W + 10.0
    xs = np.arange(x0, x1, 1.0)
    period = 44.0
    strands = []
    for phase in (0.0, math.pi):
        ys = y + 4.2 * np.sin((xs - x0) / period * 2 * math.pi + phase)
        strands.append(np.stack([xs, ys], axis=1))
    # En cada cruce pasa por encima uno distinto.
    half = period * 0.5
    for over in (False, True):
        for k, strand in enumerate(strands):
            seg = ((strand[:, 0] - x0 + half * 0.5) // half).astype(int)
            mask = ((seg + k) % 2 == 0) == over
            for run in np.split(np.arange(len(strand)), np.where(np.diff(mask.astype(int)) != 0)[0] + 1):
                if mask[run[0]] and len(run) > 1:
                    run = np.arange(max(run[0] - 1, 0), min(run[-1] + 2, len(strand)))
                    draw(sd_stroke(strand[run], np.full(len(run), 1.0), reach=4.0), WIRE)


# --- Huginn y Muninn ------------------------------------------------------------------------------

# Los cuervos son de hierro, como los tallos, con el filete de bronce y las plumas grabadas.
RAVEN = dict(halo=1.6, fill=IRON_RAISED, line=BRONZE, line_alpha=0.9, line_w=1.0)
RAVEN_SCALE = 2.0 / 3.0


def local(points, origin, facing):
    """De coordenadas propias de la pieza (x hacia donde mira, y hacia abajo) a las de la placa."""
    p = np.asarray(points, np.float64)
    return np.stack([origin[0] + p[:, 0] * facing, origin[1] + p[:, 1]], axis=1)


def engrave(points, width=0.55, alpha=0.7):
    """Una raya de bronce grabada sobre lo que ya hay."""
    p = resample(points, 0.6)
    paint(coverage(sd_stroke(p, np.full(len(p), width), reach=3.0)), BRONZE, alpha)


def raven(feet, facing, k=RAVEN_SCALE):
    """Cuervo posado de perfil con el ala alzada, a lo Mammen: una espiral en el arranque del ala y
    las plumas grabadas. [feet] es donde agarra, [facing] (1 o -1) hacia dónde mira y [k] su tamaño
    (dibujado para 1, con unos 68 px base de la cola al pico)."""
    def at(points):
        return local(np.asarray(points, np.float64) * k, feet, facing)

    def shape(ctrl, keys):
        p = at(spline(ctrl, 1.25 / k))
        return sd_stroke(p, profile(p, keys) * k)

    def line(ctrl, width=0.55, alpha=0.7):
        engrave(at(spline(ctrl, 1.0 / k)), max(width * k, 0.45), alpha)

    # Patas y garras, de bronce.
    for leg in ([(-3, -8), (-2, -3), (-1, 0)], [(2, -8), (2.5, -3), (3, 0)]):
        draw(shape(leg, [(0, 1.3), (1, 0.9)]), dict(fill=BRONZE, fill_alpha=0.9))
    for toe in ([(-1, 0), (3, 1.2), (6, 3)], [(-1, 0), (-4, 1), (-6, 3)], [(3, 0), (7, 1), (9, 3.5)]):
        draw(shape(toe, [(0, 1.0), (1, 0.5)]), dict(fill=BRONZE, fill_alpha=0.9))
    # El ala de detrás asoma por encima de la otra.
    far = shape([(5, -22), (-2, -36), (-11, -47), (-22, -52)], [(0, 4.0), (0.4, 6.0), (1, 1.4)])
    # Cola en cuña, cuerpo, cuello y cabeza, el buche erizado y el pico, grueso y algo ganchudo.
    tail = shape([(-8, -10), (-21, -7), (-34, -2)], [(0, 3.8), (0.6, 5.0), (1, 4.0)])
    body = shape([(-12, -9), (-3, -13), (5, -17), (10, -23), (12, -29), (13, -34)],
                 [(0, 5.5), (0.3, 9.4), (0.55, 8.4), (0.78, 6.2), (1, 7.2)])
    hackles = np.minimum(
        shape([(13, -30), (17, -27), (19.5, -25.5)], [(0, 2.6), (1, 0.4)]),
        shape([(12, -27), (15.5, -23.5), (17, -21.5)], [(0, 2.4), (1, 0.4)]))
    beak = shape([(17, -37.5), (24, -37.2), (30, -35), (33.5, -31.5)], [(0, 4.2), (0.45, 2.9), (1, 0.5)])
    near = shape([(4, -20), (-5, -30), (-15, -38), (-24, -42)], [(0, 6.6), (0.4, 7.8), (1, 4.0)])
    draw(far, RAVEN)
    draw(np.minimum(np.minimum(np.minimum(tail, body), beak), hackles), RAVEN)
    # Las primarias, abiertas como dedos al final del ala.
    fingers = [shape([(-17, -40 + f * 3.2), (-27, -44.5 + f * 5.0), (-37, -46 + f * 7.0)],
                     [(0, 2.6), (0.6, 2.3), (1, 0.6)]) for f in range(4)]
    draw(np.minimum(near, np.minimum.reduce(fingers)), RAVEN)
    # Plumas grabadas: las coberteras del ala y las de la cola.
    line([(-4, -31), (-12, -37), (-19, -40)])
    line([(-1, -26.5), (-9, -33), (-17, -36.5)])
    line([(-16, -7.5), (-30, -2.5)], alpha=0.55)
    # La espiral del arranque del ala.
    turns = zip(np.linspace(math.pi * 0.9, math.pi * 3.6, 40), np.linspace(5.0, 0.8, 40))
    line([(3.5 + r * math.cos(a), -21.5 + r * math.sin(a)) for a, r in turns], 0.65, 0.85)
    # Ojo y comisura del pico.
    eye = at([(14.5, -36.5)])[0]
    paint(coverage(sd_circle(eye, max(2.0 * k, 1.5))), BRONZE)
    paint(coverage(sd_circle(eye, max(1.0 * k, 0.75))), INK)
    line([(18, -35.5), (24, -35.2)], 0.45, 0.6)


def ravens():
    # Posados en lo alto de las volutas de la cordura, mirándola.
    for facing in (1, -1):
        raven((CENTRE_X - facing * (DOME + 26), -45.5), facing)


# --- Las sierpes ----------------------------------------------------------------------------------

# La sierpe es parte de la placa: el mismo hierro y su filete; la cabeza lleva halo para despegarse
# de lo que pisa.
SERPENT = dict(halo=1.6, fill=IRON, fill_alpha=IRON_ALPHA, line=BRONZE, line_alpha=0.7, line_w=1.0)


def pose(points, origin, angle, mirrored):
    """Coordenadas propias de la pieza giradas [angle] grados y llevadas a [origin] (las de la
    izquierda; con [mirrored], al otro lado)."""
    a = math.radians(angle)
    p = np.asarray(points, np.float64)
    out = np.stack([origin[0] + p[:, 0] * math.cos(a) - p[:, 1] * math.sin(a),
                    origin[1] + p[:, 0] * math.sin(a) + p[:, 1] * math.cos(a)], axis=1)
    return mirror(out) if mirrored else out


# La sierpe muerde el aro a SERPENT_BITE grados de lo alto, con el hocico hacia SERPENT_SNOUT
# grados y la coronilla hacia fuera (SERPENT_FLIP), y su cabeza se agranda SERPENT_K.
SERPENT_BITE, SERPENT_SNOUT, SERPENT_FLIP, SERPENT_K = 52.0, 172.0, -1.0, 1.6
# Dónde quedan las fauces abiertas en la cabeza, en sus coordenadas.
GAPE = np.array([22.0, 3.9])


def serpent_neck(bite, angle, k, flip):
    """La nuca de una cabeza que tiene las fauces sobre [bite] (en las coordenadas de la izquierda)."""
    a = math.radians(angle)
    rot = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
    return np.array(bite) - rot @ (GAPE * (1.0, flip) * k)


def serpent_head(bite, angle, mirrored, k=SERPENT_K, flip=SERPENT_FLIP):
    """Cabeza de sierpe a lo Urnes con las fauces abiertas sobre [bite]: el hocico hacia [angle]
    grados, el labio de arriba acabado en rizo, el ojo almendrado hacia atrás y una melena que se
    enrosca sobre la nuca. [k] la agranda y [flip] = -1 le da la vuelta (la coronilla al otro lado)."""
    neck = serpent_neck(bite, angle, k, flip)

    def at(points):
        return pose(np.asarray(points, np.float64) * (k, k * flip), neck, angle, mirrored)

    def part(ctrl, keys):
        p = at(spline(ctrl, 1.0 / k))
        return sd_stroke(p, profile(p, keys) * k)

    lappet = part([(2, -5), (-6, -10), (-15, -11.5), (-22, -8), (-21, -3), (-16, -4.5)],
                  [(0, 2.4), (0.5, 1.7), (1, 0.6)])
    skull = part([(0, 0.5), (6, -0.5), (13, -0.5)], [(0, 5.0), (0.45, 6.6), (1, 5.4)])
    upper = part([(10, -2), (18, -2.6), (26, -2.2), (30, -4.5), (29, -8), (26, -7.4)],
                 [(0, 4.2), (0.5, 2.6), (0.75, 1.6), (1, 0.7)])
    lower = part([(10, 3), (17, 6.5), (24, 10.5)], [(0, 3.4), (1, 1.1)])
    draw(lappet, SERPENT)
    draw(np.minimum(np.minimum(skull, upper), lower), SERPENT)
    # El ojo, una almendra con la punta hacia atrás, y el labio grabado.
    almond = at(resample([(4.5, -2.2), (8.5, -3.6), (12.5, -2.8)], 0.4))
    radii = np.sin(np.linspace(0.0, math.pi, len(almond))) ** 0.7 * 1.7 * k + 0.3
    draw(sd_stroke(almond, radii), dict(fill=BRONZE))
    paint(coverage(sd_circle(at([(10.0, -3.1)])[0], 0.9 * k)), INK)
    engrave(at(spline([(13, -0.6), (19, -0.4), (25, 0.2)], 0.5)), 0.45, 0.6)


def serpent_body(mirrored=False):
    """El cuerpo de una sierpe: sale de la nuca, se echa sobre el borde de arriba de la barra y la
    recorre a jorobas, hundiéndose en la placa entre una y otra, hasta que la cola sale hecha
    zarcillo. Devuelve los puntos y el radio."""
    bite = on_ring(LEFT, HOUSING - 1.5, SERPENT_BITE)
    neck = serpent_neck(bite, SERPENT_SNOUT, SERPENT_K, SERPENT_FLIP)
    a = math.radians(SERPENT_SNOUT)
    back = neck - np.array([math.cos(a), math.sin(a)]) * 8.0
    ctrl = [tuple(neck), tuple(back), (24, -26), (46, -26), (68, -38), (90, -48), (112, -40), (128, -20),
            (142, -4), (160, -4), (176, -22), (196, -34), (216, -24), (230, -6), (248, -4), (266, -18),
            (284, -29), (300, -38)]
    ctrl += spiral((296, -52), 12.0, 3.5, 20, -310, 20)[1:]
    body = spline(ctrl)
    radii = profile(body, [(0, 8.0), (0.08, 10.0), (0.45, 8.6), (0.68, 6.0), (0.8, 2.6), (1, 1.1)])
    return (mirror(body) if mirrored else body), radii


def serpent(mirrored):
    """Lo que la sierpe lleva encima de la placa (el cuerpo ya va en ella, ver plate()): el lomo
    grabado donde asoma, las hojas del zarcillo y la cabeza, que muerde el engaste donde se junta
    con la barra."""
    p, radii = serpent_body(mirrored)
    # Lomo grabado, solo donde el cuerpo asoma por encima de la placa.
    spine = slice(int(len(p) * 0.02), int(len(p) * 0.8))
    out = 1.0 - coverage(plate_sdf() + 3.0)
    paint(coverage(sd_stroke(p[spine], np.full(len(p[spine]), 0.55), reach=3.0)) * out, BRONZE, 0.5)
    # Hojas del zarcillo.
    leaf((276, -26), -70, 22, 8.5, 16, 30, mirrored)
    leaf((304, -40), 10, 16, 6.5, 12, 26, mirrored)
    serpent_head(on_ring(LEFT, HOUSING - 1.5, SERPENT_BITE), SERPENT_SNOUT, mirrored)


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
    for mirrored in (False, True):
        ash_roots(mirrored)
    plate()
    braid()
    runes(LEFT, RUNE_TEXT["left"], RUNE_IN, RUNE_OUT, RUNE_H)
    breath = runes(RIGHT, RUNE_TEXT["right"], RUNE_IN, RUNE_OUT, RUNE_H)
    runes(DOME_CENTRE, SANITY_TEXT, DOME_RUNE_IN, DOME_RUNE_OUT, 8.0, (-80.0, 80.0))
    for centre, medallion, end, icon in GAUGES:
        gauge(centre, medallion, end, icon)
    for mirrored in (False, True):
        serpent(mirrored)
        crown(mirrored)
    crest()
    ravens()

    alpha = CANVAS[..., 3]
    colour = np.where(alpha[..., None] > 1e-5, CANVAS[..., :3] / np.maximum(alpha, 1e-5)[..., None], 0.0)
    out = np.concatenate([colour, alpha[..., None]], axis=2)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT)
    print(f"{OUT}: {W}x{H}")
    print(f"VitalsPlate.BAR_ORIGIN = Vector2({-X0 * ART:g}, {-Y0 * ART:g}), REACH = {-X0:g}")
    breath_mask(breath)


if __name__ == "__main__":
    main()
