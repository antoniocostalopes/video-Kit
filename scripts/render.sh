#!/usr/bin/env bash
# render.sh — Orquestra o render de um projeto videokit.
#
# Phases: cut | subs | effects | overlays | all | verify
#
# Uso:
#   ./render.sh --project-dir <abs-path> [--phase all|cut|subs|effects|overlays|verify]
#               [--quality draft|final] [--clean-cache]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

PROJECT_DIR=""
PHASE="all"
QUALITY="draft"
CLEAN_CACHE=0
HWACCEL="none"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --phase)       PHASE="$2"; shift 2 ;;
        --quality)     QUALITY="$2"; shift 2 ;;
        --clean-cache) CLEAN_CACHE=1; shift ;;
        --hwaccel)     HWACCEL="$2"; shift 2 ;;
        *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$PROJECT_DIR" || ! -d "$PROJECT_DIR" ]] && { echo "ERRO: --project-dir invalido" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

ENV_REPORT="$SKILL_DIR/cache/env-report.json"
require_env_report "$ENV_REPORT"
FFMPEG_BIN="$(read_json "$ENV_REPORT" ffmpeg_bin)"
FFPROBE_BIN="$(read_json "$ENV_REPORT" ffprobe_bin)"
PYTHON_BIN="$(read_json "$ENV_REPORT" python_bin)"
[[ -z "$PYTHON_BIN" ]] && PYTHON_BIN="python3"
[[ -z "$FFMPEG_BIN"  || ! -x "$FFMPEG_BIN"  ]] && { echo "ERRO: ffmpeg_bin invalido em env-report.json" >&2; exit 1; }
[[ -z "$FFPROBE_BIN" || ! -x "$FFPROBE_BIN" ]] && { echo "ERRO: ffprobe_bin invalido em env-report.json" >&2; exit 1; }

PROJECT_JSON="$PROJECT_DIR/project.json"
[[ ! -f "$PROJECT_JSON" ]] && { echo "ERRO: project.json nao existe em $PROJECT_DIR" >&2; exit 1; }

DISPLAY_W="$(read_json "$PROJECT_JSON" media.display_width)"
DISPLAY_H="$(read_json "$PROJECT_JSON" media.display_height)"
FPS="$(read_json "$PROJECT_JSON" media.fps)"
ROTATION="$(read_json "$PROJECT_JSON" media.rotation)"
SUBTITLE_STYLE="$(read_json "$PROJECT_JSON" settings.subtitle_style)"
[[ -z "$DISPLAY_W" || -z "$DISPLAY_H" ]] && { echo "ERRO: project.json sem media.display_width/height" >&2; exit 1; }
[[ -z "$FPS" ]] && FPS=30
[[ -z "$ROTATION" ]] && ROTATION=0
[[ -z "$SUBTITLE_STYLE" ]] && SUBTITLE_STYLE="sem"

# Codec args (delega para hwaccel.py que conhece NVENC/VideoToolbox/QSV/AMF + libx264)
codec_args() {
    "$PYTHON_BIN" "$SCRIPT_DIR/hwaccel.py" --quality "$1" --hwaccel "$HWACCEL"
}

# Pre-computa para uso na fase overlays (passa para Python heredoc)
QUALITY_CODEC_ARGS="$(codec_args "$QUALITY")"

# ============================================================
# Phase: cut
# ============================================================

phase_cut() {
    local edl_path="$PROJECT_DIR/edit/edl.json"
    [[ ! -f "$edl_path" ]] && { echo "ERRO: edit/edl.json nao existe. Corre auto-cut.py primeiro." >&2; exit 1; }

    local seg_dir="$PROJECT_DIR/edit/segments"
    mkdir -p "$seg_dir"

    # Source (de project.json)
    local source_rel
    source_rel="$(read_json "$PROJECT_JSON" source.local_copy)"
    [[ -z "$source_rel" ]] && { echo "ERRO: source.local_copy em falta em project.json" >&2; exit 1; }
    local source="$PROJECT_DIR/$source_rel"

    local needs_reencode=0
    case "$ROTATION" in
        90|-90|270|-270) needs_reencode=1 ;;
    esac

    echo "Phase: cut"

    local concat_list="$PROJECT_DIR/edit/concat.txt"
    > "$concat_list"

    # Para extrair segmentos do edl.json precisamos parser básico
    # Vamos usar Python helper (já disponível) para parsing robusto:
    python3 - "$edl_path" "$source" "$seg_dir" "$FFMPEG_BIN" "$needs_reencode" "$ROTATION" "$concat_list" <<'PYEOF'
import json, subprocess, sys
edl_path, source, seg_dir, ffmpeg_bin, needs_reencode, rotation, concat_list = sys.argv[1:]
needs_reencode = int(needs_reencode)
rotation = int(rotation)

with open(edl_path, encoding="utf-8") as f:
    edl = json.load(f)

with open(concat_list, "w", encoding="utf-8") as cl:
    for seg in edl["segments_keep"]:
        seg_file = f"{seg_dir}/{seg['id']}.mp4"
        cmd = [ffmpeg_bin, "-y",
               "-ss", str(seg["start"]),
               "-to", str(seg["end"]),
               "-i", source,
               "-map", "0:v:0",
               "-map", "0:a:0"]
        if needs_reencode:
            cmd += ["-c:v", "libx264", "-preset", "fast", "-crf", "20"]
            if rotation in (90, -90):
                cmd += ["-vf", "transpose=1"]
            elif rotation in (270, -270):
                cmd += ["-vf", "transpose=2"]
        else:
            cmd += ["-c:v", "copy"]
        cmd += ["-c:a", "aac", "-b:a", "192k", "-avoid_negative_ts", "make_zero", seg_file]
        print(f"  > Cortar {seg['id']} ({seg['start']}..{seg['end']})")
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stderr, file=sys.stderr)
            sys.exit(2)
        cl.write(f"file '{seg_file}'\n")
PYEOF

    local edited_out="$PROJECT_DIR/renders/edited.mp4"
    echo "  > Concatenar segmentos"
    "$FFMPEG_BIN" -y -f concat -safe 0 -i "$concat_list" -c copy "$edited_out"
    echo "OK renders/edited.mp4 gerado"
}

# ============================================================
# Phase: subs
# ============================================================

phase_subs() {
    if [[ "$SUBTITLE_STYLE" == "sem" ]]; then
        echo "subtitle_style=sem - skip"
        return 0
    fi

    local ass_path="$PROJECT_DIR/edit/subtitles.ass"
    [[ ! -f "$ass_path" ]] && { echo "ERRO: edit/subtitles.ass nao existe." >&2; exit 1; }

    local input="$PROJECT_DIR/renders/edited.mp4"
    local output="$PROJECT_DIR/renders/edited_subs.mp4"

    "$SCRIPT_DIR/burn-subtitles.sh" \
        --input "$input" \
        --subtitles "$ass_path" \
        --output "$output" \
        --preset "$QUALITY"
}

# ============================================================
# Phase: effects (zoompan etc)
# ============================================================

phase_effects() {
    local beats_plan="$PROJECT_DIR/beats_plan.json"
    if [[ ! -f "$beats_plan" ]]; then
        echo "beats_plan.json nao existe - sem efeitos"
        return 0
    fi

    # Parse video_effects via Python
    local effects_count
    effects_count="$(python3 -c "import json; d=json.load(open('$beats_plan')); print(len(d.get('video_effects', [])))")"
    if [[ "$effects_count" -eq 0 ]]; then
        echo "beats_plan sem video_effects - skip"
        return 0
    fi

    local input_candidate="$PROJECT_DIR/renders/edited_subs.mp4"
    [[ ! -f "$input_candidate" ]] && input_candidate="$PROJECT_DIR/renders/edited.mp4"

    local output="$PROJECT_DIR/cache/base_with_effects.mp4"

    # Build filters via Python
    local filter_str
    filter_str="$(python3 - "$beats_plan" "$DISPLAY_W" "$DISPLAY_H" "$FPS" <<'PYEOF'
import json, sys
beats_plan, w, h, fps = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
with open(beats_plan, encoding="utf-8") as f:
    bp = json.load(f)
parts = []
for vfx in bp.get("video_effects", []):
    if vfx.get("type") == "zoompan":
        s, e = vfx["start"], vfx["end"]
        mx = vfx.get("max_zoom", 1.25)
        rate = round((mx - 1) / max(e - s, 0.5), 4)
        expr = f"if(between(in_time,{s},{e}),min(1+{rate}*(in_time-{s}),{mx}),1)"
        parts.append(f"zoompan=z='{expr}':d=1:s={w}x{h}:fps={fps}")
print(",".join(parts))
PYEOF
)"

    if [[ -z "$filter_str" ]]; then
        echo "Sem zoompan filters - skip"
        return 0
    fi

    echo "  > Aplicar efeitos de video"
    # shellcheck disable=SC2086
    "$FFMPEG_BIN" -y -i "$input_candidate" -vf "$filter_str" $(codec_args "$QUALITY") -c:a copy "$output"
    echo "OK cache/base_with_effects.mp4 gerado"
}

# ============================================================
# Phase: overlays
# ============================================================

phase_overlays() {
    local base="$PROJECT_DIR/cache/base_with_effects.mp4"
    [[ ! -f "$base" ]] && base="$PROJECT_DIR/renders/edited_subs.mp4"
    [[ ! -f "$base" ]] && base="$PROJECT_DIR/renders/edited.mp4"

    local out_dir="$PROJECT_DIR/renders/$QUALITY"
    mkdir -p "$out_dir"
    local out="$out_dir/$QUALITY.mp4"

    local overlays_dir="$PROJECT_DIR/overlays"
    local has_overlays=0
    if [[ -d "$overlays_dir" ]]; then
        shopt -s nullglob
        local files=("$overlays_dir"/*.mov "$overlays_dir"/*.mp4)
        shopt -u nullglob
        [[ "${#files[@]}" -gt 0 ]] && has_overlays=1
    fi

    if [[ "$has_overlays" -eq 0 ]]; then
        echo "Sem overlays - a copiar base para $out"
        cp "$base" "$out"
        return 0
    fi

    # Construcao do filter_complex complicada — delegar a Python para clareza.
    # Passa os codec args pre-resolvidos (hwaccel-aware) via env var para evitar split frágil.
    export VIDEOKIT_CODEC_ARGS="$QUALITY_CODEC_ARGS"
    python3 - "$PROJECT_DIR/beats_plan.json" "$base" "${files[@]}" "$out" "$FFMPEG_BIN" <<'PYEOF'
import json, os, shlex, subprocess, sys
beats_plan_path = sys.argv[1]
base = sys.argv[2]
files = sys.argv[3:-2]
out = sys.argv[-2]
ffmpeg_bin = sys.argv[-1]
codec = shlex.split(os.environ.get("VIDEOKIT_CODEC_ARGS", "-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p"))

with open(beats_plan_path, encoding="utf-8") as f:
    bp = json.load(f)

inputs = ["-i", base]
for ov in files:
    inputs.extend(["-i", ov])

chain = "[0:v]"
i = 1
for beat in bp.get("beats", []):
    name = beat["id"] + ".mov"
    if not any(name in f for f in files):
        continue
    s = beat["start"]
    e = s + beat["duration"]
    nxt = f"v{i}"
    chain += f"[{i}:v]overlay=0:0:enable='between(t,{s},{e})'[{nxt}];[{nxt}]"
    i += 1
chain = chain.rstrip(";[v").rstrip("[v]") + ",format=yuv420p[outv]"

cmd = [ffmpeg_bin, "-y"] + inputs + ["-filter_complex", chain, "-map", "[outv]", "-map", "0:a:0"] + codec + ["-c:a","aac","-b:a","192k", out]
r = subprocess.run(cmd, capture_output=True, text=True)
if r.returncode != 0:
    print(r.stderr, file=sys.stderr)
    sys.exit(2)
PYEOF
    unset VIDEOKIT_CODEC_ARGS

    echo "OK renders/$QUALITY/$QUALITY.mp4 gerado"
}

# ============================================================
# Phase: verify
# ============================================================

phase_verify() {
    local target="$PROJECT_DIR/renders/$QUALITY/$QUALITY.mp4"
    [[ ! -f "$target" ]] && target="$PROJECT_DIR/renders/final/final.mp4"
    [[ ! -f "$target" ]] && target="$PROJECT_DIR/renders/draft/draft.mp4"
    [[ ! -f "$target" ]] && { echo "ERRO: nenhum render encontrado." >&2; exit 1; }

    local duration
    duration="$("$FFPROBE_BIN" -v error -show_entries format=duration -of default=nw=1:nk=1 "$target")"
    echo "Duracao: $duration s"

    local verify_dir="$PROJECT_DIR/verify"
    mkdir -p "$verify_dir"

    # Timestamps fixos: 1s, 25%, 50%, 75%, duration-1
    local t_quarter t_half t_three_q t_end
    t_quarter="$(awk -v d="$duration" 'BEGIN { printf "%.3f", d*0.25 }')"
    t_half="$(awk -v d="$duration" 'BEGIN { printf "%.3f", d*0.5 }')"
    t_three_q="$(awk -v d="$duration" 'BEGIN { printf "%.3f", d*0.75 }')"
    t_end="$(awk -v d="$duration" 'BEGIN { printf "%.3f", d-1.0 }')"

    local timestamps=("1.000" "$t_quarter" "$t_half" "$t_three_q" "$t_end")

    # Picos de efeitos via Python
    if [[ -f "$PROJECT_DIR/beats_plan.json" ]]; then
        local peaks
        peaks="$(python3 -c "
import json
d = json.load(open('$PROJECT_DIR/beats_plan.json'))
for vfx in d.get('video_effects', []):
    peak = (vfx['start'] + vfx['end']) / 2
    print(f'{peak:.3f}')
")"
        while IFS= read -r p; do
            [[ -n "$p" ]] && timestamps+=("$p")
        done <<< "$peaks"
    fi

    echo "Extraindo ${#timestamps[@]} frames para verify/..."
    for t in "${timestamps[@]}"; do
        "$FFMPEG_BIN" -y -ss "$t" -i "$target" -frames:v 1 "$verify_dir/frame_${t}.png" 2>/dev/null
    done

    # silencedetect
    local silence_count
    silence_count="$("$FFMPEG_BIN" -i "$target" -af silencedetect=n=-30dB:d=2 -f null - 2>&1 | grep -c silence_start || true)"

    echo "Silencios > 2s: $silence_count"
    echo "OK Verificacao concluida (${#timestamps[@]} frames em verify/)"
}

# ============================================================
# Cache cleanup
# ============================================================

clean_cache_if_requested() {
    if [[ "$CLEAN_CACHE" -eq 1 ]]; then
        echo "A limpar cache/ (--clean-cache pedido)..."
        rm -rf "$PROJECT_DIR/cache"/*
        echo "OK cache/ limpo (verify/ e renders/ mantidos)"
    fi
}

# ============================================================
# Dispatch
# ============================================================

case "$PHASE" in
    cut)      phase_cut ;;
    subs)     phase_subs ;;
    effects)  phase_effects ;;
    overlays) phase_overlays ;;
    verify)   phase_verify ;;
    all)
        phase_cut
        phase_subs
        phase_effects
        phase_overlays
        phase_verify
        ;;
    *) echo "ERRO: --phase invalido '$PHASE'" >&2; exit 2 ;;
esac

clean_cache_if_requested

echo ""
echo "Phase '$PHASE' concluida."
