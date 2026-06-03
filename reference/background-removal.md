# Background removal — sem greenscreen

Remove fundo de vídeos frame-a-frame usando `rembg` (modelo U²-Net). Funciona em vídeos normais — não precisa de chroma key.

## Modos

| Mode | O que faz | Use case |
|---|---|---|
| `alpha` | Output MOV ProRes 4444 com alpha channel | Compositing avançado em editor, overlay sobre outro vídeo |
| `replace` | Substitui fundo por imagem ou cor sólida | Background virtual estilo Zoom |
| `blur` | Aplica gaussian blur ao fundo | Look "webcam profissional", isola o orador |

## Dependências

```bash
pip install rembg opencv-python pillow
```

Modelo descarregado ~170MB na primeira corrida (cache em `~/.u2net/`).

## Uso

### Blur do fundo (mais comum)
```bash
python scripts/remove-bg.py \
    --input video.mp4 \
    --output video_blur.mp4 \
    --mode blur \
    --blur-strength 25
```

`--blur-strength`: 1-99, default 25. `15` é subtil, `35` é forte. Tem de ser ímpar (auto-ajustado).

### Substituir fundo por imagem
```bash
python scripts/remove-bg.py \
    --input video.mp4 \
    --output video_bg.mp4 \
    --mode replace \
    --bg-image background.jpg
```

A imagem é automaticamente redimensionada para o tamanho do vídeo. Funciona melhor com imagens de mesma proporção que o source.

### Substituir por cor sólida
```bash
python scripts/remove-bg.py \
    --input video.mp4 \
    --output video_solid.mp4 \
    --mode replace \
    --bg-color "#1E3A8A"
```

### Alpha channel para compositing
```bash
python scripts/remove-bg.py \
    --input video.mp4 \
    --output video_alpha.mov \
    --mode alpha
```

Output `.mov` ProRes 4444 (`yuva444p10le`) com alpha channel. Composita depois com FFmpeg ou em editor profissional:

```bash
ffmpeg -i background.mp4 -i video_alpha.mov \
    -filter_complex "[0:v][1:v]overlay=0:0[v]" \
    -map "[v]" -map 0:a output.mp4
```

## Modelos disponíveis

| Model | Quality | Speed |
|---|---|---|
| `u2net` (default) | Best | Medium |
| `u2netp` | Good | Fast (~2×) |
| `u2net_human_seg` | Optimized for people | Medium |
| `silueta` | Alternative | Medium |

Para mudar: `--model u2netp` etc.

## Performance optimization

`--sample-rate N`: processa 1 em cada N frames (reusa a máscara). Default 1 (todos os frames).

- `N=1`: máxima qualidade, mais lento
- `N=2-3`: bom compromisso para vídeos estáticos (talking head)
- `N=5+`: rápido mas pode ter "saltos" se a pessoa se mexer

| Setting | 1080p 30fps 1min |
|---|---|
| `--sample-rate 1` | ~5min |
| `--sample-rate 3` | ~2min |
| `--sample-rate 5` | ~1.5min |

## Limitações

- **Bordas suaves** — modelos U²-Net produzem alpha hard. Para borda suave (cabelo, fibras), precisas de modelos mais avançados (BackgroundMattingV2 ou MODNet).
- **Detalhes finos** — óculos, brincos, fios microfone às vezes recortados incorretamente.
- **Múltiplas pessoas** — o modelo isola "primeiro plano humano" no geral. Não distingue pessoa A de pessoa B.
- **Movimento rápido** — saltos podem dar "tearing" na borda entre frames. Mitiga com `--sample-rate 1`.
- **Iluminação extrema** — muito escuro ou muito claro degrada deteção.

## Casos de uso típicos

### Webcam look (talking head)
```bash
python scripts/remove-bg.py \
    --input talking.mp4 --output talking_pro.mp4 \
    --mode blur --blur-strength 25 --sample-rate 2
```

### Background corporate
```bash
python scripts/remove-bg.py \
    --input talking.mp4 --output talking_corp.mp4 \
    --mode replace --bg-image office_bg.jpg --sample-rate 1
```

### Para compositing em After Effects / DaVinci
```bash
python scripts/remove-bg.py \
    --input source.mp4 --output source_alpha.mov \
    --mode alpha --sample-rate 1
```

## Pipeline videokit típico

Adicionar como fase pós-render (depois de `final.mp4` ou em vez dele):

```
source.mp4
   ↓ pipeline normal (cut, subs, etc)
final.mp4
   ↓ remove-bg.py --mode blur
final_no_bg.mp4
```

Ou usar antes do pipeline (substitui fundo do source, depois corre pipeline normal sobre o video processado):

```
source.mp4
   ↓ remove-bg.py --mode replace --bg-image office.jpg
source_with_office_bg.mp4
   ↓ pipeline normal
final.mp4
```

## Não incluído

- **Real-time webcam** (este é offline batch; para tempo real ver BackgroundMattingV2-Mobile ou MediaPipe Selfie Segmentation)
- **Edge refinement** (modelos mais avançados como `ModNet` ou `Robust Video Matting`)
- **Manual mask painting** (precisa UI)
