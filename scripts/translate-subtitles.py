#!/usr/bin/env python3
"""
translate-subtitles.py — Traduz legendas ASS/SRT entre linguas usando argostranslate
(local, offline, sem API key).

Suporta translation packages para PT/EN/ES/FR/IT/DE etc. Modelos descarregados na
primeira utilizacao (~100MB cada par de linguas).

Uso:
  python translate-subtitles.py --input <file.ass> --output <file.ass>
                                --from pt --to en
                                [--format ass|srt]

Requer:
  pip install argostranslate
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def ensure_argos_package(from_lang: str, to_lang: str):
    """Descarrega o pacote de traducao se nao estiver instalado."""
    try:
        import argostranslate.package
        import argostranslate.translate
    except ImportError:
        print("ERRO: argostranslate nao instalado. Corre: pip install argostranslate", file=sys.stderr)
        sys.exit(2)

    installed = argostranslate.translate.get_installed_languages()
    has = any(
        l.code == from_lang and any(t.to_lang.code == to_lang for t in l.translations_from)
        for l in installed
    )
    if has:
        return

    print(f"A descarregar pacote {from_lang} -> {to_lang} (pode demorar 1-3min)...")
    argostranslate.package.update_package_index()
    available = argostranslate.package.get_available_packages()
    matches = [p for p in available if p.from_code == from_lang and p.to_code == to_lang]
    if not matches:
        print(f"ERRO: nenhum pacote {from_lang}->{to_lang} disponivel.", file=sys.stderr)
        print("Pacotes disponiveis: pt, en, es, fr, it, de, ru, ar, zh, ja, etc.", file=sys.stderr)
        sys.exit(2)
    pkg = matches[0]
    pkg_path = pkg.download()
    argostranslate.package.install_from_path(pkg_path)
    print(f"  OK pacote {from_lang}->{to_lang} instalado")


def translate_text(text: str, from_lang: str, to_lang: str) -> str:
    """Translation com argos. Fallback retorna texto original se falhar."""
    if not text.strip():
        return text
    try:
        import argostranslate.translate
        return argostranslate.translate.translate(text, from_lang, to_lang)
    except Exception as e:
        print(f"AVISO falha a traduzir '{text[:40]}': {e}", file=sys.stderr)
        return text


# ---------------- ASS parser/translator ----------------

ASS_DIALOGUE_RE = re.compile(r"^(Dialogue:\s*\d+,[^,]+,[^,]+,[^,]+,[^,]*,\d+,\d+,\d+,[^,]*,)(.*)$")
ASS_OVERRIDE_RE = re.compile(r"\{[^}]*\}")


def translate_ass(text: str, from_lang: str, to_lang: str) -> str:
    """Traduz so o texto visivel de cada Dialogue (preserva overrides {\\...} e \\N)."""
    out_lines = []
    for line in text.splitlines():
        m = ASS_DIALOGUE_RE.match(line)
        if not m:
            out_lines.append(line)
            continue
        prefix, dialogue_text = m.group(1), m.group(2)

        # Extrai overrides e mantém posicoes
        # Estrategia: split por overrides, traduz so partes textuais, recompoe
        parts = []
        last = 0
        for ov in ASS_OVERRIDE_RE.finditer(dialogue_text):
            if ov.start() > last:
                parts.append(("text", dialogue_text[last:ov.start()]))
            parts.append(("override", ov.group()))
            last = ov.end()
        if last < len(dialogue_text):
            parts.append(("text", dialogue_text[last:]))

        out_parts = []
        for kind, content in parts:
            if kind == "text":
                # \N e nova linha em ASS — preserva
                sub_parts = content.split(r"\N")
                translated_subs = [translate_text(sp, from_lang, to_lang) for sp in sub_parts]
                out_parts.append(r"\N".join(translated_subs))
            else:
                out_parts.append(content)

        out_lines.append(prefix + "".join(out_parts))
    return "\n".join(out_lines) + ("\n" if text.endswith("\n") else "")


# ---------------- SRT parser/translator ----------------

SRT_TIME_RE = re.compile(r"^\d{2}:\d{2}:\d{2}[,.]\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}[,.]\d{3}.*$")


def translate_srt(text: str, from_lang: str, to_lang: str) -> str:
    """Traduz blocos SRT."""
    blocks = re.split(r"\n\s*\n", text.strip())
    out_blocks = []
    for block in blocks:
        lines = block.splitlines()
        if len(lines) < 3:
            out_blocks.append(block)
            continue
        # Primeira linha: indice numerico
        # Segunda linha: timing
        # Restantes: texto
        idx_line = lines[0]
        timing_line = lines[1] if SRT_TIME_RE.match(lines[1]) else None
        if not timing_line:
            out_blocks.append(block)
            continue
        text_lines = lines[2:]
        translated = [translate_text(tl, from_lang, to_lang) for tl in text_lines]
        out_blocks.append(idx_line + "\n" + timing_line + "\n" + "\n".join(translated))
    return "\n\n".join(out_blocks) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--from", dest="from_lang", required=True, help="codigo lingua source (pt, en, es, fr, ...)")
    ap.add_argument("--to", dest="to_lang", required=True, help="codigo lingua target")
    ap.add_argument("--format", choices=["ass", "srt", "auto"], default="auto")
    args = ap.parse_args()

    if not args.input.exists():
        print(f"ERRO: input nao existe: {args.input}", file=sys.stderr)
        sys.exit(1)

    fmt = args.format
    if fmt == "auto":
        ext = args.input.suffix.lower()
        if ext == ".ass":
            fmt = "ass"
        elif ext == ".srt":
            fmt = "srt"
        else:
            print(f"ERRO: nao consigo detetar formato. Usa --format ass|srt.", file=sys.stderr)
            sys.exit(2)

    ensure_argos_package(args.from_lang, args.to_lang)

    text = args.input.read_text(encoding="utf-8")
    print(f"Traduzindo {fmt.upper()} {args.from_lang} -> {args.to_lang}...")

    if fmt == "ass":
        out = translate_ass(text, args.from_lang, args.to_lang)
    else:
        out = translate_srt(text, args.from_lang, args.to_lang)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(out, encoding="utf-8")
    print(f"OK escrito em {args.output}")


if __name__ == "__main__":
    main()
