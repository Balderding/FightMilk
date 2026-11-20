"""Our own reward sounds, synthesised from scratch (no samples, no borrowed audio).

- uwu_set.wav      : short cute "uwu" for a finished set
- uwu_exercise.wav : sparkle + "uwu~" for a finished exercise
- uwu_workout.wav  : little fanfare + long "uwuuu~" for a finished workout
- rest_over.wav    : soft two-note chime when rest is over
- simple_*.wav     : plain blips for people who prefer no voice

The "voice" is a tiny formant synthesiser: a glottal-like buzz at a high, rising pitch, sent through
three resonators tuned to the vowel "oo" (u), with a "w" glide in the middle (formants dip, volume dips).
Pure Python (wave + math). Licence: CC BY-SA 4.0, balderding.
Run: python tools/gen_sounds.py
"""
import math, pathlib, random, struct, wave

SR = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "app" / "assets" / "sounds"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(7)


class Reso:
    """Two-pole resonator (formant filter)."""

    def __init__(self):
        self.y1 = self.y2 = 0.0

    def run(self, x, f, bw):
        r = math.exp(-math.pi * bw / SR)
        c = 2 * r * math.cos(2 * math.pi * f / SR)
        y = (1 - r) * x + c * self.y1 - r * r * self.y2
        self.y2, self.y1 = self.y1, y
        return y


def lerp(a, b, t):
    return a + (b - a) * t


def voice(segments, pitch, vib=6.0, vib_depth=0.025, breath=0.04):
    """segments: list of (seconds, (F1,F2,F3) start, (F1,F2,F3) end, amp start, amp end).
    pitch(t01) -> Hz over the whole sound."""
    total = sum(s[0] for s in segments)
    n = int(total * SR)
    f1, f2, f3 = Reso(), Reso(), Reso()
    out = []
    phase = 0.0
    t_abs = 0
    for dur, fa, fb, aa, ab in segments:
        m = int(dur * SR)
        for i in range(m):
            u = i / max(1, m - 1)
            g = t_abs / max(1, n - 1)
            f0 = pitch(g) * (1 + vib_depth * math.sin(2 * math.pi * vib * t_abs / SR))
            phase += f0 / SR
            if phase >= 1:
                phase -= 1
            # glottal-ish pulse: smooth rise, sharp fall, plus a little breath
            src = (phase ** 3 - 0.25) * 2.0 + breath * (random.random() * 2 - 1)
            F = [lerp(fa[k], fb[k], u) for k in range(3)]
            y = f1.run(src, F[0], 80) * 1.0 + f2.run(src, F[1], 110) * 0.55 + f3.run(src, F[2], 160) * 0.25
            out.append(y * lerp(aa, ab, u))
            t_abs += 1
    return out


U = (330, 820, 2400)   # vowel "oo"
W = (280, 620, 2200)   # "w": formants dip


def uwu(length=1.0, p0=430, p1=560, end_rise=True):
    seg = [
        (0.05 * length, U, U, 0.0, 1.0),     # attack
        (0.12 * length, U, U, 1.0, 0.95),    # "u"
        (0.07 * length, U, W, 0.95, 0.35),   # into "w"
        (0.06 * length, W, U, 0.35, 0.95),   # out of "w"
        (0.22 * length, U, U, 0.95, 0.8),    # "u"
        (0.08 * length, U, U, 0.8, 0.0),     # release
    ]

    def pitch(g):
        base = lerp(p0, p1, g)
        if end_rise and g > 0.55:
            base *= 1 + 0.35 * ((g - 0.55) / 0.45) ** 2  # the cute upturn at the end
        return base

    return voice(seg, pitch)


def bell(freq, dur, amp=0.5):
    n = int(dur * SR)
    return [amp * math.exp(-5 * i / n) * (math.sin(2 * math.pi * freq * i / SR) + 0.3 * math.sin(2 * math.pi * freq * 2.01 * i / SR)) for i in range(n)]


def silence(s):
    return [0.0] * int(s * SR)


def mix(*tracks):
    """tracks: (start_seconds, samples)"""
    n = max(int(st * SR) + len(x) for st, x in tracks)
    out = [0.0] * n
    for st, x in tracks:
        o = int(st * SR)
        for i, v in enumerate(x):
            out[o + i] += v
    return out


def write(name, x, gain_db=-3.0):
    peak = max(1e-9, max(abs(v) for v in x))
    g = 10 ** (gain_db / 20) / peak
    # tiny fade in/out against clicks
    fade = int(0.004 * SR)
    for i in range(min(fade, len(x))):
        x[i] *= i / fade
        x[-1 - i] *= i / fade
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * g)) * 32767)) for v in x))
    print(f"{name}: {len(x) / SR:.2f}s")


write("uwu_set.wav", uwu(0.55, 470, 560))
write("uwu_exercise.wav", mix((0.0, bell(1319, 0.25, 0.35)), (0.09, bell(1760, 0.3, 0.3)), (0.16, uwu(0.8, 440, 600))))
write("uwu_workout.wav", mix(
    (0.00, bell(1047, 0.30, 0.35)), (0.12, bell(1319, 0.30, 0.35)), (0.24, bell(1568, 0.35, 0.35)), (0.36, bell(2093, 0.6, 0.4)),
    (0.42, uwu(1.3, 420, 640)),
    (1.55, uwu(0.6, 520, 700)),
))
write("rest_over.wav", mix((0.0, bell(880, 0.5, 0.5)), (0.18, bell(1175, 0.7, 0.5))))
write("simple_set.wav", bell(1046, 0.18, 0.5))
write("simple_exercise.wav", mix((0.0, bell(1046, 0.2, 0.5)), (0.1, bell(1568, 0.3, 0.5))))
write("simple_workout.wav", mix((0.0, bell(784, 0.25, 0.5)), (0.12, bell(1046, 0.25, 0.5)), (0.24, bell(1568, 0.5, 0.5))))
