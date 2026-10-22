"""Every piece of Caper City music: one recipe per scene loop and per event sting.

LOOPS: scene name -> function returning a mastered stereo array (seamless loop)
STINGS: event name -> function returning a mastered stereo array (one-shot)
"""
import numpy as np
from synth import *  # noqa: F401,F403
from synth import SR, Track, midi, Rand


# ------------------------------------------------------------------ helpers
def drums(tr, bars, kick_b=(0, 2), snare_b=(1, 3), hats=8, swing=0.0, hat_gain=0.7, open_on=(), kick_g=0.7,
          snare_g=0.6, snare_fn=None, hat_fn=None, start=0):
    sn = snare_fn or (lambda: snare())
    for bar in range(start, bars):
        b0 = bar * tr.bpb
        for k in kick_b:
            tr.add(kick(), b0 + k, 0, kick_g)
        for s in snare_b:
            tr.add(sn(), b0 + s, 0.05, snare_g)
        step = tr.bpb / hats if hats else 0
        for i in range(hats):
            sw = swing if i % 2 else 0.0
            h = hat_fn() if hat_fn else hat(open_=(i in open_on))
            tr.add(h, b0 + i * step + sw, 0.35, hat_gain * (1.0 if i % 2 == 0 else 0.7))


def bassline(tr, roots, rhythm, inst=bass_saw, gain=0.5, octave=-12):
    """rhythm: list of (beat_in_bar, dur_beats, interval)."""
    for bar, r in enumerate(roots):
        for pos, dur, iv in rhythm:
            tr.add(inst(midi(r + iv + octave), dur * tr.beat * 0.95), bar * tr.bpb + pos, 0, gain)


def comp(tr, chords, rhythm, inst=epiano, gain=0.18, spread=0.5, strum=0.0):
    """rhythm: list of (beat_in_bar, dur_beats)."""
    for bar, ch in enumerate(chords):
        for pos, dur in rhythm:
            tr.chord(inst, ch, bar * tr.bpb + pos, dur, gain, spread, strum)


def melody(tr, notes, inst, gain=0.3, pan=0.15, offset=0.0, legato=0.92):
    for pos, dur, n in notes:
        if n is None:
            continue
        tr.add(inst(midi(n), dur * tr.beat * legato), offset + pos, pan, gain)


def walking(tr, roots, gain=0.6, inst=bass_upright):
    """Quarter-note walking bass: root, third/fifth, approach."""
    for bar, r in enumerate(roots):
        nxt = roots[(bar + 1) % len(roots)]
        line = [r, r + 4 if bar % 2 == 0 else r + 3, r + 7, nxt - 1 if nxt > r else nxt + 1]
        for i, n in enumerate(line[: tr.bpb]):
            tr.add(inst(midi(n - 12), tr.beat * 0.9), bar * tr.bpb + i, 0, gain)


def sprinkle(tr, fn, count, gain=0.3, pan_range=0.7):
    for _ in range(count):
        tr.add(fn(), 0, (Rand.rng.random() * 2 - 1) * pan_range, gain, at_seconds=Rand.rng.random() * tr.n / SR)


# chord shapes (MIDI)
def ch(root, kind):
    shapes = {"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "m9": [0, 3, 7, 10, 14],
              "maj9": [0, 4, 7, 11, 14], "7b9": [0, 4, 7, 10, 13], "m": [0, 3, 7], "maj": [0, 4, 7], "6": [0, 4, 7, 9],
              "m6": [0, 3, 7, 9], "dim": [0, 3, 6, 9], "sus": [0, 5, 7], "add9": [0, 4, 7, 14]}
    return [root + i for i in shapes[kind]]


# ------------------------------------------------------------------ scene loops
def menu():
    tr = Track(78, 8, seed=11)
    prog = [ch(62, "m9"), ch(58, "maj7"), ch(55, "m9"), ch(57, "7b9")] * 2
    roots = [38, 34, 31, 33] * 2
    for bar, c in enumerate(prog):
        tr.add(pad([midi(n) for n in c], 4 * tr.beat + 0.5, 1200, 0.8), bar * 4, 0, 0.22)
    comp(tr, prog, [(0, 1.5), (2.5, 1.0)], epiano, 0.12)
    bassline(tr, roots, [(0, 2.5, 0), (2.5, 1.5, 7)], bass_upright, 0.55, 0)
    for bar in range(8):
        tr.add(kick(0.6), bar * 4, 0, 0.35)
        tr.add(brush(), bar * 4 + 1, 0.1, 0.6)
        tr.add(brush(), bar * 4 + 3, 0.1, 0.6)
        for i in range(4):
            tr.add(brush(0.12), bar * 4 + i + 0.5, -0.2, 0.25)
    mel = [(0, 1.5, 74), (1.5, 0.5, 72), (2, 2, 69), (4, 1, 70), (5, 1, 69), (6, 2, 67), (8, 1.5, 65), (9.5, 0.5, 67),
           (10, 1, 69), (11, 1, 70), (12, 3, 69), (16, 1.5, 74), (17.5, 0.5, 76), (18, 2, 77), (20, 1, 76), (21, 1, 74),
           (22, 2, 70), (24, 1.5, 69), (25.5, 0.5, 67), (26, 1.5, 65), (28, 3.5, 64)]
    melody(tr, mel, muted_trumpet, 0.32, 0.2)
    tr.bed(rain_bed(tr.n), 0.5)
    tr.add(siren(5.0, "wail", 550, 900) * 0.25, 20, 0.8, 0.5)
    return tr.master(-18, 0.28)


def lobby():
    tr = Track(104, 8, seed=12)
    prog = [ch(60, "maj7"), ch(57, "m7"), ch(62, "m7"), ch(55, "7")] * 2
    comp(tr, prog, [(0, 0.75), (1.5, 0.5), (2.5, 0.75), (3.5, 0.5)], epiano, 0.13)
    bassline(tr, [48, 45, 50, 43] * 2, [(0, 1.5, 0), (1.5, 0.5, 7), (2, 1.5, 7), (3.5, 0.5, 12)], bass_upright, 0.55, 0)
    for bar in range(8):
        for p in (0, 1.5, 2.5):
            tr.add(rim(), bar * 4 + p + (0.75 if p == 2.5 and bar % 2 else 0), -0.3, 0.5)
        for i in range(8):
            tr.add(shaker(), bar * 4 + i * 0.5, 0.4, 0.8)
        tr.add(kick(0.5), bar * 4, 0, 0.45)
        tr.add(kick(0.5), bar * 4 + 2.5, 0, 0.35)
    mel = [(0, 1, 76), (1, 1, 79), (2, 2, 81), (4, 1, 79), (5, 1, 76), (6, 2, 74), (8, 1, 72), (9, 1, 74), (10, 2, 76),
           (12, 3, 79), (16, 1, 81), (17, 1, 79), (18, 2, 76), (20, 1, 74), (21, 1, 72), (22, 2, 71), (24, 4, 72)]
    melody(tr, mel, vibes, 0.28, 0.25)
    return tr.master(-18)


def bank():
    tr = Track(112, 8, seed=13)
    prog = [ch(65, "maj7"), ch(62, "m7"), ch(67, "m7"), ch(60, "7")] * 2
    comp(tr, prog, [(0, 0.5), (1.5, 0.5), (2.5, 0.5), (3, 0.5)], epiano, 0.11, 0.4)
    for bar, r in enumerate([41, 38, 43, 36] * 2):
        for pos, iv in ((0, 0), (1.5, 7), (2, 7), (3.5, 0)):
            tr.add(bass_upright(midi(r + iv), tr.beat * 0.9), bar * 4 + pos, 0, 0.5)
    for bar in range(8):
        tr.add(kick(0.4), bar * 4, 0, 0.35)
        tr.add(kick(0.4), bar * 4 + 2.5, 0, 0.3)
        for i in range(8):
            tr.add(brush(0.1), bar * 4 + i * 0.5, 0.3, 0.45 if i % 2 else 0.6)
        tr.add(rim(), bar * 4 + 1.5, -0.3, 0.35)
    mel = [(0, 0.5, 77), (0.5, 0.5, 76), (1, 2, 74), (4, 0.5, 72), (4.5, 0.5, 74), (5, 2, 77), (8, 1, 79), (9, 1, 77),
           (10, 2, 74), (12, 3, 72), (16, 0.5, 81), (16.5, 0.5, 79), (17, 2, 77), (20, 1, 76), (21, 1, 74),
           (22, 2, 72), (24, 4, 77)]
    melody(tr, mel, vibes, 0.26, -0.2)
    tr.bed(crowd_bed(tr.n, 0.6), 0.9)
    tr.add(typewriter(7), 3, 0.6, 0.5)
    tr.add(typewriter(5), 19, 0.6, 0.45)
    tr.add(phone_ring(), 13, -0.7, 0.35)
    tr.add(bell(midi(88), 1.2, 2.0, 0.6), 27, 0.5, 0.25)
    return tr.master(-18.5, 0.25)


def hotel():
    tr = Track(120, 8, seed=14)
    prog = [ch(58, "maj7"), ch(55, "7"), ch(60, "m7"), ch(53, "7")] * 2
    walking(tr, [46, 43, 48, 41] * 2, 0.6)
    comp(tr, prog, [(1, 0.5), (2.5, 0.5)], epiano, 0.11)
    for bar in range(8):
        for i in range(4):
            tr.add(hat(open_=False, dur=0.15), bar * 4 + i, 0.4, 0.7)
            if i % 2:
                tr.add(hat(dur=0.08), bar * 4 + i + 0.66, 0.4, 0.5)
        tr.add(brush(), bar * 4 + 1, 0.1, 0.5)
        tr.add(brush(), bar * 4 + 3, 0.1, 0.5)
    mel = [(0, 0.66, 74), (0.66, 0.34, 72), (1, 1, 70), (2, 2, 65), (4, 0.66, 67), (4.66, 0.34, 69), (5, 1, 70),
           (6, 2, 74), (8, 1, 75), (9, 1, 74), (10, 1, 72), (11, 1, 70), (12, 3, 69), (16, 1, 77), (17, 1, 74),
           (18, 2, 70), (20, 1, 72), (21, 1, 69), (22, 2, 65), (24, 4, 70)]
    melody(tr, mel, vibes, 0.3, 0.2)
    tr.add(chime3(84), 0, 0.5, 0.15)
    tr.bed(crowd_bed(tr.n, 0.3), 0.6)
    return tr.master(-18)


def casino():
    tr = Track(126, 8, seed=15)
    prog = [ch(63, "6"), ch(60, "m7"), ch(65, "m7"), ch(58, "7")] * 2
    walking(tr, [51, 48, 53, 46] * 2, 0.6)
    comp(tr, prog, [(0, 0.5), (1.5, 0.5), (3, 0.75)], organ, 0.12)
    for bar in range(8):
        tr.add(kick(0.6), bar * 4, 0, 0.5)
        tr.add(kick(0.6), bar * 4 + 2, 0, 0.45)
        tr.add(snare(), bar * 4 + 1, 0.05, 0.4)
        tr.add(snare(), bar * 4 + 3, 0.05, 0.4)
        for i in range(4):
            tr.add(hat(dur=0.12), bar * 4 + i, 0.4, 0.6)
            tr.add(hat(dur=0.06), bar * 4 + i + 0.66, 0.4, 0.4)
        if bar % 2 == 1:
            for p in (3.5,):
                tr.chord(brass, [n + 12 for n in prog[bar][:3]], bar * 4 + p, 0.4, 0.13, 0.4)
    mel = [(0, 1, 75), (1, 1, 79), (2, 1, 82), (3, 1, 84), (4, 3, 82), (8, 1, 80), (9, 1, 79), (10, 2, 77),
           (12, 3, 75), (16, 1, 75), (17, 1, 77), (18, 1, 79), (19, 1, 82), (20, 3, 84), (24, 1, 82), (25, 1, 79),
           (26, 2, 77), (28, 3, 75)]
    melody(tr, mel, brass, 0.2, 0.2)
    tr.bed(crowd_bed(tr.n, 1.0), 1.0)
    sprinkle(tr, slot_ding, 7, 0.35)
    sprinkle(tr, lambda: coins(5), 3, 0.3)
    return tr.master(-17)


def pub():
    tr = Track(88, 8, seed=16)
    roots = [40, 40, 45, 40, 47, 45, 40, 47]
    chords = [ch(r + 12, "7") for r in roots]
    shuffle = [(0, 0.66, 0), (0.66, 0.34, 0), (1, 0.66, 4), (1.66, 0.34, 4), (2, 0.66, 7), (2.66, 0.34, 7), (3, 0.66, 9), (3.66, 0.34, 7)]
    bassline(tr, roots, shuffle, bass_upright, 0.55, 0)
    comp(tr, chords, [(0.66, 0.3), (1.66, 0.3), (2.66, 0.3), (3.66, 0.3)], organ, 0.1)
    for bar in range(8):
        tr.add(kick(0.6), bar * 4, 0, 0.55)
        tr.add(kick(0.6), bar * 4 + 2, 0, 0.45)
        tr.add(snare(), bar * 4 + 1, 0.05, 0.5)
        tr.add(snare(), bar * 4 + 3, 0.05, 0.5)
        for i in range(4):
            tr.add(hat(dur=0.1), bar * 4 + i, 0.4, 0.55)
            tr.add(hat(dur=0.06), bar * 4 + i + 0.66, 0.4, 0.4)
    licks = [(0.66, 0.34, 76), (1, 1.5, 79), (3, 0.5, 76), (3.5, 0.5, 74), (4, 2, 71), (8.66, 0.34, 79), (9, 1, 81),
             (10, 1, 79), (11, 1, 76), (12, 3, 76), (16.66, 0.34, 83), (17, 2, 83), (19, 1, 81), (20, 1, 79),
             (21, 1, 76), (22, 2, 74), (24.66, 0.34, 76), (25, 1, 79), (26, 2, 76), (28, 3, 76)]
    melody(tr, licks, harmonica, 0.3, -0.2)
    tr.bed(crowd_bed(tr.n, 1.3), 1.0)
    sprinkle(tr, glass_clink, 6, 0.4)
    return tr.master(-17.5, 0.2)


def arms():
    tr = Track(92, 8, seed=17)
    for bar in range(8):
        for k in (0, 0.75, 2, 2.5):
            tr.add(kick(1.2), bar * 4 + k, 0, 0.7)
        tr.add(clap(), bar * 4 + 1, 0, 0.45)
        tr.add(metal_clang(160 + 20 * (bar % 3), 1.2), bar * 4 + 3, -0.3 + 0.2 * (bar % 4), 0.25)
        for i in range(16):
            if i % 4 != 0:
                tr.add(hat(dur=0.04), bar * 4 + i * 0.25, 0.4, 0.35)
    roots = [36, 36, 39, 34] * 2
    for bar, r in enumerate(roots):
        tr.add(bass_sub(midi(r - 12), 4 * tr.beat), bar * 4, 0, 0.55)
        for i, iv in enumerate((0, 0, 12, 0, 3, 0, 10, 0)):
            tr.add(bass_saw(midi(r + iv), tr.beat * 0.4, 1.4), bar * 4 + i * 0.5, 0, 0.32)
    ost = [(i * 0.5, 0.45, n) for i, n in enumerate([60, 63, 67, 63, 62, 63, 67, 70] * 8)]
    melody(tr, ost, lambda f, d: pluck(f, d + 0.2, 0.99, 0.6), 0.22, 0.4)
    tr.add(pad([midi(48), midi(51), midi(55)], 32 * tr.beat, 700, 2.0), 0, 0, 0.12)
    tr.bed(hum_bed(tr.n, 50), 1.0)
    return tr.master(-17, 0.2)


def car_dealer():
    tr = Track(112, 8, seed=18)
    roots = [43, 43, 48, 50] * 2
    chords = [ch(67, "add9"), ch(67, "add9"), ch(60, "maj7"), ch(62, "7")] * 2
    slap = [(0, 0.25, 0), (0.5, 0.25, 12), (0.75, 0.25, 0), (1.5, 0.25, 0), (2, 0.25, 12), (2.5, 0.25, 10), (3, 0.25, 7), (3.5, 0.25, 0)]
    bassline(tr, roots, slap, lambda f, d: bass_saw(f, d, 1.8), 0.45, 0)
    for bar in range(8):
        tr.add(kick(), bar * 4, 0, 0.6)
        tr.add(kick(), bar * 4 + 2.5, 0, 0.5)
        tr.add(clap(), bar * 4 + 1, 0, 0.55)
        tr.add(clap(), bar * 4 + 3, 0, 0.55)
        for i in range(8):
            tr.add(hat(open_=(i == 7)), bar * 4 + i * 0.5, 0.35, 0.6 if i % 2 == 0 else 0.4)
        tr.chord(brass, [n + 12 for n in chords[bar][:3]], bar * 4 + 1.5, 0.3, 0.12, 0.4)
        tr.chord(brass, [n + 12 for n in chords[bar][:3]], bar * 4 + 3.5, 0.3, 0.1, 0.4)
    comp(tr, chords, [(0, 1.0), (2, 0.5)], epiano, 0.1)
    return tr.master(-16.5)


def print_shop():
    tr = Track(100, 8, seed=19)
    for bar in range(8):
        for i in range(16):
            tr.add(clock_tick(), bar * 4 + i * 0.25, 0.5 if i % 2 else -0.5, 0.5 if i % 4 == 0 else 0.3)
        tr.add(kick(0.7), bar * 4, 0, 0.5)
        tr.add(kick(0.7), bar * 4 + 2.75, 0, 0.4)
        tr.add(rim(), bar * 4 + 1, 0, 0.4)
        tr.add(rim(), bar * 4 + 3, 0, 0.4)
        tr.add(metal_clang(400, 0.5) * 0.4, bar * 4 + 2, 0.2, 0.2)
    bassline(tr, [45, 45, 41, 43] * 2, [(0, 0.75, 0), (1, 0.5, 0), (2, 0.75, 7), (3.5, 0.5, 5)], bass_saw, 0.45, 0)
    mot = [(0, 0.5, 69), (0.5, 0.5, 72), (1, 0.5, 76), (2, 1, 74), (4, 0.5, 69), (4.5, 0.5, 72), (5, 0.5, 77), (6, 1, 76)]
    for rep in range(4):
        melody(tr, mot, vibes, 0.22, -0.3, offset=rep * 8)
    sprinkle(tr, lambda: typewriter(6), 4, 0.4)
    return tr.master(-17.5)


def subway():
    tr = Track(84, 8, seed=20)
    prog = [ch(53, "m9"), ch(49, "maj7"), ch(51, "sus"), ch(48, "7")] * 2
    for bar, c in enumerate(prog):
        tr.add(pad([midi(n) for n in c], 4 * tr.beat + 0.6, 900, 1.0), bar * 4, 0, 0.24)
    for bar in range(8):
        tr.add(kick(0.5), bar * 4, 0, 0.45)
        tr.add(snare(160, 0.3, 3000), bar * 4 + 2, 0.1, 0.3)
        tr.add(hat(dur=0.05), bar * 4 + 1.5, 0.5, 0.35)
        tr.add(hat(dur=0.05), bar * 4 + 3.5, 0.5, 0.35)
    bassline(tr, [41, 37, 39, 36] * 2, [(0, 3, 0)], bass_sub, 0.5, 0)
    tr.add(chime3(76), 4, 0.3, 0.2)
    tr.bed(rumble_bed(tr.n), 0.9)
    tr.add(whoosh(4.0, True) * 0.8, 14, -0.5, 0.6)
    tr.add(whoosh(4.0, False) * 0.8, 17, 0.5, 0.6)
    return tr.master(-18, 0.4)


def police():
    tr = Track(100, 8, seed=21)
    prog = [ch(55, "m"), ch(55, "m"), ch(51, "maj"), ch(50, "7")] * 2
    for bar, c in enumerate(prog):
        tr.add(strings([midi(n) for n in c], 4 * tr.beat + 0.3, 2000, 0.4), bar * 4, 0, 0.2)
        for i in range(8):
            tr.add(bass_saw(midi(c[0] - 12), tr.beat * 0.4, 0.7), bar * 4 + i * 0.5, 0, 0.35)
        tr.add(kick(0.8), bar * 4, 0, 0.5)
        tr.add(kick(0.8), bar * 4 + 2.5, 0, 0.4)
        tr.add(snare(200, 0.2, 5000), bar * 4 + 3, 0.1, 0.3)
        for i in range(16):
            tr.add(clock_tick(), bar * 4 + i * 0.25, 0.4, 0.4 if i % 4 == 0 else 0.22)
    tr.add(phone_ring(), 6, -0.6, 0.3)
    tr.add(phone_ring(), 22, 0.6, 0.25)
    tr.add(typewriter(8), 11, 0.5, 0.45)
    tr.bed(crowd_bed(tr.n, 0.4), 0.7)
    return tr.master(-17.5)


def station():
    tr = Track(104, 8, seed=22)
    prog = [ch(62, "maj"), ch(57, "maj"), ch(59, "m"), ch(55, "maj")] * 2
    for bar, c in enumerate(prog):
        for pos in (0, 1, 1.5, 2.5, 3):
            tr.chord(lambda f, d: pluck(f, d + 0.4, 0.996, 0.7), [n - 12 for n in c] + [c[0]], bar * 4 + pos, 0.5, 0.12, 0.5, 0.015)
    bassline(tr, [50, 45, 47, 43] * 2, [(0, 1.5, 0), (1.5, 0.5, 7), (2, 1.5, 0), (3.5, 0.5, 7)], bass_upright, 0.5, -12)
    for bar in range(8):
        tr.add(kick(0.6), bar * 4, 0, 0.45)
        tr.add(kick(0.6), bar * 4 + 2, 0, 0.4)
        tr.add(snare(), bar * 4 + 1, 0.05, 0.3)
        tr.add(snare(), bar * 4 + 3, 0.05, 0.3)
        for i in range(8):
            tr.add(shaker(), bar * 4 + i * 0.5, 0.4, 0.8)
    mel = [(0, 1, 74), (1, 1, 76), (2, 2, 78), (4, 1, 76), (5, 1, 74), (6, 2, 73), (8, 1.5, 71), (9.5, 0.5, 73),
           (10, 2, 74), (12, 3, 71), (16, 1, 74), (17, 1, 78), (18, 2, 81), (20, 1, 79), (21, 1, 78), (22, 2, 76), (24, 4, 74)]
    melody(tr, mel, whistle, 0.25, 0.25)
    tr.add(chime3(72), 12, -0.4, 0.22)
    tr.bed(rumble_bed(tr.n, 0.7), 0.8)
    tr.bed(crowd_bed(tr.n, 0.5), 0.7)
    return tr.master(-17.5)


def playground():
    tr = Track(116, 8, seed=23)
    prog = [ch(60, "maj"), ch(65, "maj"), ch(67, "maj"), ch(60, "maj")] * 2
    for bar, c in enumerate(prog):
        for pos in (0, 0.5, 1.5, 2, 3):
            tr.chord(lambda f, d: pluck(f, d + 0.2, 0.993, 1.0), c, bar * 4 + pos, 0.4, 0.11, 0.4, 0.012)
    bassline(tr, [48, 53, 55, 48] * 2, [(0, 1, 0), (2, 1, 7)], bass_upright, 0.4, 0)
    for bar in range(8):
        tr.add(kick(0.4), bar * 4, 0, 0.35)
        tr.add(clap(), bar * 4 + 2, 0, 0.25)
        for i in range(8):
            tr.add(shaker(), bar * 4 + i * 0.5, 0.4, 0.7)
    mel = [(0, 0.5, 76), (0.5, 0.5, 79), (1, 1, 84), (2, 0.5, 83), (2.5, 0.5, 81), (3, 1, 79), (4, 1, 77), (5, 1, 81),
           (6, 2, 84), (8, 0.5, 83), (8.5, 0.5, 81), (9, 1, 79), (10, 2, 74), (12, 3, 72)]
    melody(tr, mel, music_box, 0.4, 0.3)
    melody(tr, mel, music_box, 0.4, -0.3, offset=16)
    sprinkle(tr, bird, 12, 0.6)
    tr.bed(wind_bed(tr.n, 0.4), 0.6)
    return tr.master(-18)


def supermarket():
    tr = Track(116, 8, seed=24)
    prog = [ch(56, "maj7"), ch(53, "m7"), ch(58, "m7"), ch(51, "7")] * 2
    comp(tr, prog, [(0, 0.5), (1, 0.5), (2, 0.5), (3, 0.5)], epiano, 0.1)
    for bar, c in enumerate(prog):
        tr.add(strings([midi(n + 12) for n in c[:3]], 4 * tr.beat, 3000, 0.4), bar * 4, 0, 0.1)
    bassline(tr, [44, 41, 46, 39] * 2, [(0, 1.5, 0), (1.5, 0.5, 7), (2, 1.5, 7), (3.5, 0.5, 0)], bass_upright, 0.5, 0)
    for bar in range(8):
        tr.add(rim(), bar * 4 + 1.5, -0.3, 0.35)
        tr.add(kick(0.4), bar * 4, 0, 0.4)
        tr.add(kick(0.4), bar * 4 + 2.5, 0, 0.3)
        for i in range(8):
            tr.add(shaker(), bar * 4 + i * 0.5, 0.4, 0.7)
    mel = [(0, 1, 80), (1, 1, 79), (2, 2, 75), (4, 1, 77), (5, 1, 79), (6, 2, 80), (8, 1, 82), (9, 1, 80), (10, 2, 77),
           (12, 3, 75), (16, 1, 80), (17, 1, 84), (18, 2, 82), (20, 1, 80), (21, 1, 79), (22, 2, 77), (24, 4, 80)]
    melody(tr, mel, vibes, 0.25, 0.2)
    tr.bed(crowd_bed(tr.n, 0.5), 0.7)
    sprinkle(tr, lambda: bell(midi(93), 0.3, 1.0, 0.2), 5, 0.25)
    return tr.master(-18)


def harbor():
    tr = Track(72, 8, seed=25)
    prog = [ch(57, "m9"), ch(53, "maj7"), ch(55, "sus"), ch(52, "m7")] * 2
    for bar, c in enumerate(prog):
        tr.add(pad([midi(n) for n in c], 4 * tr.beat + 0.5, 1000, 1.2), bar * 4, 0, 0.22)
        for i, n in enumerate([c[0], c[-1], c[1], c[-1]]):
            tr.add(pluck(midi(n), 1.6, 0.997, 0.5), bar * 4 + i, -0.3 + 0.2 * i, 0.16)
    bassline(tr, [45, 41, 43, 40] * 2, [(0, 3.5, 0)], bass_sub, 0.45, 0)
    for bar in range(8):
        tr.add(kick(0.4), bar * 4, 0, 0.3)
        tr.add(brush(), bar * 4 + 2, 0.1, 0.5)
    tr.add(foghorn(3.0), 6, -0.4, 0.5)
    sprinkle(tr, gull, 6, 0.6)
    tr.bed(water_bed(tr.n, 1.2), 1.0)
    tr.bed(wind_bed(tr.n, 0.8), 0.7)
    return tr.master(-18.5, 0.3)


def loan_shark():
    tr = Track(68, 8, seed=26)
    prog = [ch(60, "m9"), ch(56, "maj7"), ch(53, "m7"), ch(55, "7b9")] * 2
    for bar, c in enumerate(prog):
        tr.add(pad([midi(n) for n in c], 4 * tr.beat + 0.5, 800, 0.8), bar * 4, 0, 0.2)
    walking(tr, [48, 44, 41, 43] * 2, 0.55)
    for bar in range(8):
        tr.add(brush(), bar * 4 + 1, 0.1, 0.55)
        tr.add(brush(), bar * 4 + 3, 0.1, 0.55)
        for i in range(4):
            tr.add(clock_tick(), bar * 4 + i, -0.6, 0.35)
    mel = [(0, 1.5, 72), (1.5, 0.5, 70), (2, 2, 67), (4, 1, 68), (5, 1, 67), (6, 2, 63), (8, 2, 65), (10, 1, 63),
           (11, 1, 60), (12, 3, 62), (16, 1.5, 75), (17.5, 0.5, 74), (18, 2, 72), (20, 1, 71), (21, 1, 68),
           (22, 2, 67), (24, 4, 66)]
    melody(tr, mel, muted_trumpet, 0.3, 0.2)
    return tr.master(-18.5, 0.25)


def dept_store():
    tr = Track(120, 8, seed=27)
    prog = [ch(62, "maj7"), ch(59, "m7"), ch(64, "m7"), ch(57, "7")] * 2
    comp(tr, prog, [(0, 0.75), (1.5, 0.5), (2.5, 0.75)], epiano, 0.11)
    bassline(tr, [50, 47, 52, 45] * 2, [(0, 1.5, 0), (1.5, 0.5, 7), (2, 1, 7), (3, 1, 12)], bass_saw, 0.42, 0)
    drums(tr, 8, (0, 2.5), (1, 3), 8, 0.0, 0.55, (), 0.5, 0.35, lambda: clap())
    mel = [(0, 1, 78), (1, 1, 81), (2, 2, 83), (4, 1, 81), (5, 1, 78), (6, 2, 76), (8, 1, 74), (9, 1, 76), (10, 2, 78),
           (12, 3, 81), (16, 1, 83), (17, 1, 85), (18, 2, 86), (20, 1, 85), (21, 1, 83), (22, 2, 81), (24, 4, 78)]
    melody(tr, mel, vibes, 0.27, 0.2)
    tr.bed(crowd_bed(tr.n, 0.6), 0.8)
    return tr.master(-17.5)


def villa():
    tr = Track(90, 8, beats_per_bar=3, seed=28)
    prog = [ch(55, "maj7"), ch(60, "maj7"), ch(57, "m7"), ch(62, "7")] * 2
    for bar, c in enumerate(prog):
        tr.add(bass_upright(midi(c[0] - 12), tr.beat * 0.9), bar * 3, 0, 0.28)
        for pos in (1, 2):
            tr.chord(lambda f, d: pluck(f, d + 0.3, 0.995, 1.2), c[1:], bar * 3 + pos, 0.6, 0.11, 0.4)
        tr.add(strings([midi(n + 12) for n in c[:3]], 3 * tr.beat, 2600, 0.5), bar * 3, 0, 0.1)
    mel = [(0, 1, 79), (1, 1, 78), (2, 1, 76), (3, 2, 74), (5, 1, 76), (6, 1, 77), (7, 1, 76), (8, 1, 74),
           (9, 3, 72), (12, 1, 74), (13, 1, 76), (14, 1, 78), (15, 2, 79), (17, 1, 81), (18, 3, 79), (21, 3, 78)]
    melody(tr, mel, lambda f, d: pluck(f, d + 0.4, 0.997, 1.4), 0.3, 0.2)
    tr.bed(water_bed(tr.n, 0.5), 0.8)
    sprinkle(tr, bird, 6, 0.5)
    return tr.master(-18.5, 0.3)


def city_hall():
    tr = Track(96, 8, seed=29)
    prog = [ch(58, "maj"), ch(63, "maj"), ch(65, "maj"), ch(58, "maj")] * 2
    for bar, c in enumerate(prog):
        tr.add(strings([midi(n) for n in c], 4 * tr.beat + 0.2, 2600, 0.3), bar * 4, 0, 0.16)
        tr.add(timpani(midi(c[0] - 24), 1.0), bar * 4, 0, 0.5)
        tr.add(timpani(midi(c[0] - 17), 0.8), bar * 4 + 2, 0, 0.35)
        for i in range(4):
            tr.add(snare(220, 0.15, 6000), bar * 4 + i, 0.1, 0.25 if i % 2 else 0.4)
        if bar % 2 == 1:
            for i in range(4):
                tr.add(snare(220, 0.1, 6000), bar * 4 + 3 + i * 0.25, 0.1, 0.2)
    fan = [(0, 1.5, 70), (1.5, 0.5, 74), (2, 2, 77), (4, 1, 75), (5, 1, 74), (6, 2, 72), (8, 1.5, 77), (9.5, 0.5, 79),
           (10, 2, 81), (12, 3, 82), (16, 1.5, 70), (17.5, 0.5, 74), (18, 2, 77), (20, 1, 79), (21, 1, 77), (22, 2, 75),
           (24, 2, 74), (26, 2, 72), (28, 3, 70)]
    melody(tr, fan, brass, 0.25, 0.15)
    bassline(tr, [46, 51, 53, 46] * 2, [(0, 1, 0), (1, 1, 7), (2, 1, 0), (3, 1, 7)], bass_upright, 0.45, -12)
    return tr.master(-17.5, 0.3)


def airport():
    tr = Track(100, 8, seed=30)
    prog = [ch(64, "maj9"), ch(61, "m7"), ch(57, "maj9"), ch(59, "sus")] * 2
    for bar, c in enumerate(prog):
        tr.add(pad([midi(n) for n in c], 4 * tr.beat + 0.5, 1800, 0.9), bar * 4, 0, 0.2)
        for i in range(8):
            n = c[i % len(c)] + 12
            tr.add(bell(midi(n), 1.0, 2.0, 0.8), bar * 4 + i * 0.5, -0.4 + 0.1 * i, 0.08)
    bassline(tr, [40, 37, 45, 47] * 2, [(0, 2, 0), (2.5, 1.5, 7)], bass_sub, 0.4, 0)
    for bar in range(8):
        tr.add(kick(0.4), bar * 4, 0, 0.35)
        tr.add(kick(0.4), bar * 4 + 2.5, 0, 0.3)
        for i in range(8):
            tr.add(shaker(), bar * 4 + i * 0.5, 0.4, 0.5)
    tr.add(chime3(76), 2, -0.3, 0.25)
    tr.add(jet(10.0), 0, 0.3, 0.35, at_seconds=7)
    tr.bed(crowd_bed(tr.n, 0.4), 0.6)
    return tr.master(-18, 0.3)


def police_standoff():
    tr = Track(128, 8, seed=31)
    roots = [40, 40, 36, 38] * 2
    for bar, r in enumerate(roots):
        for i in range(16):
            tr.add(bass_saw(midi(r - 12 + (12 if i in (6, 14) else 0)), tr.beat * 0.2, 1.2), bar * 4 + i * 0.25, 0, 0.32)
        tr.add(kick(1.1), bar * 4, 0, 0.7)
        tr.add(kick(1.1), bar * 4 + 0.75, 0, 0.45)
        tr.add(kick(1.1), bar * 4 + 2, 0, 0.7)
        tr.add(snare(), bar * 4 + 1, 0.05, 0.55)
        tr.add(snare(), bar * 4 + 3, 0.05, 0.55)
        for i in range(8):
            tr.add(hat(dur=0.05), bar * 4 + i * 0.5 + 0.25, 0.4, 0.45)
        st = [r + 24, r + 27, r + 31] if bar % 4 < 2 else [r + 24, r + 28, r + 31]
        for i in range(4):
            tr.chord(lambda f, d: strings([f], d, 3500, 0.01), st, bar * 4 + i, 0.3, 0.09, 0.5)
        if bar % 4 == 3:
            for i in range(4):
                tr.add(tom(140 - i * 15), bar * 4 + 3 + i * 0.25, -0.3 + i * 0.2, 0.5)
    tr.add(siren(tr.n / SR, "wail"), 0, 0.5, 0.25)
    tr.add(pad([midi(52), midi(55), midi(59)], 32 * tr.beat, 600, 3), 0, 0, 0.1)
    return tr.master(-16)


def jail():
    tr = Track(64, 8, seed=32)
    roots = [43, 43, 48, 43, 50, 48, 43, 50]
    walking(tr, roots, 0.55)
    comp(tr, [ch(r + 12, "7") for r in roots], [(0, 1.5), (2, 1.5)], organ, 0.07)
    for bar in range(8):
        tr.add(brush(), bar * 4 + 1, 0.1, 0.5)
        tr.add(brush(), bar * 4 + 3, 0.1, 0.5)
        tr.add(kick(0.4), bar * 4, 0, 0.3)
    licks = [(0, 1, 74), (1, 2, 70), (3, 1, 67), (4, 3, 67), (8, 1, 77), (9, 1, 74), (10, 2, 72), (12, 3, 70),
             (16, 1, 79), (17, 2, 77), (19, 1, 74), (20, 3, 74), (24, 1, 72), (25, 1, 70), (26, 2, 67), (28, 3, 67)]
    melody(tr, licks, harmonica, 0.3, -0.2)
    sprinkle(tr, lambda: bell(midi(96), 0.2, 1.0, 0.1), 8, 0.08)
    return tr.master(-19, 0.35)


def victory():
    tr = Track(120, 8, seed=33)
    prog = [ch(60, "maj"), ch(65, "maj"), ch(67, "maj"), ch(60, "maj"), ch(57, "m"), ch(65, "maj"), ch(67, "7"), ch(60, "maj")]
    for bar, c in enumerate(prog):
        tr.add(strings([midi(n) for n in c] + [midi(c[0] + 12)], 4 * tr.beat, 3200, 0.1), bar * 4, 0, 0.17)
        tr.add(timpani(midi(c[0] - 24)), bar * 4, 0, 0.5)
        tr.add(kick(), bar * 4, 0, 0.55)
        tr.add(kick(), bar * 4 + 2, 0, 0.5)
        tr.add(snare(), bar * 4 + 1, 0.05, 0.5)
        tr.add(snare(), bar * 4 + 3, 0.05, 0.5)
        for i in range(8):
            tr.add(hat(), bar * 4 + i * 0.5, 0.35, 0.5)
    tr.add(cymbal(), 0, 0.3, 0.6)
    tr.add(cymbal(), 16, -0.3, 0.5)
    fan = [(0, 1, 67), (1, 0.5, 67), (1.5, 0.5, 67), (2, 2, 72), (4, 1, 72), (5, 1, 74), (6, 2, 76), (8, 1.5, 79),
           (9.5, 0.5, 76), (10, 2, 79), (12, 4, 84), (16, 1, 81), (17, 1, 79), (18, 2, 77), (20, 1, 77), (21, 1, 76),
           (22, 2, 74), (24, 1, 74), (25, 1, 76), (26, 2, 79), (28, 4, 84)]
    melody(tr, fan, brass, 0.28, 0.1)
    bassline(tr, [48, 53, 55, 48, 45, 53, 55, 48], [(0, 1, 0), (1, 1, 7), (2, 1, 12), (3, 1, 7)], bass_saw, 0.4, -12)
    tr.bed(crowd_bed(tr.n, 0.8), 0.6)
    return tr.master(-16)


LOOPS = {
    "menu": menu, "lobby": lobby, "bank": bank, "hotel": hotel, "casino": casino, "pub": pub, "arms": arms,
    "car_dealer": car_dealer, "print_shop": print_shop, "subway": subway, "police": police, "station": station,
    "playground": playground, "supermarket": supermarket, "harbor": harbor, "loan_shark": loan_shark,
    "dept_store": dept_store, "villa": villa, "city_hall": city_hall, "airport": airport,
    "police_standoff": police_standoff, "jail": jail, "victory": victory,
}


# ------------------------------------------------------------------ stings (one-shots)
def _st(seconds, seed):
    return Track(120, 1, loop=False, seconds=seconds, seed=seed)


STING_MASTER = dict(bass_target=0.35, high_target=0.02)


def shootout():
    tr = _st(3.2, 41)
    times = [0.0, 0.12, 0.2, 0.55, 0.62, 0.7, 0.78, 1.1, 1.45, 1.52, 1.9, 2.25]
    for i, s in enumerate(times):
        tr.add(gunshot(1.0 if i % 3 else 1.6), 0, (Rand.rng.random() - 0.5) * 1.4, 0.8, at_seconds=s)
    for s in (0.4, 1.3, 2.0):
        tr.add(ricochet(), 0, (Rand.rng.random() - 0.5) * 1.6, 0.6, at_seconds=s)
    tr.add(timpani(55, 1.5), 0, 0, 0.6, at_seconds=0)
    tr.add(brass(midi(52), 0.8, 1.5) + brass(midi(55), 0.8, 1.5) + brass(midi(58), 0.8, 1.5), 0, 0, 0.3, at_seconds=2.3)
    return tr.master(-14, 0.2, **STING_MASTER)


def gang_war():
    tr = _st(3.6, 42)
    for i in range(8):
        tr.add(tom(150 - i * 10, 0.4), 0, -0.5 + i * 0.14, 0.6, at_seconds=i * 0.09)
    tr.add(cymbal(), 0, 0, 0.6, at_seconds=0.75)
    for i, s in enumerate([0.8, 0.9, 1.0, 1.35, 1.42, 1.7, 2.1, 2.2, 2.3, 2.6]):
        tr.add(gunshot(1.0 + (i % 2) * 0.5), 0, (Rand.rng.random() - 0.5) * 1.6, 0.75, at_seconds=s)
    tr.add(brass(midi(48), 1.2, 1.5) + brass(midi(51), 1.2, 1.5) + brass(midi(54), 1.2, 1.5), 0, 0, 0.35, at_seconds=0.75)
    return tr.master(-14, 0.2, **STING_MASTER)


def success():
    tr = _st(2.4, 43)
    tr.add(cash_register(), 0, 0.2, 0.7, at_seconds=0)
    for i, n in enumerate((72, 76, 79, 84)):
        tr.add(vibes(midi(n), 1.2), 0, -0.3 + 0.2 * i, 0.5, at_seconds=0.15 + i * 0.11)
    tr.add(strings([midi(60), midi(64), midi(67), midi(72)], 1.4, 3000, 0.05), 0, 0, 0.25, at_seconds=0.55)
    return tr.master(-15, **STING_MASTER)


def busted():
    tr = _st(3.0, 44)
    tr.add(siren(1.2, "yelp", 700, 1500), 0, 0.4, 0.6, at_seconds=0)
    for i, n in enumerate((55, 54, 53)):
        tr.add(brass(midi(n), 0.38, 0.6), 0, 0, 0.6, at_seconds=1.0 + i * 0.4)
    t = tt(1.0)
    wah = brass(midi(52), 1.0, 0.6) * (1 + 0.3 * np.sin(2 * np.pi * 6 * t))
    tr.add(wah, 0, 0, 0.6, at_seconds=2.0)
    return tr.master(-15, **STING_MASTER)


def jail_door():
    tr = _st(2.8, 45)
    tr.add(metal_clang(140, 2.6), 0, 0.2, 0.9, at_seconds=0.05)
    tr.add(metal_clang(95, 2.0) * 0.6, 0, -0.2, 0.6, at_seconds=0.12)
    tr.add(brass(midi(41), 2.0, 0.4) + brass(midi(44), 2.0, 0.4), 0, 0, 0.3, at_seconds=0.6)
    return tr.master(-15, 0.35, **STING_MASTER)


def rank_up():
    tr = _st(3.0, 46)
    fan = [(0.0, 0.18, 67), (0.2, 0.18, 67), (0.4, 0.18, 67), (0.6, 1.2, 72), (1.4, 0.3, 76), (1.75, 1.2, 79)]
    for s, d, n in fan:
        tr.add(brass(midi(n), d, 1.3) + brass(midi(n - 12), d, 1.0) * 0.5, 0, 0.1, 0.5, at_seconds=s)
    tr.add(cymbal(2.0), 0, 0, 0.7, at_seconds=0.6)
    tr.add(timpani(65, 1.2), 0, 0, 0.6, at_seconds=0.6)
    tr.add(timpani(98, 1.2), 0, 0, 0.5, at_seconds=1.75)
    return tr.master(-14.5, **STING_MASTER)


def kidnap():
    tr = _st(3.4, 47)
    tr.add(timpani(45, 2.5), 0, 0, 0.8, at_seconds=0)
    tr.add(whoosh(1.5, True), 0, -0.4, 0.5, at_seconds=0)
    tr.add(strings([midi(n) for n in (62, 63, 68, 69)], 3.0, 2500, 0.8), 0, 0, 0.35, at_seconds=0.2)
    tr.add(bell(midi(87), 2.5, 1.41, 3.0), 0, 0.5, 0.2, at_seconds=1.2)
    return tr.master(-16, 0.4, **STING_MASTER)


def cash():
    tr = _st(1.8, 48)
    tr.add(coins(10), 0, -0.2, 0.7, at_seconds=0)
    tr.add(cash_register(), 0, 0.3, 0.6, at_seconds=0.3)
    return tr.master(-15, **STING_MASTER)


def gamble_win():
    tr = _st(2.2, 49)
    for i in range(3):
        tr.add(slot_ding(), 0, -0.4 + i * 0.4, 0.7, at_seconds=i * 0.25)
    tr.add(coins(14), 0, 0, 0.6, at_seconds=0.6)
    return tr.master(-15, **STING_MASTER)


def gamble_lose():
    tr = _st(2.4, 50)
    for i, n in enumerate((60, 59, 58)):
        tr.add(muted_trumpet(midi(n), 0.4), 0, 0, 0.7, at_seconds=i * 0.42)
    t = tt(1.0)
    last = muted_trumpet(midi(57), 1.0) * (1 + 0.4 * np.sin(2 * np.pi * 7 * t))
    tr.add(last, 0, 0, 0.7, at_seconds=1.3)
    return tr.master(-15.5, **STING_MASTER)


def month():
    tr = _st(2.4, 51)
    for i in range(4):
        tr.add(clock_tick(), 0, 0.3, 0.8, at_seconds=i * 0.18)
    tr.add(chime3(79), 0, 0, 0.5, at_seconds=0.6)
    return tr.master(-17, **STING_MASTER)


def holiday():
    tr = _st(3.2, 52)
    tr.add(jet(3.0), 0, 0.4, 0.5, at_seconds=0)
    for i, n in enumerate((72, 76, 79, 84, 79, 84, 88)):
        tr.add(steel_drum(midi(n), 0.6), 0, -0.3 + 0.1 * i, 0.5, at_seconds=0.3 + i * 0.17)
    return tr.master(-15.5, **STING_MASTER)


def police_alert():
    tr = _st(2.2, 53)
    tr.add(siren(2.2, "yelp", 750, 1600), 0, 0.3, 0.8, at_seconds=0)
    tr.add(timpani(55, 1.0), 0, 0, 0.6, at_seconds=0)
    tr.add(brass(midi(52), 0.5, 1.4) + brass(midi(58), 0.5, 1.4), 0, 0, 0.35, at_seconds=0.05)
    return tr.master(-15, **STING_MASTER)


STINGS = {
    "shootout": shootout, "gang_war": gang_war, "success": success, "busted": busted, "jail_door": jail_door,
    "rank_up": rank_up, "kidnap": kidnap, "cash": cash, "gamble_win": gamble_win, "gamble_lose": gamble_lose,
    "month": month, "holiday": holiday, "police_alert": police_alert,
}
