"""Per-car engine sounds: a small physical model rendered into seamless RPM loops (CC0, own work).

Usage:  build/venv/bin/python art/audio/gen_engines.py godot/assets/audio
        (make audio-engines creates the venv with numpy)

Model (per engine, per RPM point, per load):
  * combustion events at the engine's real firing angles over one 720° cycle (rotary: per
    eccentric-shaft rev), each an exhaust pressure pulse with cycle-to-cycle amplitude/timing
    variation, plus a turbulent noise burst that decays after the valve opens;
  * per-cylinder exhaust path delays (cross-plane V8 bank merge, unequal boxer headers) — this
    is what makes the lope/burble;
  * exhaust system: pipe resonance (comb), 2–3 formants, muffler low-pass, soft saturation;
  * intake rasp (noise modulated by the firing rate), valvetrain ticks, gear whine, turbo
    whistle; over-run crackles on the off-throttle layer.
Everything is built on a circular buffer and filtered in the frequency domain, so every loop is
seamless by construction (its length is an exact number of engine cycles).

Outputs: eng_<id>_<k>_<on|off>.wav (k = RPM point) and engines.json (runtime data: loop RPMs,
idle, redline, gear top speeds as fractions of the car's top speed, levels).
Also: road_roll.wav (tyre/road loop) and wind.wav for the own car.
"""
import json
import math
import os
import sys
import wave

import numpy as np

SR = 32000
LOOP_S = 1.25

# fire: firing angles in degrees over the cycle (720 for 4-stroke, 360 for rotary per rev).
# pipe: per-event extra exhaust delay in ms (cycled). amp: per-event amplitude pattern.
ENGINES = {
    "bolt": dict(  # V10 supercar: high, bright wail
        kind="ice", fire=[i * 72 for i in range(10)], cycle=720, pipe=[0, 0.25], amp=[1, 0.93],
        pulse_ms=0.35, noise=0.42, jitter=0.05, formants=[(520, 3.0, 1.0), (1350, 4.0, 0.7), (3100, 3.0, 0.35)],
        pipe_ms=2.4, pipe_g=0.55, lp=7000, rpms=[1100, 3200, 5600, 7900, 9600], idle=1100, redline=9800,
        gears=[0.2, 0.34, 0.49, 0.64, 0.8, 0.96], intake=0.22, turbo=0.0, whine=0.05, crackle=0.25, drive=1.6),
    "rhino": dict(  # big cross-plane V8 (truck/muscle): deep lopey burble
        kind="ice", fire=[i * 90 for i in range(8)], cycle=720, pipe=[0, 1.6, 0, 0, 1.6, 0, 1.6, 1.6],
        amp=[1, 0.8, 0.95, 0.75, 1, 0.85, 0.9, 0.78],
        pulse_ms=1.2, noise=0.38, jitter=0.07, formants=[(140, 2.0, 1.0), (420, 2.5, 0.6), (1100, 3.0, 0.25)],
        pipe_ms=6.5, pipe_g=0.6, lp=2600, rpms=[750, 1800, 3000, 4300, 5600], idle=750, redline=5800,
        gears=[0.24, 0.42, 0.62, 0.8, 0.98], intake=0.3, turbo=0.0, whine=0.03, crackle=0.35, drive=2.2),
    "glacier": dict(  # turbo inline-6: smooth, silky, turbo whistle
        kind="ice", fire=[i * 120 for i in range(6)], cycle=720, pipe=[0], amp=[1, 0.96, 0.98],
        pulse_ms=0.7, noise=0.3, jitter=0.045, formants=[(260, 2.5, 1.0), (780, 3.0, 0.55), (1900, 3.0, 0.25)],
        pipe_ms=3.8, pipe_g=0.5, lp=3600, rpms=[850, 2300, 3900, 5500, 7000], idle=850, redline=7200,
        gears=[0.22, 0.38, 0.55, 0.72, 0.88, 1.0], intake=0.18, turbo=0.1, whine=0.03, crackle=0.0, drive=1.4),
    "volt": dict(  # electric: motor whine, inverter, gear mesh — no gears
        kind="ev", rpms=[1200, 3600, 7000, 10500, 14000], idle=0, redline=15000, gears=[1.06],
        poles=4, mesh=31),
    "hook": dict(  # rally turbo inline-4: raspy, pops and bangs off throttle
        kind="ice", fire=[0, 180, 360, 540], cycle=720, pipe=[0], amp=[1, 0.9, 0.97, 0.88],
        pulse_ms=0.55, noise=0.45, jitter=0.06, formants=[(330, 3.0, 1.0), (980, 3.5, 0.7), (2600, 3.0, 0.4)],
        pipe_ms=3.0, pipe_g=0.5, lp=5200, rpms=[950, 2700, 4500, 6300, 7900], idle=950, redline=8000,
        gears=[0.2, 0.35, 0.52, 0.7, 0.86, 1.0], intake=0.35, turbo=0.13, whine=0.06, crackle=0.8, drive=1.9),
    "goo": dict(  # flat-4 boxer with unequal headers: the off-beat rumble
        kind="ice", fire=[0, 196, 360, 556], cycle=720, pipe=[0, 1.1, 0.3, 1.4], amp=[1, 0.82, 0.95, 0.8],
        pulse_ms=0.95, noise=0.33, jitter=0.06, formants=[(190, 2.2, 1.0), (560, 2.8, 0.55), (1500, 3.0, 0.2)],
        pipe_ms=5.0, pipe_g=0.55, lp=3000, rpms=[800, 2100, 3600, 5000, 6400], idle=800, redline=6600,
        gears=[0.23, 0.4, 0.58, 0.77, 0.96], intake=0.25, turbo=0.06, whine=0.03, crackle=0.2, drive=1.8),
    "phantom": dict(  # V12: dense, smooth, operatic
        kind="ice", fire=[i * 60 for i in range(12)], cycle=720, pipe=[0, 0.15], amp=[1, 0.97, 0.95],
        pulse_ms=0.45, noise=0.3, jitter=0.035, formants=[(400, 3.0, 1.0), (1150, 3.5, 0.65), (2700, 3.0, 0.3)],
        pipe_ms=2.8, pipe_g=0.5, lp=6000, rpms=[900, 2800, 4800, 6800, 8400], idle=900, redline=8600,
        gears=[0.2, 0.35, 0.5, 0.66, 0.82, 0.98], intake=0.2, turbo=0.0, whine=0.04, crackle=0.15, drive=1.3),
    "twister": dict(  # 2-rotor rotary: buzzy, brappy idle, very high revs
        kind="ice", fire=[0, 180], cycle=360, pipe=[0, 0.4], amp=[1, 0.86],
        pulse_ms=0.3, noise=0.55, jitter=0.12, formants=[(450, 2.5, 1.0), (1300, 3.0, 0.75), (3300, 2.5, 0.45)],
        pipe_ms=2.2, pipe_g=0.6, lp=6500, rpms=[1000, 3000, 5200, 7400, 9200], idle=1000, redline=9400,
        gears=[0.2, 0.36, 0.53, 0.7, 0.86, 1.0], intake=0.3, turbo=0.0, whine=0.05, crackle=0.55, drive=2.0),
}


def freqs(n):
    return np.fft.rfftfreq(n, 1.0 / SR)


def bandpass(f, fc, q):
    f = np.maximum(f, 1e-3)
    return 1.0 / (1.0 + 1j * q * (f / fc - fc / f))


def lowpass(f, fc, q=0.707):
    s = 1j * f / fc
    return 1.0 / (1.0 + s / q + s * s)


def highpass(f, fc, q=0.707):
    s = 1j * f / fc
    return (s * s) / (1.0 + s / q + s * s)


def cfilter(x, h):
    return np.fft.irfft(np.fft.rfft(x) * h, len(x))


def loop_len(rpm, cycle_deg):
    """Exact number of cycles in ≈ LOOP_S; returns (samples, adjusted rpm)."""
    cycle_s = cycle_deg / 360.0 * 60.0 / rpm
    k = max(1, round(LOOP_S / cycle_s))
    n = int(round(k * cycle_s * SR))
    return n, k * (cycle_deg / 360.0) * 60.0 / (n / SR), k


def periodic_noise(n, rng):
    return rng.standard_normal(n)


def decay_env(n, times, amps, tau_s):
    """Sum of exponential decays starting at each event time, wrapped circularly."""
    t = np.arange(n) / SR
    env = np.zeros(n)
    span = int(tau_s * SR * 6)
    for t0, a in zip(times, amps):
        i0 = int(t0 * SR)
        idx = (i0 + np.arange(span)) % n
        env[idx] += a * np.exp(-np.arange(span) / (tau_s * SR))
    return env


def render_ice(e, rpm, on, rng):
    n, rpm, k = loop_len(rpm, e["cycle"])
    f = freqs(n)
    cycle_s = n / SR / k
    fire = np.array(e["fire"], dtype=float) / e["cycle"] * cycle_s
    load_amp = 1.0 if on else 0.32
    x = rpm / e["redline"]
    times, amps = [], []
    spec = np.zeros(len(f), dtype=complex)
    a_ms = e["pulse_ms"] * (1.0 if on else 1.4) / 1000.0
    pulse = a_ms * math.e / (1.0 + 2j * math.pi * f * a_ms) ** 2  # t/a·e^(1−t/a)
    jit = e["jitter"] * (1.6 - x)  # combustion varies more at idle
    for c in range(k):
        for i, t0 in enumerate(fire):
            ev = c * len(fire) + i
            delay = e["pipe"][ev % len(e["pipe"])] / 1000.0
            dt = rng.normal(0.0, 0.004) * cycle_s / len(fire) * (1.0 + jit * 4)
            a = e["amp"][ev % len(e["amp"])] * load_amp * (1.0 + rng.normal(0.0, jit))
            if e["cycle"] == 360 and x < 0.25 and rng.random() < 0.12:
                a *= 0.35  # rotary brap: the odd weak chamber at idle
            t = (c * cycle_s + t0 + delay + dt) % (n / SR)
            times.append(t)
            amps.append(a)
            spec += a * np.exp(-2j * math.pi * f * t)
    tone = np.fft.irfft(spec * pulse, n)
    tone /= np.max(np.abs(tone)) + 1e-9
    # turbulent burst after each exhaust valve opening
    burst = periodic_noise(n, rng) * decay_env(n, times, np.abs(amps), (0.9 + 1.5 * (1 - x)) / 1000.0 * (e["pulse_ms"] / 0.5))
    burst = cfilter(burst, highpass(f, 400) * lowpass(f, e["lp"] * 1.4))
    burst /= np.max(np.abs(burst)) + 1e-9
    src = tone + e["noise"] * (1.2 if on else 0.6) * burst
    # exhaust system
    h = np.zeros(len(f), dtype=complex)
    for fc, q, g in e["formants"]:
        h += g * bandpass(f, fc * (1 + 0.15 * x), q)
    h += 0.35  # direct path
    pipe = 1.0 / (1.0 - e["pipe_g"] * np.exp(-2j * math.pi * f * e["pipe_ms"] / 1000.0))
    lp = lowpass(f, e["lp"] * (0.75 + 0.5 * x) * (1.0 if on else 0.6), 0.8)
    y = cfilter(src, h * pipe * lp * highpass(f, 35))
    y /= np.max(np.abs(y)) + 1e-9
    # intake rasp: band noise modulated at the firing rate
    fr = len(e["fire"]) * k / (n / SR)
    ph = np.arange(n) / SR * fr * 2 * math.pi
    rasp = cfilter(periodic_noise(n, rng), bandpass(f, 1600 + 1800 * x, 1.2))
    rasp *= 0.55 + 0.45 * np.sin(ph)
    y += e["intake"] * (1.0 if on else 0.25) * (0.4 + x) * rasp / (np.max(np.abs(rasp)) + 1e-9)
    # valvetrain ticks (high, quiet) and gear whine
    t = np.arange(n) / SR
    tick = cfilter(periodic_noise(n, rng) * decay_env(n, [tt + 0.3 * cycle_s / len(fire) for tt in times],
                                                     np.ones(len(times)), 0.00025), highpass(f, 4500))
    y += 0.05 * tick / (np.max(np.abs(tick)) + 1e-9)
    whine_f = rpm / 60.0 * 3.7
    cyc_w = round(whine_f * n / SR) * SR / n  # snap to the loop so it stays seamless
    y += e["whine"] * (0.6 if on else 1.4) * x * np.sin(2 * math.pi * cyc_w * t)
    if e["turbo"] > 0 and on:
        tf = 2200 + 5200 * x ** 1.4
        tf = round(tf * n / SR) * SR / n
        boost = np.clip((x - 0.15) / 0.5, 0, 1)
        flutter = round(7.0 * n / SR) * SR / n
        y += e["turbo"] * boost * np.sin(2 * math.pi * tf * t + 0.6 * np.sin(2 * math.pi * flutter * t))
        hiss = cfilter(periodic_noise(n, rng), bandpass(f, 5200, 1.5))
        y += 0.25 * e["turbo"] * boost * hiss / (np.max(np.abs(hiss)) + 1e-9)
    if not on and e["crackle"] > 0 and x > 0.2:
        # over-run afterfire: sparse sharp pops with ringing
        pops = np.zeros(n)
        count = int(e["crackle"] * 7 * LOOP_S * (0.5 + x))
        for _ in range(count):
            i0 = rng.integers(0, n)
            ln = int(SR * rng.uniform(0.003, 0.012))
            idx = (i0 + np.arange(ln)) % n
            pops[idx] += rng.uniform(0.5, 1.0) * rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln / 4))
        pops = cfilter(pops, h * pipe * highpass(f, 150) * lowpass(f, 6000))
        y += 0.9 * e["crackle"] * pops / (np.max(np.abs(pops)) + 1e-9)
    y = np.tanh(e["drive"] * y / (np.max(np.abs(y)) + 1e-9)) / math.tanh(e["drive"])
    return y, rpm


def render_ev(e, rpm, on, rng):
    n = int(LOOP_S * SR)
    f = freqs(n)
    t = np.arange(n) / SR
    x = rpm / e["redline"]

    def snap(fr):
        return max(1, round(fr * n / SR)) * SR / n

    fm = rpm / 60.0 * e["poles"]
    y = np.zeros(n)
    for hmul, g in [(1, 1.0), (2, 0.35), (3, 0.12), (6, 0.3), (12, 0.12)]:
        fr = snap(fm * hmul)
        if fr < SR / 2 - 500:
            y += g * np.sin(2 * math.pi * fr * t + hmul)
    y *= (0.9 if on else 0.45) * (0.35 + 0.65 * min(1.0, x * 2.0))
    mesh = snap(rpm / 60.0 * e["mesh"] / 4.0)
    if mesh < SR / 2 - 500:
        y += (0.28 if on else 0.4) * x * np.sin(2 * math.pi * mesh * t)
    # inverter switching tone + its sidebands (characteristic EV "sci-fi" whine)
    inv = snap(2600 + 900 * x)
    y += (0.12 if on else 0.06) * np.sin(2 * math.pi * inv * t) * (0.6 + 0.4 * np.sin(2 * math.pi * snap(fm) * t))
    # low hum + air
    y += 0.25 * np.sin(2 * math.pi * snap(50 + 30 * x) * t)
    air = cfilter(np.random.default_rng(7).standard_normal(n), bandpass(f, 900 + 2000 * x, 0.8))
    y += 0.12 * (0.3 + x) * air / (np.max(np.abs(air)) + 1e-9)
    y = np.tanh(1.2 * y / (np.max(np.abs(y)) + 1e-9)) / math.tanh(1.2)
    return y, rpm


def write_wav(path, y, peak=0.9):
    y = np.asarray(y, dtype=float)
    y = y / (np.max(np.abs(y)) + 1e-9) * peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())


def rms(y):
    return float(np.sqrt(np.mean(y * y)))


def tyre_loops(out):
    rng = np.random.default_rng(42)
    n = int(2.0 * SR)
    f = freqs(n)
    # road roll: low rumble + coarse tyre noise
    road = cfilter(rng.standard_normal(n), lowpass(f, 380, 0.9) * highpass(f, 40))
    road += 0.35 * cfilter(rng.standard_normal(n), bandpass(f, 900, 0.9))
    write_wav(os.path.join(out, "road_roll.wav"), road, 0.8)
    # wind: broadband, slowly gusting
    wind = cfilter(rng.standard_normal(n), bandpass(f, 600, 0.5) + 0.4 * bandpass(f, 2200, 0.7))
    wind *= 0.75 + 0.25 * cfilter(rng.standard_normal(n), lowpass(f, 1.5)) / 0.5
    write_wav(os.path.join(out, "wind.wav"), wind, 0.8)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/audio"
    meta = {"sample_rate": SR, "engines": {}}
    for name, e in ENGINES.items():
        rng = np.random.default_rng(sum(map(ord, name)) * 7919)  # deterministic per engine
        loops = []
        for i, rpm in enumerate(e["rpms"]):
            # each loop is peak-normalised; EngineSound sets on/off and RPM levels at runtime
            for on in (True, False):
                fn = render_ev if e["kind"] == "ev" else render_ice
                y, real = fn(e, rpm, on, rng)
                write_wav(os.path.join(out, "eng_%s_%d_%s.wav" % (name, i, "on" if on else "off")), y)
            loops.append(round(real, 2))
            print("%-8s %d  %6.0f rpm" % (name, i, real))
        meta["engines"][name] = {
            "kind": e["kind"], "loops": loops, "idle": e["idle"], "redline": e["redline"], "gears": e["gears"],
        }
    with open(os.path.join(out, "engines.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    tyre_loops(out)


if __name__ == "__main__":
    main()
