# Pipeline do videokit

Seis fases, da entrada à entrega. Cada fase atualiza `project.json` ao fechar.

## 0. Entrada e pasta única

1. Utilizador invoca a skill com o caminho absoluto do vídeo (ex.: `edita este vídeo C:\Downloads\meu.mp4`). Se o caminho não for dado, pede.
2. Executa `scripts/init-project.ps1 -InputVideo <abs-path>` que:
   - Gera slug ASCII a partir do nome
   - Cria `<dir-do-source>/videokit-projects/YYYY-MM-DD_slug/` com subpastas (ou `<OutputDir>/YYYY-MM-DD_slug/` se utilizador passou `-OutputDir`)
   - Copia source (não move) para `source/`
   - Deteta `width`, `height`, `fps`, `duration_s`, `rotation`, `aspect_ratio` com `ffprobe`
   - Escreve `project.json` inicial (incluindo `skill_dir` para os scripts Python encontrarem o env-report)
   - Devolve no stdout o `project_dir` absoluto — guarda esse path para todas as fases seguintes
3. Lê `reference/formats.md` para o aspect ratio detetado e carrega zonas seguras.
4. Pergunta **uma única vez** ao utilizador:
   - Estilo de legendas: `completas | karaoke | highlights | sem`
   - Modo: `full` (com motion graphics) ou `cut-only`
   - Termos técnicos ou contexto importante
5. Se utilizador disser "só corte", "sem animações", "limpa só os ahn": `project.json.settings.mode = "cut-only"` e ignora fase 3.

## 1. Transcrição

Todas as paths nesta fase são relativas ao `<project_dir>` devolvido pela fase 0.

1. Lê `<project_dir>/project.json.media` para resolução e fps.
2. Extrai áudio com FFmpeg:
   ```
   ffmpeg -ss 0 -i <project_dir>/source/<video> -map 0:a:0 -vn -c:a pcm_s16le -ar 16000 -ac 1 <project_dir>/cache/audio.wav
   ```
   Em `.MOV` multi-stream, `-ss` antes de `-i` é crítico.
3. Decide transcritor:
   - Default: **Whisper local** com `python scripts/transcribe.py --provider local --model medium --lang <pt|en|auto>`
   - Se `client-style.md` preferir `openai` ou `elevenlabs` e a key existir em `.env`, usa essa.
4. Em Windows, define `PYTHONIOENCODING=utf-8` antes de invocar o script.
5. Outputs:
   - `transcripts/raw.json` — saída crua do modelo (segments + word timestamps quando disponível)
   - `transcripts/clean.json` — formato canónico:
     ```json
     {
       "language": "pt",
       "duration_s": 423.5,
       "segments": [
         { "id": 0, "start": 0.0, "end": 4.2, "text": "Olá pessoal, hoje vamos falar..." }
       ],
       "words": [
         { "start": 0.12, "end": 0.34, "text": "Olá" }
       ]
     }
     ```
6. Regista provider, tempo e custo estimado em `project.json.transcript`.

## 2. Corte automático

1. Executa `python scripts/auto-cut.py <project-dir> --fillers-pt --min-silence 0.5`.
2. O script analisa `transcripts/clean.json` e marca para remover:
   - **Silêncios** > `min_silence` (default 0.5s) entre palavras
   - **Fillers PT**: `ahn`, `ah`, `hum`, `tipo`, `tipo assim`, `né`, `então`, `digamos`, `é`, `pronto` (configurável)
   - **Fillers EN** (se `language=en`): `um`, `uh`, `you know`, `like`, `actually`, `basically`, `so`
   - **Retakes**: detecta frase começada e abortada (palavras iniciais repetidas em <2s)
3. Gera `edit/edl.json`:
   ```json
   {
     "source": "source/raw.mp4",
     "segments_keep": [
       { "start": 0.0, "end": 12.4, "reason": "intro" },
       { "start": 13.1, "end": 28.6, "reason": "main-1" }
     ],
     "cuts_removed": [
       { "start": 12.4, "end": 13.1, "type": "silence" }
     ]
   }
   ```
4. Corta cada segmento. Em FFmpeg 8.x para cortes precisos:
   ```
   ffmpeg -ss <start> -to <end> -i <source> -c:v copy -c:a aac -b:a 192k -avoid_negative_ts make_zero edit/segments/seg_NN.mp4
   ```
   - **Áudio sempre recodificado** (`-c:a aac -b:a 192k`). Nunca `-c copy` sozinho.
   - Em `.MOV` iPhone, `-ss`/`-to` antes de `-i`, e `-map 0:a:0`.
   - Se há rotação 90/270, recodifica vídeo: `-c:v libx264 -preset fast -crf 18`.
5. Valida cada segmento com `silencedetect`:
   ```
   ffmpeg -i edit/segments/seg_NN.mp4 -af silencedetect=n=-30dB:d=2 -f null -
   ```
   Se aparecer silêncio > 2s inesperado, regista em `notes.md` e considera reaproveitar.
6. Concatena com lista:
   ```
   ffmpeg -f concat -safe 0 -i edit/concat.txt -c copy renders/edited.mp4
   ```
   (Concat pode usar `-c copy` porque todos os segmentos têm mesmo codec depois do passo 4.)
7. Valida duração e canais áudio do `renders/edited.mp4`.
8. Se `mode = "cut-only"`: salta para fase 4.

## 3. Plano de motion graphics (modo full)

1. Lê `styles/client-style.md`, `reference/formats.md` para o aspect ratio, e `reference/subtitle-styles.md`.
2. Identifica perfil do vídeo pelos primeiros 15s do `clean.json`:
   - Talking head → cards laterais (se 16:9), title cards no início, lower thirds para nome
   - Reels (9:16) → highlights grandes, sem lower thirds, foco em texto centrado
   - Screencast → zoom em momentos de demo, anotações setas, sem cards laterais
   - YouTube longo → title cards, B-roll suggestions opcionais em `notes.md`
3. Gera `beats_plan.json`:
   ```json
   {
     "video": { "w": 1920, "h": 1080, "fps": 30 },
     "beats": [
       {
         "id": "b01",
         "type": "title-card",
         "start": 0.0,
         "duration": 2.5,
         "text": { "title": "Como triplicar leads", "subtitle": "Caso real" },
         "template": "title-card.html",
         "video_effect": null
       },
       {
         "id": "b02",
         "type": "lower-third",
         "start": 6.3,
         "duration": 4.0,
         "text": { "name": "Maria Silva", "role": "CMO" },
         "template": "lower-third.html"
       }
     ],
     "video_effects": [
       { "id": "vfx01", "type": "zoompan", "start": 45.2, "end": 47.5, "zoom_curve": "smoothstep", "max_zoom": 1.25 }
     ]
   }
   ```
4. Regras:
   - Min 2s entre beats (exceto micro-acentos).
   - Sem cards laterais em `9:16`.
   - Zoom temporal **sempre** com `zoompan`, nunca `crop` com `t` (FFmpeg 8.x congela).
   - Se aplicas efeito, regista razão; se não aplicas em modo full, regista razão em `notes.md`.

## 4. Render base + legendas

### 4a. Legendas (se pediu)

1. Gera ficheiro ASS a partir do template:
   - `assets/subtitle-templates/full.ass` — segmentos completos
   - `assets/subtitle-templates/karaoke.ass` — word-by-word com `{\k}`
   - `assets/subtitle-templates/highlights.ass` — só palavras-chave em destaque
2. Substitui placeholders no template:
   - `__PLAY_RES_X__` / `__PLAY_RES_Y__` → width/height de `project.json`
   - `__PRIMARY__` / `__SECONDARY__` → cores do `client-style.md`
   - `__FONT__` → fonte preferida (default `Inter` ou `Bebas Neue` para Reels)
3. Gera `edit/subtitles.ass`. Em Windows escreve UTF-8 **sem BOM**:
   ```powershell
   [IO.File]::WriteAllText($path, $ass, [Text.UTF8Encoding]::new($false))
   ```
4. Queima com `scripts/burn-subtitles.ps1 -Input renders/edited.mp4 -Subtitles edit/subtitles.ass -Output renders/edited_subs.mp4`.

### 4b. Efeitos de vídeo (se `beats_plan.video_effects` não estiver vazio)

1. Para cada `zoompan`:
   ```
   -vf "zoompan=z='if(between(in_time,<s>,<e>),min(1+<rate>*(in_time-<s>),1.25),1)':d=1:s=<W>x<H>:fps=<FPS>"
   ```
   `in_time` é a chave — `crop=t...` não funciona em FFmpeg 8.x.
2. Para `punch-in` instantâneo: `scale` para zoom fixo no momento (>1s).
3. Para `speed-ramp-soft`: combina `setpts` com `atempo`.
4. Aplica sobre `renders/edited_subs.mp4` (ou `edited.mp4` se sem legendas), saída para `cache/base_with_effects.mp4`.

### 4c. Overlays motion graphics (modo full)

1. Para cada beat `title-card`, `lower-third`, etc.:
   - Renderiza HTML via Chrome headless → PNG sequência ou MOV com alpha
   - `scripts/render.ps1 -Phase overlays` orquestra
2. Composita overlays no momento certo:
   ```
   ffmpeg -i cache/base_with_effects.mp4 -i overlays/b01.mov \
     -filter_complex "[0:v][1:v]overlay=enable='between(t,<start>,<end>)'" \
     -c:a copy renders/draft/draft.mp4
   ```
3. Se Chrome headless não estiver disponível: usa fallback puro FFmpeg com `drawtext` para cards simples.

### 4d. Draft

1. Gera `renders/draft/draft.mp4` com encoder rápido: `-c:v libx264 -preset ultrafast -crf 28`.
2. Mostra ao utilizador.

## 5. Revisão e render final

### 5a. Revisão visual

1. Extrai 6+ frames para `verify/`:
   ```powershell
   foreach ($t in 0.5, $d_a_quarter, $d_a_metade, $d_a_3_quartos, ($d - 0.5), $efeito_pico) {
       ffmpeg -y -ss $t -i renders/draft/draft.mp4 -frames:v 1 verify/frame_$t.png
   }
   ```
2. Mostra ao utilizador o draft + frames.
3. Espera o utilizador dizer `"renderiza"` ou `"está bom"` antes do final. Se pedir ajustes, vai para **Iteração** (no fim).

### 5b. Render final

Aplica o pipeline de overlays/efeitos novamente mas com encoder lento:
```
-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p
-c:a aac -b:a 192k -movflags +faststart
```
Output: `renders/final/final.mp4`.

## 6. Verificação e entrega

### 6a. Checklist booleano em `project.json.checklist`

| Item | Verificação |
|---|---|
| `duration_verified` | `ffprobe -show_entries format=duration` do final está dentro do esperado (±0.5s) |
| `audio_present` | Stream áudio existe e tem nível médio > -40dB |
| `silences_reviewed` | `silencedetect=n=-30dB:d=2` não revela silêncios > 2s não intencionais |
| `codec_verified` | `pix_fmt=yuv420p`, `codec_name=h264` |
| `resolution_correct` | Width/height batem com `project.json.media` |
| `subtitles_synced_or_skipped` | Se legendas: amostra 3 timestamps e confirma sync ≤ 0.2s |
| `files_in_project_folder` | Não há outputs fora da pasta do projeto |

### 6b. Revisão visual obrigatória

Extrai ≥6 frames para `verify/`:
1. Início (`t=1`), meio (`t=duration/2`), fim (`t=duration-1`)
2. Pico de cada efeito declarado em `beats_plan.video_effects`
3. 2 momentos de legendas densas (se aplicável)
4. Um frame de **controlo** fora de qualquer efeito

Compara cada frame com a expectativa. Anti-padrões a procurar:
- Zoom congelado (efeito declarado mas frame de pico igual ao base) → `crop` com `t` em vez de `zoompan`
- Legendas mojibake (`Ã¡`/`Ã©`) → ASS gravado com BOM ou encoding errado
- Overlay vazio → HTML transparente sem conteúdo visível
- Cara coberta → zona segura não respeitada
- Karaoke sobreposto → timestamps de palavras com gap incorreto

### 6c. Entrega

Só com 6a verde **E** 6b OK:
1. Atualiza `notes.md` com sumário das decisões
2. Apresenta ao utilizador:
   - Path: `projects/YYYY-MM-DD_slug/renders/final/final.mp4`
   - Duração final
   - 2-3 frames de amostra (paths em `verify/`)
   - Resumo: `Cortei N silêncios (X segundos), M fillers. Legendas estilo Y. Modo Z.`

## Fases opcionais (packs extras)

Estas fases ativam-se por pedido do utilizador ou por flags no `client-style.md`. Aplicar **antes** da fase 5b (render final).

### Fase A — Pack áudio (`reference/audio-pack.md`)

Trigger: utilizador diz `"limpa o áudio"`, `"normaliza"`, `"som consistente"`, ou `client-style.md.audio_pack` está definido.

Aplica entre a fase 2 (corte) e a fase 4 (legendas) — o áudio limpo melhora também a transcrição se for refeita:

```powershell
.\scripts\audio-process.ps1 `
    -InputFile <projeto>\renders\edited.mp4 `
    -OutputFile <projeto>\renders\edited_audio.mp4 `
    -Denoise -Compress -Normalize -TargetLufs -14
```

Default chain para voz: `-Denoise -Compress -Normalize`. Ajustar `-TargetLufs` por plataforma:
- YouTube/Spotify: -14
- Reels/Instagram: -16
- TikTok: -13

Se utilizador passar música de fundo, adicionar `-Music <path> -MusicVolume 0.25` para ducking automático.

### Fase B — Pack visual (`reference/visual-effects.md`)

Trigger: utilizador diz `"look cinematográfico"`, `"aplica X.cube"`, `"adiciona vignette/grain"`, `"transição entre estes clips"`, ou `client-style.md.lut` está definido.

**LUT no render final** (entre legendas e overlays):
```powershell
.\scripts\visual-effects.ps1 -Mode Lut `
    -InputFile <projeto>\renders\edited_subs.mp4 `
    -OutputFile <projeto>\cache\graded.mp4 `
    -LutFile assets\luts\cinematic.cube -LutIntensity 0.8
```

**Color grade custom (sem LUT)**:
```powershell
.\scripts\visual-effects.ps1 -Mode Grade `
    -InputFile <input> -OutputFile <output> `
    -Contrast 1.15 -Saturation 1.1 -VignetteStrength 0.4 -FilmGrain 6
```

**Transição entre segmentos** (alternativa ao concat seco da fase 2):
```powershell
.\scripts\visual-effects.ps1 -Mode Transition `
    -InputA seg_01.mp4 -InputB seg_02.mp4 `
    -OutputFile join.mp4 -Transition fade -Duration 0.5
```

### Fase C — Smart reframe 16:9 → 9:16 (`reference/smart-reframe.md`)

Trigger: utilizador diz `"versão Reels"`, `"converte para vertical"`, `"output 9:16"`, `"versão Stories"`.

Aplica **depois** do `final.mp4` 16:9 estar pronto, gerando um output adicional sem reprocessar tudo:

```powershell
python scripts\smart-reframe.py `
    --input <projeto>\renders\final\final.mp4 `
    --output <projeto>\renders\final\final_reels.mp4 `
    --target-aspect 9:16 --vertical-offset -0.3
```

`--vertical-offset -0.3` empurra crop para cima (talking head típico).

Registar em `project.json.renders.vertical = "renders/final/final_reels.mp4"`.

Para multi-formato a partir do mesmo source, correr 2-3 vezes com `--target-aspect` diferente (`9:16`, `1:1`, `4:5`).

**Dependência**: `pip install mediapipe opencv-python`. Se em falta, perguntar ao utilizador se autoriza instalar antes de continuar.

## Iteração

Mudanças depois do primeiro render:

| Pedido | Onde mexer | Re-render |
|---|---|---|
| "Muda a cor das legendas" | `assets/subtitle-templates/<estilo>.ass` (cópia em `edit/`) | Fase 4a |
| "O zoom aos 45s está mau" | `beats_plan.json.video_effects[id=vfx01]` | Fase 4b |
| "Tira o card do início" | `beats_plan.json.beats` (remove b01) | Fase 4c |
| "Corta também aos 30s" | `edit/edl.json.segments_keep` | Fases 2 → 6 (timestamps deslocam) |
| "Outro estilo de legendas" | `project.json.settings.subtitle_style` + regenera | Fase 4a |

Em cortes adicionais (último caso), avisa o utilizador antes de continuar — todos os timestamps a jusante mudam.
