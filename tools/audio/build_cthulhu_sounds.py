#!/usr/bin/env python3
"""Sonidos de Cthulhu y de la cordura, montados a partir de clips CC0 que ya están en el repo.

No descarga nada: parte de los clips de audio/combat/ (grabaciones CC0 de Freesound, ver
audio/combat/credits.json) y de audio/effects/lake_storm.wav (CC0), y sintetiza el resto. Deja OGG
mono en audio/monsters/cthulhu/ y audio/monsters/sanity/, más audio/monsters/credits.json (de qué
clips sale cada uno).

  build/fauna_tools/bin/python tools/audio/build_cthulhu_sounds.py [--only=roar,step,...]

Qué sale:
  roar      la voz: rugidos de león y oso, gruñido de caimán y algo de trompeta de elefante, cada uno
            bajado de tono (más lento y más grave), sobre un sub grave que sigue la envolvente, con
            una reverberación larga de mar abierto
  step      la pisada: un golpe sub (38 -> 20 Hz), el agua que revienta (ruido grave) y la ola que
            se abre (un trozo de lake_storm a media velocidad)
  cascade   bucle: el agua que le chorrea del cuerpo al salir (ruido de lluvia y salpicones)
  rumble    bucle: el retumbar del fondo antes de que salga (zumbido grave que late)
  bubbles   el mar que burbujea: burbujas grandes sintetizadas (resonancia de Minnaert)
  whisper   susurros de la cordura baja: voces CC0 al revés pasadas por un vocoder de ruido
"""
import argparse, json, os, glob
import numpy as np
import soundfile as sf
from scipy import signal

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMBAT = os.path.join(ROOT, "audio", "combat")
OUT = os.path.join(ROOT, "audio", "monsters")
RATE = 48000


def load(path):
    x, rate = sf.read(os.path.join(ROOT, path), always_2d=True)
    x = x.mean(axis=1)
    if rate != RATE:
        g = np.gcd(rate, RATE)
        x = signal.resample_poly(x, RATE // g, rate // g)
    return x


def clip(event, n):
    return load("audio/combat/%s/%s_%02d.ogg" % (event, event, n))


def slow(x, factor):
    """Más lento y más grave a la vez (como una cinta a menos velocidad): factor < 1."""
    return signal.resample_poly(x, int(round(1000 / factor)), 1000)


def onset(x, thresh=0.08):
    env = np.abs(x)
    idx = np.argmax(env > thresh * env.max())
    return max(0, idx - int(0.02 * RATE))


def lowpass(x, f, order=4):
    sos = signal.butter(order, f, "low", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, f, order=2):
    sos = signal.butter(order, f, "high", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def bandpass(x, lo, hi, order=3):
    sos = signal.butter(order, [lo, hi], "band", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def envelope(x, smooth=0.05):
    return lowpass(np.abs(x), 1.0 / smooth, 2).clip(0)


def fit(x, n):
    out = np.zeros(n)
    out[:min(n, len(x))] = x[:n]
    return out


def fades(x, fin=0.01, fout=0.3):
    a, b = int(fin * RATE), int(fout * RATE)
    x = x.copy()
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def reverb(x, decay, wet, length=None, tone=3000.0, seed=1, predelay=0.0):
    """Convolución con ruido que decae: una sala enorme o el mar abierto."""
    rng = np.random.default_rng(seed)
    n = int((length or decay * 4.0) * RATE)
    t = np.arange(n) / RATE
    ir = rng.standard_normal(n) * np.exp(-t / decay)
    ir = lowpass(ir, tone, 2)
    ir[:int(predelay * RATE)] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    tail = signal.fftconvolve(x, ir)
    dry = np.concatenate([x, np.zeros(len(tail) - len(x))])
    return dry * (1.0 - wet) + tail * wet * 1.8


def normalize(x, peak=0.89):
    return x * (peak / (np.abs(x).max() + 1e-12))


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(np.square(x))) + 1e-12)


def loop_close(x, fade):
    """El final entra sobre el principio con un fundido de potencia constante."""
    n = int(fade * RATE)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    t = np.linspace(0, np.pi / 2, n)
    mixed = tail * np.cos(t) + head * np.sin(t)
    return np.concatenate([body, mixed])


def trim_tail(x, floor_db=-55.0, keep=0.25):
    """Corta la cola que queda por debajo de [floor_db] respecto al pico (con un fundido corto)."""
    env = envelope(x, 0.05)
    above = np.nonzero(env > env.max() * 10 ** (floor_db / 20))[0]
    end = min(len(x), (above[-1] if len(above) else len(x)) + int(keep * RATE))
    return fades(x[:end], 0.0, keep)


def write(name, x, sources, loop=False):
    if not loop:
        x = trim_tail(x)
    path = os.path.join(OUT, name + ".ogg")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, x.astype(np.float32), RATE, format="OGG", subtype="VORBIS")
    CREDITS[name] = sorted(set(sources))
    print("  %s  %.2f s  %.1f dB RMS" % (name, len(x) / RATE, rms_db(x)))


CREDITS = {}


# --- La voz ---------------------------------------------------------------------------------------

ROARS = [
    # (león, oso, caimán, elefante, bajada del león)
    (2, 3, 4, 4, 0.42),
    (6, 1, 3, 1, 0.45),
    (4, 2, 1, 5, 0.40),
    (8, 3, 6, 3, 0.47),
]


def build_roar():
    outs = []
    for i, (lion, bear, gator, trumpet, factor) in enumerate(ROARS):
        layers = []
        main = slow(clip("lion_roar", lion), factor)
        main = main[onset(main):][:int(6.5 * RATE)]
        n = len(main) + int(0.6 * RATE)
        layers.append(fit(main, n) * 1.0)
        b = slow(clip("bear_roar", bear), 0.55)
        layers.append(fit(b[onset(b):], n) * 0.65)
        g = slow(clip("alligator_growl", gator), 0.62)
        g = g[onset(g):]
        # El gruñido del caimán, con un poco de retraso: la garganta que gorgotea debajo.
        layers.append(fit(np.concatenate([np.zeros(int(0.25 * RATE)), g]), n) * 0.55)
        e = slow(clip("elephant_trumpet", trumpet), 0.5)
        e = e[onset(e):]
        layers.append(fit(np.concatenate([np.zeros(int(0.5 * RATE)), lowpass(e, 1800)]), n) * 0.22)
        mix = sum(normalize(l) * w for l, w in zip(layers, [1.0, 0.65, 0.55, 0.22]))
        # Un sub que sigue la envolvente: lo que se nota en el pecho.
        env = envelope(mix, 0.12)
        env /= env.max() + 1e-12
        t = np.arange(n) / RATE
        sub = np.sin(2 * np.pi * (31.0 + 4.0 * np.sin(2 * np.pi * 0.7 * t)) * t) \
            + 0.5 * np.sin(2 * np.pi * 46.5 * t + 0.4)
        mix = mix + sub * env * 0.35
        mix = lowpass(highpass(mix, 22.0), 6500.0)
        mix = fades(mix, 0.02, 0.8)
        mix = reverb(mix, 1.1, 0.42, length=4.5, tone=2200.0, seed=10 + i, predelay=0.04)
        outs.append(normalize(mix))
    ref = rms_db(outs[0])
    srcs = ["lion_roar", "bear_roar", "alligator_growl", "elephant_trumpet"]
    for i, x in enumerate(outs):
        x = x * 10 ** ((ref - rms_db(x)) / 20)
        write("cthulhu/roar_%02d" % (i + 1), normalize(x) if np.abs(x).max() > 0.95 else x, srcs)


# --- Pisada ---------------------------------------------------------------------------------------

def build_step():
    lake = load("audio/effects/lake_storm.wav")
    rng = np.random.default_rng(7)
    for i in range(4):
        n = int(4.2 * RATE)
        t = np.arange(n) / RATE
        f = 20.0 + 18.0 * np.exp(-t / 0.35) + rng.uniform(-2, 2)
        phase = 2 * np.pi * np.cumsum(f) / RATE
        boom = np.sin(phase) * np.minimum(t / 0.025, 1) * np.exp(-t / 0.85)
        # El agua que revienta contra la espinilla: ruido grave con un golpe seco.
        burst = lowpass(rng.standard_normal(n), 380.0) * np.exp(-t / 0.22) * np.minimum(t / 0.01, 1)
        # La ola que se abre y vuelve a caer: un trozo de temporal en el lago a media velocidad.
        start = rng.integers(0, len(lake) - int(3.0 * RATE))
        wave = slow(lake[start:start + int(2.6 * RATE)], 0.55)
        wave = fit(bandpass(wave, 70.0, 1600.0), n) * np.minimum(t / 0.15, 1) * np.exp(-t / 1.6)
        mix = normalize(boom) * 1.0 + normalize(burst) * 0.55 + normalize(wave) * 0.6
        mix = fades(mix, 0.0, 0.6)
        mix = reverb(mix, 0.7, 0.3, length=2.5, tone=1500.0, seed=30 + i)
        write("cthulhu/step_%02d" % (i + 1), normalize(mix), ["lake_storm"])


# --- Agua que chorrea -----------------------------------------------------------------------------

def build_cascade():
    rng = np.random.default_rng(11)
    lake = load("audio/effects/lake_storm.wav")
    dur, fade = 12.0, 2.0
    n = int((dur + fade) * RATE)
    t = np.arange(n) / RATE
    # La cortina: ruido rosa por banda con oleadas lentas.
    white = rng.standard_normal(n)
    b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
    pink = signal.lfilter(b, a, white)
    swell = 0.65 + 0.35 * lowpass(rng.standard_normal(n), 0.6, 1) / 0.05
    sheet = bandpass(pink, 180.0, 4200.0) * np.clip(swell, 0.25, 1.4)
    # Los chorros gruesos que caen al mar: golpes graves sueltos.
    plops = np.zeros(n)
    for _ in range(int(dur * 9)):
        at = rng.integers(0, n - RATE)
        k = int(rng.uniform(0.08, 0.3) * RATE)
        tt = np.arange(k) / RATE
        plops[at:at + k] += lowpass(rng.standard_normal(k), rng.uniform(250, 700)) * np.exp(-tt / rng.uniform(0.04, 0.12)) \
            * rng.uniform(0.3, 1.0)
    body = slow(np.tile(lake, 2)[:int((dur + fade) * 0.7 * RATE) + 10], 0.7)
    body = fit(bandpass(body, 90.0, 2500.0), n)
    mix = normalize(sheet) * 0.8 + normalize(plops) * 0.55 + normalize(body) * 0.5
    mix = reverb(mix, 0.6, 0.25, length=2.0, tone=3000.0, seed=12)[:n]
    write("cthulhu/cascade_loop", normalize(loop_close(mix, fade)), ["lake_storm"], loop=True)


# --- Retumbar del fondo ---------------------------------------------------------------------------

def build_rumble():
    rng = np.random.default_rng(21)
    dur, fade = 14.0, 3.0
    n = int((dur + fade) * RATE)
    t = np.arange(n) / RATE
    drone = np.zeros(n)
    # Graves que baten entre sí (late), con armónicos a los que llega un altavoz pequeño.
    for f, w in [(27.5, 1.0), (29.1, 0.8), (41.2, 0.55), (55.0, 0.45), (82.4, 0.25), (110.6, 0.12)]:
        drone += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * w
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / 7.0 + 1.0) * np.sin(2 * np.pi * t / 4.3)
    grind = lowpass(rng.standard_normal(n), 140.0, 4) * (0.5 + 0.5 * lowpass(rng.standard_normal(n), 0.4, 1) / 0.04)
    mix = normalize(drone * swell) * 0.8 + normalize(grind) * 0.6
    mix = reverb(mix, 1.5, 0.3, length=5.0, tone=400.0, seed=22)[:n]
    write("cthulhu/rumble_loop", normalize(loop_close(highpass(mix, 18.0), fade)), [], loop=True)


# --- Burbujas -------------------------------------------------------------------------------------

def build_bubbles():
    rng = np.random.default_rng(31)
    for i in range(4):
        dur = rng.uniform(2.6, 3.6)
        n = int(dur * RATE)
        out = np.zeros(n)
        count = rng.integers(28, 55)
        for _ in range(count):
            # Burbujas de mucho fondo: grandes y graves (Minnaert: f ~ 3,26 / radio).
            radius = rng.uniform(0.006, 0.05)
            f0 = 3.26 / radius
            tau = min(rng.uniform(0.04, 0.12) * (radius / 0.02) ** 0.5, 0.12)
            k = int(tau * 6 * RATE)
            tt = np.arange(k) / RATE
            # Sube un poco al subir la burbuja; sin barridos largos (sonarían a muelle).
            f = f0 * (1.0 + rng.uniform(0.3, 1.2) * np.minimum(tt, 0.25))
            b = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-tt / tau) * np.minimum(tt / 0.002, 1)
            at = int(rng.beta(1.6, 2.2) * (n - k))
            out[at:at + k] += b * rng.uniform(0.3, 1.0)
        gloop = lowpass(rng.standard_normal(n), 220.0) * envelope(out, 0.3) * 2.0
        mix = fades(out + gloop, 0.05, 0.5)
        mix = reverb(mix, 0.4, 0.2, length=1.5, tone=2500.0, seed=40 + i)
        write("cthulhu/bubbles_%02d" % (i + 1), normalize(mix), [])


# --- Susurros -------------------------------------------------------------------------------------

def noise_vocode(voice, rng, nfft=1024):
    """El espectro de la voz sobre ruido: lo que queda es aire con la forma de las palabras."""
    f, t, v = signal.stft(voice, RATE, nperseg=nfft)
    mag = np.abs(v)
    # Envolvente espectral (sin la altura de la voz): media móvil por frecuencia.
    kernel = np.ones(5) / 5.0
    mag = np.apply_along_axis(lambda c: np.convolve(c, kernel, mode="same"), 0, mag)
    _, _, z = signal.stft(rng.standard_normal(len(voice)), RATE, nperseg=nfft)
    z = z[:, :mag.shape[1]]
    _, out = signal.istft(mag * np.exp(1j * np.angle(z)), RATE, nperseg=nfft)
    return out[:len(voice)]


WHISPER_SOURCES = [("player_agony", [1, 5, 7, 10]), ("player_agony_female", [1, 5, 7]),
    ("player_hurt", [1, 3, 5, 8, 11])]


def build_whisper():
    rng = np.random.default_rng(51)
    pool = []
    for event, ids in WHISPER_SOURCES:
        for k in ids:
            pool.append((event, clip(event, k)))
    used = set()
    for i in range(8):
        dur = rng.uniform(1.6, 3.0)
        n = int(dur * RATE)
        voices = np.zeros(n)
        # Una o dos voces que se pisan. Cada una dice sílabas sueltas (trozos cortos de clips al revés)
        # con huecos entre palabras: sin huecos el vocoder deja un siseo continuo.
        for v in range(rng.integers(1, 3)):
            line = np.zeros(0)
            while len(line) < n:
                for _syllable in range(rng.integers(2, 5)):
                    event, x = pool[rng.integers(len(pool))]
                    used.add(event)
                    x = x[::-1]
                    seg = int(rng.uniform(0.09, 0.26) * RATE)
                    start = rng.integers(0, max(1, len(x) - seg))
                    piece = x[start:start + seg] * np.hanning(seg) ** 0.6
                    piece = signal.resample_poly(piece, 100, int(rng.uniform(85, 115)))
                    line = np.concatenate([line, piece, np.zeros(int(rng.uniform(0.01, 0.06) * RATE))])
                line = np.concatenate([line, np.zeros(int(rng.uniform(0.18, 0.5) * RATE))])
            line = line[:n]
            wh = noise_vocode(line, rng)
            # El vocoder emborrona el tiempo: se le vuelve a poner la envolvente de las sílabas.
            env = envelope(line, 0.02)
            wh = wh * env / (envelope(wh, 0.02) + 1e-4 * env.max() + 1e-9)
            delay = int(rng.uniform(0.15, 0.6) * RATE) if v > 0 else 0
            voices += np.concatenate([np.zeros(delay), wh])[:n] * (1.0 if v == 0 else 0.55)
        mix = bandpass(voices, 500.0, 7500.0)
        mix = fades(mix, 0.25, 0.6)
        mix = reverb(mix, 0.22, 0.14, length=0.9, tone=5000.0, seed=60 + i, predelay=0.02)
        write("sanity/whisper_%02d" % (i + 1), normalize(mix), sorted(used))


BUILDERS = {"roar": build_roar, "step": build_step, "cascade": build_cascade, "rumble": build_rumble,
    "bubbles": build_bubbles, "whisper": build_whisper}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    only = [s for s in args.only.split(",") if s] or list(BUILDERS)
    credits_path = os.path.join(OUT, "credits.json")
    if os.path.exists(credits_path):
        CREDITS.update(json.load(open(credits_path))["clips"])
    for name in only:
        print(name)
        BUILDERS[name]()
    # De qué grabación de Freesound sale cada carpeta de clips usada.
    combat = json.load(open(os.path.join(COMBAT, "credits.json")))
    sources = {}
    for clips in CREDITS.values():
        for event in clips:
            ids = sorted({c["source"] for c in combat["events"].get(event, [])})
            if event == "lake_storm":
                ids = [169883]
            for sid in ids:
                meta = combat["sources"].get(str(sid))
                sources[str(sid)] = meta or {"url": "https://freesound.org/s/%d/" % sid,
                    "license": "http://creativecommons.org/publicdomain/zero/1.0/"}
    json.dump({"clips": CREDITS, "sources": sources}, open(credits_path, "w"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
