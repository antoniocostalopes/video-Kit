#!/usr/bin/env python3
"""
auto-cut.py — Gera EDL (edit decision list) a partir do transcript clean.json.

Deteta para remover:
  - Silencios > --min-silence (default 0.5s)
  - Fillers em PT/EN (lista configuravel)
  - Retakes (frase iniciada e abortada)

Saida: <project>/edit/edl.json

Uso:
  python auto-cut.py <project-dir>
                     [--min-silence 0.5]
                     [--fillers-pt]
                     [--fillers-en]
                     [--keep-pauses-over 1.0]   # nao corta pausas dramaticas
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

FILLERS_PT = {
    "ahn", "ah", "hum", "hmm", "eh", "ehh", "uhm",
    "tipo", "tipo assim", "ne", "ne?",
    "entao", "digamos", "pronto",
    "e tipo", "tipo que",
}

FILLERS_EN = {
    "um", "umm", "uh", "uhh", "er", "erm",
    "like", "you know", "i mean",
    "actually", "basically", "literally",
    "so", "well",
}


def normalize(text: str) -> str:
    """Normaliza texto para comparar com fillers."""
    t = text.lower().strip()
    t = re.sub(r"[.,!?;:\"'`´]+$", "", t)
    return t


def detect_silences(words: list[dict], min_silence: float, keep_pauses_over: float) -> list[dict]:
    """Identifica gaps de silencio entre palavras."""
    silences = []
    for i in range(len(words) - 1):
        gap = words[i + 1]["start"] - words[i]["end"]
        if gap >= min_silence:
            # Manter pausas dramaticas se configurado
            if keep_pauses_over and gap >= keep_pauses_over:
                continue
            silences.append({
                "start": round(words[i]["end"], 3),
                "end": round(words[i + 1]["start"], 3),
                "duration": round(gap, 3),
                "type": "silence",
            })
    return silences


def detect_fillers(words: list[dict], filler_set: set[str]) -> list[dict]:
    """Identifica palavras filler."""
    out = []
    i = 0
    while i < len(words):
        w = words[i]
        word_norm = normalize(w["text"])

        # Bigramas primeiro ("tipo assim", "you know")
        if i + 1 < len(words):
            bigram = f"{word_norm} {normalize(words[i + 1]['text'])}"
            if bigram in filler_set:
                out.append({
                    "start": round(w["start"], 3),
                    "end": round(words[i + 1]["end"], 3),
                    "text": bigram,
                    "type": "filler",
                })
                i += 2
                continue

        if word_norm in filler_set:
            out.append({
                "start": round(w["start"], 3),
                "end": round(w["end"], 3),
                "text": word_norm,
                "type": "filler",
            })
        i += 1
    return out


def detect_retakes(segments: list[dict]) -> list[dict]:
    """Deteta retakes: inicio de frase repetido dentro de < 2s."""
    out = []
    for i in range(len(segments) - 1):
        cur = segments[i]
        nxt = segments[i + 1]
        gap = nxt["start"] - cur["end"]
        if gap > 2.0:
            continue
        cur_words = normalize(cur["text"]).split()[:3]
        nxt_words = normalize(nxt["text"]).split()[:3]
        if len(cur_words) < 2 or len(nxt_words) < 2:
            continue
        if cur_words == nxt_words:
            out.append({
                "start": round(cur["start"], 3),
                "end": round(cur["end"], 3),
                "text": cur["text"],
                "type": "retake",
            })
    return out


def merge_cuts(cuts: list[dict]) -> list[dict]:
    """Funde cortes sobrepostos ou contiguos."""
    if not cuts:
        return []
    cuts = sorted(cuts, key=lambda c: c["start"])
    merged = [dict(cuts[0])]
    for c in cuts[1:]:
        last = merged[-1]
        if c["start"] <= last["end"] + 0.05:
            last["end"] = max(last["end"], c["end"])
            last["type"] = last["type"] if last["type"] == c["type"] else "mixed"
        else:
            merged.append(dict(c))
    return merged


def cuts_to_keep_segments(cuts: list[dict], duration: float) -> list[dict]:
    """Inverte: dada lista de cortes, devolve lista de segmentos a manter."""
    keep = []
    cursor = 0.0
    seg_id = 0
    for c in cuts:
        if c["start"] > cursor + 0.05:
            keep.append({
                "id": f"seg_{seg_id:03d}",
                "start": round(cursor, 3),
                "end": round(c["start"], 3),
                "reason": "kept",
            })
            seg_id += 1
        cursor = max(cursor, c["end"])
    if cursor < duration - 0.05:
        keep.append({
            "id": f"seg_{seg_id:03d}",
            "start": round(cursor, 3),
            "end": round(duration, 3),
            "reason": "kept",
        })
    return keep


def update_project_state(project_dir: Path, n_cuts: int, n_kept: int, removed_s: float) -> None:
    project_json_path = project_dir / "project.json"
    project = json.loads(project_json_path.read_text(encoding="utf-8"))
    project["edit"] = {
        "edl_path": "edit/edl.json",
        "cuts_removed": n_cuts,
        "segments_kept": n_kept,
        "duration_removed_s": round(removed_s, 1),
    }
    project["events"].append({
        "phase": "auto-cut",
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "cuts": n_cuts,
    })
    project_json_path.write_text(
        json.dumps(project, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def main():
    ap = argparse.ArgumentParser(description="Gera EDL a partir do transcript.")
    ap.add_argument("project_dir", type=Path)
    ap.add_argument("--min-silence", type=float, default=0.5, help="Silencio minimo para cortar (s)")
    ap.add_argument("--keep-pauses-over", type=float, default=2.0, help="Pausas acima disto sao mantidas (s). 0 desativa.")
    ap.add_argument("--fillers-pt", action="store_true", default=True)
    ap.add_argument("--no-fillers-pt", dest="fillers_pt", action="store_false")
    ap.add_argument("--fillers-en", action="store_true", default=False)
    ap.add_argument("--detect-retakes", action="store_true", default=True)
    ap.add_argument("--no-retakes", dest="detect_retakes", action="store_false")
    args = ap.parse_args()

    project_dir = args.project_dir.resolve()
    if not (project_dir / "project.json").exists():
        print(f"ERRO: project.json nao existe em {project_dir}", file=sys.stderr)
        sys.exit(1)

    clean_path = project_dir / "transcripts" / "clean.json"
    if not clean_path.exists():
        print(f"ERRO: transcripts/clean.json nao existe. Corre transcribe.py primeiro.", file=sys.stderr)
        sys.exit(1)

    transcript = json.loads(clean_path.read_text(encoding="utf-8"))
    project = json.loads((project_dir / "project.json").read_text(encoding="utf-8"))
    duration = float(project["media"]["duration_s"])

    words = transcript.get("words", [])
    segments = transcript.get("segments", [])

    if not words:
        print("AVISO: transcript sem word timestamps. Corte por fillers limitado.", file=sys.stderr)

    print(f"Duracao do source: {duration:.1f}s")
    print(f"Transcript: {len(segments)} segmentos, {len(words)} palavras")

    all_cuts = []

    if words:
        silences = detect_silences(words, args.min_silence, args.keep_pauses_over)
        print(f"Silencios > {args.min_silence}s: {len(silences)}")
        all_cuts.extend(silences)

    filler_set = set()
    if args.fillers_pt:
        filler_set |= FILLERS_PT
    if args.fillers_en:
        filler_set |= FILLERS_EN

    if words and filler_set:
        fillers = detect_fillers(words, filler_set)
        print(f"Fillers detetados: {len(fillers)}")
        all_cuts.extend(fillers)

    if args.detect_retakes and segments:
        retakes = detect_retakes(segments)
        print(f"Retakes: {len(retakes)}")
        all_cuts.extend(retakes)

    merged = merge_cuts(all_cuts)
    removed_s = sum(c["end"] - c["start"] for c in merged)
    keep = cuts_to_keep_segments(merged, duration)
    final_duration = sum(s["end"] - s["start"] for s in keep)

    print(f"Total cortes apos merge: {len(merged)} ({removed_s:.1f}s removidos)")
    print(f"Segmentos mantidos: {len(keep)} ({final_duration:.1f}s)")

    edl = {
        "source": project["source"]["local_copy"],
        "source_duration_s": duration,
        "final_duration_s": round(final_duration, 1),
        "duration_removed_s": round(removed_s, 1),
        "config": {
            "min_silence": args.min_silence,
            "keep_pauses_over": args.keep_pauses_over,
            "fillers_pt": args.fillers_pt,
            "fillers_en": args.fillers_en,
            "detect_retakes": args.detect_retakes,
        },
        "segments_keep": keep,
        "cuts_removed": merged,
    }

    edl_path = project_dir / "edit" / "edl.json"
    edl_path.parent.mkdir(parents=True, exist_ok=True)
    edl_path.write_text(
        json.dumps(edl, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"EDL escrito em {edl_path}")

    update_project_state(project_dir, len(merged), len(keep), removed_s)
    print("OK EDL gerado.")


if __name__ == "__main__":
    main()
