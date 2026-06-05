#!/usr/bin/env python3
"""
transcribe.py — Transcreve audio para texto com word timestamps.

Provider default: Whisper local (openai-whisper).
Fallback: OpenAI Whisper API, ElevenLabs.

Saidas:
  <project>/transcripts/raw.json   — saida crua do modelo
  <project>/transcripts/clean.json — formato canonico para auto-cut.py

Uso:
  python transcribe.py <project-dir> [--provider local|openai|elevenlabs]
                                     [--model tiny|base|small|medium|large-v3]
                                     [--language pt|en|auto]

Requer:
  - openai-whisper (pip install -U openai-whisper) para --provider local
  - openai (pip install openai) para --provider openai
  - requests (pip install requests) para --provider elevenlabs
  - ffmpeg no PATH ou env-report.json
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=UserWarning)
warnings.filterwarnings("ignore", category=FutureWarning)


def load_env_report(skill_dir: Path) -> dict:
    p = skill_dir / "cache" / "env-report.json"
    if not p.exists():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def get_skill_dir(project_dir: Path) -> Path:
    """Le skill_dir de project.json. Fallback: pasta deste script."""
    pj = project_dir / "project.json"
    if pj.exists():
        data = json.loads(pj.read_text(encoding="utf-8"))
        sd = data.get("skill_dir")
        if sd:
            return Path(sd)
    return Path(__file__).resolve().parent.parent


def find_source(project_dir: Path) -> Path:
    project_json = json.loads((project_dir / "project.json").read_text(encoding="utf-8"))
    source_rel = project_json["source"]["local_copy"]
    return project_dir / source_rel


def extract_audio(ffmpeg_bin: str, video_path: Path, out_wav: Path) -> None:
    cmd = [
        ffmpeg_bin, "-y",
        "-i", str(video_path),
        "-map", "0:a:0",
        "-vn",
        "-c:a", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        str(out_wav),
    ]
    print(f"Extraindo audio para {out_wav.name}...", flush=True)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise RuntimeError("ffmpeg falhou na extracao de audio")


def transcribe_local(audio_path: Path, model_name: str, language: str | None) -> dict:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _lib import require_deps
    require_deps("core", ["whisper"])
    import whisper

    print(f"Carregando modelo Whisper '{model_name}'...", flush=True)
    t0 = time.time()
    model = whisper.load_model(model_name)
    print(f"  modelo carregado em {time.time() - t0:.1f}s", flush=True)

    print("Transcrevendo (pode demorar)...", flush=True)
    t0 = time.time()
    kwargs = {"word_timestamps": True, "verbose": False}
    if language and language != "auto":
        kwargs["language"] = language
    result = model.transcribe(str(audio_path), **kwargs)
    elapsed = time.time() - t0
    print(f"  transcricao em {elapsed:.1f}s", flush=True)

    return {
        "provider": "local",
        "model": model_name,
        "language": result.get("language", language or "auto"),
        "duration_s": elapsed,
        "raw": result,
    }


def transcribe_openai(audio_path: Path, language: str | None) -> dict:
    try:
        from openai import OpenAI
    except ImportError:
        print("ERRO: openai nao instalado. Corre: pip install openai", file=sys.stderr)
        sys.exit(2)

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("ERRO: OPENAI_API_KEY nao definida no ambiente.", file=sys.stderr)
        sys.exit(3)

    client = OpenAI(api_key=api_key)
    print("Enviando para OpenAI Whisper API...", flush=True)
    t0 = time.time()

    with audio_path.open("rb") as f:
        kwargs = {"model": "whisper-1", "response_format": "verbose_json", "timestamp_granularities": ["word", "segment"]}
        if language and language != "auto":
            kwargs["language"] = language
        resp = client.audio.transcriptions.create(file=f, **kwargs)

    elapsed = time.time() - t0
    print(f"  resposta em {elapsed:.1f}s", flush=True)

    raw = resp.model_dump() if hasattr(resp, "model_dump") else dict(resp)
    return {
        "provider": "openai",
        "model": "whisper-1",
        "language": raw.get("language", language or "auto"),
        "duration_s": elapsed,
        "raw": raw,
    }


def transcribe_elevenlabs(audio_path: Path, language: str | None) -> dict:
    try:
        import requests
    except ImportError:
        print("ERRO: requests nao instalado. Corre: pip install requests", file=sys.stderr)
        sys.exit(2)

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        print("ERRO: ELEVENLABS_API_KEY nao definida no ambiente.", file=sys.stderr)
        sys.exit(3)

    print("Enviando para ElevenLabs Speech-to-Text...", flush=True)
    t0 = time.time()
    url = "https://api.elevenlabs.io/v1/speech-to-text"
    headers = {"xi-api-key": api_key}

    with audio_path.open("rb") as f:
        files = {"file": (audio_path.name, f, "audio/wav")}
        data = {"model_id": "scribe_v1"}
        if language and language != "auto":
            data["language_code"] = language
        resp = requests.post(url, headers=headers, files=files, data=data, timeout=600)

    if resp.status_code != 200:
        print(f"ElevenLabs falhou: {resp.status_code} {resp.text}", file=sys.stderr)
        sys.exit(4)

    raw = resp.json()
    elapsed = time.time() - t0
    print(f"  resposta em {elapsed:.1f}s", flush=True)

    return {
        "provider": "elevenlabs",
        "model": "scribe_v1",
        "language": raw.get("language_code", language or "auto"),
        "duration_s": elapsed,
        "raw": raw,
    }


def to_canonical(provider_result: dict) -> dict:
    """Converte saida de qualquer provider para formato canonico."""
    raw = provider_result["raw"]
    provider = provider_result["provider"]

    segments = []
    words = []

    if provider == "local":
        for seg in raw.get("segments", []):
            segments.append({
                "id": seg.get("id"),
                "start": round(float(seg["start"]), 3),
                "end": round(float(seg["end"]), 3),
                "text": seg["text"].strip(),
            })
            for w in seg.get("words", []) or []:
                words.append({
                    "start": round(float(w["start"]), 3),
                    "end": round(float(w["end"]), 3),
                    "text": w["word"].strip(),
                })
    elif provider == "openai":
        for i, seg in enumerate(raw.get("segments", []) or []):
            segments.append({
                "id": i,
                "start": round(float(seg["start"]), 3),
                "end": round(float(seg["end"]), 3),
                "text": seg["text"].strip(),
            })
        for w in raw.get("words", []) or []:
            words.append({
                "start": round(float(w["start"]), 3),
                "end": round(float(w["end"]), 3),
                "text": w["word"].strip(),
            })
    elif provider == "elevenlabs":
        # ElevenLabs returns words array; build segments by sentence
        el_words = raw.get("words", []) or []
        current = {"start": None, "end": None, "text": []}
        seg_id = 0
        for w in el_words:
            t_start = round(float(w["start"]), 3)
            t_end = round(float(w["end"]), 3)
            text = w.get("text", "")
            words.append({"start": t_start, "end": t_end, "text": text.strip()})
            if current["start"] is None:
                current["start"] = t_start
            current["end"] = t_end
            current["text"].append(text)
            if text.endswith((".", "!", "?")):
                segments.append({
                    "id": seg_id,
                    "start": current["start"],
                    "end": current["end"],
                    "text": " ".join(current["text"]).strip(),
                })
                seg_id += 1
                current = {"start": None, "end": None, "text": []}
        if current["text"]:
            segments.append({
                "id": seg_id,
                "start": current["start"],
                "end": current["end"],
                "text": " ".join(current["text"]).strip(),
            })

    duration = 0.0
    if segments:
        duration = segments[-1]["end"]

    return {
        "language": provider_result["language"],
        "provider": provider,
        "model": provider_result.get("model"),
        "duration_s": duration,
        "segments": segments,
        "words": words,
    }


def write_json(path: Path, data: dict) -> None:
    text = json.dumps(data, ensure_ascii=False, indent=2)
    path.write_text(text, encoding="utf-8")


def update_project_state(project_dir: Path, provider: str, model: str, elapsed: float, n_segments: int, n_words: int) -> None:
    project_json_path = project_dir / "project.json"
    project = json.loads(project_json_path.read_text(encoding="utf-8"))
    project["transcript"] = {
        "provider": provider,
        "model": model,
        "elapsed_s": round(elapsed, 1),
        "segments": n_segments,
        "words": n_words,
        "raw_path": "transcripts/raw.json",
        "clean_path": "transcripts/clean.json",
    }
    project["events"].append({
        "phase": "transcribe",
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "provider": provider,
    })
    write_json(project_json_path, project)


def main():
    ap = argparse.ArgumentParser(description="Transcreve video de um projeto videokit.")
    ap.add_argument("project_dir", type=Path, help="Caminho para projects/YYYY-MM-DD_slug/")
    ap.add_argument("--provider", choices=["local", "openai", "elevenlabs"], default="local")
    ap.add_argument("--model", default="medium", help="Modelo Whisper local (tiny|base|small|medium|large-v3)")
    ap.add_argument("--language", default="pt", help="Codigo ISO (pt|en|es|auto)")
    args = ap.parse_args()

    project_dir = args.project_dir.resolve()
    if not (project_dir / "project.json").exists():
        print(f"ERRO: project.json nao existe em {project_dir}", file=sys.stderr)
        sys.exit(1)

    skill_dir = get_skill_dir(project_dir)
    env = load_env_report(skill_dir)
    ffmpeg_bin = env.get("ffmpeg_bin") or "ffmpeg"

    source = find_source(project_dir)
    audio_wav = project_dir / "cache" / "audio.wav"
    audio_wav.parent.mkdir(parents=True, exist_ok=True)

    if not audio_wav.exists():
        extract_audio(ffmpeg_bin, source, audio_wav)
    else:
        print(f"Audio ja existe: {audio_wav}")

    t_total = time.time()
    if args.provider == "local":
        result = transcribe_local(audio_wav, args.model, args.language)
    elif args.provider == "openai":
        result = transcribe_openai(audio_wav, args.language)
    elif args.provider == "elevenlabs":
        result = transcribe_elevenlabs(audio_wav, args.language)
    else:
        raise ValueError(f"provider desconhecido: {args.provider}")

    raw_path = project_dir / "transcripts" / "raw.json"
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    write_json(raw_path, result["raw"])
    print(f"Raw escrito em {raw_path}")

    canonical = to_canonical(result)
    clean_path = project_dir / "transcripts" / "clean.json"
    write_json(clean_path, canonical)
    print(f"Clean escrito em {clean_path}")

    print(f"  {len(canonical['segments'])} segmentos, {len(canonical['words'])} palavras")
    print(f"  lingua detetada: {canonical['language']}")

    update_project_state(
        project_dir,
        provider=args.provider,
        model=result.get("model", args.model),
        elapsed=time.time() - t_total,
        n_segments=len(canonical["segments"]),
        n_words=len(canonical["words"]),
    )

    print("OK Transcricao concluida.")


if __name__ == "__main__":
    main()
