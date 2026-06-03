#!/usr/bin/env python3
r"""
smart-reframe.py — Reframe 16:9 -> 9:16 (ou 1:1, 4:5) com tracking de cara via MediaPipe.

Estrategia:
  1. Deteta cara em cada Nth frame (mais rapido)
  2. Suaviza posicoes com moving average
  3. Decode -> crop -> resize -> pipe para ffmpeg encode

Requer:
  pip install mediapipe opencv-python numpy

Uso:
  python smart-reframe.py --input C:\v\src.mp4 --output C:\v\reels.mp4
  python smart-reframe.py --input X --output Y --target-aspect 1:1
  python smart-reframe.py --input X --output Y --sample-rate 3 --smooth-window 21
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def smooth_positions(positions, window: int = 15):
    """Moving average symetrico. Lida com bordas reduzindo a janela."""
    if not positions:
        return positions
    half = window // 2
    out = []
    for i in range(len(positions)):
        lo = max(0, i - half)
        hi = min(len(positions), i + half + 1)
        out.append(sum(positions[lo:hi]) / (hi - lo))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="Video source")
    ap.add_argument("--output", required=True, help="Video output")
    ap.add_argument("--target-aspect", default="9:16", choices=["9:16", "1:1", "4:5"])
    ap.add_argument("--sample-rate", type=int, default=5,
                    help="Detetar cara a cada N frames (5 = ~6Hz num video 30fps)")
    ap.add_argument("--smooth-window", type=int, default=15,
                    help="Janela do moving average para suavizar tracking")
    ap.add_argument("--vertical-offset", type=float, default=0.0,
                    help="Desloca crop verticalmente (-1.0 = topo, 0 = centro, 1.0 = fundo)")
    args = ap.parse_args()

    try:
        import cv2
        import mediapipe as mp
        from mediapipe.tasks import python as mp_python
        from mediapipe.tasks.python import vision as mp_vision
    except ImportError as e:
        print(f"ERRO: dependencia em falta ({e}).", file=sys.stderr)
        print("Corre: pip install mediapipe opencv-python", file=sys.stderr)
        sys.exit(2)

    inp = Path(args.input).resolve()
    out = Path(args.output).resolve()
    if not inp.exists():
        print(f"ERRO: input nao existe: {inp}", file=sys.stderr)
        sys.exit(1)
    out.parent.mkdir(parents=True, exist_ok=True)

    # ffmpeg do env-report
    skill_dir = Path(__file__).resolve().parent.parent
    env_path = skill_dir / "cache" / "env-report.json"
    if not env_path.exists():
        print("ERRO: env-report.json nao existe. Corre detect-env.ps1 primeiro.", file=sys.stderr)
        sys.exit(1)
    env = json.loads(env_path.read_text(encoding="utf-8"))
    ffmpeg_bin = env.get("ffmpeg_bin") or "ffmpeg"

    # --- Pass 0: metadata ---
    cap = cv2.VideoCapture(str(inp))
    if not cap.isOpened():
        print(f"ERRO: nao consegui abrir {inp}", file=sys.stderr)
        sys.exit(1)
    src_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    src_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    print(f"Source: {src_w}x{src_h} @ {fps:.2f}fps ({total} frames)")

    # --- Calcular crop window ---
    aspect_map = {"9:16": (9, 16), "1:1": (1, 1), "4:5": (4, 5)}
    aw, ah = aspect_map[args.target_aspect]

    if src_w / src_h > aw / ah:
        # source mais largo que target -> recorta largura
        crop_h = src_h
        crop_w = int(round(crop_h * aw / ah))
    else:
        crop_w = src_w
        crop_h = int(round(crop_w * ah / aw))

    # Y fixo (sem tracking vertical neste MVP), com offset opcional
    base_y = (src_h - crop_h) // 2
    crop_y = max(0, min(src_h - crop_h, base_y + int(args.vertical_offset * crop_h / 4)))

    output_sizes = {"9:16": (1080, 1920), "1:1": (1080, 1080), "4:5": (1080, 1350)}
    out_w, out_h = output_sizes[args.target_aspect]

    print(f"Crop window: {crop_w}x{crop_h} a partir de (variavel, {crop_y})")
    print(f"Output: {out_w}x{out_h}")

    # --- Pass 1: detetar caras ---
    # Carregar modelo BlazeFace (descarregar se necessario)
    model_path = skill_dir / "assets" / "face-detector" / "blaze_face_short_range.tflite"
    if not model_path.exists():
        print("Modelo de cara nao encontrado. A descarregar BlazeFace...")
        model_path.parent.mkdir(parents=True, exist_ok=True)
        import urllib.request
        url = "https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/latest/blaze_face_short_range.tflite"
        try:
            urllib.request.urlretrieve(url, str(model_path))
            print(f"  OK ({model_path.stat().st_size / 1024:.1f} KB)")
        except Exception as e:
            print(f"ERRO ao descarregar modelo: {e}", file=sys.stderr)
            sys.exit(2)

    base_opts = mp_python.BaseOptions(model_asset_path=str(model_path))
    fd_opts = mp_vision.FaceDetectorOptions(base_options=base_opts, min_detection_confidence=0.5)
    detector = mp_vision.FaceDetector.create_from_options(fd_opts)

    print("Pass 1: detetando caras...")
    face_centers_x = []
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
    last_x = src_w / 2.0
    idx = 0
    detections_count = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if idx % args.sample_rate == 0:
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = detector.detect(mp_image)
            if result.detections:
                # bounding_box em pixels do source
                best = max(result.detections, key=lambda d: d.categories[0].score if d.categories else 0)
                bb = best.bounding_box
                last_x = bb.origin_x + bb.width / 2.0
                detections_count += 1
        face_centers_x.append(last_x)
        idx += 1
        if idx % 300 == 0:
            print(f"  {idx}/{total}", flush=True)

    cap.release()
    detector.close()
    print(f"  detecoes confirmadas: {detections_count}/{idx // args.sample_rate}")

    if detections_count == 0:
        print("AVISO: nenhuma cara detetada. Usando crop centrado.")

    # Suaviza
    smoothed = smooth_positions(face_centers_x, window=args.smooth_window)
    half_crop = crop_w / 2.0
    crop_xs = []
    for cx in smoothed:
        x = int(round(cx - half_crop))
        x = max(0, min(src_w - crop_w, x))
        crop_xs.append(x)

    # --- Pass 2: render via ffmpeg pipe ---
    print("Pass 2: encoding...", flush=True)

    import tempfile
    err_file = tempfile.NamedTemporaryFile(delete=False, suffix=".log")
    err_file.close()
    err_handle = open(err_file.name, "wb")

    cmd = [
        ffmpeg_bin, "-y",
        "-f", "rawvideo", "-vcodec", "rawvideo",
        "-pix_fmt", "bgr24",
        "-s", f"{out_w}x{out_h}",
        "-r", f"{fps:.6f}",
        "-i", "-",
        "-i", str(inp),
        "-map", "0:v",
        "-map", "1:a?",
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "20",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "192k",
        "-shortest",
        "-movflags", "+faststart",
        str(out),
    ]

    # stderr para ficheiro evita deadlock de buffer cheio.
    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=err_handle)

    cap = cv2.VideoCapture(str(inp))
    idx = 0
    broken = False
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            cx = crop_xs[idx] if idx < len(crop_xs) else crop_xs[-1]
            cropped = frame[crop_y:crop_y + crop_h, cx:cx + crop_w]
            resized = cv2.resize(cropped, (out_w, out_h), interpolation=cv2.INTER_LANCZOS4)
            try:
                ff.stdin.write(resized.tobytes())
            except BrokenPipeError:
                broken = True
                break
            idx += 1
            if idx % 300 == 0:
                print(f"  {idx}/{total}", flush=True)
    finally:
        cap.release()
        try:
            ff.stdin.close()
        except Exception:
            pass
        ff.wait()
        err_handle.close()

    if ff.returncode != 0 or broken:
        with open(err_file.name, "rb") as f:
            err = f.read().decode("utf-8", errors="replace")
        print(f"ffmpeg exit {ff.returncode}: {err[-2000:]}", file=sys.stderr)
        Path(err_file.name).unlink(missing_ok=True)
        sys.exit(3)
    Path(err_file.name).unlink(missing_ok=True)

    size_mb = out.stat().st_size / (1024 * 1024)
    print(f"OK reframe escrito em {out} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    main()
