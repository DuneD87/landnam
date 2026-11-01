#!/usr/bin/env python3
"""Hornea el marco del minimapa: textures/ui/minimap_frame.png.

La talla de la consola de la barra rápida (bake_hotbar_console.py), con sus mismas piezas, para el
minimapa (Minimap): el mapa va en un engaste de hierro con una banda de runas, «land auk haf»
(tierra y mar), coronado por una copa de hojas como los engastes de las orbes. La banda se abre
arriba para el medallón del norte y abajo para la cartela de la estación, una placa pequeña con las
puntas en pico, como las barras de las criaturas. A la izquierda, a media altura y fundida con el
engaste sin cuello (su hueco llega hasta la banda de runas), va la cajita de la hora y la altura,
con las dos filas separadas por un filete con un rombo. Los textos (la N, la estación, la hora y la altura) los
escribe Minimap.

Las medidas van en píxeles base (1440 px de alto) con el origen en el centro del mapa, y la imagen
a ART píxeles por cada uno, como la consola. Si cambian, hay que cambiar también las constantes de
Minimap con lo que imprime este script al acabar.

    build/fauna_tools/bin/python -I tools/ui/bake_minimap_frame.py
    godot --headless --editor --quit --path .   # importa la textura
"""

import importlib.util
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "textures", "ui", "minimap_frame.png")

# Las piezas de la consola, cargadas por ruta (con -I la carpeta del script no está en sys.path).
_spec = importlib.util.spec_from_file_location("bake_hotbar_console", os.path.join(HERE, "bake_hotbar_console.py"))
saga = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(saga)

# Radio del mapa (Minimap.MAP_RADIUS); su aro lo dibuja Minimap, como las orbes el suyo.
MAP_R = 108.0
# Banda de runas y engaste, a la misma distancia del mapa que los de las orbes de la barra.
RUNE_IN, RUNE_OUT = MAP_R + 4.0, MAP_R + 19.5
RUNE_MID = (RUNE_IN + RUNE_OUT) * 0.5
HOUSING = MAP_R + 26.0
RUNE_H = 9.5
# «land auk haf»: tierra y mar.
RUNE_TEXT = ["l", "a", "n", "t", "|", "a", "u", "k", "|", "h", "a", "f", "|"]
# Medallón del norte, sobre la banda de runas.
NORTH_R = 13.0
NORTH_AT = (0.0, -RUNE_MID)
# Cartela de la estación: medio largo del cuerpo, medio alto, lo que sale cada pico y su centro,
# sobre la banda (sin rozar el aro del mapa). La banda se abre SEASON_GAP grados a cada lado de abajo.
SEASON_HALF_W, SEASON_HALF_H, SEASON_TIP = 81.0, 15.0, 10.0
SEASON_AT = (0.0, 124.0)
SEASON_GAP = 34.0
# Cajita de la hora y la altura (x0, y0, x1, y1), con las esquinas biseladas. Su lado derecho queda
# dentro del engaste: se funde con él con un rincón de JOIN_FILLET, sin cuello. Su filete de dentro y
# su hueco llegan hasta la banda de runas; entre las dos filas, otro filete. Es justo lo que piden un
# icono de 20 px pegado a «00:00» o a «888 m» a 26 px (63 px), con los textos arrimados al aro
# (acaban en TEXT_RIGHT).
BOX = (-231.0, -40.0, -110.0, 40.0)
BOX_CUT = 10.0
BOX_INSET = 6.0
JOIN_FILLET = 6.0
RULE_Y = 0.0
# Líneas de base de la hora y de la altura, y dónde acaban, a unos píxeles de la banda (las usa
# Minimap).
TIME_BASELINE, ALTITUDE_BASELINE = -7.0, 25.0
TEXT_RIGHT = -133.0
# Lienzo.
X0, X1 = -240.0, 150.0
Y0, Y1 = -172.0, 156.0


def use_canvas():
    """Las piezas de la consola dibujan sobre los globales de su módulo: se les da este lienzo. Con
    BAR_W = 0, lo que dibujan con `mirrored` sale reflejado en x = 0, el eje del minimapa."""
    w = int(round((X1 - X0) * saga.ART))
    h = int(round((Y1 - Y0) * saga.ART))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    saga.X0, saga.Y0, saga.W, saga.H = X0, Y0, w, h
    saga.BX = (xx + 0.5) / saga.ART + X0
    saga.BY = (yy + 0.5) / saga.ART + Y0
    saga.CANVAS = np.zeros((h, w, 4), np.float32)
    saga.BAR_W = 0.0


def union_round(a, b, r):
    """Unión con el rincón redondeado por un arco de radio [r] (fOpUnionRound de hg_sdf). A
    diferencia de smin, por fuera sigue siendo una distancia: los filetes salen del mismo grueso
    también en la curva."""
    u = np.hypot(np.maximum(r - a, 0.0), np.maximum(r - b, 0.0))
    return np.maximum(r, np.minimum(a, b)) - u


def sd_chamfered_box(rect, cut):
    """Caja con las cuatro esquinas cortadas [cut] píxeles base, como SagaFrame."""
    x0, y0, x1, y1 = rect
    box = saga.sd_box((x0, y0), (x1, y1))
    cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
    reach = (x1 - x0) * 0.5 + (y1 - y0) * 0.5 - cut
    corners = (np.abs(saga.BX - cx) + np.abs(saga.BY - cy) - reach) * 0.7071
    return np.maximum(box, corners)


def sd_cartouche():
    """La cartela: una placa con las puntas en pico. Distancia exacta en las caras."""
    x = np.abs(saga.BX - SEASON_AT[0]) - SEASON_HALF_W
    y = np.abs(saga.BY - SEASON_AT[1]) - SEASON_HALF_H
    # Cara del pico: de la esquina del cuerpo a la punta, con la normal hacia fuera.
    length = math.hypot(SEASON_TIP, SEASON_HALF_H)
    tip = (x * SEASON_HALF_H + y * SEASON_TIP) / length
    return np.maximum(y, tip)


def plate():
    housing = saga.sd_circle((0.0, 0.0), HOUSING)
    whole = union_round(housing, sd_chamfered_box(BOX, BOX_CUT), JOIN_FILLET)
    saga.paint(saga.coverage(whole), saga.IRON, saga.IRON_ALPHA)
    saga.paint(saga.band_of(whole, 1.0), saga.BRONZE, 0.55)
    # Hueco del mapa, más oscuro según se acerca a él, entre los filetes de la banda de runas. El
    # filete de fuera de la banda hace de filete de dentro del engaste, como en las orbes.
    r = saga.sd_circle((0.0, 0.0), 0.0)
    saga.paint(saga.coverage(r - RUNE_IN), saga.IRON_DEEP,
               np.clip(1.0 - (r - MAP_R) / (RUNE_IN - MAP_R), 0.4, 1.0))
    saga.paint(saga.band_of(r - RUNE_IN - 1.0, 1.0), saga.BRONZE, 0.5)
    saga.paint(saga.band_of(r - RUNE_OUT, 1.0), saga.BRONZE, 0.5)


def stats_box():
    # Dentro de la cajita, un filete tenue y el fondo algo más oscuro para que se lea, que llegan
    # hasta la banda de runas: el filete de fuera de la banda cierra el hueco por la derecha. Entre
    # la hora y la altura, el filete de SagaRule, que se desvanece hacia los lados con un rombo en
    # medio.
    box = sd_chamfered_box(BOX, BOX_CUT)
    inner = box + BOX_INSET
    outside_band = np.clip((saga.sd_circle((0.0, 0.0), RUNE_OUT + 1.0)) * saga.ART, 0.0, 1.0)
    saga.paint(saga.coverage(inner) * outside_band, saga.IRON_DEEP, 0.45)
    saga.paint(saga.band_of(box, 1.0, BOX_INSET) * outside_band, saga.BRONZE, 0.2)
    left, right = BOX[0] + BOX_INSET, -RUNE_OUT
    cx = (left + right) * 0.5
    half = (right - left) * 0.5 - 10.0
    line = saga.resample([(cx - half, RULE_Y), (cx + half, RULE_Y)], 0.75)
    fade = np.clip(1.0 - np.abs(saga.BX - cx) / half, 0.0, 1.0) ** 0.6
    saga.paint(saga.coverage(saga.sd_stroke(line, np.full(len(line), 0.5), reach=3.0)) * fade, saga.BRONZE, 0.6)
    saga.rivet((cx, RULE_Y), 3.0)
    # Remaches en las esquinas de fuera.
    for y in (BOX[1] + BOX_CUT * 0.5, BOX[3] - BOX_CUT * 0.5):
        saga.rivet((BOX[0] + BOX_CUT * 0.5, y), 3.5)


def band_runes():
    # La frase se repite por cada tramo de la banda, del medallón del norte a la cartela y de la
    # cartela al medallón.
    north_gap = math.degrees((NORTH_R + 3.0) / RUNE_MID)
    phrase = sum(saga.glyph_width(t) + 0.5 for t in RUNE_TEXT) * RUNE_H
    for start, end in ((north_gap, 180.0 - SEASON_GAP), (180.0 + SEASON_GAP, 360.0 - north_gap)):
        length = math.radians(end - start) * RUNE_MID
        tokens = RUNE_TEXT * max(1, round(length / phrase))
        saga.runes((0.0, 0.0), tokens[:-1], RUNE_IN, RUNE_OUT, RUNE_H, (start, end))


def north():
    # La copa de hojas, y encima de sus tallos el medallón del norte.
    top = -HOUSING
    saga.leaf((-4.0, top + 1.0), -126, 22, 9.0, -14, -38)
    saga.leaf((1.0, top - 1.0), -92, 27, 10.5, 10, 28)
    saga.leaf((7.0, top + 1.0), -56, 21, 8.5, 18, 36)
    disc = saga.sd_circle(NORTH_AT, NORTH_R)
    saga.draw(disc, saga.MEDALLION)
    saga.paint(saga.band_of(disc, 1.0, 3.5), saga.BRONZE, 0.2)


def cartouche():
    # Encima de la banda, con su halo, como el medallón, y un remache en cada punta.
    d = sd_cartouche()
    saga.draw(d, saga.MEDALLION)
    saga.paint(saga.band_of(d, 1.0, 3.0), saga.BRONZE, 0.2)
    for side in (-1.0, 1.0):
        saga.rivet((SEASON_AT[0] + side * (SEASON_HALF_W + 1.0), SEASON_AT[1]), 3.0)


def main():
    use_canvas()
    plate()
    stats_box()
    band_runes()
    north()
    cartouche()

    canvas = saga.CANVAS
    alpha = canvas[..., 3]
    colour = np.where(alpha[..., None] > 1e-5, canvas[..., :3] / np.maximum(alpha, 1e-5)[..., None], 0.0)
    out = np.concatenate([colour, alpha[..., None]], axis=2)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT)
    print(f"{OUT}: {saga.W}x{saga.H}")
    # Lo que ocupa la talla de verdad (sin el margen vacío del lienzo), para arrimarla a los bordes.
    rows = np.nonzero(alpha.max(axis=1) > 0.02)[0]
    cols = np.nonzero(alpha.max(axis=0) > 0.02)[0]
    bounds = [cols[0] / saga.ART + X0, rows[0] / saga.ART + Y0,
              (cols[-1] + 1) / saga.ART + X0, (rows[-1] + 1) / saga.ART + Y0]
    panel = (BOX[0] + BOX_INSET, BOX[1] + BOX_INSET, -RUNE_OUT, BOX[3] - BOX_INSET)
    room = (SEASON_HALF_W - 6.0) * 2.0
    print(f"Minimap: MAP_RADIUS = {MAP_R:g}, ART_RECT = Rect2({X0:g}, {Y0:g}, {X1 - X0:g}, {Y1 - Y0:g}), "
          f"BOUNDS = Rect2({bounds[0]:g}, {bounds[1]:g}, {bounds[2] - bounds[0]:g}, {bounds[3] - bounds[1]:g}), "
          f"NORTH_AT = Vector2({NORTH_AT[0]:g}, {NORTH_AT[1]:g}), "
          f"SEASON_RECT = Rect2({SEASON_AT[0] - room * 0.5:g}, {SEASON_AT[1] - SEASON_HALF_H:g}, "
          f"{room:g}, {SEASON_HALF_H * 2.0:g}), "
          f"STATS_PANEL = Rect2({panel[0]:g}, {panel[1]:g}, {panel[2] - panel[0]:g}, {panel[3] - panel[1]:g}), "
          f"TIME_BASELINE = {TIME_BASELINE:g}, ALTITUDE_BASELINE = {ALTITUDE_BASELINE:g}, TEXT_RIGHT = {TEXT_RIGHT:g}")


if __name__ == "__main__":
    main()
