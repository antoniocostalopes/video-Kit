# TTS local — narração com Piper

Síntese de voz neural local (offline) via Piper. Gera narração WAV a partir de texto.

## Quando usar

- Conteúdo educativo onde o utilizador escreve script e quer voz lida
- Narração de B-roll, transições, voiceover
- Acessibilidade: descrições de áudio (audio descriptions track)
- Substituir narrador humano em vídeos automatizados

## Dependências

```bash
pip install piper-tts
```

Modelos de voz descarregados sob demanda (~50-100MB cada). Cache em `<skill>/assets/voice-models/`.

## Vozes incluídas no catálogo

| Voice ID | Língua | Género | Qualidade |
|---|---|---|---|
| `pt_PT-tugao` | PT Portugal | M | medium |
| `pt_BR-faber` | PT Brasil | M | medium |
| `pt_BR-edresson` | PT Brasil | M | low (rápido) |
| `en_US-amy` | EN US | F | medium |
| `en_US-lessac` | EN US | neutral | medium |
| `en_GB-alan` | EN UK | M | medium |
| `es_ES-davefx` | ES | M | medium |
| `fr_FR-siwis` | FR | F | medium |

Catálogo completo de Piper em [VOICES.md](https://github.com/rhasspy/piper/blob/master/VOICES.md). Para adicionar, edita `VOICE_CATALOG` em `scripts/narrate.py`.

## Uso

### Texto direto
```bash
python scripts/narrate.py \
    --text "Bem-vindo ao meu canal." \
    --output narration.wav \
    --voice pt_PT-tugao
```

### A partir de ficheiro
```bash
python scripts/narrate.py \
    --text-file script.txt \
    --output narration.wav \
    --voice en_US-amy
```

### Integração com pipeline
Combinar com `audio-process.sh` para narração + música:

```bash
# 1. Gera narração TTS
python scripts/narrate.py --text-file intro.txt --output intro.wav --voice pt_PT-tugao

# 2. Mistura com música de fundo + ducking
./scripts/audio-process.sh \
    --input intro.wav \
    --music background.mp3 \
    --output final.mp4 \
    --normalize --target-lufs -16
```

## Output

Single WAV file, mono ou stereo (depende da voz), 22050Hz (Piper default).

## Performance

| Hardware | 100 chars | 1000 chars |
|---|---|---|
| CPU recente | <1s | ~5s |
| GPU NVIDIA | <0.5s | ~2s |

Piper é otimizado para tempo real (>1× real-time em CPU).

## Limitações

- **Sem clonagem de voz** (cada voice é fixa, não personalizada)
- **Sem prosódia avançada** (sem controlo fino de ênfase, emoção, pausas customizadas)
- **PT-PT limited** — só 1 voz disponível (`tugao`, masculina)
- **Texto plain** — sem SSML support (não tags `<break>`, `<emphasis>`)
- **Frases longas** — corta automaticamente em frases; quebra natural em pontos finais

## Alternativas (não incluídas)

- **Coqui TTS** (mais flexível, suporta voice cloning, mas instalação mais complexa)
- **ElevenLabs** (cloud, pago, qualidade superior, suporta voice cloning)
- **OpenAI TTS** (cloud, pago, qualidade alta)
- **Microsoft Edge read-aloud** (via `edge-tts` package, free mas terms vagos sobre uso comercial)

## Tips

- **Frases curtas** (<200 chars) soam mais naturais. Quebra textos longos.
- **Pontuação correta** — Piper usa vírgulas e pontos para pausas. Adiciona-os para ritmo.
- **Texto especial** — números, datas, abreviaturas: escreve por extenso ("dois mil e vinte e seis" em vez de "2026") para soar natural.
- **Acentos** — UTF-8 sem BOM. Acentos têm de estar correctos no input.

## Não incluído

- **Auto-segmentação do vídeo** para narração por capítulo
- **Sincronização lip-sync** (precisa modelos diferentes tipo Wav2Lip)
- **Voice cloning** (pessoa real → voz sintética)
