"""Paints the skin masks of the human from the MakeHuman export.

    blender -b --python tools/character/blender/make_skin_masks.py -- <export dir>

Reads human.json/human.bin (export_mpfb_human.py) and writes to the same
directory (numpy is only at hand in Blender's Python):

 - masks.png (1024, RGBA): scalp, full beard, moustache and goatee regions.
   Rules on the male base head, per vertex, rasterized in UV space;
 - body_masks.png (1024, R/G): pubic hair fields for women and men, from 1
   at the core down to 0 at the fullest reach, so one threshold in the
   shader sets how far the hair goes. The men's also climbs to the navel;
 - stubble.png (512, tiling): R short straight strokes for stubble and buzz
   cuts, G curls for pubic hair;
 - skin_normal_female.png: the skin relief map with the breasts flattened, as
   it was sculpted on a male chest.
"""

import json
import os
import sys

import bpy
import numpy as np

OUT = sys.argv[sys.argv.index("--") + 1]
MASK_SIZE = 1024


def load():
    with open(os.path.join(OUT, "human.json")) as f:
        header = json.load(f)
    blob = open(os.path.join(OUT, "human.bin"), "rb").read()

    def array(entry, dtype=np.float32, width=None):
        data = np.frombuffer(blob, dtype=dtype, count=entry["count"], offset=entry["offset"])
        return data.reshape(-1, width) if width else data

    return header, array


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def rasterize(uvs, triangles, values, size):
    """Interpolates per-vertex values over the UV triangles (max where they overlap)."""
    channels = values.shape[1]
    image = np.zeros((size, size, channels), dtype=np.float32)
    pixel = uvs * size - 0.5
    for tri in triangles:
        if not values[tri].any():
            continue
        p = pixel[tri]
        lo = np.floor(p.min(axis=0)).astype(int)
        hi = np.ceil(p.max(axis=0)).astype(int)
        lo = np.clip(lo, 0, size - 1)
        hi = np.clip(hi, 0, size - 1)
        xs, ys = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
        q = np.stack([xs.ravel(), ys.ravel()], axis=1).astype(np.float32)
        a, b, c = p
        m = np.array([[b[0] - a[0], c[0] - a[0]], [b[1] - a[1], c[1] - a[1]]])
        det = np.linalg.det(m)
        if abs(det) < 1e-9:
            continue
        inv = np.linalg.inv(m)
        uv = (q - a) @ inv.T
        w = np.stack([1.0 - uv[:, 0] - uv[:, 1], uv[:, 0], uv[:, 1]], axis=1)
        inside = (w >= -0.02).all(axis=1)
        if not inside.any():
            continue
        v = w[inside] @ values[tri]
        px = q[inside].astype(int)
        cur = image[px[:, 1], px[:, 0]]
        image[px[:, 1], px[:, 0]] = np.maximum(cur, v)
    return image


def blur(image, radius):
    """Box blur, repeated three times (about Gaussian), wrapping nothing."""
    for _ in range(3):
        for axis in (0, 1):
            padded = np.pad(image, [(radius, radius) if a == axis else (0, 0) for a in range(image.ndim)], mode="edge")
            cumsum = np.cumsum(padded, axis=axis, dtype=np.float64)
            zero = np.zeros_like(np.take(cumsum, [0], axis=axis))
            cumsum = np.concatenate([zero, cumsum], axis=axis)
            n = image.shape[axis]
            upper = np.take(cumsum, np.arange(2 * radius + 1, n + 2 * radius + 1), axis=axis)
            lower = np.take(cumsum, np.arange(0, n), axis=axis)
            image = ((upper - lower) / (2 * radius + 1)).astype(np.float32)
    return image


def save(image, path):
    """Writes a (size, size, 1..4) float image, first row at the top."""
    size = image.shape[0]
    channels = image.shape[2]
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[..., :channels] = image
    if channels == 1:
        rgba[..., 1] = rgba[..., 2] = image[..., 0]
    out = bpy.data.images.new(os.path.basename(path), size, size, alpha=True)
    out.pixels[:] = np.flipud(np.clip(rgba, 0.0, 1.0)).ravel()
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)


def head_masks(header, array):
    body = header["body"]
    p = array(body["positions"], width=3)
    uvs = array(body["uvs"], width=2)
    triangles = array(body["indices"], np.int32, 3)
    lips = array(body["group_lips"])
    ears = array(body["group_ears"])
    scalp = array(body["group_scalp"])
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)

    # Landmarks of the male base face.
    mouth = p[lips > 0.5].mean(axis=0)
    mouth_half = np.abs(p[lips > 0.5, 0]).max()
    front = (ax < 0.006) & (y > mouth[1] + 0.01) & (y < mouth[1] + 0.07)
    nose = p[front][np.argmax(z[front])]
    below = (ax < 0.01) & (y < mouth[1]) & (y > mouth[1] - 0.09) & (z > mouth[2] - 0.06)
    chin = p[below][np.argmin(y[below])] if below.any() else mouth - [0, 0.05, 0]
    ear = p[(ears > 0.5) & (x > 0)].mean(axis=0)
    print("Landmarks mouth", mouth.round(3), "nose", nose.round(3), "chin", chin.round(3), "ear", ear.round(3))

    # Full beard: below the nose, down under the jaw, in front of the ears. The
    # upper edge runs from beside the nose down to below the ear.
    side = np.clip(ax / abs(ear[0]), 0.0, 1.0)
    top = nose[1] - 0.012 + (ear[1] - 0.028 - (nose[1] - 0.012)) * side ** 1.4
    beard = (1.0 - smoothstep(top - 0.008, top + 0.004, y))
    beard *= smoothstep(chin[1] - 0.02, chin[1] - 0.004, y)                     # under the jaw
    beard *= 1.0 - smoothstep(abs(ear[0]) - 0.012, abs(ear[0]) + 0.004, ax)     # not past the jaw's width
    beard *= smoothstep(ear[2] - 0.012, ear[2] + 0.004, z)                      # in front of the ears
    beard *= 1.0 - smoothstep(0.35, 0.6, lips)
    nose_zone = (ax < 0.022) & (y > mouth[1] + 0.014)
    beard[nose_zone] *= 1.0 - smoothstep(nose[1] - 0.03, nose[1] - 0.012, y[nose_zone])
    head = y > chin[1] - 0.09
    beard *= head
    # Moustache: between the upper lip and the nose.
    moustache = smoothstep(mouth[1] + 0.001, mouth[1] + 0.006, y) * (1.0 - smoothstep(nose[1] - 0.022, nose[1] - 0.012, y))
    moustache *= 1.0 - smoothstep(mouth_half + 0.002, mouth_half + 0.014, ax)
    moustache *= smoothstep(mouth[2] - 0.03, mouth[2] - 0.012, z) * (1.0 - smoothstep(0.35, 0.6, lips))
    # Goatee: the chin under the lower lip.
    goatee = (1.0 - smoothstep(0.016, 0.03, ax)) * (1.0 - smoothstep(mouth[1] - 0.012, mouth[1] - 0.005, y))
    goatee *= smoothstep(chin[1] - 0.015, chin[1] - 0.002, y) * smoothstep(chin[2] - 0.04, chin[2] - 0.015, z)
    goatee *= 1.0 - smoothstep(0.35, 0.6, lips)
    goatee = np.maximum(goatee, moustache)
    scalp_mask = smoothstep(0.1, 0.6, scalp)

    values = np.stack([scalp_mask, beard, moustache, goatee], axis=1).astype(np.float32)
    image = rasterize(uvs, triangles, values, MASK_SIZE)
    return blur(image, 2)


def pubic_masks(header, array):
    """Pubic hair fields on the male base's pelvis (skin space, metres, Y up,
    +Z forward, origin at the hips): a triangle over the pubis, from the
    crotch up, narrow at the bottom and wide at the top."""
    body = header["body"]
    p = array(body["positions"], width=3)
    x, y, z = np.abs(p[:, 0]), p[:, 1], p[:, 2]
    genitals = array(header["proxies"]["genitals"]["positions"], width=3)
    root = genitals[np.argmax(genitals[:, 1])]          # the penis root, on the pubis
    bottom = root[1] - 0.04                              # the crotch
    top = root[1] + 0.07
    near = (y > bottom - 0.06) & (y < top + 0.2) & (x < 0.14) & (z > -0.01)
    t = (y - bottom) / (top - bottom)

    def field(width_bottom, width_top, roundness):
        width = width_bottom + (width_top - width_bottom) * np.clip(t, 0.0, 1.3)
        across = x / width
        # Above: a flat top for roundness 0, a mound for 1. Below: the hair
        # thins out between the legs.
        up = np.maximum(t, 0.0) + roundness * across ** 2 * 0.35
        down = np.maximum(-t, 0.0) * 1.8
        reach = np.maximum(np.maximum(across, up), down)
        return np.clip(1.0 - reach / 1.45, 0.0, 1.0) * near

    female = field(0.02, 0.075, 0.2)
    male = field(0.025, 0.07, 0.8)
    # A trail up to the navel, only at the fullest.
    trail = (1.0 - smoothstep(0.006, 0.02, x)) * smoothstep(top - 0.02, top + 0.02, y)
    trail *= 0.4 * (1.0 - np.clip((y - top) / 0.16, 0.0, 1.0)) * near
    male = np.maximum(male, trail)
    print("Pubis root", root.round(3), "crotch %.3f top %.3f" % (bottom, top))
    values = np.stack([female, male], axis=1).astype(np.float32)
    image = rasterize(array(body["uvs"], width=2), array(body["indices"], np.int32, 3), values, MASK_SIZE)
    return blur(image, 2)


def curls(size=512, seed=11):
    """Tiling field of short curled strokes (1 = hair)."""
    rng = np.random.default_rng(seed)
    image = np.zeros((size, size), dtype=np.float32)
    count = size * size // 110
    centres = rng.uniform(0, size, (count, 2))
    radii = rng.uniform(4.0, 8.0, count)
    starts = rng.uniform(0, 2 * np.pi, count)
    sweeps = rng.uniform(1.5, 3.5, count) * rng.choice([-1.0, 1.0], count)
    for step in np.linspace(0.0, 1.0, 40):
        angle = starts + sweeps * step
        r = radii * (1.0 - 0.3 * step)
        xs = (centres[:, 0] + np.cos(angle) * r).astype(int) % size
        ys = (centres[:, 1] + np.sin(angle) * r).astype(int) % size
        np.maximum.at(image, (ys, xs), 1.0 - 0.3 * step)
    soft = image
    for _ in range(2):
        soft = (soft + np.roll(soft, 1, 0) + np.roll(soft, 1, 1) + np.roll(soft, -1, 0) + np.roll(soft, -1, 1)) / 5.0
    return np.clip(0.5 * image + 1.2 * soft, 0.0, 1.0)


def stubble(size=512, seed=7):
    """Tiling field of short strokes (1 = hair)."""
    rng = np.random.default_rng(seed)
    image = np.zeros((size, size), dtype=np.float32)
    count = size * size // 18
    starts = rng.uniform(0, size, (count, 2))
    angles = rng.normal(np.pi / 2, 0.45, count)
    lengths = rng.uniform(2.0, 5.0, count)
    for step in np.linspace(0.0, 1.0, 6):
        xs = (starts[:, 0] + np.cos(angles) * lengths * step).astype(int) % size
        ys = (starts[:, 1] + np.sin(angles) * lengths * step).astype(int) % size
        np.maximum.at(image, (ys, xs), 1.0 - 0.4 * step)
    soft = image
    for _ in range(1):
        soft = (soft + np.roll(soft, 1, 0) + np.roll(soft, 1, 1) + np.roll(soft, -1, 0) + np.roll(soft, -1, 1)) / 5.0
    return np.clip(0.55 * image + 0.8 * soft, 0.0, 1.0)[..., None]


def female_normal(header, array):
    path = header["textures"].get("skin_normal")
    if not path:
        return None
    image = bpy.data.images.load(path, check_existing=False)
    w, h = image.size
    pixels = np.flipud(np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4))
    bpy.data.images.remove(image)
    body = header["body"]
    morph = body["morphs"].get("breast_size@female")
    count = body["vertex_count"]
    amount = np.zeros(count, dtype=np.float32)
    if morph:
        moved = array(morph["indices"], np.int32)
        delta = array(morph["positions"], width=3)
        amount[moved] = np.linalg.norm(delta, axis=1)
    female = body["morphs"].get("sex_female")
    if female:
        moved = array(female["indices"], np.int32)
        delta = array(female["positions"], width=3)
        chest = array(body["positions"], width=3)[moved]
        breast = (chest[:, 1] > 0.25) & (chest[:, 1] < 0.5) & (chest[:, 2] > 0.02)
        amount[moved[breast]] = np.maximum(amount[moved[breast]], np.linalg.norm(delta[breast], axis=1))
    weight = smoothstep(0.004, 0.02, amount)
    mask = rasterize(array(body["uvs"], width=2), array(body["indices"], np.int32, 3), weight[:, None].astype(np.float32), 512)
    mask = blur(mask, 6)
    # Upsample the mask to the normal map.
    ys = (np.arange(h) * 512 // h)
    xs = (np.arange(w) * 512 // w)
    big = mask[ys][:, xs, 0][..., None]
    flat = np.array([0.5, 0.5, 1.0, 1.0], dtype=np.float32)
    return pixels * (1.0 - big) + flat * big


def main():
    header, array = load()
    save(head_masks(header, array), os.path.join(OUT, "masks.png"))
    save(pubic_masks(header, array), os.path.join(OUT, "body_masks.png"))
    save(np.concatenate([stubble(), curls()[..., None]], axis=2), os.path.join(OUT, "stubble.png"))
    normal = female_normal(header, array)
    if normal is not None:
        save(normal, os.path.join(OUT, "skin_normal_female.png"))
    print("MASKS written to", OUT)


main()
