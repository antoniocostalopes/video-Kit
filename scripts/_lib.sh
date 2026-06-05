#!/usr/bin/env bash
# _lib.sh — helpers partilhados pelos scripts .sh.
#
# Source via:
#   . "$SCRIPT_DIR/_lib.sh"

# read_json <ficheiro> <dotted.key>
#
# Le um campo de um ficheiro JSON. Segmentos numericos sao indices de array.
# Devolve string vazia se o caminho nao existir (sem falhar).
# Robusto a paths Windows-style, espacos, e qualquer caracter especial.
read_json() {
    python3 - "$1" "$2" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        data = json.load(f)
    for k in sys.argv[2].split('.'):
        data = data[int(k)] if k.isdigit() else data[k]
    print('' if data is None else data)
except (FileNotFoundError, KeyError, IndexError, TypeError, json.JSONDecodeError):
    sys.exit(0)
PYEOF
}

# read_json_stdin <dotted.key>
#
# Le JSON do stdin. Para parsing de output de ffprobe sem tempfile.
# Usage: echo "$FFPROBE_JSON" | read_json_stdin streams.0.width
read_json_stdin() {
    python3 - "$1" <<'PYEOF'
import json, sys
try:
    data = json.load(sys.stdin)
    for k in sys.argv[1].split('.'):
        data = data[int(k)] if k.isdigit() else data[k]
    print('' if data is None else data)
except (KeyError, IndexError, TypeError, json.JSONDecodeError):
    sys.exit(0)
PYEOF
}

# require_env_report <env-report-path>
#
# Garante que env-report.json existe. Se nao existir, tenta correr detect-env.sh.
# Aborta com mensagem clara se falhar.
require_env_report() {
    local report="$1"
    if [[ ! -f "$report" ]]; then
        local script_dir
        script_dir="$(dirname "$report")/../scripts"
        if [[ -x "$script_dir/detect-env.sh" ]]; then
            echo "env-report.json nao existe. A correr detect-env.sh..." >&2
            "$script_dir/detect-env.sh"
        fi
        if [[ ! -f "$report" ]]; then
            echo "ERRO: env-report.json em falta em $report. Corre detect-env.sh manualmente." >&2
            exit 1
        fi
    fi
}
