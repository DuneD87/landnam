#!/usr/bin/env python3
"""Sonidos del combate a partir de grabaciones CC0 de Freesound.

Descarga la previsualización de calidad alta (OGG) de cada fuente, la recorta y la deja en
audio/combat/<evento>/ como OGG mono, con las variantes de cada evento igualadas en volumen.
Escribe también audio/combat/credits.json (de dónde sale cada clip), docs/audio_credits.md y, con
--sheets, un espectrograma por evento en build/audio/ para revisar los cortes a ojo.

  build/fauna_tools/bin/python tools/audio/build_combat_sounds.py [--only=bear_roar,...] [--sheets]

Modos de recorte:
  whole     el sonido entero, sin el silencio de los bordes (y como mucho max_dur)
  impact    desde el transitorio más fuerte (el golpe), como mucho max_dur: quita el silbido o el
            ruido que llevan delante algunas grabaciones de golpes
  segments  trocea una grabación larga en sus vocalizaciones (envolvente sobre el ruido de fondo)
            y se queda con las n más fuertes cuya duración cae en dur; las más largas se
            recortan a su tramo más fuerte, o a su arranque con "take": "start" (quejidos)

Los cortes se revisan con las láminas (--sheets) y con la planitud espectral: una vocalización
tiene bandas armónicas graves; el ruido de movimiento o de fondo, textura gris uniforme.
"""
import argparse, html, json, os, re, subprocess, sys
import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, "build", "audio", "freesound")
OUT = os.path.join(ROOT, "audio", "combat")
SHEETS = os.path.join(ROOT, "build", "audio")
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

# Por evento: fuentes (id de Freesound, o (id, n) en segments), modo y límites de duración (s).
EVENTS = {
    # Silbidos de un palo de bambú (qubodup, Free Whoosh Sound Pack), los ligeros y los lentos
    # (los pesados suenan además más graves en su SoundEvent). Golpes cortados antes del siguiente.
    "swing_light": {"mode": "whole", "max_dur": 0.6, "sources": [60030, 60026, 59988, 60029, 60023, 59992]},
    "swing_heavy": {"mode": "whole", "max_dur": 0.8, "sources": [60027, 475135, 514162, 60024, 60026]},
    "hit_slash": {"mode": "impact", "max_dur": 0.5, "sources": [504615, 323526, 395370, 179222]},
    "hit_pierce": {"mode": "impact", "max_dur": 0.4, "sources": [411743, 395373, 205938, 708223]},
    "hit_blunt": {"mode": "impact", "max_dur": 0.6, "sources": [399183, 434147, 733904, 276600]},
    "hit_world": {"mode": "impact", "max_dur": 0.7, "sources": [733887, 815415]},
    "bow_release": {"mode": "whole", "max_dur": 0.45, "sources": [263675, 394179, 384918, 536068]},
    "throw": {"mode": "whole", "max_dur": 0.6, "sources": [346373, 523230, 394873]},
    # Una sola voz (MrFossy, Voice – Male Grunts and Screams).
    "player_hurt": {"mode": "whole", "max_dur": 0.8, "sources": [547203, 547202, 547201, 547200, 547207, 547206,
        547205, 547204, 547209, 547208, 547194, 547195]},
    "player_death": {"mode": "whole", "max_dur": 3.0, "sources": [547185, 547186, 547187, 547188, 547189, 547190]},
    # Y una sola voz de mujer (Reitanna), sin palabras.
    "player_hurt_female": {"mode": "whole", "max_dur": 0.8, "sources": [242623, 242622, 344004, 252231, 252235,
        253776, 252232, 344045, 344013]},
    "player_death_female": {"mode": "whole", "max_dur": 3.0, "sources": [241522, 241573, 343954, 343999, 241545]},
    # Osos de verdad: grizzlis de Yellowstone (NPS), un oso negro en Whistler (celldroid) y la
    # librería antigua de craigsmith.
    "bear_growl": {"mode": "segments", "dur": (0.6, 3.0), "sources": [(763026, 3), (519599, 4), (519596, 1)]},
    "bear_roar": {"mode": "segments", "dur": (0.8, 3.5), "sources": [(479825, 3)]},
    "bear_huff": {"mode": "whole", "max_dur": 0.8, "sources": [519598, 519597]},
    "bear_hurt": {"mode": "segments", "dur": (0.35, 0.6), "take": "start", "sources": [(763026, 2), (519599, 3)]},
    "bear_death": {"mode": "segments", "dur": (1.5, 4.0), "sources": [(519599, 2), (479825, 1)]},
    # Leones en zoológicos (felix.blume, Filmscore, Bidone, polymorpheva, roman_cgr).
    "lion_roar": {"mode": "segments", "dur": (1.0, 4.0), "sources": [(405211, 3), (869002, 2), (869003, 2), (69572, 2)]},
    "lion_growl": {"mode": "segments", "dur": (0.5, 2.5), "sources": [(223978, 4), (270383, 2)]},
    "lion_hurt": {"mode": "segments", "dur": (0.35, 0.6), "take": "start", "sources": [(223978, 3), (270383, 2)]},
    "lion_death": {"mode": "segments", "dur": (1.5, 4.5), "sources": [(223978, 1), (405211, 1), (869003, 1)]},
}

# Cómo se llama cada evento en docs/audio_credits.md.
NAMES = {
    "swing_light": "Silbido de arma ligera", "swing_heavy": "Silbido de arma pesada (y zarpazo de fiera, `claw_swipe`)",
    "hit_slash": "Tajo en carne", "hit_pierce": "Estocada o flecha en carne", "hit_blunt": "Golpe contundente en carne",
    "hit_world": "Arma contra el suelo", "bow_release": "Suelta del arco", "throw": "Lanzamiento",
    "player_hurt": "Quejidos del jugador", "player_death": "Muerte del jugador",
    "player_hurt_female": "Quejidos de la jugadora", "player_death_female": "Muerte de la jugadora",
    "bear_growl": "Gruñido de oso", "bear_roar": "Rugido de oso", "bear_huff": "Resoplido de oso",
    "bear_hurt": "Oso herido", "bear_death": "Muerte del oso", "lion_roar": "Rugido de león",
    "lion_growl": "Gruñido de león", "lion_hurt": "León herido", "lion_death": "Muerte del león",
}

FRAME = 0.02
HOP = 0.01


def fetch(url):
    return subprocess.run(["wget", "-q", "-U", UA, "-T", "30", "-O", "-", url], capture_output=True).stdout


def source(sid):
    """Descarga (una vez) la previsualización HQ y los datos de la página del sonido."""
    os.makedirs(CACHE, exist_ok=True)
    meta_path = os.path.join(CACHE, "%d.json" % sid)
    audio_path = os.path.join(CACHE, "%d.ogg" % sid)
    if not os.path.exists(meta_path):
        page = fetch("https://freesound.org/s/%d/" % sid).decode("utf-8", "replace")
        title = re.search(r'data-title="([^"]*)"', page)
        user = re.search(r'<title>Freesound - .* by ([^<]*)</title>', page)
        lic = re.search(r'href="(https?://creativecommons.org/[^"]*)"', page)
        mp3 = re.search(r'data-mp3="([^"]*)"', page)
        if not mp3:
            sys.exit("No encuentro la previsualización de %d" % sid)
        meta = {"id": sid, "title": html.unescape(title.group(1)) if title else "?",
            "author": html.unescape(user.group(1)) if user else "?",
            "license": lic.group(1) if lic else "?", "url": "https://freesound.org/s/%d/" % sid,
            "preview": mp3.group(1).replace("-lq.mp3", "-hq.ogg")}
        if "publicdomain/zero" not in meta["license"]:
            sys.exit("%d no es CC0: %s" % (sid, meta["license"]))
        json.dump(meta, open(meta_path, "w"), indent=1)
    meta = json.load(open(meta_path))
    if meta.get("author", "?") in ("", "?"):
        page = fetch(meta["url"]).decode("utf-8", "replace")
        user = re.search(r'<title>Freesound - .* by ([^<]*)</title>', page)
        meta["author"] = html.unescape(user.group(1)).strip() if user else "?"
        json.dump(meta, open(meta_path, "w"), indent=1)
    if not os.path.exists(audio_path):
        data = fetch(meta["preview"])
        if len(data) < 1000:
            sys.exit("Descarga vacía de %d" % sid)
        open(audio_path, "wb").write(data)
    audio, rate = sf.read(audio_path, always_2d=True)
    return meta, audio.mean(axis=1), rate


def envelope(x, rate):
    frame, hop = int(FRAME * rate), int(HOP * rate)
    n = max(1, 1 + (len(x) - frame) // hop)
    idx = np.arange(frame)[None, :] + hop * np.arange(n)[:, None]
    idx = np.minimum(idx, len(x) - 1)
    rms = np.sqrt(np.mean(x[idx] ** 2, axis=1))
    return 20.0 * np.log10(rms + 1e-9)


def fade(x, rate, fade_in=0.004, fade_out=0.04):
    x = x.copy()
    a, b = min(len(x), int(fade_in * rate)), min(len(x), int(fade_out * rate))
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b) ** 2
    return x


def cut_whole(x, rate, max_dur):
    env = envelope(x, rate)
    peak = env.max()
    on = np.nonzero(env > peak - 35.0)[0]
    start = max(0, int((on[0] * HOP - 0.01) * rate))
    end = min(len(x), int((on[-1] * HOP + FRAME + 0.06) * rate))
    end = min(end, start + int(max_dur * rate))
    return [fade(x[start:end], rate)]


def cut_impact(x, rate, max_dur):
    env = envelope(x, rate)
    peak = env.max()
    rise = np.diff(env, prepend=env[0])
    rise[env < peak - 12.0] = -np.inf
    onset = int(np.argmax(rise))
    start = max(0, int((onset * HOP - 0.015) * rate))
    tail = np.nonzero(env[onset:] > peak - 40.0)[0]
    end = int(((onset + (tail[-1] if len(tail) else 0)) * HOP + FRAME + 0.05) * rate)
    end = min(len(x), end, start + int(max_dur * rate))
    return [fade(x[start:end], rate, 0.002, 0.05)]


def cut_segments(x, rate, n, dur, take="loudest"):
    env = envelope(x, rate)
    floor = np.percentile(env, 20)
    threshold = max(floor + 12.0, env.max() - 28.0)
    active = env > threshold
    groups, start = [], None
    for i, a in enumerate(np.append(active, False)):
        if a and start is None:
            start = i
        elif not a and start is not None:
            groups.append([start, i])
            start = None
    merged = []
    for g in groups:
        if merged and (g[0] - merged[-1][1]) * HOP < 0.2:
            merged[-1][1] = g[1]
        else:
            merged.append(g)
    picks = []
    for a, b in merged:
        length = (b - a) * HOP
        if length < dur[0]:
            continue
        if length > dur[1]:
            # Lo más fuerte de la vocalización larga (o su arranque), a la duración máxima.
            width = int(dur[1] / HOP)
            if take == "loudest":
                sums = np.convolve(env[a:b], np.ones(width), "valid")
                a += int(np.argmax(sums))
            b = a + width
        picks.append((float(np.mean(env[a:b])), a, b))
    picks.sort(reverse=True)
    clips = []
    for _, a, b in picks[:n]:
        s = max(0, int((a * HOP - 0.06) * rate))
        tail = 0.08 if take == "start" else 0.2
        e = min(len(x), int((b * HOP + FRAME + tail) * rate))
        clips.append(fade(x[s:e], rate, 0.03, 0.1 if take == "start" else 0.15))
    return clips


def level(clips):
    """Iguala las variantes de un evento: misma energía (RMS de la parte fuerte) y pico ≤ -1 dBFS."""
    def loud_rms(c):
        env = np.sort(np.abs(c))
        top = c[np.abs(c) >= np.percentile(np.abs(c), 50)]
        return np.sqrt(np.mean(top ** 2)) + 1e-9
    target = np.median([loud_rms(c) for c in clips])
    out = []
    for c in clips:
        c = c * (target / loud_rms(c))
        out.append(c)
    peak = max(np.max(np.abs(c)) for c in out)
    gain = 10 ** (-1.0 / 20.0) / peak
    return [c * gain for c in out]


def sheet(name, clips, rates):
    from PIL import Image, ImageDraw
    tiles = []
    for c, rate in zip(clips, rates):
        n = 1024
        hop = 256
        frames = max(1, 1 + (len(c) - n) // hop)
        win = np.hanning(n)
        spec = np.array([np.abs(np.fft.rfft(np.pad(c[i * hop:i * hop + n], (0, max(0, n - len(c[i * hop:i * hop + n])))) * win))
            for i in range(frames)]).T
        spec = 20 * np.log10(spec + 1e-6)
        spec = np.clip((spec - spec.max() + 70) / 70, 0, 1)[:256][::-1]
        img = Image.fromarray((spec * 255).astype(np.uint8)).resize((300, 160))
        d = ImageDraw.Draw(img)
        d.text((4, 4), "%.2fs" % (len(c) / rate), fill=255)
        tiles.append(img)
    sheet = Image.new("L", (300 * min(4, len(tiles)), 160 * ((len(tiles) + 3) // 4)))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 4) * 300, (i // 4) * 160))
    os.makedirs(SHEETS, exist_ok=True)
    sheet.save(os.path.join(SHEETS, "%s.png" % name))


def build(name, spec, sheets):
    clips, rates, used = [], [], []
    for entry in spec["sources"]:
        sid, n = entry if isinstance(entry, tuple) else (entry, 1)
        meta, x, rate = source(sid)
        if spec["mode"] == "whole":
            got = cut_whole(x, rate, spec["max_dur"])
        elif spec["mode"] == "impact":
            got = cut_impact(x, rate, spec["max_dur"])
        else:
            got = cut_segments(x, rate, n, spec["dur"], spec.get("take", "loudest"))
        if not got:
            print("  %s: nada en %d" % (name, sid))
        clips += got
        rates += [rate] * len(got)
        used += [meta] * len(got)
    clips = level(clips)
    folder = os.path.join(OUT, name)
    os.makedirs(folder, exist_ok=True)
    keep = {"%s_%02d.ogg" % (name, i + 1) for i in range(len(clips))}
    for old in os.listdir(folder):
        # Las variantes que sobran, con su .import; las demás se reescriben (su .import y su uid
        # se quedan).
        if old.removesuffix(".import") not in keep:
            os.remove(os.path.join(folder, old))
    files = []
    for i, (c, rate, meta) in enumerate(zip(clips, rates, used)):
        path = os.path.join(folder, "%s_%02d.ogg" % (name, i + 1))
        sf.write(path, c.astype(np.float32), rate, format="OGG", subtype="VORBIS")
        files.append({"file": os.path.relpath(path, ROOT), "source": meta["id"], "dur": round(len(c) / rate, 2)})
    print("%-12s %2d clips  %s" % (name, len(clips), " ".join("%.2f" % f["dur"] for f in files)))
    if sheets:
        sheet(name, clips, rates)
    return files, {m["id"]: m for m in used}


def write_credits_doc(credits):
    lines = ["# Créditos del audio de combate", "",
        "Los clips de `audio/combat/` salen de grabaciones de [Freesound](https://freesound.org) con licencia",
        "[CC0](https://creativecommons.org/publicdomain/zero/1.0/): no exigen atribución, pero se listan para",
        "saber de dónde viene cada uno. Se usa la previsualización de calidad alta (OGG) de cada sonido,",
        "recortada, pasada a mono e igualada en volumen por `tools/audio/build_combat_sounds.py`, que deja",
        "el detalle clip a clip en `audio/combat/credits.json` y escribe esta página. Descargados en octubre",
        "de 2026.", "", "| Evento | Fuentes |", "| --- | --- |"]
    for name in EVENTS:
        files = credits["events"].get(name)
        if not files:
            continue
        refs = []
        for sid in dict.fromkeys(f["source"] for f in files):
            src = credits["sources"][str(sid)]
            refs.append("[%s](%s) (%s)" % (src["title"].replace("|", "/"), src["url"], src["author"]))
        lines.append("| %s (`%s`) | %s |" % (NAMES.get(name, name), name, ", ".join(refs)))
    lines += ["", "Los osos son de verdad: grizzlis de Yellowstone (del Servicio de Parques Nacionales de EE. UU.,",
        "subidos por Nivatius), un oso negro en Whistler (celldroid) y una librería antigua de efectos",
        "(craigsmith). Los leones están grabados en zoológicos y en un santuario de fauna. Cada voz del",
        "jugador es de una sola persona: MrFossy la de hombre y Reitanna la de mujer, sin palabras."]
    open(os.path.join(ROOT, "docs", "audio_credits.md"), "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--sheets", action="store_true")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    credits_path = os.path.join(OUT, "credits.json")
    credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {"events": {}, "sources": {}}
    for name, spec in EVENTS.items():
        if only and name not in only:
            continue
        files, sources = build(name, spec, a.sheets)
        credits["events"][name] = files
        for sid, meta in sources.items():
            credits["sources"][str(sid)] = {k: meta[k] for k in ("title", "author", "license", "url")}
    json.dump(credits, open(credits_path, "w"), indent=1, ensure_ascii=False)
    write_credits_doc(credits)
