"""Offline listening demo for the engine loops: mirrors EngineSound.gd (gears, shift cut, load,
cross-fade, pitch) for a scripted run per car: idle 2 s → full throttle to top speed → boost on
the limiter → lift off (over-run) → idle. Writes one WAV with all cars in sequence.

Usage: build/venv/bin/python art/audio/demo_engines.py godot/assets/audio build/engine_demo.wav
"""
import json
import math
import os
import sys
import wave

import numpy as np

FPS = 60
TOP = {"bolt": 42.0, "rhino": 35.0, "glacier": 38.0, "volt": 38.0, "hook": 38.0, "goo": 37.0, "phantom": 40.0, "twister": 36.0}


def read(path):
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32767, w.getframerate()


class Drive:
    def __init__(self, e, top):
        self.ev = e["kind"] == "ev"
        self.idle, self.red = e["idle"], e["redline"]
        self.gt = [g * top for g in e["gears"]]
        self.loops = e["loops"]
        self.gear, self.rpm, self.load, self.cut, self.prev, self.acc, self.t = 0, max(e["idle"], e["loops"][0]), 1.0, 0.0, 0.0, 0.0, 0.0

    def step(self, v, dt):
        self.t += dt
        self.acc += ((v - self.prev) / dt - self.acc) * (1 - math.exp(-dt / 0.12))
        self.prev = v
        self.cut = max(self.cut - dt, 0)
        if self.ev:
            tgt = max(v / self.gt[0] * self.red, self.loops[0] * 0.8)
        else:
            ig = v / self.gt[self.gear] * self.red
            if self.gear < len(self.gt) - 1 and ig > self.red * 0.93 and self.acc > -2.5:
                self.gear += 1
                self.cut = 0.13
            elif self.gear > 0 and v / self.gt[self.gear - 1] < 0.6:
                self.gear -= 1
            tgt = v / self.gt[self.gear] * self.red
            if self.gear == 0 and v > 0.3:
                slip = self.idle + (self.red * 0.55 - self.idle) * min(max(self.load, 0), 1)
                k = min(max(v / (self.gt[0] * 0.55), 0), 1)
                tgt = max(tgt, slip + (tgt - slip) * k)
            if tgt > self.red:
                tgt = self.red * (0.965 + 0.035 * abs(math.sin(self.t * 26)))
            tgt = max(tgt, self.idle)
            if self.cut > 0:
                tgt = min(tgt, self.rpm)
        self.rpm += (tgt - self.rpm) * (1 - math.exp(-dt / (0.07 * (0.6 if self.cut > 0 else 1))))
        want = 1.0 if (self.acc > -2.5 or v < 2) else 0.0
        if self.cut > 0:
            want = 0.15
        self.load += (want - self.load) * (1 - math.exp(-dt / 0.09))


def main():
    adir, out = sys.argv[1], sys.argv[2]
    meta = json.load(open(os.path.join(adir, "engines.json")))
    full = []
    for car, e in meta["engines"].items():
        top = TOP[car]
        bufs = {(k, l): read(os.path.join(adir, "eng_%s_%d_%s.wav" % (car, k, l)))[0] for k in range(len(e["loops"])) for l in ("on", "off")}
        sr = meta["sample_rate"]
        ph = {key: 0.0 for key in bufs}
        d = Drive(e, top)
        script = []  # speed per frame
        v = 0.0
        for i in range(int(2 * FPS)):
            script.append(0.0)
        while v < top:
            v = min(v + top / (7.0 * FPS) * (1.4 - v / top), top)
            script.append(v)
        for i in range(int(1.5 * FPS)):
            script.append(top * 1.12)  # boost on the limiter
        for i in range(int(2.5 * FPS)):
            v = max(v - 6.0 / FPS, top * 0.5)
            script.append(v)
        for i in range(int(1.0 * FPS)):
            script.append(0.0 if i > 30 else v * (1 - i / 30))
        spf = sr // FPS
        o = []
        for v in script:
            d.step(v, 1 / FPS)
            loops = d.loops
            i = 0
            while i < len(loops) - 2 and d.rpm > loops[i + 1]:
                i += 1
            f = min(max(math.log(d.rpm / loops[i]) / math.log(loops[i + 1] / loops[i]), 0), 1)
            x = min(max((d.rpm - d.idle) / (d.red - d.idle), 0), 1)
            level = (0.55 + 0.45 * x) * (0.7 if d.cut > 0 else 1)
            gains = {"on": math.sqrt(min(max(d.load, 0), 1)), "off": math.sqrt(min(max(1 - d.load, 0), 1)) * 0.7}
            chunk = np.zeros(spf)
            for k, w in ((i, math.cos(f * math.pi / 2)), (i + 1, math.sin(f * math.pi / 2))):
                pitch = min(max(d.rpm / loops[k], 0.5), 2.0)
                for l in ("on", "off"):
                    b = bufs[(k, l)]
                    idx = (ph[(k, l)] + np.arange(spf) * pitch) % len(b)
                    i0 = idx.astype(int)
                    fr = idx - i0
                    chunk += w * level * gains[l] * (b[i0] * (1 - fr) + b[(i0 + 1) % len(b)] * fr)
                    ph[(k, l)] = (ph[(k, l)] + spf * pitch) % len(b)
            o.append(chunk)
        y = np.concatenate(o)
        full.append(y / (np.max(np.abs(y)) + 1e-9) * 0.8)
        full.append(np.zeros(int(0.6 * sr)))
        print(car, "%.1f s" % (len(y) / sr))
    y = np.concatenate(full)
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(meta["sample_rate"])
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())


if __name__ == "__main__":
    main()
