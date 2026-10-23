#!/usr/bin/env python3
"""Sonido de recoger (item_pickup) a partir de grabaciones CC0 de Freesound.

Lo mismo para todo lo que se recoge: ramas, piedras, plantas, leña, lo soltado. Tiene que oírse
sin llamar la atención: un toque blando de cuero, como guardar algo en el zurrón. Descarga con la
caché de los sonidos del combate (build_combat_sounds.source), trocea cada grabación en sus tomas,
le quita los graves del micro y los agudos, redondea el golpe del arranque (un compresor rápido) y
deja audio/effects/pickup/pickup_NN.ogg en mono, con las variantes igualadas en volumen. Escribe
su entrada en audio/effects/credits.json y docs/pickup_audio_credits.md.

  build/fauna_tools/bin/python tools/audio/build_pickup_sound.py

El volumen de mezcla lo pone su SoundEvent (data/audio/events/item_pickup.tres).
"""
import json, os
import numpy as np
import soundfile as sf

from build_combat_sounds import ROOT, bandpass, cut_segments, envelope, fade, level, source, HOP

OUT = os.path.join(ROOT, "audio", "effects", "pickup")
NAME = "pickup"
# Una chaqueta de cuero agarrada con suavidad, cuatro tomas (Kinoton, Foley, Grab Leather, Soft).
SOURCES = [(719963, 4)]
DUR = (0.1, 0.6)
BAND = (150, 5500)
## El compresor: por encima de THRESHOLD_DB bajo el pico, divide por RATIO; ataque y suelta (s).
THRESHOLD_DB = 14.0
RATIO = 3.0
ATTACK = 0.002
RELEASE = 0.06
## Lo que se deja delante del arranque (s): suena con la tecla.
LEAD = 0.008


def soften(x, rate):
    """Compresor de pico: el toque del arranque baja y la cola de roce queda igual."""
    threshold = np.abs(x).max() * 10 ** (-THRESHOLD_DB / 20)
    a = np.exp(-1.0 / (ATTACK * rate))
    r = np.exp(-1.0 / (RELEASE * rate))
    level_now = 0.0
    out = np.empty_like(x)
    for i, sample in enumerate(np.abs(x)):
        k = a if sample > level_now else r
        level_now = k * level_now + (1 - k) * sample
        gain = 1.0 if level_now <= threshold else (threshold / level_now) ** (1 - 1 / RATIO)
        out[i] = x[i] * gain
    return out


def trim_lead(x, rate):
    """Sin el silencio de delante (cut_segments deja 60 ms), menos LEAD."""
    env = envelope(x, rate)
    start = max(0, int((np.argmax(env > env.max() - 30.0) * HOP - LEAD) * rate))
    return x[start:]


def build():
    clips, rates, used = [], [], []
    for sid, n in SOURCES:
        meta, x, rate = source(sid)
        x = bandpass(x, rate, *BAND)
        for clip in cut_segments(x, rate, n, DUR, "start"):
            clips.append(fade(soften(trim_lead(clip, rate), rate), rate, 0.004, 0.08))
            rates.append(rate)
            used.append(meta)
    clips = level(clips)
    os.makedirs(OUT, exist_ok=True)
    keep = {"%s_%02d.ogg" % (NAME, i + 1) for i in range(len(clips))}
    for old in os.listdir(OUT):
        if old.removesuffix(".import") not in keep:
            os.remove(os.path.join(OUT, old))
    files = []
    for i, (c, rate, meta) in enumerate(zip(clips, rates, used)):
        path = os.path.join(OUT, "%s_%02d.ogg" % (NAME, i + 1))
        sf.write(path, c.astype(np.float32), rate, format="OGG", subtype="VORBIS")
        files.append({"file": os.path.relpath(path, ROOT), "source": meta["id"], "dur": round(len(c) / rate, 2)})
    print("%-12s %2d clips  %s" % (NAME, len(clips), " ".join("%.2f" % f["dur"] for f in files)))
    return files, {m["id"]: m for m in used}


def write_credits_doc(credits):
    lines = ["# Créditos del sonido de recoger", "",
        "Los clips de `audio/effects/pickup/` salen de grabaciones de [Freesound](https://freesound.org) con",
        "licencia [CC0](https://creativecommons.org/publicdomain/zero/1.0/): no exigen atribución, pero se",
        "listan para saber de dónde viene cada uno. Se usa la previsualización de calidad alta (OGG),",
        "troceada en tomas, suavizada e igualada en volumen por `tools/audio/build_pickup_sound.py`, que",
        "deja el detalle en `audio/effects/credits.json` y escribe esta página. Descargados en octubre de",
        "2026.", "", "| Evento | Fuentes |", "| --- | --- |"]
    files = credits["clips"].get(NAME, [])
    refs = []
    for sid in dict.fromkeys(f["source"] for f in files):
        src = credits["sources"][str(sid)]
        refs.append("[%s](%s) (%s)" % (src["title"].replace("|", "/"), src["url"], src["author"]))
    lines.append("| Recoger (`item_pickup`) | %s |" % ", ".join(refs))
    open(os.path.join(ROOT, "docs", "pickup_audio_credits.md"), "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    credits_path = os.path.join(ROOT, "audio", "effects", "credits.json")
    credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {"sources": {}}
    files, sources = build()
    credits.setdefault("clips", {})[NAME] = files
    for sid, meta in sources.items():
        credits["sources"][str(sid)] = {k: meta[k] for k in ("title", "author", "license", "url")}
    json.dump(credits, open(credits_path, "w"), indent=1, ensure_ascii=False)
    write_credits_doc(credits)
