"""Corteza de abedul procedural y repetible (1024 px): blanca crema con lenticelas horizontales
oscuras, tiras que se pelan y manchas negras rugosas. Escribe albedo, normal (OpenGL) y
rugosidad en textures/planet/vegetation/tree/trunk/bark_birch_*.jpg.
El eje vertical de la imagen va a lo largo del tronco, como en las demás cortezas.

    build/fauna_tools/bin/python tools/vegetation/paint_birch_bark.py
"""
from pathlib import Path
import numpy as np
from PIL import Image

N = 1024
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "textures/planet/vegetation/tree/trunk"
rng = np.random.default_rng(2718)


def periodic_noise(freq_x, freq_y, octaves=4, seed=0):
    """Ruido repetible por síntesis espectral (filtro sobre ruido blanco en frecuencia)."""
    r = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp = 1.0
    for o in range(octaves):
        spec = np.fft.fft2(r.standard_normal((N, N)))
        fy = np.fft.fftfreq(N)[:, None] * N
        fx = np.fft.fftfreq(N)[None, :] * N
        fx0, fy0 = freq_x * 2 ** o, freq_y * 2 ** o
        filt = np.exp(-((fx / fx0) ** 2 + (fy / fy0) ** 2))
        layer = np.real(np.fft.ifft2(spec * filt))
        layer /= layer.std() + 1e-9
        out += layer * amp
        amp *= 0.5
    return out / out.std()


def stamp(field, cy, cx, h, w, value, mode="min"):
    """Pinta un rectángulo redondeado con borde suave, envolviendo en los bordes."""
    ys = np.arange(int(cy - h * 2), int(cy + h * 2) + 1)
    xs = np.arange(int(cx - w), int(cx + w) + 1)
    yy, xx = np.meshgrid(ys, xs, indexing="ij")
    d = np.sqrt(((yy - cy) / max(h, 0.5)) ** 2 + ((xx - cx) / max(w, 0.5)) ** 2)
    a = np.clip(1.5 - d, 0, 1)
    iy, ix = yy % N, xx % N
    if mode == "min":
        field[iy, ix] = np.minimum(field[iy, ix], 1 - a * (1 - value))
    else:
        field[iy, ix] = np.maximum(field[iy, ix], a * value)


# Base: crema con vetas horizontales muy suaves (la corteza se estira alrededor del tronco).
tone = periodic_noise(2, 10, 5, 1)
fine = periodic_noise(24, 90, 3, 2)
base = np.stack([0.86 + tone * 0.025 + fine * 0.015,
                 0.84 + tone * 0.025 + fine * 0.015,
                 0.79 + tone * 0.03 + fine * 0.02], -1)
# Tiras de corteza que se pelan: bandas horizontales algo rosadas o grises.
peel = periodic_noise(3, 40, 3, 3)
peel_mask = np.clip((peel - 1.1) * 2.5, 0, 1)[..., None]
base = base * (1 - peel_mask * 0.25) + np.array([0.80, 0.70, 0.62]) * peel_mask * 0.25

height = 0.5 + tone * 0.02 + fine * 0.03 - peel_mask[..., 0] * 0.08
dark = np.ones((N, N))          # 1 = sin lenticela, 0 = negro
rough = np.full((N, N), 0.52) + fine * 0.03

# Lenticelas: rayas horizontales cortas, agrupadas en bandas.
band_density = np.clip(periodic_noise(1, 6, 2, 4) * 0.5 + 0.7, 0.1, 1.5)
for _ in range(900):
    cy, cx = rng.uniform(0, N), rng.uniform(0, N)
    if rng.uniform() > band_density[int(cy) % N, int(cx) % N] * 0.55:
        continue
    w = rng.uniform(6, 30) * (2.2 if rng.uniform() < 0.08 else 1.0)
    h = rng.uniform(1.0, 2.4)
    stamp(dark, cy, cx, h, w, rng.uniform(0.12, 0.55))

# Manchas negras rugosas (grietas viejas en la base de las ramas).
blot = np.zeros((N, N))
for _ in range(5):
    cy, cx = rng.uniform(0, N), rng.uniform(0, N)
    for _ in range(26):
        stamp(blot, cy + rng.normal(0, 12), cx + rng.normal(0, 30), rng.uniform(3, 8), rng.uniform(6, 26),
              rng.uniform(0.6, 1.0), mode="max")
crack = periodic_noise(40, 40, 2, 5)
blot = np.clip(blot * (0.75 + crack * 0.2), 0, 1)

albedo = base * dark[..., None]
albedo = albedo * (1 - blot[..., None]) + np.array([0.09, 0.08, 0.075]) * blot[..., None] * (1 + crack[..., None] * 0.2)
height = height - (1 - dark) * 0.35 + blot * (0.12 + crack * 0.06)
rough = np.clip(rough + (1 - dark) * 0.3 + blot * 0.35, 0, 1)

# Normal OpenGL desde la altura (envolviendo).
strength = 6.0
gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
nrm = np.stack([-gx, gy, np.ones_like(gx)], -1)
nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)

def save(arr, name):
    Image.fromarray(np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8)).save(OUT / name, quality=92)
    print("wrote", OUT / name)

save(np.clip(albedo, 0, 1), "bark_birch_albedo.jpg")
save(nrm * 0.5 + 0.5, "bark_birch_normal.jpg")
save(rough, "bark_birch_roughness.jpg")
