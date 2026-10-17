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
            recortan a su tramo más fuerte, o a su arranque con "take": "start" (quejidos).
            Cada trozo empieza en su ataque, y su parte fuerte llega en MAX_LEAD como mucho: el
            juego lo dispara con la acción, y lo que va delante se oiría como un retraso.
            Una fuente (id, "whole") es una sola llamada corta: entra entera, hasta dur[1]

"band": (lo, hi) en Hz filtra la grabación antes de cortarla: en las de campo, la detección ya no
confunde los grillos (agudos) o el viento (graves) con una llamada, y el clip sale sin ellos.

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
    # La guardia: madera (escudos, mangos), metal (espadas, cantos de hierro), la parada en seco y
    # la guardia que cede.
    "block_wood": {"mode": "impact", "max_dur": 0.45, "sources": [783059, 536736, 693581, 693582]},
    "block_metal": {"mode": "impact", "max_dur": 0.5, "sources": [326868, 326867, 326864, 326861, 326857]},
    "parry": {"mode": "impact", "max_dur": 0.9, "sources": [760636, 760635, 760634, 760633]},
    "guard_break": {"mode": "impact", "max_dur": 0.8, "sources": [529396, 693582]},
    # Despellejar: cortes de cuchillo en carne cruda, la piel que se arranca, chapoteos de vísceras y
    # huesos que se parten (carniceros, canales de caza y librerías de gore).
    "skin_cut": {"mode": "segments", "dur": (0.2, 1.2), "sources": [(360796, 3), (472501, 3), (593682, 3), (637641, 3)]},
    "skin_tear": {"mode": "segments", "dur": (0.4, 2.0), "sources": [(30931, 2), (234236, 3), (762900, 2), (814734, 1),
        (704771, 2), (530919, 2)]},
    "skin_squelch": {"mode": "segments", "dur": (0.2, 1.0), "sources": [(649982, 3), (734836, 2), (211605, 3)]},
    "bone_snap": {"mode": "impact", "max_dur": 0.7, "sources": [211606, 784768, 513315]},
    # Una sola voz (MrFossy, Voice – Male Grunts and Screams).
    "player_hurt": {"mode": "whole", "max_dur": 0.8, "sources": [547203, 547202, 547201, 547200, 547207, 547206,
        547205, 547204, 547209, 547208, 547194, 547195]},
    "player_death": {"mode": "whole", "max_dur": 3.0, "sources": [547185, 547186, 547187, 547188, 547189, 547190]},
    # Y una sola voz de mujer (Reitanna), sin palabras.
    "player_hurt_female": {"mode": "whole", "max_dur": 0.8, "sources": [242623, 242622, 344004, 252231, 252235,
        253776, 252232, 344045, 344013]},
    "player_death_female": {"mode": "whole", "max_dur": 3.0, "sources": [241522, 241573, 343954, 343999, 241545]},
    # Devorado vivo (Devouring): gritos largos de agonía (otras voces: las de arriba no los tienen),
    # el estertor ahogado del final y la fiera desgarrando, masticando y royendo.
    "player_agony": {"mode": "segments", "dur": (0.8, 3.0), "sources": [(325548, 4), (556976, 3), (173944, 3),
        (764370, 2)]},
    "player_agony_female": {"mode": "segments", "dur": (0.8, 3.0), "sources": [(671355, 4), (573096, 2), (845164, 1),
        (320740, 2)]},
    # El estertor, sin voz de hombre ni de mujer (la jugadora lo usa más agudo: build_combat_events).
    "player_gurgle": {"mode": "segments", "dur": (0.6, 2.5), "sources": [(826999, 2), (654044, 1), (476437, 2),
        (830016, 3)]},
    "devour_bite": {"mode": "segments", "dur": (0.35, 1.4), "sources": [(234237, 4), (260880, 3), (264280, 2)]},
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
    # Lobos: aullidos de lobos de verdad (uno salvaje en Wrangell-St. Elias, betchkal, y un coro de
    # cinco, ondrosik). Los gruñidos, gañidos y gemidos de cerca son de perros (DaniloSFX, qubodup,
    # unfa, jedg y craigsmith): un perro grande suena casi igual. El gruñido largo de lobo
    # (JoseAgudelo) y los coros del Harz y de Wolf Haven no se dejan trocear: son un continuo.
    "wolf_growl": {"mode": "segments", "dur": (0.6, 2.5), "sources": [(672736, 3), (122183, 2)]},
    "wolf_snarl": {"mode": "segments", "dur": (0.5, 2.0), "sources": [(672732, 4), (122183, 1)]},
    "wolf_hurt": {"mode": "segments", "dur": (0.15, 0.6), "take": "start", "sources": [(160478, 5)]},
    "wolf_death": {"mode": "segments", "dur": (0.8, 3.0), "sources": [(675407, 2), (505827, 1)]},
    "wolf_howl": {"mode": "segments", "dur": (2.0, 8.0), "sources": [(500646, 3), (143568, 1)]},
    # Ciervos (cierva, berrendo, ciervo y caribú): llamadas de corzos en el bosque (Sacha.Julien,
    # bruno.auzet) y de ciervos en un parque (msantoro11), sin los grillos de la noche; la muerte, las
    # más largas, que su SoundEvent baja de tono. Los ladridos de Spamanator, mattl83 y Katerios y los
    # bramidos de celo lejanos se quedan bajo el ruido; el reclamo de caza y el "cervatillo" (un
    # cordero alterado) no son animales.
    "deer_hurt": {"mode": "segments", "dur": (0.2, 0.9), "take": "start", "band": (250, 3500),
        "sources": [(724578, 3), (850406, 3), (351113, 2)]},
    "deer_death": {"mode": "segments", "dur": (0.6, 1.8), "band": (200, 4000), "sources": [(351113, 2), (724578, 2)]},
    # Cabras (cabra, cabra montés) grabadas de cerca; la muerte, una cabrita enferma (jsbarrett).
    "goat_hurt": {"mode": "segments", "dur": (0.3, 1.4), "take": "start",
        "sources": [(581240, 2), (677218, 1), (677220, 1), (677217, 1), (842964, 2)]},
    "goat_death": {"mode": "segments", "dur": (0.8, 2.5), "sources": [(200333, 2), (842964, 2)]},
    # Ovejas (el muflón) en granjas (zachrau, Sheyvan, Garuda1982).
    "sheep_hurt": {"mode": "segments", "dur": (0.3, 1.2), "take": "start",
        "sources": [(362283, 3), (471162, 3), (428103, 2)]},
    "sheep_death": {"mode": "segments", "dur": (0.8, 2.5), "sources": [(383144, 2), (471162, 1), (428103, 1)]},
    # Vacas y terneros; la angustia, una vaca con sus terneros separados por una carretera (lolamadeus).
    "cow_hurt": {"mode": "segments", "dur": (0.6, 2.0), "take": "start",
        "sources": [(163727, 2), (513565, 2), (546481, "whole"), (546479, "whole"), (59245, "whole")]},
    "cow_death": {"mode": "segments", "dur": (1.2, 3.5), "sources": [(194899, 3), (163727, 1)]},
    "calf_hurt": {"mode": "segments", "dur": (0.4, 1.5), "take": "start", "sources": [(860984, 1), (660694, 4)]},
    "calf_death": {"mode": "segments", "dur": (0.8, 2.5), "sources": [(660694, 2), (860984, 1)]},
    # Caballo (craigsmith, Kubuzz, 3bagbrew, foxen10) y burro (felix.blume, craigsmith). El de
    # Mercantour lleva los cencerros del rebaño encima y la imitación con la boca no vale.
    "horse_hurt": {"mode": "segments", "dur": (0.6, 2.0), "take": "start",
        "sources": [(437110, 1), (347036, 1), (59569, 2), (149024, 1)]},
    "horse_death": {"mode": "segments", "dur": (1.0, 3.0), "sources": [(437110, 1), (59569, 1), (347036, 1)]},
    "donkey_hurt": {"mode": "segments", "dur": (0.5, 1.5), "take": "start",
        "sources": [(705300, 2), (675411, 2)]},
    "donkey_death": {"mode": "segments", "dur": (1.5, 4.0), "sources": [(705300, "whole"), (675411, 1)]},
    # Bramidos de bisontes de Yellowstone (NPS, subido por Nivatius). No hay alces ni ñus libres: el
    # alce y el ñu, y el búfalo, usan estos con otro tono. Los resoplidos de cerca (TheKingOfGeeks360)
    # y la manada de Oklahoma (felix.blume) no se separan del masticar y el pisar.
    "bison_bellow": {"mode": "segments", "dur": (0.8, 3.0), "sources": [(519594, 3)]},
    # Cerdos grabados de cerca (MatiasEzcurra, a 20 cm; mrmunk; TheKingOfGeeks360; wwstudioswastaken):
    # un jabalí suena igual. Los jabalíes salvajes de felix.blume, bruno.auzet y Garuda1982 quedan
    # lejos, bajo el retumbo, la hierba y los pájaros, y el juguete no vale.
    "boar_grunt": {"mode": "segments", "dur": (0.3, 1.5), "sources": [(842313, 1), (147240, 4), (620080, 1)]},
    "boar_squeal": {"mode": "segments", "dur": (0.3, 1.0), "band": (250, 7000), "sources": [(344972, 2), (147240, 4)]},
    "boar_death": {"mode": "segments", "dur": (0.8, 2.5), "band": (200, 7000), "sources": [(344972, 1), (147240, 2)]},
    # Elefantes de verdad: uno en un zoo (ikbenraar), D.jones y la librería de craigsmith (con tigres
    # de fondo; se toman los trompetazos). El tubo de PVC y la boca no valen. El mamut, más grave.
    "elephant_trumpet": {"mode": "segments", "dur": (0.8, 3.5), "sources": [(819668, 2), (527845, 1), (437977, 3)]},
    # Rinocerontes blancos peleando en una charca de Umfolozi (geoffvt) y uno indio (Breviceps). La
    # trompa "de rinoceronte" no vale.
    "rhino_grunt": {"mode": "segments", "dur": (0.3, 1.5), "band": (70, 2500), "sources": [(792852, 5), (535810, 3)]},
    "rhino_squeal": {"mode": "segments", "dur": (0.2, 0.8), "take": "start", "band": (150, 5000), "sources": [(792852, 3), (535810, 2)]},
    # Caimanes: gruñidos de la librería de craigsmith y de D.jones; herido, una cría de cocodrilo
    # chillando en el Amazonas (felix.blume), que su SoundEvent baja de tono.
    "alligator_growl": {"mode": "segments", "dur": (0.8, 4.0), "sources": [(437933, 3), (675513, 1), (527844, 2)]},
    "alligator_hiss": {"mode": "segments", "dur": (0.5, 3.0), "sources": [(675513, 2)]},
    "alligator_hurt": {"mode": "segments", "dur": (0.2, 0.8), "take": "start", "sources": [(403373, 4)]},
    # Felinos (el lince; el puma, más grave: sisea y gruñe, no ruge): lince siberiano y serval
    # (TheKingOfGeeks360) y gatos grabados de cerca (aunrea, Zabuhailo, Kinoton). La imitación de
    # rickismyname y el "jaguar" con la boca no valen.
    "cat_hiss": {"mode": "segments", "dur": (0.3, 1.5),
        "sources": [(485952, "whole"), (146963, 1), (867552, "whole"), (656619, 2)]},
    "cat_growl": {"mode": "segments", "dur": (0.5, 2.5), "sources": [(844316, 1), (656619, 3)]},
    "cat_hurt": {"mode": "segments", "dur": (0.3, 1.0), "take": "start", "sources": [(656619, 4)]},
}

# Cómo se llama cada evento en docs/audio_credits.md.
NAMES = {
    "swing_light": "Silbido de arma ligera", "swing_heavy": "Silbido de arma pesada (y zarpazo de fiera, `claw_swipe`)",
    "hit_slash": "Tajo en carne", "hit_pierce": "Estocada o flecha en carne", "hit_blunt": "Golpe contundente en carne",
    "hit_world": "Arma contra el suelo", "bow_release": "Suelta del arco", "throw": "Lanzamiento",
    "block_wood": "Golpe parado con madera", "block_metal": "Golpe parado con metal",
    "parry": "Parada en seco", "guard_break": "Guardia rota",
    "skin_cut": "Cuchillo en carne al despellejar", "skin_tear": "Piel que se arranca",
    "skin_squelch": "Chapoteo de vísceras", "bone_snap": "Hueso que se parte",
    "player_hurt": "Quejidos del jugador", "player_death": "Muerte del jugador",
    "player_hurt_female": "Quejidos de la jugadora", "player_death_female": "Muerte de la jugadora",
    "player_agony": "Agonía del jugador devorado", "player_agony_female": "Agonía de la jugadora devorada",
    "player_gurgle": "Estertor del jugador o la jugadora devorados",
    "devour_bite": "Fiera comiendo carne (desgarrar, masticar, roer)",
    "bear_growl": "Gruñido de oso", "bear_roar": "Rugido de oso", "bear_huff": "Resoplido de oso",
    "bear_hurt": "Oso herido", "bear_death": "Muerte del oso", "lion_roar": "Rugido de león",
    "lion_growl": "Gruñido de león", "lion_hurt": "León herido", "lion_death": "Muerte del león",
    "wolf_growl": "Gruñido de lobo", "wolf_snarl": "Lobo enseñando los dientes", "wolf_hurt": "Lobo herido",
    "wolf_death": "Muerte del lobo", "wolf_howl": "Aullido de lobo",
    "deer_hurt": "Ciervo herido", "deer_death": "Muerte del ciervo", "goat_hurt": "Cabra herida",
    "goat_death": "Muerte de la cabra", "sheep_hurt": "Oveja herida (muflón)", "sheep_death": "Muerte de la oveja (muflón)",
    "cow_hurt": "Vaca herida", "cow_death": "Muerte de la vaca", "calf_hurt": "Ternero herido",
    "calf_death": "Muerte del ternero", "horse_hurt": "Caballo herido", "horse_death": "Muerte del caballo",
    "donkey_hurt": "Burro herido", "donkey_death": "Muerte del burro",
"bison_bellow": "Bramido de bisonte (alce, ñu, búfalo)",
    "boar_grunt": "Gruñido de jabalí", "boar_squeal": "Chillido de jabalí", "boar_death": "Muerte del jabalí",
    "elephant_trumpet": "Trompeta de elefante (y mamut)", "rhino_grunt": "Gruñido de rinoceronte",
    "rhino_squeal": "Rinoceronte herido", "alligator_growl": "Gruñido de caimán", "alligator_hiss": "Siseo de caimán",
    "alligator_hurt": "Caimán herido", "cat_hiss": "Siseo de felino (lince, puma)",
    "cat_growl": "Gruñido de felino (lince, puma)", "cat_hurt": "Felino herido (lince, puma)",
}

FRAME = 0.02
HOP = 0.01
## Lo más flojo (dB por debajo de su pico) con lo que puede arrancar una voz.
ATTACK_DB = 15.0
## La parte fuerte de una voz: a menos de esto (dB) de su pico.
LOUD_DB = 6.0
## Lo más tarde (s) que puede llegar la parte fuerte desde el arranque.
MAX_LEAD = 0.3
## Lo que se deja delante de la parte fuerte al recortar una que llega tarde (s).
LEAD_KEEP = 0.15


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


def bandpass(x, rate, lo, hi):
    """Paso banda por FFT con flancos suaves de un tercio de octava."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / rate)
    gain = np.clip(np.log2(np.maximum(f, 1e-3) / (lo / 1.26)) / np.log2(1.26), 0, 1) \
        * np.clip(np.log2(hi * 1.26 / np.maximum(f, 1e-3)) / np.log2(1.26), 0, 1)
    return np.fft.irfft(spec * gain, len(x))


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


def attack(env, a, b, end, width):
    """El tramo [a, b) de una voz desde su ataque. El clip se dispara con la acción (el golpe, el
    ataque), y lo que va delante de su parte fuerte se oye como un retraso: lo muy flojo (un rumor,
    un resoplido, la cola de otra llamada) se quita, y si aun así la parte fuerte llega tarde (la
    ventana de más energía de una vocalización larga puede acabar en su pico) el tramo empieza poco
    antes de ella y se alarga hasta [end], el final de la vocalización, sin pasar de [width]."""
    peak = env[a:b].max()
    a += int(np.argmax(env[a:b] > peak - ATTACK_DB))
    loud = a + int(np.argmax(env[a:b] > peak - LOUD_DB))
    if (loud - a) * HOP > MAX_LEAD:
        a = loud - int(LEAD_KEEP / HOP)
        b = min(end, a + width)
    return a, b


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
    width = int(dur[1] / HOP)
    for a, b in merged:
        length = (b - a) * HOP
        if length < dur[0]:
            continue
        end = b
        if length > dur[1]:
            # Lo más fuerte de la vocalización larga (o su arranque), a la duración máxima.
            if take == "loudest":
                sums = np.convolve(env[a:b], np.ones(width), "valid")
                a += int(np.argmax(sums))
            b = a + width
        picks.append((float(np.mean(env[a:b])), a, b, end))
    picks.sort(reverse=True)
    clips = []
    for _, a, b, end in picks[:n]:
        a, b = attack(env, a, b, end, width)
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
        if "band" in spec:
            x = bandpass(x, rate, *spec["band"])
        if n == "whole":
            got = cut_whole(x, rate, spec["dur"][1])
        elif spec["mode"] == "whole":
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
        "(craigsmith). Los leones están grabados en zoológicos y en un santuario de fauna. Los aullidos",
        "son de lobos de verdad (uno salvaje en Alaska y un coro de cinco); los gruñidos, gañidos y",
        "gemidos de cerca, de perros. Cada voz del",
        "jugador es de una sola persona: MrFossy la de hombre y Reitanna la de mujer, sin palabras.", "",
        "Las especies del pack WildMesh también suenan a animales de verdad: corzos en el bosque y ciervos",
        "de un parque (cierva, berrendo, ciervo, caribú), cabras, ovejas (el muflón), vacas y terneros,",
        "caballos y burros de granja, cerdos grabados de cerca (el jabalí), elefantes (el mamut, con su",
        "voz más grave), rinocerontes blancos peleando en Sudáfrica, caimanes y una cría de cocodrilo en",
        "el Amazonas, y un lince, un serval y gatos (el lince y, más grave, el puma). No hay grabaciones",
        "libres de alces ni de ñus: el alce, el ñu y el búfalo braman con los bisontes de Yellowstone,",
        "cada uno con su tono. Las grabaciones de campo pasan antes por un paso banda (\"band\") que deja",
        "fuera los grillos y el viento."]
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
