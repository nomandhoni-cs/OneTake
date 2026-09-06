#!/usr/bin/env python3
"""Generate the six SIZE-32 Adobe `.cube` grades for OneTake.

Deterministic parametric recipes (lift/gamma/gain + saturation + two-tone)
baked on a 32^3 lattice, R fastest — the order `CIColorCube` expects.
Output: `OneTake/Resources/<name>.cube` (~800KB each vs 4MB legacy 64^3).

Usage:  python3 tools/generate_luts.py
Checks: asserts every value in [0,1], prints min/max + identity distance.
"""
import os

SIZE = 32
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "OneTake", "Resources")


def clamp01(x):
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


def luma(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def lift_gamma_gain(x, lift, gamma, gain):
    return clamp01(gain * (max(x, 0.0) ** gamma) + lift)


def grade_lgg_sat(r, g, b, lift, gamma, gain, sat):
    r = lift_gamma_gain(r, lift[0], gamma[0], gain[0])
    g = lift_gamma_gain(g, lift[1], gamma[1], gain[1])
    b = lift_gamma_gain(b, lift[2], gamma[2], gain[2])
    lum = luma(r, g, b)
    return (clamp01(lum + (r - lum) * sat),
            clamp01(lum + (g - lum) * sat),
            clamp01(lum + (b - lum) * sat))


def smoothstep(edge0, edge1, x):
    t = clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def golden_hour(r, g, b):
    return grade_lgg_sat(r, g, b,
                         lift=(0.0, 0.0, 0.0), gamma=(1.0, 1.0, 1.0),
                         gain=(1.10, 1.00, 0.88), sat=1.12)


def teal_orange(r, g, b):
    t = smoothstep(0.25, 0.75, luma(r, g, b))  # 0 shadows -> 1 highlights
    cool = (r * 0.90, g * 1.00, b * 1.10)      # teal shadows
    warm = (r * 1.08, g * 1.00, b * 0.90)      # orange highlights
    r2 = cool[0] + (warm[0] - cool[0]) * t
    g2 = cool[1] + (warm[1] - cool[1]) * t
    b2 = cool[2] + (warm[2] - cool[2]) * t
    lum = luma(r2, g2, b2)
    sat = 1.15
    return (clamp01(lum + (r2 - lum) * sat),
            clamp01(lum + (g2 - lum) * sat),
            clamp01(lum + (b2 - lum) * sat))


def faded_film(r, g, b):
    return grade_lgg_sat(r, g, b,
                         lift=(0.07, 0.07, 0.07), gamma=(1.0, 1.0, 1.0),
                         gain=(0.95, 0.95, 0.95), sat=0.82)


def noir(r, g, b):
    lum = luma(r, g, b)
    x = clamp01(0.5 + (lum - 0.5) * 1.7)  # crushed high-contrast mono
    return (x, x, x)


def vibrant_pop(r, g, b):
    r, g, b = (clamp01(0.5 + (c - 0.5) * 1.12) for c in (r, g, b))
    lum = luma(r, g, b)
    sat = 1.30
    return (clamp01(lum + (r - lum) * sat),
            clamp01(lum + (g - lum) * sat),
            clamp01(lum + (b - lum) * sat))


def cool_morning(r, g, b):
    return grade_lgg_sat(r, g, b,
                         lift=(0.0, 0.0, 0.0), gamma=(1.04, 1.02, 1.00),
                         gain=(0.92, 0.97, 1.08), sat=0.95)


PRESETS = {
    "golden_hour": ("Golden Hour", golden_hour),
    "teal_orange": ("Teal & Orange", teal_orange),
    "faded_film": ("Faded Film", faded_film),
    "noir": ("Noir Punch", noir),
    "vibrant_pop": ("Vibrant Pop", vibrant_pop),
    "cool_morning": ("Cool Morning", cool_morning),
}


def bake(fn):
    """Evaluate fn over the lattice, R fastest. Returns flat [(r,g,b)]."""
    out = []
    lo, hi = 1e9, -1e9
    ident = 0.0
    for bi in range(SIZE):
        for gi in range(SIZE):
            for ri in range(SIZE):
                r, g, b = ri / (SIZE - 1), gi / (SIZE - 1), bi / (SIZE - 1)
                nr, ng, nb = fn(r, g, b)
                assert 0.0 <= nr <= 1.0 and 0.0 <= ng <= 1.0 and 0.0 <= nb <= 1.0, \
                    f"out of range: {(nr, ng, nb)}"
                out.append((nr, ng, nb))
                lo = min(lo, nr, ng, nb)
                hi = max(hi, nr, ng, nb)
                ident += abs(nr - r) + abs(ng - g) + abs(nb - b)
    assert len(out) == SIZE ** 3
    return out, lo, hi, ident / len(out)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (title, fn) in PRESETS.items():
        lattice, lo, hi, ident = bake(fn)
        path = os.path.join(OUT_DIR, f"{name}.cube")
        with open(path, "w") as f:
            f.write(f'TITLE "{title}"\n')
            f.write(f"LUT_3D_SIZE {SIZE}\n")
            f.write("DOMAIN_MIN 0.0 0.0 0.0\n")
            f.write("DOMAIN_MAX 1.0 1.0 1.0\n")
            for r, g, b in lattice:
                f.write(f"{r:.6f} {g:.6f} {b:.6f}\n")
        kb = os.path.getsize(path) // 1024
        print(f"{name}.cube  {kb}KB  range=[{lo:.3f},{hi:.3f}]  mean|delta-vs-identity|={ident:.4f}")


if __name__ == "__main__":
    main()
