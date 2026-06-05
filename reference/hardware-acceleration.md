# Hardware acceleration (NVENC / VideoToolbox / QSV / AMF)

Em vídeos longos (>20min) ou batches grandes, o encode software (`libx264 -preset slow`) é o passo mais lento — pode demorar mais que o vídeo a tocar. Usar o encoder da GPU corta esse tempo em 5–10×.

A skill suporta 4 encoders HW + fallback software:

| Encoder | Hardware | Plataforma |
|---|---|---|
| **NVENC** | GeForce GTX 600+ / Quadro / Tesla | Windows + Linux |
| **VideoToolbox** | Apple Silicon (M1+) ou Mac com GPU dedicada | macOS |
| **Intel QSV** | CPU Intel com Quick Sync (6ª gen+) | Windows + Linux |
| **AMD AMF** | Radeon RX 400+ | Windows |
| **libx264** | qualquer CPU | todas |

## Como ativar

Adiciona `--hwaccel <modo>` (ou `-Hwaccel <modo>` em PowerShell) a `render`:

```powershell
# Auto-deteta o melhor disponível
.\scripts\render.ps1 -ProjectDir <proj> -Phase all -Quality final -Hwaccel auto

# Força NVENC explicitamente
.\scripts\render.ps1 -ProjectDir <proj> -Phase all -Quality final -Hwaccel nvenc

# Apple Silicon
./scripts/render.sh --project-dir <proj> --phase all --quality final --hwaccel videotoolbox

# Sem HW (default) — máxima qualidade per-bitrate
./scripts/render.sh --project-dir <proj> --phase all --quality final --hwaccel none
```

`detect-env.{ps1,sh}` deteta o que está disponível e escreve em `cache/env-report.json`:

```json
"hw_encoders": {
  "nvenc": true,
  "videotoolbox": false,
  "qsv": true,
  "amf": false
}
```

Se passas `--hwaccel nvenc` num sistema sem NVENC, a skill avisa e cai para `libx264` (não falha).

## Quando usar (e quando não)

| Caso | Recomendação |
|---|---|
| Vídeo curto (<5min), 1× | `none` (libx264 slow) — qualidade > velocidade |
| Vídeo longo (>20min) | `auto` (HW se disponível) — corta 80% do tempo |
| Batch de 10+ vídeos | `auto` — total time matters |
| Material já comprimido (TikTok/Reels download) | `none` — HW perde mais qualidade visível |
| Material limpo (RAW, ProRes) | `auto` — pouco compromisso de qualidade |
| Preview/draft | qualquer um — `--quality draft` já usa preset rápido |

**Regra prática**: a 1080p 30fps, NVENC produz ~5% pior qualidade percetual que libx264 com o mesmo bitrate. Em vídeo de marketing/educação não se nota. Em colorgraded cinematic com gradients suaves, nota-se banding leve em alturas escuras.

## O que está mapeado

Ver tabela completa com `python scripts/hwaccel.py --list`:

```
=== quality=final ===
  ✓ --hwaccel none         : -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart
  ✓ --hwaccel nvenc        : -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 19 -b:v 0 ...
  ✗ --hwaccel videotoolbox : -c:v h264_videotoolbox -q:v 65 ...
  ✓ --hwaccel qsv          : -c:v h264_qsv -preset veryslow -global_quality 20 ...
  ✗ --hwaccel amf          : -c:v h264_amf -quality quality -rc vbr_peak -qp_i 19 -qp_p 21 ...

=== quality=draft ===
  ✓ --hwaccel none         : -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p
  ✓ --hwaccel nvenc        : -c:v h264_nvenc -preset p1 -rc vbr -cq 30 -b:v 0 -pix_fmt yuv420p
  ...
```

(✓ = disponível neste sistema, ✗ = sem hardware)

## Tuning fino

Os defaults estão calibrados para "boa qualidade default". Para casos específicos:

### NVENC mais lento mas melhor (preset p7 → mantém)
Já está em `p7`, o mais lento da gama NVENC. Para forçar 2-pass:

```bash
# Edit hwaccel.py linha "nvenc" final:
"-c:v", "h264_nvenc", "-preset", "p7", "-tune", "hq",
"-rc", "vbr", "-multipass", "qres",   # ← add this
"-cq", "19", "-b:v", "0", ...
```

### VideoToolbox quality knob
`-q:v 65` ≈ libx264 CRF 19. Sobe para 75 = melhor qualidade, ficheiro maior. Desce para 55 = pior, ficheiro menor.

### Forçar bitrate fixo em vez de quality
Para upload a plataforma que exige bitrate específico (ex.: ATSC):

```bash
ffmpeg ... -c:v h264_nvenc -b:v 8M -maxrate 10M -bufsize 16M ...
```

Não está exposto em CLI — edita `hwaccel.py` para o teu caso.

## Detalhes técnicos

### NVENC presets P1–P7
- `p1` = mais rápido (~10× tempo real), mais bits para mesma qualidade
- `p7` = mais lento (~2-3× tempo real em GPU média), eficiência próxima de libx264 medium
- A skill usa `p7` para final e `p1` para draft

### QSV `-global_quality`
Equivalente a CRF. 0 = lossless, 51 = pior. A skill usa 20 (final) / 30 (draft).

### VideoToolbox `-q:v`
Escala 0–100. 65 ≈ CRF 18 visualmente. Não tem preset — VT decide internamente.

### AMF `-quality`
- `quality` = best per byte
- `balanced` = default
- `speed` = fastest

## Limitações

- **Só vídeo, não filtros**: `subtitles=`, `lut3d=`, `zoompan=` ainda correm em CPU. Numa pipeline com legendas + LUT + overlays, o ganho do HW encoder fica diluído (~2-3× em vez de 5-10×).
- **Quality não é idêntica**: ao mesmo ficheiro size, libx264 -preset slow ganha sempre. Se entregares para arquivo / cliente exigente, usa `none`.
- **NVENC tem limite de sessões concorrentes**: GeForce consumer (gaming GPUs) limita a 3-8 streams paralelos. Em batch nunca és bloqueado porque a queue é sequencial.
- **VideoToolbox H.264 só** (no estado atual da skill): HEVC/AV1 são suportados em `videotoolbox` mas a skill não os expõe. Edita `hwaccel.py` se precisares (`hevc_videotoolbox`).
- **Sem AV1**: nenhum dos modos atuais usa AV1. Em GPUs Ada Lovelace+ (RTX 40+) o NVENC suporta AV1; pode ser adicionado.
- **HW na fase `cut`**: os recortes per-segmento usam `libx264 -preset fast` independentemente do `--hwaccel` — porque o overhead de inicializar NVENC por cada segmento curto anula o ganho.
