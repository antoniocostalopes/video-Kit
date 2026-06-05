#!/usr/bin/env python3
"""
auto-chapters.py — Gera chapters automáticos a partir do transcript clean.json.

Estratégia:
  1. Procura silêncios > --min-pause (default 1.5s) no transcript.
  2. Cada silêncio + mudança de tópico vira candidato a chapter boundary.
  3. Filtra para min --min-chapter-duration (default 30s) entre chapters.
  4. Para cada chapter, gera título: primeiras N palavras da frase seguinte (até cair em pontuação).

Outputs:
  <project>/edit/chapters.json          — formato canónico videokit
  <project>/edit/chapters.ffmetadata    — para embed no MP4 via ffmpeg -f ffmetadata
  <project>/edit/chapters.youtube.txt   — copy/paste na descrição YouTube
  <project>/edit/chapters.podcast.txt   — formato podcast (HH:MM:SS - título)

Uso:
  python auto-chapters.py <project-dir> [--min-pause 1.5] [--min-chapter-duration 30]
                                        [--max-title-words 8] [--language pt|en]
                                        [--from-final]   # usa final.mp4 + ajusta timestamps com edl
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path


def seconds_to_timecode(seconds: float, fmt: str = "hms") -> str:
    """Formato HH:MM:SS ou MM:SS conforme duração."""
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if fmt == "hms" or h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def first_n_words(text: str, n: int) -> str:
    """Primeiras n palavras, parando em pontuação forte."""
    text = text.strip()
    if not text:
        return ""
    words = text.split()
    out = []
    for w in words[:n]:
        out.append(w)
        if w.endswith((".", "!", "?", "…")):
            break
    result = " ".join(out).strip(" ,;:")
    if result and result[-1] not in ".!?…":
        result = result.rstrip(",")
    return result


def detect_pause_boundaries(words: list[dict], min_pause: float) -> list[float]:
    """Devolve timestamps onde há pausa > min_pause."""
    boundaries = []
    for i in range(len(words) - 1):
        gap = words[i + 1]["start"] - words[i]["end"]
        if gap >= min_pause:
            boundaries.append(words[i + 1]["start"])
    return boundaries


def map_source_to_final_time(t_source: float, edl: dict) -> float | None:
    """Converte timestamp do source para timestamp no final.mp4 (após cortes).
    Devolve None se t_source cai num segmento removido."""
    elapsed = 0.0
    for seg in edl.get("segments_keep", []):
        s, e = seg["start"], seg["end"]
        if s <= t_source < e:
            return elapsed + (t_source - s)
        if t_source < s:
            return None
        elapsed += (e - s)
    return None


def build_chapters(
    words: list[dict],
    segments: list[dict],
    duration: float,
    min_pause: float,
    min_chapter_duration: float,
    max_title_words: int,
    language: str,
) -> list[dict]:
    """Constrói lista de chapters [{start, end, title}]."""
    if not words:
        # Sem word timestamps — chapters por segmento de transcript
        chapters = []
        for i, seg in enumerate(segments[:: max(1, len(segments) // 8)]):
            chapters.append({
                "start": float(seg["start"]),
                "title": first_n_words(seg["text"], max_title_words) or f"Capítulo {i+1}",
            })
        return _close_chapters(chapters, duration)

    boundaries = detect_pause_boundaries(words, min_pause)

    # Sempre começa em 0
    chapters = [{"start": 0.0, "title": ""}]

    for t in boundaries:
        if t - chapters[-1]["start"] < min_chapter_duration:
            continue
        chapters.append({"start": float(t), "title": ""})

    # Atribui título: primeiras palavras a partir do start de cada chapter
    intro_label = "Introdução" if language == "pt" else "Intro"
    for i, ch in enumerate(chapters):
        following_words = [w["text"] for w in words if w["start"] >= ch["start"]][: max_title_words * 2]
        title = first_n_words(" ".join(following_words), max_title_words)
        if not title:
            title = f"Capítulo {i+1}" if language == "pt" else f"Chapter {i+1}"
        ch["title"] = intro_label if i == 0 and ch["start"] < 1.0 else title

    return _close_chapters(chapters, duration)


def _close_chapters(chapters: list[dict], duration: float) -> list[dict]:
    """Adiciona `end` a cada chapter (= start do próximo, último = duration)."""
    for i, ch in enumerate(chapters):
        ch["end"] = chapters[i + 1]["start"] if i + 1 < len(chapters) else round(duration, 3)
        ch["start"] = round(ch["start"], 3)
        ch["end"] = round(ch["end"], 3)
    return chapters


def write_ffmetadata(chapters: list[dict], path: Path) -> None:
    """Formato ffmpeg chapters metadata (https://ffmpeg.org/ffmpeg-formats.html#Metadata-1)."""
    lines = [";FFMETADATA1"]
    for ch in chapters:
        start_ms = int(ch["start"] * 1000)
        end_ms = int(ch["end"] * 1000)
        title = ch["title"].replace("=", r"\=").replace(";", r"\;").replace("#", r"\#").replace("\\", r"\\").replace("\n", r"\n")
        lines.append("[CHAPTER]")
        lines.append("TIMEBASE=1/1000")
        lines.append(f"START={start_ms}")
        lines.append(f"END={end_ms}")
        lines.append(f"title={title}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_youtube_format(chapters: list[dict], path: Path) -> None:
    """Formato YouTube description: '00:00 Título' (primeiro tem de ser 00:00)."""
    lines = []
    for i, ch in enumerate(chapters):
        tc = seconds_to_timecode(ch["start"], fmt="auto")
        if i == 0:
            # YouTube exige primeiro chapter em 00:00
            tc = "00:00" if ":" not in tc or tc.count(":") == 1 else "00:00:00"
        lines.append(f"{tc} {ch['title']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_podcast_format(chapters: list[dict], path: Path) -> None:
    """Formato podcast (Apple/Spotify aceitam): 'HH:MM:SS - Título'."""
    lines = []
    for ch in chapters:
        tc = seconds_to_timecode(ch["start"], fmt="hms")
        lines.append(f"{tc} - {ch['title']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description="Gera chapters automáticos a partir do transcript.")
    ap.add_argument("project_dir", type=Path)
    ap.add_argument("--min-pause", type=float, default=1.5,
                    help="Pausa mínima (s) para considerar chapter boundary. Default 1.5.")
    ap.add_argument("--min-chapter-duration", type=float, default=30.0,
                    help="Duração mínima (s) entre chapters consecutivos. Default 30.")
    ap.add_argument("--max-title-words", type=int, default=8,
                    help="Número máximo de palavras no título auto-gerado.")
    ap.add_argument("--language", default="pt", choices=["pt", "en"],
                    help="Língua para labels default ('Introdução' vs 'Intro').")
    ap.add_argument("--from-final", action="store_true",
                    help="Ajusta timestamps para o final.mp4 (compensar cortes). Requer edit/edl.json.")
    args = ap.parse_args()

    project_dir = args.project_dir.resolve()
    if not (project_dir / "project.json").exists():
        print(f"ERRO: project.json nao existe em {project_dir}", file=sys.stderr)
        sys.exit(1)

    clean_path = project_dir / "transcripts" / "clean.json"
    if not clean_path.exists():
        print("ERRO: transcripts/clean.json nao existe. Corre transcribe.py primeiro.", file=sys.stderr)
        sys.exit(1)

    transcript = json.loads(clean_path.read_text(encoding="utf-8"))
    project = json.loads((project_dir / "project.json").read_text(encoding="utf-8"))
    source_duration = float(project["media"]["duration_s"])

    words = transcript.get("words", [])
    segments = transcript.get("segments", [])

    edl = None
    final_duration = source_duration
    if args.from_final:
        edl_path = project_dir / "edit" / "edl.json"
        if not edl_path.exists():
            print("ERRO: --from-final pedido mas edit/edl.json nao existe.", file=sys.stderr)
            sys.exit(1)
        edl = json.loads(edl_path.read_text(encoding="utf-8"))
        final_duration = float(edl.get("final_duration_s", source_duration))

    target_duration = final_duration if args.from_final else source_duration
    chapters = build_chapters(
        words, segments, target_duration,
        min_pause=args.min_pause,
        min_chapter_duration=args.min_chapter_duration,
        max_title_words=args.max_title_words,
        language=args.language,
    )

    if args.from_final and edl:
        adjusted = []
        for ch in chapters:
            t_final = map_source_to_final_time(ch["start"], edl)
            if t_final is None:
                continue
            adjusted.append({"start": round(t_final, 3), "title": ch["title"]})
        chapters = _close_chapters(adjusted, final_duration)

    if not chapters:
        print("AVISO: nenhum chapter gerado. Tenta --min-pause menor ou --min-chapter-duration menor.")
        sys.exit(0)

    edit_dir = project_dir / "edit"
    edit_dir.mkdir(parents=True, exist_ok=True)

    chapters_json = {
        "source": "final.mp4" if args.from_final else project["source"]["local_copy"],
        "duration_s": round(target_duration, 1),
        "language": args.language,
        "config": {
            "min_pause": args.min_pause,
            "min_chapter_duration": args.min_chapter_duration,
            "max_title_words": args.max_title_words,
            "from_final": args.from_final,
        },
        "chapters": chapters,
    }

    (edit_dir / "chapters.json").write_text(
        json.dumps(chapters_json, ensure_ascii=False, indent=2), encoding="utf-8",
    )
    write_ffmetadata(chapters, edit_dir / "chapters.ffmetadata")
    write_youtube_format(chapters, edit_dir / "chapters.youtube.txt")
    write_podcast_format(chapters, edit_dir / "chapters.podcast.txt")

    print(f"OK {len(chapters)} chapters gerados:")
    for ch in chapters:
        print(f"  {seconds_to_timecode(ch['start'], 'hms')}  {ch['title']}")
    print(f"\nFicheiros:")
    print(f"  edit/chapters.json")
    print(f"  edit/chapters.ffmetadata  (para embed via ffmpeg -i in.mp4 -i chapters.ffmetadata -map_metadata 1)")
    print(f"  edit/chapters.youtube.txt (copy/paste na descrição)")
    print(f"  edit/chapters.podcast.txt (Apple Podcasts / Spotify)")

    # Update project.json
    project["chapters"] = {
        "count": len(chapters),
        "json_path": "edit/chapters.json",
        "ffmetadata_path": "edit/chapters.ffmetadata",
        "from_final": args.from_final,
    }
    project["events"].append({
        "phase": "auto-chapters",
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "count": len(chapters),
    })
    (project_dir / "project.json").write_text(
        json.dumps(project, ensure_ascii=False, indent=2), encoding="utf-8",
    )


if __name__ == "__main__":
    main()
