#!/usr/bin/env python3
"""Synthesize the jetpack SFX set from stdlib only.

Original work written for this repo and dedicated to the public domain
(CC0 1.0, see assets/audio/LICENSE.md). Every file is 22050 Hz 16-bit
mono WAV, 0.5 s or shorter. Deterministic: the PRNG is seeded, so reruns
are byte-identical.

Writers:
  shot()        sine freq-sweep with a noise crack layered in (gunshots)
  noise_burst() decaying filtered noise (explosion, scatter body)
  blip()        enveloped sine, optionally two-tone (UI / pickup / beep)

Usage: python3 tools/make_sfx.py   (run from the jetpack/ directory)
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")


def _to_i16(frames):
    peak = 0.0
    for s in frames:
        a = abs(s)
        if a > peak:
            peak = a
    gain = 0.9 / peak if peak > 0.9 else 1.0
    return [max(-1.0, min(1.0, s * gain)) for s in frames]


def _write(name, frames):
    frames = _to_i16(frames)
    path = os.path.join(OUT_DIR, name)
    os.makedirs(OUT_DIR, exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack("<%dh" % len(frames), *(int(s * 32767) for s in frames)))
    print("wrote %s (%d frames, %.3fs)" % (path, len(frames), len(frames) / RATE))


def shot(f0, f1, dur, noise_amt=0.5, seed=7):
    """Pitched zap from f0 down to f1 with a noise crack on the attack."""
    rng = random.Random(seed)
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = f0 + (f1 - f0) * t
        phase += 2.0 * math.pi * freq / RATE
        env = math.exp(-9.0 * t)
        crack = math.exp(-40.0 * t)
        out.append(math.sin(phase) * env + (rng.random() * 2.0 - 1.0) * noise_amt * crack)
    return out


def noise_burst(dur, decay=4.0, sub_hz=0.0, seed=21):
    """Decaying noise wash, optionally under a sub sine for body."""
    rng = random.Random(seed)
    n = int(RATE * dur)
    out = []
    last = 0.0
    phase = 0.0
    for i in range(n):
        t = i / n
        env = math.exp(-decay * t)
        raw = rng.random() * 2.0 - 1.0
        last = 0.6 * last + 0.4 * raw  # cheap lowpass so it booms, not hisses
        s = last * env
        if sub_hz > 0.0:
            phase += 2.0 * math.pi * sub_hz / RATE
            s += 0.6 * math.sin(phase) * env
        out.append(s)
    return out


def blip(freq, dur, freq2=0.0, seed=3):
    """Enveloped sine; freq2 != 0 plays freq then freq2 back to back."""
    rng = random.Random(seed + int(freq))
    _ = rng.random()  # touch the seed so every call is reproducible
    if freq2 > 0.0:
        half = dur / 2.0
        return blip(freq, half, seed=seed) + blip(freq2, half, seed=seed + 1)
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / n
        attack = min(1.0, t * 20.0)
        env = attack * math.exp(-6.0 * t)
        out.append(math.sin(2.0 * math.pi * freq * i / RATE) * env)
    return out


def clicks(gap=0.12, seed=11):
    """Two short filtered ticks (reload foley)."""
    rng = random.Random(seed)
    dur = gap + 0.08
    n = int(RATE * dur)
    out = [0.0] * n
    for start in (0, int(RATE * gap)):
        for i in range(int(RATE * 0.03)):
            t = i / (RATE * 0.03)
            out[start + i] += (rng.random() * 2.0 - 1.0) * math.exp(-30.0 * t) * 0.8
    return out


def main():
    _write("ar_shot.wav", shot(1800.0, 300.0, 0.18, noise_amt=0.5, seed=7))
    body = noise_burst(0.25, decay=9.0, seed=22)
    crack = shot(900.0, 150.0, 0.25, noise_amt=0.6, seed=8)
    _write("scatter_shot.wav", [a + b for a, b in zip(body, crack)])
    _write("longbow_shot.wav", shot(600.0, 120.0, 0.30, noise_amt=0.3, seed=9))
    _write("explosion.wav", noise_burst(0.50, decay=4.0, sub_hz=60.0, seed=21))
    hit = blip(1200.0, 0.12, seed=4)
    ring = blip(1800.0, 0.12, seed=5)
    _write("hit.wav", [a + 0.4 * b for a, b in zip(hit, ring)])
    _write("pickup.wav", blip(660.0, 0.20, freq2=990.0, seed=6))
    _write("reload.wav", clicks(gap=0.12, seed=11))
    _write("ui_click.wav", blip(2000.0, 0.06, seed=12))
    _write("grenade_beep.wav", blip(880.0, 0.12, seed=13))


if __name__ == "__main__":
    main()
