"""Render every Caper City music loop and sting, then report mix measurements.

Usage: python3 -I tools/music/build_all.py <project_dir> [name ...]
Writes audio/music/<scene>.ogg (loops) and audio/sfx/<event>.ogg (stings) via ffmpeg.
"""
import os
import subprocess
import sys
import tempfile
from multiprocessing import Pool

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scenes  # noqa: E402
from synth import SR  # noqa: E402

PROJECT = sys.argv[1]
ONLY = set(sys.argv[2:])
BANDS = [("bass", 30, 150), ("lowmid", 150, 600), ("mid", 600, 3000), ("high", 3000, 12000)]


def measure(st):
    m = st.mean(axis=1)
    f = np.fft.rfftfreq(len(m), 1 / SR)
    P = np.abs(np.fft.rfft(m)) ** 2
    tot = P.sum() + 1e-12
    bands = {n: 100 * P[(f >= lo) & (f < hi)].sum() / tot for n, lo, hi in BANDS}
    rms = 20 * np.log10(np.sqrt(np.mean(st ** 2)) + 1e-12)
    # click check: high-frequency burst at the loop point vs. the loudest one at any other bar start (8 bars)
    from synth import hp
    n = len(m)
    x = hp(np.roll(m, n // 2), 8000, 4)
    w = int(0.005 * SR)
    burst = lambda c: float(np.sqrt(np.mean(x[c - w:c + w] ** 2)))
    others = [burst(int((n // 2 + k * n / 8) % n)) for k in range(1, 8)]
    seam = burst(n // 2) / (max(others) + 1e-12)
    return {"peak": float(np.abs(st).max()), "rms": rms, "seam": seam, **bands}


def render(job):
    kind, name = job
    fn = (scenes.LOOPS if kind == "music" else scenes.STINGS)[name]
    try:
        st = fn()
    except Exception as e:  # report every broken recipe in one run
        import traceback
        return {"error": "%s/%s: %s\n%s" % (kind, name, e, traceback.format_exc(limit=3))}
    out_dir = os.path.join(PROJECT, "audio", kind)
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, name + ".wav")
        wavfile.write(wav, SR, (np.clip(st, -1, 1) * 32767).astype(np.int16))
        q = "4" if kind == "music" else "5"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", q,
                        os.path.join(out_dir, name + ".ogg")], check=True)
    m = measure(st)
    m.update(kind=kind, name=name, seconds=len(st) / SR, kb=os.path.getsize(os.path.join(out_dir, name + ".ogg")) // 1024)
    return m


if __name__ == "__main__":
    jobs = [("music", n) for n in scenes.LOOPS] + [("sfx", n) for n in scenes.STINGS]
    if ONLY:
        jobs = [j for j in jobs if j[1] in ONLY]
    with Pool(2) as pool:
        results = pool.map(render, jobs)
    print("%-6s %-16s %5s %5s %6s %5s %6s %6s %5s %5s %6s" % ("kind", "name", "sec", "KB", "rms", "peak", "bass%", "lowm%", "mid%", "hi%", "click"))
    for r in results:
        if "error" in r:
            print("ERROR", r["error"])
            continue
        flag = ""
        if r["bass"] > 45:
            flag += " BASSY"
        if r["mid"] + r["high"] < 6:
            flag += " DULL"
        if r["high"] > 35:
            flag += " HARSH"

        print("%-6s %-16s %5.1f %5d %6.1f %5.2f %6.1f %6.1f %5.1f %5.1f %6.3f%s" % (
            r["kind"], r["name"], r["seconds"], r["kb"], r["rms"], r["peak"], r["bass"], r["lowmid"], r["mid"], r["high"], r["seam"], flag))
    total = sum(r.get("kb", 0) for r in results)
    print("total size: %.1f MB" % (total / 1024))
