#!/usr/bin/env bash
# install-feature.sh — Instala pacotes Python por feature pack.
#
# Uso: ./install-feature.sh <feature> [--upgrade]
#
# Features:
#   core               whisper + mediapipe + opencv-python
#   diarization        pyannote.audio + torch + torchaudio
#   translation        argostranslate
#   tts                piper-tts
#   audio-separation   demucs + torch + torchaudio
#   bg-removal         rembg + opencv-python + pillow
#   all                tudo

set -euo pipefail

FEATURE="${1:-}"
UPGRADE=0
[[ "${2:-}" == "--upgrade" ]] && UPGRADE=1

case "$FEATURE" in
    core)
        PKGS="openai-whisper mediapipe opencv-python"
        SIZE="~300MB"
        ;;
    diarization)
        PKGS="pyannote.audio torch torchaudio"
        SIZE="~500MB"
        ;;
    translation)
        PKGS="argostranslate"
        SIZE="~150MB + ~100MB por par de linguas"
        ;;
    tts)
        PKGS="piper-tts"
        SIZE="~50MB"
        ;;
    audio-separation)
        PKGS="demucs torch torchaudio"
        SIZE="~2GB (torch + demucs models)"
        ;;
    bg-removal)
        PKGS="rembg opencv-python pillow"
        SIZE="~250MB (modelo U2Net ~170MB sob demanda)"
        ;;
    all)
        # union de todos sem duplicados, atraves de tr+sort
        PKGS="$(echo openai-whisper mediapipe opencv-python pyannote.audio torch torchaudio argostranslate piper-tts demucs rembg pillow | tr ' ' '\n' | sort -u | tr '\n' ' ')"
        SIZE="~5GB"
        ;;
    "")
        echo "ERRO: passa o nome do feature." >&2
        echo "Disponiveis: core, diarization, translation, tts, audio-separation, bg-removal, all" >&2
        exit 2
        ;;
    *)
        echo "ERRO: feature desconhecida: '$FEATURE'" >&2
        echo "Disponiveis: core, diarization, translation, tts, audio-separation, bg-removal, all" >&2
        exit 2
        ;;
esac

# Check python3
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERRO: python3 nao encontrado no PATH. Corre bootstrap.sh primeiro." >&2
    exit 1
fi

echo ""
echo "=== install-feature: $FEATURE ==="
echo "Pacotes: $PKGS"
echo "Download estimado: $SIZE"
echo ""

PIP_ARGS=("-m" "pip" "install" "--user")
[[ "$UPGRADE" -eq 1 ]] && PIP_ARGS+=("--upgrade")

# shellcheck disable=SC2086
python3 "${PIP_ARGS[@]}" $PKGS

echo ""
echo "OK feature '$FEATURE' instalada"

# Notas especiais
if [[ "$FEATURE" == "diarization" || "$FEATURE" == "all" ]]; then
    echo ""
    echo "NOTA diarization: precisa de HF_TOKEN da huggingface.co"
    echo "  1. Cria token gratuito em https://huggingface.co/settings/tokens"
    echo "  2. Aceita termos em https://huggingface.co/pyannote/speaker-diarization-3.1"
    echo "  3. export HF_TOKEN='hf_xxx...'"
fi
if [[ "$FEATURE" == "translation" || "$FEATURE" == "all" ]]; then
    echo ""
    echo "NOTA translation: pacotes de linguas descarregados sob demanda na 1a corrida (~100MB cada par)."
fi
if [[ "$FEATURE" == "tts" || "$FEATURE" == "all" ]]; then
    echo ""
    echo "NOTA tts: voice models descarregados sob demanda (~50-100MB cada voz)."
fi
