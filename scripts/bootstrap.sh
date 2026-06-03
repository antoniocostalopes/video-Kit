#!/usr/bin/env bash
# bootstrap.sh — Bootstrap automatico do videokit em macOS / Linux.
#
# Deteta FFmpeg + Python 3.12+. Instala via brew (macOS) ou apt (Debian/Ubuntu).
# Em seguida instala pacotes Python core: openai-whisper, mediapipe, opencv-python.
#
# Para features adicionais, usa install-feature.sh.
#
# Uso:
#   ./bootstrap.sh              # interativo
#   ./bootstrap.sh --auto-yes   # nao perguntar
#   ./bootstrap.sh --check-only # so reportar

set -euo pipefail

AUTO_YES=0
CHECK_ONLY=0
SKIP_FFMPEG=0
SKIP_PYTHON=0
SKIP_PIP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto-yes)    AUTO_YES=1; shift ;;
        --check-only)  CHECK_ONLY=1; shift ;;
        --skip-ffmpeg) SKIP_FFMPEG=1; shift ;;
        --skip-python) SKIP_PYTHON=1; shift ;;
        --skip-pip)    SKIP_PIP=1; shift ;;
        *) echo "Arg desconhecido: $1" >&2; shift ;;
    esac
done

# --- Detect OS ---

OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS_NAME" in
    darwin*) PLATFORM="macos" ;;
    linux*)  PLATFORM="linux" ;;
    *) echo "ERRO: OS '$OS_NAME' nao suportado." >&2; exit 1 ;;
esac

# --- Helpers ---

has_cmd() { command -v "$1" >/dev/null 2>&1; }

has_python312() {
    if has_cmd python3; then
        ver="$(python3 -c "import sys; print(sys.version_info[0]*100+sys.version_info[1])" 2>/dev/null || echo 0)"
        [[ "$ver" -ge 312 ]]
    else
        return 1
    fi
}

confirm() {
    local q="$1"
    [[ "$AUTO_YES" -eq 1 ]] && return 0
    read -r -p "$q [Y/n] " r
    [[ -z "$r" || "$r" == "y" || "$r" == "Y" || "$r" == "sim" || "$r" == "s" ]]
}

# --- Header ---

echo ""
echo "=== videokit bootstrap ($PLATFORM) ==="
echo ""

# --- Status check ---

HAS_FFMPEG=0; has_cmd ffmpeg && HAS_FFMPEG=1
HAS_PYTHON=0; has_python312 && HAS_PYTHON=1

echo "Estado atual:"
echo "  ffmpeg:        $(test "$HAS_FFMPEG" = 1 && echo OK || echo 'EM FALTA')"
echo "  Python 3.12+:  $(test "$HAS_PYTHON" = 1 && echo OK || echo 'EM FALTA')"

if [[ "$PLATFORM" = "macos" ]]; then
    HAS_BREW=0; has_cmd brew && HAS_BREW=1
    echo "  Homebrew:      $(test "$HAS_BREW" = 1 && echo OK || echo 'EM FALTA')"
fi
echo ""

# --- Check-only mode ---

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    if [[ "$HAS_FFMPEG" = 1 && "$HAS_PYTHON" = 1 ]]; then
        echo "Tudo OK."
        exit 0
    else
        echo "Algo em falta. Corre sem --check-only para instalar."
        exit 1
    fi
fi

# --- macOS path ---

if [[ "$PLATFORM" = "macos" ]]; then
    if [[ "$HAS_FFMPEG" = 0 || "$HAS_PYTHON" = 0 ]]; then
        if [[ "$HAS_BREW" = 0 ]]; then
            echo "ERRO: Homebrew necessario mas nao instalado." >&2
            echo "" >&2
            echo "Instala primeiro:" >&2
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" >&2
            echo "" >&2
            echo "Depois corre este script de novo." >&2
            exit 1
        fi
    fi

    if [[ "$HAS_FFMPEG" = 0 && "$SKIP_FFMPEG" = 0 ]]; then
        if confirm "Instalar FFmpeg via brew?"; then
            echo "  A instalar FFmpeg..."
            brew install ffmpeg
            has_cmd ffmpeg && echo "  OK FFmpeg instalado" || echo "  AVISO: FFmpeg instalado mas nao detetado"
        else
            echo "  Skip FFmpeg."
        fi
    fi

    if [[ "$HAS_PYTHON" = 0 && "$SKIP_PYTHON" = 0 ]]; then
        if confirm "Instalar Python 3.12+ via brew?"; then
            echo "  A instalar Python 3.12..."
            brew install python@3.12
            has_python312 && echo "  OK Python instalado" || { echo "AVISO: Python instalado mas nao detetado" >&2; exit 1; }
        else
            echo "  Skip Python."
        fi
    fi
fi

# --- Linux path (Debian/Ubuntu) ---

if [[ "$PLATFORM" = "linux" ]]; then
    if [[ "$HAS_FFMPEG" = 0 || "$HAS_PYTHON" = 0 ]]; then
        if ! has_cmd apt; then
            echo "ERRO: apt nao disponivel (Debian/Ubuntu apenas neste bootstrap)." >&2
            echo "" >&2
            echo "Para outras distros, instala manualmente:" >&2
            echo "  Fedora:    sudo dnf install ffmpeg python3 python3-pip" >&2
            echo "  Arch:      sudo pacman -S ffmpeg python python-pip" >&2
            echo "  openSUSE:  sudo zypper install ffmpeg-7 python312 python312-pip" >&2
            exit 1
        fi

        if [[ "$AUTO_YES" -eq 0 ]]; then
            echo ""
            echo "Vou correr 'sudo apt install' (pede password admin)."
            confirm "Continuar?" || { echo "Skip"; exit 1; }
        fi

        sudo apt-get update -qq

        if [[ "$HAS_FFMPEG" = 0 && "$SKIP_FFMPEG" = 0 ]]; then
            echo "  A instalar FFmpeg..."
            sudo apt-get install -y ffmpeg
        fi

        if [[ "$HAS_PYTHON" = 0 && "$SKIP_PYTHON" = 0 ]]; then
            echo "  A instalar Python 3 + pip..."
            sudo apt-get install -y python3 python3-pip
            # Em Ubuntu/Debian, python3 nao tem 3.12 por defeito em LTS antigas
            ver="$(python3 -c "import sys; print(sys.version_info[0]*100+sys.version_info[1])" 2>/dev/null || echo 0)"
            if [[ "$ver" -lt 312 ]]; then
                echo "AVISO: python3 instalado mas versao < 3.12 ($ver)." >&2
                echo "Para 3.12+ instala via deadsnakes PPA:" >&2
                echo "  sudo add-apt-repository ppa:deadsnakes/ppa" >&2
                echo "  sudo apt install python3.12 python3.12-venv" >&2
            fi
        fi
    fi
fi

# --- pip core packages ---

if [[ "$SKIP_PIP" = 0 ]]; then
    if has_cmd python3; then
        echo ""
        echo "A instalar pacotes Python core (whisper, mediapipe, opencv)..."
        echo "(download ~300MB-1GB, demora alguns minutos)"

        python3 -m pip install --user --upgrade pip
        python3 -m pip install --user --upgrade openai-whisper mediapipe opencv-python

        echo "  OK pacotes core instalados"
    else
        echo "Python3 nao disponivel. Skip pip install." >&2
        exit 1
    fi
fi

# --- Sumario ---

echo ""
echo "=== bootstrap concluido ==="
echo ""
echo "Para features adicionais, usa install-feature.sh:"
echo "  ./install-feature.sh diarization        # pyannote-audio + torch"
echo "  ./install-feature.sh translation        # argostranslate"
echo "  ./install-feature.sh tts                # piper-tts"
echo "  ./install-feature.sh audio-separation   # demucs + torch"
echo "  ./install-feature.sh bg-removal         # rembg"
echo "  ./install-feature.sh all                # tudo (~5GB download)"
echo ""
echo "Agora corre detect-env.sh para verificar e popular cache/env-report.json:"
echo "  ./detect-env.sh"
