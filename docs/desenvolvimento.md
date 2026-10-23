# Desenvolvimento

## Ambiente

- Fedora com niri e Noctalia 5.3+.
- OpenCode 2.x com `opencode` no `PATH`.
- Skill `omyfedora` em `~/.agents/skills/omyfedora/`.
- `noctalia`, `bash` e utilitários básicos.

O plugin é escrito em **Luau** (`--!nonstrict`), sem build step. A instalação copia os arquivos diretamente para o diretório de plugins do Noctalia.

## Estrutura de trabalho

```text
plugin/                 # fonte do plugin
plugin/lib/             # api, store e format
opencode/agents/        # agente
install.sh              # cópia plugin + agente + workspace
uninstall.sh            # remoção
docs/                   # esta documentação
```

O runtime lê a cópia em `~/.local/share/noctalia/plugins/omyfedora-ai-chat/`, não o repositório. Depois de editar, reinstale.

## Ciclo de desenvolvimento

```bash
cd /caminho/para/omyfedora-ai-chat

# 1. instalar a cópia nova (faz backup do agente)
./install.sh

# 2. lint do plugin instalado
noctalia plugins lint ~/.local/share/noctalia/plugins/omyfedora-ai-chat

# 3. recarregar se o install não recarregou
noctalia msg plugins disable omyfedora/ai-chat
noctalia msg plugins enable omyfedora/ai-chat

# 4. abrir o painel
noctalia msg panel-toggle omyfedora/ai-chat:panel
```

Resultado esperado do lint:

```text
omyfedora/ai-chat
  ok

0 errors, 0 warnings
```

## Logs

```bash
tail -n 200 ~/.cache/noctalia/noctalia.log

grep -iE 'omyfedora-ai-chat|script-runtime.*error' \
  ~/.cache/noctalia/noctalia.log | tail -n 80
```

O engine registra:

- conexão/queda do SSE e backoff;
- falha ao exportar/renomear sessão;
- permissões automáticas (decisão e ação);
- aplicação do preset de tamanho e recarga;
- falha ao gravar backup/manifesto.

## IPC manual

O painel e o engine podem ser comandados pela CLI:

```bash
# Estado do host
noctalia msg status

# Sincronizar snapshot/modelos/sessões
noctalia msg plugin omyfedora/ai-chat:engine all sync

# Abrir o seletor
noctalia msg plugin omyfedora/ai-chat:panel all open_picker

# Enviar um prompt (payload é um argumento)
noctalia msg plugin omyfedora/ai-chat:engine all prompt "mostre o status do niri"

# Criar nova sessão
noctalia msg plugin omyfedora/ai-chat:engine all new_session "{}"

# Recarregar catálogo/sessões
noctalia msg plugin omyfedora/ai-chat:engine all refresh_models
noctalia msg plugin omyfedora/ai-chat:engine all refresh_sessions
```

> O payload do IPC é um argumento de linha de comando. Evite prompts enormes ou com caracteres que o shell interprete; para volumes grandes, o caminho correto seria um arquivo de outbox (não implementado).

## Depuração de estado

1. Abra o painel; ele envia `sync`.
2. Confira `chat.snapshot`/`chat.status` pelo comportamento da barra e do painel.
3. Se o estado parecer antigo, recarregue o plugin e reabra a sessão.
4. Se o problema for de eventos, veja o log e o `/context` via `curl` (com token).
5. Se o problema for de modelo, confira `state/ui.json` (`model`, `preferredModel`) e `/api/model`.

### Inspecionar arquivos

```bash
ls -l ~/.omyfedora-ai-chat/state ~/.omyfedora-ai-chat/sessions
stat -c '%a %n' ~/.omyfedora-ai-chat/state/pairing.json \
  ~/.omyfedora-ai-chat/state/ui.json \
  ~/.omyfedora-ai-chat/sessions/index.json
```

Não cole o conteúdo de `pairing.json` em issues/logs.

## Testes manuais

Não há suíte automatizada. Checklist mínimo após mudanças:

### Conexão

- [ ] Sem token: onboarding aparece; com `auto_pair`, o engine pareia sozinho.
- [ ] **Conectar automaticamente** pareia e mostra o chat.
- [ ] Link colado inválido mostra erro claro.
- [ ] Boot com o serviço parado: painel mostra `starting` e chega a `idle` sem terminal.
- [ ] Painel abre offline e **Iniciar OpenCode** sobe o serviço (`opencode service status` depois).
- [ ] Porta antiga em `pairing.json`: `ensureService` corrige a `baseUrl` sozinho.
- [ ] Servidor parado por mais de 1 min: retry continua com backoff (5–60 s).
- [ ] Token inválido: sonda `/api/agent` dá `401` e o engine re-pareia com `auto_pair`.
- [ ] Agente ausente no `/api/agent`: cartão aparece; ao voltar, some sem recarregar.
- [ ] Reiniciar o plugin mantém a sessão ativa (`ui.json`).

### Conversa

- [ ] Prompt aparece como mensagem otimista.
- [ ] Texto e raciocínio chegam em streaming.
- [ ] Ferramentas mostram status/entrada/saída e expandem.
- [ ] **Parar** interrompe.
- [ ] Erro do OpenCode aparece no painel.

### Formulário `question`

- [ ] Pedir ao agente para usar `question` com 2–3 opções.
- [ ] O cartão aparece **sem recarregar** o plugin.
- [ ] Selecionar uma opção e **Responder** remove o cartão.
- [ ] O agente continua a execução com a resposta.
- [ ] Painel fechado: notificação “O agente precisa de uma resposta.”

### Sessões e modelos

- [ ] **+** herda o modelo e a variante atuais.
- [ ] Trocar modelo/variante grava `preferredModel` em `ui.json`.
- [ ] Abrir uma sessão antiga carrega o contexto correto.
- [ ] Apagar sessão remove do OpenCode e mantém o espelho local.
- [ ] Lista vazia mostra “Nenhuma sessão ainda.”

### Interface

- [ ] Painel sem fundo/borda duplicados.
- [ ] Selecionada em `primary`; não selecionadas translúcidas.
- [ ] Compositor compacto (altura 36) e botão enviar/parar correto.
- [ ] Spinner anima durante `busy`.
- [ ] Presets de tamanho aplicam e recarregam.

### Export e segurança

- [ ] `sessions/<id>.json` e `.md` são gerados após a execução.
- [ ] Arquivos têm modo `0600`.
- [ ] `pairing.json`/`ui.json` têm modo `0600`.
- [ ] Token não aparece em logs.

### SSE

- [ ] Derrubar/religar o plugin reconecta o SSE.
- [ ] Log mostra “SSE caiu” e “SSE conectado”.
- [ ] Reconectar não duplica mensagens no contexto.

## Como adicionar uma feature

### Novo comando IPC

1. Adicione o `elseif event == "..."` em `onIpc` (`engine.luau`).
2. Adicione o `sendCommand("...", payload)` no painel ou documente o uso manual.
3. Atualize [Componentes](componentes.md#ipc-recebido-pelo-engine).
4. Teste com o painel aberto e com o serviço recarregado.

### Novo evento SSE

1. Adicione o tratamento em `handleEvent`.
2. Respeite a ordem: formulários antes do filtro de sessão.
3. Atualize o snapshot com `publish`/`schedulePublish`.
4. Documente em [Eventos](eventos.md).
5. Teste com uma execução real; não invente payloads.

### Novo setting

1. Adicione `[[setting]]` em `plugin/plugin.toml`.
2. Adicione as labels em `translations/pt-BR.json` e `en.json`.
3. Leia em `init()`/`onConfigChanged()` ou na entrada apropriada.
4. Documente em [Configuração](configuracao.md).

### Novo campo de formulário

1. Estenda `renderForm` para o tipo.
2. Verifique o schema em `Form.*` do OpenCode.
3. Envie o valor no formato esperado por `Form.Value`.
4. Teste com a ferramenta `question` e com um formulário manual.

## Convenções

- Luau `--!nonstrict`; sem dependências externas.
- UI declarativa e sem bloqueio; rede só no engine.
- Estado compartilhado por `noctalia.state`; comandos por IPC.
- Use `generation`/`streamGeneration` em callbacks assíncronos para ignorar respostas antigas.
- Não desenhe fundo/borda no frame do painel.
- Mensagens de UI e docs em português brasileiro; IDs/técnicos em inglês.
- Prefira `noctalia.runAsync` com argv em vez de shell; o único uso de shell é o reload do preset de tamanho.

## Limitações do ambiente de desenvolvimento

- Sem testes unitários, CI ou lint de Luau além do `noctalia plugins lint`.
- O comportamento do host (tamanho, transparência, foco) não é testável fora do Noctalia.
- A API do OpenCode é experimental em parte (`/api/experimental/.../export`); mudanças de versão podem exigir ajustes.
