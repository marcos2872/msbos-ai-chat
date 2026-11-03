# Fase 1 — Exibição e limpeza

Objetivo da fase: o usuário escolhe **quanto** da execução quer ver, e a
conversa deixa de ser uma pilha de cards. Nada aqui depende de API nova do
OpenCode além do que o snapshot já entrega (exceto M-07, que adiciona campos).

Ordem recomendada: **M-01 → M-05 → M-06 → M-02 → M-03 → M-04 → M-07 → M-08 → M-09**.

---

## M-01

### Setting `tool_display` com 4 modos

**Objetivo** — dar ao usuário um controle global de exibição, equivalente ao
`toolDisplay` da referência (`src/options/App.tsx:448-480`).

**Entregável**

- Novo `[[setting]]` em `plugin/plugin.toml`:

  ```toml
  [[setting]]
  key = "tool_display"
  type = "select"
  label_key = "settings.tool_display.label"
  description_key = "settings.tool_display.description"
  default = "grouped"
  options = [
    { value = "grouped", label_key = "settings.tool_display.grouped" },
    { value = "rows",    label_key = "settings.tool_display.rows" },
    { value = "full",    label_key = "settings.tool_display.full" },
    { value = "hidden",  label_key = "settings.tool_display.hidden" },
  ]
  ```

- Labels em `plugin/translations/pt-BR.json` e `en.json`
  (`settings.tool_display.*`), no mesmo formato das chaves existentes.
- No painel, `refreshToolDisplay()` ao lado de `refreshComposer()`
  (`plugin/panel.luau:56-60`), com clamp para valor inválido → `grouped`.
- Chamada no `onConfigChanged` (`plugin/panel.luau:1647`) para aplicar sem
  recarregar o plugin.
- Comportamento por modo (implementado nas tasks seguintes; nesta task só o
  roteamento):
  - `full` = comportamento atual (`renderTool`, `panel.luau:327`);
  - `rows` = linha compacta por chamada, expansível;
  - `grouped` = uma linha por execução (M-02);
  - `hidden` = sem raciocínio e sem tools (M-04).

**Arquivos** — `plugin/plugin.toml`, `plugin/translations/pt-BR.json`,
`plugin/translations/en.json`, `plugin/panel.luau`,
`docs/configuracao.md`, `docs/interface.md`.

**Aceite**

- [ ] Os 4 valores aparecem no ajuste do plugin e o padrão é `grouped`.
- [ ] Trocar o valor reflete no chat **sem** recarregar o plugin.
- [ ] `full` reproduz exatamente o comportamento anterior à fase.
- [ ] Valor desconhecido no `plugin.toml` cai em `grouped` sem erro no log.

**Evidência** — lint `0 errors, 0 warnings` + observação dos 4 modos + linha
nova na tabela de `docs/configuracao.md`.

**Depende de** — nada.
**Esforço** — S.

---

## M-02

### Agrupar tools por execução + linha-resumo

**Objetivo** — uma execução com 5 ferramentas ocupa **uma linha**, como o
`ToolRun` da referência (`src/sidepanel/ToolsModal.tsx:29-73`).

**Entregável**

- Helpers no painel (ou em `lib/format.luau` se ficarem puros):

  ```lua
  -- índice da primeira mensagem de assistente do run que contém `index`
  local function runStartIndex(messages, index)
  -- todas as tools (exceto `question`) de cada run, indexadas pelo início
  local function collectRunTools(messages)
  ```

  Regra de truncamento: se o snapshot não contiver a mensagem do usuário que
  abriu o run, usar a mensagem mais antiga disponível como início.

- No modo `grouped`, cada run renderiza:
  `[ícone] N ferramentas · N erro(s) · 12s   → ver`
  como `ui.row` clicável (`onClick = "onOpenTools"`) com `fill =
  "surface_variant/0.16"`, `border`, `radius = 8` e a mesma altura do card
  atual.
- Continuam inline: a tool com `status == "running"`, a tool `question` e o
  cartão de permissão.
- Erro no run: contagem em `error` na própria linha.

**Arquivos** — `plugin/panel.luau` (`chatView`/`renderMessage`, `765-858`),
`plugin/lib/format.luau` (`toolsSummary`), `docs/interface.md`.

**Aceite**

- [ ] Pedido com 5 tools concluídas mostra 1 linha, não 5 cards.
- [ ] Com 1 erro, a linha mostra `1 erro` em `error` e a primeira linha da
      mensagem de erro fica visível (M-06).
- [ ] A tool em execução continua aparecendo individualmente no chat.
- [ ] Histórico truncado não gera contagem negativa nem run “fantasma”.
- [ ] `question` nunca é agrupada nem escondida.

**Evidência** — lint + execução real com 2 tools (`read` + `shell`) e uma
execução com falha; registrar contagem exibida.

**Depende de** — M-01 (para respeitar o modo).
**Esforço** — M.

---

## M-03

### View "Ferramentas desta execução"

**Objetivo** — dar acesso ao detalhe completo sem poluir o chat, substituindo o
modal da referência (`ToolsModal.tsx:76-180`) por uma view do painel.

**Entregável**

- Estado `toolsViewRun` (id da mensagem que abre o run) e `onlyErrors`.
- Nova `toolsView()` no padrão de `pickerView` (`panel.luau:1169`) e
  `changesView` (`panel.luau:1454`), registrada no dispatch de view
  (`panel.luau:1596-1626`); `onBackToChat` (`panel.luau:1768`) já serve de
  retorno.
- Conteúdo: cabeçalho com `N ferramentas · N erros · duração total`, filtro
  "Somente erros" (`ui.toggle`), e uma linha por tool com glifo, rótulo
  humanizado, resumo do input (M-05), duração (M-07) e chevron para expandir
  `Parâmetros` (`format.toolInput`) e `Resultado` (markdown, aberto por padrão
  quando `status == "error"`).
- Lista em `ui.scroll` com `key = tool.id`.

**Arquivos** — `plugin/panel.luau`, `docs/interface.md`.

**Aceite**

- [ ] Clicar na linha-resumo abre a view do run correspondente (e somente dele).
- [ ] Filtro "Somente erros" esvazia corretamente quando não há erro.
- [ ] Expandir/recolher preserva os outros itens abertos.
- [ ] Voltar retorna ao chat na mesma posição de scroll.
- [ ] Saída longa respeita o limite de exibição (M-09).

**Evidência** — lint + navegação completa com execução de 3+ tools.

**Depende de** — M-02.
**Esforço** — M.

---

## M-04

### Modo limpo (`hidden`)

**Objetivo** — "deixar tudo limpo": só o texto da conversa e o indicador de
trabalho, como o modo `hidden` da referência (`src/sidepanel/Chat.tsx:113-155`).

**Entregável**

- Com `tool_display = "hidden"`:
  - não desenhar blocos de raciocínio (`panel.luau:828-843`);
  - não desenhar cards de tool;
  - fundir os textos das mensagens de assistente do run num bloco único;
  - manter visíveis: `question`, cartão de permissão, erro da mensagem,
    `historyNotice` e toast;
  - indicador de trabalho com a frase de atividade (M-10) ou, até M-10,
    `executando…`.
- Run sem texto, sem erro e sem pendência não renderiza nada.

**Arquivos** — `plugin/panel.luau` (`renderMessage`, `chatView`),
`docs/interface.md`.

**Aceite**

- [ ] Com 3 tools e raciocínio, o chat mostra apenas o texto final.
- [ ] Pergunta do agente (`question`) continua aparecendo e respondível.
- [ ] Cartão de permissão continua aparecendo e respondível.
- [ ] Falha de ferramenta não desaparece silenciosamente (erro do run visível).
- [ ] Alternar `hidden` ↔ `full` não perde mensagens nem estado de streaming.

**Evidência** — lint + execução real em `hidden` com uma permissão e uma
pergunta; registrar o que apareceu.

**Depende de** — M-01, M-02.
**Esforço** — M.

---

## M-05

### Resumo do input na linha da tool

**Objetivo** — dizer *o que* a ferramenta fez sem obrigar a expandir, como
`summary()` da referência (`src/sidepanel/ToolCard.tsx:105-124`).

**Entregável** — `format.toolSummary(tool)` retornando até 80 caracteres:

| Tool | Resumo |
|---|---|
| `read` / `edit` / `write` / `patch` | nome do arquivo (`baseName` já existe em `panel.luau:575`) + diretório curto |
| `shell` / `bash` | primeiro comando, sem flags longas |
| `grep` / `rg` | o padrão entre aspas |
| `glob` / `find` / `list` | o padrão/escopo |
| `webfetch` / `fetch` | host da URL |
| `websearch` | a consulta entre aspas |
| `todowrite` / `todoread` | `N itens` |
| outros | string vazia |

- Usado no cabeçalho da linha compacta (`rows`/`grouped`) e nas linhas da view
  (M-03), em `on_surface_variant` e fonte 10–11 px.
- Nome técnico continua **só** no tooltip (`panel.luau:343`).

**Arquivos** — `plugin/lib/format.luau`, `plugin/panel.luau`.

**Aceite**

- [ ] `read` mostra o arquivo; `shell` mostra o comando; `grep` mostra o padrão.
- [ ] Nada quebra com `input` vazio, `nil` ou não-tabela (tools antigas).
- [ ] Texto nunca passa de 80 caracteres (ellipsis).

**Evidência** — lint + uma execução com `read`, `shell` e `grep`.

**Depende de** — nada (é pré-requisito útil para M-02 e M-03).
**Esforço** — S.

---

## M-06

### Erro visível com o card colapsado

**Objetivo** — falha identificável sem clique, como no `tool-error-line` da
referência (`ToolCard.tsx:255-259`).

**Entregável**

- Quando `tool.status == "error"` e o card está fechado, desenhar abaixo do
  cabeçalho a **primeira linha** da saída (até 160 caracteres, `color =
  "error"`, `fontSize` 11).
- Ao expandir, o resultado completo continua como hoje.
- A contagem de erros da linha-resumo (M-02) é independente deste bloco.

**Arquivos** — `plugin/panel.luau` (`renderTool`, `327-377`).

**Aceite**

- [ ] Tool que falhou mostra a primeira linha mesmo fechada.
- [ ] Tool com sucesso não mostra nada extra.
- [ ] Saída só com linhas em branco não renderiza bloco vazio.

**Evidência** — lint + execução com comando inválido (`false`/`exit 1`).

**Depende de** — nada.
**Esforço** — S.

---

## M-07

### Duração por tool e total do run

**Objetivo** — dar noção de tempo, como `toolDuration`/`totalDuration` da
referência (`ToolsModal.tsx:7-27`).

**Entregável**

- Engine: `startedAt`/`finishedAt` (ms, `noctalia.nowMs()`) no registro da tool
  (`plugin/engine.luau:170-192`) e na transição de status
  (`plugin/engine.luau:1176-1209`).
- Snapshot: publicar os dois campos em `snapshotMessages`
  (`plugin/engine.luau:459-511`), contabilizando-os no orçamento de 48 KB
  (são números curtos; somar apenas o custo fixo).
- Painel: `format.duration(ms)` → `820 ms`, `3 s`, `1 m 5 s`; exibir na linha da
  tool e no cabeçalho da view; total do run na linha-resumo (M-02).
- Tool em execução: duração contada a partir de `startedAt` (usar o tick de
  400 ms que o painel já tem, `panel.luau:1677`).

**Arquivos** — `plugin/engine.luau`, `plugin/lib/format.luau`,
`plugin/panel.luau`, `docs/eventos.md`, `docs/estado.md`.

**Aceite**

- [ ] Duração exibida bate com o tempo real (±1 s).
- [ ] Total do run = do início da primeira tool ao fim da última.
- [ ] Sessão antiga (tools sem timestamps) mostra a linha sem duração, sem erro.
- [ ] Campos novos documentados em `docs/estado.md`.

**Evidência** — lint + comparação com o relógio durante uma execução.

**Depende de** — M-02.
**Esforço** — M.

---

## M-08

### Persistir preferências de exibição

**Objetivo** — fechar e reabrir o painel não deve desfazer a escolha do
usuário. Hoje `expandedTools`, `expandedReasoning` etc. vivem só na memória do
painel (`panel.luau:14-19`).

**Entregável**

- `ui.json` (`store.luau:55`) ganha `ui = { showReasoning = bool,
  expandedTools = bool, toolsFilterErrors = bool }` — **sem** tocar em
  `pairing.json`.
- Novo IPC `set_ui_pref <chave>=<valor>` no engine, com whitelist de chaves,
  gravação atômica e permissão `0600` (mesmo caminho de `ui.json` atual).
- Engine publica `snapshot.ui` e o painel usa como valor inicial; mudanças no
  painel atualizam o otimista e persistem em background.
- `tool_display` continua no `plugin.toml` (é ajuste do host, não `ui.json`).

**Arquivos** — `plugin/engine.luau`, `plugin/lib/store.luau`,
`plugin/panel.luau`, `docs/eventos.md`, `docs/estado.md`.

**Aceite**

- [ ] Fechar/minimizar e reabrir mantém "raciocínio aberto" e o filtro da view.
- [ ] `ui.json` continua `0600`; nenhum token é escrito nele.
- [ ] Chave desconhecida no IPC é ignorada com aviso no log, sem quebrar.
- [ ] `preferredModel` (comportamento existente) continua funcionando.

**Evidência** — lint + `ls -l ~/.msbos-ai-chat/state/ui.json` antes e depois.

**Depende de** — M-01.
**Esforço** — S.

---

## M-09

### `max_tool_output` valendo no painel

**Objetivo** — corrigir a inconsistência: a descrição do ajuste já diz "exibido
no chat e no export"
(`plugin/translations/pt-BR.json:21-22`), mas o painel trunca em 4 000 fixo
(`panel.luau:364`) e o snapshot em 2 000 (`engine.luau:28`).

**Entregável**

- Engine lê `max_tool_output` (clamp 500–20000) e usa como limite de
  `MAX_SNAPSHOT_TOOL_OUTPUT` em `snapshotMessages`; o valor efetivo entra em
  `snapshot.limits.toolOutput` para o painel exibir com o mesmo teto.
- Painel deixa de truncar em 4 000 fixo e usa o valor publicado.
- Remover de `docs/configuracao.md` a nota que explica a divergência
  (`configuracao.md:28`).

**Arquivos** — `plugin/engine.luau`, `plugin/panel.luau`,
`docs/configuracao.md`, `docs/estado.md`.

**Aceite**

- [ ] Alterar o ajuste muda o tamanho do resultado exibido após um run novo.
- [ ] Valor fora da faixa é limitado (500–20000) sem erro.
- [ ] O orçamento total de 48 KB do snapshot continua respeitado.
- [ ] Export Markdown continua usando o mesmo valor.

**Evidência** — lint + teste com 500 e 20000 usando uma saída longa
(`seq 1 2000`).

**Depende de** — nada.
**Esforço** — S.
