# Batch processing

Para processar 10 entrevistas seguidas com a mesma config, em vez de invocar a skill 10 vezes manualmente. O `scripts/queue.py` orquestra `init-project → transcribe → auto-cut → render` para cada vídeo numa pasta, com estado persistido para resume.

## Uso típico

```bash
# Processar pasta com vídeos em modo cut-only, sem extras
python scripts/queue.py D:\entrevistas\

# Com preset de plataforma + audio pack + skip já-processados
python scripts/queue.py D:\entrevistas\ --preset reels --with-audio-pack --skip-existing

# Ver o que seria feito sem executar
python scripts/queue.py D:\entrevistas\ --dry-run

# Continuar para o próximo vídeo se um falhar
python scripts/queue.py D:\entrevistas\ --continue-on-error
```

Cross-platform — usa `python` (Windows) ou `python3` (macOS/Linux). Lê o `python_bin` de `env-report.json` se existir.

## Argumentos

| Flag | Default | O que faz |
|---|---|---|
| `<video-dir>` | obrigatório | Pasta com os vídeos. Sub-pastas são ignoradas. |
| `--preset` | nenhum | Plataforma (`youtube`, `reels`, `tiktok`, `podcast-video`, etc.). Aplica LUFS no audio pack. |
| `--subs` | `sem` | `completas`, `karaoke`, `highlights` ou `sem` |
| `--mode` | `cut-only` | `full` (com motion graphics) ou `cut-only` |
| `--language` | `pt` | Whisper language code. Afeta detecção de fillers (`pt`/`en`). |
| `--ext` | `mp4,mov,mkv,webm,m4v` | Extensões a procurar (CSV) |
| `--skip-existing` | off | Salta vídeos com `renders/final/final.mp4` já presente |
| `--dry-run` | off | Mostra o que faria sem executar |
| `--continue-on-error` | off | Não aborta se um vídeo falhar |
| `--with-audio-pack` | off | Aplica denoise+normalize+compress entre cut e render |

## Estado persistente

A queue escreve `<video-dir>/.videokit-queue.json`:

```json
{
  "jobs": {
    "entrevista-01.mp4": {
      "status": "completed",
      "started_at": "2026-06-05T14:23:11Z",
      "completed_at": "2026-06-05T14:35:42Z",
      "elapsed_s": 751.3,
      "project_dir": "D:\\entrevistas\\videokit-projects\\2026-06-05_entrevista-01"
    },
    "entrevista-02.mp4": {
      "status": "failed",
      "started_at": "2026-06-05T14:35:43Z",
      "failed_at": "2026-06-05T14:36:10Z",
      "elapsed_s": 27.0,
      "error": "transcribe falhou"
    }
  }
}
```

Com `--skip-existing`, vídeos com `status=completed` e `final.mp4` no disco são saltados na próxima corrida.

## Padrões de uso

### Lote de podcasts (mesma config para todos)

```bash
python scripts/queue.py D:\podcast-eps\ \
    --preset podcast-video \
    --subs completas \
    --mode cut-only \
    --with-audio-pack \
    --continue-on-error
```

### Versões Reels de uma pasta de entrevistas

```bash
# Primeiro, gera os finals (16:9)
python scripts/queue.py D:\entrevistas\ --mode cut-only

# Depois converte cada um para 9:16 (loop manual — smart-reframe ainda não está integrado na queue)
for /f %f in ('dir /b "D:\entrevistas\videokit-projects\*"') do (
    python scripts/smart-reframe.py ^
        --input "D:\entrevistas\videokit-projects\%f\renders\final\final.mp4" ^
        --output "D:\entrevistas\videokit-projects\%f\renders\final\final_reels.mp4" ^
        --target-aspect 9:16
)
```

### Recovery após crash

```bash
# Primeira corrida — algo a meio falhou
python scripts/queue.py D:\big-pasta\

# Reabre — continua de onde parou
python scripts/queue.py D:\big-pasta\ --skip-existing
```

## Limitações

- **Sequencial** — processa um vídeo de cada vez. Não há `--max-parallel` (não compensa: ffmpeg satura o CPU/GPU sozinho; correr 2 em paralelo torna ambos lentos).
- **Sem motion graphics em batch** — `--mode full` funciona mas todos os vídeos ficam com o mesmo template de title-card / lower-third. Se queres beats diferentes por vídeo, usa o pipeline manual.
- **`smart-reframe` não está integrado** — para gerar versões 9:16 em batch usa loop manual (ver exemplo acima).
- **Sem retry automático** — se o vídeo N falha por causa de OOM/disco, marca como `failed` e segue (ou pára). A próxima corrida retenta esse vídeo.
- **Sem `--max-jobs` ou priority** — todos com a mesma prioridade, ordem alfabética da pasta.

## Quando NÃO usar a queue

- **1 vídeo só** → invoca a skill normalmente, é mais flexível.
- **Configs diferentes por vídeo** (ex.: vídeo A com legendas karaoke, vídeo B sem) → loop manual com scripts individuais.
- **Pipeline custom** (ex.: cada vídeo precisa de B-roll diferente) → batch só prejudica.
