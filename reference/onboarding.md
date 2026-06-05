# Primeira conversa — onboarding

A skill exige `~/.claude/skills/videokit/styles/client-style.md` antes de editar. Se não existir, faz onboarding **antes** de qualquer pipeline.

Este ficheiro vive **dentro da skill** (uma vez por utilizador), não na pasta de trabalho. Aplica-se a todos os vídeos.

## Regras da conversa

- **Uma pergunta de cada vez**. Não atires lista numerada.
- Sugere defaults razoáveis (com `(default: X)` na pergunta) para o utilizador poder dizer "default" e avançar.
- Aceita "qualquer", "tu escolhes" — usa o default e regista que foi auto-decidido.
- Quando o utilizador disser cor por nome (ex.: "azul"), converte para hex razoável (`#2563EB` por exemplo) e mostra.
- Não perguntes sobre coisas que dá para inferir (resolução, fps — vem de `ffprobe`).

## Persistência incremental (state recovery)

**Guarda depois de CADA resposta, não no fim.** O utilizador pode interromper a meio (Ctrl-C, sessão termina, "ok deixa para amanhã") — quando regressar a skill deve **continuar de onde parou**, não recomeçar do zero.

Implementação:

1. Antes da primeira pergunta, escreve um esqueleto em `~/.claude/skills/videokit/styles/client-style.md` com `<!-- onboarding-status: in_progress -->` no topo e os campos vazios (`(pendente)` em cada um).
2. Após cada resposta, edita só a linha correspondente e regrava o ficheiro.
3. Quando a sétima resposta for guardada, troca o marcador para `<!-- onboarding-status: complete -->` e remove o disclaimer no topo.
4. Quando uma nova sessão começa, lê o ficheiro:
   - Se não existir → começa do zero (pergunta 1).
   - Se existir com `onboarding-status: complete` → segue para o pipeline normal.
   - Se existir com `onboarding-status: in_progress` → identifica a primeira linha com `(pendente)` e retoma a partir daí. Diz: `"Encontrei onboarding incompleto. Continuamos onde parámos."`.

Em Windows escreve sempre UTF-8 sem BOM:
```powershell
[IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
```

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

Estrutura final (depois das 7 respostas). Em Windows resolve para `C:\Users\<user>\.claude\skills\videokit\styles\client-style.md`. Cria a pasta `styles/` se não existir.

```markdown
<!-- onboarding-status: complete -->
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

### Esqueleto durante o onboarding

Enquanto está incompleto, deve ser:

```markdown
<!-- onboarding-status: in_progress -->
<!-- Em curso — não eliminar. A skill retoma da primeira linha com "(pendente)". -->
# Estilo do cliente

## Identidade visual
- **Cor principal**: (pendente)
- **Cor secundária**: (pendente)
- **Logo**: (pendente)

## Edição
- **Estilo**: (pendente)
- **Posição do orador**: (pendente)

## Legendas
- **Estilo default**: (pendente)
- **Cor texto**: branco com outline #0F172A
- **Cor destaque**: (cor principal — preenche quando souberes)
- **Fonte default**: Inter (16:9, 1:1) / Bebas Neue (9:16)

## Transcrição
- **Provider default**: (pendente)
- **Modelo Whisper**: medium
- **Língua principal**: pt

## Notas adicionais
(vazio por agora)
```

## Confirmação final

Só depois da 7ª resposta:
```
Estilo guardado. Já posso editar os teus vídeos com este look.
Quando quiseres editar, passa-me o caminho do vídeo: "edita C:\caminho\para\video.mp4".
```

## Saltar onboarding

Se o utilizador diz `"deixa o default, quero só editar agora"` ou `"vou configurar depois"`:
1. Cria o `client-style.md` completo com **todos** os defaults (cor #2563EB, secundária #F8FAFC, dinâmico, centro, sem logo, sem legendas, Whisper local).
2. Marca `<!-- onboarding-status: complete -->`.
3. Adiciona em `## Notas adicionais`: `"Auto-preenchido a partir de defaults. Atualiza quando quiseres."`.
4. Continua para o pipeline.

## Atualizar o client-style.md

Quando o utilizador disser algo como "muda a cor principal para verde" ou "passa a usar karaoke por defeito":
1. Edita o `~/.claude/skills/videokit/styles/client-style.md`
2. Não voltes a perguntar tudo — só o que mudou
3. Adiciona uma linha em `## Notas adicionais` se for uma preferência cumulativa (ex.: "evitar cortar pausas dramáticas > 1s")
