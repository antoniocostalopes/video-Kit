#!/usr/bin/env bash
# quick-preview.sh — Render rapido de um segmento para confirmar efeito antes do final.
#
# Uso:
#   ./quick-preview.sh --project-dir <abs> [--start 0] [--duration 5] [--label preview]
#                      [--with-subs] [--with-lut <file.cube>] [--lut-intensity 1.0]
#                      [--with-zoom] [--from-zoom 1.0] [--to-zoom 1.25]
#                      [--scale 720]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

PROJECT_DIR=""
START="0"
DURATION="5"
LABEL="preview"
WITH_SUBS=0
WITH_LUT=""
LUT_INTENSITY="1.0"
WITH_ZOOM=0
FROM_ZOOM="1.0"
TO_ZOOM="1.25"
SCALE="720"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
        --start)         START="$2"; shift 2 ;;
        --duration)      DURATION="$2"; shift 2 ;;
        --label)         LABEL="$2"; shift 2 ;;
        --with-subs)     WITH_SUBS=1; shift ;;
        --with-lut)      WITH_LUT="$2"; shift 2 ;;
        --lut-intensity) LUT_INTENSITY="$2"; shift 2 ;;
        --with-zoom)     WITH_ZOOM=1; shift ;;
        --from-zoom)     FROM_ZOOM="$2"; shift 2 ;;
        --to-zoom)       TO_ZOOM="$2"; shift 2 ;;
        --scale)         SCALE="$2"; shift 2 ;;
        *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$PROJECT_DIR" || ! -d "$PROJECT_DIR" ]] && { echo "ERRO: --project-dir invalido" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

ENV_REPORT="$SKILL_DIR/cache/env-report.json"
require_env_report "$ENV_REPORT"
FFMPEG_BIN="$(read_json "$ENV_REPORT" ffmpeg_bin)"
[[ -z "$FFMPEG_BIN" || ! -x "$FFMPEG_BIN" ]] && { echo "ERRO: ffmpeg_bin invalido" >&2; exit 1; }

PROJECT_JSON="$PROJECT_DIR/project.json"
DISPLAY_W="$(read_json "$PROJECT_JSON" media.display_width)"
DISPLAY_H="$(read_json "$PROJECT_JSON" media.display_height)"
FPS="$(read_json "$PROJECT_JSON" media.fps)"
SOURCE_REL="$(read_json "$PROJECT_JSON" source.local_copy)"

# --- Escolher input ---
INPUT=""
for cand in "$PROJECT_DIR/renders/edited_subs.mp4" "$PROJECT_DIR/renders/edited.mp4" "$PROJECT_DIR/$SOURCE_REL"; do
    if [[ -f "$cand" ]]; then
        INPUT="$cand"; break
    fi
done
[[ -z "$INPUT" ]] && { echo "ERRO: nenhum input encontrado em $PROJECT_DIR" >&2; exit 1; }
echo "Input: $INPUT"

# --- Output ---
PREVIEW_DIR="$PROJECT_DIR/cache/preview"
mkdir -p "$PREVIEW_DIR"
TS="$(date +%H%M%S)"
SAFE_LABEL="$(echo "$LABEL" | tr -c 'a-zA-Z0-9_-' '_')"
OUTPUT="$PREVIEW_DIR/${TS}_${SAFE_LABEL}.mp4"

# --- Filtros ---
FILTERS=()
LUT_TEMP=""

if [[ "$WITH_ZOOM" -eq 1 ]]; then
    RATE="$(awk -v fz="$FROM_ZOOM" -v tz="$TO_ZOOM" -v d="$DURATION" 'BEGIN { d2=d; if (d2<0.5) d2=0.5; printf "%.6f", (tz-fz)/d2 }')"
    EXPR="if(between(in_time,0,${DURATION}),min(${FROM_ZOOM}+${RATE}*in_time,${TO_ZOOM}),1)"
    FILTERS+=("zoompan=z='${EXPR}':d=1:s=${DISPLAY_W}x${DISPLAY_H}:fps=${FPS}")
fi

if [[ -n "$WITH_LUT" ]]; then
    [[ ! -f "$WITH_LUT" ]] && { echo "ERRO: LUT nao existe: $WITH_LUT" >&2; exit 1; }
    LUT_BASENAME="$(basename "$WITH_LUT")"
    LUT_TEMP="$PREVIEW_DIR/__lut_${LUT_BASENAME}"
    cp "$WITH_LUT" "$LUT_TEMP"
    if awk -v i="$LUT_INTENSITY" 'BEGIN { exit !(i >= 0.99) }'; then
        FILTERS+=("lut3d=__lut_${LUT_BASENAME}")
    else
        FILTERS+=("split[a][b];[b]lut3d=__lut_${LUT_BASENAME}[g];[a][g]blend=all_mode=normal:all_opacity=${LUT_INTENSITY}")
    fi
fi

if [[ "$WITH_SUBS" -eq 1 ]]; then
    ASS_PATH="$PROJECT_DIR/edit/subtitles.ass"
    [[ ! -f "$ASS_PATH" ]] && { echo "ERRO: --with-subs pedido mas edit/subtitles.ass nao existe" >&2; exit 1; }
    SUBS_FOR_FILTER="$(realpath "$ASS_PATH" 2>/dev/null || readlink -f "$ASS_PATH" || echo "$ASS_PATH")"
    FILTERS+=("subtitles='${SUBS_FOR_FILTER}'")
fi

if [[ "$SCALE" -gt 0 ]]; then
    FILTERS+=("scale=-2:${SCALE}")
fi

# --- ffmpeg ---
echo "Preview: ${DURATION}s a partir de ${START}s"
[[ "${#FILTERS[@]}" -gt 0 ]] && echo "  Filtros: $(IFS='|'; echo "${FILTERS[*]}")"

WORK_DIR="$(pwd)"
if [[ -n "$LUT_TEMP" ]]; then WORK_DIR="$PREVIEW_DIR"; fi

cleanup() {
    [[ -n "$LUT_TEMP" && -f "$LUT_TEMP" ]] && rm -f "$LUT_TEMP"
}
trap cleanup EXIT

FF_ARGS=("-y" "-ss" "$START" "-i" "$INPUT" "-t" "$DURATION")
if [[ "${#FILTERS[@]}" -gt 0 ]]; then
    VF="$(IFS=,; echo "${FILTERS[*]}")"
    FF_ARGS+=("-vf" "$VF")
fi
FF_ARGS+=(
    "-c:v" "libx264" "-preset" "ultrafast" "-crf" "26"
    "-pix_fmt" "yuv420p"
    "-c:a" "aac" "-b:a" "128k"
    "$OUTPUT"
)

(
    cd "$WORK_DIR"
    "$FFMPEG_BIN" "${FF_ARGS[@]}"
)

SIZE_MB="$(du -m "$OUTPUT" | cut -f1)"
echo "OK preview: $OUTPUT (${SIZE_MB} MB)"
echo "Abre em qualquer player para confirmar antes de re-render."
