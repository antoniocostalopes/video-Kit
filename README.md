<div align="center">
  <img src="assets/icon.svg" width="140" alt="videokit"/>

  # videokit

  **Editor autónomo de vídeo com IA, como Skill do Claude Code.**

  Transcrição com Whisper · Corte automático · Legendas burned-in · Motion graphics · LUTs cinematográficos · Reframe 16:9 → 9:16 com tracking de cara

  [![License: Proprietary](https://img.shields.io/badge/license-Proprietary-DC2626.svg)](LICENSE)
  [![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-7C3AED.svg)](https://docs.anthropic.com/en/docs/claude-code)
  [![FFmpeg](https://img.shields.io/badge/FFmpeg-8.x-007808.svg)](https://ffmpeg.org)
  [![Python](https://img.shields.io/badge/Python-3.12%2B-3776AB.svg)](https://python.org)

</div>

---

## O que faz

Dás-lhe um vídeo. Ele transcreve, corta silêncios e fillers, gera legendas, aplica efeitos visuais, opcionalmente cria motion graphics, exporta multi-formato e verifica o resultado antes de entregar. Tudo a partir de uma única instrução conversacional no Claude Code.

| Capacidade | Implementação |
|---|---|
| **Transcrição** | Whisper local (default, offline, gratuito) ou OpenAI/ElevenLabs API |
| **Corte automático** | Remove silêncios >0.5s, fillers PT (`ahn`, `tipo`, `né`) e EN (`um`, `like`) |
| **Legendas queimadas** | 3 estilos ASS: `full`, `karaoke` (word-by-word), `highlights` |
| **LUTs e color grading** | 5 LUTs procedurais (warm/cool/cinematic/bw/identity) + vignette + film grain |
| **Transições** | 40+ via FFmpeg `xfade` (fade, slide, wipe, circleopen, dissolve...) |
| **Áudio profissional** | Denoise RNNoise + normalize EBU R128 + compressor + ducking de música |
| **Reframe 16:9 → 9:16** | Tracking de cara via MediaPipe BlazeFace (também 1:1 e 4:5) |
| **Motion graphics** | Title cards e lower thirds HTML com alpha |
| **Verificação obrigatória** | Checklist booleano + extração ≥6 frames antes de declarar "pronto" |

---

## Como funciona

1. **Instalas a skill uma vez** (instruções abaixo).
2. **Abres o Claude Code em qualquer pasta** — não precisas de preparar pastas, copiar ficheiros, ou criar `input/`.
3. **Dizes ao Claude o que queres**:
   ```
   edita este vídeo C:\Downloads\pitch.mp4
   ```
   Ou variantes:
   ```
   corta os silêncios em D:\raw\entrevista.mov
   limpa o áudio de pitch.mp4
   versão Reels de pitch.mp4
   aplica look cinematográfico em pitch.mp4
   ```
4. **Primeira vez:** responde a 7 perguntas de onboarding (cor, estilo, posição do orador, etc.). Guardado em `~/.claude/skills/videokit/styles/client-style.md`.
5. **Pipeline corre.** Vês um draft + 6 frames extraídos. Dizes `renderiza`.
6. **Recebes o `final.mp4`** ao lado do vídeo source, dentro de `videokit-projects/YYYY-MM-DD_slug/renders/final/`.

---

## Instalação

### Pré-requisitos

| Ferramenta | Para quê | Como instalar |
|---|---|---|
| **Claude Code** | Runtime da skill | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code) |
| **FFmpeg 8.x** com libass | Pipeline de vídeo/áudio | `winget install Gyan.FFmpeg` (Win) / `brew install ffmpeg` (mac) |
| **Python 3.12+** | Scripts de transcrição, corte, smart-reframe | `winget install Python.Python.3.13` (Win) / `brew install python` (mac) |
| **Node.js 22+** (opcional) | HyperFrames para motion graphics avançado | `winget install OpenJS.NodeJS.LTS` |

Pacotes Python (instalados sob demanda pela skill):
```bash
pip install openai-whisper           # transcrição local (default)
pip install mediapipe opencv-python  # smart reframe 16:9 → 9:16
```

### Passo 1 — Clonar este repositório

Numa pasta de desenvolvimento à tua escolha:

**Windows (PowerShell):**
```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/antoniocostalopes/video-Kit.git videokit
```

**macOS / Linux:**
```bash
cd ~/Documents
git clone https://github.com/antoniocostalopes/video-Kit.git videokit
```

### Passo 2 — Ligar ao Claude Code

A skill tem de estar visível em `~/.claude/skills/`. Cria um link simbólico (não duplica ficheiros):

**Windows (PowerShell, sem privilégios admin):**
```powershell
cmd /c mklink /J "$env:USERPROFILE\.claude\skills\videokit" "$env:USERPROFILE\Documents\videokit"
```

**macOS / Linux:**
```bash
ln -s ~/Documents/videokit ~/.claude/skills/videokit
```

### Passo 3 — Verificar

Abre o Claude Code (em qualquer pasta) e pergunta: `que skills tens disponíveis?` Deves ver `videokit` na lista.

Ou pelo terminal:
```powershell
Test-Path "$env:USERPROFILE\.claude\skills\videokit\SKILL.md"  # True
```

### Passo 4 — Detect ambiente (automático no 1º uso)

Na primeira invocação, a skill corre `scripts/detect-env.ps1` que escreve `cache/env-report.json` com os caminhos do FFmpeg, Python e capacidades disponíveis. Só precisas de garantir que FFmpeg e Python estão no PATH.

---

## Uso

### Pipeline completo (default)

```
edita este vídeo C:\Downloads\pitch.mp4
```

O Claude:
1. Cria `C:\Downloads\videokit-projects\2026-06-03_pitch\` com subpastas
2. Transcreve (Whisper local)
3. Corta silêncios e fillers (gera EDL editável)
4. Queima legendas se pediste (full/karaoke/highlights)
5. Aplica motion graphics (opcional)
6. Mostra draft + 6 frames de revisão
7. Pelo teu `renderiza`, gera `renders/final/final.mp4`

### Modos rápidos

| Pedido | O que faz | Modo |
|---|---|---|
| `edita este vídeo X` | Pipeline completo | `full` |
| `corta os ahn em X` | Só corte + legendas | `cut-only` |
| `limpa o áudio de X` | Denoise + normalize + compressor (FFmpeg puro) | audio-only |
| `põe legendas karaoke em X` | Pipeline com legendas word-by-word | `full` |
| `versão Reels de X` | Smart reframe 16:9 → 9:16 (precisa mediapipe) | reframe |
| `aplica look cinematográfico em X` | LUT cinematic.cube (teal-orange) | grade |

### Flags via slash command

```
/videokit C:\v.mp4 --mode cut-only --subs karaoke
```

`argument-hint` no SKILL.md declara: `<caminho-absoluto-do-video> [--mode full|cut-only] [--subs full|karaoke|highlights|sem]`.

---

## Estrutura do projeto

```
videokit/
├── SKILL.md                    # Manifest + fluxo principal (lido pelo Claude)
├── README.md                   # Este ficheiro (para humanos)
├── LICENSE                     # Proprietary (All Rights Reserved)
├── .gitignore
├── reference/                  # Documentação on-demand
│   ├── pipeline.md             # 6 fases (entrada → entrega)
│   ├── formats.md              # specs 16:9 / 9:16 / 1:1 / screencast
│   ├── onboarding.md           # primeira conversa
│   ├── subtitle-styles.md      # full / karaoke / highlights
│   ├── audio-pack.md           # denoise / loudnorm / ducking
│   ├── visual-effects.md       # transições / LUTs / grading
│   ├── smart-reframe.md        # tracking de cara MediaPipe
│   └── lessons-learned.md      # gotchas FFmpeg 8.x, Windows, Whisper
├── scripts/                    # 11 scripts (7 PowerShell + 4 Python)
│   ├── detect-env.ps1
│   ├── init-project.ps1
│   ├── transcribe.py
│   ├── auto-cut.py
│   ├── burn-subtitles.ps1
│   ├── audio-process.ps1
│   ├── visual-effects.ps1
│   ├── smart-reframe.py
│   ├── render.ps1
│   ├── download-assets.ps1
│   └── gen-luts.py
├── assets/
│   ├── icon.svg                # logo da skill
│   ├── subtitle-templates/     # 3 templates .ass
│   ├── beat-templates/         # 2 templates HTML
│   ├── luts/                   # 5 LUTs procedurais .cube
│   ├── audio-models/           # RNNoise .rnnn (download em runtime)
│   └── face-detector/          # BlazeFace .tflite (download em runtime)
└── cache/                      # env-report.json (estado local, gitignored)
```

### Onde ficam os outputs?

**Não dentro da skill.** Ficam ao lado do vídeo source:

```
C:\Downloads\
├── pitch.mp4                                  # o teu source
└── videokit-projects\
    └── 2026-06-03_pitch\
        ├── source/         # cópia do raw
        ├── transcripts/    # raw.json + clean.json
        ├── edit/           # edl.json + segments/ + subtitles.ass
        ├── overlays/
        ├── renders/
        │   ├── draft/
        │   └── final/final.mp4    ← entrega
        ├── verify/         # 6+ frames extraídos para revisão
        ├── project.json
        ├── beats_plan.json
        └── notes.md
```

Apagar `2026-06-03_pitch/` apaga tudo desse vídeo. O source original mantém-se intacto.

---

## Exemplos completos

### 1. Talking head para YouTube longo

```
edita este vídeo C:\Videos\episode-03.mp4 com legendas completas
```

Corte de fillers + legendas brancas em baixo + motion graphics ligeiros + áudio normalizado a -14 LUFS (YouTube).

### 2. Reel de Instagram com karaoke

```
versão Reels de C:\Videos\hook.mp4 com legendas karaoke
```

Smart reframe 16:9 → 9:16 (1080×1920) + legendas word-by-word grandes + áudio normalizado a -16 LUFS (Instagram).

### 3. Limpeza rápida sem motion graphics

```
corta os silêncios e os "tipo" em C:\Videos\raw.mov
```

Cut-only mode — só EDL + segmentos cortados + concatenação. Sem legendas, sem efeitos, sem motion graphics.

### 4. Áudio standalone para podcast

```
limpa o áudio de C:\Audio\episode.mp4 e normaliza para podcast
```

Denoise RNNoise + compressor + EBU R128 a -16 LUFS (Apple Podcasts).

### 5. Look cinematográfico

```
edita C:\Videos\promo.mp4 com look cinematográfico e legendas highlights
```

Pipeline + LUT cinematic.cube (teal-orange) + vignette + legendas highlights nas palavras-chave.

---

## Limitações

- **Windows-first**: scripts são PowerShell. Funciona em macOS/Linux com bash equivalentes a ser adicionados — contribuições bem-vindas.
- **Single-pass loudnorm**: ~0.5 LUFS de imprecisão vs. two-pass. Aceitável para conteúdo digital.
- **Smart reframe só tracking X**: o Y é fixo. Pessoas que se levantam/sentam não são tracked verticalmente.
- **Whisper local CPU**: ~5× tempo real em 1080p com modelo `medium`. GPU NVIDIA acelera 10× mas exige setup adicional.
- **Sem chroma key removal**: para greenscreen tens de processar antes.

---

## Roadmap

Funcionalidades planeadas (PRs bem-vindas):

- [ ] **Diarização** (`pyannote-audio`) — legendas com `Orador 1: / Orador 2:`
- [ ] **Tradução de legendas** (`NLLB-200`) — multi-língua local
- [ ] **B-roll automático** via Pexels API — keywords da transcrição → vídeos de stock
- [ ] **Chapter markers** automáticos — YouTube chapters file
- [ ] **TTS local** (`Piper` / `Coqui TTS`) — narração PT-PT / PT-BR
- [ ] **Stable Diffusion thumbnails** — frame + título overlay automático
- [ ] **Bash scripts** para macOS/Linux (parity com `.ps1`)
- [ ] **Hook detection** — primeiros 3-5s mais fortes para auto-trim Reels

---

## Lessons learned (FFmpeg 8.x gotchas)

Em `reference/lessons-learned.md` documento bugs reais e workarounds. Exemplos:

- **`crop` com `t` em FFmpeg 8.x não reavalia o filtro por frame** → zoom temporal congela. Usar `zoompan` com `in_time` (`d=1`).
- **`-c copy` sozinho em cortes desincroniza packets AAC** → sempre `-c:a aac -b:a 192k`.
- **Filtro `subtitles` em Windows não aceita paths com `:`** → copiar `.ass` para a pasta do output e referenciar pelo nome (`Push-Location`).
- **iPhone MOV multi-stream** (AAC + spatial 4ch) → `-map 0:a:0` para apanhar o stereo certo.
- **PowerShell 5.1 trata stderr de exes nativos como erro** → `Start-Process -RedirectStandardError $file` em vez de `2>&1`.

Se apanhares um bug FFmpeg num cenário não coberto, abre um issue ou PR com o workaround.

---

## Créditos

- **[FFmpeg](https://ffmpeg.org)** (LGPL/GPL) — pipeline central de vídeo/áudio
- **[OpenAI Whisper](https://github.com/openai/whisper)** (MIT) — transcrição
- **[MediaPipe](https://github.com/google-ai-edge/mediapipe)** (Apache 2.0, Google) — face detection para reframe
- **[RNNoise models](https://github.com/GregorR/rnnoise-models)** (CC-BY) — `cb.rnnn` para denoise
- **[OpenCV](https://opencv.org)** (Apache 2.0) — I/O de frames no smart-reframe
- Inspirado por [LeMousk/video-edit-kit](https://github.com/LeMousk/video-edit-kit) — arquitetura de pipeline e disciplina de "lessons learned"

---

## Licença

**Proprietário — All Rights Reserved** — ver [LICENSE](LICENSE).

Este código é publicado para visualização (portfólio, transparência, fins educativos), mas **não concede licença de uso, modificação ou redistribuição**. Para licenciar o videokit ou partes dele, contacta: **antonio@agencycoders.com**.

### Componentes de terceiros

Modelos descarregados em runtime (FFmpeg, OpenAI Whisper, MediaPipe BlazeFace, RNNoise, OpenCV) mantêm as **suas próprias licenças** e não são cobertos por esta licença proprietária. Os scripts da skill nunca incluem nem redistribuem os modelos `cb.rnnn` (CC-BY) e `blaze_face_short_range.tflite` (Apache 2.0) — são `gitignored` e descarregados localmente a partir das fontes oficiais pelos helpers `scripts/download-assets.ps1` e `scripts/smart-reframe.py` na primeira utilização.

---

<div align="center">
  <sub>Built for Claude Code · Antonio Costa Lopes · 2026</sub>
</div>
