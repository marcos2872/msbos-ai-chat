# Plano de melhorias do chat — experiência de uso

Plano derivado da comparação com o projeto de referência
`/home/marcos/Projetos/opencode-extencion` (extensão OpenCode Browser, side panel
em React). O objetivo é a mesma sensação de uso: **o chat mostra o que aconteceu
sem virar uma pilha de cards**, e o usuário escolhe o nível de detalhe.

| Item | Valor |
|---|---|
| Base analisada | `msbos-ai-chat` `0.2.0` (plugin API 34) |
| Referência | `opencode-extencion` (side panel React) |
| Tasks | 25 (`M-01` … `M-25`) em 3 fases |
| Regra de ouro | Nada de esconder pendência: `question` e cartão de permissão **sempre** visíveis |

## O que foi copiado da referência

1. **Um único setting com 4 modos** (`toolDisplay` → aqui `tool_display`):
   `grouped` (padrão), `rows`, `full`, `hidden`.
2. **Agrupamento por execução, não por mensagem**: as tools de um run viram uma
   linha-resumo (`N ferramentas · N erros · 12s`).
3. **Detalhe sob demanda**: lista completa do run com filtro de erros e
   expansão de parâmetros/resultado.
4. **Atividade em gerúndio** (`trabalhando: lendo arquivos`) em vez do rótulo
   nominal da ferramenta.
5. **Resumo do input na linha** (`app.py`, `dnf install htop`, `"TODO"`, URL).
6. **Custo e contexto no rodapé** do compositor.

## O que **não** foi copiado (não se aplica)

| Recurso da extensão | Motivo |
|---|---|
| `ToolsModal` como modal real | O host do Noctalia não tem modal; usamos **view** (padrão `pickerView`/`changesView`). |
| Tools de navegador (`browser_*`, CDP, GIF, abas) | Específicas da extensão. |
| Permissão por domínio/host | Este chat age no sistema, não em páginas web. |
| `chrome.*`, service worker, Port | Arquitetura diferente: o `engine` já é o serviço. |

## Princípios de implementação

1. **Engine é fonte de verdade.** Dado que o painel precisa (duração, usage,
   metadata, pendências de outras sessões) é publicado no snapshot; o painel só
   decide como desenhar.
2. **Sem modal, sem janela nova.** Tudo é view ou bloco inline no painel.
3. **Cores só por role do tema** (`primary`, `surface_variant/0.16`, `outline`,
   `error`) e `gap` do sistema (12 entre seções, 6 em listas).
4. **Preferência do usuário vira setting**, não constante no código.
5. **Truncamento respeitado.** O snapshot corta em 24 mensagens / 48 KB, texto
   8 000, raciocínio 3 000 e saída de tool 2 000 (`plugin/engine.luau:24-31`).
   Qualquer agrupamento precisa suportar histórico truncado.
6. **Nunca esconder o que bloqueia a sessão.** No modo `hidden`, `question`,
   permissão, erro e aviso de histórico continuam renderizados.

## Backlog

### Fase 1 — Exibição e limpeza (o "modo limpo")

| ID | Task | Esforço | Depende de |
|---|---|---|---|
| [M-01](fase-1-exibicao.md#m-01) | Setting `tool_display` com 4 modos | S | — |
| [M-02](fase-1-exibicao.md#m-02) | Agrupar tools por execução + linha-resumo | M | M-01 |
| [M-03](fase-1-exibicao.md#m-03) | View "Ferramentas desta execução" | M | M-02 |
| [M-04](fase-1-exibicao.md#m-04) | Modo limpo (`hidden`) | M | M-01, M-02 |
| [M-05](fase-1-exibicao.md#m-05) | Resumo do input na linha da tool | S | — |
| [M-06](fase-1-exibicao.md#m-06) | Erro visível com o card colapsado | S | — |
| [M-07](fase-1-exibicao.md#m-07) | Duração por tool e total do run | M | M-02 |
| [M-08](fase-1-exibicao.md#m-08) | Persistir preferências de exibição | S | M-01 |
| [M-09](fase-1-exibicao.md#m-09) | `max_tool_output` valendo no painel | S | — |

### Fase 2 — Experiência de execução

| ID | Task | Esforço | Depende de |
|---|---|---|---|
| [M-10](fase-2-run.md#m-10) | Atividade em gerúndio no indicador | S | — |
| [M-11](fase-2-run.md#m-11) | Contexto e custo no compositor | M | — |
| [M-12](fase-2-run.md#m-12) | Cronômetro do run | S | M-07 |
| [M-13](fase-2-run.md#m-13) | Copiar saída, entrada e mensagem | S | — |
| [M-14](fase-2-run.md#m-14) | Rascunho por sessão | S | — |
| [M-15](fase-2-run.md#m-15) | Trocar de agente no painel | S | — |
| [M-16](fase-2-run.md#m-16) | Meta na lista de sessões | M | — |
| [M-17](fase-2-run.md#m-17) | Fila de pendências de outras sessões | M | — |
| [M-18](fase-2-run.md#m-18) | Atalhos de teclado | S | — |
| [M-19](fase-2-run.md#m-19) | Busca dentro da conversa | M | — |

### Fase 3 — Polimento

| ID | Task | Esforço | Depende de |
|---|---|---|---|
| [M-20](fase-3-polimento.md#m-20) | `tool.metadata` e diff de `edit` | M | — |
| [M-21](fase-3-polimento.md#m-21) | Nome da skill e do subagente na linha | S | M-05 |
| [M-22](fase-3-polimento.md#m-22) | Resumo do run no modo limpo | S | M-03, M-04, M-07 |
| [M-23](fase-3-polimento.md#m-23) | Banner de conexão classificado | M | — |
| [M-24](fase-3-polimento.md#m-24) | Som ao terminar | S | — |
| [M-25](fase-3-polimento.md#m-25) | Partes não-texto (anexos e imagens) | G | — |

Esforço: **S** ≈ até ~40 linhas alteradas · **M** ≈ 40–150 · **G** ≈ 150+ ou
mexe no contrato do snapshot.

## Lotes sugeridos

| Lote | Tasks | Resultado visível |
|---|---|---|
| **A** | M-01, M-05, M-06 | Chat menos verboso, sem mudar a estrutura. |
| **B** | M-02, M-03, M-04, M-07 | Um card por execução + modo limpo de verdade. |
| **C** | M-08, M-09 | Preferências persistem; truncamento coerente. |
| **D** | M-10, M-11, M-12 | O run fica legível: o que está fazendo, quanto gastou, quanto demorou. |
| **E** | M-13, M-14, M-15, M-18 | Compositor e navegação mais rápidos. |
| **F** | M-16, M-17, M-19 | Convivência com várias conversas. |
| **G** | M-20 … M-25 | Polimento. |

## Status da implementação

Todas as 25 tasks foram implementadas (2026-11-03), em 8 commits:

| Commit | Tasks |
|---|---|
| `9e3b9c9` | M-05, M-06 |
| `dded24d` | M-01, M-02, M-03, M-04 |
| `78a87ac` | M-07, M-12 |
| `dc236b7` | M-08, M-09 |
| `4470987` | M-10, M-11 |
| `f3a2ea5` | M-13, M-14, M-18 |
| `99957f9` | M-15, M-16, M-17 |
| `2f94d0e` | M-19 |
| `3d90b3f` | M-20, M-21, M-22, M-23, M-24, M-25 |

Desvios conscientes em relação ao plano original:

- **M-05**: o resumo é calculado no **engine** (`format.toolSummary`) e vai pronto em `tool.summary`; o painel não decodifica JSON.
- **M-11**: o uso vem do `/context` (mensagens) e do `cost` da sessão. Não há evento de usage tratado no SSE, então o número atualiza ao fim do run e ao trocar de sessão.
- **M-17**: contamos permissões e formulários de outras sessões por ID; o detalhe continua sendo carregado ao abrir a conversa.
- **M-21**: resolvido por `toolSummary` (`Skill: <nome>`, agente do `task`) — o rótulo genérico permanece como fallback.
- **M-25**: chips com metadados (`Arquivo:`/`Imagem:`), sem miniatura — nada de binário no snapshot.

## Definição de pronto (vale para toda task)

- [ ] `./install.sh` seguido de
      `noctalia plugins lint "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/msbos-ai-chat"`
      termina com `0 errors, 0 warnings`.
- [ ] Checklist manual de [desenvolvimento.md](../desenvolvimento.md) executado;
      resultado registrado no fim da task.
- [ ] Documentação atualizada **no mesmo trabalho**: `docs/configuracao.md` para
      setting novo, `docs/interface.md` para mudança visual, `docs/eventos.md`
      para IPC/estado novo, `docs/estado.md` para campo novo no snapshot/`ui.json`,
      `docs/componentes.md` para função nova, `README.md` se o uso mudar.
- [ ] Sem regressão de segurança: cartão de permissão e formulário continuam
      aparecendo e respondíveis em todos os modos de exibição.
- [ ] `ui.json`, `pairing.json` e exports continuam `0600`; nenhum token em log.
- [ ] `AGENTS.md` atualizado se surgir setting, IPC ou fluxo novo.
- [ ] Sem dependência externa, bundler ou build novo (Luau `--!nonstrict`).

## Riscos e mitigação

| Risco | Impacto | Mitigação |
|---|---|---|
| Agrupar por run com histórico truncado (o início do run pode ter saído do snapshot) | Linha-resumo com contagem errada | Tratar a mensagem mais antiga disponível como início do run e sinalizar quando `messagesTotal > #messages`. |
| Esconder tool no modo `hidden` e o usuário não ver uma falha | Perda de confiança | Erros sempre visíveis; resumo do run discreto (M-22); pendências nunca escondidas. |
| `limit.context` ausente no catálogo de modelos | Percentual de contexto errado | Mostrar só tokens; percentual apenas quando `limit.context` existir (M-11). |
| `ui.markdown` não permite copiar por bloco de código | Expectativa frustrada | Botão "Copiar saída" no card expandido (M-13); documentar a limitação. |
| Novas publicações no snapshot aumentarem os 48 KB | Mensagens recentes cortadas | Contabilizar os campos novos no orçamento de `snapshotMessages` (`engine.luau:459`). |
| `onConfigChanged` não reler setting novo | Modo não aplica sem recarregar | Registrar o refresh junto de `refreshComposer` (`panel.luau:56`) e no `onConfigChanged` (`panel.luau:1647`). |

## Métricas de sucesso (observação manual)

1. Um pedido com 5 ferramentas ocupa **1 linha**, não 5 cards.
2. Existe um modo em que a conversa mostra **só texto** e o indicador de trabalho.
3. Falha de ferramenta é identificável **sem clicar**.
4. O rodapé informa consumo (tokens/custo) durante e após o run.
5. Fechar e reabrir o painel não perde preferências nem rascunho.
6. Nenhuma sessão fica travada esperando permissão em outra aba do chat.
