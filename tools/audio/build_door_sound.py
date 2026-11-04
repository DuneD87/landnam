#!/usr/bin/env python3
"""Sonidos de abrir y cerrar las puertas y trampillas (door_open, door_close).

Salen de una sola grabación de Pixabay (Universfield) con las dos cosas seguidas y un silencio en
medio: audio/effects/door_open_close.mp3. La parte en el punto más callado entre las dos, quita el
silencio de delante de cada una (menos LEAD), las pasa a mono para que suenen en su sitio y les pone
un fundido corto en los cortes para que no chasqueen. Deja audio/effects/door_open.wav y
door_close.wav, su entrada en audio/effects/credits.json y docs/door_audio_credits.md.

  build/fauna_tools/bin/python tools/audio/build_door_sound.py

El volumen de mezcla lo pone su SoundEvent (data/audio/events/door_open.tres, door_close.tres).
"""
import json, os
import numpy as np
import soundfile as sf

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "audio", "effects")
SOURCE_FILE = os.path.join(OUT, "door_open_close.mp3")
NAME = "door"
SOURCE_ID = "pixabay-universfield-door"
SOURCE = {
    "title": "door_open_close.mp3",
    "author": "Universfield",
    "license": "https://pixabay.com/service/license-summary/",
    "url": "https://pixabay.com/users/universfield-28281460/",
}
## Por encima de esto (dB) empieza a sonar; el corte se busca a partir de SPLIT_FROM s.
ONSET_DB = -50.0
END_DB = -60.0
SPLIT_FROM = 1.2
## Lo que se deja delante del arranque y detrás de lo último que suena, y los fundidos (s).
LEAD = 0.01
TAIL = 0.05
FADE_IN = 0.003
FADE_OUT = 0.02
## Ventana de la envolvente (s).
STEP = 0.005


def envelope(x, rate):
    step = int(rate * STEP)
    peaks = np.array([np.abs(x[i:i + step]).max() for i in range(0, len(x), step)])
    return 20 * np.log10(np.maximum(peaks, 1e-6)), step


def cut(x, rate, start, end):
    clip = x[max(0, start):min(len(x), end)].copy()
    fade_in = int(rate * FADE_IN)
    fade_out = int(rate * FADE_OUT)
    clip[:fade_in] *= np.linspace(0, 1, fade_in)
    clip[-fade_out:] *= np.linspace(1, 0, fade_out)
    return clip


def build():
    x, rate = sf.read(SOURCE_FILE)
    mono = x.mean(axis=1) if x.ndim > 1 else x
    db, step = envelope(mono, rate)
    first = int(SPLIT_FROM * rate / step)
    open_on = int(np.argmax(db > ONSET_DB))
    close_on = first + int(np.argmax(db[first:] > ONSET_DB))
    split = first + int(np.argmin(db[first:close_on]))
    close_end = len(db) - 1 - int(np.argmax(db[::-1] > END_DB))
    lead = int(rate * LEAD)
    clips = {
        "open": cut(mono, rate, open_on * step - lead, split * step),
        "close": cut(mono, rate, close_on * step - lead, (close_end + 1) * step + int(rate * TAIL)),
    }
    files = []
    for kind, clip in clips.items():
        path = os.path.join(OUT, "%s_%s.wav" % (NAME, kind))
        sf.write(path, clip.astype(np.float32), rate, subtype="PCM_16")
        files.append({"file": os.path.relpath(path, ROOT), "source": SOURCE_ID, "dur": round(len(clip) / rate, 2)})
    print("abrir %.2f-%.2f s · cerrar %.2f-%.2f s" % (open_on * step / rate, split * step / rate,
        close_on * step / rate, (close_end + 1) * step / rate))
    return files


def write_credits_doc(credits):
    lines = ["# Créditos del sonido de las puertas", "",
        "`audio/effects/door_open.wav` y `door_close.wav` salen de una grabación de",
        "[Pixabay](https://pixabay.com) con su [licencia](https://pixabay.com/service/license-summary/), que",
        "deja usarla sin atribución; se lista para saber de dónde viene. Tiene el abrir y el cerrar seguidos:",
        "`tools/audio/build_door_sound.py` la parte por el silencio del medio, la pasa a mono, deja el",
        "detalle en `audio/effects/credits.json` y escribe esta página. Descargada en noviembre de 2026.",
        "", "| Evento | Fuente |", "| --- | --- |"]
    src = credits["sources"][SOURCE_ID]
    ref = "%s (%s, [su página](%s))" % (src["title"], src["author"], src["url"])
    lines.append("| Abrir y cerrar una puerta o una trampilla (`door_open`, `door_close`) | %s |" % ref)
    open(os.path.join(ROOT, "docs", "door_audio_credits.md"), "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    credits_path = os.path.join(OUT, "credits.json")
    credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {"sources": {}}
    credits.setdefault("clips", {})[NAME] = build()
    credits["sources"][SOURCE_ID] = SOURCE
    json.dump(credits, open(credits_path, "w"), indent=1, ensure_ascii=False)
    write_credits_doc(credits)
