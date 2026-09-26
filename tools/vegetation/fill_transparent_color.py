#!/usr/bin/env python3
"""Rellena el color (RGB) de las zonas transparentes de una textura con recorte alfa.

Las texturas de ramita tienen negro donde alfa = 0. Godot solo arregla unos píxeles junto
al borde (fix_alpha_border), así que en los mipmaps pequeños -los que se usan de lejos y
al hornear los impostores- el negro se promedia con las hojas y las oscurece un ~30 %.
Relleno push-pull: pirámide de color premultiplicado y alfa, y cada hueco toma el color
medio de la escala más fina que tenga cobertura. El alfa y los píxeles con alfa > 0 no
cambian: a resolución completa la textura se ve igual.

    python3 tools/vegetation/fill_transparent_color.py textura.png [...]
"""
import sys
from PIL import Image, ImageMath


def fill(path):
    im = Image.open(path).convert("RGBA")
    r, g, b, a = [ch.convert("F") for ch in im.split()]
    af = ImageMath.lambda_eval(lambda e: e["a"] / 255.0, a=a)
    prem = [ImageMath.lambda_eval(lambda e: e["c"] * e["a"], c=c, a=af) for c in (r, g, b)]
    # Pirámide hasta 1 px.
    levels = [(prem, af)]
    w, h = im.size
    while w > 1 or h > 1:
        w, h = max(1, w // 2), max(1, h // 2)
        p, al = levels[-1]
        levels.append(([c.resize((w, h), Image.BOX) for c in p], al.resize((w, h), Image.BOX)))
    # De la más gruesa a la más fina: color = premultiplicado / alfa, o el de la escala superior.
    filled = None
    for p, al in reversed(levels):
        size = al.size
        colors = [ImageMath.lambda_eval(lambda e: e["c"] / (e["a"] + 1e-6), c=c, a=al) for c in p]
        if filled is not None:
            up = [c.resize(size, Image.BILINEAR) for c in filled]
            # Donde casi no hay cobertura, manda la escala gruesa.
            colors = [ImageMath.lambda_eval(
                lambda e: e["own"] * e["w"] + e["up"] * (1.0 - e["w"]),
                own=own, up=u, w=ImageMath.lambda_eval(lambda e: e["min"](e["a"] * 8.0, 1.0), a=al))
                for own, u in zip(colors, up)]
        filled = colors
    out = []
    for orig, fil in zip((r, g, b), filled):
        # Conserva el color original donde hay algo de alfa.
        mixed = ImageMath.lambda_eval(lambda e: e["o"] * e["k"] + e["f"] * (1.0 - e["k"]),
            o=orig, f=fil, k=ImageMath.lambda_eval(lambda e: e["min"](e["a"] * 255.0, 1.0), a=af))
        out.append(mixed.convert("L"))
    Image.merge("RGBA", out + [im.split()[3]]).save(path, optimize=True)
    print("filled", path)


for arg in sys.argv[1:]:
    fill(arg)
