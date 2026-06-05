# Export para Premiere / DaVinci Resolve / Final Cut Pro

Se o utilizador quer refinar o corte no NLE em vez de aceitar o final.mp4 da skill, exporta o `edit/edl.json` para um formato que o NLE entenda.

## Formatos suportados

| Formato | Extensão | NLEs |
|---|---|---|
| CMX 3600 EDL | `.edl` | Premiere Pro, DaVinci Resolve, Avid Media Composer, Final Cut Pro X |
| Final Cut XML | `.fcpxml` | DaVinci Resolve 18+, Final Cut Pro X (formato moderno, com metadata) |

## Como exportar

```bash
# Default: gera ambos (.edl + .fcpxml) em <projeto>/edit/
python scripts/export-edl.py <projeto>

# Só CMX 3600
python scripts/export-edl.py <projeto> --format cmx3600

# Só FCPXML
python scripts/export-edl.py <projeto> --format fcpxml

# Override fps (útil se project.json tem fps wrong)
python scripts/export-edl.py <projeto> --fps 25
```

Pré-requisito: já tens `edit/edl.json` gerado por `auto-cut.py`.

## Como importar no NLE

### DaVinci Resolve

**Opção 1 — FCPXML (recomendado)**:
1. Importa o source para o Media Pool (drag-and-drop ou `File > Import > Media`).
2. `File > Import > Timeline > Pre-conformed FCPXML`.
3. Seleciona `<projeto>.fcpxml`.
4. Resolve cria a timeline com cortes nos sítios corretos.

**Opção 2 — EDL**:
1. Importa o source para o Media Pool.
2. `File > Import > Timeline > Pre-conformed EDL`.
3. Aponta para `<projeto>.edl`.
4. Confirma fps (deve bater com o source).

### Premiere Pro

**EDL** é o caminho mais fiável:
1. Importa o source para um bin.
2. `File > Import` → seleciona `<projeto>.edl`.
3. Premiere cria uma nova sequence com os clips conformes.

Premiere também aceita FCPXML mas com perda de algumas features modernas (multicam, captions estruturadas).

### Final Cut Pro X

1. `File > Import > XML`.
2. Seleciona `<projeto>.fcpxml`.
3. FCP cria um project com event e timeline.

## O que vai dentro do EDL

A skill exporta **só os cortes** (corresponde a `edl.json.segments_keep`):

- Cada segment vira um clip na timeline
- Timecodes convertidos para SMPTE HH:MM:SS:FF (non-drop frame) usando `fps` do `project.json`
- Reel name = `AX` (auxiliary, sem reel físico — standard para ficheiros)
- Cada clip referencia o source com path absoluto (no FCPXML) ou nome (no EDL)

O que **não** vai (limitação intencional, NLE faz melhor):
- Filtros visuais (LUTs, color grade) — re-aplica no NLE
- Legendas queimadas — exporta `.ass` separadamente se quiseres
- Motion graphics — re-cria com templates do NLE
- Áudio pack (denoise/loudnorm) — reaplica com plugins do NLE

## Workflow típico

```
1. videokit faz transcribe + auto-cut → cortes "boa o suficiente"
2. export-edl → .edl + .fcpxml
3. Editor abre no Resolve, refina cortes que ficaram errados, mete grading próprio
4. Editor exporta o final do Resolve, não do videokit
```

A skill é fortemente útil aqui para **poupar o trabalho mecânico** (transcrever + remover ahn/ums + cortar silêncios) e deixar o editor focar no que tem valor (timing, narrativa, cor).

## Limitações conhecidas

- **Timecode imprecisão**: a conversão `seconds → SMPTE` arredonda ao frame. Se `min_silence=0.5` produz cortes em `t=12.347s`, o EDL vê isso como `00:00:12:10` (a 30fps). Imperceptível na prática.
- **FCPXML 1.10**: testado em Resolve 18. Versões mais antigas (Resolve 16, FCP X 10.4) podem rejeitar — usa CMX 3600 nesses casos.
- **Path do source**: o `.fcpxml` embute path absoluto. Se mexeres o ficheiro source de sítio depois de exportar, o NLE vai pedir relink.
- **Não exporta áudio multi-canal**: assume mono ou stereo standard. Se o source é spatial 4-ch, o NLE pode mapear para os canais errados — verifica após import.
- **Sem suporte de drop-frame**: usa NDF (non-drop). Se trabalhas com broadcast 29.97/59.94 em DF, edita manualmente o `FCM:` no `.edl`.
