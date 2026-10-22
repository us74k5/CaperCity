"""Synthesizes the Caper City background theme: a moody 96 BPM street-crime groove in A minor.

Everything is generated from code (no samples), so the track is 100% ours.
Usage: python3 make_theme.py out.wav
The loop is sample-exact: note tails that run past the end wrap to the start, so it repeats seamlessly.
"""
import sys
import numpy as np
from scipy.signal import lfilter, butter

SR = 44100
BPM = 96
BEAT = 60.0 / BPM
BARS = 16
LEN = int(round(BARS * 4 * BEAT * SR))
rng = np.random.default_rng(7)

L = np.zeros(LEN)
R = np.zeros(LEN)


def add(sig, start_beat, pan=0.0, gain=1.0):
    """Mix a mono signal in at a beat position; wraps around the loop end."""
    s = int(round(start_beat * BEAT * SR)) % LEN
    n = len(sig)
    lg = gain * np.sqrt(0.5 * (1 - pan))
    rg = gain * np.sqrt(0.5 * (1 + pan))
    idx = (np.arange(n) + s) % LEN
    np.add.at(L, idx, sig * lg)
    np.add.at(R, idx, sig * rg)


def t_(dur):
    return np.arange(int(dur * SR)) / SR


def env(n, a=0.005, d=0.1, s=0.6, r=0.1, dur=None):
    total = n
    out = np.ones(total)
    ai = max(1, int(a * SR)); di = max(1, int(d * SR)); ri = max(1, int(r * SR))
    out[:ai] = np.linspace(0, 1, ai)
    out[ai:ai + di] = np.linspace(1, s, min(di, max(0, total - ai)))[: max(0, min(di, total - ai))]
    out[ai + di:] = s
    out[-ri:] *= np.linspace(1, 0, ri)
    return out


def lowpass(x, cutoff, order=2):
    b, a = butter(order, min(cutoff, SR * 0.45) / (SR / 2))
    return lfilter(b, a, x)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


# ---------------------------------------------------------------- drums
def kick():
    t = t_(0.45)
    f = 50 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 7.5) * 0.95


def snare():
    t = t_(0.3)
    noise = lowpass(rng.standard_normal(len(t)), 7000) * np.exp(-t * 16)
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 22)
    return (noise * 0.55 + body * 0.45) * 0.8


def hat(open_=False):
    t = t_(0.25 if open_ else 0.06)
    n = rng.standard_normal(len(t))
    n = n - lowpass(n, 7000)
    return n * np.exp(-t * (14 if open_ else 70)) * 0.22


K, S = kick(), snare()
for bar in range(BARS):
    b0 = bar * 4
    fill = bar % 4 == 3
    for kb in ([0, 1.75, 2.5] if bar % 2 else [0, 1.5, 2.5, 3.25]):
        add(K, b0 + kb, 0, 0.55)
    add(S, b0 + 1, 0.05, 0.85)
    add(S, b0 + 3, 0.05, 0.85)
    if fill:
        add(S, b0 + 3.75, 0.1, 0.35)
        add(S, b0 + 3.5, -0.1, 0.25)
    for i in range(8):
        swing = 0.06 if i % 2 else 0.0
        add(hat(open_=(i == 7 and bar % 2 == 1)), b0 + i * 0.5 + swing, 0.35, 1.8 if i % 2 == 0 else 1.25)

# ---------------------------------------------------------------- harmony
# Am9 - Fmaj7 - Dm9 - E7(b9) , one bar each, 4x
CHORDS = [
    [57, 60, 64, 67, 71],   # Am9 (A C E G B)
    [53, 57, 60, 64, 67],   # Fmaj9
    [50, 57, 60, 64, 65],   # Dm9-ish
    [52, 56, 59, 62, 65],   # E7b9
]
ROOTS = [45, 41, 38, 40]


def epiano(freq, dur):
    t = t_(dur)
    mod = np.sin(2 * np.pi * freq * 2 * t) * (1.2 * np.exp(-t * 3))
    tone = np.sin(2 * np.pi * freq * t + mod)
    tone += 0.15 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t * 6)
    trem = 1 + 0.12 * np.sin(2 * np.pi * 4.5 * t)
    return tone * np.exp(-t * 0.9) * trem * env(len(t), 0.004, 0.2, 0.7, 0.15)


for bar in range(BARS):
    ch = CHORDS[bar % 4]
    # stabs on 1 and the "and" of 2, a little rhythmic push
    for pos, dur, g in ((0, 1.4, 0.27), (1.5, 0.45, 0.18), (2.75, 1.1, 0.21)):
        for j, n in enumerate(ch[1:]):
            add(epiano(midi(n), dur * BEAT + 0.2), bar * 4 + pos + j * 0.008, -0.3 + 0.15 * j, g)


# ---------------------------------------------------------------- bass
def bass_note(freq, dur):
    t = t_(dur)
    saw = 2 * ((freq * t) % 1.0) - 1
    sub = np.sin(2 * np.pi * freq / 2 * t)
    pluck = np.exp(-t * 9)  # filter envelope: bright attack, dark sustain
    sig = (lowpass(saw, 1300) * pluck + lowpass(saw, 380) * (1 - pluck)) * 0.7 + sub * 0.5
    return sig * env(len(t), 0.004, 0.15, 0.75, 0.04)


BASS_RHYTHM = [(0, 0.75, 0), (0.75, 0.25, 12), (1.5, 0.5, 0), (2.5, 0.5, 7), (3.0, 0.5, 0), (3.5, 0.5, 10)]
for bar in range(BARS):
    r = ROOTS[bar % 4]
    for pos, dur, iv in BASS_RHYTHM:
        add(bass_note(midi(r + iv - 12), dur * BEAT * 0.95), bar * 4 + pos, 0, 0.3)


# ---------------------------------------------------------------- lead (second half only)
def lead(freq, dur):
    t = t_(dur)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t * 3, 0, 1)
    ph = 2 * np.pi * np.cumsum(freq * vib) / SR
    sq = np.tanh(3 * np.sin(ph)) * 0.6 + 0.4 * np.sin(2 * ph)
    return lowpass(sq, 2600) * env(len(t), 0.02, 0.2, 0.65, 0.12)


# A minor pentatonic phrase, call and answer
MELODY = [
    (0, 0.5, 76), (0.5, 0.5, 74), (1, 1.0, 72), (2.5, 0.5, 69), (3, 1, 72),
    (4, 0.5, 72), (4.5, 0.5, 74), (5, 1.5, 76), (7, 0.5, 79), (7.5, 0.5, 76),
    (8, 1.0, 74), (9, 0.5, 72), (9.5, 0.5, 74), (10, 1.5, 69), (12, 0.5, 71),
    (12.5, 0.5, 72), (13, 0.5, 74), (13.5, 0.5, 71), (14, 2.0, 68),
]
for rep in range(2):
    for pos, dur, n in MELODY:
        add(lead(midi(n), dur * BEAT * 0.92), 32 + rep * 16 + pos, 0.2, 0.42)

# ---------------------------------------------------------------- city ambience + mix
amb = lowpass(rng.standard_normal(LEN), 600) * 0.02
L += amb
R += np.roll(amb, 4000)


def simple_reverb(x, mix=0.18):
    out = x.copy()
    for delay, g in ((1557, 0.5), (2213, 0.42), (3307, 0.33), (4931, 0.25)):
        out += g * mix * np.roll(x, delay)
    return out


L, R = simple_reverb(L), simple_reverb(R)
# clean up the low end (phone speakers can't play it anyway) and add a little air
hp_b, hp_a = butter(2, 45 / (SR / 2), btype="high")
L, R = lfilter(hp_b, hp_a, L), lfilter(hp_b, hp_a, R)
sh_b, sh_a = butter(1, 2500 / (SR / 2), btype="high")
L, R = L + 0.35 * lfilter(sh_b, sh_a, L), R + 0.35 * lfilter(sh_b, sh_a, R)
mixed = np.stack([L, R], axis=1)
mixed = np.tanh(mixed * 1.2)
mixed /= np.max(np.abs(mixed)) * 1.12
from scipy.io import wavfile
wavfile.write(sys.argv[1], SR, (mixed * 32767).astype(np.int16))
print("wrote %s: %.1f s loop, %d bars at %d BPM" % (sys.argv[1], LEN / SR, BARS, BPM))
