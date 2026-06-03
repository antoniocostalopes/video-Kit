# Primeira conversa — onboarding

A skill exige `~/.claude/skills/videokit/styles/client-style.md` antes de editar. Se não existir, faz onboarding **antes** de qualquer pipeline.

Este ficheiro vive **dentro da skill** (uma vez por utilizador), não na pasta de trabalho. Aplica-se a todos os vídeos.

## Regras da conversa

- **Uma pergunta de cada vez**. Não atires lista numerada.
- Sugere defaults razoáveis (com `(default: X)` na pergunta) para o utilizador poder dizer "default" e avançar.
- Aceita "qualquer", "tu escolhes" — usa o default e regista que foi auto-decidido.
- Quando o utilizador disser cor por nome (ex.: "azul"), converte para hex razoável (`#2563EB` por exemplo) e mostra.
- Não pergunes sobre coisas que dá para inferir (resolução, fps — vem de `ffprobe`).

## Perguntas (ordem)

### 1. Cor principal
```
Qual a cor principal da tua marca? Podes dar o hex, o nome (azul, vermelho...) ou "default" para usar #2563EB.
```

### 2. Cor secundária
```
E uma cor secundária para acentos? Podes dar hex, nome ou "default" para usar um neutro compatível (#0F172A escuro / #F8FAFC claro).
```

### 3. Estilo de edição
```
Que estilo de edição preferes?
- minimalista (pouco motion, transições limpas)
- dinâmico (mais cortes, jumps, energia)
- corporativo (formal, lower thirds, transições suaves)
- educativo (didático, zooms em demos, anotações claras)
Default: minimalista
```

### 4. Posição habitual do orador
```
Onde costumas aparecer no enquadramento?
- centro
- direita
- esquerda
Default: centro
```

### 5. Logo (opcional)
```
Tens logo? Se sim, indica o caminho absoluto para o PNG (transparente, preferido).
A skill copia para ~/.claude/skills/videokit/brand/logo/ e usa em todos os vídeos.
Senão diz "não".
```

### 6. Estilo de legendas default
```
Estilo de legendas para os teus vídeos por defeito?
- completas (1-2 linhas com toda a frase)
- karaoke (palavra a palavra, realçada à medida que é dita)
- highlights (só palavras-chave grandes)
- sem (não queres legendas por defeito)
Default: completas
```

### 7. Transcritor
```
Que transcritor preferes?
- Whisper local (gratuito, offline, ~1GB de modelo na primeira corrida)
- OpenAI Whisper API (rápido, pago, precisa OPENAI_API_KEY)
- ElevenLabs (preciso, pago, precisa ELEVENLABS_API_KEY)
Default: Whisper local
```

## Output: `~/.claude/skills/videokit/styles/client-style.md`

Depois das 7 respostas, escreve em `~/.claude/skills/videokit/styles/client-style.md` (UTF-8 sem BOM). Em Windows, esse path resolve para `C:\Users\<user>\.claude\skills\videokit\styles\client-style.md`. Cria a pasta `styles/` dentro da skill se não existir.

```markdown
# Estilo do cliente

## Identidade visual
- **Cor principal**: #2563EB
- **Cor secundária**: #0F172A
- **Logo**: brand/logo/marca.png (ou: nenhum)

## Edição
- **Estilo**: dinâmico
- **Posição do orador**: centro

## Legendas
- **Estilo default**: karaoke
- **Cor texto**: branco com outline #0F172A
- **Cor destaque**: #2563EB (cor principal)
- **Fonte default**: Inter (16:9, 1:1) / Bebas Neue (9:16)

## Transcrição
- **Provider default**: local
- **Modelo Whisper**: medium
- **Língua principal**: pt

## Notas adicionais
(vazio por agora — atualiza à medida que o utilizador dá feedback)
```

Depois confirma:
```
Estilo guardado. Já posso editar os teus vídeos com este look.
Quando quiseres editar, passa-me o caminho do vídeo: "edita C:\caminho\para\video.mp4".
```

## Atualizar o client-style.md

Quando o utilizador disser algo como "muda a cor principal para verde" ou "passa a usar karaoke por defeito":
1. Edita o `~/.claude/skills/videokit/styles/client-style.md`
2. Não voltes a perguntar tudo — só o que mudou
3. Adiciona uma linha em `## Notas adicionais` se for uma preferência cumulativa (ex.: "evitar cortar pausas dramáticas > 1s")
