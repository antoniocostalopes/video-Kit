"""
_lib.py — helpers partilhados pelos scripts Python da skill.

Importa via:
    from _lib import require_deps, find_install_feature
"""
from __future__ import annotations

import sys
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parent.parent


def find_install_feature() -> tuple[str, str]:
    """Devolve (caminho-relativo, comando-completo) para install-feature
    apropriado a esta plataforma."""
    if sys.platform.startswith("win"):
        path = SKILL_DIR / "scripts" / "install-feature.ps1"
        cmd_prefix = f'& "{path}"'
    else:
        path = SKILL_DIR / "scripts" / "install-feature.sh"
        cmd_prefix = f'bash "{path}"'
    return str(path), cmd_prefix


def require_deps(feature: str, modules: list[str], extras: str | None = None) -> None:
    """Verifica dependencias e devolve mensagem clara com comando de install.

    feature: nome em install-feature (core, diarization, translation, tts, audio-separation, bg-removal)
    modules: lista de imports a verificar (e.g. ["whisper", "torch"])
    extras: instrucao adicional (e.g. setup de HF_TOKEN para diarization)

    Aborta com exit 2 se faltar alguma dep, com mensagem accionavel.
    """
    missing = []
    for m in modules:
        try:
            __import__(m)
        except ImportError:
            missing.append(m)
    if not missing:
        return

    _, install_cmd = find_install_feature()
    print(
        f"ERRO: dependencia(s) em falta para feature '{feature}': {', '.join(missing)}",
        file=sys.stderr,
    )
    print("", file=sys.stderr)
    print("Para instalar corre:", file=sys.stderr)
    print(f"  {install_cmd} {feature}", file=sys.stderr)
    print("", file=sys.stderr)
    if extras:
        print(extras, file=sys.stderr)
        print("", file=sys.stderr)
    sys.exit(2)
