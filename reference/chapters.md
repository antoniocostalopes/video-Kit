# Chapters automáticos

Para vídeos longos (>10 min) — podcasts, tutoriais, conferences — chapters poupam ao espectador ter de adivinhar onde está o conteúdo que lhe interessa. YouTube, Apple Podcasts e Spotify mostram-nos nativamente, e o YouTube acrescenta-os à timeline.

A skill gera chapters automaticamente a partir do transcript (pausas longas → boundaries; primeiras palavras da frase seguinte → título).

## Quando usar

Trigger natural do utilizador:
- `"gera chapters para este podcast"`
- `"divide em capítulos"`
- `"timestamps para a descrição YouTube"`

Aplica **depois** de:
- `transcribe.py` (precisa de `clean.json` com word timestamps), e
- opcionalmente `auto-cut.py` (para timestamps já no `final.mp4` em vez do source).

## Como correr

```powershell
# Chapters a partir do source (timestamps batem com renders/edited.mp4 só se mode=cut-only)
python scripts/auto-chapters.py <projeto>

# Chapters ajustados ao final.mp4 (compensa cortes)
python scripts/auto-chapters.py <projeto> --from-final

# Tuning fino
python scripts/auto-chapters.py <projeto> --min-pause 2.0 --min-chapter-duration 60 --max-title-words 6 --language pt
```

## Outputs

Tudo escrito em `<projeto>/edit/`:

| Ficheiro | Para quê |
|---|---|
| `chapters.json` | Formato canónico videokit — referência interna + iteração |
| `chapters.ffmetadata` | Embed no MP4: `ffmpeg -i in.mp4 -i chapters.ffmetadata -map_metadata 1 -c copy out.mp4` |
| `chapters.youtube.txt` | Copy/paste na descrição do YouTube (`00:00 Intro\n01:34 Tema X\n...`) |
| `chapters.podcast.txt` | Copy/paste em Apple Podcasts / Spotify shownotes (`HH:MM:SS - Título`) |

### Embed no MP4 final

Depois de gerar chapters e ter `renders/final/final.mp4`:

```bash
ffmpeg -i renders/final/final.mp4 \
       -i edit/chapters.ffmetadata \
       -map_chapters 1 -c copy \
       renders/final/final_with_chapters.mp4
```

QuickTime, VLC, mpv e YouTube reconhecem chapters embebidos.

## Parâmetros importantes

### `--min-pause` (default 1.5)
Silêncios mais curtos não viram boundary. Para podcasts naturais (mais pausas), sobe para `2.0`. Para conteúdo rápido (Shorts, vlogs), `1.0`.

### `--min-chapter-duration` (default 30)
Impede chapters de 5s consecutivos só porque o orador respirou fundo. Para vídeos de >1h aumenta para `120` (chapter cada 2min mínimo).

### `--max-title-words` (default 8)
Mais palavras = títulos mais informativos mas piores na timeline. YouTube corta visualmente após ~30 chars.

### `--from-final`
**Recomendado** quando aplicas a um vídeo editado. Sem este flag, os timestamps batem com o source — não com o `final.mp4` que já tem cortes. Com `--from-final`, a skill lê `edit/edl.json` e mapeia `t_source → t_final` (segmentos cortados deixam de contar).

Sem `auto-cut.py` prévio, não há `edl.json` → este flag dá erro. Usa sem o flag.

### `--language pt | en`
Só afeta labels default (`Introdução` vs `Intro`). Não afeta os títulos extraídos (esses vêm do transcript, na língua original).

## Heurística por trás dos títulos

1. Procura todas as pausas > `--min-pause` no `clean.json`.
2. Filtra para garantir ≥ `--min-chapter-duration` entre chapters consecutivos.
3. Para cada chapter, junta as primeiras palavras a partir do `start`, até `--max-title-words` ou pontuação forte (`.`, `!`, `?`).
4. O primeiro chapter (start ~0) vira "Introdução"/"Intro".

Esta heurística produz títulos **literais** — repete as palavras do orador. Para títulos curados (ex.: "O problema com o React 19"), passa-os por LLM depois, ou edita manualmente o `chapters.json` e regenera os outros 3 formatos:

```python
# Re-gerar formatos a partir de chapters.json editado:
python -c "
import json, sys
sys.path.insert(0, 'scripts')
from auto_chapters import write_ffmetadata, write_youtube_format, write_podcast_format
from pathlib import Path
data = json.load(open('<projeto>/edit/chapters.json', encoding='utf-8'))
ed = Path('<projeto>/edit')
write_ffmetadata(data['chapters'], ed/'chapters.ffmetadata')
write_youtube_format(data['chapters'], ed/'chapters.youtube.txt')
write_podcast_format(data['chapters'], ed/'chapters.podcast.txt')
"
```

## Limitações

- **Sem deteção de tópico semântico** — só usa pausas. Vídeos com pouca pausa (apresentações lidas) podem ter chapters mal posicionados. Tuning: aumenta `--min-pause` para 2.5.
- **Heurística língua-agnóstica** — funciona em PT, EN, ES, mas pontuação em árabe/chinês precisa de ajustes (não testado).
- **Não deteta scene cuts visuais** — só áudio. Para vídeos com B-roll silencioso entre falas, considera `scenedetect` (não incluído, pode ser feature futura).
- **`chapters.youtube.txt` exige primeiro chapter em 00:00** — YouTube não aceita primeiro chapter ≠ 0. A skill já força isso, mas confirma se editares manualmente.
