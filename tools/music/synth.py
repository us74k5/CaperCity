"""Tiny code-only synth for Caper City's music and stings. No samples: everything is generated.

Track: a stereo buffer measured in beats. Loops wrap note tails to the start so they repeat seamlessly.
Instruments return mono numpy arrays; ambience helpers return arrays for a whole track.
"""
import numpy as np
from scipy.signal import lfilter, butter, sosfilt, sosfiltfilt

SR = 44100


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def tt(dur):
    return np.arange(max(1, int(dur * SR))) / SR


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.08):
    e = np.full(n, float(s))
    ai = min(n, max(1, int(a * SR)))
    e[:ai] = np.linspace(0, 1, ai)
    di = min(n - ai, max(1, int(d * SR)))
    if di > 0:
        e[ai:ai + di] = np.linspace(1, s, di)
    ri = min(n, max(1, int(r * SR)))
    e[-ri:] *= np.linspace(1, 0, ri)
    return e


def lp(x, f, order=2):
    sos = butter(order, min(f, SR * 0.45) / (SR / 2), output="sos")
    return sosfilt(sos, x)


def hp(x, f, order=2):
    sos = butter(order, min(f, SR * 0.45) / (SR / 2), btype="high", output="sos")
    return sosfilt(sos, x)


def bp(x, lo, hi, order=2):
    sos = butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], btype="band", output="sos")
    return sosfilt(sos, x)


class Rand:
    rng = np.random.default_rng(1)

    @classmethod
    def seed(cls, s):
        cls.rng = np.random.default_rng(s)


def noise(n):
    return Rand.rng.standard_normal(n)


def saw(f, t):
    return 2 * ((f * t) % 1.0) - 1


def sqr(f, t, duty=0.5):
    return np.where((f * t) % 1.0 < duty, 1.0, -1.0)


def tri(f, t):
    return 2 * np.abs(2 * ((f * t) % 1.0) - 1) - 1


# ------------------------------------------------------------------ drums
def kick(punch=1.0, dur=0.45):
    t = tt(dur)
    f = 48 + 120 * punch * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)


def snare(tone=185, dur=0.28, bright=7000):
    t = tt(dur)
    return lp(noise(len(t)), bright) * np.exp(-t * 15) * 0.6 + np.sin(2 * np.pi * tone * t) * np.exp(-t * 22) * 0.45


def brush(dur=0.25):
    t = tt(dur)
    return bp(noise(len(t)), 1500, 9000) * np.exp(-t * 12) * 0.35


def clap():
    t = tt(0.25)
    n = bp(noise(len(t)), 900, 5000)
    e = np.exp(-t * 18)
    for off in (0.01, 0.022):
        e += np.exp(-np.maximum(t - off, 0) * 60) * (t >= off) * 0.6
    return n * e * 0.5


def hat(open_=False, dur=None):
    t = tt(dur or (0.3 if open_ else 0.06))
    return hp(noise(len(t)), 7000) * np.exp(-t * (12 if open_ else 70)) * 0.3


def shaker():
    t = tt(0.09)
    return bp(noise(len(t)), 4000, 12000) * np.sin(np.pi * t / t[-1]) * 0.2


def rim():
    t = tt(0.08)
    return (np.sin(2 * np.pi * 1700 * t) + 0.5 * np.sin(2 * np.pi * 820 * t)) * np.exp(-t * 60) * 0.4


def tom(freq=110, dur=0.5):
    t = tt(dur)
    f = freq * (1 + 0.4 * np.exp(-t * 20))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6) * 0.8


def timpani(freq=80, dur=1.2):
    t = tt(dur)
    s = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 1.5 * t) + 0.3 * np.sin(2 * np.pi * freq * 1.99 * t)
    return (s * np.exp(-t * 3) + lp(noise(len(t)), 400) * np.exp(-t * 30) * 0.4) * 0.6


def cymbal(dur=1.6):
    t = tt(dur)
    return hp(noise(len(t)), 5000) * np.exp(-t * 2.5) * 0.25


# ------------------------------------------------------------------ bass
def bass_saw(f, dur, bright=1.0):
    t = tt(dur)
    pl = np.exp(-t * 9)
    s = saw(f, t)
    return ((lp(s, 400 + 1200 * bright) * pl + lp(s, 320) * (1 - pl)) * 0.7 + np.sin(np.pi * f * t) * 0.45) * adsr(len(t), 0.004, 0.12, 0.8, 0.04)


def bass_upright(f, dur):
    t = tt(dur)
    s = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(4 * np.pi * f * t) * np.exp(-t * 8) + 0.15 * np.sin(6 * np.pi * f * t) * np.exp(-t * 12)
    return s * np.exp(-t * 2.5) * adsr(len(t), 0.003, 0.05, 1.0, 0.05) * 0.9


def bass_sub(f, dur):
    t = tt(dur)
    return np.sin(2 * np.pi * f * t) * adsr(len(t), 0.01, 0.1, 0.9, 0.08)


# ------------------------------------------------------------------ keys / tonal
def epiano(f, dur):
    t = tt(dur)
    mod = np.sin(2 * np.pi * f * 2 * t) * 1.2 * np.exp(-t * 3)
    s = np.sin(2 * np.pi * f * t + mod) + 0.15 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 6)
    return s * np.exp(-t * 1.0) * (1 + 0.1 * np.sin(2 * np.pi * 4.5 * t)) * adsr(len(t), 0.004, 0.2, 0.75, 0.12)


def organ(f, dur, perc=True):
    t = tt(dur)
    s = sum(a * np.sin(2 * np.pi * f * m * t) for m, a in ((0.5, 0.6), (1, 1.0), (2, 0.5), (3, 0.3), (4, 0.2)))
    if perc:
        s += 0.5 * np.sin(2 * np.pi * f * 3 * t) * np.exp(-t * 10)
    leslie = 1 + 0.15 * np.sin(2 * np.pi * 6.2 * t)
    return np.tanh(s * 0.6) * leslie * adsr(len(t), 0.01, 0.05, 0.9, 0.06) * 0.6


def vibes(f, dur):
    t = tt(dur)
    s = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 5)
    return s * np.exp(-t * 1.6) * (1 + 0.35 * np.sin(2 * np.pi * 5.5 * t)) * adsr(len(t), 0.002, 0.1, 1.0, 0.1) * 0.7


def bell(f, dur, ratio=3.5, idx=2.5):
    t = tt(dur)
    mod = np.sin(2 * np.pi * f * ratio * t) * idx * np.exp(-t * 2)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 1.8) * adsr(len(t), 0.002, 0.1, 1.0, 0.1) * 0.6


def music_box(f, dur):
    t = tt(dur)
    return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t * 6)) * np.exp(-t * 3.5) * 0.5


def pluck(f, dur, damp=0.996, bright=1.0):
    """Karplus-Strong string: guitar, ukulele, harpsichord."""
    n = max(4, int(SR / f))
    x = np.zeros(int(dur * SR))
    burst = lp(noise(n), 2000 + 8000 * bright)
    x[:n] = burst
    a = np.zeros(n + 2)
    a[0] = 1.0
    a[n] = -damp / 2
    a[n + 1] = -damp / 2
    y = lfilter([1.0], a, x)
    return y / (np.max(np.abs(y)) + 1e-9) * adsr(len(y), 0.001, 0.05, 1.0, 0.05) * 0.7


def pad(freqs, dur, cutoff=1400, attack=0.6):
    t = tt(dur)
    s = np.zeros(len(t))
    for f in freqs:
        for det in (-0.006, 0.0, 0.007):
            s += saw(f * (1 + det), t + Rand.rng.random())
    s = lp(s / (len(freqs) * 3), cutoff, 2)
    return s * adsr(len(t), attack, 0.3, 0.85, min(0.8, dur * 0.3)) * 1.4


def strings(freqs, dur, cutoff=2400, attack=0.25):
    t = tt(dur)
    s = np.zeros(len(t))
    for f in freqs:
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t + Rand.rng.random() * 6)
        for det in (-0.004, 0.005):
            s += saw(1.0, np.cumsum(f * (1 + det) * vib) / SR)
    s = lp(s / (len(freqs) * 2), cutoff, 2)
    return s * adsr(len(t), attack, 0.2, 0.9, min(0.5, dur * 0.3)) * 1.2


def brass(f, dur, bright=1.0):
    t = tt(dur)
    scoop = 1 - 0.03 * np.exp(-t * 25)
    s = saw(1.0, np.cumsum(f * scoop) / SR)
    fe = np.minimum(1, t * 18) * (0.6 + 0.4 * np.exp(-t * 3))
    s = lp(s, 900 + 2600 * bright) * (0.35 + 0.65 * fe)
    return s * adsr(len(t), 0.02, 0.15, 0.8, 0.08) * 0.8


def lead_square(f, dur, cutoff=2600):
    t = tt(dur)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t * 3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    s = np.tanh(3 * np.sin(ph)) * 0.6 + 0.4 * np.sin(2 * ph)
    return lp(s, cutoff) * adsr(len(t), 0.02, 0.2, 0.7, 0.1)


def muted_trumpet(f, dur):
    t = tt(dur)
    vib = 1 + 0.008 * np.sin(2 * np.pi * 5.0 * t) * np.clip(t * 2 - 0.2, 0, 1)
    s = saw(1.0, np.cumsum(f * vib) / SR)
    s = bp(s, f * 0.9, min(f * 6, 9000)) * 1.6
    return s * adsr(len(t), 0.04, 0.15, 0.75, 0.12)


def harmonica(f, dur):
    t = tt(dur)
    bend = 1 - 0.04 * np.exp(-t * 6)
    vib = 1 + 0.01 * np.sin(2 * np.pi * 6 * t)
    s = sqr(1.0, np.cumsum(f * bend * vib) / SR, 0.35)
    return lp(s, 2200) * adsr(len(t), 0.05, 0.1, 0.8, 0.15) * 0.5


def steel_drum(f, dur):
    t = tt(dur)
    s = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * 4) + 0.3 * np.sin(2 * np.pi * f * 3.0 * t) * np.exp(-t * 8)
    return s * np.exp(-t * 2.6) * adsr(len(t), 0.003, 0.05, 1.0, 0.05) * 0.6


def whistle(f, dur):
    t = tt(dur)
    vib = 1 + 0.01 * np.sin(2 * np.pi * 5 * t)
    return np.sin(2 * np.pi * np.cumsum(f * vib) / SR) * adsr(len(t), 0.05, 0.1, 0.8, 0.1) * 0.5 + bp(noise(len(t)), f * 0.9, f * 1.2) * 0.04


# ------------------------------------------------------------------ fx & ambience
def gunshot(dist=1.0):
    t = tt(0.6)
    crack = noise(len(t)) * np.exp(-t * (40 / dist))
    boom = lp(noise(len(t)), 300) * np.exp(-t * 8) * 1.5
    tail = lp(noise(len(t)), 1200) * np.exp(-t * 5) * 0.3
    return np.tanh((crack * 0.8 + boom + tail) * 1.5) * (0.9 / dist)


def ricochet():
    t = tt(0.5)
    f = 3200 * np.exp(-t * 3) + 900
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6) * 0.2


def siren(dur, kind="wail", f0=650, f1=1350):
    t = tt(dur)
    if kind == "wail":
        f = f0 + (f1 - f0) * (0.5 - 0.5 * np.cos(2 * np.pi * t / 3.2))
    else:
        f = f0 + (f1 - f0) * (np.abs(((t * 3.0) % 1.0) * 2 - 1))
    s = np.tanh(2 * np.sin(2 * np.pi * np.cumsum(f) / SR))
    return lp(s, 3000) * 0.35


def metal_clang(f=180, dur=2.0):
    t = tt(dur)
    s = sum(np.sin(2 * np.pi * f * r * t) * np.exp(-t * d) for r, d in ((1, 1.6), (2.76, 2.4), (5.4, 3.5), (8.93, 5), (13.3, 7)))
    return (s / 3 + noise(len(t)) * np.exp(-t * 40) * 0.5) * 0.7


def cash_register():
    t = tt(0.9)
    ding = bell(2100, 0.9, 2.0, 1.2) * 0.8 + bell(2800, 0.9, 2.0, 0.6) * 0.4
    drawer = lp(noise(len(t)), 2000) * np.exp(-np.maximum(t - 0.25, 0) * 25) * (t > 0.25) * 0.5
    return ding + drawer


def coins(n=8):
    out = np.zeros(int(1.2 * SR))
    for i in range(n):
        f = 3000 + Rand.rng.random() * 2500
        s = bell(f, 0.25, 2.3, 0.8) * 0.3
        o = int((0.05 + i * 0.07 + Rand.rng.random() * 0.03) * SR)
        out[o:o + len(s)] += s[:len(out) - o]
    return out


def chime3(base=72):
    out = np.zeros(int(2.2 * SR))
    for i, iv in enumerate((7, 4, 0)):
        s = vibes(midi(base + iv), 1.4)
        o = int(i * 0.35 * SR)
        out[o:o + len(s)] += s[:len(out) - o]
    return out


def phone_ring():
    t = tt(1.6)
    s = np.sin(2 * np.pi * 440 * t) + np.sin(2 * np.pi * 480 * t)
    gate = (np.sin(2 * np.pi * 20 * t) > 0) * (t < 1.0)
    return s * gate * 0.12


def typewriter(n=6):
    out = np.zeros(int(1.0 * SR))
    for i in range(n):
        c = hp(noise(400), 2000) * np.exp(-np.arange(400) / 60) * 0.4
        o = int((i * 0.11 + Rand.rng.random() * 0.04) * SR)
        out[o:o + 400] += c
    return out


def clock_tick():
    t = tt(0.05)
    return bp(noise(len(t)), 2500, 6000) * np.exp(-t * 120) * 0.5


def glass_clink():
    return bell(3300, 0.5, 2.71, 1.0) * 0.25 + bell(4100, 0.5, 2.3, 0.6) * 0.12


def foghorn(dur=2.5):
    t = tt(dur)
    s = saw(82, t) + saw(82.6, t) * 0.8
    return lp(s, 500) * adsr(len(t), 0.3, 0.2, 0.9, 0.6) * 0.5


def gull():
    t = tt(0.7)
    f = 1700 + 900 * np.sin(np.pi * t / 0.7) - 400 * t
    return np.sin(2 * np.pi * np.cumsum(f) / SR + 2 * np.sin(2 * np.pi * 30 * t)) * adsr(len(t), 0.03, 0.1, 0.7, 0.2) * 0.12


def bird():
    t = tt(0.25)
    f = 3200 + 1500 * np.sin(2 * np.pi * 9 * t)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) * 0.07


def slot_ding():
    out = np.zeros(int(0.8 * SR))
    for i, n in enumerate((84, 88, 91)):
        s = bell(midi(n), 0.5, 2.0, 0.8) * 0.3
        o = int(i * 0.07 * SR)
        out[o:o + len(s)] += s[:len(out) - o]
    return out


def jet(dur):
    t = tt(dur)
    w = np.sin(2 * np.pi * np.cumsum(2400 + 300 * t / dur) / SR) * 0.05
    rumble = lp(noise(len(t)), 300) * 0.5
    return (w + rumble + bp(noise(len(t)), 800, 3000) * 0.15) * adsr(len(t), dur * 0.4, 0.1, 0.9, dur * 0.4)


def whoosh(dur=1.2, up=True):
    t = tt(dur)
    n = noise(len(t))
    out = np.zeros(len(t))
    steps = 24
    seg = len(t) // steps
    for i in range(steps):
        f = 300 + 4000 * ((i / steps) if up else (1 - i / steps))
        out[i * seg:(i + 1) * seg] = bp(n[i * seg:(i + 1) * seg + 200], f * 0.7, f * 1.3)[:seg]
    return out * np.sin(np.pi * t / dur) * 0.6


# whole-track ambience beds
def crowd_bed(n, level=1.0):
    out = np.zeros(n)
    for _ in range(6):
        lo = 250 + Rand.rng.random() * 300
        v = bp(noise(n), lo, lo * 4)
        env = lp(np.abs(noise(n)), 2.5) * 6
        out += v * np.clip(env, 0, 1)
    return out * 0.05 * level


def traffic_bed(n, level=1.0):
    out = lp(noise(n), 180) * 0.6 + lp(noise(n), 900) * 0.08
    for _ in range(n // (SR * 4)):
        c = whoosh(2.0, up=Rand.rng.random() < 0.5) * 0.4
        o = int(Rand.rng.random() * (n - len(c)))
        out[o:o + len(c)] += c
    return out * 0.08 * level


def rain_bed(n, level=1.0):
    return (hp(noise(n), 2000) * 0.15 + lp(noise(n), 600) * 0.1) * level


def water_bed(n, level=1.0):
    slow = 0.5 + 0.5 * np.sin(2 * np.pi * np.arange(n) / SR * 0.25)
    return lp(noise(n), 700) * (0.3 + 0.7 * slow) * 0.12 * level


def wind_bed(n, level=1.0):
    slow = lp(np.abs(noise(n)), 0.8) * 8
    return bp(noise(n), 200, 1200) * np.clip(slow, 0.2, 1.2) * 0.08 * level


def rumble_bed(n, level=1.0):
    return lp(noise(n), 90) * 0.5 * level


def hum_bed(n, f=60, level=1.0):
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 3 * t)) * 0.03 * level


# ------------------------------------------------------------------ track
class Track:
    def __init__(self, bpm, bars, beats_per_bar=4, loop=True, seconds=None, seed=1):
        Rand.seed(seed)
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bpb = beats_per_bar
        self.loop = loop
        self.n = int(round((seconds if seconds else bars * beats_per_bar * self.beat) * SR))
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)

    def add(self, sig, beat, pan=0.0, gain=1.0, at_seconds=None):
        s = int(round((at_seconds if at_seconds is not None else beat * self.beat) * SR))
        lg = gain * np.sqrt(0.5 * (1 - pan))
        rg = gain * np.sqrt(0.5 * (1 + pan))
        if self.loop:
            s %= self.n
            idx = (np.arange(len(sig)) + s) % self.n
            np.add.at(self.L, idx, sig * lg)
            np.add.at(self.R, idx, sig * rg)
        else:
            e = min(self.n, s + len(sig))
            if e > s:
                self.L[s:e] += sig[:e - s] * lg
                self.R[s:e] += sig[:e - s] * rg

    def bed(self, sig, gain=1.0, width=0.6):
        """Full-length ambience, decorrelated a little between ears."""
        sig = sig[: self.n]
        shift = int(SR * 0.37)
        self.L += sig * gain
        self.R += np.roll(sig, shift) * gain * (1 - width * 0.3)

    def chord(self, inst, notes, beat, dur_beats, gain=0.2, spread=0.5, strum=0.0):
        for j, n in enumerate(notes):
            pan = -spread + 2 * spread * j / max(1, len(notes) - 1)
            self.add(inst(midi(n), dur_beats * self.beat + 0.15), beat + j * strum, pan, gain)

    def _filt(self, x, fn):
        """Apply an IIR filter; loops are pre-rolled with their own tail so the seam stays clean."""
        if not self.loop:
            return fn(x)
        pad = min(len(x), SR * 2)
        y = fn(np.concatenate([x[-pad:], x, x[:pad]]))
        return y[pad:pad + len(x)]

    def _balance(self, x, bass_target, high_target):
        """Tilt EQ toward a target share of energy below 150 Hz and above 3 kHz."""
        # zero-phase filters so the bands add back up exactly (no hidden cancellation)
        lo_sos = butter(4, 150 / (SR / 2), output="sos")
        hi_sos = butter(2, 3000 / (SR / 2), btype="high", output="sos")
        low = self._filt(x, lambda v: sosfiltfilt(lo_sos, v))
        rest = x - low
        high = self._filt(rest, lambda v: sosfiltfilt(hi_sos, v))
        mid = rest - high
        e_low, e_mid, e_high = (np.sum(b ** 2) + 1e-12 for b in (low, mid, high))
        tot = e_low + e_mid + e_high
        g_low = np.sqrt(min(1.0, bass_target * (e_mid + e_high) / max(e_low * (1 - bass_target), 1e-12)))
        g_low = max(g_low, 0.12)
        g_high = 1.0
        if e_high / tot < high_target:
            g_high = min(3.0, np.sqrt(high_target * tot / max(e_high * (1 - high_target), 1e-12)))
        elif e_high / tot > 0.3:
            g_high = np.sqrt(0.3 / (e_high / tot))
        return low * g_low + mid + high * g_high

    def master(self, target_rms_db=-17.0, reverb=0.18, low_cut=40, air=0.25, bass_target=0.28, high_target=0.04):
        L, R = self.L, self.R
        if reverb > 0:
            for d, g in ((1557, 0.5), (2213, 0.42), (3307, 0.33), (4931, 0.25), (6007, 0.18)):
                L = L + g * reverb * np.roll(self.L, d)
                R = R + g * reverb * np.roll(self.R, d + 97)
        L = self._filt(L, lambda v: hp(v, low_cut))
        R = self._filt(R, lambda v: hp(v, low_cut))
        if bass_target is not None:
            L = self._balance(L, bass_target, high_target)
            R = self._balance(R, bass_target, high_target)
        if air > 0:
            L = L + air * self._filt(L, lambda v: hp(v, 2500, 1))
            R = R + air * self._filt(R, lambda v: hp(v, 2500, 1))
        st = np.stack([L, R], axis=1)
        rms = np.sqrt(np.mean(st ** 2)) + 1e-9
        st *= 10 ** (target_rms_db / 20) / rms
        st = np.tanh(st * 1.1) / 1.1
        peak = np.max(np.abs(st))
        if peak > 0.92:
            st *= 0.92 / peak
        if not self.loop:
            fade = int(0.05 * SR)
            st[-fade:] *= np.linspace(1, 0, fade)[:, None]
        return st
