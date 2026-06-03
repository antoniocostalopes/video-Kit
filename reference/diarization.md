# Diarização — quem fala quando

Identifica falantes num vídeo (`SPEAKER_00`, `SPEAKER_01`, ...). Útil em podcasts, entrevistas, mesas redondas. Integra com o transcript para legendas com etiqueta de orador.

## Quando usar

- Podcast com 2-4 falantes que se alternam
- Entrevista (anfitrião + convidado)
- Painel / mesa redonda
- Vídeos onde quereres legendas tipo `Orador 1: ...` / `Orador 2: ...`

**Não usar** em videos monólogo (talking head solo) — overhead sem ganho.

## Dependências

```bash
pip install pyannote.audio torch
```

Precisa de **HF_TOKEN** gratuito (registo em [huggingface.co](https://huggingface.co)):

1. Cria token em [hf.co/settings/tokens](https://huggingface.co/settings/tokens)
2. Aceita termos do modelo em [hf.co/pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)
3. Define `HF_TOKEN`:
   ```powershell
   $env:HF_TOKEN = "hf_xxx..."
   ```
   ```bash
   export HF_TOKEN="hf_xxx..."
   ```

Modelo descarregado ~80MB na primeira corrida.

## Uso

```bash
python scripts/diarize.py <project-dir>
```

Com hint de número de oradores (mais preciso):
```bash
python scripts/diarize.py <project-dir> --num-speakers 2
```

Range em vez de exato:
```bash
python scripts/diarize.py <project-dir> --min-speakers 2 --max-speakers 4
```

GPU (10× mais rápido):
```bash
python scripts/diarize.py <project-dir> --device cuda
```

## Output

```
<project>/transcripts/
├── diarization.json         # timeline de turns {start, end, speaker}
└── clean_diarized.json      # transcript com speaker per segment
```

Exemplo `diarization.json`:
```json
{
  "model": "pyannote/speaker-diarization-3.1",
  "num_speakers": 2,
  "speakers": ["SPEAKER_00", "SPEAKER_01"],
  "turns": [
    { "start": 0.5, "end": 4.2, "speaker": "SPEAKER_00" },
    { "start": 4.5, "end": 7.8, "speaker": "SPEAKER_01" }
  ]
}
```

Exemplo `clean_diarized.json` (extracto):
```json
{
  "language": "pt",
  "segments": [
    { "id": 0, "start": 0.5, "end": 4.2, "text": "Olá pessoal", "speaker": "SPEAKER_00" },
    { "id": 1, "start": 4.5, "end": 7.8, "text": "Bem-vindos ao podcast", "speaker": "SPEAKER_01" }
  ]
}
```

## Integração com legendas

Quando gerares legendas (`burn-subtitles`), usa `clean_diarized.json` em vez de `clean.json` e prefixa o speaker no texto:

```python
text = f"{speaker}: {segment['text']}"  # → "SPEAKER_00: Olá pessoal"
```

Ou substitui os labels genéricos por nomes reais (a skill pode perguntar ao utilizador):
```
SPEAKER_00 → João
SPEAKER_01 → Maria
```

## Performance

| Hardware | 1h podcast | 10min podcast |
|---|---|---|
| CPU recente (8 cores) | ~25min | ~4min |
| NVIDIA RTX 3060 | ~3min | ~30s |
| Apple M1/M2 (`--device mps`) | ~5min | ~50s |

## Limitações

- **Língua**: o modelo é language-agnostic mas funciona melhor em inglês. PT/ES/FR razoável; línguas raras pior.
- **Falantes muito similares**: vozes parecidas (irmãos, mesmo género/idade) podem confundir o modelo.
- **Overlapping speech**: quando dois oradores falam ao mesmo tempo, o modelo escolhe um. Performance degradada.
- **Background music**: música forte degrada a deteção. Considera correr `separate-audio.py` antes para isolar voz.

## Combinar com outros packs

**Pipeline recomendado para podcast:**
```bash
# 1. Separar voz/música (se aplicável)
python scripts/separate-audio.py --input source.mp4 --output-dir audio/stems/ --two-stems vocals

# 2. Transcrever
python scripts/transcribe.py <project-dir>

# 3. Diarizar
python scripts/diarize.py <project-dir> --num-speakers 2

# 4. Gerar ASS com speaker labels (manual ou via custom script)
# Use clean_diarized.json em vez de clean.json
```

## Não incluído

- **Identificação real de nomes** (precisa enrollment com voice samples por orador)
- **Tradução cross-língua** (modelo só identifica turns, não traduz)
- **Real-time streaming** (este script é batch)
