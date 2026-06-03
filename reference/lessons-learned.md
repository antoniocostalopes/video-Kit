# Lições operacionais

Regras vindas de bugs reais. Lê antes de editar.

## FFmpeg 8.x

### Zoom temporal: `zoompan`, nunca `crop` com `t`

FFmpeg 8.x mudou a forma como filtros são avaliados por frame. `crop=w:h:x:y:t` deixou de reavaliar `t` em cada frame — o crop fica congelado no primeiro valor.

```bash
# CORRETO (FFmpeg 8.x)
-vf "zoompan=z='if(between(in_time,45.2,47.5),min(1+0.15*(in_time-45.2),1.25),1)':d=1:s=1920x1080:fps=30"

# ERRADO (zoom congela)
-vf "crop=w='iw/(1+0.1*t)':h='ih/(1+0.1*t)':x='(iw-iw/(1+0.1*t))/2':y='(ih-ih/(1+0.1*t))/2'"
```

`d=1` é crítico (1 frame por iteração), `in_time` é a variável certa (não `t`).

### Áudio em cortes: nunca `-c copy` sozinho

```bash
# CORRETO
ffmpeg -ss 12.3 -to 28.6 -i src.mp4 -c:v copy -c:a aac -b:a 192k -avoid_negative_ts make_zero out.mp4

# ERRADO (silêncio aleatório, packets AAC desincronizam)
ffmpeg -ss 12.3 -to 28.6 -i src.mp4 -c copy out.mp4
```

### MOV iPhone multi-stream

`.MOV` do iPhone tem AAC mono + spatial áudio 4ch. Sem `-map`, o ffmpeg pode pegar no spatial e perder o stereo.

```bash
# CORRETO para iPhone .MOV
ffmpeg -ss 12.3 -to 28.6 -i src.MOV -map 0:v:0 -map 0:a:0 -c:v copy -c:a aac -b:a 192k out.mp4
```

E `-ss`/`-to` **antes** de `-i` (input seeking, preciso o suficiente para corte e muito mais rápido em ficheiros longos).

### Rotação metadata

iPhone grava horizontal e adiciona `displaymatrix rotation=90/270`. Players respeitam, mas pipelines de filtros podem não. Deteta:

```bash
ffprobe -v error -select_streams v:0 -show_entries stream_side_data=rotation:stream=width,height -of json src.mp4
```

Se `rotation` for 90 ou 270:
- A resolução de display é `(height, width)` (trocadas)
- Recodifica com rotação aplicada: `-vf "transpose=1"` (90 CW) ou `-vf "transpose=2"` (90 CCW)
- Não uses `-c:v copy` se a rotação não for preservada

### `silencedetect` para validar

Sempre que recortas, valida com:
```bash
ffmpeg -i seg.mp4 -af silencedetect=noise=-30dB:d=0.5 -f null - 2>&1 | grep silence_
```

Threshold `-30dB` é razoável para voz; `-40dB` para ambientes muito silenciosos.

### `libass` indisponível

Se o ffmpeg foi compilado sem libass (raro em builds full), o filtro `subtitles` falha. Detecta com:
```bash
ffmpeg -hide_banner -filters | grep "^ T.. subtitles"
```

Fallback: renderiza legendas como PNG sequência com Pillow e composita com `overlay`.

## Whisper local

### Modelo `medium` é o sweet spot

- `tiny`/`base`: rápidos mas erram nomes próprios e termos técnicos
- `medium`: ~1.5GB RAM, melhor balanço
- `large-v3`: ~3GB RAM, melhor qualidade, lento (~3× tempo real em CPU)

Em GPU NVIDIA: `large-v3` é viável. Em CPU, `medium` é a escolha pragmática.

### Word timestamps

```python
result = model.transcribe(audio_path, word_timestamps=True, language="pt")
```

Necessário para legendas karaoke. Activa `word_timestamps=True` sempre — custo é marginal.

### Língua

Detecção automática funciona, mas explicitar `language="pt"` evita erros em vídeos curtos com palavras ambíguas. Lê do `client-style.md` ou de detecção rápida nos primeiros 30s.

### Suprimir warnings

Whisper imprime muito ruído em stderr. Em scripts:
```python
import warnings
warnings.filterwarnings("ignore", category=UserWarning)
```

## Windows / PowerShell pegadinhas

### UTF-8 sem BOM

Para JSON, ASS, e ficheiros lidos por ferramentas estritas:
```powershell
[IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
```

**Nunca** uses `Set-Content -Encoding utf8` (mete BOM, parsers ASS partem).

### Locale: vírgula vs ponto decimal

Em PT/ES, locale usa vírgula. `ffprobe` devolve `12.34`. Parsing:
```powershell
$d = [double]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)
```

### stderr de native exes

Em PowerShell 5.1, redirigir `2>&1` ou `2>$null` em executáveis nativos cria `NativeCommandError` mesmo com exit 0. Capta via `cmd`:
```powershell
$out = cmd /c "ffprobe -v error -show_entries format=duration $f 2>&1"
```

### `ffprobe -of`

Prefere `-of default=nw=1:nk=1` (não wrappers, não keys). `csv=p=0` deixa vírgula final que parte parsers.

### Variável `$Args` é reservada

Não chames variáveis `$Args` — usa `$Arguments` ou `$Params`.

### PowerShell 5.1 não tem ternário

Sem `?:`, `?.`, `??`. Usa `if/else` e checks explícitos de `$null`.

### `PYTHONIOENCODING=utf-8`

Em scripts Python que imprimem texto do transcript (acentos PT):
```powershell
$env:PYTHONIOENCODING = "utf-8"
python scripts/transcribe.py ...
```

Senão, `UnicodeEncodeError` em consoles legacy do Windows.

### `MPLCONFIGDIR`

Se algum helper Python importa Matplotlib (alguns plotters do Whisper community fazem), define para pasta escrevível:
```powershell
$env:MPLCONFIGDIR = "$ProjectDir\cache"
```

Senão tenta escrever em `~/.config/matplotlib` que pode falhar com perfis corporativos.

## ASS (legendas)

### Encoding

UTF-8 **sem BOM**. Mojibake (`Ã¡`, `Ã©`, `Ã±`) acontece quando:
- Editor guardou com BOM
- Source string já tinha encoding errado
- PowerShell `Set-Content -Encoding utf8` (mete BOM)

Sempre valida: `Get-Content -Raw <path.ass> | Select-Object -First 200` deve mostrar acentos corretos.

### `PlayResX` / `PlayResY`

Devem bater com a resolução do vídeo final. Mismatch causa legendas pequenas ou cortadas:
```ass
[Script Info]
PlayResX: 1920
PlayResY: 1080
```

Para 9:16 1080×1920: `PlayResX: 1080` / `PlayResY: 1920`.

### Karaoke sem overlap

Em ASS karaoke, cada `Dialogue:` line deve ter `Start` ≥ `End` da anterior. Sobreposição causa render duplicado e flicker.

Para palavra-a-palavra dentro de uma linha, usa `{\k<centisecs>}`:
```ass
Dialogue: 0,0:00:05.12,0:00:07.45,Karaoke,,0,0,0,,{\k22}Olá{\k15}pessoal{\k30}hoje
```

`22` = 220ms para "Olá", etc.

### Fonts em ASS

`Fontname` no `[V4+ Styles]` tem de bater com nome **instalado no sistema** (não com `font-family` CSS). Em Windows:
```powershell
Get-ChildItem -Path C:\Windows\Fonts | Where-Object Name -Match "Inter"
```

Se a fonte não está, queima falha silenciosamente (ffmpeg avisa em stderr mas continua com substituição).

### Burn vs softsubs

A skill **queima** sempre (burn-in). Razão: redes sociais (Reels/Shorts/TikTok) ignoram softsubs. Para entrega flexível, mantém também o `.ass` em `edit/` mas não anexes ao MP4.

## Verificação obrigatória

### Checklist booleano NÃO detecta tudo

Coisas que `ffprobe` não vê:
- Zoom declarado mas congelado (FFmpeg 8.x bug acima)
- Overlay com pixel format correto mas frame vazio
- Karaoke sobreposto
- Mojibake em legendas queimadas
- Cara coberta por card

Por isso a fase 6b (revisão visual) é **obrigatória**: extrair ≥6 frames e olhar.

### Frame de controlo

Inclui sempre 1 frame **fora** de qualquer efeito/legenda como controlo. Se o frame de controlo difere do `renders/edited.mp4`, há contaminação na pipeline de filtros.

### Comparar pixel a pixel

Quando o utilizador diz "o zoom não funciona": compara frame do pico do zoom com frame 2s antes. Se forem iguais, é o bug do `crop` vs `zoompan`.

## Whisper: línguas mistas

Vídeos onde o orador alterna PT/EN: Whisper pode marcar como uma única língua e errar metade. Estratégia:
- Pergunta ao utilizador a língua principal
- Se for evidente que há blocos longos em outra língua, transcreve em duas passagens com `--language` diferente e merge por timestamp

## Performance

### CPU vs GPU

Em CPU, `medium` Whisper: ~5× tempo real para 1080p. GPU NVIDIA: 0.3× tempo real (`fp16=True`).

Render FFmpeg final 1080p 30fps: `-preset slow` em CPU recente faz ~0.7× tempo real. `-preset medium` ~1.2× tempo real com perda mínima de qualidade — bom default para drafts.

### Disk space

Projeto típico de 10min em 1080p ocupa ~3GB:
- Source: ~500MB
- `cache/audio.wav` (PCM 16k): ~20MB
- `cache/base_with_effects.mp4`: ~600MB
- `overlays/*.mov` (ProRes ou PNG sequence): ~1GB
- `renders/draft/draft.mp4`: ~150MB
- `renders/final/final.mp4`: ~500MB

Limpa `cache/` no fim. `verify/` mantém-se para auditoria.
