#!/usr/bin/env python3
"""
narrate.py — TTS local via Piper (PT-PT, PT-BR, EN-US, etc.).

Gera narracao WAV a partir de texto. Modelos descarregados na primeira utilizacao
de huggingface.co/rhasspy/piper-voices.

Uso:
  python narrate.py --text "Olá mundo" --output narration.wav --voice pt_PT-tugao
  python narrate.py --text-file script.txt --output narration.wav --voice en_US-amy

Vozes disponiveis (descarregadas sob demanda):
  - pt_PT-tugao       (Portugues europeu, M)
  - pt_BR-faber       (Portugues brasileiro, M)
  - pt_BR-edresson    (Portugues brasileiro, M, low quality - mais rapido)
  - en_US-amy         (Ingles americano, F)
  - en_US-lessac      (Ingles americano, neutral)
  - en_GB-alan        (Ingles britanico, M)
  - es_ES-davefx      (Espanhol)
  - fr_FR-siwis       (Frances, F)

Requer:
  pip install piper-tts
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

VOICES_BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main"

# Mapping: voice_id -> (HF path, quality)
VOICE_CATALOG = {
    "pt_PT-tugao":    ("pt/pt_PT/tugão/medium/pt_PT-tugão-medium",  "medium"),
    "pt_BR-faber":    ("pt/pt_BR/faber/medium/pt_BR-faber-medium",   "medium"),
    "pt_BR-edresson": ("pt/pt_BR/edresson/low/pt_BR-edresson-low",   "low"),
    "en_US-amy":      ("en/en_US/amy/medium/en_US-amy-medium",       "medium"),
    "en_US-lessac":   ("en/en_US/lessac/medium/en_US-lessac-medium", "medium"),
    "en_GB-alan":     ("en/en_GB/alan/medium/en_GB-alan-medium",     "medium"),
    "es_ES-davefx":   ("es/es_ES/davefx/medium/es_ES-davefx-medium", "medium"),
    "fr_FR-siwis":    ("fr/fr_FR/siwis/medium/fr_FR-siwis-medium",   "medium"),
}


def url_encode_path(p: str) -> str:
    """URL-encode partes do path mantendo /."""
    parts = p.split("/")
    return "/".join(urllib.request.quote(x, safe="") for x in parts)


def ensure_voice(voice_id: str, models_dir: Path):
    """Descarrega modelo .onnx + .onnx.json se necessario."""
    if voice_id not in VOICE_CATALOG:
        print(f"ERRO: voice '{voice_id}' desconhecida. Disponiveis: {', '.join(VOICE_CATALOG)}", file=sys.stderr)
        sys.exit(2)

    hf_path, _quality = VOICE_CATALOG[voice_id]
    encoded_path = url_encode_path(hf_path)

    onnx_url = f"{VOICES_BASE}/{encoded_path}.onnx"
    json_url = f"{VOICES_BASE}/{encoded_path}.onnx.json"

    models_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = models_dir / f"{voice_id}.onnx"
    json_path = models_dir / f"{voice_id}.onnx.json"

    if not onnx_path.exists():
        print(f"A descarregar voice model {voice_id}.onnx (~50-100MB)...")
        urllib.request.urlretrieve(onnx_url, str(onnx_path))
        print(f"  OK {onnx_path.stat().st_size / 1024 / 1024:.1f} MB")
    if not json_path.exists():
        print(f"A descarregar voice config {voice_id}.onnx.json...")
        urllib.request.urlretrieve(json_url, str(json_path))
        print(f"  OK")

    return onnx_path


def synthesize(text: str, voice_onnx: Path, output_wav: Path):
    """Sintetiza texto -> WAV usando Piper."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _lib import require_deps
    require_deps("tts", ["piper"])
    import wave
    from piper import PiperVoice

    print(f"A carregar Piper voice {voice_onnx.name}...")
    voice = PiperVoice.load(str(voice_onnx))

    print(f"A sintetizar {len(text)} chars...")
    output_wav.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output_wav), "wb") as wav_file:
        voice.synthesize(text, wav_file)
    print(f"OK escrito em {output_wav} ({output_wav.stat().st_size / 1024:.1f} KB)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", help="Texto a sintetizar (use --text-file para input maior)")
    ap.add_argument("--text-file", type=Path, help="Ficheiro com o texto")
    ap.add_argument("--output", required=True, type=Path, help="Output WAV")
    ap.add_argument("--voice", required=True, help=f"Voice ID (uma de: {', '.join(VOICE_CATALOG)})")
    args = ap.parse_args()

    if not args.text and not args.text_file:
        print("ERRO: --text ou --text-file obrigatorio.", file=sys.stderr)
        sys.exit(2)

    text = args.text if args.text else args.text_file.read_text(encoding="utf-8").strip()
    if not text:
        print("ERRO: texto vazio.", file=sys.stderr)
        sys.exit(1)

    # Models cache em <skill>/assets/voice-models/
    skill_dir = Path(__file__).resolve().parent.parent
    models_dir = skill_dir / "assets" / "voice-models"

    voice_onnx = ensure_voice(args.voice, models_dir)
    synthesize(text, voice_onnx, args.output)


if __name__ == "__main__":
    main()
