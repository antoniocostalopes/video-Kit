# Smart reframe 16:9 → 9:16

Converte vídeo horizontal em vertical (ou quadrado / 4:5) seguindo o orador automaticamente via deteção de cara.

## Dependências

```powershell
pip install mediapipe opencv-python
```

MediaPipe (Google, Apache 2.0) faz a deteção de cara; OpenCV faz I/O de frames; ffmpeg encoda o output.

A primeira corrida descarrega o modelo MediaPipe (~10MB). Sem internet o pip install falha — instala com rede.

## Como funciona

1. **Pass 1 — detetar caras** (~6Hz, configurável)
   - Sample a cada N frames (default 5) para velocidade
   - Para cada sample, MediaPipe devolve bounding box da cara mais confidente
   - Entre samples, mantém última posição conhecida

2. **Smoothing** com moving average (janela 15 frames default)
   - Evita "jitter" quando a cara se mexe ligeiramente
   - Janela maior = mais estável mas reage tarde a movimento real

3. **Pass 2 — render**
   - Cada frame é decodificado, croppado (X varia, Y fixo), redimensionado e enviado para `ffmpeg` via pipe stdin
   - ffmpeg encoda h264 com áudio do source original

## Uso básico

```powershell
python scripts\smart-reframe.py `
    --input <projeto>\renders\final\final.mp4 `
    --output <projeto>\renders\final\final_vertical.mp4
```

Default: 9:16 1080×1920.

## Parâmetros

### `--target-aspect`

- `9:16` (default) — output 1080×1920, ideal Reels/Shorts/TikTok
- `1:1` — output 1080×1080, Instagram feed
- `4:5` — output 1080×1350, formato recomendado feed Instagram (ocupa mais ecrã)

### `--sample-rate N`

Detetar cara a cada N frames. Default 5 (~6Hz em 30fps source).

- N=1: deteção todos os frames. Mais preciso mas 5× mais lento. Útil se há movimento muito rápido.
- N=5 (default): bom compromisso.
- N=10: rápido. OK se o orador está quase parado.

### `--smooth-window K`

Janela do moving average. Default 15 frames (~0.5s em 30fps).

- K pequeno (5-9): segue movimento de perto mas pode tremer
- K=15 (default): suave para talking head típico
- K=30+: muito estável, reage tarde a mudanças (bom para conteúdo onde o orador se desloca pouco)

### `--vertical-offset` (-1 a 1)

Desloca verticalmente o crop estaticamente (usado só com `--vertical-tracking` OFF):
- `0` (default): centrado verticalmente
- `-0.5`: empurra para cima (útil quando a cara está no terço superior — talking head típico)
- `0.5`: empurra para baixo (útil quando a cara está no terço inferior)

Cálculo: offset multiplica `crop_h / 4` em pixels, somado a `(src_h - crop_h) / 2`.

### `--vertical-tracking` (flag, novo)

Ativa tracking dinâmico de Y (a cara é seguida verticalmente além de horizontalmente). Útil quando o orador:
- Se levanta / senta durante o vídeo
- Se inclina muito (head movement vertical)
- Mexe-se entre dois pontos no enquadramento

Quando ativo, `--vertical-offset` é ignorado (a posição é calculada dinamicamente). A janela de smoothing aplica-se também a Y.

### `--face-position` (com `--vertical-tracking`)

Onde colocar a cara dentro do crop quando vertical tracking está ON:
- `upper-third` (default) — terço superior do crop. Bom para talking head (espaço para legendas/conteúdo)
- `center` — meio do crop
- `two-thirds` — dois terços abaixo (raro, mas útil para conteúdo onde a cara aparece em pé)

Implementação: face center y é colocada em `crop_h * face_target_y_frac` do topo do crop.

## Casos de uso

### Talking head 1920×1080 → Reels
```powershell
python scripts\smart-reframe.py `
    --input talking.mp4 --output talking_reel.mp4 `
    --target-aspect 9:16 --vertical-offset -0.3
```

Offset negativo porque a cara em talking heads costuma estar no terço superior.

### Podcast com 2 oradores (cuidado)
Se há corte entre orador A e B, o tracking salta entre os dois. Pode aparecer "swooshing" de câmara virtual.

Solução: aumentar `--smooth-window 30` para evitar saltos rápidos, ou processar segmentos separados.

### Screencast → Reels
Não usa cara — o orador está no canto. Usar crop manual com FFmpeg em vez de smart-reframe:
```powershell
ffmpeg -i src.mp4 -vf "crop=608:1080:656:0,scale=1080:1920" -c:a copy out.mp4
```

### Tutorial com webcam canto inferior direito
A cara da webcam vai dominar a deteção. Resultado: crop persegue a webcam pequena no canto.

Soluções:
1. Usar `--vertical-offset 0.5` para baixar o crop até à webcam
2. Crop manual focado no conteúdo principal (não na cara)

## Performance

Em CPU recente:
- 1080p 30fps, 1min, sample-rate=5: ~3-5min (Pass 1 detect ~30s, Pass 2 render ~3min)
- 1080p 30fps, 1min, sample-rate=1: ~10min
- 4K source: ~2× mais lento

Em GPU (não suportado por mediapipe directamente neste script): teria de migrar para `cv2.dnn` com modelo OpenCV ou usar `mediapipe` com GPU build (complexo em Windows).

Para acelerar:
- Aumenta `--sample-rate` (menos deteções)
- Reduz resolução do source antes (`-vf scale=1280:720` no ffmpeg)
- Aumenta `--smooth-window` (não acelera mas dá mais margem para erros de deteção)

## Limitações

- **Tracking só X**: o Y é fixo (centro com offset). Pessoas que se levantam/sentam não são tracked verticalmente. Razão: complexidade vs. ganho — para talking head típico não compensa.
- **Múltiplas caras**: usa a mais confidente. Em entrevistas com duas pessoas, pode "saltar".
- **Cara escondida momentaneamente** (mão na cara, virar de costas): mantém última posição. Aparece "stuck" até voltar a detetar.
- **Iluminação muito baixa**: deteção falha → crop fica centrado/última posição.
- **No-audio source**: o `-map 1:a?` salta áudio (`?` torna o mapping opcional). Output não terá áudio.

## Integração com o pipeline

Depois do `final.mp4` ser gerado, podes invocar smart-reframe para uma segunda entrega vertical sem reprocessar tudo:

```
renders/final/final.mp4       # 16:9 entrega principal
   ↓ smart-reframe.py --target-aspect 9:16
renders/final/final_reels.mp4 # 9:16 para Reels/Shorts
   ↓ smart-reframe.py --target-aspect 1:1
renders/final/final_square.mp4 # 1:1 para feed
```

Ou em modo `cut-only` + smart-reframe pós-corte para output multi-formato sem motion graphics.

Registar em `project.json.renders` os outputs adicionais:
```json
"renders": {
  "final": "renders/final/final.mp4",
  "vertical": "renders/final/final_reels.mp4",
  "square": "renders/final/final_square.mp4"
}
```

## Extensões futuras

- **Tracking vertical** (cara que se desloca verticalmente)
- **Zoom dinâmico** (close-up automático em momentos de ênfase)
- **Deteção de pose** (mãos, gestos) para framing mais inteligente
- **Lookahead** (smoothing bidirecional centrado, em vez de causal)
- **Múltiplas caras com switching** (em conversas, alterna entre oradores baseado em quem está a falar — combinaria com diarização do pyannote)
