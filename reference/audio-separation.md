# Separação de áudio — Demucs

Separa um áudio em **vocals / drums / bass / other** usando Facebook Demucs. Útil para:

- **Remover música pré-existente** do vídeo (mantém só voz)
- **Isolar voz** para karaoke real (canto sobre instrumental)
- **Substituir música de fundo** (separa voz, mistura nova música)
- **Remixar** podcast (isolar vocals + drums + bass + other para mistura customizada)

## Dependências

```bash
pip install demucs torch torchaudio
```

PyTorch CPU é suficiente. Para GPU (10× mais rápido), instala com CUDA: ver [pytorch.org/get-started](https://pytorch.org/get-started/locally/).

Modelo descarregado ~1-2GB na primeira corrida (cached em `~/.cache/torch/hub/`).

## Uso

### Separação completa (4 stems)
```bash
python scripts/separate-audio.py \
    --input <project>/source/video.mp4 \
    --output-dir <project>/audio/stems/
```

Gera:
```
<project>/audio/stems/
├── vocals.wav    # voz isolada
├── drums.wav     # bateria
├── bass.wav      # baixo
└── other.wav     # outros instrumentos / sintetizadores
```

### Two-stems (mais rápido, ~2× speedup)
```bash
python scripts/separate-audio.py \
    --input source.mp4 \
    --output-dir audio/stems/ \
    --two-stems vocals
```

Gera apenas:
- `vocals.wav` — voz
- `no_vocals.wav` — tudo o resto (instrumental)

Modos two-stems disponíveis: `vocals`, `drums`, `bass`, `other`.

### GPU
```bash
python scripts/separate-audio.py --input X --output-dir Y --device cuda  # NVIDIA
python scripts/separate-audio.py --input X --output-dir Y --device mps   # Apple Silicon
```

## Modelos disponíveis

| Model | Quality | Speed | RAM |
|---|---|---|---|
| `htdemucs_ft` (default) | Best | Slow | ~4GB |
| `htdemucs` | Very good | Fast | ~2GB |
| `mdx_extra_q` | Alternative | Medium | ~3GB |

Para mudar, usa `--model htdemucs`.

## Performance

| Hardware | 3min track | 30min podcast |
|---|---|---|
| CPU recente (8 cores) | ~10min | ~90min |
| NVIDIA RTX 3060 | ~1.5min | ~12min |
| Apple M1/M2 (mps) | ~3min | ~25min |

## Casos de uso

### Caso 1: remover música stock de vídeo
```bash
# Separa, fica só com voz
python scripts/separate-audio.py \
    --input source.mp4 --output-dir cache/stems/ \
    --two-stems vocals

# Mistura voz com vídeo (sem música)
ffmpeg -i source.mp4 -i cache/stems/vocals.wav \
    -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k cleaned.mp4
```

### Caso 2: substituir música de fundo
```bash
# Separa
python scripts/separate-audio.py \
    --input source.mp4 --output-dir cache/stems/ --two-stems vocals

# Mistura voz + nova música via audio-process com ducking
./scripts/audio-process.sh \
    --input cache/stems/vocals.wav \
    --music new_song.mp3 \
    --music-volume 0.3 \
    --output mixed.wav --normalize
```

### Caso 3: karaoke real (instrumental para sing-along)
```bash
# Extrai instrumental (no_vocals)
python scripts/separate-audio.py \
    --input music_video.mp4 --output-dir karaoke/ --two-stems vocals

# karaoke/no_vocals.wav agora pode ser usado como base de karaoke
```

## Limitações

- **Vozes baixas em mix denso**: Demucs separa razoavelmente, mas vozes ténues em produções comerciais ficam com artefactos.
- **Background vocals / coros**: tratados como `vocals` (não isolados separadamente).
- **Voz e instrumentos na mesma banda**: separação imperfeita (ex.: saxofone melódico pode parecer voz).
- **Tempo**: real-time impossível em CPU. Pensa em batch / offline.
- **Disk space**: stems são WAV não comprimidos (~10MB/min). Limpa depois de usar.

## Tips

- **Source quality matters**: mixagem stereo bem separada → resultados muito melhores que mono ou mixagem comprimida.
- **Pre-normalize**: se source é muito quiet, normalize antes (`ffmpeg -af loudnorm`) para Demucs ter mais sinal.
- **Two-stems = melhor para uso prático**: poucas vezes precisas dos 4 stems. `--two-stems vocals` é 2× rápido e suficiente para 80% dos casos.

## Não incluído

- **Análise de stems** (BPM, key, energy levels) — usar `librosa` separadamente
- **Re-mixagem automática** (Demucs separa, mas remix é decisão humana)
- **Stem isolation interativa** (UI para ajustar)
