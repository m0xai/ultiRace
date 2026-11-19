"""Procedural, deterministic game audio (sfxr-style synthesis, CC0 by construction).

Usage: python3 art/audio/gen_audio.py godot/assets/audio
Writes 16-bit mono WAVs: sfx_*.wav, engine_<class>_<layer>.wav (seamless loops), music_*.wav.
Standard library only (wave, math, random with fixed seeds).
"""
import math
import os
import random
import struct
import sys
import wave

SR = 22050


def write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        peak = max(1e-9, max(abs(s) for s in samples))
        k = 0.89 / peak if peak > 0.89 else 1.0
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))


def env(i, n, attack=0.01, release=0.2):
    t = i / SR
    total = n / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (total - t) / release) if release > 0 else 1.0
    return max(0.0, a * r)


def osc(kind, phase):
    p = phase % 1.0
    if kind == "sine":
        return math.sin(2 * math.pi * p)
    if kind == "square":
        return 1.0 if p < 0.5 else -1.0
    if kind == "saw":
        return 2 * p - 1
    if kind == "tri":
        return 4 * abs(p - 0.5) - 1
    return 0.0


def tone(dur, f0, f1=None, kind="square", vol=0.5, attack=0.005, release=0.1, vibrato=0.0):
    n = int(dur * SR)
    f1 = f0 if f1 is None else f1
    out, ph = [], 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        f *= 1 + vibrato * math.sin(2 * math.pi * 6 * i / SR)
        ph += f / SR
        out.append(osc(kind, ph) * vol * env(i, n, attack, release))
    return out


def noise(dur, vol=0.5, lp=0.5, seed=1, attack=0.002, release=0.15, lp_end=None):
    rng = random.Random(seed)
    n = int(dur * SR)
    out, y = [], 0.0
    for i in range(n):
        a = lp if lp_end is None else lp + (lp_end - lp) * i / n
        y += a * (rng.uniform(-1, 1) - y)
        out.append(y * vol * env(i, n, attack, release))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def cat(*tracks):
    out = []
    for t in tracks:
        out += t
    return out


def silence(dur):
    return [0.0] * int(dur * SR)


# ---------- SFX ----------
def sfx():
    return {
        "countdown": tone(0.18, 660, kind="square", vol=0.35, release=0.08),
        "go": tone(0.45, 990, kind="square", vol=0.4, release=0.25),
        "boost": mix(noise(0.6, 0.5, 0.08, seed=2, release=0.4, lp_end=0.4), tone(0.6, 180, 520, "saw", 0.25, release=0.3)),
        "wall": mix(noise(0.18, 0.8, 0.6, seed=3, release=0.15), tone(0.12, 120, 60, "square", 0.4)),
        "spinout": mix(tone(0.9, 700, 150, "tri", 0.4, release=0.4, vibrato=0.08), noise(0.9, 0.2, 0.2, seed=4)),
        "ice": cat(*[tone(0.05, 2000 + 300 * k, 1500, "sine", 0.25, release=0.04) for k in range(6)]),
        "emp": mix(tone(0.7, 90, 40, "saw", 0.5, release=0.5), noise(0.7, 0.3, 0.05, seed=5, release=0.5)),
        "grapple": mix(tone(0.25, 300, 1200, "square", 0.25, release=0.1), noise(0.25, 0.2, 0.9, seed=6)),
        "splat": noise(0.35, 0.8, 0.12, seed=7, release=0.3),
        "tornado": mix(noise(1.2, 0.6, 0.03, seed=8, attack=0.2, release=0.5, lp_end=0.15), tone(1.2, 200, 260, "tri", 0.15, vibrato=0.2)),
        "phase": tone(0.6, 400, 1600, "sine", 0.35, release=0.4, vibrato=0.05),
        "lap": cat(tone(0.1, 880, kind="square", vol=0.3), tone(0.16, 1320, kind="square", vol=0.3)),
        "finish": cat(*[tone(0.14, f, kind="square", vol=0.3) for f in (523, 659, 784)], tone(0.5, 1047, kind="square", vol=0.35, release=0.3)),
        "ult_ready": tone(0.12, 1200, 1600, "sine", 0.3, release=0.08),
        "ui_click": tone(0.04, 1500, 1200, "square", 0.2, release=0.03),
        "start_boost": cat(tone(0.08, 880, kind="square", vol=0.3), tone(0.2, 1760, kind="square", vol=0.3)),
    }


# ---------- engines: seamless loops (whole number of cycles) ----------
ENGINE = {"light": 1.25, "medium": 1.0, "heavy": 0.75}  # base pitch factor per car class
LAYERS = {"idle": 55.0, "mid": 110.0, "high": 220.0}


def engine_loop(base_f, cls_k, seed):
    f = base_f * cls_k
    cycles = max(1, round(f * 0.5))  # ~0.5 s loop, integer cycles → seamless
    dur = cycles / f
    n = int(round(dur * SR))
    rng = random.Random(seed)
    out = []
    for i in range(n):
        p = i * f / SR
        s = 0.55 * osc("saw", p) + 0.3 * osc("square", p * 0.5) + 0.15 * osc("sine", p * 2)
        s += 0.08 * rng.uniform(-1, 1)
        out.append(s * 0.5)
    return out


# ---------- music: simple chiptune loops ----------
SCALES = {
    "menu": ([0, 4, 7, 11, 12, 11, 7, 4], 110, 57),
    "sunny": ([0, 4, 7, 9, 12, 9, 7, 4], 126, 60),
    "neon": ([0, 3, 7, 10, 12, 10, 7, 3], 132, 57),
    "frosty": ([0, 2, 7, 9, 14, 9, 7, 2], 118, 62),
}


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def music(name, bars=8):
    arp, bpm, root = SCALES[name]
    step = 60.0 / bpm / 2  # eighth notes
    chords = [0, 5, 7, 3] if name == "neon" else [0, 5, 9, 7]
    out = []
    for bar in range(bars):
        ch = chords[bar % 4]
        for k in range(8):
            n_lead = root + 12 + ch + arp[(k + bar) % len(arp)]
            lead = tone(step, midi(n_lead), kind="square", vol=0.12, attack=0.003, release=step * 0.6)
            bass = tone(step, midi(root - 12 + ch + (7 if k % 4 == 2 else 0)), kind="tri", vol=0.3, release=step * 0.3)
            kick = tone(step * 0.6, 120, 45, "sine", 0.45, release=0.1) if k % 4 == 0 else silence(step)
            hat = noise(step * 0.25, 0.08, 0.9, seed=bar * 8 + k, release=0.03) if k % 2 == 1 else silence(step)
            out += mix(lead, bass, kick, hat)
    return out


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    for name, s in sfx().items():
        write(os.path.join(outdir, f"sfx_{name}.wav"), s)
    seed = 10
    for cls, k in ENGINE.items():
        for layer, f in LAYERS.items():
            write(os.path.join(outdir, f"engine_{cls}_{layer}.wav"), engine_loop(f, k, seed))
            seed += 1
    for name in SCALES:
        write(os.path.join(outdir, f"music_{name}.wav"), music(name))
    print("audio written to", outdir)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "godot/assets/audio")
