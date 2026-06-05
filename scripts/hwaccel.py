#!/usr/bin/env python3
"""
hwaccel.py — Resolve hwaccel + codec args para FFmpeg conforme env-report.json.

Modos de --hwaccel:
  none      — sempre libx264 software (default)
  auto      — escolhe melhor disponível: nvenc > videotoolbox > qsv > amf > none
  nvenc     — NVIDIA NVENC (Windows/Linux com placa NVIDIA)
  videotoolbox — Apple Silicon / Intel Mac (macOS)
  qsv       — Intel Quick Sync Video
  amf       — AMD Advanced Media Framework

Uso programático:
  from hwaccel import resolve_codec_args
  args = resolve_codec_args(quality="final", hwaccel="auto")
  # → ["-c:v", "h264_nvenc", "-preset", "p7", ...]

Uso CLI (para debug ou Bash):
  python hwaccel.py --quality final --hwaccel auto
  # imprime args separados por espaço, prontos para usar em $(...)
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# Tabela de mapeamento: (quality, hwaccel) → ffmpeg args
#
# Notas de qualidade:
#  - libx264 -preset slow -crf 18 produz o melhor resultado a igual bitrate.
#  - NVENC/VideoToolbox são 5-10× mais rápidos mas precisam ~30% mais bitrate
#    para alcançar a mesma qualidade percetual.
#  - Para "draft" (preview) qualquer encoder serve, prioridade é velocidade.
# ---------------------------------------------------------------------------

PROFILES = {
    "final": {
        "none":          ["-c:v", "libx264", "-preset", "slow", "-crf", "18",
                          "-pix_fmt", "yuv420p", "-movflags", "+faststart"],
        "nvenc":         ["-c:v", "h264_nvenc", "-preset", "p7", "-tune", "hq",
                          "-rc", "vbr", "-cq", "19", "-b:v", "0",
                          "-pix_fmt", "yuv420p", "-movflags", "+faststart"],
        "videotoolbox":  ["-c:v", "h264_videotoolbox", "-q:v", "65",
                          "-pix_fmt", "yuv420p", "-movflags", "+faststart"],
        "qsv":           ["-c:v", "h264_qsv", "-preset", "veryslow",
                          "-global_quality", "20",
                          "-pix_fmt", "yuv420p", "-movflags", "+faststart"],
        "amf":           ["-c:v", "h264_amf", "-quality", "quality",
                          "-rc", "vbr_peak", "-qp_i", "19", "-qp_p", "21",
                          "-pix_fmt", "yuv420p", "-movflags", "+faststart"],
    },
    "draft": {
        "none":          ["-c:v", "libx264", "-preset", "ultrafast", "-crf", "28",
                          "-pix_fmt", "yuv420p"],
        "nvenc":         ["-c:v", "h264_nvenc", "-preset", "p1",
                          "-rc", "vbr", "-cq", "30", "-b:v", "0",
                          "-pix_fmt", "yuv420p"],
        "videotoolbox":  ["-c:v", "h264_videotoolbox", "-q:v", "45",
                          "-pix_fmt", "yuv420p"],
        "qsv":           ["-c:v", "h264_qsv", "-preset", "veryfast",
                          "-global_quality", "30",
                          "-pix_fmt", "yuv420p"],
        "amf":           ["-c:v", "h264_amf", "-quality", "speed",
                          "-rc", "cqp", "-qp_i", "30", "-qp_p", "32",
                          "-pix_fmt", "yuv420p"],
    },
}

PRIORITY_BY_OS = {
    "windows": ["nvenc", "qsv", "amf"],
    "linux":   ["nvenc", "qsv", "amf"],
    "macos":   ["videotoolbox"],
}


def load_env_report() -> dict:
    p = SKILL_DIR / "cache" / "env-report.json"
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}


def detect_best_hwaccel(env: dict) -> str:
    """Devolve o nome do melhor encoder HW disponível, ou 'none'."""
    hw = (env.get("hw_encoders") or {})
    os_name = (env.get("os") or "").lower()
    priorities = PRIORITY_BY_OS.get(os_name, ["nvenc", "videotoolbox", "qsv", "amf"])
    for name in priorities:
        if hw.get(name):
            return name
    return "none"


def resolve_codec_args(quality: str = "final", hwaccel: str = "none",
                       env: dict | None = None) -> list[str]:
    """Devolve a lista de args ffmpeg (video codec + pix_fmt).
    Faz fallback para 'none' se o pedido não está disponível."""
    if quality not in PROFILES:
        raise ValueError(f"quality invalida: {quality} (use 'final' ou 'draft')")
    if env is None:
        env = load_env_report()

    if hwaccel == "auto":
        hwaccel = detect_best_hwaccel(env)

    # Validar disponibilidade — se pediram explicitamente NVENC mas a placa não tem,
    # cai para software com aviso.
    if hwaccel not in ("none", "auto"):
        hw = (env.get("hw_encoders") or {})
        if not hw.get(hwaccel):
            print(
                f"AVISO hwaccel: '{hwaccel}' pedido mas nao detetado neste sistema. "
                f"A usar software (libx264).",
                file=sys.stderr,
            )
            hwaccel = "none"

    return list(PROFILES[quality].get(hwaccel, PROFILES[quality]["none"]))


def main():
    ap = argparse.ArgumentParser(description="Resolve codec args ffmpeg conforme hwaccel.")
    ap.add_argument("--quality", choices=list(PROFILES.keys()), default="final")
    ap.add_argument("--hwaccel", default="none",
                    choices=["none", "auto", "nvenc", "videotoolbox", "qsv", "amf"])
    ap.add_argument("--list", action="store_true",
                    help="Lista todas as combinações disponíveis e sai.")
    args = ap.parse_args()

    if args.list:
        env = load_env_report()
        hw = env.get("hw_encoders") or {}
        print(f"OS: {env.get('os', 'unknown')}")
        print(f"Best hwaccel auto-detect: {detect_best_hwaccel(env)}")
        print()
        for qual in PROFILES:
            print(f"=== quality={qual} ===")
            for name in PROFILES[qual]:
                marker = "✓" if (name == "none" or hw.get(name)) else "✗"
                args_str = " ".join(PROFILES[qual][name])
                print(f"  {marker} --hwaccel {name:<12} : {args_str}")
            print()
        return

    out = resolve_codec_args(args.quality, args.hwaccel)
    print(" ".join(out))


if __name__ == "__main__":
    main()
