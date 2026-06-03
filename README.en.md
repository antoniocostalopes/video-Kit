<div align="center">
  <img src="assets/icon.svg" width="140" alt="videokit"/>

  # videokit

  **Autonomous video editor as a Claude Code Skill.**

  Whisper transcription · Auto-cut · Burned-in subtitles · Motion graphics · Cinematic LUTs · 16:9 → 9:16 reframe with face tracking

  [![Author](https://img.shields.io/badge/author-Antonio%20Costa%20Lopes-1E3A8A.svg)](#authorship)
  [![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-7C3AED.svg)](https://docs.anthropic.com/en/docs/claude-code)
  [![FFmpeg](https://img.shields.io/badge/FFmpeg-8.x-007808.svg)](https://ffmpeg.org)
  [![Python](https://img.shields.io/badge/Python-3.12%2B-3776AB.svg)](https://python.org)

  **Languages:** English · [Português](README.md)

</div>

---

## What it does

You give it a video. It transcribes, cuts silences and fillers, generates subtitles, applies visual effects, optionally creates motion graphics, exports multi-format, and verifies the result before delivery. All from a single conversational instruction in Claude Code.

| Capability | Implementation |
|---|---|
| **Transcription** | Whisper local (default, offline, free) or OpenAI/ElevenLabs API |
| **Auto-cut** | Removes silences >0.5s, fillers in PT (`ahn`, `tipo`, `né`) and EN (`um`, `like`) |
| **Burned-in subtitles** | 3 ASS styles: `full`, `karaoke` (word-by-word), `highlights` |
| **LUTs and color grading** | 5 procedural LUTs (warm/cool/cinematic/bw/identity) + vignette + film grain |
| **Transitions** | 40+ via FFmpeg `xfade` (fade, slide, wipe, circleopen, dissolve...) |
| **Professional audio** | RNNoise denoise + EBU R128 normalize + compressor + music ducking |
| **16:9 → 9:16 reframe** | Face tracking via MediaPipe BlazeFace (also 1:1 and 4:5) |
| **Motion graphics** | HTML title cards and lower thirds with alpha |
| **Mandatory verification** | Boolean checklist + ≥6 frame extraction before declaring "done" |

---

## How it works

1. **Install the skill once** (instructions below).
2. **Open Claude Code in any folder** — no need to prepare directories, copy files, or create `input/`.
3. **Tell Claude what you want**:
   ```
   edit this video C:\Downloads\pitch.mp4
   ```
   Or variants:
   ```
   cut silences in D:\raw\interview.mov
   clean the audio of pitch.mp4
   Reels version of pitch.mp4
   apply cinematic look to pitch.mp4
   ```
4. **First time:** answer 7 onboarding questions (color, style, speaker position, etc.). Saved in `~/.claude/skills/videokit/styles/client-style.md`.
5. **Pipeline runs.** You see a draft + 6 extracted frames. You say `render`.
6. **You get `final.mp4`** next to the source video, inside `videokit-projects/YYYY-MM-DD_slug/renders/final/`.

---

## Installation

### Prerequisites

| Tool | What for | How to install |
|---|---|---|
| **Claude Code** | Skill runtime | [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code) |
| **FFmpeg 8.x** with libass | Video/audio pipeline | `winget install Gyan.FFmpeg` (Win) / `brew install ffmpeg` (mac) / `apt install ffmpeg` (Linux) |
| **Python 3.12+** | Transcription, cut, smart-reframe scripts | `winget install Python.Python.3.13` (Win) / `brew install python` (mac) |
| **Node.js 22+** (optional) | HyperFrames for advanced motion graphics | `winget install OpenJS.NodeJS.LTS` |

Python packages (installed on demand by the skill):
```bash
pip install openai-whisper           # local transcription (default)
pip install mediapipe opencv-python  # smart reframe 16:9 → 9:16
```

### Step 1 — Clone this repository

In any development folder of your choice:

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

### Step 2 — Link to Claude Code

The skill must be visible in `~/.claude/skills/`. Create a symbolic link (no file duplication):

**Windows (PowerShell, no admin privileges required):**
```powershell
cmd /c mklink /J "$env:USERPROFILE\.claude\skills\videokit" "$env:USERPROFILE\Documents\videokit"
```

**macOS / Linux:**
```bash
ln -s ~/Documents/videokit ~/.claude/skills/videokit
```

### Step 3 — Verify

Open Claude Code (in any folder) and ask: `what skills do you have available?` You should see `videokit` in the list.

Or via terminal:
```powershell
Test-Path "$env:USERPROFILE\.claude\skills\videokit\SKILL.md"  # True
```

### Step 4 — Environment detection (automatic on first use)

On first invocation, the skill runs `scripts/detect-env.ps1` (Windows) or `scripts/detect-env.sh` (macOS/Linux) which writes `cache/env-report.json` with FFmpeg/Python paths and available capabilities. You just need to ensure FFmpeg and Python are on PATH.

---

## How to use — step by step

### Pipeline overview

```mermaid
flowchart TD
    A[Source video<br/>e.g. C:\Downloads\pitch.mp4] --> B[Phase 0<br/>init-project<br/>creates projects/YYYY-MM-DD_slug/]
    B --> C[Phase 1<br/>transcribe.py<br/>Whisper → transcripts/clean.json]
    C --> D[Phase 2<br/>auto-cut.py<br/>EDL: silences + fillers]
    D --> E[Phase 3<br/>motion graphics plan<br/>beats_plan.json]
    E --> F[Phase 4<br/>burn subtitles<br/>+ effects + overlays]
    F --> G[renders/draft/draft.mp4<br/>+ 6 frames extracted]
    G --> H{You say 'render'?}
    H -->|Yes| I[Phase 5<br/>final render<br/>preset slow + CRF 18]
    H -->|Iterate| J[Edit EDL or beats_plan.json]
    J --> F
    I --> K[Phase 6<br/>mandatory verification<br/>checklist + frames]
    K --> L[final.mp4<br/>delivered next to source]

    style A fill:#1e3a8a,color:#fff
    style L fill:#16a34a,color:#fff
    style H fill:#f59e0b,color:#000
```

### First use — onboarding (5 minutes, once)

When invoked for the first time, the skill doesn't have your visual identity defined yet. It asks 7 questions — one at a time — and saves to `~/.claude/skills/videokit/styles/client-style.md`. This config applies to all future videos.

Example session:

> **You:** `configure videokit for my brand`
>
> **Claude:** I'll create your brand profile. First question — what's your brand's primary color? You can give hex (`#2563EB`), name (`blue`, `red`...) or `default`.
>
> **You:** `#2563EB`
>
> **Claude:** And a secondary accent color?
>
> **You:** `default`
>
> **Claude:** What editing style do you prefer? `minimalist` / `dynamic` / `corporate` / `educational` — default is `minimalist`.
>
> **You:** `dynamic`
>
> **Claude:** Where do you usually appear in the frame? `center` / `right` / `left` — default `center`.
>
> **You:** `center`
>
> **Claude:** Do you have a logo? If yes, give absolute path. If not, say `no`.
>
> **You:** `no`
>
> **Claude:** Default subtitle style: `full` / `karaoke` / `highlights` / `none`.
>
> **You:** `karaoke`
>
> **Claude:** Preferred transcriber: `Whisper local` / `OpenAI` / `ElevenLabs`. Default `Whisper local`.
>
> **You:** `Whisper local`
>
> **Claude:** Style saved. I can now edit your videos with this look. When ready, give me the video path: `edit C:\path\to\video.mp4`.

Done. You don't need to do this again.

### Typical session — full edit

Let's edit a real video. Concrete conversation:

> **You:** `edit this video C:\Downloads\ai-pitch.mp4`
>
> **Claude:** I'll create the project. Before starting:
>
> 1. Subtitle style for **this** video (default from your profile is karaoke): keep or other?
> 2. Mode: `full` (with motion graphics) or `cut-only`?
> 3. Any context I should know? (technical terms, focus, audience)
>
> **You:** `karaoke, full, it's a pitch about AI agents with terms "MCP", "embedding", "RAG"`
>
> **Claude:**
> ```
> Running detect-env.ps1...
> ffmpeg: 8.1 ✓  ffprobe ✓  Whisper installed ✓
>
> Creating C:\Downloads\videokit-projects\2026-06-03_ai-pitch\
> Source detected: 1920×1080 @ 30fps, 4m12s, 16:9
>
> Phase 1/6 — Extracting audio and transcribing (medium model, ~2min)...
> ✓ 87 segments, 1124 words (PT detected)
>
> Phase 2/6 — Analyzing for auto-cut...
> ✓ Silences detected: 23 (12.4s removed)
> ✓ Fillers detected: 41 ("tipo", "ahn", "né"...)
> ✓ Final duration: 3m26s (cut 46s, 18%)
>
> Phase 3/6 — Planning motion graphics...
> ✓ 5 beats: 1 title card + 2 lower thirds + 2 highlights
> ✓ 2 zoompan effects (at 1m12s and 2m48s)
>
> Phase 4/6 — Burning karaoke subtitles and applying overlays...
> Phase 5/6 — Generating draft (~1min, preset ultrafast)...
>
> ✓ Draft ready: C:\Downloads\videokit-projects\2026-06-03_ai-pitch\renders\draft\draft.mp4
> ✓ 6 frames extracted to verify/
>
> Check the draft and say 'render' for final, or request adjustments.
> ```
>
> **You:** *(after watching draft)* `the zoom at 2m48s is exaggerated, reduce to 1.15× and render final`
>
> **Claude:**
> ```
> Adjusting beats_plan.json.video_effects[id=vfx02].max_zoom: 1.25 → 1.15
> Regenerating from phase 4 (preset slow, ~3min)...
>
> Phase 6/6 — Verification...
> ✓ Duration: 3m26s
> ✓ Audio present (-14 LUFS)
> ✓ Codec h264, yuv420p, 1920×1080
> ✓ Subtitles synced (sampling at 0:30, 1:45, 3:00)
> ✓ Zoom at 2m48s confirmed in verify/ frames
>
> Done. Delivery:
> 📁 C:\Downloads\videokit-projects\2026-06-03_ai-pitch\renders\final\final.mp4
> ⏱️ 3m26s · 1920×1080 · 87 MB
> 📸 6 review frames in verify/
> ```

That's it. Final file next to your original source. Delete the `2026-06-03_ai-pitch/` folder when you no longer need it.

### Commands during the session

Cheatsheet of what you can say to Claude at each phase:

| When | What you say | Effect |
|---|---|---|
| **Start** | `edit C:\v.mp4` | Full pipeline `full` |
| **Start** | `cut silences in C:\v.mp4` | Mode `cut-only` |
| **Start** | `clean audio in C:\v.mp4` | Audio pack only (denoise + normalize) |
| **Start** | `Reels version of C:\v.mp4` | Smart reframe 16:9 → 9:16 |
| **Before transcribing** | `use OpenAI Whisper instead of local` | Override transcriber |
| **After draft** | `render` | Proceed to final |
| **After draft** | `looks good` | Equivalent to render |
| **After draft** | `change subtitle color to red` | Edit ASS + re-render |
| **After draft** | `remove the intro card` | Remove beat[0] and re-render |
| **After draft** | `speed up 1.1× from 1m30s` | Add setpts in beats_plan |
| **After draft** | `also 9:16 version` | Smart reframe post-final |
| **After final** | `apply cinematic look` | LUT cinematic + grade pass |

### How to iterate after first render

After the first render, visual changes are **fast** because you only re-render what changed. The skill touches only what's affected:

| Request | What changes | Extra time |
|---|---|---|
| `change subtitle color to green` | `edit/subtitles.ass` → re-burn | ~30s |
| `move lower-third from 30s to 45s` | `beats_plan.json` timestamp → recompose overlay | ~30s |
| `remove zoom at 2m48s` | `beats_plan.json.video_effects` remove → re-render base | ~1min |
| `also cut segment from 1m20s to 1m25s` | `edit/edl.json` segments_keep → re-cut → re-render | ~3min (redoes from phase 2) |
| `apply warm LUT instead of cinematic` | re-run `visual-effects.ps1 -Mode Lut` | ~1min |
| `also 9:16 version of this final` | `smart-reframe.py` post-final | ~3min (1080p, 1min source) |

The skill **warns you** when a change requires re-running earlier phases (especially cuts — downstream timestamps shift).

### Scenarios by video type

#### 1. Talking head for long-form YouTube (16:9)

```
edit C:\Videos\episode-03.mp4 with full subtitles and corporate look
```

The skill creates 16:9 1920×1080, white subtitles with black outline in safe zones, discrete lower thirds, audio normalized to -14 LUFS (YouTube target), no aggressive effects.

#### 2. Instagram Reel/Short (9:16)

```
edit C:\Videos\hook.mp4 with karaoke subtitles and Reels version
```

The skill does the pipeline in 16:9, then runs smart-reframe to 9:16 1080×1920. Large word-by-word subtitles (font-size ~110px), audio normalized to -16 LUFS (Instagram), max 2-3 words per line.

#### 3. Quick cleanup without motion graphics

```
cut silences and "ums" in C:\Videos\raw.mov, no motion graphics
```

Cut-only mode. Only EDL + concat + (optional) subtitles. No cards, no overlays. Ideal for video podcasts, long interviews, content where the cut is what matters.

#### 4. Podcast — standalone audio pack

```
clean audio in C:\Audio\episode.mp4 and normalize to -16 LUFS for podcast
```

No video pipeline. Only: RNNoise denoise + de-esser + compressor + EBU R128 to -16 LUFS (Apple Podcasts/Spotify target). Output preserves video intact (`-c:v copy`), only re-encodes audio.

#### 5. Screencast / tutorial

```
edit C:\Videos\demo.mp4, it's a code tutorial, add zoom on demos
```

Pipeline in `full` mode but with screencast profile: discrete subtitles (smaller font, bottom corner, don't cover UI), subtle zoom (1.15-1.2×) at demo moments, no side cards (UI may hide).

#### 6. Cinematic look for promo

```
edit C:\Videos\promo.mp4 with cinematic LUT, vignette, and highlights subtitles
```

Pipeline + `visual-effects.ps1 -Mode Lut cinematic.cube` + `-Mode Grade -VignetteStrength 0.4 -FilmGrain 4` + highlights subtitles on key words (numbers, percentages, emphatic words) instead of continuous subtitles.

### Where to find the result

When the skill says `Done. Delivery:` follow the indicated path. Typical structure:

```
C:\Downloads\
├── ai-pitch.mp4                                  ← your original source (intact)
└── videokit-projects\
    └── 2026-06-03_ai-pitch\
        ├── source\ai-pitch.mp4                   ← local copy
        ├── transcripts\
        │   ├── raw.json                          ← raw Whisper output
        │   └── clean.json                        ← canonical format
        ├── edit\
        │   ├── edl.json                          ← edit here to change cuts
        │   ├── subtitles.ass                     ← edit here to change subtitles
        │   └── segments\seg_001.mp4 ...          ← each cut segment
        ├── overlays\b01.mov, b02.mov, ...        ← motion graphics with alpha
        ├── renders\
        │   ├── draft\draft.mp4                   ← fast preview
        │   └── final\final.mp4                   ⬅ DELIVERY
        ├── verify\
        │   ├── frame_1.000.png                   ← control
        │   ├── frame_51.500.png                  ← middle
        │   ├── frame_peak_zoom_2m48s.png         ← effect peak
        │   └── ...                                ← ≥6 frames
        ├── cache\                                 ← temporaries (deletable)
        ├── project.json                          ← complete state
        ├── beats_plan.json                       ← motion graphics plan
        └── notes.md                              ← decisions and exceptions
```

Delete `2026-06-03_ai-pitch/` to clean up everything for that video. Your source in `Downloads\` remains intact.

### Flags via slash command (alternative to conversation)

If you prefer direct commands instead of conversation:

```
/videokit C:\v.mp4 --mode cut-only --subs karaoke
/videokit C:\v.mp4 --mode full --subs highlights
/videokit C:\v.mp4 --mode cut-only --subs none
```

`argument-hint` in SKILL.md declares: `<absolute-video-path> [--mode full|cut-only] [--subs full|karaoke|highlights|none]`.

The skill accepts both styles — flexible conversation or slash with flags. In both, you can interact during the session to iterate.

---

## Project structure

```
videokit/
├── SKILL.md                    # Manifest + main flow (read by Claude)
├── README.md                   # Portuguese version
├── README.en.md                # This file (English)
├── CHANGELOG.md                # Version history
├── CONTRIBUTING.md             # Contribution guidelines
├── .gitignore
├── reference/                  # On-demand documentation
│   ├── pipeline.md             # 6 phases (input → delivery)
│   ├── formats.md              # specs 16:9 / 9:16 / 1:1 / screencast
│   ├── onboarding.md           # first conversation
│   ├── subtitle-styles.md      # full / karaoke / highlights
│   ├── audio-pack.md           # denoise / loudnorm / ducking
│   ├── visual-effects.md       # transitions / LUTs / grading
│   ├── smart-reframe.md        # MediaPipe face tracking
│   └── lessons-learned.md      # FFmpeg 8.x, Windows, Whisper gotchas
├── scripts/                    # Cross-platform scripts
│   ├── detect-env.ps1 / .sh
│   ├── init-project.ps1 / .sh
│   ├── transcribe.py
│   ├── auto-cut.py
│   ├── burn-subtitles.ps1 / .sh
│   ├── audio-process.ps1 / .sh
│   ├── visual-effects.ps1 / .sh
│   ├── smart-reframe.py
│   ├── render.ps1 / .sh
│   ├── download-assets.ps1 / .sh
│   └── gen-luts.py
├── assets/
│   ├── icon.svg                # skill logo
│   ├── subtitle-templates/     # 3 .ass templates
│   ├── beat-templates/         # 2 HTML templates
│   ├── luts/                   # 5 procedural .cube LUTs
│   ├── audio-models/           # RNNoise .rnnn (runtime download)
│   └── face-detector/          # BlazeFace .tflite (runtime download)
└── cache/                      # env-report.json (local state, gitignored)
```

---

## Limitations

- **Cross-platform**: PowerShell (`.ps1`) for Windows and Bash (`.sh`) for macOS/Linux are both included
- **Single-pass loudnorm**: ~0.5 LUFS imprecision vs. two-pass. Acceptable for digital content.
- **Smart reframe X-only tracking**: Y is fixed. People who stand up/sit down aren't tracked vertically.
- **CPU Whisper**: ~5× real-time at 1080p with `medium` model. NVIDIA GPU accelerates 10× but requires additional setup.
- **No chroma key removal**: greenscreen needs pre-processing.

---

## Roadmap

Planned features (PRs welcome):

- [ ] **Diarization** (`pyannote-audio`) — subtitles with `Speaker 1: / Speaker 2:`
- [ ] **Subtitle translation** (`NLLB-200`) — multi-language local
- [ ] **Automatic B-roll** via Pexels API — keywords from transcript → stock videos
- [ ] **Automatic chapter markers** — YouTube chapters file
- [ ] **Local TTS** (`Piper` / `Coqui TTS`) — PT-PT / PT-BR / EN narration
- [ ] **Stable Diffusion thumbnails** — frame + title overlay automatic
- [ ] **Hook detection** — strongest first 3-5s for Reels auto-trim
- [ ] **GPU end-to-end** — NVENC + Whisper.cpp + CUDA OpenCV (10× speedup)

---

## Lessons learned (FFmpeg 8.x gotchas)

In `reference/lessons-learned.md` I document real bugs and workarounds. Examples:

- **`crop` with `t` in FFmpeg 8.x doesn't re-evaluate filter per frame** → temporal zoom freezes. Use `zoompan` with `in_time` (`d=1`).
- **`-c copy` alone in cuts desyncs AAC packets** → always `-c:a aac -b:a 192k`.
- **`subtitles` filter in Windows doesn't accept paths with `:`** → copy `.ass` to output folder and reference by name (`Push-Location`).
- **iPhone MOV multi-stream** (AAC + spatial 4ch) → `-map 0:a:0` to grab the right stereo.
- **PowerShell 5.1 treats native exe stderr as error** → `Start-Process -RedirectStandardError $file` instead of `2>&1`.

If you encounter an FFmpeg bug in a scenario not covered, open an issue or PR with the workaround.

---

## Authorship

**videokit** was conceived, architected, and developed by **Antonio Costa Lopes** in 2026.

© 2026 Antonio Costa Lopes.

This repository does not declare a public license. The code is authored by the author and subject to applicable automatic copyright (Berne Convention). For usage discussions, open an [issue](https://github.com/antoniocostalopes/video-Kit/issues).

### Third-party components

videokit is an orchestrator that invokes external tools. These tools retain their own licenses and terms of use — they are not redistributed by this repository (they are installed/downloaded locally by you or by skill helpers on first use):

- **FFmpeg** — LGPL/GPL ([ffmpeg.org/legal.html](https://ffmpeg.org/legal.html))
- **OpenAI Whisper** — MIT
- **MediaPipe BlazeFace** — Apache 2.0 (Google, `.tflite` model downloaded at runtime)
- **RNNoise** model `cb.rnnn` — Creative Commons Attribution 4.0 (CC-BY 4.0), by GregorR ([github.com/GregorR/rnnoise-models](https://github.com/GregorR/rnnoise-models)) — attribution maintained per CC-BY
- **OpenCV** — Apache 2.0

The scripts `download-assets.{ps1,sh}` and `smart-reframe.py` download models directly from official sources. The `cb.rnnn` and `blaze_face_short_range.tflite` files are `.gitignored` — they never pass through this repository.

---

<div align="center">
  <sub>Built for Claude Code · Antonio Costa Lopes · 2026</sub>
</div>
