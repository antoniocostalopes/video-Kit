#!/usr/bin/env python3
"""
remove-bg.py — Remove fundo de video frame-a-frame usando rembg (U2Net).

Funciona SEM greenscreen. Detecta orador, isola, e:
  - Modo alpha: gera MOV ProRes com alpha para compositing
  - Modo replace: substitui fundo por imagem ou cor solida
  - Modo blur: aplica blur gaussiano no fundo (efeito virtual webcam)

Uso:
  python remove-bg.py --input video.mp4 --output out.mp4 --mode blur --blur-strength 25
  python remove-bg.py --input video.mp4 --output out.mp4 --mode replace --bg-image bg.jpg
  python remove-bg.py --input video.mp4 --output out.mov --mode alpha

Requer:
  pip install rembg opencv-python pillow
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--mode", required=True, choices=["alpha", "replace", "blur"])
    ap.add_argument("--bg-image", type=Path, help="Imagem de fundo (mode replace)")
    ap.add_argument("--bg-color", default="#000000", help="Cor de fundo hex (mode replace, fallback)")
    ap.add_argument("--blur-strength", type=int, default=25, help="Forca do blur (mode blur), 1-99")
    ap.add_argument("--model", default="u2net", choices=["u2net", "u2netp", "u2net_human_seg", "silueta"],
                    help="u2net (default, melhor), u2netp (rapido), u2net_human_seg (pessoas), silueta (alternativa)")
    ap.add_argument("--sample-rate", type=int, default=1,
                    help="Processar 1 em cada N frames. Default 1 (todos). Higher = faster but lower quality.")
    args = ap.parse_args()

    try:
        import cv2
        import numpy as np
        from rembg import remove, new_session
    except ImportError as e:
        print(f"ERRO: dependencia em falta ({e}).", file=sys.stderr)
        print("Corre: pip install rembg opencv-python pillow", file=sys.stderr)
        sys.exit(2)

    if not args.input.exists():
        print(f"ERRO: input nao existe: {args.input}", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)

    skill_dir = Path(__file__).resolve().parent.parent
    env = json.loads((skill_dir / "cache" / "env-report.json").read_text(encoding="utf-8"))
    ffmpeg_bin = env.get("ffmpeg_bin") or "ffmpeg"

    # Background image preprocess
    bg_image_np = None
    if args.mode == "replace" and args.bg_image:
        if not args.bg_image.exists():
            print(f"ERRO: bg-image nao existe: {args.bg_image}", file=sys.stderr)
            sys.exit(1)
        bg_image_np = cv2.imread(str(args.bg_image))

    bg_color_bgr = None
    if args.mode == "replace":
        # Parse #RRGGBB
        h = args.bg_color.lstrip("#")
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        bg_color_bgr = (b, g, r)

    # Open input
    cap = cv2.VideoCapture(str(args.input))
    if not cap.isOpened():
        print(f"ERRO: nao consegui abrir {args.input}", file=sys.stderr)
        sys.exit(1)

    src_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    src_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    print(f"Source: {src_w}x{src_h} @ {fps:.2f}fps ({total} frames)")
    print(f"Mode: {args.mode}, model: {args.model}")

    # Initialize rembg session
    print(f"A carregar modelo rembg '{args.model}' (descarrega ~170MB na primeira corrida)...")
    session = new_session(args.model)

    # Pre-process bg_image to match dims
    if bg_image_np is not None:
        bg_image_np = cv2.resize(bg_image_np, (src_w, src_h))

    # Determine pixel format do output
    if args.mode == "alpha":
        # Pipe to ffmpeg with prores 4444 (alpha)
        pix_fmt_in = "bgra"
        codec_args = ["-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le"]
    else:
        pix_fmt_in = "bgr24"
        codec_args = ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p"]

    cmd = [
        ffmpeg_bin, "-y",
        "-f", "rawvideo", "-vcodec", "rawvideo",
        "-pix_fmt", pix_fmt_in,
        "-s", f"{src_w}x{src_h}",
        "-r", f"{fps:.6f}",
        "-i", "-",
        "-i", str(args.input),
        "-map", "0:v",
        "-map", "1:a?",
    ] + codec_args + [
        "-c:a", "aac", "-b:a", "192k",
        "-shortest",
        str(args.output),
    ]

    import tempfile
    err_file = tempfile.NamedTemporaryFile(delete=False, suffix=".log")
    err_file.close()
    err_handle = open(err_file.name, "wb")

    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=err_handle)

    last_mask = None
    idx = 0
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            # Process mask em 1 em cada sample_rate frames; entre, reusa o ultimo
            if idx % args.sample_rate == 0 or last_mask is None:
                rgba = remove(frame, session=session, post_process_mask=True)  # returns RGBA
                last_mask = rgba

            rgba = last_mask
            # rgba e RGBA (4 canais). Em opencv ordem BGRA.
            mask = rgba[:, :, 3] / 255.0  # alpha as 0..1
            mask3 = np.stack([mask, mask, mask], axis=-1)

            if args.mode == "alpha":
                # Write BGRA direto
                out_frame = np.concatenate([frame, (mask * 255).astype(np.uint8)[:, :, None]], axis=-1)
            elif args.mode == "replace":
                bg = bg_image_np if bg_image_np is not None else np.full_like(frame, bg_color_bgr, dtype=np.uint8)
                out_frame = (frame * mask3 + bg * (1 - mask3)).astype(np.uint8)
            elif args.mode == "blur":
                # Aplica gaussian blur ao frame original como fundo
                k = max(1, args.blur_strength) | 1  # garante ímpar
                blurred = cv2.GaussianBlur(frame, (k, k), 0)
                out_frame = (frame * mask3 + blurred * (1 - mask3)).astype(np.uint8)
            else:
                raise ValueError(args.mode)

            try:
                ff.stdin.write(out_frame.tobytes())
            except BrokenPipeError:
                err_handle.close()
                with open(err_file.name) as f:
                    print("ffmpeg broke pipe:", f.read()[-500:], file=sys.stderr)
                sys.exit(3)
            idx += 1
            if idx % 50 == 0:
                print(f"  {idx}/{total}", flush=True)

    finally:
        cap.release()
        try: ff.stdin.close()
        except Exception: pass
        ff.wait()
        err_handle.close()

    if ff.returncode != 0:
        with open(err_file.name) as f:
            print("ffmpeg exit non-zero:", f.read()[-1000:], file=sys.stderr)
        sys.exit(3)

    size_mb = args.output.stat().st_size / (1024 * 1024)
    print(f"OK output: {args.output} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    main()
