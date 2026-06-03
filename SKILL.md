---
name: videokit
description: Editor autónomo de vídeo via FFmpeg + Whisper. Corta silêncios e fillers, queima legendas (full/karaoke/highlights), aplica LUTs e efeitos visuais, motion graphics, limpa áudio (denoise + loudnorm) e converte 16:9 → 9:16 com tracking de cara. Trigger quando o utilizador disser 'edita vídeo X', 'corta os ahn', 'legenda', 'versão Reels', 'limpa áudio'.
argument-hint: <caminho-absoluto-do-video> [--mode full|cut-only] [--subs full|karaoke|highlights|sem]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, PowerShell
---

# videokit

## Princípio

Atua como editor de vídeo autónomo. A skill é **invocada explicitamente** pelo utilizador — não procura ficheiros na pasta atual do Claude Code. Toda a configuração persistente (estilo do cliente, cache de ambiente) vive **dentro da própria skill**. Outputs (projetos com transcrições, edits, renders) são criados **ao lado do vídeo source**, ou num caminho que o utilizador indique.

A skill cobre 4 formatos: **16:9**, **9:16**, **1:1**, **screencast**. O perfil é detetado por `ffprobe` ou perguntado se ambíguo.

## Paths fixos da skill

Independentemente da pasta de onde o Claude Code é invocado:

```text
~/.claude/skills/videokit/
├── SKILL.md
├── reference/        # documentação on-demand
├── scripts/          # PowerShell + Python
├── assets/           # templates ASS + HTML
├── cache/
│   └── env-report.json    # detect-env.ps1 escreve aqui (uma vez)
└── styles/
    └── client-style.md    # criado no onboarding (uma vez)
```

Em Windows isto resolve para `C:\Users\<user>\.claude\skills\videokit\`. Em mac/Linux: `~/.claude/skills/videokit/`.

## Invocação típica

O utilizador chama a skill com um caminho de vídeo absoluto, p.ex.:

```
edita este vídeo C:\Downloads\meu-pitch.mp4
```

Ou:

```
corta os silêncios e fillers em D:\projetos\cliente\raw.mov
```

A skill **não** procura `input/` em lado nenhum. Se o utilizador não indicar caminho, pede o caminho absoluto do source.

## Onboarding (primeira utilização)

Se `~/.claude/skills/videokit/styles/client-style.md` não existir, faz onboarding **antes** de qualquer pipeline. Lê `reference/onboarding.md` e faz **uma pergunta de cada vez**. Guarda em `~/.claude/skills/videokit/styles/client-style.md`.

Resumo das 7 perguntas (detalhe em `reference/onboarding.md`):
1. Cor principal (hex)
2. Cor secundária compatível (hex)
3. Estilo de edição: minimalista, dinâmico, corporativo ou educativo
4. Posição habitual do orador: centro, direita ou esquerda
5. Logo opcional (caminho para PNG transparente — fica em `~/.claude/skills/videokit/brand/logo/`)
6. Estilo de legendas por defeito: completas, karaoke, highlights, sem
7. Transcritor preferido: Whisper local, OpenAI ou ElevenLabs

Confirma no fim: `Estilo guardado. Já posso editar os teus vídeos com este look.`

## Arranque (preparação interna)

Antes da primeira fase do pipeline:

0. **Auto-instalar pré-requisitos se em falta**. Verifica `ffmpeg`, `python3.12+`, e pacotes pip core (whisper, mediapipe, opencv). Se algo em falta:
   - Avisa o utilizador: `"Detetei que falta X. Posso instalar automaticamente?"`
   - Se sim, corre:
     ```powershell
     # Windows
     & "$env:USERPROFILE\.claude\skills\videokit\scripts\bootstrap.ps1" -AutoYes
     ```
     ```bash
     # macOS / Linux
     bash ~/.claude/skills/videokit/scripts/bootstrap.sh --auto-yes
     ```
   - Para features adicionais (diarization, translation, tts, audio-separation, bg-removal), corre `install-feature.{ps1,sh} <feature>` quando o utilizador pedir essa funcionalidade pela primeira vez.

1. **Deteta o SO** para fazer routing entre scripts PowerShell (`.ps1`) e Bash (`.sh`):
   - Windows: usar `.ps1` via PowerShell
   - macOS / Linux: usar `.sh` via Bash
2. Verifica `~/.claude/skills/videokit/cache/env-report.json`. Se não existir, corre:
   ```powershell
   # Windows
   & "$env:USERPROFILE\.claude\skills\videokit\scripts\detect-env.ps1"
   ```
   ```bash
   # macOS / Linux
   bash ~/.claude/skills/videokit/scripts/detect-env.sh
   ```
   O script escreve o report dentro de `cache/` da skill. O campo `os` em `env-report.json` confirma `windows`/`macos`/`linux` — usa-o para decidir entre `.ps1` e `.sh` em invocações posteriores.
3. Lê `env-report.json` para `ffmpeg_bin`, `ffprobe_bin`, `python_bin`, `whisper_installed`, `libass_available`, `transcription_provider`.
4. Em produção usa **sempre** caminhos completos lidos do report. Nunca invoques `ffmpeg`/`ffprobe` nus em Windows.
5. Se utilizador escolheu Whisper local e `whisper_installed=false`: instala com `pip install -U openai-whisper` (com o `python_bin` do report). Avisa do download de modelo na primeira corrida.
6. Em Windows define no ambiente da sessão: `PYTHONIOENCODING=utf-8` e `MPLCONFIGDIR=<skill>/cache`.

### Tabela de routing por script

| Operação | Windows | macOS / Linux |
|---|---|---|
| Bootstrap (system + pip core) | `bootstrap.ps1` | `bootstrap.sh` |
| Install feature pack | `install-feature.ps1 <feature>` | `install-feature.sh <feature>` |
| Detect env | `detect-env.ps1` | `detect-env.sh` |
| Init project | `init-project.ps1 -InputVideo X` | `init-project.sh --input X` |
| Download models | `download-assets.ps1` | `download-assets.sh` |
| Audio pack | `audio-process.ps1` | `audio-process.sh` |
| Visual effects | `visual-effects.ps1` | `visual-effects.sh` |
| Burn subs | `burn-subtitles.ps1` | `burn-subtitles.sh` |
| Render orchestrator | `render.ps1` | `render.sh` |
| Auto-cut | `auto-cut.py` (cross-platform) |
| Transcribe | `transcribe.py` (cross-platform) |
| Smart reframe | `smart-reframe.py` (cross-platform) |
| Diarize | `diarize.py` (cross-platform) |
| Translate subs | `translate-subtitles.py` (cross-platform) |
| TTS narration | `narrate.py` (cross-platform) |
| Audio separation | `separate-audio.py` (cross-platform) |
| Background removal | `remove-bg.py` (cross-platform) |
| Gen LUTs | `gen-luts.py` (cross-platform) |

Os scripts Python são cross-platform — invocados via `python3` (Unix) ou `python` (Windows), lê o `python_bin` do `env-report.json`.

### Workflow de auto-install de dependências por feature

Quando o utilizador pede uma feature que precisa de deps adicionais, deteta primeiro se estão instaladas. Se não:

```
Utilizador: "diariza este podcast"
Skill: deteta pyannote em falta via `python -c "import pyannote"`
Skill: "Preciso instalar pyannote.audio + torch (~500MB). Posso?"
Utilizador: "sim"
Skill: corre install-feature.ps1 diarization (ou .sh)
Skill: continua com diarize.py
```

Pacotes pip por feature:
- `diarization` → `pyannote.audio` `torch` `torchaudio` (~500MB) + `HF_TOKEN` env var
- `translation` → `argostranslate` (~150MB + ~100MB por par de línguas)
- `tts` → `piper-tts` (~50MB + ~50-100MB por voz)
- `audio-separation` → `demucs` `torch` `torchaudio` (~2GB)
- `bg-removal` → `rembg` `opencv-python` `pillow` (~250MB)

## Criar projeto para um vídeo

Quando o utilizador passa um caminho de vídeo, cria a pasta do projeto **ao lado do source** (não dentro da skill):

```text
<dir_do_source>/videokit-projects/YYYY-MM-DD_slug/
  source/             # cópia do raw
  transcripts/        # raw.json + clean.json
  edit/               # edl.json + segments/ + subtitles.ass
  overlays/           # MOV/PNG com alpha (motion graphics)
  renders/
    draft/            # preview rápido
    final/            # entrega
  verify/             # frames extraídos
  cache/              # temporários
  logs/
  project.json
  beats_plan.json
  notes.md
```

Exemplo: se o utilizador passa `C:\Downloads\meu.mp4`, o projeto fica em `C:\Downloads\videokit-projects\2026-06-03_meu\`.

Se o utilizador indicar um `-OutputDir` explícito (ex.: "põe o resultado em D:\edited\"), usa esse path.

Usa `scripts/init-project.ps1 -InputVideo <abs-path> [-OutputDir <abs-path>]`:
- Gera slug ASCII seguro
- Copia source para `source/`
- Deteta `width`, `height`, `fps`, `duration`, `rotation`, aspect ratio
- Escreve `project.json`
- Devolve o path absoluto do projeto criado (para usares nos passos seguintes)

**Toda** a saída específica do vídeo fica nesta pasta. Apagar a pasta = limpar tudo desse vídeo.

## Fluxo principal

Para `"edita este vídeo <path>"` (ou equivalente), lê `reference/pipeline.md` e executa as 6 fases. Antes de começar, pergunta **uma vez só**:

1. Estilo de legendas para este vídeo (default vem do `client-style.md`): `completas | karaoke | highlights | sem`
2. Modo: `full` (com motion graphics) ou `cut-only`
3. Algum comentário importante? (termos técnicos, contexto, foco)

Depois disso, executa sem pausas até à **revisão visual** (fase 5b). Aí espera o utilizador dizer `"renderiza"` antes do final.

## Documentos do workspace

Lê só o necessário, nesta ordem:

- `reference/pipeline.md` — as 6 fases (entrada → entrega)
- `reference/formats.md` — specs e zonas seguras por aspect ratio
- `reference/subtitle-styles.md` — quando usar full / karaoke / highlights
- `reference/lessons-learned.md` — gotchas FFmpeg 8.x, iPhone, PowerShell, Whisper
- `reference/onboarding.md` — primeira conversa (perguntas + formato do client-style.md)
- `reference/audio-pack.md` — denoise RNNoise, loudnorm EBU R128, ducking de música
- `reference/visual-effects.md` — transições xfade, LUTs (.cube), color grading, vignette, film grain
- `reference/smart-reframe.md` — converte 16:9 → 9:16/1:1 com tracking de cara (MediaPipe)
- `~/.claude/skills/videokit/styles/client-style.md` — identidade visual do utilizador
- Pastas `videokit-projects/` anteriores (se existirem ao lado do source) — consistência com edições prévias

## Regras duras

- **Áudio nunca com `-c copy` sozinho** em cortes: usa `-c:v copy -c:a aac -b:a 192k` (packets AAC desincronizam senão).
- **Zoom temporal só com `zoompan`** (`d=1`, `s=WxH:fps=N`); nunca `crop` com expressão `t` — FFmpeg 8.x não reavalia o filtro por frame e o zoom fica congelado.
- **Legendas ASS em UTF-8 sem BOM**, com `PlayResX`/`PlayResY` iguais à resolução. Em Windows:
  ```powershell
  [IO.File]::WriteAllText($p, $s, [Text.UTF8Encoding]::new($false))
  ```
- **iPhone/MOV com rotação**: deteta `displaymatrix/rotation` com `ffprobe`. Se 90/270, recodifica para normalizar. Nunca `-c:v copy` se mantiver orientação errada.
- **MOV multi-stream** (AAC + spatial 4ch): `-ss`/`-to` **antes** de `-i` e `-map 0:a:0` ao extrair áudio.
- **Não hardcoded resolutions**: lê sempre de `project.json.media` (vem de `ffprobe`).
- **Não cobrir cara do orador**: respeita zonas seguras de `reference/formats.md`.
- **Karaoke sem sobreposição**: `Start[i+1] ≥ End[i]`. Word-by-word com `{\k}` tags.
- **Verificação obrigatória antes de entregar**: checklist booleano em `project.json.checklist` **E** extração de ≥6 frames para `verify/` (pico de cada efeito, 1 frame de controlo, 2 momentos de legendas densas, primeiro/último beat).
- **Whisper local first**: se houver chave API E o `client-style.md` preferir API, usa essa. Senão, Whisper local com modelo `medium`.
- **Outputs sempre dentro da pasta do projeto** criada — não escreves em `~/.claude/skills/videokit/` durante uma edição (exceto onboarding e env-report).
- **PowerShell em Windows**: traduz comandos bash sem mudar intenção. Vê pegadinhas em `reference/lessons-learned.md`.

## Iteração

Depois do primeiro render, modo iteração — toca só no afetado:

- **Legendas (cor, estilo)**: edita `<projeto>/edit/subtitles.ass` e re-queima.
- **Timestamp de corte**: edita `<projeto>/edit/edl.json` e re-executa fase de cut.
- **Motion graphics**: edita `<projeto>/beats_plan.json` e re-renderiza só os beats afetados.
- **Cortes diferentes do base**: avisa que timestamps das legendas vão deslocar e pede confirmação antes.

## Funcionalidades extra (opt-in por pedido)

Além do pipeline base (corte + legendas + motion graphics), a skill expõe vários packs opcionais que o utilizador pode invocar diretamente ou que ficam configurados no `client-style.md`:

### Audio/Visual base (FFmpeg puro, sem deps adicionais)

- **Pack áudio** (`scripts/audio-process.{ps1,sh}`): denoise (RNNoise), normalize EBU R128 (-14 LUFS YouTube, -16 Reels, -13 TikTok), compressor de voz, de-esser, mistura com música de fundo + ducking automático. Trigger: `"limpa o áudio"`, `"normaliza o som"`, `"mete uma música de fundo"`. Detalhe em `reference/audio-pack.md`.

- **Pack visual** (`scripts/visual-effects.{ps1,sh}`): 40+ transições xfade entre clips, aplicação de LUTs `.cube` (13 incluídos: identity, warm, cool, cinematic, bw, pastel, vintage, noir, vibrant, faded, golden-hour, teal-cool, high-contrast), color grading com vignette + film grain. Trigger: `"aplica um look cinematográfico"`, `"transição suave aqui"`, `"adiciona grain"`. Detalhe em `reference/visual-effects.md`.

- **Smart reframe 16:9 → 9:16** (`scripts/smart-reframe.py`): converte vídeo horizontal em vertical (ou 1:1, 4:5) seguindo o orador via MediaPipe Face Detection. Suporta tracking só X (default) ou X+Y com `--vertical-tracking`. Trigger: `"faz versão para Reels"`, `"converte para vertical"`, `"versão Stories"`. Requer `pip install mediapipe opencv-python`.

### Audio/Visual avançado (deps adicionais — instalar conforme uso)

- **Diarização** (`scripts/diarize.py`): identifica quem fala quando (`SPEAKER_00`, `SPEAKER_01`, ...). Trigger: `"quem fala em cada parte?"`, `"podcast com 2 oradores"`, `"legendas com nome do orador"`. Requer `pip install pyannote.audio torch` + `HF_TOKEN`. Detalhe em `reference/diarization.md`.

- **Tradução de legendas** (`scripts/translate-subtitles.py`): traduz ASS/SRT entre línguas (PT/EN/ES/FR/IT/DE...) offline via argos-translate. Trigger: `"traduz legendas para inglês"`, `"versão para espanhol"`. Requer `pip install argostranslate`. Detalhe em `reference/translation.md`.

- **TTS narração** (`scripts/narrate.py`): síntese de voz neural local via Piper. Vozes PT-PT (tugão), PT-BR (faber/edresson), EN-US (amy/lessac), etc. Trigger: `"gera narração para este texto"`, `"voz a ler isto"`. Requer `pip install piper-tts`. Detalhe em `reference/tts.md`.

- **Separação de áudio** (`scripts/separate-audio.py`): Demucs separa vocals/drums/bass/other. Útil para remover música pré-existente, isolar voz para karaoke real, ou substituir música de fundo. Trigger: `"remove a música do vídeo"`, `"isola só a voz"`, `"karaoke instrumental"`. Requer `pip install demucs torch`. Detalhe em `reference/audio-separation.md`.

- **Background removal** (`scripts/remove-bg.py`): remove fundo sem greenscreen via rembg/U²-Net. Modos: alpha (compositing), replace (imagem/cor), blur (look webcam). Trigger: `"remove o fundo"`, `"fundo blur"`, `"troca fundo por imagem"`. Requer `pip install rembg opencv-python`. Detalhe em `reference/background-removal.md`.

## Resumo: como o utilizador usa a skill

1. (Uma vez) instalou a skill em `~/.claude/skills/videokit/`.
2. Abre o Claude Code **em qualquer lado**.
3. Diz: `edita este vídeo C:\caminho\para\video.mp4`.
4. Na primeira vez responde às 7 perguntas de onboarding.
5. Vê o draft + 6 frames. Diz `renderiza` para final.
6. Recebe path do `final.mp4` ao lado do source.
7. Pode pedir extras: `"limpa o áudio"`, `"versão Reels"`, `"aplica look cinematográfico"`.

Nunca precisa de criar pastas, copiar ficheiros, ou preparar o ambiente.
