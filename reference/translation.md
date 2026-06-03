# Tradução de legendas

Traduz ficheiros ASS ou SRT entre línguas usando `argostranslate` (local, offline, sem API key).

## Quando usar

- Vídeo PT → legendas EN, ES, FR, IT, DE para audiência internacional
- Multi-formato: queimar PT no vídeo principal + gerar SRT externos noutras línguas para upload em YouTube/Vimeo

## Dependências

```bash
pip install argostranslate
```

Pacotes de tradução descarregados sob demanda (~100MB cada par de línguas). Línguas comuns: `pt`, `en`, `es`, `fr`, `it`, `de`, `ru`, `ar`, `zh`, `ja`.

## Uso

```bash
# Traduz ASS PT → EN
python scripts/translate-subtitles.py \
    --input <project>/edit/subtitles.ass \
    --output <project>/edit/subtitles_en.ass \
    --from pt --to en

# SRT (deteta automaticamente pelo .ext)
python scripts/translate-subtitles.py \
    --input subs.srt --output subs_es.srt \
    --from pt --to es
```

## O que é traduzido

**Em ASS:**
- Apenas o texto visível dos blocos `Dialogue: ...`
- Preservados: timing, `{\overrides}` (cores, animações, karaoke `{\k}`), quebras de linha `\N`

**Em SRT:**
- Apenas as linhas de texto após o timing
- Preservados: índices numéricos, blocos de timing

## Output

Ficheiro novo com mesma estrutura mas texto traduzido. UTF-8 sem BOM, mantém todas as tags de formatação.

## Pares de línguas mais comuns

| Source | Targets disponíveis |
|---|---|
| `pt` | `en`, `es`, `fr`, `it`, `de`, `nl`, `ru` |
| `en` | quase todas (50+) |
| `es` | `en`, `pt`, `fr`, `it`, `de` |
| `fr` | `en`, `pt`, `es`, `de` |

Lista completa em [argosopentech.com](https://www.argosopentech.com/argospm/index/).

## Limitações

- **Qualidade**: argos-translate é decent mas não tão preciso como DeepL/Google. Para conteúdo crítico, revê manualmente.
- **Karaoke tags `{\k}`**: as palavras dentro são traduzidas individualmente, o que pode quebrar sincronização palavra-a-palavra. Tradução de karaoke fica boa só em texto contíguo, mau em word-by-word verdadeiro.
- **Termos técnicos / nomes próprios**: podem ser traduzidos quando não deviam (ex.: "Cláudia" → "Claudia"). Considera pre-processar para preservar (envolver em `{` `}`).
- **Sem context awareness**: cada Dialogue/SRT block traduzido isoladamente, sem ver os anteriores. Pronouns ambíguos podem ficar errados.

## Pipeline típico multi-língua

```bash
# 1. Pipeline normal em PT (gera subtitles.ass + queima)
# ... corre o pipeline base ...

# 2. Traduz ASS para EN, ES, FR
for lang in en es fr; do
    python scripts/translate-subtitles.py \
        --input <project>/edit/subtitles.ass \
        --output <project>/edit/subtitles_${lang}.ass \
        --from pt --to $lang
done

# 3. Para cada língua, queima OU exporta SRT
# (opcao A) queima em videos separados
# (opcao B) gera SRT para anexar ao mp4 como softsubs

# Gerar SRT a partir de ASS (com ffmpeg)
ffmpeg -i <project>/edit/subtitles.ass <project>/edit/subtitles_pt.srt
```

## Alternativas (não incluídas)

- **NLLB-200** (Meta, 200 línguas, qualidade superior, mais pesado) — `pip install transformers torch sentencepiece`
- **DeepL API** (pago mas excelente) — não funciona offline
- **Google Translate API** (pago, requer API key)

Para upgrade futuro para NLLB-200, é trivial adaptar o script — substituir a chamada `argostranslate.translate.translate()` por `transformers.pipeline("translation", model="facebook/nllb-200-distilled-600M")`.
