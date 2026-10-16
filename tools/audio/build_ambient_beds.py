#!/usr/bin/env python3
"""Camas de ambiente (bucles largos de audio/effects/) a partir de grabaciones CC0 de Freesound.

Descarga la previsualización de calidad alta (OGG) de cada fuente con la misma caché que los sonidos
del combate (build_combat_sounds.source), se queda con el tramo de nivel más parejo, lo cierra en
bucle con un fundido cruzado de potencia constante (el final entra en el principio sin salto) e
iguala su volumen al de otra cama de referencia. Escribe audio/effects/<cama>.wav (estéreo, 16
bits, a la frecuencia de la fuente), audio/effects/credits.json y docs/ambient_audio_credits.md.

  build/fauna_tools/bin/python tools/audio/build_ambient_beds.py [--only=lake_storm,...]

Las camas las mezclan WaterAmbience y WeatherAmbience; su SoundEvent (data/audio/events/) pone el
volumen de mezcla, así que aquí solo se igualan entre sí.
"""
import argparse, json, os
import numpy as np
import soundfile as sf

from build_combat_sounds import CACHE, ROOT, source

OUT = os.path.join(ROOT, "audio", "effects")

# Por cama: la fuente, cuánto dura el bucle (s; None = la grabación entera menos el fundido), el
# fundido del cierre (s), la cama cuyo volumen copia y lo que se aparta de él (dB).
BEDS = {
    # Orilla de un lago pequeño con olas empujadas por el viento (sur de Illinois): olas picadas a
    # ritmo, sin el viento en el micro ni pájaros. El viento lo ponen las camas de WeatherAmbience.
    "lake_storm": {"source": 169883, "dur": 30.0, "fade": 2.0, "match": "lake_calm", "gain_db": 0.0,
        "label": "Lago con temporal"},
    # Lluvia constante en el tejado de una cabaña, grabada desde dentro: apagada en agudos y con los
    # golpes graves del techo. Ya está pensada como bucle; se cierra igual para que no chasquee.
    "rain_indoor": {"source": 232731, "dur": None, "fade": 1.0, "match": "rain_light", "gain_db": 0.0,
        "label": "Lluvia bajo techo"},
}


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(np.square(x))) + 1e-12)


def steadiest(x, rate, dur, fade):
    """Inicio del tramo de [dur + fade] s cuyo nivel (por medio segundo) varía menos, sin los 3 s de
    cada borde (las grabaciones suelen arrancar y acabar con un fundido)."""
    step = int(rate * 0.5)
    mono = x.mean(axis=1)
    levels = np.array([rms_db(mono[i:i + step]) for i in range(0, len(mono) - step, step)])
    span = int(np.ceil((dur + fade) / 0.5))
    margin = 6
    best, best_cost = margin, None
    for k in range(margin, len(levels) - span - margin):
        window = levels[k:k + span]
        # Parejo, y que el principio y el final suenen igual (el cierre se oye menos).
        cost = window.std() + 0.5 * abs(window[:4].mean() - window[-4:].mean())
        if best_cost is None or cost < best_cost:
            best, best_cost = k, cost
    return best * step


def close_loop(seg, rate, fade):
    """El último [fade] s entra sobre el primero con un fundido de potencia constante: el bucle
    resultante (len(seg) - fade) vuelve a empezar justo donde lo dejaría la grabación."""
    n = int(rate * fade)
    loop = seg[:-n].copy()
    t = np.linspace(0.0, np.pi * 0.5, n)[:, None]
    loop[:n] = seg[:n] * np.sin(t) + seg[-n:] * np.cos(t)
    return loop


def build(name, spec):
    meta, _, _ = source(spec["source"])
    x, rate = sf.read(os.path.join(CACHE, "%d.ogg" % spec["source"]), always_2d=True)
    if x.shape[1] == 1:
        x = np.repeat(x, 2, axis=1)
    fade = spec["fade"]
    if spec["dur"] is None:
        seg = x
    else:
        start = steadiest(x, rate, spec["dur"], fade)
        seg = x[start:start + int(rate * (spec["dur"] + fade))]
    loop = close_loop(seg, rate, fade)
    ref, _ = sf.read(os.path.join(OUT, "%s.wav" % spec["match"]), always_2d=True)
    gain = rms_db(ref) - rms_db(loop) + spec["gain_db"]
    loop = loop * 10 ** (gain / 20)
    peak = np.abs(loop).max()
    if peak > 0.89:
        # Sin pasar de -1 dBFS.
        loop *= 0.89 / peak
    path = os.path.join(OUT, "%s.wav" % name)
    sf.write(path, loop.astype(np.float32), rate, subtype="PCM_16")
    print("%-12s %5.1f s  %d Hz  %+.1f dB  pico %.2f" % (name, len(loop) / rate, rate, gain, np.abs(loop).max()))
    return {"file": os.path.relpath(path, ROOT), "source": meta["id"], "dur": round(len(loop) / rate, 2)}, meta


def write_credits_doc(credits):
    lines = ["# Créditos del audio de ambiente", "",
        "Las camas de `audio/effects/` que lista esta página salen de grabaciones de",
        "[Freesound](https://freesound.org) con licencia [CC0](https://creativecommons.org/publicdomain/zero/1.0/):",
        "no exigen atribución, pero se listan para saber de dónde viene cada una. Se usa la",
        "previsualización de calidad alta (OGG), cerrada en bucle e igualada en volumen por",
        "`tools/audio/build_ambient_beds.py`, que deja el detalle en `audio/effects/credits.json` y escribe",
        "esta página. Descargadas en octubre de 2026.", "", "| Cama | Fuente |", "| --- | --- |"]
    for name, spec in BEDS.items():
        bed = credits["beds"].get(name)
        if not bed:
            continue
        src = credits["sources"][str(bed["source"])]
        lines.append("| %s (`%s`) | [%s](%s) (%s) |" % (spec["label"], name, src["title"].replace("|", "/"),
            src["url"], src["author"]))
    open(os.path.join(ROOT, "docs", "ambient_audio_credits.md"), "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    credits_path = os.path.join(OUT, "credits.json")
    credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {"beds": {}, "sources": {}}
    for name, spec in BEDS.items():
        if only and name not in only:
            continue
        bed, meta = build(name, spec)
        credits["beds"][name] = bed
        credits["sources"][str(meta["id"])] = {k: meta[k] for k in ("title", "author", "license", "url")}
    json.dump(credits, open(credits_path, "w"), indent=1, ensure_ascii=False)
    write_credits_doc(credits)
