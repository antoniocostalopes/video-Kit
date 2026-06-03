# Estilos de legendas

Quatro modos: `completas | karaoke | highlights | sem`.

## Como escolher

| Caso | Estilo recomendado |
|---|---|
| YouTube longo (16:9, conteúdo educativo) | `completas` |
| Podcast com vídeo | `completas` ou `sem` |
| Reels / Shorts (9:16) | `karaoke` ou `highlights` |
| Anúncio com hook forte | `highlights` (palavras-chave grandes) |
| Tutorial / screencast | `discretas` (variante de `completas` com font menor) |
| Cliente quer impacto máximo | `karaoke` |

## `completas`

**Quando**: o utilizador quer toda a fala legível, sem ginástica visual.

**Layout**: 1-2 linhas, centradas em baixo (16:9, 1:1) ou no terço inferior (9:16).

**Font-size**:
- 1920×1080: 56-64px
- 1080×1080: 56-72px
- 1080×1920: 72-90px (mais agressivo em vertical)

**Cor**: branco com outline preto 4-6px. Sombra suave opcional.

**Chunking**:
- Max 42 chars por linha em 16:9
- Max 30 chars em 1:1
- Max 18 chars por linha em 9:16

**Timing**: cada `Dialogue:` ASS dura 2-4s. Quebra em final de frase ou pausa natural.

**Cor de destaque**: opcional. Cor principal do `client-style.md` em palavras-chave (números, nomes próprios).

Template: `assets/subtitle-templates/full.ass`.

## `karaoke` (word-by-word)

**Quando**: vídeos sociais (Reels, Shorts, TikTok), conteúdo que se ouve com som ligado, ritmo dinâmico.

**Layout**: bloco de 2-3 palavras visível por vez, palavra atual destacada em cor.

**Implementação ASS**:
```ass
Dialogue: 0,0:00:05.12,0:00:07.45,Karaoke,,0,0,0,,{\k22}Olá{\k15}pessoal{\k30}hoje{\k20}vamos{\k25}falar
```

Cada `{\k<centisecs>}` é o tempo até a próxima palavra. Total deve bater com `(End - Start)`.

**Font-size grande**: 90-110px em 1080×1920. Impacto.

**Cor de destaque**: cor principal do `client-style.md`. Default `#FFD700` (dourado) se não houver preferência.

**Pegadinhas**:
- Sem sobreposição entre `Dialogue:` lines (`Start[i+1]` ≥ `End[i]`)
- Word timestamps do Whisper têm de estar disponíveis (`word_timestamps=True`)
- Em PT, palavras com acento (`á`, `ção`) — ASS em UTF-8 sem BOM, senão mojibake

Template: `assets/subtitle-templates/karaoke.ass`.

## `highlights`

**Quando**: só o essencial. Funciona bem em anúncios, hooks, "data points" (estatísticas, números).

**Layout**: palavra ou frase curta (1-5 palavras) muito grande, centrada. Aparece e desaparece nos momentos certos.

**Detecção de highlights**:
- Números e percentagens (`50%`, `3x mais`, `10 milhões`)
- Nomes próprios mencionados pela primeira vez
- Palavras enfáticas detectadas por análise: `"nunca"`, `"sempre"`, `"tudo"`, `"impossível"`, etc.
- Verbo + objeto curto em frases curtas

Se incerto, o auto-cut.py marca candidatos e o LLM filtra os 8-12 melhores.

**Font-size**: gigante. 120-180px em 1080×1920. Em 1920×1080: 90-120px.

**Animação**: fade-in 100ms, fade-out 150ms, ou pop-in com scale 0.9→1.0.

**Cor**: cor principal sobre branco, ou branco sobre cor principal. Outline forte.

Template: `assets/subtitle-templates/highlights.ass`.

## `sem`

**Quando**: o orador é claro, áudio limpo, contexto consome legendas. Tutorial em PT para audiência PT, podcast com legendas externas (CC/SRT na plataforma).

**Implementação**: salta a fase 4a. Continua para 4b (efeitos) e 4c (overlays motion graphics) se modo `full`.

**Mantém o `.ass` em `edit/`**: mesmo sem queimar, gerar é cheap. Útil para anexar como SRT/VTT à plataforma depois (YouTube CC, etc.).

## Combinações

Em alguns casos faz sentido **misturar**:
- `completas` + `highlights` para palavras-chave: legenda base completa, mas overlays maiores em pontos específicos
- `karaoke` + lower thirds: karaoke para fala, lower third para nome do orador no início

Quando misturas, gera dois ficheiros ASS e queima em duas passagens FFmpeg (uma após a outra). Performance: ~2× tempo de uma passagem.

## Tuning depois do primeiro render

Se o utilizador disser:
- "muito grandes": reduzir font-size 10-15%
- "muito apinhadas": cortar para max 2 palavras menos por linha
- "estão a tapar a cara": subir `MarginV` em ASS (`+80` em 1080p)
- "não vejo o destaque": verificar contraste — se cor de destaque é clara sobre branco, mudar
- "mojibake": refazer ASS com UTF-8 sem BOM (ver `lessons-learned.md`)
