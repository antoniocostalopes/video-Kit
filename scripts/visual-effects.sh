#!/usr/bin/env bash
# visual-effects.sh — Transicoes xfade, LUTs, color grading.
#
# Uso:
#   ./visual-effects.sh --mode transition --input-a <v> --input-b <v> --output <v> [--transition fade] [--duration 0.5]
#   ./visual-effects.sh --mode lut --input <v> --output <v> --lut-file <file.cube> [--lut-intensity 1.0]
#   ./visual-effects.sh --mode grade --input <v> --output <v> [--brightness 0] [--contrast 1.0] [--saturation 1.0] [--vignette-strength 0] [--film-grain 0]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

MODE=""
INPUT=""
INPUT_A=""
INPUT_B=""
OUTPUT=""
TRANSITION="fade"
DURATION="0.5"
OFFSET=""
LUT_FILE=""
LUT_INTENSITY="1.0"
VIGNETTE="0"
FILM_GRAIN="0"
BRIGHTNESS="0"
CONTRAST="1.0"
SATURATION="1.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)             MODE="$2"; shift 2 ;;
        --input)            INPUT="$2"; shift 2 ;;
        --input-a)          INPUT_A="$2"; shift 2 ;;
        --input-b)          INPUT_B="$2"; shift 2 ;;
        --output)           OUTPUT="$2"; shift 2 ;;
        --transition)       TRANSITION="$2"; shift 2 ;;
        --duration)         DURATION="$2"; shift 2 ;;
        --offset)           OFFSET="$2"; shift 2 ;;
        --lut-file)         LUT_FILE="$2"; shift 2 ;;
        --lut-intensity)    LUT_INTENSITY="$2"; shift 2 ;;
        --vignette-strength) VIGNETTE="$2"; shift 2 ;;
        --film-grain)       FILM_GRAIN="$2"; shift 2 ;;
        --brightness)       BRIGHTNESS="$2"; shift 2 ;;
        --contrast)         CONTRAST="$2"; shift 2 ;;
        --saturation)       SATURATION="$2"; shift 2 ;;
        *)                  echo "Argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$MODE"   ]] && { echo "ERRO: --mode obrigatorio" >&2; exit 2; }
[[ -z "$OUTPUT" ]] && { echo "ERRO: --output obrigatorio" >&2; exit 2; }

# Env
ENV_REPORT="$SKILL_DIR/cache/env-report.json"
[[ ! -f "$ENV_REPORT" ]] && "$SCRIPT_DIR/detect-env.sh"
FFMPEG_BIN="$(grep -oE '"ffmpeg_bin": "[^"]*"' "$ENV_REPORT" | sed 's/"ffmpeg_bin": "//;s/"$//')"
FFPROBE_BIN="$(grep -oE '"ffprobe_bin": "[^"]*"' "$ENV_REPORT" | sed 's/"ffprobe_bin": "//;s/"$//')"

# Helpers
get_duration() {
    local p="$1"
    "$FFPROBE_BIN" -v error -show_entries format=duration -of default=nw=1:nk=1 "$p"
}

mkdir -p "$(dirname "$OUTPUT")"

# ========================================
# MODE: transition
# ========================================
if [[ "$MODE" == "transition" ]]; then
    [[ -z "$INPUT_A" || ! -f "$INPUT_A" ]] && { echo "ERRO: --input-a invalido" >&2; exit 1; }
    [[ -z "$INPUT_B" || ! -f "$INPUT_B" ]] && { echo "ERRO: --input-b invalido" >&2; exit 1; }

    DUR_A="$(get_duration "$INPUT_A")"
    if [[ -z "$OFFSET" ]]; then
        OFFSET="$(awk -v d="$DUR_A" -v t="$DURATION" 'BEGIN { v=d-t; if (v<0) v=0; printf "%.3f", v }')"
    fi

    echo "Transition: $TRANSITION ($DURATION s, offset $OFFSET)"

    FILTER_COMPLEX="[0:v][1:v]xfade=transition=${TRANSITION}:duration=${DURATION}:offset=${OFFSET}[v];[0:a][1:a]acrossfade=d=${DURATION}[a]"

    "$FFMPEG_BIN" -y \
        -i "$INPUT_A" \
        -i "$INPUT_B" \
        -filter_complex "$FILTER_COMPLEX" \
        -map "[v]" -map "[a]" \
        -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
        -c:a aac -b:a 192k \
        "$OUTPUT"

    echo "OK $OUTPUT"
    exit 0
fi

# ========================================
# MODE: lut
# ========================================
if [[ "$MODE" == "lut" ]]; then
    [[ -z "$INPUT"    || ! -f "$INPUT"    ]] && { echo "ERRO: --input invalido" >&2; exit 1; }
    [[ -z "$LUT_FILE" || ! -f "$LUT_FILE" ]] && { echo "ERRO: --lut-file invalido" >&2; exit 1; }

    # Em Unix nao ha problema com paths. Mas mantemos o workaround do .ps1
    # (copiar LUT para a pasta de output e usar so o nome) para consistencia.
    OUT_DIR="$(dirname "$OUTPUT")"
    TMP_LUT_NAME="__skv_lut_$(date +%s)_$$.cube"
    TMP_LUT_PATH="$OUT_DIR/$TMP_LUT_NAME"
    cp "$LUT_FILE" "$TMP_LUT_PATH"

    if awk -v i="$LUT_INTENSITY" 'BEGIN { exit !(i >= 0.99) }'; then
        VIDEO_FILTER="lut3d=${TMP_LUT_NAME}"
    else
        VIDEO_FILTER="split[a][b];[b]lut3d=${TMP_LUT_NAME}[graded];[a][graded]blend=all_mode=normal:all_opacity=${LUT_INTENSITY}"
    fi

    echo "LUT: $(basename "$LUT_FILE") (intensity $LUT_INTENSITY)"

    (
        cd "$OUT_DIR"
        "$FFMPEG_BIN" -y \
            -i "$INPUT" \
            -vf "$VIDEO_FILTER" \
            -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
            -c:a copy \
            "$OUTPUT"
    )

    rm -f "$TMP_LUT_PATH"
    echo "OK $OUTPUT"
    exit 0
fi

# ========================================
# MODE: grade
# ========================================
if [[ "$MODE" == "grade" ]]; then
    [[ -z "$INPUT" || ! -f "$INPUT" ]] && { echo "ERRO: --input invalido" >&2; exit 1; }

    FILTERS=()
    if ! awk -v b="$BRIGHTNESS" -v c="$CONTRAST" -v s="$SATURATION" 'BEGIN { exit !(b == 0 && c == 1.0 && s == 1.0) }'; then
        FILTERS+=("eq=brightness=${BRIGHTNESS}:contrast=${CONTRAST}:saturation=${SATURATION}")
    fi
    if awk -v v="$VIGNETTE" 'BEGIN { exit !(v > 0) }'; then
        FILTERS+=("vignette=angle=PI/3-${VIGNETTE}*(PI/6)")
    fi
    if (( FILM_GRAIN > 0 )) 2>/dev/null; then
        FILTERS+=("noise=alls=${FILM_GRAIN}:allf=t")
    fi

    if [[ "${#FILTERS[@]}" -eq 0 ]]; then
        echo "AVISO: Sem efeitos. Copy do input para o output."
        cp "$INPUT" "$OUTPUT"
        exit 0
    fi

    VF_STR="$(IFS=,; echo "${FILTERS[*]}")"
    echo "Grade: $VF_STR"

    "$FFMPEG_BIN" -y \
        -i "$INPUT" \
        -vf "$VF_STR" \
        -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
        -c:a copy \
        "$OUTPUT"

    echo "OK $OUTPUT"
    exit 0
fi

echo "ERRO: --mode invalido '$MODE' (use transition|lut|grade)" >&2
exit 2
