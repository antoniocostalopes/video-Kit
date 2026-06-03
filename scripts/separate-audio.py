#!/usr/bin/env python3
"""
separate-audio.py — Separa voz/musica/baixo/outros via Facebook Demucs.

Util para:
  - Remover musica pre-existente do video (mantem so voz)
  - Isolar voz para karaoke real (gera ficheiro de "vozes apenas")
  - Substituir musica de fundo (separa voz, depois mistura nova musica)

Uso:
  python separate-audio.py --input <video|audio> --output-dir <projeto>/audio/stems/
                           [--model htdemucs_ft] [--two-stems vocals]

Stems gerados:
  vocals.wav, drums.wav, bass.wav, other.wav

Com --two-stems vocals: gera so vocals.wav + no_vocals.wav (mais rapido).

Requer:
  pip install demucs
  pip install torch (CPU ou GPU)

Modelo descarrega ~80MB-2GB na primeira corrida (cached em ~/.cache/torch/hub/).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, type=Path)
    ap.add_argument("--output-dir", required=True, type=Path)
    ap.add_argument("--model", default="htdemucs_ft",
                    help="htdemucs_ft (default, melhor qualidade), htdemucs (mais rapido), mdx_extra_q (alternativa)")
    ap.add_argument("--two-stems", default=None, choices=[None, "vocals", "drums", "bass", "other"],
                    help="Se setado, separa so esse stem + 'no_<stem>'. Mais rapido (~2x).")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda", "mps"],
                    help="cpu (default), cuda (NVIDIA), mps (Apple Silicon)")
    args = ap.parse_args()

    try:
        import torch
        from demucs.api import Separator
        from demucs.apply import apply_model
    except ImportError as e:
        print(f"ERRO: dependencia em falta ({e}).", file=sys.stderr)
        print("Corre: pip install demucs torch", file=sys.stderr)
        sys.exit(2)

    if not args.input.exists():
        print(f"ERRO: input nao existe: {args.input}", file=sys.stderr)
        sys.exit(1)

    args.output_dir.mkdir(parents=True, exist_ok=True)

    # Verifica device disponivel
    if args.device == "cuda" and not torch.cuda.is_available():
        print("AVISO: CUDA pedido mas nao disponivel. A usar CPU.")
        args.device = "cpu"
    if args.device == "mps" and not torch.backends.mps.is_available():
        print("AVISO: MPS pedido mas nao disponivel. A usar CPU.")
        args.device = "cpu"

    print(f"A carregar modelo {args.model} no device {args.device}...")
    print("(primeira corrida descarrega o modelo, pode demorar)")

    try:
        sep = Separator(
            model=args.model,
            device=args.device,
            shifts=1,  # 1 = rapido, 10 = melhor qualidade mas 10x mais lento
            split=True,
            overlap=0.25,
        )
    except Exception as e:
        print(f"ERRO ao carregar modelo: {e}", file=sys.stderr)
        sys.exit(3)

    print(f"A separar {args.input.name} (pode demorar varios minutos)...")

    # API Demucs 4.x: Separator().separate_audio_file()
    origin, separated = sep.separate_audio_file(str(args.input))
    # separated e dict { "vocals": Tensor, "drums": Tensor, ... }

    # two-stems: cria vocals + no_vocals
    if args.two_stems:
        import torch as _torch
        target = args.two_stems
        if target not in separated:
            print(f"ERRO: stem '{target}' nao gerado pelo modelo {args.model}.", file=sys.stderr)
            sys.exit(2)
        target_audio = separated[target]
        no_target_audio = _torch.zeros_like(target_audio)
        for name, audio in separated.items():
            if name != target:
                no_target_audio = no_target_audio + audio
        output_stems = {target: target_audio, f"no_{target}": no_target_audio}
    else:
        output_stems = separated

    # Escrita via torchaudio
    import torchaudio
    sample_rate = sep.samplerate

    for name, audio in output_stems.items():
        out_path = args.output_dir / f"{name}.wav"
        # demucs returns Tensor[2, samples] (stereo)
        torchaudio.save(str(out_path), audio.cpu(), sample_rate)
        size_mb = out_path.stat().st_size / 1024 / 1024
        print(f"  OK {out_path.name} ({size_mb:.1f} MB)")

    print(f"\nStems escritos em {args.output_dir}")
    print("Para remixar com FFmpeg:")
    print("  ffmpeg -i vocals.wav -i nova_musica.mp3 -filter_complex amix=inputs=2:duration=longest output.wav")


if __name__ == "__main__":
    main()
