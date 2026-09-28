"""Pelajes de la fauna fría a partir de las texturas de los animales templados:
  scenes/animals/PolarBear_Bear.png  oso polar: el pelo del oso pardo pasa a blanco crema
                                     conservando su detalle; ojos, nariz, garras y boca igual.
  scenes/animals/Caribou_Deer.png    caribú: el pardo anaranjado del ciervo pasa a gris pardo,
                                     con las zonas blancas intactas.
    build/fauna_tools/bin/python tools/fauna/recolor_cold_fauna.py
"""
from pathlib import Path
import colorsys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ANIMALS = ROOT / "scenes/animals"


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    v = mx
    s = np.where(mx > 1e-6, (mx - mn) / np.maximum(mx, 1e-6), 0)
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6
    return h, s, v


def polar_bear():
    src = np.asarray(Image.open(ANIMALS / "Bear_Bear.png").convert("RGB")).astype(np.float32) / 255
    lum = src @ np.array([0.2126, 0.7152, 0.0722])
    h, s, v = to_hsv(src)
    lo, hi = np.percentile(lum, 5), np.percentile(lum, 95)
    t = np.clip((lum - lo) / (hi - lo), 0, 1) ** 0.6
    dark = np.array([0.74, 0.70, 0.60])
    light = np.array([0.97, 0.95, 0.89])
    fur = dark + (light - dark) * t[..., None]
    # Se quedan como estaban: lo muy oscuro (ojos, nariz, almohadillas) y lo rojizo saturado (boca).
    keep = np.maximum(smooth(0.03, 0.012, lum), smooth(0.25, 0.4, s) * ((h < 0.05) | (h > 0.9)))
    out = fur * (1 - keep[..., None]) + src * keep[..., None]
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(ANIMALS / "PolarBear_Bear.png")
    print("wrote PolarBear_Bear.png")


def caribou():
    img = Image.open(ANIMALS / "Deer_Deer_M_BC.png")
    alpha = img.getchannel("A") if img.mode == "RGBA" else None
    src = np.asarray(img.convert("RGB")).astype(np.float32) / 255
    lum = src @ np.array([0.2126, 0.7152, 0.0722])
    h, s, v = to_hsv(src)
    grey_brown = np.array([0.46, 0.42, 0.37])
    # Pelaje pardo: su luminancia sobre un gris pardo, algo más oscuro; lo blanco y lo gris se quedan.
    brown = smooth(0.18, 0.35, s) * ((h > 0.02) & (h < 0.14))
    detail = lum / max(np.percentile(lum, 50), 1e-3)
    recolored = grey_brown * np.clip(detail, 0.2, 2.2)[..., None] * 0.95
    out = src * (1 - brown[..., None]) + recolored * brown[..., None]
    result = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8))
    if alpha is not None:
        result.putalpha(alpha)
    result.save(ANIMALS / "Caribou_Deer.png")
    print("wrote Caribou_Deer.png")


if __name__ == "__main__":
    polar_bear()
    caribou()
