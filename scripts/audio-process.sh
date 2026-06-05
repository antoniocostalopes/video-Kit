#!/usr/bin/env bash
# audio-process.sh — Processamento de audio profissional via FFmpeg.
#
# Uso:
#   ./audio-process.sh --input <file> --output <file>
#                      [--denoise] [--normalize] [--target-lufs -14]
#                      [--compress] [--deess]
#                      [--music <file>] [--music-volume 0.25]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

INPUT=""
OUTPUT=""
DENOISE=0
NORMALIZE=0
TARGET_LUFS="-14.0"
COMPRESS=0
DEESS=0
MUSIC=""
MUSIC_VOLUME="0.25"
PLATFORM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)        INPUT="$2"; shift 2 ;;
        --output)       OUTPUT="$2"; shift 2 ;;
        --denoise)      DENOISE=1; shift ;;
        --normalize)    NORMALIZE=1; shift ;;
        --target-lufs)  TARGET_LUFS="$2"; shift 2 ;;
        --compress)     COMPRESS=1; shift ;;
        --deess)        DEESS=1; shift ;;
        --music)        MUSIC="$2"; shift 2 ;;
        --music-volume) MUSIC_VOLUME="$2"; shift 2 ;;
        --preset)       PLATFORM="$2"; shift 2 ;;
        *)              echo "Argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done

# --- Aplica preset de plataforma se pedido (sobrescreve --target-lufs) ---
if [[ -n "$PLATFORM" ]]; then
    PRESETS_FILE="$SKILL_DIR/assets/platform-presets.json"
    if [[ -f "$PRESETS_FILE" ]]; then
        PRESET_LUFS="$(read_json "$PRESETS_FILE" "$PLATFORM.audio.target_lufs")"
        if [[ -n "$PRESET_LUFS" ]]; then
            TARGET_LUFS="$PRESET_LUFS"
            echo "Preset '$PLATFORM' aplicado: target_lufs=$TARGET_LUFS"
        else
            echo "AVISO: preset '$PLATFORM' nao encontrado em $PRESETS_FILE. A usar --target-lufs=$TARGET_LUFS." >&2
        fi
    else
        echo "AVISO: $PRESETS_FILE nao existe. A usar --target-lufs=$TARGET_LUFS." >&2
    fi
fi

[[ -z "$INPUT"  ]] && { echo "ERRO: --input obrigatorio" >&2; exit 2; }
[[ -z "$OUTPUT" ]] && { echo "ERRO: --output obrigatorio" >&2; exit 2; }
[[ ! -f "$INPUT" ]] && { echo "ERRO: Input nao existe" >&2; exit 1; }
[[ -n "$MUSIC" && ! -f "$MUSIC" ]] && { echo "ERRO: Music nao existe" >&2; exit 1; }

# --- Env ---
ENV_REPORT="$SKILL_DIR/cache/env-report.json"
require_env_report "$ENV_REPORT"
FFMPEG_BIN="$(read_json "$ENV_REPORT" ffmpeg_bin)"
[[ -z "$FFMPEG_BIN" || ! -x "$FFMPEG_BIN" ]] && { echo "ERRO: ffmpeg_bin invalido em env-report.json" >&2; exit 1; }

# --- Modelo RNNoise se denoise ---
MODEL_FOR_FILTER=""
if [[ "$DENOISE" -eq 1 ]]; then
    MODEL_PATH="$SKILL_DIR/assets/audio-models/cb.rnnn"
    if [[ ! -f "$MODEL_PATH" ]]; then
        echo "Modelo RNNoise nao encontrado. A descarregar..."
        "$SCRIPT_DIR/download-assets.sh" --what rnnoise
    fi
    [[ ! -f "$MODEL_PATH" ]] && { echo "ERRO: Modelo RNNoise indisponivel" >&2; exit 1; }
    MODEL_FOR_FILTER="$MODEL_PATH"
fi

# --- Filtros de audio ---
AUDIO_FILTERS=()
[[ "$DENOISE"   -eq 1 ]] && AUDIO_FILTERS+=("arnndn=m=${MODEL_FOR_FILTER}")
[[ "$DEESS"     -eq 1 ]] && AUDIO_FILTERS+=("equalizer=f=7000:t=q:w=1.5:g=-3")
[[ "$COMPRESS"  -eq 1 ]] && AUDIO_FILTERS+=("acompressor=threshold=-18dB:ratio=2.5:attack=8:release=180:makeup=2")
[[ "$NORMALIZE" -eq 1 ]] && AUDIO_FILTERS+=("loudnorm=I=${TARGET_LUFS}:TP=-1.5:LRA=11")

# --- Caso 1: sem musica ---
if [[ -z "$MUSIC" ]]; then
    echo "Audio processing (sem musica)..."
    if [[ "${#AUDIO_FILTERS[@]}" -gt 0 ]]; then
        echo "  Filtros: $(IFS=,; echo "${AUDIO_FILTERS[*]}")"
        AF_STR="$(IFS=,; echo "${AUDIO_FILTERS[*]}")"
        "$FFMPEG_BIN" -y -i "$INPUT" -c:v copy -af "$AF_STR" -c:a aac -b:a 192k "$OUTPUT"
    else
        echo "  Filtros: nenhum"
        "$FFMPEG_BIN" -y -i "$INPUT" -c:v copy -c:a aac -b:a 192k "$OUTPUT"
    fi

    SIZE_MB="$(du -m "$OUTPUT" | cut -f1)"
    echo "OK Output: $OUTPUT (${SIZE_MB} MB)"
    exit 0
fi

# --- Caso 2: com musica + ducking ---
echo "Audio processing com musica + ducking..."

if [[ "${#AUDIO_FILTERS[@]}" -gt 0 ]]; then
    VOICE_PREFIX="$(IFS=,; echo "${AUDIO_FILTERS[*]}"),"
else
    VOICE_PREFIX=""
fi

FILTER_COMPLEX="[0:a]${VOICE_PREFIX}asplit=2[vmix][vsc];[1:a]volume=${MUSIC_VOLUME}[mbase];[mbase][vsc]sidechaincompress=threshold=0.05:ratio=20:attack=5:release=300:level_sc=0.8[mduck];[vmix][mduck]amix=inputs=2:duration=first:dropout_transition=3[outa]"

"$FFMPEG_BIN" -y \
    -i "$INPUT" \
    -i "$MUSIC" \
    -filter_complex "$FILTER_COMPLEX" \
    -map "0:v?" \
    -map "[outa]" \
    -c:v copy \
    -c:a aac -b:a 192k \
    -shortest \
    "$OUTPUT"

SIZE_MB="$(du -m "$OUTPUT" | cut -f1)"
echo "OK Output: $OUTPUT (${SIZE_MB} MB)"
