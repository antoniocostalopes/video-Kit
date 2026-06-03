# Contribuir para o videokit

Obrigado pelo interesse. Este documento explica como contribuir de forma que o PR seja aceite rapidamente.

## O que aceitamos

| Tipo | Bem-vindo? | Notas |
|---|---|---|
| Bug fixes (FFmpeg/PowerShell/Whisper gotchas) | ✅ sim | Documenta em `reference/lessons-learned.md` |
| Bash equivalents de scripts PowerShell em falta | ✅ sim | Paridade total com `.ps1` |
| Novos LUTs procedurais | ✅ sim | Adiciona em `scripts/gen-luts.py` |
| Novos templates ASS / HTML | ✅ sim | Em `assets/subtitle-templates/` ou `assets/beat-templates/` |
| Performance optimizations | ✅ sim | Inclui benchmark antes/depois no PR |
| Suporte a línguas adicionais para fillers | ✅ sim | Em `scripts/auto-cut.py` |
| Refactorings sem mudança funcional | ⚠️ depende | Discute em issue primeiro |
| Breaking changes em `project.json` schema | ⚠️ depende | Requer migration path |
| Reescritas grandes (architectural) | ❌ provavelmente não | Abre issue para discutir |
| Cosmetics no README/docs | ✅ sim | Pequenos PRs OK |

## Antes de abrir PR

1. **Confirma que existe issue** ou abre uma a descrever o problema/feature
2. **Lê** `reference/lessons-learned.md` — muitas armadilhas FFmpeg/PowerShell/Whisper já estão documentadas
3. **Testa em ambiente real** — não basta `python -m py_compile`, corre o script com um vídeo real

## Estilo de código

### PowerShell

- `#Requires -Version 5.1` no topo (compatibilidade Windows 10+)
- UTF-8 sem BOM em todos os ficheiros (não `Set-Content -Encoding utf8` — usar `[IO.File]::WriteAllText`)
- Sem operadores PS7+ (`??`, `?.`, `?:`) — funciona em PS 5.1
- Parsing de floats com `CultureInfo.InvariantCulture` (locale PT/ES usa vírgula)
- stderr de exes nativos via `Start-Process -RedirectStandardError` (não `2>&1` direto)
- Variáveis claras, não `$args` (reservado)

### Python

- Python 3.12+ syntax
- Type hints sempre que possível
- `print(..., flush=True)` em loops longos
- `subprocess` com stderr para tempfile, não PIPE (evitar deadlocks)
- `Path` (pathlib), não strings para paths
- `warnings.filterwarnings('ignore', category=UserWarning)` para silenciar Whisper/MediaPipe

### Bash (.sh)

- `#!/usr/bin/env bash` shebang
- `set -euo pipefail` para fail-fast
- Comentários em PT (consistente com PS scripts)
- Funções > 10 linhas devem ter docstring `# Descrição` no topo
- Paths absolutos com `realpath`/`readlink -f`

## Lessons-learned format

Quando apanhas um bug não-óbvio (especialmente FFmpeg/PowerShell/Whisper), documenta em `reference/lessons-learned.md` com:

```markdown
### Nome do problema

**Sintoma:** o que viste
**Causa raiz:** porquê
**Workaround:** comando ou flag exata
**Referência:** issue link, documento, commit
```

Bug reports sem reprodução clara são fechados.

## Schema changes

`project.json` e `beats_plan.json` têm consumidores em vários scripts. Se adicionares campo:
- Default sensato quando ausente (compatibilidade retroativa)
- Documenta em `reference/pipeline.md` na fase relevante
- Update `init-project.ps1` para inicializar com o default

## Testing

Não há tests automáticos ainda (issue aberta para `pytest` + `Pester`). Por agora, valida manualmente:

```powershell
# Sintaxe PowerShell
Get-ChildItem scripts/*.ps1 | ForEach-Object {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) | Out-Null
    if ($errors.Count -eq 0) { "OK $($_.Name)" } else { "FAIL" }
}

# Sintaxe Python
python -m py_compile scripts/*.py

# Smoke test (precisa de FFmpeg + vídeo de teste)
scripts/detect-env.ps1
```

## Pull request checklist

- [ ] Branch a partir de `main` atualizado
- [ ] 1 commit por PR (squash antes se houver vários)
- [ ] Commit message no imperativo (`Add bash detect-env`, não `Added` ou `Adds`)
- [ ] CHANGELOG.md atualizado em `## [Unreleased]`
- [ ] Sintaxe validada (PSScriptAnalyzer / py_compile)
- [ ] Smoke test em vídeo real (se mudaste lógica de pipeline)
- [ ] Sem segredos ou paths absolutos pessoais no código

## Code of conduct

Não há código formal. Espera-se discussão técnica, respeito, e foco em soluções.

## Licensing

Este repositório não tem licença pública declarada (ver `## Autoria` no README). Quando submeteres um PR, estás a conceder ao autor (Antonio Costa Lopes) direitos perpétuos, irrevogáveis e não-exclusivos para usar a tua contribuição como parte do videokit, inclusive em distribuições proprietárias futuras.
