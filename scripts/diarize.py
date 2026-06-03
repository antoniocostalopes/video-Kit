#!/usr/bin/env python3
"""
diarize.py — Diarização (quem fala quando) via pyannote-audio.

Identifica falantes (SPEAKER_00, SPEAKER_01, ...) e gera timeline. Integra com
transcripts/clean.json para etiquetar cada segmento com o orador.

Output:
  <project>/transcripts/diarization.json   - timeline {start, end, speaker}
  <project>/transcripts/clean_diarized.json - clean + speaker_id por segmento

Uso:
  python diarize.py <project-dir> [--num-speakers 2] [--device cpu|cuda]

Requer:
  pip install pyannote.audio torch
  HF_TOKEN env var (free no huggingface.co - aceita termos do modelo pyannote/speaker-diarization-3.1)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)


def assign_speakers_to_segments(transcript_segments, diarization_turns):
    """Para cada segmento do transcript, atribui o speaker que mais overlap teve."""
    out = []
    for seg in transcript_segments:
        s_start, s_end = seg["start"], seg["end"]
        # Calcula overlap com cada turn
        best_spk = None
        best_overlap = 0.0
        for turn in diarization_turns:
            overlap = max(0.0, min(s_end, turn["end"]) - max(s_start, turn["start"]))
            if overlap > best_overlap:
                best_overlap = overlap
                best_spk = turn["speaker"]
        new_seg = dict(seg)
        new_seg["speaker"] = best_spk if best_spk else "UNKNOWN"
        out.append(new_seg)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project_dir", type=Path)
    ap.add_argument("--num-speakers", type=int, default=None, help="Forca numero de speakers. Default: auto-deteta.")
    ap.add_argument("--min-speakers", type=int, default=None)
    ap.add_argument("--max-speakers", type=int, default=None)
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda", "mps"])
    ap.add_argument("--model", default="pyannote/speaker-diarization-3.1")
    args = ap.parse_args()

    if not args.project_dir.exists():
        print(f"ERRO: project_dir nao existe", file=sys.stderr)
        sys.exit(1)

    project_json_path = args.project_dir / "project.json"
    if not project_json_path.exists():
        print(f"ERRO: project.json nao existe em {args.project_dir}", file=sys.stderr)
        sys.exit(1)

    hf_token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")
    if not hf_token:
        print("ERRO: HF_TOKEN env var em falta.", file=sys.stderr)
        print("Cria token gratuito em https://huggingface.co/settings/tokens", file=sys.stderr)
        print("Depois aceita termos do modelo em https://huggingface.co/pyannote/speaker-diarization-3.1", file=sys.stderr)
        sys.exit(2)

    try:
        import torch
        from pyannote.audio import Pipeline
    except ImportError as e:
        print(f"ERRO: dependencia em falta ({e}).", file=sys.stderr)
        print("Corre: pip install pyannote.audio torch", file=sys.stderr)
        sys.exit(2)

    # Usar audio.wav cached pelo transcribe (se existe)
    audio_wav = args.project_dir / "cache" / "audio.wav"
    if not audio_wav.exists():
        # Extrair audio
        project = json.loads(project_json_path.read_text(encoding="utf-8"))
        source = args.project_dir / project["source"]["local_copy"]

        skill_dir = Path(__file__).resolve().parent.parent
        env = json.loads((skill_dir / "cache" / "env-report.json").read_text(encoding="utf-8"))
        ffmpeg_bin = env.get("ffmpeg_bin") or "ffmpeg"

        import subprocess
        audio_wav.parent.mkdir(parents=True, exist_ok=True)
        print("A extrair audio para diarizacao...")
        subprocess.run([
            ffmpeg_bin, "-y", "-i", str(source),
            "-map", "0:a:0", "-vn",
            "-c:a", "pcm_s16le", "-ar", "16000", "-ac", "1",
            str(audio_wav)
        ], capture_output=True, check=True)

    # Carregar pipeline
    print(f"A carregar modelo {args.model} (primeira corrida descarrega ~80MB)...")
    pipeline = Pipeline.from_pretrained(args.model, use_auth_token=hf_token)

    if args.device != "cpu":
        if args.device == "cuda" and torch.cuda.is_available():
            pipeline.to(torch.device("cuda"))
        elif args.device == "mps" and torch.backends.mps.is_available():
            pipeline.to(torch.device("mps"))

    # Diarizar
    print("A diarizar (pode demorar varios minutos)...")
    kwargs = {}
    if args.num_speakers:
        kwargs["num_speakers"] = args.num_speakers
    elif args.min_speakers or args.max_speakers:
        if args.min_speakers: kwargs["min_speakers"] = args.min_speakers
        if args.max_speakers: kwargs["max_speakers"] = args.max_speakers

    diarization = pipeline(str(audio_wav), **kwargs)

    # Construir timeline
    turns = []
    speakers_seen = set()
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        turns.append({
            "start": round(turn.start, 3),
            "end": round(turn.end, 3),
            "speaker": speaker,
        })
        speakers_seen.add(speaker)

    print(f"  {len(turns)} turns identificados, {len(speakers_seen)} orador(es)")

    # Escrever diarization.json
    diar_path = args.project_dir / "transcripts" / "diarization.json"
    diar_path.parent.mkdir(parents=True, exist_ok=True)
    diar_path.write_text(json.dumps({
        "model": args.model,
        "num_speakers": len(speakers_seen),
        "speakers": sorted(speakers_seen),
        "turns": turns,
    }, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"OK diarization escrita em {diar_path}")

    # Mergear com transcripts/clean.json se existir
    clean_path = args.project_dir / "transcripts" / "clean.json"
    if clean_path.exists():
        clean = json.loads(clean_path.read_text(encoding="utf-8"))
        clean["segments"] = assign_speakers_to_segments(clean["segments"], turns)
        clean_diarized_path = args.project_dir / "transcripts" / "clean_diarized.json"
        clean_diarized_path.write_text(json.dumps(clean, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"OK clean_diarized escrito em {clean_diarized_path}")
        print(f"   (segmentos agora tem campo 'speaker' = SPEAKER_00, SPEAKER_01, ...)")


if __name__ == "__main__":
    main()
