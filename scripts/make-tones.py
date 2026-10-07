#!/usr/bin/env python3
"""Synthesises the app's four alert tones (Compte › Préférences › Sons des
notifications) from nothing but sine waves.

Original, no samples and no third-party audio: every sound is a sum of
decaying partials computed here. 16 kHz mono 16-bit PCM WAV, each under
30 KB. Standard library only:

    python3 scripts/make-tones.py

Regenerating is deterministic; commit the WAVs it writes to app/assets/sounds.
"""
import math, struct, sys, wave, os

RATE = 16000
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'app', 'assets', 'sounds')

def env(t, attack, decay):
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-t / decay)

def note(buf, start, freq, length, partials, attack=0.004, decay=0.18, gain=1.0, glide=0.0):
    n0 = int(start * RATE)
    n = int(length * RATE)
    phase = [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        f = freq * (1 + glide * t)
        e = env(t, attack, decay)
        s = 0.0
        for k, (ratio, amp, pdecay) in enumerate(partials):
            phase[k] += 2 * math.pi * f * ratio / RATE
            s += amp * math.sin(phase[k]) * math.exp(-t / pdecay)
        idx = n0 + i
        if idx < len(buf):
            buf[idx] += gain * e * s

def write(name, buf):
    peak = max(abs(x) for x in buf) or 1.0
    # A short fade at the very end so nothing clicks.
    fade = int(0.02 * RATE)
    for i in range(fade):
        buf[-1 - i] *= i / fade
    frames = b''.join(struct.pack('<h', int(32767 * 0.85 * x / peak)) for x in buf)
    path = os.path.join(out, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(frames)
    print(name, os.path.getsize(path), 'bytes')

def blank(seconds):
    return [0.0] * int(seconds * RATE)

# 1. Balafon: three wooden notes climbing a pentatonic step, a hollow
#    resonator (fundamental + a 4x partial that dies fast).
buf = blank(0.75)
wood = [(1.0, 1.0, 0.25), (3.98, 0.35, 0.03), (10.1, 0.08, 0.01)]
for start, f in ((0.0, 587.33), (0.13, 698.46), (0.26, 880.0)):
    note(buf, start, f, 0.45, wood, attack=0.002, decay=0.12)
write('balafon.wav', buf)

# 2. Clochette: a small bell, inharmonic partials, struck twice.
buf = blank(0.9)
bell = [(1.0, 1.0, 0.5), (2.76, 0.5, 0.25), (5.40, 0.25, 0.12), (8.93, 0.12, 0.06)]
note(buf, 0.0, 1318.5, 0.85, bell, attack=0.001, decay=0.35)
note(buf, 0.18, 1318.5, 0.7, bell, attack=0.001, decay=0.3, gain=0.7)
write('clochette.wav', buf)

# 3. Carillon: the doorbell ding-dong, a falling major third.
buf = blank(0.88)
chime = [(1.0, 1.0, 0.6), (2.0, 0.3, 0.3), (3.0, 0.12, 0.15)]
note(buf, 0.0, 783.99, 0.6, chime, attack=0.003, decay=0.3)
note(buf, 0.28, 622.25, 0.6, chime, attack=0.003, decay=0.32)
write('carillon.wav', buf)

# 4. Goutte: two soft drops, a sine whose pitch rises as it fades.
buf = blank(0.55)
drop = [(1.0, 1.0, 1.0), (2.0, 0.15, 0.05)]
note(buf, 0.0, 900.0, 0.2, drop, attack=0.003, decay=0.06, glide=3.5)
note(buf, 0.16, 1200.0, 0.25, drop, attack=0.003, decay=0.07, glide=3.0, gain=0.85)
write('goutte.wav', buf)
