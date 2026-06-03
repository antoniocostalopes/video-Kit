#!/usr/bin/env bash
# download-assets.sh — Descarrega modelos gratuitos necessarios (RNNoise).
# Idempotente: so descarrega o que falta.
#
# Uso: ./download-assets.sh [--what rnnoise|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

WHAT="all"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --what)
            WHAT="$2"
            shift 2
            ;;
        *)
            echo "Aviso: argumento desconhecido $1" >&2
            shift
            ;;
    esac
done

fetch_if_missing() {
    local url="$1"
    local dest="$2"
    local desc="$3"

    if [[ -f "$dest" ]]; then
        echo "OK ja existe: $desc"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    echo "  A descarregar $desc..."

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    else
        echo "ERRO: curl ou wget necessario." >&2
        exit 1
    fi

    local size_kb
    size_kb="$(du -k "$dest" | cut -f1)"
    echo "  OK (${size_kb} KB) -> $dest"
}

if [[ "$WHAT" == "rnnoise" || "$WHAT" == "all" ]]; then
    echo "RNNoise models (denoise para arnndn filter)..."
    fetch_if_missing \
        "https://raw.githubusercontent.com/GregorR/rnnoise-models/master/conjoined-burgers-2018-08-28/cb.rnnn" \
        "$SKILL_DIR/assets/audio-models/cb.rnnn" \
        "RNNoise model cb.rnnn"
fi

echo ""
echo "OK Assets verificados."
