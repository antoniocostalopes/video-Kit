#!/usr/bin/env python3
"""
queue.py — Batch processing de vídeos. Orquestra init-project + transcribe + auto-cut + render
para todos os vídeos numa pasta.

Estado guardado em <video-dir>/.videokit-queue.json — permite resume.

Uso:
  python queue.py <video-dir> [--preset reels|youtube|...]
                              [--subs completas|karaoke|highlights|sem]
                              [--mode full|cut-only]
                              [--language pt|en|auto]
                              [--ext mp4,mov,mkv]
                              [--skip-existing]   # salta videos com final.mp4
                              [--dry-run]         # lista o que faria, sem executar
                              [--continue-on-error]

Default: processa todos os mp4/mov da pasta, modo cut-only, pt, sem extras.
"""
from __future__ import annotations

import argparse
import json
import platform
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
DEFAULT_EXTS = {"mp4", "mov", "mkv", "webm", "m4v"}


def is_windows() -> bool:
    return platform.system().lower().startswith("win")


def python_bin() -> str:
    env_path = SKILL_DIR / "cache" / "env-report.json"
    if env_path.exists():
        try:
            env = json.loads(env_path.read_text(encoding="utf-8"))
            if env.get("python_bin"):
                return env["python_bin"]
        except Exception:
            pass
    return sys.executable or ("python" if is_windows() else "python3")


def run_init_project(video: Path, mode: str, subs: str) -> Path | None:
    """Invoca init-project.{ps1,sh}. Devolve project_dir absoluto."""
    if is_windows():
        cmd = [
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(SCRIPT_DIR / "init-project.ps1"),
            "-InputVideo", str(video),
            "-Mode", mode,
            "-Subs", subs,
        ]
    else:
        cmd = [
            "bash", str(SCRIPT_DIR / "init-project.sh"),
            "--input", str(video),
            "--mode", mode,
            "--subs", subs,
        ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        return None
    # Última linha JSON com project_dir
    for line in reversed(proc.stdout.strip().splitlines()):
        line = line.strip()
        if line.startswith("{") and "project_dir" in line:
            try:
                return Path(json.loads(line)["project_dir"])
            except Exception:
                continue
    print(proc.stdout)
    return None


def run_transcribe(project_dir: Path, language: str) -> bool:
    cmd = [python_bin(), str(SCRIPT_DIR / "transcribe.py"), str(project_dir), "--language", language]
    return subprocess.run(cmd).returncode == 0


def run_auto_cut(project_dir: Path, language: str) -> bool:
    cmd = [python_bin(), str(SCRIPT_DIR / "auto-cut.py"), str(project_dir)]
    if language == "en":
        cmd.append("--fillers-en")
    return subprocess.run(cmd).returncode == 0


def run_render(project_dir: Path, quality: str = "final") -> bool:
    if is_windows():
        cmd = [
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(SCRIPT_DIR / "render.ps1"),
            "-ProjectDir", str(project_dir),
            "-Phase", "all",
            "-Quality", quality,
        ]
    else:
        cmd = [
            "bash", str(SCRIPT_DIR / "render.sh"),
            "--project-dir", str(project_dir),
            "--phase", "all",
            "--quality", quality,
        ]
    return subprocess.run(cmd).returncode == 0


def run_audio_pack(project_dir: Path, preset: str | None) -> bool:
    """Audio pack opcional. Substitui edited.mp4 por versão limpa + normalizada por preset."""
    edited = project_dir / "renders" / "edited.mp4"
    if not edited.exists():
        return True  # nada para processar, segue
    out = project_dir / "renders" / "edited_audio.mp4"
    if is_windows():
        cmd = [
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(SCRIPT_DIR / "audio-process.ps1"),
            "-InputFile", str(edited),
            "-OutputFile", str(out),
            "-Denoise", "-Normalize", "-Compress",
        ]
        if preset:
            cmd += ["-Preset", preset]
    else:
        cmd = [
            "bash", str(SCRIPT_DIR / "audio-process.sh"),
            "--input", str(edited),
            "--output", str(out),
            "--denoise", "--normalize", "--compress",
        ]
        if preset:
            cmd += ["--preset", preset]
    ok = subprocess.run(cmd).returncode == 0
    if ok and out.exists():
        # Swap: a versão com áudio limpo passa a ser o "edited.mp4"
        edited_bak = project_dir / "renders" / "edited_raw.mp4"
        edited.rename(edited_bak)
        out.rename(edited)
    return ok


def discover_videos(video_dir: Path, exts: set[str]) -> list[Path]:
    out = []
    for p in sorted(video_dir.iterdir()):
        if p.is_file() and p.suffix.lstrip(".").lower() in exts:
            out.append(p)
    return out


def load_queue_state(video_dir: Path) -> dict:
    state_path = video_dir / ".videokit-queue.json"
    if state_path.exists():
        try:
            return json.loads(state_path.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"jobs": {}}


def save_queue_state(video_dir: Path, state: dict) -> None:
    state_path = video_dir / ".videokit-queue.json"
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    ap = argparse.ArgumentParser(description="Batch process de uma pasta de vídeos.")
    ap.add_argument("video_dir", type=Path)
    ap.add_argument("--preset", default=None, help="Plataforma (youtube, reels, tiktok, podcast-video...)")
    ap.add_argument("--subs", default="sem", choices=["completas", "karaoke", "highlights", "sem"])
    ap.add_argument("--mode", default="cut-only", choices=["full", "cut-only"])
    ap.add_argument("--language", default="pt")
    ap.add_argument("--ext", default="mp4,mov,mkv,webm,m4v",
                    help="Extensões a processar (separadas por virgula).")
    ap.add_argument("--skip-existing", action="store_true",
                    help="Salta vídeos com renders/final/final.mp4 já presente em queue state.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Lista o que processaria sem executar.")
    ap.add_argument("--continue-on-error", action="store_true",
                    help="Continua para o próximo vídeo se um falhar.")
    ap.add_argument("--with-audio-pack", action="store_true",
                    help="Aplica denoise+normalize+compress entre cut e render.")
    args = ap.parse_args()

    video_dir = args.video_dir.resolve()
    if not video_dir.is_dir():
        print(f"ERRO: nao e directorio: {video_dir}", file=sys.stderr)
        sys.exit(1)

    exts = {e.strip().lower().lstrip(".") for e in args.ext.split(",") if e.strip()}
    videos = discover_videos(video_dir, exts)
    if not videos:
        print(f"AVISO: nenhum video com extensoes {exts} em {video_dir}")
        sys.exit(0)

    state = load_queue_state(video_dir)

    print(f"=== videokit batch queue ===")
    print(f"  Pasta:         {video_dir}")
    print(f"  Encontrados:   {len(videos)} vídeo(s)")
    print(f"  Preset:        {args.preset or '(nenhum)'}")
    print(f"  Modo:          {args.mode}")
    print(f"  Subs:          {args.subs}")
    print(f"  Audio pack:    {'sim' if args.with_audio_pack else 'nao'}")
    print(f"  Skip existing: {args.skip_existing}")
    print()

    if args.dry_run:
        print("DRY RUN — nada será executado:")
        for v in videos:
            job = state["jobs"].get(v.name, {})
            status = job.get("status", "pending")
            print(f"  • {v.name}  ({status})")
        return

    total_t0 = time.time()
    succeeded = 0
    failed = 0
    skipped = 0

    for idx, video in enumerate(videos, start=1):
        print(f"\n[{idx}/{len(videos)}] {video.name}")
        print("=" * 60)

        prev = state["jobs"].get(video.name, {})
        if args.skip_existing and prev.get("status") == "completed":
            final = Path(prev.get("project_dir", "")) / "renders" / "final" / "final.mp4"
            if final.exists():
                print("  SKIP (já completo, --skip-existing)")
                skipped += 1
                continue

        state["jobs"][video.name] = {
            "status": "in_progress",
            "started_at": now_iso(),
        }
        save_queue_state(video_dir, state)

        t0 = time.time()
        try:
            project_dir = run_init_project(video, args.mode, args.subs)
            if not project_dir:
                raise RuntimeError("init-project falhou")
            print(f"  → project: {project_dir}")
            state["jobs"][video.name]["project_dir"] = str(project_dir)

            print("  → transcribe...")
            if not run_transcribe(project_dir, args.language):
                raise RuntimeError("transcribe falhou")

            print("  → auto-cut...")
            if not run_auto_cut(project_dir, args.language):
                raise RuntimeError("auto-cut falhou")

            if args.with_audio_pack:
                print("  → audio pack...")
                if not run_audio_pack(project_dir, args.preset):
                    raise RuntimeError("audio-pack falhou")

            print("  → render final...")
            if not run_render(project_dir, "final"):
                raise RuntimeError("render falhou")

            elapsed = time.time() - t0
            state["jobs"][video.name].update({
                "status": "completed",
                "completed_at": now_iso(),
                "elapsed_s": round(elapsed, 1),
            })
            save_queue_state(video_dir, state)
            succeeded += 1
            print(f"  OK ({elapsed:.0f}s)")

        except Exception as e:
            elapsed = time.time() - t0
            state["jobs"][video.name].update({
                "status": "failed",
                "failed_at": now_iso(),
                "error": str(e),
                "elapsed_s": round(elapsed, 1),
            })
            save_queue_state(video_dir, state)
            failed += 1
            print(f"  FAIL: {e}", file=sys.stderr)
            if not args.continue_on_error:
                print("\nAbortado (use --continue-on-error para saltar para o seguinte).", file=sys.stderr)
                break

    total_elapsed = time.time() - total_t0
    print()
    print("=" * 60)
    print(f"Concluído em {total_elapsed/60:.1f}min")
    print(f"  Sucesso:  {succeeded}")
    print(f"  Falhados: {failed}")
    print(f"  Saltados: {skipped}")
    print(f"  Estado:   {video_dir}/.videokit-queue.json")


if __name__ == "__main__":
    main()
