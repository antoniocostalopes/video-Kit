#!/usr/bin/env python3
"""
gen-luts.py — Gera ficheiros .cube procedurais e escreve em assets/luts/.

Os LUTs sao 17x17x17 (tamanho razoavel, ~80KB por ficheiro).
Aplicaveis com FFmpeg lut3d filter.

Uso:
  python gen-luts.py
"""
from __future__ import annotations

import math
from pathlib import Path

SIZE = 17

SKILL_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = SKILL_DIR / "assets" / "luts"


def clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, v))


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)


# ---------- Look definitions ----------

def look_identity(r: float, g: float, b: float):
    return r, g, b


def look_warm(r: float, g: float, b: float):
    """Boost laranjas/amarelos, tira azuis. Tonalidade de sunset/golden hour."""
    nr = clamp(r * 1.08 + 0.03)
    ng = clamp(g * 1.02 + 0.015)
    nb = clamp(b * 0.88 - 0.02)
    return nr, ng, nb


def look_cool(r: float, g: float, b: float):
    """Boost azuis/cyans, tira vermelhos. Look tech/winter."""
    nr = clamp(r * 0.92 - 0.02)
    ng = clamp(g * 1.0 + 0.0)
    nb = clamp(b * 1.10 + 0.04)
    return nr, ng, nb


def look_cinematic(r: float, g: float, b: float):
    """Teal-orange grade popular em filmes.
       Shadows -> teal/blue. Highlights -> orange. Mid contrast aumentado."""
    # Luminance approximation
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

    # Shadow tint (teal): peso de shadow = 1 - smoothstep(0, 0.4, lum)
    shadow_w = 1.0 - smoothstep(0.0, 0.45, lum)
    # Highlight tint (orange): smoothstep(0.5, 1, lum)
    high_w = smoothstep(0.55, 1.0, lum)

    # Aplicar tints
    nr = r + (-0.04) * shadow_w + 0.06 * high_w
    ng = g + 0.02 * shadow_w + 0.02 * high_w
    nb = b + 0.07 * shadow_w + (-0.06) * high_w

    # S-curve para contraste
    def s_curve(x: float) -> float:
        return 0.5 + 0.5 * math.tanh(2.5 * (x - 0.5))

    nr = s_curve(clamp(nr))
    ng = s_curve(clamp(ng))
    nb = s_curve(clamp(nb))

    # Saturacao leve +10%
    avg = (nr + ng + nb) / 3
    nr = clamp(avg + (nr - avg) * 1.1)
    ng = clamp(avg + (ng - avg) * 1.1)
    nb = clamp(avg + (nb - avg) * 1.1)

    return nr, ng, nb


def look_bw(r: float, g: float, b: float):
    """Black & white com pequeno contraste."""
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    # Slight S-curve
    lum = 0.5 + 0.5 * math.tanh(2.0 * (lum - 0.5))
    return lum, lum, lum


# ---------- Generator ----------

def write_cube(name: str, look_fn, description: str):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{name}.cube"

    lines = [
        f"# {description}",
        f"# Generated procedurally by videokit gen-luts.py",
        f"TITLE \"{name}\"",
        f"LUT_3D_SIZE {SIZE}",
        "DOMAIN_MIN 0.0 0.0 0.0",
        "DOMAIN_MAX 1.0 1.0 1.0",
        "",
    ]

    step = 1.0 / (SIZE - 1)
    # cube order: B outermost, then G, then R innermost (fastest)
    for ib in range(SIZE):
        for ig in range(SIZE):
            for ir in range(SIZE):
                r = ir * step
                g = ig * step
                b = ib * step
                nr, ng, nb = look_fn(r, g, b)
                lines.append(f"{nr:.6f} {ng:.6f} {nb:.6f}")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    size_kb = path.stat().st_size / 1024
    print(f"OK {path.name} ({size_kb:.1f} KB)")


def main():
    write_cube("identity", look_identity, "Identity LUT (no-op, useful baseline).")
    write_cube("warm", look_warm, "Warm look: golden hour, sunset.")
    write_cube("cool", look_cool, "Cool look: tech, winter, modern.")
    write_cube("cinematic", look_cinematic, "Teal-orange cinematic grade.")
    write_cube("bw", look_bw, "Black & white with mild contrast.")
    print(f"\nLUTs em: {OUT_DIR}")


if __name__ == "__main__":
    main()
