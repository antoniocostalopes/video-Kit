# Pack áudio profissional

Tudo FFmpeg puro (zero dependências adicionais). Modelo RNNoise descarregado automaticamente na primeira utilização (~50KB).

## Quando aplicar

Antes da fase de render final, ou logo após o corte mas antes das legendas (para o agente poder ouvir o áudio limpo se quiser validar).

A ordem canónica é:
1. **Denoise** primeiro (remove ruído de banda larga)
2. **De-ess** (sibilantes)
3. **Compressor** (dinâmica)
4. **Normalize** (loudness final)

`scripts/audio-process.ps1` aplica nesta ordem automaticamente quando passas as flags.

## Funcionalidades

### `-Denoise` — RNNoise neural

Aplica `arnndn` filter com modelo `cb.rnnn` (Conjoined Burgers, treinado para voz humana).

Remove muito bem:
- Ar condicionado / ventoinha
- Hiss de microfones baratos
- Ruído de tráfego à distância
- Eco leve de quarto não tratado

Não remove:
- Ruídos transientes fortes (porta a bater, teclado)
- Música de fundo intencional
- Ruído na mesma frequência da voz

**Modelo descarregado para** `~/.claude/skills/videokit/assets/audio-models/cb.rnnn` na primeira corrida via `download-assets.ps1`.

Outros modelos disponíveis (alternar editando `audio-process.ps1`):
- `bd.rnnn` — Beguiling Drafts (mais agressivo)
- `mp.rnnn` — Marathon Prescription (mais subtil)
- `sh.rnnn` — Somnolent Hogwash (para vozes específicas)

Repositório: github.com/GregorR/rnnoise-models (CC-BY).

### `-Normalize` — EBU R128 loudnorm

Aplica `loudnorm=I=-14:TP=-1.5:LRA=11` (single-pass).

**Parâmetro `-TargetLufs`** para plataforma específica:

| Plataforma | LUFS alvo |
|---|---|
| YouTube | `-14` (default) |
| Spotify | `-14` |
| Apple Podcasts | `-16` |
| Reels / Instagram | `-16` |
| TikTok | `-13` (mais agressivo) |
| Broadcast TV | `-23` |

Para máxima precisão usa two-pass (não automatizado aqui — primeiro corre o filter com `print_format=json`, parseia `measured_*`, depois aplica com esses valores. Single-pass é 90% tão bom).

### `-Compress` — compressor de voz

`acompressor=threshold=-18dB:ratio=2.5:attack=8:release=180:makeup=2`

Aproxima picos e vales — voz mais "presente" e consistente. Bom para vídeos onde o orador grita e depois sussurra. Não usar com compressão pesada já existente.

### `-Deess` — de-esser

`equalizer=f=7000:t=q:w=1.5:g=-3`

Atenua 3dB na zona 6-8kHz para reduzir "sssss" excessivos. Útil em microfones brilhantes ou pessoas com muita sibilância.

### `-Music <path>` — mistura com música + ducking

Mistura música de fundo com **ducking sidechain** automático: música baixa volume quando há voz, sobe entre frases.

```powershell
.\audio-process.ps1 -InputFile voz.mp4 -OutputFile final.mp4 -Music bg.mp3 -Normalize
```

**`-MusicVolume`** controla o volume base da música (0.0–1.0). Default `0.25` (~ -12dB).

Filter graph aplicado:
- Voz: filtros (denoise/comp/etc) → split em duas pistas (uma para mix, outra como sidechain trigger)
- Música: `volume` aplicado → sidechain compressor com a voz como trigger → mix com voz

Parâmetros do ducking (afinar em `audio-process.ps1` se precisares):
- `threshold=0.05` — quão alta a voz tem de estar para começar a duckar
- `ratio=20` — quanto reduzir a música quando a voz dispara
- `attack=5` — ms para começar a duckar
- `release=300` — ms para a música voltar ao volume base após silêncio da voz

## Exemplos

### Pack completo "voz limpa"
```powershell
.\audio-process.ps1 `
    -InputFile <projeto>\renders\edited.mp4 `
    -OutputFile <projeto>\renders\edited_audio.mp4 `
    -Denoise -Compress -Normalize
```

### Reels com música de fundo
```powershell
.\audio-process.ps1 `
    -InputFile voz.mp4 -Music musica.mp3 `
    -OutputFile final.mp4 `
    -Denoise -Normalize -TargetLufs -16 -MusicVolume 0.3
```

### Podcast com loudness Apple Podcasts
```powershell
.\audio-process.ps1 -InputFile raw.mp4 -OutputFile master.mp4 `
    -Denoise -Compress -Deess -Normalize -TargetLufs -16
```

## Onde encaixar no pipeline

Recomendado: entre a **fase 2 (corte)** e a **fase 4 (legendas)**. O áudio limpo torna a transcrição mais precisa se for refeita após denoise. Mas se a transcrição já está feita e está boa, podes processar áudio só depois.

Concretamente:
```
edited.mp4 (fase 2)
   ↓ audio-process.ps1 -Denoise -Normalize -Compress
edited_audio.mp4
   ↓ burn-subtitles.ps1
edited_audio_subs.mp4
   ↓ (effects/overlays)
final.mp4
```

Adiciona como flag opcional ao pipeline em `project.json.settings`:
```json
"settings": {
  "audio_pack": ["denoise", "normalize", "compress"],
  "audio_target_lufs": -14,
  "music_path": null,
  "music_volume": 0.25
}
```

## Verificação

Após processar, valida com `ffprobe` + `ebur128`:
```powershell
ffmpeg -i clean.mp4 -af ebur128 -f null - 2>&1 | Select-String "I:|LRA:|Peak:"
```

O valor `I:` deve estar dentro de ±0.5 LUFS do target.

## Limitações

- **Single-pass loudnorm** introduz pequena imprecisão (~0.5 LUFS) — aceitável para conteúdo digital
- **arnndn** com 16kHz mono é ótimo para voz; para stereo, ffmpeg aplica por canal mas pode dessincronizar — preferir mono antes de denoise
- **Sidechain ducking** com música muito densa pode soar artificial — afinar `attack`/`release` ou usar `level_sc=0.6` para reagir menos

## Não incluído (mas adicionável)

- **Stereo image widening** (haas effect / mid-side)
- **Reverb removal** (precisa modelos mais pesados, ex.: Demucs)
- **Volume curves manuais** (ducking baseado em timeline em vez de sidechain)
- **Música licenciada** (precisa cliente fornecer)
