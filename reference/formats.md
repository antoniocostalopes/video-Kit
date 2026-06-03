# Formatos e zonas seguras

Quatro perfis suportados. O perfil é detetado por aspect ratio em `project.json.media`. Em caso de ambiguidade (p.ex. 4:3), pergunta ao utilizador.

## Detecção automática

| Aspect | Perfil |
|---|---|
| 1.77 (16:9) | `youtube-long` ou `talking-head` (escolhe pelo conteúdo) |
| 0.5625 (9:16) | `reels` |
| 1.0 (1:1) | `square` |
| 1.33 (4:3) | `talking-head` legado — pergunta |
| Outro | Pergunta ao utilizador |

Screencast é detetado por heurística: fps ≥ 30, predominância de cor estática nos primeiros 5s, presença de cursor (opcional). Se incerto, pergunta.

## 16:9 — talking head / podcast / YouTube longo

- **Resolução típica**: 1920×1080 (Full HD) ou 3840×2160 (4K)
- **Posição habitual do orador**: centro ou direita (se há ecrã/cards à esquerda)
- **Zona segura central**: 80% da largura (`x: 192..1728`, `y: 108..972` em 1920×1080)
- **Lower thirds**: faixa inferior 110px de altura (em 1080p) entre `y=900` e `y=1010`
- **Cards laterais**: permitidos. Largura típica 480px, posicionados à esquerda ou direita
- **Legendas**: 1-2 linhas, max 42 chars por linha, font-size 56px em 1080p
- **Margem do orador**: nunca colocar texto sobre o terço onde está a cara (detecta posição do utilizador no `client-style.md`)

## 9:16 — Reels / Shorts / TikTok

- **Resolução típica**: 1080×1920 ou 720×1280
- **Zona segura central**: 90% da largura, 70% da altura central — UI de redes sociais ocupa topo e base
  - Topo: evita `y < 250` (header da rede)
  - Base: evita `y > 1670` (caption + botões em 1080×1920)
- **Posição do orador**: tipicamente centro-superior, deixando metade inferior para legendas
- **Legendas grandes**: font-size 80-110px em 1080×1920, 2-3 palavras por linha, **karaoke** ou **highlights** funcionam melhor que completas
- **Cards laterais**: **NÃO usar**. Espaço horizontal insuficiente
- **Lower thirds**: substituir por overlays centrais grandes
- **Title cards**: cobrem toda a largura, 30-40% da altura

## 1:1 — Instagram feed quadrado

- **Resolução típica**: 1080×1080
- **Posição do orador**: centro
- **Zona segura**: 85% × 85%
- **Legendas**: 1-2 linhas, max 30 chars, font-size 64px
- **Cards laterais**: estreitos (max 240px), só se imprescindível
- **Lower thirds**: largura total, altura 100px no fundo

## Screencast / tutorial

- **Resolução típica**: 1920×1080 ou resolução nativa do ecrã (pode ser 2560×1440, 3840×2160)
- **Posição do orador**: webcam no canto (geralmente inferior-direito ou superior-direito). Se houver, evita pôr UI por cima
- **Zona segura**: depende do conteúdo gravado. Detetar webcam (round/rect canto) e respeitar
- **Zoom em demos**: usar `zoompan` para destacar área onde clica. Max zoom 1.3× para não perder contexto
- **Anotações**: setas e highlights via overlay HTML simples ou `drawtext`/`drawbox` FFmpeg
- **Legendas**: **discretas** ou **highlights** (não tapar UI da app demonstrada). Posição: canto inferior central, font-size 48px em 1080p
- **Lower thirds**: raramente — só para introduzir secções

## Cores e contraste

Independente do formato:
- Texto sobre vídeo: usar fundo semi-transparente (`rgba(0,0,0,0.55)` mínimo) ou outline de 4-6px
- Garantir contraste WCAG AA: texto branco sobre cinza-escuro (#202020), preto sobre pastel claro
- Cores primárias do `client-style.md` para acentos (highlights de palavras, barras de progresso, lower-thirds)
- Cores secundárias para elementos de apoio (cards de fundo, separadores)

## Fonts recomendadas

Por perfil:
- **YouTube longo / talking head**: `Inter`, `Manrope`, `DM Sans` — legibilidade
- **Reels / Shorts**: `Bebas Neue`, `Anton`, `Montserrat ExtraBold` — impacto
- **Screencast**: `JetBrains Mono` para código, `Inter` para legendas
- **1:1**: igual ao 16:9

Garantir que a fonte está disponível: usar `@font-face` ou Google Fonts em HTML overlays; em ASS, embutir nome exato do ficheiro instalado no sistema (`fc-list` em Linux, `Get-ChildItem -Path C:\Windows\Fonts` em Windows).

## FPS

- Default: manter fps do source (`project.json.media.fps`)
- Quando filtros exigem fps fixo (ex.: `zoompan`), usar exatamente o do source
- Nunca subir fps artificialmente (interpolação degrada qualidade)
- Reels: 30fps é padrão; vídeos a 60fps mantêm 60 se source for 60

## Bitrate (final render)

- 1080p 30fps: 8-12 Mbps (h264 CRF 18-20)
- 1080p 60fps: 12-16 Mbps
- 4K 30fps: 35-45 Mbps (CRF 18)
- Reels 1080×1920: 10-14 Mbps

Usar CRF para qualidade constante: `-crf 18` final, `-crf 28` draft.
