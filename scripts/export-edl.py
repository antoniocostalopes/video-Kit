#!/usr/bin/env python3
"""
export-edl.py — Exporta edit/edl.json para formatos que NLEs entendem.

Formatos suportados:
  cmx3600 (.edl)       — universal, lê em Premiere/Resolve/Avid/FCP X
  fcpxml  (.fcpxml)    — DaVinci Resolve / Final Cut Pro X (versão 1.10)

Uso:
  python export-edl.py <project-dir> [--format cmx3600|fcpxml|both] [--fps 30]
                                     [--output <path>]

Default: exporta ambos os formatos para <project>/edit/.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape


def seconds_to_tc(seconds: float, fps: float) -> str:
    """Converte segundos para timecode SMPTE HH:MM:SS:FF (non-drop frame)."""
    seconds = max(0, seconds)
    total_frames = round(seconds * fps)
    fps_int = max(1, round(fps))
    frames = int(total_frames % fps_int)
    total_seconds = int(total_frames // fps_int)
    h, rem = divmod(total_seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}:{frames:02d}"


def seconds_to_rational(seconds: float, fps: float) -> str:
    """Para FCPXML: '0/30000s' ou similar. Devolve string com numerador/denominador."""
    # Usa timebase = 1000 para precisão suficiente; FCPXML aceita s/ms
    ms = int(round(seconds * 1000))
    return f"{ms}/1000s"


def export_cmx3600(edl: dict, source_filename: str, fps: float, out_path: Path, title: str) -> None:
    """
    CMX 3600 EDL — formato texto simples industry-standard.
    Cada cut tem 4 timecodes: source-in, source-out, record-in, record-out.
    Reel name = "AX" (auxiliary, sem reel físico).
    """
    lines = []
    lines.append(f"TITLE: {title}")
    lines.append("FCM: NON-DROP FRAME")
    lines.append("")

    record_cursor = 0.0
    for i, seg in enumerate(edl.get("segments_keep", []), start=1):
        src_in = seconds_to_tc(seg["start"], fps)
        src_out = seconds_to_tc(seg["end"], fps)
        rec_in = seconds_to_tc(record_cursor, fps)
        seg_duration = seg["end"] - seg["start"]
        record_cursor += seg_duration
        rec_out = seconds_to_tc(record_cursor, fps)

        # Edit number = 3 dígitos, V para video, A para audio. Usamos V+A num só corte ("B" = both).
        edit_num = f"{i:03d}"
        # CMX 3600: <num> <reel> <channels> <transition> <src_in> <src_out> <rec_in> <rec_out>
        lines.append(f"{edit_num}  AX       AA/V  C        {src_in} {src_out} {rec_in} {rec_out}")
        lines.append(f"* FROM CLIP NAME: {source_filename}")
        lines.append("")

    out_path.write_text("\n".join(lines), encoding="utf-8")


def export_fcpxml(edl: dict, source_path: str, source_filename: str, media: dict, fps: float, out_path: Path, title: str) -> None:
    """
    FCPXML 1.10 — DaVinci Resolve (18+) e Final Cut Pro X.

    Estrutura:
      fcpxml
       └── resources (format + asset)
       └── library
            └── event
                 └── project
                      └── sequence
                           └── spine
                                └── clip[] (uma por segmento_keep)
    """
    width = int(media.get("display_width") or media.get("width") or 1920)
    height = int(media.get("display_height") or media.get("height") or 1080)
    duration_s = float(media.get("duration_s") or 0)

    # Timebase para FCPXML: usa /1000s para simplicidade (precisão ms)
    asset_duration = seconds_to_rational(duration_s, fps)
    fps_str = f"{int(fps)}/1s" if fps == int(fps) else f"{int(round(fps * 1000))}/1000s"

    # Spine clips
    spine_clips = []
    for i, seg in enumerate(edl.get("segments_keep", []), start=1):
        seg_dur = seg["end"] - seg["start"]
        spine_clips.append(
            f'        <clip name="{xml_escape(source_filename)} - seg {i}" '
            f'offset="{seconds_to_rational(_offset_for_index(edl, i), fps)}" '
            f'duration="{seconds_to_rational(seg_dur, fps)}" '
            f'start="{seconds_to_rational(seg["start"], fps)}" '
            f'tcFormat="NDF">\n'
            f'          <video ref="r2" offset="0/1s" duration="{seconds_to_rational(seg_dur, fps)}" start="{seconds_to_rational(seg["start"], fps)}"/>\n'
            f'        </clip>'
        )

    fcpxml = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fcpxml>
<fcpxml version="1.10">
  <resources>
    <format id="r1" name="FFVideoFormat{height}p{int(fps)}" frameDuration="1/{int(fps)}s" width="{width}" height="{height}"/>
    <asset id="r2" name="{xml_escape(source_filename)}" start="0/1s" duration="{asset_duration}" hasVideo="1" hasAudio="1" format="r1">
      <media-rep kind="original-media" src="file://{xml_escape(source_path)}"/>
    </asset>
  </resources>
  <library>
    <event name="{xml_escape(title)}">
      <project name="{xml_escape(title)}">
        <sequence format="r1" tcFormat="NDF">
          <spine>
{chr(10).join(spine_clips)}
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
'''
    out_path.write_text(fcpxml, encoding="utf-8")


def _offset_for_index(edl: dict, index_1based: int) -> float:
    """Soma das durações dos segments_keep anteriores ao index dado."""
    total = 0.0
    for i, seg in enumerate(edl.get("segments_keep", []), start=1):
        if i >= index_1based:
            break
        total += seg["end"] - seg["start"]
    return total


def main():
    ap = argparse.ArgumentParser(description="Exporta EDL videokit para CMX 3600 / FCPXML.")
    ap.add_argument("project_dir", type=Path)
    ap.add_argument("--format", choices=["cmx3600", "fcpxml", "both"], default="both")
    ap.add_argument("--fps", type=float, default=None,
                    help="Override fps (default: lê de project.json.media.fps).")
    ap.add_argument("--output-dir", type=Path, default=None,
                    help="Override pasta de output (default: <project>/edit/).")
    args = ap.parse_args()

    project_dir = args.project_dir.resolve()
    edl_path = project_dir / "edit" / "edl.json"
    if not edl_path.exists():
        print(f"ERRO: edit/edl.json nao existe em {project_dir}. Corre auto-cut.py primeiro.", file=sys.stderr)
        sys.exit(1)

    project = json.loads((project_dir / "project.json").read_text(encoding="utf-8"))
    edl = json.loads(edl_path.read_text(encoding="utf-8"))

    fps = args.fps if args.fps else float(project["media"].get("fps") or 30.0)
    media = project["media"]
    source_filename = Path(project["source"]["local_copy"]).name
    source_path = str((project_dir / project["source"]["local_copy"]).resolve())
    title = project.get("name", "videokit_project")

    out_dir = args.output_dir.resolve() if args.output_dir else project_dir / "edit"
    out_dir.mkdir(parents=True, exist_ok=True)

    n_segments = len(edl.get("segments_keep", []))
    if n_segments == 0:
        print("AVISO: edl.json sem segments_keep — nada para exportar.")
        sys.exit(0)

    written = []
    if args.format in ("cmx3600", "both"):
        edl_out = out_dir / f"{title}.edl"
        export_cmx3600(edl, source_filename, fps, edl_out, title)
        written.append(edl_out)

    if args.format in ("fcpxml", "both"):
        fcp_out = out_dir / f"{title}.fcpxml"
        export_fcpxml(edl, source_path, source_filename, media, fps, fcp_out, title)
        written.append(fcp_out)

    print(f"OK exportados {n_segments} segmentos @ {fps}fps:")
    for p in written:
        size_kb = p.stat().st_size / 1024
        print(f"  {p}  ({size_kb:.1f} KB)")
    print("\nNotas:")
    print("  • .edl   — importa em Premiere (File > Import), Resolve (File > Import > Pre-conformed EDL), Avid")
    print("  • .fcpxml — importa em DaVinci Resolve (File > Import > Timeline > Pre-conformed FCPXML)")
    print("              e Final Cut Pro X (File > Import > XML)")
    print("  • Em Premiere, abre primeiro o source como sequence; em Resolve liga ao source via media pool.")


if __name__ == "__main__":
    main()
