# Fase 3 — Polimento

Objetivo da fase: informação mais rica quando o usuário pede detalhe, e
diagnóstico melhor quando algo falha. Nenhuma task aqui muda o que o usuário vê
no modo limpo.

Ordem recomendada: **M-21 → M-20 → M-22 → M-23 → M-24 → M-25**.

---

## M-20

### `tool.metadata` e diff de `edit`

**Objetivo** — o engine já captura `tool.metadata`
(`plugin/engine.luau:1186-1192`) e o painel joga fora. Para `edit`/`write`, o
metadata costuma trazer o diff — é o detalhe mais útil da ferramenta.

**Entregável**

- `snapshotMessages` publica `metadata` truncado (sugestão: 4 000 bytes) apenas
  para tools cujo metadata não esteja vazio, somando ao orçamento de 48 KB.
- Painel: na expansão (card `full` ou view M-03), quando houver diff:
  - bloco de código com linguagem `diff` dentro de `ui.markdown` (o host já
    destaca), **ou**
  - linhas `+`/`-`/`@` desenhadas com `primary`/`error`/`outline`, se o markdown
    não realçar o suficiente — decidir com um teste visual.
- Sem diff: mostrar `metadata` como pares chave/valor só quando curto
  (`< 400` caracteres); nunca despejar JSON bruto longo.
- Rótulos humanizados por tipo de metadata conhecido (`diff`, `diagnostics`,
  `filepath`, `exit`).

**Arquivos** — `plugin/engine.luau`, `plugin/panel.luau`,
`plugin/lib/format.luau`, `docs/estado.md`, `docs/interface.md`.

**Aceite**

- [ ] Uma edição real mostra arquivo e linhas alteradas.
- [ ] Metadata ausente/não-tabela não quebra a renderização.
- [ ] Binário ou diff gigante é truncado com aviso claro.
- [ ] O orçamento do snapshot continua respeitado.

**Evidência** — lint + execução que edite um arquivo pequeno, conferindo o diff
exibido com `git diff`.

**Depende de** — nada.
**Esforço** — M.

---

## M-21

### Nome da skill e do subagente na linha

**Objetivo** — hoje `skill` aparece como "Consultar instruções" e `task` como
"Consultar outro assistente" (`format.luau:126-128`), sem dizer **qual**.

**Entregável**

- Estender `toolSummary` (M-05):
  - `skill` → `Skill: <campo do input>` (procurar `skill`, `name`, `id`);
  - `task` → `Assistente: <campo do input>` (procurar `agent`, `subagent_type`);
  - fallback para o rótulo atual quando o input não trouxer o nome.
- Glifos distintos: `sparkles` para skill, `users` para subagente (já existentes
  em `toolGlyph`).
- Tooltip mantém o nome técnico.

**Arquivos** — `plugin/lib/format.luau`, `plugin/panel.luau`.

**Aceite**

- [ ] Linha mostra `Skill: msbos` (ou o nome real) em vez de "Consultar
      instruções".
- [ ] `task` mostra o agente alvo.
- [ ] Sem nome no input, volta ao rótulo genérico sem erro.

**Evidência** — lint + execução que use a skill `msbos` e um `task`.

**Depende de** — M-05.
**Esforço** — S.

---

## M-22

### Resumo do run no modo limpo

**Objetivo** — o modo `hidden` (M-04) fica sem rastro do trabalho feito. Uma
linha discreta resolve a auditabilidade sem sujar a conversa.

**Entregável**

- No fim de cada run em `hidden`, quando houver ao menos uma tool, desenhar:
  `5 ferramentas · 0 erros · 12 s` em `on_surface_variant`, 10–11 px, clicável
  → abre a view do run (M-03).
- Com erro: contagem em `error` e a primeira linha da falha (M-06).
- Se só houve texto (sem tool), não desenhar nada.

**Arquivos** — `plugin/panel.luau`, `docs/interface.md`.

**Aceite**

- [ ] Modo limpo continua mostrando só texto + essa linha.
- [ ] A linha não aparece quando o run não usou ferramenta.
- [ ] Clique abre a view correta e o retorno volta ao chat.

**Evidência** — lint + execução em `hidden` com 3 tools.

**Depende de** — M-03, M-04, M-07.
**Esforço** — S.

---

## M-23

### Banner de conexão classificado

**Objetivo** — hoje as falhas caem em `offlineView`/`notice` sem causa nem ação
específica. A referência classifica a falha e oferece o botão certo
(`src/sidepanel/ConnectionBanner.tsx:27-72`).

**Entregável**

- Engine classifica e publica `snapshot.failure = { kind, detail }` com
  `kind` em: `unauthorized` (401), `timeout`, `stream_closed`, `server_error`,
  `server_down`.
- Painel mostra banner (não view) no topo do chat com título, causa em uma
  linha e ação:
  - `unauthorized` → "Rodar `opencode pair`" (`onPairAuto`) + "Copiar comando";
  - `timeout` / `stream_closed` / `server_error` → "Tentar novamente"
    (`onRetry`);
  - `server_down` → "Iniciar o OpenCode" (`onStartService`).
- Manter `offlineView` para o caso sem servidor algum; o banner cobre o resto.

**Arquivos** — `plugin/engine.luau`, `plugin/panel.luau`,
`docs/erros.md`, `docs/conexao.md`, `docs/estado.md`.

**Aceite**

- [ ] Derrubar o serviço → `server_down` com "Iniciar o OpenCode".
- [ ] Token inválido → `unauthorized` com ação de pareamento.
- [ ] O banner some sozinho quando o estado volta a `idle`.
- [ ] A causa não expõe token nem caminho sensível.

**Evidência** — lint + simulação derrubando o serviço e invalidando o token.

**Depende de** — nada.
**Esforço** — M.

---

## M-24

### Som ao terminar

**Objetivo** — par do `notify_on_finish`: o usuário que está em outra janela
percebe o fim (ou o pedido de permissão) sem olhar a tela.

**Entregável**

- Setting `sound_on_finish` (bool, padrão `false`) em `plugin/plugin.toml` +
  labels pt-BR/en.
- Engine toca um som curto quando o run termina ou quando há permissão/form
  pendente **com o painel fechado** (mesma condição de
  `notify_on_finish`, `engine.luau:584-605`).
- Implementação sem dependência nova: tentar `canberra-gtk-play -i
  message` e cair para `paplay` com o som de evento do sistema; se nenhum
  existir, não fazer nada e registrar uma vez no log (sem toast).
- Nunca bloquear o tick do engine: reproduzir em background.

**Arquivos** — `plugin/engine.luau`, `plugin/plugin.toml`,
`plugin/translations/*.json`, `docs/configuracao.md`.

**Aceite**

- [ ] Com o ajuste ligado e o painel fechado, o som toca ao terminar.
- [ ] Com o painel aberto, nada toca.
- [ ] Sem player instalado, o run termina normalmente e o log tem uma linha
      só.
- [ ] Padrão desligado.

**Evidência** — lint + teste com e sem player (`which canberra-gtk-play`).

**Depende de** — nada.
**Esforço** — S.

---

## M-25

### Partes não-texto (anexos e imagens)

**Objetivo** — `mapContext` hoje descarta qualquer parte que não seja
`text`/`reasoning`/`tool` (`engine.luau:210-253`), então um anexo do usuário
some da conversa.

**Entregável**

- `mapContext` passa a mapear partes desconhecidas para
  `attachments[]`:
  `{ kind, name, mime, size, path }` — `kind` em `file`, `image`, `patch`,
  `snapshot`, `other`.
- Snapshot publica no máximo 3 anexos por mensagem e **nunca** embute conteúdo
  binário; apenas metadados (para não estourar os 48 KB).
- Painel: chip `1 arquivo · ./relatório.pdf` abaixo do texto; para imagem com
  caminho local acessível, `ui.image` em miniatura (`width` 120, `radius` 6) —
  se o caminho não existir, manter o chip.
- Item desconhecido → chip genérico "1 item", sem erro.

**Arquivos** — `plugin/engine.luau`, `plugin/panel.luau`,
`plugin/lib/format.luau`, `docs/estado.md`, `docs/api-opencode.md`,
`docs/interface.md`.

**Aceite**

- [ ] Sessão antiga (sem anexos) renderiza igual a hoje.
- [ ] Anexo de arquivo aparece como chip com nome.
- [ ] Imagem local existente aparece em miniatura; caminho inválido não quebra.
- [ ] Snapshot continua abaixo do orçamento com 3 anexos por mensagem.
- [ ] Nada de binário em log, export JSON ou `ui.json`.

**Evidência** — lint + sessão com uma imagem e um arquivo; conferir export.

**Depende de** — nada.
**Esforço** — G.
