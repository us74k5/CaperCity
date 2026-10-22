"""Synthesizes Caper City's weapon sounds (no samples). Each gunshot is layered the way sound designers
build them: supersonic crack + muzzle blast + low punch + street reflections + decaying tail +
the gun's mechanism + brass casings bouncing on the pavement. Melee hits layer a swing with an impact.

Usage: python3 -I tools/music/weapons.py <project_dir>
Writes audio/weapons/<name>.ogg (variants as name_1, name_2, ...) and prints levels.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synth import SR, Rand, adsr, bp, hp, lp, noise, tt  # noqa: E402


def place(out, sig, at, gain=1.0):
    s = int(at * SR)
    e = min(len(out), s + len(sig))
    if e > s:
        out[s:e] += sig[: e - s] * gain


def env_exp(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def crack(dur=0.006, bright=2500, gain=1.0):
    n = int(dur * SR)
    return hp(noise(n), bright) * env_exp(n, 900) * gain


def thump(f0=140, f1=45, dur=0.12, rate=30):
    t = tt(dur)
    f = f1 + (f0 - f1) * np.exp(-t * 40)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * rate)


def blast(lo, hi, dur, rate, drive=3.0):
    n = int(dur * SR)
    return np.tanh(bp(noise(n), lo, hi) * drive) * env_exp(n, rate)


def metal_click(freqs=(2700, 3900, 6100), dur=0.06, rate=70, nz=0.6):
    t = tt(dur)
    s = sum(np.sin(2 * np.pi * f * t + Rand.rng.random() * 6) for f in freqs) / len(freqs)
    return (s + bp(noise(len(t)), 1500, 8000) * nz) * np.exp(-t * rate)


def slap(dur=0.05, lo=450, hi=2600, rate=65):
    """The mid-range thwack of an impact: what a phone speaker can actually play."""
    n = int(dur * SR)
    return np.tanh(bp(noise(n), lo, hi) * 2.5) * env_exp(n, rate)


def casing_bounces(out, start):
    """Brass shell hitting the pavement a few times."""
    amp = 0.16
    at = start
    for i in range(3 + Rand.rng.integers(0, 2)):
        f = 5200 + Rand.rng.random() * 2600
        t = tt(0.12)
        ping = (np.sin(2 * np.pi * f * t) + 0.6 * np.sin(2 * np.pi * f * 1.51 * t)) * np.exp(-t * 45)
        place(out, ping, at, amp)
        at += 0.06 + 0.05 * Rand.rng.random() / (i + 1)
        amp *= 0.55


def reflections(out, src, delays=((0.023, 0.33), (0.041, 0.24), (0.067, 0.17), (0.11, 0.1), (0.16, 0.06))):
    soft = lp(src, 2500)
    for d, g in delays:
        place(out, soft, d, g)


def tail(dur, rate, level, cutoff=1500):
    n = int(dur * SR)
    return (lp(noise(n), cutoff) * 0.8 + lp(noise(n), 220) * 0.6) * env_exp(n, rate) * level


def finish(x, peak=0.94):
    x = hp(x, 35)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


# ------------------------------------------------------------------ guns
def pistol(seed):
    Rand.seed(seed)
    out = np.zeros(int(1.1 * SR))
    b = blast(250, 6500, 0.09, 55)
    place(out, crack(0.005, 2500, 1.6), 0)
    place(out, b, 0.0015, 1.0)
    place(out, thump(150, 55, 0.12, 32), 0, 0.9)
    reflections(out, b)
    place(out, tail(0.9, 5.5, 0.22), 0.01)
    place(out, metal_click((2600, 3700, 5400), 0.05, 80), 0.045 + 0.01 * Rand.rng.random(), 0.35)   # slide
    casing_bounces(out, 0.38 + 0.08 * Rand.rng.random())
    return finish(out)


def rifle(seed):
    Rand.seed(seed)
    out = np.zeros(int(1.9 * SR))
    b = blast(160, 7000, 0.14, 32, 4.0)
    place(out, crack(0.004, 3500, 2.2), 0)          # supersonic crack
    place(out, b, 0.002, 1.0)
    place(out, thump(110, 38, 0.2, 18), 0, 1.2)
    reflections(out, b, ((0.03, 0.42), (0.055, 0.3), (0.09, 0.22), (0.15, 0.14), (0.24, 0.09), (0.34, 0.05)))
    place(out, tail(1.6, 3.2, 0.3, 1200), 0.01)
    # bolt: open, then close
    place(out, metal_click((1800, 2900, 4400), 0.08, 45, 0.9), 0.62, 0.4)
    place(out, metal_click((2100, 3300, 5200), 0.07, 55, 0.9), 0.86, 0.45)
    casing_bounces(out, 0.72)
    return finish(out)


def machine_gun(seed):
    Rand.seed(seed)
    rounds = 6
    gap = 0.085
    out = np.zeros(int((rounds * gap + 1.3) * SR))
    for i in range(rounds):
        at = i * gap + 0.004 * Rand.rng.random()
        g = 0.85 + 0.15 * Rand.rng.random()
        b = blast(200, 6800, 0.08, 60, 3.5)
        place(out, crack(0.004, 2800, 1.5 * g), at)
        place(out, b, at + 0.0015, g)
        place(out, thump(130, 48, 0.09, 40), at, 0.8 * g)
        reflections(out, b * 0.7) if i == rounds - 1 else None
        place(out, metal_click((3100, 4500), 0.03, 120, 0.4), at + 0.04, 0.15)
    place(out, tail(1.3, 3.5, 0.32, 1300), 0.02)
    for i in range(3):
        casing_bounces(out, 0.3 + i * 0.12)
    return finish(out)


def explosion(seed):
    Rand.seed(seed)
    out = np.zeros(int(2.8 * SR))
    place(out, crack(0.01, 1500, 1.8), 0)
    t = tt(0.6)
    f = 26 + 70 * np.exp(-t * 9)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 5)
    place(out, boom, 0, 1.5)
    n = int(2.6 * SR)
    body = np.tanh(lp(noise(n), 700) * 4) * env_exp(n, 3.2)
    place(out, body, 0.003, 0.9)
    place(out, lp(noise(n), 160) * env_exp(n, 1.6), 0.01, 0.9)    # rumble
    place(out, np.tanh(bp(noise(n), 400, 2200) * 3) * env_exp(n, 6), 0.002, 0.5)   # fireball roar
    for _ in range(40):    # debris and glass
        at = 0.12 + Rand.rng.random() ** 1.5 * 1.6
        if Rand.rng.random() < 0.3:
            fq = 4000 + Rand.rng.random() * 4000
            tt_ = tt(0.08)
            place(out, np.sin(2 * np.pi * fq * tt_) * np.exp(-tt_ * 50), at, 0.06)
        else:
            place(out, bp(noise(300), 1200, 5000) * env_exp(300, 300), at, 0.12 * (1.6 - at))
    return finish(out, 0.97)


# ------------------------------------------------------------------ melee & throwing
def swing(dur=0.24, lo=350, hi=1900, seed=0, level=1.0):
    Rand.seed(seed)
    n = int(dur * SR)
    src = noise(n)
    out = np.zeros(n)
    steps = 16
    seg = n // steps
    for i in range(steps):
        x = i / (steps - 1)
        fc = lo + (hi - lo) * np.sin(np.pi * x)
        piece = bp(src[i * seg:(i + 1) * seg + 256], fc * 0.75, fc * 1.3)[:seg]
        out[i * seg:i * seg + len(piece)] = piece
    return finish(out * np.sin(np.pi * np.arange(n) / n) ** 1.5, 0.9 * level)


def punch_hit(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.35 * SR))
    place(out, thump(120, 70, 0.14, 38), 0, 0.55)
    place(out, lp(noise(int(0.06 * SR)), 1100) * env_exp(int(0.06 * SR), 60), 0, 0.8)
    place(out, hp(noise(int(0.008 * SR)), 2500), 0, 0.5)   # skin slap
    place(out, slap(0.05, 500, 2400, 70), 0, 1.0)
    return finish(out)


def club_hit(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.45 * SR))
    place(out, thump(110, 60, 0.2, 22), 0, 1.0)
    t = tt(0.25)
    knock = (np.sin(2 * np.pi * 430 * t) + 0.5 * np.sin(2 * np.pi * 1120 * t)) * np.exp(-t * 30)
    place(out, knock, 0, 0.8)
    place(out, lp(noise(int(0.05 * SR)), 2000) * env_exp(int(0.05 * SR), 70), 0, 0.6)
    place(out, slap(0.06, 400, 2000, 55), 0, 0.6)
    return finish(out)


def baton_hit(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.35 * SR))
    place(out, thump(130, 70, 0.15, 30), 0, 0.9)
    t = tt(0.15)
    place(out, (np.sin(2 * np.pi * 820 * t) + 0.4 * np.sin(2 * np.pi * 2100 * t)) * np.exp(-t * 45), 0, 0.4)
    place(out, hp(noise(int(0.01 * SR)), 2000), 0, 0.6)
    return finish(out)


def knife_slash(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.5 * SR))
    place(out, swing(0.16, 1800, 6500, seed), 0, 0.7)
    place(out, swing(0.16, 600, 1800, seed + 7), 0, 0.6)
    t = tt(0.35)
    f = 3600 + 1600 * t / 0.35
    shing = np.sin(2 * np.pi * np.cumsum(f) / SR + 1.5 * np.sin(2 * np.pi * 9000 * t)) * np.exp(-t * 11)
    place(out, shing, 0.02, 0.25)
    return finish(out)


def knife_stab(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.35 * SR))
    place(out, thump(100, 60, 0.12, 40), 0, 0.45)
    n = int(0.12 * SR)
    squelch = bp(noise(n), 300, 1100) * env_exp(n, 30) * (1 + 0.6 * np.sin(2 * np.pi * 35 * np.arange(n) / SR))
    place(out, squelch, 0.005, 1.0)
    place(out, slap(0.04, 600, 2600, 80), 0, 0.5)
    return finish(out)


def knife_throw(seed):
    Rand.seed(seed)
    n = int(0.45 * SR)
    w = swing(0.45, 900, 3200, seed)
    spin = 0.55 + 0.45 * np.sin(2 * np.pi * 17 * np.arange(len(w)) / SR)
    return finish(w * spin)


def knife_thunk(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.4 * SR))
    place(out, thump(140, 80, 0.1, 40), 0, 0.8)
    t = tt(0.3)
    place(out, np.sin(2 * np.pi * 620 * t) * np.exp(-t * 25) * (1 + 0.3 * np.sin(2 * np.pi * 40 * t)), 0, 0.8)   # handle twang
    place(out, slap(0.04, 700, 3000, 80), 0, 0.5)
    return finish(out)


def grenade_pin():
    Rand.seed(70)
    out = np.zeros(int(0.5 * SR))
    place(out, metal_click((3200, 4700, 7100), 0.12, 25, 0.3), 0, 0.6)
    place(out, metal_click((2400, 3600), 0.05, 90, 0.5), 0.18, 0.5)   # spoon flies off
    return finish(out, 0.8)


def grenade_bounce():
    Rand.seed(71)
    out = np.zeros(int(0.6 * SR))
    amp = 1.0
    at = 0.0
    for i in range(3):
        place(out, metal_click((900, 1700, 2600), 0.08, 50, 0.9), at, amp)
        at += 0.16 / (i + 1)
        amp *= 0.5
    return finish(out, 0.7)


# ------------------------------------------------------------------ impacts & misc
def bullet_flesh(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.3 * SR))
    place(out, thump(160, 80, 0.1, 50), 0, 0.5)
    n = int(0.05 * SR)
    place(out, lp(noise(n), 900) * env_exp(n, 70), 0, 0.6)
    place(out, hp(noise(int(0.004 * SR)), 3000), 0, 0.4)
    place(out, slap(0.045, 500, 2200, 75), 0, 1.0)
    return finish(out)


def bullet_miss(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.5 * SR))
    t = tt(0.16)
    f = 4200 - 2600 * t / 0.16
    whiz = (np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.3 + bp(noise(len(t)), 2000, 7000) * 0.5) * np.sin(np.pi * t / t[-1])
    place(out, whiz, 0, 0.6)
    place(out, hp(noise(int(0.008 * SR)), 2000) * 1.2, 0.15)                      # concrete chip
    place(out, bp(noise(int(0.04 * SR)), 1500, 4500) * env_exp(int(0.04 * SR), 80), 0.152, 0.6)
    if seed % 2 == 0:   # every other miss ricochets off
        t2 = tt(0.35)
        f2 = 2800 - 1500 * t2 / 0.35 + 120 * np.sin(2 * np.pi * 30 * t2)
        place(out, np.sin(2 * np.pi * np.cumsum(f2) / SR) * np.exp(-t2 * 7), 0.16, 0.22)
    return finish(out, 0.85)


def body_fall(seed):
    Rand.seed(seed)
    out = np.zeros(int(0.7 * SR))
    place(out, thump(90, 50, 0.2, 24), 0, 0.5)
    n = int(0.3 * SR)
    place(out, lp(noise(n), 1500) * env_exp(n, 12), 0, 0.35)    # clothes
    place(out, thump(110, 60, 0.12, 36), 0.17, 0.25)              # second bump
    place(out, slap(0.08, 350, 1600, 35), 0, 0.9)
    place(out, slap(0.05, 400, 1800, 50), 0.17, 0.3)
    return finish(out, 0.85)


def reload_pistol():
    Rand.seed(80)
    out = np.zeros(int(0.9 * SR))
    place(out, metal_click((1800, 2600), 0.05, 70, 0.8), 0.0, 0.6)    # mag out
    place(out, metal_click((1500, 2300, 3100), 0.07, 60, 0.9), 0.38, 0.8)   # mag in
    place(out, swing(0.08, 1500, 4000, 81), 0.6, 0.3)
    place(out, metal_click((2800, 4200, 5900), 0.06, 80, 0.9), 0.66, 0.9)   # slide forward
    return finish(out, 0.75)


def gun_cock():
    Rand.seed(82)
    out = np.zeros(int(0.6 * SR))
    place(out, metal_click((1600, 2500, 3600), 0.08, 45, 1.0), 0.0, 0.8)
    place(out, metal_click((2000, 3100, 4600), 0.08, 55, 1.0), 0.2, 0.9)
    return finish(out, 0.75)


SOUNDS = {
    "pistol": [lambda i=i: pistol(100 + i) for i in range(3)],
    "rifle": [lambda i=i: rifle(110 + i) for i in range(2)],
    "machine_gun": [lambda i=i: machine_gun(120 + i) for i in range(2)],
    "explosion": [lambda i=i: explosion(130 + i) for i in range(2)],
    "swing_light": [lambda i=i: swing(0.18, 500, 2400, 140 + i) for i in range(3)],
    "swing_heavy": [lambda i=i: swing(0.3, 250, 1400, 150 + i) for i in range(3)],
    "punch_hit": [lambda i=i: punch_hit(160 + i) for i in range(3)],
    "club_hit": [lambda i=i: club_hit(170 + i) for i in range(2)],
    "baton_hit": [lambda i=i: baton_hit(180 + i) for i in range(2)],
    "knife_slash": [lambda i=i: knife_slash(190 + i) for i in range(2)],
    "knife_stab": [lambda i=i: knife_stab(200 + i) for i in range(2)],
    "knife_throw": [lambda i=i: knife_throw(210 + i) for i in range(2)],
    "knife_thunk": [lambda i=i: knife_thunk(220 + i) for i in range(2)],
    "grenade_pin": [grenade_pin],
    "grenade_bounce": [grenade_bounce],
    "bullet_flesh": [lambda i=i: bullet_flesh(230 + i) for i in range(3)],
    "bullet_miss": [lambda i=i: bullet_miss(240 + i) for i in range(3)],
    "body_fall": [lambda i=i: body_fall(250 + i) for i in range(2)],
    "reload_pistol": [reload_pistol],
    "gun_cock": [gun_cock],
}


if __name__ == "__main__":
    out_dir = os.path.join(sys.argv[1], "audio", "weapons")
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, makers in SOUNDS.items():
        for i, mk in enumerate(makers):
            x = mk()
            fname = "%s_%d" % (name, i + 1) if len(makers) > 1 else name
            st = np.stack([x, x], axis=1)
            with tempfile.TemporaryDirectory() as td:
                wav = os.path.join(td, "a.wav")
                wavfile.write(wav, SR, (np.clip(st, -1, 1) * 32767).astype(np.int16))
                dst = os.path.join(out_dir, fname + ".ogg")
                subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-ac", "1", "-c:a", "libvorbis", "-q:a", "6", dst], check=True)
            kb = os.path.getsize(dst) // 1024
            total += kb
            f = np.fft.rfftfreq(len(x), 1 / SR)
            P = np.abs(np.fft.rfft(x)) ** 2
            low = 100 * P[f < 200].sum() / P.sum()
            high = 100 * P[f > 3000].sum() / P.sum()
            rms = 20 * np.log10(np.sqrt(np.mean(x[: int(0.15 * SR)] ** 2)) + 1e-9)
            print("%-18s %4.2fs %3dKB  first-150ms rms %6.1f dB  <200Hz %4.1f%%  >3k %4.1f%%" % (fname, len(x) / SR, kb, rms, low, high))
    print("total %d KB" % total)
