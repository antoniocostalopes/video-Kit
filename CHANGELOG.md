# Changelog

Todas as mudanças significativas do videokit ficam documentadas aqui.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e o projeto adere a [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [Unreleased]

### Audio/Visual avançado (7 novos scripts + extensões)

- **`scripts/diarize.py`** — Diarização via pyannote-audio. Identifica `SPEAKER_00`, `SPEAKER_01`... Integra com transcript para legendas com nome do orador. Requer HF_TOKEN.
- **`scripts/translate-subtitles.py`** — Tradução de legendas ASS/SRT entre línguas (PT/EN/ES/FR/IT/DE...) offline via argos-translate.
- **`scripts/narrate.py`** — TTS local Piper. Vozes PT-PT, PT-BR, EN-US/UK, ES, FR descarregadas sob demanda.
- **`scripts/separate-audio.py`** — Separação de áudio via Demucs (vocals/drums/bass/other ou two-stems vocals+no_vocals).
- **`scripts/remove-bg.py`** — Background removal sem greenscreen via rembg/U²-Net. Modos alpha/replace/blur.
- **`scripts/smart-reframe.py`** — adicionado `--vertical-tracking` (segue cara em Y também) + `--face-position` (upper-third/center/two-thirds).
- **`scripts/gen-luts.py`** — 8 novos LUTs procedurais: pastel, vintage, noir, vibrant, faded, golden-hour, teal-cool, high-contrast. Total: 13 LUTs.

### Reference docs (5 novos)
- `reference/diarization.md`
- `reference/translation.md`
- `reference/tts.md`
- `reference/audio-separation.md`
- `reference/background-removal.md`

### Quick wins
- Bash equivalents (.sh) dos scripts PowerShell — paridade macOS/Linux
- `CHANGELOG.md` + `CONTRIBUTING.md`
- GitHub Actions workflow para validar sintaxe em PRs
- Validação de inputs em `init-project` (extensão, duração, audio stream, disco livre)
- Flag `-CleanCache` / `--clean-cache` em `render` para apagar temporários no fim do pipeline
- `README.en.md` (versão inglesa)
- SKILL.md instrui agente a fazer routing automático Windows (.ps1) / Unix (.sh)

---

## [0.1.0] — 2026-06-03

### Adicionado

#### Pipeline core
- **Transcrição** via Whisper local (default), OpenAI API, ou ElevenLabs API
- **Corte automático** com remoção de silêncios (>0.5s) e fillers PT/EN
- **Legendas queimadas** em 3 estilos: `completas`, `karaoke`, `highlights`
- **Motion graphics** com title cards e lower thirds HTML (alpha)
- **Verificação obrigatória** pré-entrega: checklist booleano + ≥6 frames de revisão

#### Pack áudio profissional (FFmpeg)
- Denoise RNNoise via `arnndn` filter (modelo `cb.rnnn` CC-BY)
- Normalize EBU R128 com presets por plataforma (-14 YouTube, -16 Reels, -13 TikTok)
- Compressor de voz + de-esser
- Sidechain ducking de música de fundo

#### Pack visual (FFmpeg)
- 40+ transições via `xfade` filter
- 5 LUTs procedurais (`.cube`): identity, warm, cool, cinematic, bw
- Color grading com vignette + film grain
- Aplicação parcial de LUT (`-LutIntensity`)

#### Smart reframe 16:9 → 9:16
- Tracking de cara via MediaPipe BlazeFace (Tasks API)
- Smoothing temporal (moving average) configurável
- Suporta 9:16, 1:1, 4:5
- Vertical offset opcional para talking heads

#### Scripts orquestradores
- `detect-env.ps1` — deteta ambiente, escreve `cache/env-report.json`
- `init-project.ps1` — cria `videokit-projects/YYYY-MM-DD_slug/` ao lado do source
- `download-assets.ps1` — descarrega modelos runtime (RNNoise, BlazeFace) on-demand
- `render.ps1` — orquestra cut / subs / effects / overlays / verify

#### Documentação
- `SKILL.md` manifest com `argument-hint` e `allowed-tools`
- 8 docs de referência (pipeline, formats, onboarding, lessons-learned, etc.)
- README completo com Mermaid diagram + walkthrough conversacional

#### Assets
- 3 templates ASS de legendas (full, karaoke, highlights)
- 2 templates HTML para motion graphics (title-card, lower-third)
- 5 LUTs procedurais (auto-gerados via `gen-luts.py`)
- Icon SVG vetorial

### Limitações conhecidas
- Scripts apenas em PowerShell (Windows-only neste release)
- Smart reframe só tracking horizontal (X), não vertical (Y)
- Single-pass loudnorm (~0.5 LUFS imprecisão vs two-pass)
- Sem suporte GPU para Whisper (CPU only neste release)

[Unreleased]: https://github.com/antoniocostalopes/video-Kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/antoniocostalopes/video-Kit/releases/tag/v0.1.0
