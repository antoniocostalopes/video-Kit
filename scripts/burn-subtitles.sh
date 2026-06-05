#!/usr/bin/env bash
# burn-subtitles.sh — Queima legendas ASS num video via FFmpeg.
#
# Uso:
#   ./burn-subtitles.sh --input <video> --subtitles <file.ass> --output <video.mp4>
#                       [--preset draft|final]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

INPUT=""
SUBTITLES=""
OUTPUT=""
PRESET="draft"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)      INPUT="$2"; shift 2 ;;
        --subtitles)  SUBTITLES="$2"; shift 2 ;;
        --output)     OUTPUT="$2"; shift 2 ;;
        --preset)     PRESET="$2"; shift 2 ;;
        *)            echo "Argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$INPUT"     ]] && { echo "ERRO: --input obrigatorio" >&2; exit 2; }
[[ -z "$SUBTITLES" ]] && { echo "ERRO: --subtitles obrigatorio" >&2; exit 2; }
[[ -z "$OUTPUT"    ]] && { echo "ERRO: --output obrigatorio" >&2; exit 2; }

[[ ! -f "$INPUT"     ]] && { echo "ERRO: Input nao existe: $INPUT" >&2; exit 1; }
[[ ! -f "$SUBTITLES" ]] && { echo "ERRO: Subtitles nao existe: $SUBTITLES" >&2; exit 1; }

# --- Env report ---
ENV_REPORT="$SKILL_DIR/cache/env-report.json"
require_env_report "$ENV_REPORT"
FFMPEG_BIN="$(read_json "$ENV_REPORT" ffmpeg_bin)"
[[ -z "$FFMPEG_BIN" || ! -x "$FFMPEG_BIN" ]] && { echo "ERRO: ffmpeg_bin invalido em env-report.json" >&2; exit 1; }

# --- Codec args por preset ---
if [[ "$PRESET" == "final" ]]; then
    VIDEO_ARGS=(-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart)
else
    VIDEO_ARGS=(-c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p)
fi

# --- Out dir ---
mkdir -p "$(dirname "$OUTPUT")"

# --- Em Unix paths nao tem ':' problemático, mas o filtro subtitles aceita aspas simples
# para envolver paths. Bash strings passam por shell uma vez antes de ffmpeg, então:
SUBS_FOR_FILTER="$(realpath "$SUBTITLES" 2>/dev/null || readlink -f "$SUBTITLES" || echo "$SUBTITLES")"

echo "Queimando legendas ($PRESET)..."
echo "  Input:  $INPUT"
echo "  Subs:   $SUBTITLES"
echo "  Output: $OUTPUT"

"$FFMPEG_BIN" -y \
    -i "$INPUT" \
    -vf "subtitles='${SUBS_FOR_FILTER}'" \
    "${VIDEO_ARGS[@]}" \
    -c:a copy \
    "$OUTPUT"

if [[ ! -f "$OUTPUT" ]]; then
    echo "ERRO: ffmpeg correu sem erro mas output nao existe: $OUTPUT" >&2
    exit 1
fi

SIZE_MB="$(du -m "$OUTPUT" | cut -f1)"
echo "OK Output gerado: $OUTPUT (${SIZE_MB} MB)"
