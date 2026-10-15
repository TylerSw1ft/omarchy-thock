#!/usr/bin/env python3
"""Synthesize the key samples in ../sounds/.

Every profile is built at five depths and five cream levels and written to
sounds/<profile>/depth<0-4>-cream<0-4>/. The bar panel switches between them
live, since Qt's SoundEffect can't reshape a sound at runtime.

  Depth (DEPTHS below) lowers the body and case thump, darkens the texture
  slightly. Default 2.
  Cream (CREAMS below) softens the attack, quiets the click, darkens the
  tone, swaps the grainy noise impact for smooth damped partials, and fades
  out overtones and stabilizer
  rattle. Level 1 is each profile exactly as tuned, level 0 is crisper than
  that, and the default, 3, is well past it.

  q-cream   A Keychron Q-series with creamy, lubed linear switches: a slow,
            rounded attack with almost no click, a dark smooth impact, a deep
            body over a strong aluminium-case thump, no ring, quiet
            stabilizers and a soft top-out.
  keychron  A brighter, clackier Keychron with tactile switches and PBT
            caps: a crisp bottom-out clack, a poppy mid-range body, a faint
            case ring, and a higher click when the key springs back up.
  thock     The original: a low, muted knock with no upstroke.

Everything is generated, so the plugin ships no third-party audio. Re-run
after tweaking the numbers:

    python3 tools/make-sounds.py              # all profiles
    python3 tools/make-sounds.py q-cream      # just one
"""

import math
import os
import random
import shutil
import struct
import sys
import wave

RATE = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")

# Pitch factor per depth level, brightest (0) to deepest (4).
DEPTHS = [1.15, 1.0, 0.86, 0.74, 0.64]

# Cream amount per level, crisp (0) to creamiest (4); 0.0 is the profile as
# tuned, negative is crisper. Past 1.0 the sound stops getting darker (so it
# stays audible on laptop speakers) and only gets smoother: the last of the
# noise grain goes.
CREAMS = [-0.6, 0.0, 0.5, 1.0, 1.4]

# Everything is dry: no setting lets a sound ring on. Resonant tails (body,
# case thump, impact partials) decay this much faster than tuned, the case
# ring is dropped, and a gate holds each strike for GATE_HOLD of its length,
# then clamps it down with a GATE_TAU release. Samples are cut off once they
# fall below SILENCE_DB.
DAMP = 0.4
GATE_HOLD = 0.15
GATE_TAU = 0.003
SILENCE_DB = -40


def lowpass(samples, cutoff):
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    y, out = 0.0, []
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def bandpass(samples, low, high):
    hi = lowpass(lowpass(samples, high), high)
    lo = lowpass(lowpass(samples, low), low)
    return [h - l for h, l in zip(hi, lo)]


def decay(t, tau):
    return math.exp(-t / tau)


def finish(out, gain=0.85, fade=0.004):
    """Cut the sample where it falls below SILENCE_DB, fade the last `fade`
    seconds out (raised cosine) and normalize."""
    peak = max(abs(s) for s in out) or 1
    floor = peak * 10 ** (SILENCE_DB / 20)
    end = max(i for i, s in enumerate(out) if abs(s) >= floor) + 1
    out = out[:end]
    n = len(out)
    fade_n = min(n - 1, max(1, int(RATE * fade)))
    for i in range(fade_n):
        out[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade_n)
    peak = max(abs(s) for s in out) or 1
    return [s / peak * gain for s in out]


def rms(samples):
    return math.sqrt(sum(s * s for s in samples) / max(1, len(samples))) or 1.0


def strike(rng, pitch, cream, length, f0, body_tau, click, click_band, impact, impact_band,
           impact_tau, overtone=1.25, overtone_amp=0.45, ring=0.0, ring_f=3100,
           rattle=0.0, gain=0.85, sub=0.0, sub_f=160, attack=0.0006, tone=None):
    """One contact: transient click, plastic impact, resonant body, case ring,
    and optionally a low thump from a heavy case (sub).

    pitch scales the tuned parts (body, overtone, case thump) fully and the
    noisy texture (click, impact, ring, tone) only gently. Small speakers
    can't reproduce a deep fundamental, and the ear infers it from the
    texture above, so dragging the texture down too would make deep settings
    near-silent on a laptop rather than deeper.

    cream > 0 makes the strike creamier and < 0 crisper; see CREAMS. Darkening
    stops at 1.0. Smoothing keeps going: the impact, normally band-passed
    noise, is crossfaded into a cluster of short damped partials in the same
    band. Noise always carries a faint hiss and grain; the partials give the
    same "tock" with neither, which is what reads as buttery rather than
    muffled. attack is the rise time: longer reads as softer and creamier.
    tone, if given, is a final low-pass cutoff that darkens the whole strike.
    """
    dark = min(cream, 1.0)
    smooth = max(0.0, cream)
    grain = 1.0  # share of the impact that is noise rather than partials
    fade = 0.004
    body_tau *= DAMP
    ring = 0.0
    if cream:
        click *= max(0.03, 1 - 0.85 * cream)
        attack = min(attack * 2 ** (1.5 * dark), max(attack, 0.005))
        # Profiles tuned without a tone filter still get one once creamed.
        tone = (tone or 9000) * 2 ** (-0.9 * dark)
        impact_band = (impact_band[0], impact_band[1] * 2 ** (-0.35 * dark))
        overtone_amp *= 2 ** (-1.2 * cream)
        ring *= 2 ** (-2 * cream)
        rattle *= 2 ** (-1.5 * cream)
        grain = max(0.0, min(1.0, 1 - 0.75 * smooth))

    f0 *= pitch
    sub_f *= pitch
    texture = pitch ** 0.3
    ring_f *= texture
    click_band = tuple(f * texture for f in click_band)
    impact_band = tuple(f * texture for f in impact_band)

    n = int(RATE * length)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    click_n = bandpass(noise, *click_band)
    impact_n = bandpass(noise, *impact_band)
    f1 = f0 * overtone * rng.uniform(2.3, 2.7)
    ring_f *= rng.uniform(0.97, 1.03)
    p0, p1, p2 = (rng.uniform(0, 6.28) for _ in range(3))

    # The impact as noise, then (when creamed) as partials matched to the
    # noise's loudness, mixed by grain.
    impact_sig = [impact_n[i] * 5 * decay(i / RATE, impact_tau) for i in range(n)]
    if grain < 1.0:
        lo, hi = impact_band
        partials = [(math.exp(rng.uniform(math.log(lo), math.log(hi))),
                     impact_tau * DAMP * rng.uniform(0.8, 1.2), rng.uniform(0.5, 1.0),
                     rng.uniform(0, 6.28)) for _ in range(6)]
        modal = [sum(a * math.sin(2 * math.pi * f * (i / RATE) + ph) * decay(i / RATE, tau)
                     for f, tau, a, ph in partials) for i in range(n)]
        scale = rms(impact_sig) / rms(modal)
        impact_sig = [grain * x + (1 - grain) * m * scale for x, m in zip(impact_sig, modal)]

    out = []
    for i in range(n):
        t = i / RATE
        # Raised-cosine rise: no corner at the start, so no extra click.
        rise = 0.5 - 0.5 * math.cos(math.pi * min(1.0, t / attack))
        s = click * click_n[i] * 6 * decay(t, 0.0016)
        s += impact * impact_sig[i]
        s += math.sin(2 * math.pi * f0 * t + p0) * decay(t, body_tau)
        s += overtone_amp * math.sin(2 * math.pi * f1 * t + p1) * decay(t, body_tau * 0.4)
        if sub:
            s += sub * math.sin(2 * math.pi * sub_f * t + p0) * decay(t, body_tau)
        if ring:
            s += ring * math.sin(2 * math.pi * ring_f * t + p2) * decay(t, 0.022)
        if rattle:
            # Stabilizer wire tapping its housing a moment after bottom-out.
            t2 = t - 0.009
            if t2 > 0:
                s += rattle * impact_n[i] * 5 * decay(t2, 0.004)
        out.append(s * rise)
    if tone:
        out = lowpass(lowpass(out, tone * texture), tone * texture)
    hold = GATE_HOLD * length
    out = [x * (decay(i / RATE - hold, GATE_TAU) if i / RATE > hold else 1.0)
           for i, x in enumerate(out)]
    return finish(out, gain, fade)


def q_cream(rng, pitch, cream):
    # Q-series: heavy aluminium case, gasket mount and foam, lubed linear
    # switches, lubed stabilizers. Creaminess here is mostly what's missing:
    # no sharp tick, no bright noise, no ring. What's left is a slow, rounded
    # attack into a smooth, dark-but-present impact (the "cream" you actually
    # hear on small speakers), a deep body and a strong case thump.
    def s(*args, **kw):
        return strike(rng, pitch, cream, *args, **kw)
    for i in range(1, 7):
        yield f"key{i}.wav", s(
            0.09, rng.uniform(250, 285), rng.uniform(0.020, 0.024),
            click=0.1, click_band=(900, 2800),
            impact=1.0, impact_band=(450, 1600), impact_tau=0.009,
            overtone=1.05, overtone_amp=0.25, sub=0.6, sub_f=rng.uniform(120, 135),
            attack=0.0022, tone=3400)
    for i in range(1, 5):
        yield f"up{i}.wav", s(
            0.045, rng.uniform(380, 440), 0.008,
            click=0.06, click_band=(900, 2800),
            impact=0.55, impact_band=(550, 1800), impact_tau=0.004,
            overtone=1.05, overtone_amp=0.2, attack=0.0018, tone=3200, gain=0.2)
    yield "space.wav", s(
        0.14, 165, 0.032, click=0.06, click_band=(800, 2500),
        impact=0.95, impact_band=(350, 1300), impact_tau=0.012,
        overtone=1.0, overtone_amp=0.22, sub=0.6, sub_f=85, rattle=0.08,
        attack=0.0028, tone=3000)
    yield "space-up.wav", s(
        0.055, 270, 0.011, click=0.05, click_band=(800, 2500),
        impact=0.55, impact_band=(450, 1500), impact_tau=0.005,
        overtone_amp=0.2, rattle=0.05, attack=0.0018, tone=3000, gain=0.24)
    yield "enter.wav", s(
        0.12, 205, 0.026, click=0.08, click_band=(900, 2800),
        impact=0.95, impact_band=(400, 1400), impact_tau=0.010,
        overtone=1.0, overtone_amp=0.22, sub=0.5, sub_f=100, rattle=0.06,
        attack=0.0025, tone=3200)
    yield "backspace.wav", s(
        0.12, 220, 0.024, click=0.08, click_band=(900, 2800),
        impact=0.95, impact_band=(400, 1400), impact_tau=0.010,
        overtone=1.0, overtone_amp=0.22, sub=0.5, sub_f=108, rattle=0.05,
        attack=0.0025, tone=3200)


def keychron(rng, pitch, cream):
    def s(*args, **kw):
        return strike(rng, pitch, cream, *args, **kw)
    for i in range(1, 7):
        yield f"key{i}.wav", s(
            0.075, rng.uniform(400, 500), rng.uniform(0.010, 0.014),
            click=0.65, click_band=(2500, 7000),
            impact=0.8, impact_band=(900, 2600), impact_tau=0.005,
            ring=0.05)
    for i in range(1, 5):
        # Upstroke: the stem slapping the top housing. Quieter and higher.
        yield f"up{i}.wav", s(
            0.045, rng.uniform(620, 760), 0.006,
            click=0.45, click_band=(3000, 8000),
            impact=0.35, impact_band=(1400, 3500), impact_tau=0.003,
            gain=0.32)
    yield "space.wav", s(
        0.12, 235, 0.026, click=0.35, click_band=(2000, 6000),
        impact=0.75, impact_band=(600, 1800), impact_tau=0.008,
        overtone=1.1, ring=0.06, rattle=0.45)
    yield "space-up.wav", s(
        0.06, 380, 0.010, click=0.3, click_band=(2500, 7000),
        impact=0.5, impact_band=(900, 2400), impact_tau=0.004,
        rattle=0.3, gain=0.38)
    yield "enter.wav", s(
        0.1, 300, 0.020, click=0.45, click_band=(2500, 7000),
        impact=0.7, impact_band=(700, 2200), impact_tau=0.006,
        ring=0.05, rattle=0.3)
    yield "backspace.wav", s(
        0.1, 330, 0.018, click=0.45, click_band=(2500, 7000),
        impact=0.7, impact_band=(700, 2200), impact_tau=0.006,
        ring=0.05, rattle=0.25)


def thock(rng, pitch, cream):
    def knock(f0, tau, length, rattle=0.0):
        return strike(rng, pitch, cream, length, f0, tau, click=0.12, click_band=(300, 3200),
                      impact=0.5, impact_band=(150, 900), impact_tau=0.009,
                      overtone=1.0, rattle=rattle)
    for i in range(1, 7):
        yield f"key{i}.wav", knock(rng.uniform(190, 250), rng.uniform(0.020, 0.028), 0.09)
    yield "space.wav", knock(128, 0.040, 0.14, rattle=0.35)
    yield "enter.wav", knock(150, 0.034, 0.12, rattle=0.2)
    yield "backspace.wav", knock(165, 0.030, 0.11, rattle=0.15)


PROFILES = {"q-cream": q_cream, "keychron": keychron, "thock": thock}


def write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))


def build(profile):
    root = os.path.join(OUT, profile)
    shutil.rmtree(root, ignore_errors=True)
    for d, pitch in enumerate(DEPTHS):
        for c, cream in enumerate(CREAMS):
            out = os.path.join(root, f"depth{d}-cream{c}")
            os.makedirs(out)
            # Same seed everywhere, so the sliders change only what they say.
            for name, samples in PROFILES[profile](random.Random(7), pitch, cream):
                write(os.path.join(out, name), samples)


def main():
    wanted = sys.argv[1:] or list(PROFILES)
    for profile in wanted:
        if profile not in PROFILES:
            sys.exit(f"unknown profile {profile!r}; choose from {', '.join(PROFILES)}")
    for profile in wanted:
        build(profile)


if __name__ == "__main__":
    main()
