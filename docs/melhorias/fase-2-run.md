# Fase 2 — Experiência de execução

Objetivo da fase: o run fica legível além do card — o que está fazendo agora,
quanto custou, quanto demorou, e como agir em várias conversas ao mesmo tempo.

Ordem recomendada: **M-10 → M-13 → M-14 → M-18 → M-12 → M-11 → M-15 → M-16 → M-17 → M-19**.

---

## M-10

### Atividade em gerúndio no indicador

**Objetivo** — trocar `Executando: Ler arquivo…` por uma frase de ação, como
`activityLabel()` da referência (`src/sidepanel/toolActivity.ts`).

**Entregável** — `format.toolActivity(tool)` com mapa nome → frase e variação
por input:

| Tool | Frase |
|---|---|
| `read` | `lendo arquivos` |
| `edit` / `write` / `patch` | `editando arquivos` |
| `shell` / `bash` | `executando comando` |
| `grep` / `rg` | `procurando no texto` |
| `glob` / `find` / `list` | `procurando arquivos` |
| `webfetch` / `fetch` | `acessando um site` |
| `websearch` | `pesquisando na web` |
| `skill` | `consultando instruções` |
| `task` | `chamando outro assistente` |
| `question` | `aguardando sua resposta` |
| outros | `trabalhando` |

- `format.activityLabel(snapshot)`: percorre o run atual (depois da última
  mensagem do usuário) e devolve, por prioridade: tool `running` → mensagem
  `streaming` com texto (`escrevendo a resposta`) ou sem texto (`pensando`) →
  última tool do run → `trabalhando`.
- `busyIndicator()` (`panel.luau:184-209`) passa a usar
  `format.activityLabel(snapshot)` no lugar do nome da ferramenta.

**Arquivos** — `plugin/lib/format.luau`, `plugin/panel.luau`,
`docs/interface.md`.

**Aceite**

- [ ] O indicador muda conforme a ferramenta em execução.
- [ ] Entre tools, mostra `pensando`/`escrevendo a resposta` em vez de congelar
      no nome anterior.
- [ ] Tool desconhecida cai em `trabalhando` sem erro.

**Evidência** — lint + execução com `read`→`shell`→texto, registrando cada
frase vista.

**Depende de** — nada (M-04 usa isso para o modo limpo).
**Esforço** — S.

---

## M-11

### Contexto e custo no compositor

**Objetivo** — mostrar consumo, como `sessionStats.ts` e o rodapé do
`Composer.tsx:88-97` da referência.

**Entregável**

- Engine: `usageFromMessage(message)` normalizando `tokens`/`cost` no próprio
  objeto ou dentro de `usage`, com `cache.read`/`cache.write` achatados (mesma
  regra de `src/background/opencode/usage.ts`).
  - `contextUsed = input + cacheRead` (ou `total`, como fallback);
  - `cost` da sessão vem de `session.cost` quando existir, senão soma das
    mensagens;
  - ouvir `session.usage.updated` no SSE, se o servidor emitir.
- Snapshot: `usage = { contextUsed, contextLimit, cost, percent }`.
  `contextLimit` vem de `models[].limit.context`; **se não existir, omitir
  `percent`** e não inventar número.
- Painel: rodapé do compositor (`panel.luau:860-895`) exibe
  `Contexto 12.345 (6%) · Sessão US$ 0,0231`; sem dados, mantém a dica
  `Enter envia · Shift+Enter quebra linha`.
- Opcional: `ui.progress` compacto (`height = 3`) abaixo da linha, só quando
  houver `percent`.

**Arquivos** — `plugin/engine.luau`, `plugin/panel.luau`,
`plugin/lib/format.luau` (`format.tokens`, `format.cost`),
`docs/eventos.md`, `docs/estado.md`, `docs/api-opencode.md`.

**Aceite**

- [ ] Valores conferem com a sessão no OpenCode (tokens e custo).
- [ ] Sem usage, nenhum "0" aparece.
- [ ] Custo com 4 casas e locale pt-BR (`R$` não: cobrança é em USD).
- [ ] `percent` só aparece quando o modelo informa `limit.context`.
- [ ] Campos novos somados ao orçamento de 48 KB do snapshot.

**Evidência** — lint + comparação com `opencode` (sessão/uso) na mesma
mensagem.

**Depende de** — nada.
**Esforço** — M.

---

## M-12

### Cronômetro do run

**Objetivo** — responder "está demorando ou travou?".

**Entregável**

- Painel guarda `busySince` quando `snapshot.state` passa a `busy` e zera em
  `idle`/`error`.
- Indicador: `executando… 12 s` (usa o tick de 400 ms já existente,
  `panel.luau:1677`).
- Linha-resumo (M-02) e cabeçalho da view (M-03) mostram o total do run
  (M-07).
- Fonte de verdade preferida: `run.startedAt` publicado pelo engine (mais
  estável que o relógio do painel); `busySince` é o fallback.

**Arquivos** — `plugin/panel.luau`, `plugin/engine.luau` (se `run.startedAt`).

**Aceite**

- [ ] O número para quando o run termina.
- [ ] Novo run recomeça do zero (não soma com o anterior).
- [ ] Abrir o painel no meio de um run mostra o tempo já decorrido.

**Evidência** — lint + comparação com o relógio.

**Depende de** — M-07.
**Esforço** — S.

---

## M-13

### Copiar saída, entrada e mensagem

**Objetivo** — hoje só existe "Copiar resposta" inteira (`panel.luau:811-825`).

**Entregável**

- Card/view da tool: `Copiar saída` e `Copiar entrada` (visíveis quando
  expandido), com `noctalia.copyToClipboard(text, "text/plain")`.
- Bolha do usuário: `Copiar mensagem` (ícone `copy`, mesmo padrão visual).
- Toast de confirmação (`toast` já existe, `panel.luau:955`).
- Sem `fill`/borda nova: usar `variant = "ghost"`, 10–11 px.

**Arquivos** — `plugin/panel.luau`, `docs/interface.md`.

**Aceite**

- [ ] Texto copiado é idêntico ao exibido (sem ellipsis do truncamento — copiar
      o valor disponível e avisar quando estiver truncado).
- [ ] Funciona com saída vazia (botão desabilitado).
- [ ] Nenhum toast de erro quando já houver um de sucesso na tela.

**Evidência** — lint + colar em editor e comparar.

**Depende de** — nada.
**Esforço** — S.

---

## M-14

### Rascunho por sessão

**Objetivo** — trocar de conversa não apaga o que foi digitado, como
`drafts` por sessão na referência (`App.tsx:44-56`).

**Entregável**

- `draft` (string única, `panel.luau:9`) vira `drafts[sessionID]`, com
  `drafts.none` quando não há sessão.
- Ao criar nova conversa, migrar o rascunho de `none` para a sessão criada.
- `composerKey` (`panel.luau:8`, `880`) continua servindo para limpar/focar.
- Enviar limpa só o rascunho da sessão ativa; falha de envio restaura o texto.

**Arquivos** — `plugin/panel.luau`, `docs/interface.md`.

**Aceite**

- [ ] Digitar na sessão A, ir para B, voltar para A: texto preservado.
- [ ] Enviar em A não apaga o rascunho de B.
- [ ] Rascunho não é persistido em disco (é efêmero por decisão).

**Evidência** — lint + roteiro manual A→B→A.

**Depende de** — nada.
**Esforço** — S.

---

## M-15

### Trocar de agente no painel

**Objetivo** — o IPC existe (`engine.luau:1726-1727`, validação em `935-948`),
mas não há UI; o agente só aparece no header (`metaLabel`,
`panel.luau:121-138`).

**Entregável**

- Engine publica o catálogo de agentes primários (`mode != "subagent"` e
  `hidden != true`) em `chat.agents` — ou dentro de `chat.models`, se preferir
  não criar estado novo.
- `pickerView` ganha `ui.select` de agente (desabilitado durante `busy`), com
  `IPC set_agent`.
- Troca afeta apenas a sessão ativa; nova conversa herda o agente padrão
  (`agent` do `plugin.toml`).

**Arquivos** — `plugin/engine.luau`, `plugin/panel.luau`,
`docs/eventos.md`, `docs/estado.md`, `docs/interface.md`.

**Aceite**

- [ ] A lista mostra só agentes primários visíveis.
- [ ] Trocar de agente reflete na próxima mensagem.
- [ ] Erro do engine vira toast, sem mudar o header.
- [ ] Durante `busy` o select fica desabilitado.

**Evidência** — lint + troca real com `msbos-chat` e outro agente.

**Depende de** — nada.
**Esforço** — S.

---

## M-16

### Meta na lista de sessões

**Objetivo** — saber, no seletor, qual conversa está rodando ou tem resposta
nova, como `metaSuffix` da referência (`SessionBar.tsx:47-51`).

**Entregável**

- Engine mantém `busyBySession` e `unreadBySession` e publica em
  `chat.sessions` (`engine.luau:449`): `{ id, title, time, busy, unread }`.
- `unread` continua global para o ponto da barra (`bar.luau:11-46`); o por
  sessão é adicional.
- `sessionText()` (`panel.luau:1140-1147`) acrescenta ` · executando` /
  ` · nova resposta` em `primary`/`tertiary`.

**Arquivos** — `plugin/engine.luau`, `plugin/panel.luau`,
`docs/estado.md`, `docs/interface.md`.

**Aceite**

- [ ] Conversa rodando em background aparece marcada no seletor.
- [ ] Abrir a conversa limpa a marca de "nova resposta".
- [ ] Excluir a sessão remove as marcas.
- [ ] A marcação não pisca a cada `publish` (250 ms).

**Evidência** — lint + duas conversas, uma executando enquanto a outra é
exibida.

**Depende de** — nada.
**Esforço** — M.

---

## M-17

### Fila de pendências de outras sessões

**Objetivo** — hoje `pending` só reflete a sessão ativa; um pedido de permissão
em outra conversa pode ficar invisível e travar aquela sessão.

**Entregável**

- Engine passa a publicar `pending` com `sessionID` de **todas** as sessões
  conhecidas (permissões e formulários), mantendo o detalhe só da ativa para
  economizar bytes.
- Painel: se houver pendência fora da sessão ativa, mostrar aviso no topo do
  chat: `1 pedido em outra conversa · abrir`, que troca de sessão e exibe o
  cartão.
- Nunca responder automaticamente; nenhuma pendência é descartada.

**Arquivos** — `plugin/engine.luau`, `plugin/panel.luau`,
`docs/eventos.md`, `docs/estado.md`.

**Aceite**

- [ ] Pedido de permissão em B não desaparece enquanto A está aberta.
- [ ] "Abrir" leva à sessão certa com o cartão visível.
- [ ] Responder/recusar remove o aviso.
- [ ] Sessão excluída não deixa aviso órfão.

**Evidência** — lint + duas conversas, uma pedindo permissão em background.

**Depende de** — nada.
**Esforço** — M.

---

## M-18

### Atalhos de teclado

**Objetivo** — reduzir cliques no painel, que é pequeno.

**Entregável**

- `capture_keys` no `[[panel]]` do `plugin.toml` e `onKey(chord, pressed)` no
  `panel.luau` (API 13; Escape sempre fecha, então não o capture).
- Mapa:

  | Atalho | Ação |
  |---|---|
  | `ctrl+n` | nova conversa (`onNewSession`) |
  | `ctrl+k` | seletor de modelos/sessões (`onOpenPicker`) |
  | `ctrl+f` | busca na conversa (M-19) |
  | `ctrl+shift+c` | copiar última resposta |

- Não interferir no campo de texto: quando o input tem foco, o host dá
  prioridade ao texto (documentar isso em `docs/interface.md`).

**Arquivos** — `plugin/plugin.toml`, `plugin/panel.luau`,
`docs/interface.md`, `README.md`.

**Aceite**

- [ ] Atalhos funcionam com o painel aberto e sem foco no input.
- [ ] Digitar `Ctrl+N` dentro do compositor não dispara a ação (ou não apaga o
      texto).
- [ ] Nenhum atalho conflita com o niri/Noctalia do usuário.

**Evidência** — lint + teste de cada atalho.

**Depende de** — nada (M-19 para o `ctrl+f`).
**Esforço** — S.

---

## M-19

### Busca dentro da conversa

**Objetivo** — hoje só existe busca por título de sessão
(`panel.luau:1301-1311`).

**Entregável**

- Estado `chatQuery`; `ui.input` com `controlSize = "sm"` no header do chat
  (quando aberta por `ctrl+f` ou botão de lupa).
- Filtro por substring em `text`, `reasoning`, `tools[].input` e
  `tools[].output` (case-insensitive), exibindo `3 de 7`.
- Navegação entre ocorrências com `revealKey` (API 33) para rolar até a
  mensagem correspondente, usando `key = message.id` já implícito nas linhas.
- Modo "filtrar" (mostra só as mensagens com ocorrência) vs. "destacar".
  Recomendado: destacar + navegar, para não esconder contexto.
- Aviso quando o histórico estiver truncado (`historyNotice`, `panel.luau:897`).

**Arquivos** — `plugin/panel.luau`, `docs/interface.md`.

**Aceite**

- [ ] Busca encontra texto em resposta, raciocínio e saída de ferramenta.
- [ ] Contador correto; navegação circular.
- [ ] Limpar restaura a conversa completa e a posição de scroll.
- [ ] Com histórico truncado, a busca avisa que só o trecho carregado foi
      pesquisado.

**Evidência** — lint + busca por termo presente em tool e em texto.

**Depende de** — nada.
**Esforço** — M.
