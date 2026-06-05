#!/usr/bin/env bash
# detect-env.sh — Deteta ambiente e escreve cache/env-report.json na pasta da skill.
#
# Equivalente a detect-env.ps1 para macOS / Linux.
#
# Uso: ./detect-env.sh [--workspace-dir <path>]
# Default workspace-dir: pasta da skill (parent de scripts/).

set -euo pipefail

# --- Resolve skill dir (parent of scripts/) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="$SKILL_DIR"

# --- Args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace-dir)
            WORKSPACE_DIR="$2"
            shift 2
            ;;
        *)
            echo "Aviso: argumento desconhecido $1" >&2
            shift
            ;;
    esac
done

# --- Helpers ---

find_bin() {
    local cmd="$1"
    command -v "$cmd" 2>/dev/null || true
}

get_ffmpeg_version() {
    local bin="$1"
    [[ -z "$bin" ]] && return
    "$bin" -version 2>/dev/null | head -n 1 | sed -E 's/.*ffmpeg version ([^ ]+).*/\1/' || true
}

get_python_version() {
    local bin="$1"
    [[ -z "$bin" ]] && return
    "$bin" --version 2>&1 | sed -E 's/Python ([^ ]+).*/\1/' || true
}

test_whisper_installed() {
    local bin="$1"
    [[ -z "$bin" ]] && return 1
    "$bin" -c "import whisper" 2>/dev/null
}

test_libass_available() {
    local bin="$1"
    [[ -z "$bin" ]] && return 1
    "$bin" -hide_banner -filters 2>/dev/null | grep -q subtitles
}

detect_hw_encoders() {
    # Devolve string "nvenc=BOOL videotoolbox=BOOL qsv=BOOL amf=BOOL"
    local bin="$1"
    local nvenc="false" vt="false" qsv="false" amf="false"
    if [[ -n "$bin" ]]; then
        local enc
        enc="$("$bin" -hide_banner -encoders 2>/dev/null || true)"
        echo "$enc" | grep -q "h264_nvenc"        && nvenc="true"
        echo "$enc" | grep -q "h264_videotoolbox" && vt="true"
        echo "$enc" | grep -q "h264_qsv"          && qsv="true"
        echo "$enc" | grep -q "h264_amf"          && amf="true"
    fi
    echo "$nvenc $vt $qsv $amf"
}

# --- Detection ---

echo "Detetando ambiente em $WORKSPACE_DIR..."

CACHE_DIR="$WORKSPACE_DIR/cache"
mkdir -p "$CACHE_DIR"

FFMPEG_BIN="$(find_bin ffmpeg)"
FFPROBE_BIN="$(find_bin ffprobe)"
PYTHON_BIN="$(find_bin python3)"
[[ -z "$PYTHON_BIN" ]] && PYTHON_BIN="$(find_bin python)"

FFMPEG_VERSION="$(get_ffmpeg_version "$FFMPEG_BIN")"
PYTHON_VERSION="$(get_python_version "$PYTHON_BIN")"

WHISPER_INSTALLED="false"
test_whisper_installed "$PYTHON_BIN" && WHISPER_INSTALLED="true"

LIBASS_AVAILABLE="false"
test_libass_available "$FFMPEG_BIN" && LIBASS_AVAILABLE="true"

read -r HW_NVENC HW_VIDEOTOOLBOX HW_QSV HW_AMF <<<"$(detect_hw_encoders "$FFMPEG_BIN")"

# OS detection
OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS_NAME" in
    darwin*) OS="macos"; OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)" ;;
    linux*)  OS="linux"; OS_VERSION="$(uname -r)" ;;
    *)       OS="$OS_NAME"; OS_VERSION="$(uname -r)" ;;
esac

ELEVENLABS_KEY_PRESENT="false"
[[ -n "${ELEVENLABS_API_KEY:-}" ]] && ELEVENLABS_KEY_PRESENT="true"

OPENAI_KEY_PRESENT="false"
[[ -n "${OPENAI_API_KEY:-}" ]] && OPENAI_KEY_PRESENT="true"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Write env-report.json ---

cat > "$CACHE_DIR/env-report.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "os": "$OS",
  "os_version": "$OS_VERSION",
  "ffmpeg_bin": "$FFMPEG_BIN",
  "ffmpeg_version": "$FFMPEG_VERSION",
  "ffprobe_bin": "$FFPROBE_BIN",
  "libass_available": $LIBASS_AVAILABLE,
  "hw_encoders": {
    "nvenc": $HW_NVENC,
    "videotoolbox": $HW_VIDEOTOOLBOX,
    "qsv": $HW_QSV,
    "amf": $HW_AMF
  },
  "python_bin": "$PYTHON_BIN",
  "python_version": "$PYTHON_VERSION",
  "whisper_installed": $WHISPER_INSTALLED,
  "elevenlabs_key_present": $ELEVENLABS_KEY_PRESENT,
  "openai_key_present": $OPENAI_KEY_PRESENT,
  "workspace_dir": "$WORKSPACE_DIR"
}
EOF

# --- Report ---

show_or_missing() {
    [[ -z "$1" ]] && echo "(nao encontrado)" || echo "$1"
}

echo "OK Ambiente detetado:"
echo "  ffmpeg:  $(show_or_missing "$FFMPEG_BIN")"
echo "  ffprobe: $(show_or_missing "$FFPROBE_BIN")"
echo "  python:  $(show_or_missing "$PYTHON_BIN") $PYTHON_VERSION"
if [[ "$WHISPER_INSTALLED" == "true" ]]; then
    echo "  whisper: instalado"
else
    echo "  whisper: NAO instalado (pip install openai-whisper)"
fi
if [[ "$LIBASS_AVAILABLE" == "true" ]]; then
    echo "  libass:  disponivel"
else
    echo "  libass:  NAO disponivel (fallback necessario)"
fi
HW_ACTIVE=()
[[ "$HW_NVENC" == "true" ]]        && HW_ACTIVE+=("NVENC")
[[ "$HW_VIDEOTOOLBOX" == "true" ]] && HW_ACTIVE+=("VideoToolbox")
[[ "$HW_QSV" == "true" ]]          && HW_ACTIVE+=("Intel QSV")
[[ "$HW_AMF" == "true" ]]          && HW_ACTIVE+=("AMD AMF")
if [[ "${#HW_ACTIVE[@]}" -gt 0 ]]; then
    echo "  hwaccel: $(IFS=', '; echo "${HW_ACTIVE[*]}")"
else
    echo "  hwaccel: nenhum (so software)"
fi
echo ""
echo "Report: $CACHE_DIR/env-report.json"

if [[ -z "$FFMPEG_BIN" || -z "$FFPROBE_BIN" ]]; then
    echo ""
    echo "AVISO: ffmpeg/ffprobe nao encontrado. Instala antes de continuar:" >&2
    echo "  macOS:  brew install ffmpeg" >&2
    echo "  Ubuntu: sudo apt install ffmpeg" >&2
    exit 1
fi

if [[ -z "$PYTHON_BIN" ]]; then
    echo "" >&2
    echo "AVISO: Python nao encontrado. Instala antes de continuar:" >&2
    echo "  macOS:  brew install python@3.12" >&2
    echo "  Ubuntu: sudo apt install python3 python3-pip" >&2
    exit 1
fi

exit 0
