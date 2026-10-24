# API do OpenCode usada pelo plugin

Referência das chamadas implementadas em `plugin/lib/api.luau` e consumidas por `plugin/engine.luau`. O contrato foi validado contra a API v2 do OpenCode 2.1.4; versões diferentes podem mudar caminhos ou schemas.

## Convenções

- Base: `pairing.baseUrl` (origem do link de pareamento).
- Autenticação: Basic auth `opencode:<token>` em todas as chamadas de dados.
- Diretório: o cliente acrescenta `?directory=<workspace>` quando a chamada recebe `opts.directory`.
- JSON: requisições enviam `Content-Type: application/json`; respostas são decodificadas como JSON.
- `204 No Content`: o cliente devolve `true`.
- Erros HTTP: o cliente devolve `{ status, message }`.

## Endpoints

| Método | Caminho | Diretório | Corpo | Resposta usada | Uso no plugin |
|---|---|---|---|---|---|
| `GET` | `/global/health` | Não | — | `{ healthy, version }` | Não usado: não valida o token e no v2 pode responder com o HTML da SPA. |
| `GET` | `/auth/connect/{code}` | Não | — | `{ token }` | Consumir link do `opencode pair`. |
| `GET` | `/api/model` | Não | — | `{ data: Model.Info[] }` | Catálogo global de modelos. |
| `GET` | `/api/model/default` | Não | — | `{ data: Model.Info ou null }` | Disponível no cliente, **não usado** pelo engine. |
| `GET` | `/api/agent` | Não | — | `{ data: Agent.Info[] }` | Catálogo global de agentes **e sonda autenticada** (detecta `401`). |
| `GET` | `/api/session?limit=50&order=desc` | Sim | — | `{ data: Session.Info[] }` | Lista as sessões do workspace. |
| `POST` | `/api/session` | Sim | `{ title?, agent?, model?, location: { directory } }` | `{ data: Session.Info }` | Cria sessão com agente/modelo herdados. |
| `GET` | `/api/session/{id}/context` | Sim | — | `{ data: Session.Message[] }` | Carrega/reconcilia mensagens. |
| `POST` | `/api/session/{id}/prompt` | Sim | `{ text }` | `{ data: Session.Inbox.User }` | Envia mensagem. |
| `POST` | `/api/session/{id}/interrupt` | Sim | — | resposta qualquer | Interrompe a execução. |
| `POST` | `/api/session/{id}/generate` | Sim | — | `SessionGenerateResponse` | Regenera a resposta da sessão (botão **Regenerar**). |
| `POST` | `/api/session/{id}/model` | Sim | `{ model: Model.Ref }` | `204` | Troca modelo/variante da sessão. |
| `POST` | `/api/session/{id}/agent` | Sim | `{ agent: string }` | `204` | Troca o agente da sessão via IPC (sem UI dedicada). |
| `PATCH` | `/api/session/{id}` | Sim | `{ title }` | resposta qualquer | Renomeia a sessão com o primeiro prompt. |
| `DELETE` | `/api/session/{id}` | Sim | — | `204` | Apaga a sessão no OpenCode. |
| `GET` | `/api/session/{id}/permission` | Sim | — | `{ data: Permission.Request[] }` | Pendências ao selecionar a sessão. |
| `POST` | `/api/session/{id}/permission/{requestID}/reply` | Sim | `{ decision }` | `204` | Responde `once`, `always` ou `reject`. |
| `GET` | `/api/session/{id}/form` | Sim | — | `{ data: Form.Info[] }` | Formulários pendentes ao selecionar a sessão. |
| `POST` | `/api/session/{id}/form/{formID}/reply` | Sim | `{ answer }` | `204` | Responde um formulário/`question`. |
| `GET` | `/api/experimental/session/{id}/export?sanitize=false` | Sim | — | `{ data: { info, messages } }` | Espelha a sessão em JSON/Markdown. |
| `GET` | `/api/event` | Não | — | SSE `text/event-stream` | Streaming de eventos. |

> O plugin não usa `/api/command`, `/api/form` global nem `/api/permission/request` global. As pendências são buscadas por sessão ao selecioná-la.

## Model.Ref e variantes

```json
{
  "id": "deepseek-v4.1-flash",
  "providerID": "opencode-go",
  "variant": "low"
}
```

- `id` e `providerID` são obrigatórios.
- `variant` é opcional.
- O plugin não envia `variant: "default"`; quando o valor é `default`, o campo é omitido e o OpenCode escolhe o padrão.
- As variantes vêm de `Model.Info.variants[]`; o painel mostra os IDs crus (`default`, `low`, `high`, `max` etc.) e só exibe o seletor quando o modelo tem variantes.

## Model.Info (campos usados)

| Campo | Uso |
|---|---|
| `id` ou `modelID` | Identificador do modelo. |
| `providerID` | Provedor. |
| `name` | Label na UI. |
| `variants[].id` | Opções de raciocínio. |
| `enabled` | Modelos com `false` são ignorados. |
| `status` | Modelos `deprecated` são ignorados. |

## Session.Info (campos usados)

| Campo | Uso |
|---|---|
| `id` | Identificador da sessão. |
| `title` | Título exibido; o primeiro prompt renomeia “Nova conversa”. |
| `time.updated` | Ordenação/“há quanto tempo”. |
| `model` | `Model.Ref` da sessão. |
| `agent` | Agente da sessão. |
| `location` | Origem/workspace. |

## Mensagens de contexto

O engine mapeia apenas dois tipos de mensagem:

| Tipo | Conteúdo usado |
|---|---|
| `user` | `id`, `text`. |
| `assistant` | `id`, `model`, `error`, `content[]`. |

Dentro de `assistant.content[]`:

| Tipo | Uso |
|---|---|
| `text` | Texto concatenado da resposta. |
| `reasoning` | Texto concatenado do raciocínio. |
| `tool` | `id`, `name`, `state.status`, `state.input`, `state.content`/`state.error`. |

Tipos como `system`, `skill`, `shell`, `compaction` e `idle` não são renderizados.

## Form.Info e campos

```json
{
  "id": "form_...",
  "sessionID": "ses_...",
  "title": "Questions",
  "metadata": { "kind": "question" },
  "fields": [
    {
      "key": "q0",
      "title": "Qual ajuste?",
      "description": "Escolha uma opção.",
      "type": "string",
      "options": [
        { "value": "Gap 8", "label": "Gap 8", "description": "Reduz o espaçamento." }
      ],
      "custom": true
    }
  ]
}
```

Tipos de campo no schema do OpenCode: `string`, `number`, `integer`, `boolean`, `multiselect`, `external`.

O painel atualmente:

- renderiza `boolean` como toggle;
- renderiza `string` com `options` como cartões de seleção única;
- renderiza `multiselect` como cartões alternáveis;
- renderiza os demais tipos como `ui.input` de texto;
- **não** implementa o campo livre de `custom`, a lógica de `when`, `hidden`, `required` ou a renderização dedicada de `external`.

A ferramenta `question` cria um campo `q0`, `q1`, … por pergunta, com `type = "multiselect"` quando `multiple = true` e `string` nos demais casos. O `custom = true` do schema não é transformado em opção livre pelo painel.

## Permission.Request

| Campo | Uso |
|---|---|
| `id` | ID da solicitação. |
| `sessionID` | Sessão dona. |
| `action` | `shell`, `edit`, `question`, `form` etc. |
| `resources` | Recursos afetados. |
| `save` | Escopos “sempre”. |
| `message` | Texto exibido pelo OpenCode. |
| `metadata` / `source` | Contexto adicional. |

Respostas válidas: `once`, `always`, `reject`.

O engine só autoaprova `question`/`form`. `shell`, `edit` e ações desconhecidas
ficam **pendentes** e viram um cartão no painel, respondido com `once`
(Permitir uma vez), `always` (Permitir sempre) ou `reject` (Recusar).

## Export

`GET /api/experimental/session/{id}/export?sanitize=false` devolve a sessão completa. O plugin usa `sanitize=false` de propósito: com `sanitize=true`, o OpenCode redige o texto real. O arquivo local é gravado com `0600`.

## Exemplos com `curl`

Substitua `$BASE` e `$TOKEN` pelos valores de `~/.msbos-ai-chat/state/pairing.json`:

```bash
BASE="http://127.0.0.1:49374"
TOKEN="<token>"

curl -s -u "opencode:$TOKEN" -o /dev/null -w '%{http_code}\n' "$BASE/api/agent"

curl -s -u "opencode:$TOKEN" \
  "$BASE/api/session?limit=50&order=desc&directory=$HOME/.msbos-ai-chat"

curl -s -u "opencode:$TOKEN" \
  "$BASE/api/session/ses_xxx/context?directory=$HOME/.msbos-ai-chat"

curl -s -u "opencode:$TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Olá"}' \
  "$BASE/api/session/ses_xxx/prompt?directory=$HOME/.msbos-ai-chat"
```

## Códigos e erros

| HTTP | Significado no plugin |
|---|---|
| `200` | Sucesso com corpo. |
| `204` | Sucesso sem corpo (modelo, agente, permissão, formulário, delete). |
| `400` | Corpo inválido; a mensagem do servidor é exibida. |
| `401` | Token inválido/expirado; SSE re-pareia se `auto_pair`; chamadas mostram erro. |
| `404` | Sessão/form/permission inexistente; erro exibido. |
| `500` | Falha do servidor; erro exibido. |

O parser de erro tenta `message`, `error`, `error.message` e `_tag`; quando há status, acrescenta `(HTTP n)`.
