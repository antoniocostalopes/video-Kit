# Pack visual — transições, LUTs, color grading

Tudo FFmpeg puro. LUTs procedurais incluídos em `assets/luts/`.

## Quando usar

- **Transições**: ao concatenar segmentos do EDL (alternativa ao concat seco), ou em pontos específicos do edit para enfatizar uma mudança de tópico
- **LUT**: aplicado depois do corte e antes do render final, dá look consistente
- **Grade**: ajustes finos de brightness/contrast/saturation + vignette + film grain

Combinar é OK: aplicar LUT primeiro, depois vignette + grain por cima.

## 1. Transições xfade

`scripts/visual-effects.ps1 -Mode Transition` junta dois clips com uma transição.

### Exemplos

```powershell
# Cross-fade simples 0.6s
.\visual-effects.ps1 -Mode Transition `
    -InputA seg_01.mp4 -InputB seg_02.mp4 `
    -OutputFile join.mp4 -Transition fade -Duration 0.6

# Slide left para mudança de tópico
.\visual-effects.ps1 -Mode Transition `
    -InputA intro.mp4 -InputB main.mp4 `
    -OutputFile flow.mp4 -Transition slideleft -Duration 0.4

# Wipe cinematográfico
.\visual-effects.ps1 -Mode Transition `
    -InputA a.mp4 -InputB b.mp4 `
    -OutputFile cut.mp4 -Transition circleopen -Duration 0.8
```

### Catálogo de transições

**Fades** (suaves, neutros):
- `fade` — cross-fade clássico
- `fadeblack` — passa por preto (corte de cena)
- `fadewhite` — flash branco (impacto)
- `dissolve` — pixel dissolve

**Wipes direcionais**:
- `wipeleft`, `wiperight`, `wipeup`, `wipedown` — varre numa direção
- `slideleft`, `slideright`, `slideup`, `slidedown` — desliza com bordas suaves
- `smoothleft`, `smoothright`, `smoothup`, `smoothdown` — slide com curva ease

**Geométricos**:
- `circleopen`, `circleclose` — círculo expande/contrai
- `circlecrop`, `rectcrop` — máscara recorta
- `horzopen`, `horzclose`, `vertopen`, `vertclose` — abertura horizontal/vertical
- `diagbl`, `diagbr`, `diagtl`, `diagtr` — varre diagonal

**Especiais**:
- `pixelize` — pixela e despixela
- `radial` — varredura radial
- `hblur` — desfoque horizontal
- `distance` — efeito de distorção

**Slices** (corte por bandas):
- `hlslice`, `hrslice` — slice horizontal esquerda/direita
- `vuslice`, `vdslice` — slice vertical cima/baixo

**Squeeze**:
- `squeezeh`, `squeezev` — comprime e expande

### Recomendações por contexto

| Contexto | Transição | Duração |
|---|---|---|
| Talking head, mudança de pergunta | `fade` | 0.4-0.6s |
| Mudança de secção em tutorial | `slideleft` | 0.5s |
| Reel/Short com energia | `circleopen` ou `wipeup` | 0.3-0.4s |
| Drama/storytelling | `fadeblack` | 0.8-1.2s |
| Demo screencast → fala | `dissolve` | 0.4s |
| Mais energia / "drop" | `radial` ou `pixelize` | 0.3s |

### Áudio em transições

`acrossfade` é aplicado automaticamente em paralelo com a transição visual, com a mesma duração. Resultado: áudio também cross-fade, sem cortes secos.

### Quando NÃO usar

- Entre segmentos do **mesmo plano** (jump cuts do mesmo orador) — usa concat seco
- Transições **>1.2s** raramente justificam-se exceto em peças narrativas
- Não acumules: 1 transição entre 2 clips, nunca encadear duas no mesmo ponto

## 2. LUTs

`scripts/visual-effects.ps1 -Mode Lut` aplica um `.cube` ao input.

### LUTs incluídos (em `assets/luts/`)

13 LUTs procedurais (gerados via `gen-luts.py`):

| LUT | Descrição | Bom para |
|---|---|---|
| `identity.cube` | sem efeito (baseline) | testes |
| `warm.cube` | golden hour, sunset | lifestyle, viagem |
| `cool.cube` | winter, tech | corporate, tecnologia |
| `cinematic.cube` | teal-orange clássico de cinema | promos, trailers |
| `bw.cube` | B&W com contraste suave | documentário |
| `pastel.cube` | tons suaves, baixa saturação | wellness, food |
| `vintage.cube` | sepia, fade nos pretos | retro, nostálgico |
| `noir.cube` | B&W alto contraste com tint azul | thriller |
| `vibrant.cube` | saturação alta + S-curve | energético, gaming |
| `faded.cube` | blacks levantados, dessaturado | Instagram filter |
| `golden-hour.cube` | quentes intensos, magic hour | contemplative |
| `teal-cool.cube` | frios saturados, modern tech | tech reviews |
| `high-contrast.cube` | bold blacks, saturação | desporto, ação |

Cada LUT ~134KB. Para regenerar (após edição de `gen-luts.py`):
```bash
python scripts/gen-luts.py
```

### Exemplos

```powershell
# Cinematic full
.\visual-effects.ps1 -Mode Lut `
    -InputFile renders/edited.mp4 `
    -OutputFile renders/graded.mp4 `
    -LutFile assets/luts/cinematic.cube

# Warm parcial (60% intensidade — mantém naturalidade)
.\visual-effects.ps1 -Mode Lut `
    -InputFile clip.mp4 -OutputFile clip_warm.mp4 `
    -LutFile assets/luts/warm.cube -LutIntensity 0.6
```

### Adicionar LUTs externos

Qualquer `.cube` 3D LUT funciona. Fontes gratuitas:
- **FreshLUTs.com** — free pack 35+ LUTs
- **RocketStock — 35 Free LUTs**
- **IWLTBAP — free starter pack**
- **Cinema Grade — free LUT vault**
- LUTs de DaVinci Resolve grátis no Reddit r/colorists

Coloca em `assets/luts/<nome>.cube` e usa `-LutFile assets/luts/<nome>.cube`.

### Verificação visual

LUTs podem **clip** sombras ou highlights se a imagem já estiver muito contrastada. Após aplicar:
1. Vê 2-3 frames de zonas escuras — sombras devem ter detalhe
2. Vê 2-3 frames de zonas claras — highlights não devem estar "queimados" puramente brancos
3. Se há clip, reduz `-LutIntensity` para 0.5-0.7

## 3. Color grade customizado (sem LUT)

`scripts/visual-effects.ps1 -Mode Grade` aplica ajustes diretos.

### Parâmetros

- `-Brightness` (-1.0 a 1.0). Default 0. `+0.05` levanta um pouco.
- `-Contrast` (0.0 a 2.0). Default 1.0. `1.15` aumenta moderadamente.
- `-Saturation` (0.0 a 3.0). Default 1.0. `1.2` mais cor, `0.8` mais desaturado.
- `-VignetteStrength` (0.0 a 1.0). Default 0. `0.4` é cinematográfico, `0.7` forte.
- `-FilmGrain` (0 a 20). Default 0. `8` é subtil, `15+` evidente.

### Exemplos

```powershell
# Look cinematográfico subtil
.\visual-effects.ps1 -Mode Grade `
    -InputFile clip.mp4 -OutputFile clip_g.mp4 `
    -Contrast 1.15 -Saturation 1.1 -VignetteStrength 0.4 -FilmGrain 6

# Talking head — só vignette para focar
.\visual-effects.ps1 -Mode Grade `
    -InputFile head.mp4 -OutputFile head_v.mp4 -VignetteStrength 0.35

# Look documentário
.\visual-effects.ps1 -Mode Grade `
    -InputFile doc.mp4 -OutputFile doc_g.mp4 `
    -Saturation 0.85 -Contrast 1.1 -FilmGrain 10
```

## Combinar LUT + Grade

Para máxima qualidade visual: LUT primeiro, depois pequeno grade por cima.

```powershell
.\visual-effects.ps1 -Mode Lut `
    -InputFile renders/edited.mp4 `
    -OutputFile cache/luted.mp4 `
    -LutFile assets/luts/cinematic.cube -LutIntensity 0.8

.\visual-effects.ps1 -Mode Grade `
    -InputFile cache/luted.mp4 `
    -OutputFile renders/final_graded.mp4 `
    -VignetteStrength 0.3 -FilmGrain 5
```

## Performance

- **Transições**: ~real-time em 1080p num CPU recente
- **LUT (lut3d filter)**: rápido, ~0.5x tempo real em 1080p
- **Grade com vignette + grain**: ~0.6x tempo real

Para drafts rápidos durante iteração, troca `-preset medium` por `-preset ultrafast` no script.

## Integração no pipeline

Sugestão: criar nova fase `4.5` no pipeline entre legendas e overlays HTML:

```
renders/edited_subs.mp4
   ↓ visual-effects.ps1 -Mode Lut (se LUT escolhido no client-style)
cache/graded.mp4
   ↓ render.ps1 -Phase effects (zoompan etc)
cache/base_with_effects.mp4
   ↓ render.ps1 -Phase overlays
renders/final/final.mp4
```

Adicionar campo opcional ao `project.json.settings`:
```json
"settings": {
  "lut": "cinematic",
  "lut_intensity": 0.8,
  "vignette": 0.3,
  "film_grain": 0
}
```

## Limitações

- `xfade` precisa que ambos os clips tenham **mesma resolução e fps** — usar `scale` + `fps` filters antes se for diferente
- `lut3d` não corrige white balance fora do range do LUT — se o source está muito subexposto, ajusta `eq` primeiro
- `noise` filter é **temporal por frame** — em vídeo H.264 muito comprimido pode ficar com bandas; preferir `crf 18` ou inferior
- Vignette é **circular fixo** — para custom (oval, deslocado), edita o filter `vignette` com mais parâmetros (`x0`, `y0`, `eval=frame`)

## Não incluído (extensível)

- **Bloom / glow** (overlay com gaussian blur composto)
- **Anamorphic lens flare** (overlay PNG com tracking)
- **Chromatic aberration** (`rgbashift` filter)
- **Halation** (highlights warmed)
- **Letterbox cinemáticos** (`pad` filter para 2.39:1)
