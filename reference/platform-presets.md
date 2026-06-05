# Presets por plataforma

Em vez de o utilizador ter de lembrar `-TargetLufs -16` para Reels, `-14` para YouTube, ou quais dimensões/duração cada plataforma exige, podes passar `--preset <nome>` (ou `-Preset <nome>` em PowerShell) e o script aplica os valores corretos.

Os presets estão em `assets/platform-presets.json` e são partilhados entre `audio-process`, `render`, `smart-reframe` (à medida que vão sendo integrados).

## Presets disponíveis

| Preset | Aspect | LUFS | Máx duração | Subs default | Notas |
|---|---|---|---|---|---|
| `youtube` | 16:9 (1920×1080) | -14 | sem limite | completas | Long-form, encoder lento (CRF 18) |
| `youtube-shorts` | 9:16 (1080×1920) | -14 | 60s | karaoke | LRA mais apertado (9 vs 11) |
| `reels` | 9:16 (1080×1920) | -16 | 90s | karaoke | Loudness Instagram |
| `tiktok` | 9:16 (1080×1920) | -13 | 180s | highlights | LUFS agressivo, foco em palavras-chave |
| `podcast-video` | 16:9 (1920×1080) | -16 | sem limite | completas | LUFS Apple Podcasts |
| `linkedin` | 16:9 (1920×1080) | -14 | 600s (10min) | completas | Feed video |
| `twitter-x` | 16:9 (1280×720) | -14 | 140s | completas | 720p, encoder médio |

## Como usar

### Audio + loudness por plataforma

```powershell
# Windows
.\scripts\audio-process.ps1 `
    -InputFile <projeto>\renders\edited.mp4 `
    -OutputFile <projeto>\renders\edited_audio.mp4 `
    -Denoise -Normalize -Compress `
    -Preset reels
```

```bash
# macOS / Linux
./scripts/audio-process.sh \
    --input <projeto>/renders/edited.mp4 \
    --output <projeto>/renders/edited_audio.mp4 \
    --denoise --normalize --compress \
    --preset reels
```

`-Preset reels` substitui `-TargetLufs -14` (default) por `-16` automaticamente. Se passares ambos, o preset ganha.

### Múltiplos outputs do mesmo source

Para o mesmo vídeo, gera 3 versões — uma por plataforma:

```powershell
$variants = @("youtube","reels","tiktok")
foreach ($p in $variants) {
    .\scripts\audio-process.ps1 -InputFile $base -OutputFile "out_$p.mp4" -Denoise -Normalize -Preset $p
}
```

## Adicionar um preset custom

Edita `assets/platform-presets.json` e adiciona:

```json
"meu-cliente-x": {
  "label": "Cliente X (16:9 corporate)",
  "video": {
    "aspect_ratio": "16:9", "width": 1920, "height": 1080, "fps": 25,
    "max_duration_s": null,
    "crf_final": 20, "crf_draft": 28,
    "encoder_preset_final": "medium", "encoder_preset_draft": "ultrafast",
    "pix_fmt": "yuv420p"
  },
  "audio": { "target_lufs": -16.0, "true_peak": -1.5, "lra": 9 },
  "subtitles": { "default_style": "completas" }
}
```

Mantém o mesmo schema para os scripts continuarem a ler corretamente.

## O que **não** está nos presets (ainda)

- **LUT por plataforma**: TikTok beneficia de saturação extra, podcast prefere look natural. Adicionar `lut_default` por preset é trivial e está na roadmap.
- **Margens seguras**: cada plataforma tem zonas de UI (right rail do YouTube, hud de comentários do TikTok) que cobrem partes do frame. Fica em `reference/formats.md`.
- **Hashtag overlays / UI mockups**: fora do scope da skill — usa `assets/beat-templates/` para criar.
