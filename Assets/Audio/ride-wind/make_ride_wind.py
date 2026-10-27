"""Writes the air rushing past the player on the dragon's back (Sources/Macrowavers/Resources/RideWind.caf).

Filtered noise (a low rumble and a brighter hiss) with slow gusts, mono for RealityKit, 12 s that loop seamlessly
(the end crossfades into the start). Python's standard library only.

usage: python3 make_ride_wind.py RideWind.wav && afconvert -f caff -d alac RideWind.wav RideWind.caf
(Apple Lossless: AAC would add a silent gap at the loop point.)
"""
import math
import random
import struct
import sys
import wave

RATE = 44100
SECONDS = 12.0
FADE = 1.5          # crossfade of the loop point (s)

random.seed(7)
total = int(RATE * (SECONDS + FADE))


def one_pole(cutoff):
    a = math.exp(-2 * math.pi * cutoff / RATE)
    state = [0.0]

    def step(x):
        state[0] = (1 - a) * x + a * state[0]
        return state[0]
    return step


low = [one_pole(180), one_pole(180)]           # rumble: noise, low-passed twice
mid_lp, mid_hp = one_pole(1400), one_pole(250)  # hiss: band of noise
samples = []
for n in range(total):
    t = n / RATE
    white = random.uniform(-1, 1)
    rumble = low[1](low[0](white)) * 9.0
    band = mid_lp(white)
    hiss = (band - mid_hp(band)) * 2.2
    # slow gusts: a few incommensurate swells, so the loop never sounds periodic
    gust = 0.55 + 0.25 * math.sin(2 * math.pi * t / 5.3) + 0.15 * math.sin(2 * math.pi * t / 3.1 + 1.2) \
        + 0.08 * math.sin(2 * math.pi * t / 1.7 + 0.4)
    samples.append(rumble * (0.7 + 0.3 * gust) + hiss * gust)

# loop: the extra tail fades out over the start, which fades in
loop_len = int(RATE * SECONDS)
fade_len = int(RATE * FADE)
out = samples[:loop_len]
for i in range(fade_len):
    w = i / fade_len
    out[i] = out[i] * w + samples[loop_len + i] * (1 - w)

peak = max(abs(x) for x in out)
gain = 0.7 / peak
with wave.open(sys.argv[1], "wb") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(RATE)
    f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x * gain)) * 32767)) for x in out))
print("wrote", sys.argv[1], f"{SECONDS:.0f} s")
