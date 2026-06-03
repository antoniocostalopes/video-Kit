# Changelog

Todas as mudanças significativas do videokit ficam documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e o projeto adere a [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [Unreleased]

Sem alterações desde v0.1.0.

---

## [0.1.0] — 2026-06-03

Release inicial. Skill completa e operacional do Claude Code para edição autónoma de vídeo.

### Pipeline core
- **Transcrição** via Whisper local (default), OpenAI API ou ElevenLabs API com word timestamps
- **Corte automático** com remoção de silêncios (>0.5s) e fillers PT (`ahn`, `tipo`, `né`, `pronto`...) e EN (`um`, `like`, `you know`...)
- **Deteção de retakes** (frase iniciada e abortada)
- **Legendas queimadas (ASS)** em 3 estilos: `full`, `karaoke` (word-by-word), `highlights`
- **Motion graphics** com title cards e lower thirds HTML alpha (Google Fonts, CSS animations)
- **Verificação obrigatória** pré-entrega: checklist booleano + ≥6 frames extraídos
- **Estrutura de projeto** `videokit-projects/YYYY-MM-DD_slug/` criada ao lado do source

### Pack áudio profissional (FFmpeg puro)
- Denoise RNNoise via `arnndn` filter (modelo `cb.rnnn` CC-BY, download runtime)
- Normalize EBU R128 com presets por plataforma (-14 LUFS YouTube, -16 Reels, -13 TikTok, -16 Apple Podcasts)
- Compressor de voz + de-esser
- Sidechain ducking automático de música de fundo

### Pack visual (FFmpeg puro)
- 40+ transições via `xfade` filter (fade, slide, wipe, circleopen, dissolve, radial, pixelize...)
- 13 LUTs procedurais (`.cube`): identity, warm, cool, cinematic, bw, pastel, vintage, noir, vibrant, faded, golden-hour, teal-cool, high-contrast
- Color grading: vignette + film grain + brightness/contrast/saturation
- Aplicação parcial de LUT via blend (`-LutIntensity 0.6`)

### Smart reframe (16:9 → 9:16 / 1:1 / 4:5)
- Tracking de cara via MediaPipe BlazeFace (Tasks API)
- Tracking horizontal (X) sempre ativo; tracking vertical (X+Y) opcional via `--vertical-tracking`
- Smoothing temporal (moving average) configurável
- `--face-position` (upper-third / center / two-thirds) para talking heads

### Features avançadas (opt-in via install-feature)
- **Diarização** via pyannote-audio: identifica `SPEAKER_00`, `SPEAKER_01`... e integra com transcript para legendas com nome do orador (requer HF_TOKEN)
- **Tradução de legendas** via argos-translate: PT↔EN/ES/FR/IT/DE em ASS e SRT, offline
- **TTS local** via Piper: 8 vozes catalogadas (PT-PT tugão, PT-BR faber/edresson, EN-US amy/lessac, EN-GB alan, ES davefx, FR siwis)
- **Separação de áudio** via Demucs: vocals/drums/bass/other ou two-stems vocals+no_vocals (remover música, isolar voz, karaoke instrumental)
- **Background removal** via rembg/U²-Net: modos alpha (compositing), replace (imagem/cor), blur (look webcam virtual). Sem greenscreen.

### Auto-install
- **`bootstrap.{ps1,sh}`** instala FFmpeg + Python 3.12+ + pacotes pip core automaticamente. Windows via winget (sem admin), macOS via Homebrew, Linux via apt (Debian/Ubuntu)
- **`install-feature.{ps1,sh}`** instala feature packs por funcionalidade: `core` | `diarization` | `translation` | `tts` | `audio-separation` | `bg-removal` | `all`
- SKILL.md ensina o agente a oferecer auto-install quando deteta deps em falta (pede confirmação)

### Validação e robustez
- Validação de inputs em `init-project`: extensão (`mp4/mov/mkv/webm/avi/m4v/mts`), audio stream presence via ffprobe, duração mín 1s / aviso >2h, disco livre (3GB ou 6× source)
- Flag `-CleanCache` / `--clean-cache` em `render` para apagar temporários no fim do pipeline (mantém verify/ e renders/)
- `Start-Process -RedirectStandardError` em PowerShell para evitar NativeCommandError com stderr de ffmpeg
- `subprocess` com stderr para tempfile em Python (evita deadlocks com PIPE)

### Cross-platform (paridade total)
- 9 scripts PowerShell (Windows): bootstrap, install-feature, detect-env, download-assets, init-project, burn-subtitles, audio-process, visual-effects, render
- 9 scripts Bash (macOS/Linux): mesma semântica que .ps1
- 9 scripts Python (cross-platform): transcribe, auto-cut, smart-reframe, diarize, translate-subtitles, narrate, separate-audio, remove-bg, gen-luts
- SKILL.md instrui o agente a fazer routing automático baseado em `env-report.os`

### Documentação
- **SKILL.md** manifest com YAML frontmatter avançado (`name`, `description`, `argument-hint`, `allowed-tools`)
- **13 reference docs** on-demand: pipeline, formats, onboarding, subtitle-styles, audio-pack, visual-effects, smart-reframe, diarization, translation, tts, audio-separation, background-removal, lessons-learned
- **README.md** (PT) + **README.en.md** (EN) completos: 659 linhas cada, Mermaid pipeline diagram, conversational walkthrough, 11 cenários, cheatsheet de 26 triggers
- **CONTRIBUTING.md** com PR guidelines, code style, lessons-learned format

### CI / Quality
- **`.github/workflows/validate.yml`** valida em PRs: PSScriptAnalyzer (.ps1), py_compile + pyflakes (.py), shellcheck (.sh), Mermaid block validation (.md)

### Assets
- 3 templates ASS de legendas (full, karaoke, highlights — UTF-8 sem BOM, `PlayResX/Y` placeholders)
- 2 templates HTML motion graphics (title-card, lower-third — Google Fonts, animações CSS)
- 13 LUTs procedurais (.cube, 17×17×17, ~134KB cada — gerados via `gen-luts.py`)
- Icon SVG vetorial (film strip + play button + AI accent dot)

### Lessons learned documentadas
8 gotchas FFmpeg 8.x + Windows PowerShell + MediaPipe API capturadas em `reference/lessons-learned.md`:
- `crop` com `t` não reavalia por frame → usar `zoompan` com `in_time`
- `-c copy` sozinho desincroniza AAC → sempre `-c:a aac -b:a 192k`
- Filtro `subtitles` em Windows não aceita paths com `:` → copy + Push-Location
- iPhone MOV multi-stream → `-map 0:a:0`
- PowerShell 5.1 trata stderr nativo como erro → Start-Process
- subprocess PIPE com ffmpeg deadlock → stderr para tempfile
- MediaPipe 0.10.x removeu `mp.solutions` → Tasks API
- PowerShell `$Input` é reservado → usar `$InputFile`

### Modelos descarregados runtime (não redistribuídos)
- RNNoise `cb.rnnn` (~300KB, CC-BY)
- MediaPipe BlazeFace `.tflite` (~230KB, Apache 2.0)
- Piper voice models (~50-100MB cada, várias licenças)
- Demucs models (~1-2GB, MIT)
- rembg U²-Net (~170MB, Apache 2.0)
- pyannote diarization (~80MB, MIT + HF terms)
- argos-translate language packs (~100MB por par, CC-BY)

[Unreleased]: https://github.com/antoniocostalopes/video-Kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/antoniocostalopes/video-Kit/releases/tag/v0.1.0
