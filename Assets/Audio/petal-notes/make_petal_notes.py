"""Writes the medallion's petal notes (Sources/Macrowavers/Resources/PetalNote01.m4a ... PetalNote10.m4a): a santur
note for each petal of chapter II's shamseh, climbing as the dragon eats: C5 D5 Eb5 G5 Bb5 C6 D6 Eb6 G6, and for the
10th petal, the medallion complete, a rolled chord C6 G6 C7. C minor, 14 cents sharp: a first reading of the ride
music's key (MusicRide.caf is closer to 3 cents sharp, and its E and B sound like Persian quarter tones). Versions on
C D G only, in tune with the track, in four other timbres were tried and this one was preferred by ear.

A santur's strings are struck in courses of four, a little out of tune with each other. Each string here is a
plucked-string model (Karplus-Strong, with an allpass for the fraction of the delay so high notes stay in tune),
started by a short soft strike of noise; the four strings of a course are detuned by a few cents so they shimmer,
and a touch of room is added. Mono. Python's standard library only.

usage: python3 make_petal_notes.py <folder>     (writes PetalNote01.wav ... PetalNote10.wav there), then:
       for f in <folder>/PetalNote*.wav; do
           afconvert -f m4af -d aac -b 128000 "$f" "Sources/Macrowavers/Resources/$(basename "$f" .wav).m4a"
       done
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 44100
SECONDS = 2.6
TUNING = 14                                      # cents above A = 440
DETUNE = [-3.5, -1.0, 1.5, 4.0]                  # the four strings of a course (cents)
BRIGHTNESS = 0.15                                # 0 = brightest strings, 0.5 = dull
ROLL = 0.06                                      # the chord's strings struck one after the other (s)
PEAK = 10 ** (-3 / 20)

# MIDI notes: C5 = 72. Each petal a note; the last a chord.
PETALS = [[72], [74], [75], [79], [82], [84], [86], [87], [91], [84, 91, 96]]


def frequency(midi, cents=0.0):
    return 440 * 2 ** ((midi - 69 + (TUNING + cents) / 100) / 12)


def string(freq, t60, seed):
    """One struck string, `SECONDS` long: Karplus-Strong, its loop delay exactly RATE / freq."""
    rng = random.Random(seed)
    delay = RATE / freq
    whole = int(delay - BRIGHTNESS - 0.1)
    fraction = delay - BRIGHTNESS - whole
    allpass = (1 - fraction) / (1 + fraction)
    loss = 10 ** (-3 / (t60 * freq))             # -60 dB after t60 seconds
    # The strike: noise, softened, without its average (a string at rest has none).
    strike, soft = [], 0.0
    for _ in range(whole + 1):
        soft += 0.5 * (rng.uniform(-1, 1) - soft)
        strike.append(soft)
    mean = sum(strike) / len(strike)
    out = [x - mean for x in strike]
    previous_in = 0.0
    total = int(RATE * SECONDS)
    while len(out) < total + whole + 1:
        n = len(out)
        filtered = loss * ((1 - BRIGHTNESS) * out[n - whole] + BRIGHTNESS * out[n - whole - 1])
        out.append(allpass * filtered + previous_in - allpass * out[n - 1])
        previous_in = filtered
    return out[whole + 1:]


def course(midi, seed):
    """The four strings of one note, a little out of tune with each other."""
    freq = frequency(midi)
    t60 = 5.0 * math.sqrt(frequency(72) / freq)  # high strings ring shorter
    strings = [string(frequency(midi, cents), t60, seed * 10 + index) for index, cents in enumerate(DETUNE)]
    return [sum(values) / len(strings) for values in zip(*strings)]


def room(samples):
    """A small room: four combs and two allpasses (Schroeder), mixed in lightly."""
    def comb(signal, length, feedback):
        out = [0.0] * len(signal)
        for n, x in enumerate(signal):
            out[n] = x + (feedback * out[n - length] if n >= length else 0)
        return out

    def diffuse(signal, length, gain):
        out = [0.0] * len(signal)
        for n, x in enumerate(signal):
            past_in = signal[n - length] if n >= length else 0
            past_out = out[n - length] if n >= length else 0
            out[n] = -gain * x + past_in + gain * past_out
        return out

    combs = [comb(samples, length, 0.72) for length in (1557, 1617, 1491, 1422)]
    wet = [sum(values) / 4 for values in zip(*combs)]
    for length in (225, 556):
        wet = diffuse(wet, length, 0.5)
    return [dry + 0.12 * reverb for dry, reverb in zip(samples, wet)]


def petal(notes, seed):
    total = int(RATE * SECONDS)
    mix = [0.0] * total
    for index, midi in enumerate(notes):
        start = int(ROLL * RATE * index)
        for n, value in enumerate(course(midi, seed + index)[:total - start]):
            mix[start + n] += value
    mix = room(mix)
    fade = int(0.3 * RATE)
    for n in range(fade):
        mix[total - fade + n] *= 1 - n / fade
    gain = PEAK / max(abs(x) for x in mix)
    return [x * gain for x in mix]


def write(path, samples):
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in samples))


if __name__ == "__main__":
    folder = sys.argv[1]
    os.makedirs(folder, exist_ok=True)
    for number, notes in enumerate(PETALS, start=1):
        path = os.path.join(folder, f"PetalNote{number:02d}.wav")
        write(path, petal(notes, number))
        print("wrote", path)
