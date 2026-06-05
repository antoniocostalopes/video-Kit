#!/usr/bin/env bash
# init-project.sh — Cria projects/YYYY-MM-DD_slug/ ao lado do source.
#
# Uso:
#   ./init-project.sh --input <abs-path> [--output-dir <abs-path>] [--slug <slug>]
#                     [--mode full|cut-only] [--subs full|karaoke|highlights|sem]
#
# Equivalente a init-project.ps1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

# --- Defaults ---
INPUT_VIDEO=""
OUTPUT_DIR=""
SLUG=""
MODE="full"
SUBS="completas"

# --- Args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)         INPUT_VIDEO="$2"; shift 2 ;;
        --output-dir)    OUTPUT_DIR="$2"; shift 2 ;;
        --slug)          SLUG="$2"; shift 2 ;;
        --mode)          MODE="$2"; shift 2 ;;
        --subs)          SUBS="$2"; shift 2 ;;
        *)               echo "Argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$INPUT_VIDEO" ]]; then
    echo "ERRO: --input <abs-path> obrigatorio." >&2
    exit 2
fi

if [[ ! -f "$INPUT_VIDEO" ]]; then
    echo "ERRO: video nao existe: $INPUT_VIDEO" >&2
    exit 1
fi

INPUT_VIDEO="$(cd "$(dirname "$INPUT_VIDEO")" && pwd)/$(basename "$INPUT_VIDEO")"

# --- Validation: mode + subs ---
case "$MODE" in
    full|cut-only) ;;
    *) echo "ERRO: --mode deve ser 'full' ou 'cut-only', recebido '$MODE'." >&2; exit 2 ;;
esac

case "$SUBS" in
    completas|karaoke|highlights|sem) ;;
    *) echo "ERRO: --subs deve ser completas|karaoke|highlights|sem, recebido '$SUBS'." >&2; exit 2 ;;
esac

# --- Env report ---
ENV_REPORT="$SKILL_DIR/cache/env-report.json"
require_env_report "$ENV_REPORT"

FFPROBE_BIN="$(read_json "$ENV_REPORT" ffprobe_bin)"
if [[ -z "$FFPROBE_BIN" || ! -x "$FFPROBE_BIN" ]]; then
    echo "ERRO: ffprobe_bin invalido em env-report.json: '$FFPROBE_BIN'" >&2
    exit 1
fi

# --- Validacao de input (fase 1 de validation enhancement) ---

# Extensao
EXT="${INPUT_VIDEO##*.}"
EXT_LOWER="$(echo "$EXT" | tr '[:upper:]' '[:lower:]')"
case "$EXT_LOWER" in
    mp4|mov|mkv|webm|avi|m4v|mts|m2ts) ;;
    *) echo "ERRO: extensao '$EXT' nao suportada. Use mp4/mov/mkv/webm/avi/m4v/mts." >&2; exit 1 ;;
esac

# Audio stream + duration (parsing robusto via Python)
PROBE_JSON="$("$FFPROBE_BIN" -v error \
    -show_entries stream=codec_type:format=duration \
    -of json "$INPUT_VIDEO" 2>&1 || true)"

eval "$(echo "$PROBE_JSON" | python3 - <<'PYEOF'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("HAS_AUDIO=0"); print("DURATION="); sys.exit(0)
has_audio = 1 if any(s.get("codec_type") == "audio" for s in d.get("streams", [])) else 0
dur = (d.get("format", {}) or {}).get("duration", "")
print(f"HAS_AUDIO={has_audio}")
print(f"DURATION='{dur}'")
PYEOF
)"

if [[ "${HAS_AUDIO:-0}" -eq 0 ]]; then
    echo "AVISO: video nao tem stream de audio. Transcricao impossivel."
fi

if [[ -n "${DURATION:-}" ]]; then
    DURATION_INT="${DURATION%.*}"
    if (( DURATION_INT < 1 )); then
        echo "ERRO: duracao $DURATION s muito curta (min 1s)." >&2
        exit 1
    fi
    if (( DURATION_INT > 7200 )); then
        echo "AVISO: duracao $DURATION s > 2h. Pipeline pode demorar bastante."
    fi
fi

# Disco livre (estimativa: 3GB ou 6x tamanho do source)
SOURCE_SIZE_MB="$(du -m "$INPUT_VIDEO" | cut -f1)"
REQUIRED_MB=$(( SOURCE_SIZE_MB * 6 ))
[[ "$REQUIRED_MB" -lt 3000 ]] && REQUIRED_MB=3000

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_PARENT="$(dirname "$INPUT_VIDEO")"
else
    OUTPUT_PARENT="$OUTPUT_DIR"
fi

# df -m gives MB on most platforms (macOS uses BSD df, similar enough)
AVAIL_MB="$(df -m "$OUTPUT_PARENT" 2>/dev/null | awk 'NR==2 {print $4}')" || AVAIL_MB="999999"
if [[ "$AVAIL_MB" -lt "$REQUIRED_MB" ]]; then
    echo "ERRO: espaco em disco insuficiente. Necessario ~${REQUIRED_MB}MB, disponivel ${AVAIL_MB}MB em $OUTPUT_PARENT" >&2
    exit 1
fi

# --- Slug ---
to_slug() {
    local txt="$1"
    # Lowercase
    txt="$(echo "$txt" | tr '[:upper:]' '[:lower:]')"
    # Replace accents (POSIX-portable)
    txt="$(echo "$txt" | sed 'y/áàâãä/aaaaa/' | sed 'y/éèêë/eeee/' | sed 'y/íìîï/iiii/' | sed 'y/óòôõö/ooooo/' | sed 'y/úùûü/uuuu/' | tr -d 'ç' | tr -d 'ñ')"
    # Replace non-alphanumeric with hyphen
    txt="$(echo "$txt" | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    # Truncate to 50 chars
    txt="${txt:0:50}"
    txt="${txt%-}"
    [[ -z "$txt" ]] && txt="video"
    echo "$txt"
}

if [[ -z "$SLUG" ]]; then
    STEM="$(basename "$INPUT_VIDEO")"
    STEM="${STEM%.*}"
    SLUG="$(to_slug "$STEM")"
fi

# --- Output dir ---
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$(dirname "$INPUT_VIDEO")/videokit-projects"
fi
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

TODAY="$(date +%Y-%m-%d)"
PROJECT_NAME="${TODAY}_${SLUG}"
PROJECT_DIR="$OUTPUT_DIR/$PROJECT_NAME"

if [[ -d "$PROJECT_DIR" ]]; then
    echo "AVISO: pasta ja existe: $PROJECT_DIR"
    SUFFIX=2
    while [[ -d "${PROJECT_DIR}-${SUFFIX}" ]]; do
        SUFFIX=$((SUFFIX + 1))
    done
    PROJECT_DIR="${PROJECT_DIR}-${SUFFIX}"
    PROJECT_NAME="${PROJECT_NAME}-${SUFFIX}"
    echo "Usando: $PROJECT_DIR"
fi

# --- Estrutura ---
for sub in source transcripts edit edit/segments overlays renders renders/draft renders/final verify cache logs; do
    mkdir -p "$PROJECT_DIR/$sub"
done

# --- Copia source ---
SOURCE_FILENAME="$(basename "$INPUT_VIDEO")"
SOURCE_DEST="$PROJECT_DIR/source/$SOURCE_FILENAME"
cp "$INPUT_VIDEO" "$SOURCE_DEST"
echo "Source copiado para $SOURCE_DEST"

# --- Media info ---
echo "Analisando media com ffprobe..."

MEDIA_JSON="$("$FFPROBE_BIN" -v error \
    -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate,codec_name:format=duration:stream_side_data=rotation \
    -of json "$SOURCE_DEST")"

# Parsing robusto via Python (lida com side_data_list vazio, paths Windows, etc.)
eval "$(echo "$MEDIA_JSON" | python3 - <<'PYEOF'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(f"echo 'ERRO: ffprobe devolveu JSON invalido: {e}' >&2", file=sys.stderr)
    sys.exit(1)

if not d.get("streams"):
    print("echo 'ERRO: video sem stream de video' >&2; exit 1")
    sys.exit(0)

s = d["streams"][0]
fmt = d.get("format", {}) or {}

rotation = 0
for sd in s.get("side_data_list", []) or []:
    if "rotation" in sd:
        try: rotation = int(sd["rotation"])
        except (ValueError, TypeError): pass
        break

frac = s.get("r_frame_rate", "0/1")
try:
    num, den = frac.split("/")
    fps = round(int(num) / max(int(den), 1), 3)
except Exception:
    fps = 0.0

print(f"WIDTH={s.get('width', 0)}")
print(f"HEIGHT={s.get('height', 0)}")
print(f"CODEC='{s.get('codec_name', 'unknown')}'")
print(f"DURATION='{fmt.get('duration', '0')}'")
print(f"ROTATION={rotation}")
print(f"FPS={fps}")
PYEOF
)"

# Display dims (considerar rotacao)
case "$ROTATION" in
    90|-90|270|-270)
        DISPLAY_W="$HEIGHT"
        DISPLAY_H="$WIDTH"
        ;;
    *)
        DISPLAY_W="$WIDTH"
        DISPLAY_H="$HEIGHT"
        ;;
esac

# Aspect ratio name
ASPECT="$(awk -v w="$DISPLAY_W" -v h="$DISPLAY_H" 'BEGIN { printf "%.3f", w/h }')"
ASPECT_NAME="custom"
if awk -v a="$ASPECT" 'BEGIN { exit !(a > 1.728 && a < 1.828) }'; then
    ASPECT_NAME="16:9"
elif awk -v a="$ASPECT" 'BEGIN { exit !(a > 0.5125 && a < 0.6125) }'; then
    ASPECT_NAME="9:16"
elif awk -v a="$ASPECT" 'BEGIN { exit !(a > 0.95 && a < 1.05) }'; then
    ASPECT_NAME="1:1"
elif awk -v a="$ASPECT" 'BEGIN { exit !(a > 1.283 && a < 1.383) }'; then
    ASPECT_NAME="4:3"
fi

echo "  Resolucao: ${WIDTH}x${HEIGHT} (display: ${DISPLAY_W}x${DISPLAY_H})"
echo "  Rotation:  ${ROTATION} deg"
echo "  FPS:       ${FPS}"
echo "  Duracao:   ${DURATION}s"
echo "  Aspect:    ${ASPECT_NAME}"

# --- project.json ---
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$PROJECT_DIR/project.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "slug": "$SLUG",
  "created_at": "$CREATED_AT",
  "skill_dir": "$SKILL_DIR",
  "source": {
    "original_path": "$INPUT_VIDEO",
    "local_copy": "source/$SOURCE_FILENAME"
  },
  "media": {
    "width": $WIDTH,
    "height": $HEIGHT,
    "display_width": $DISPLAY_W,
    "display_height": $DISPLAY_H,
    "rotation": $ROTATION,
    "fps": $FPS,
    "duration_s": $DURATION,
    "codec": "$CODEC",
    "aspect_ratio": "$ASPECT_NAME"
  },
  "settings": {
    "mode": "$MODE",
    "subtitle_style": "$SUBS",
    "language": "pt",
    "transcript_provider": "local"
  },
  "transcript": null,
  "edit": null,
  "beats": null,
  "renders": {
    "draft": null,
    "final": null
  },
  "checklist": {
    "duration_verified": false,
    "audio_present": false,
    "silences_reviewed": false,
    "codec_verified": false,
    "resolution_correct": false,
    "subtitles_synced_or_skipped": false,
    "files_in_project_folder": true,
    "verify_frames_extracted": false
  },
  "events": [],
  "notes_path": "notes.md"
}
EOF

# notes.md
cat > "$PROJECT_DIR/notes.md" <<EOF
# Notas de $PROJECT_NAME

Criado em $(date +'%Y-%m-%d %H:%M')
Source: $INPUT_VIDEO

## Decisoes

## Excecoes ao pipeline
EOF

echo ""
echo "OK Projeto criado: $PROJECT_DIR"
echo "  project.json: $PROJECT_DIR/project.json"
echo "  modo: $MODE"
echo "  legendas: $SUBS"
echo ""
echo "{\"project_dir\":\"$PROJECT_DIR\",\"project_name\":\"$PROJECT_NAME\"}"
