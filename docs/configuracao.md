# Configuração

## Settings do plugin

Definidos em `plugin/plugin.toml` e exibidos em **Settings → Plugins → msbos AI Chat**. As labels vêm de `plugin/translations/pt-BR.json` (fallback `en.json`).

| Chave | Tipo | Padrão | Efeito |
|---|---|---|---|
| `directory` | string | `~/.msbos-ai-chat` | Workspace do chat: escopo das sessões, `state/` e `sessions/`. |
| `agent` | string | `msbos-chat` | Agente usado em **novas** sessões e na checagem `agentMissing`. |
| `opencode_bin` | string | `opencode` | Binário executado para `opencode pair`. |
| `auto_pair` | bool | `true` | Re-pareia automaticamente em `401` do SSE. |
| `auto_export` | bool | `true` | Espelha cada conversa em JSON/Markdown. |
| `notify_on_finish` | bool | `true` | Notifica quando a resposta termina com o painel fechado. |
| `show_bar_label` | bool | `false` | Mostra o título curto ao lado do ícone da barra. |
| `max_tool_output` | int | `4000` (500–20000) | Limite de saída de ferramenta no **Markdown exportado**. |
| `panel_size` | select | `medium` | Preset de tamanho; reescreve o manifesto instalado e recarrega. |
| `background_opacity` | int | `45` (0–100) | Alfa do fundo preto fixo do painel; o resto deixa passar a transparência/blur do sistema. `0` = transparente. |
| `glyph` (widget) | glyph | `message-chatbot` | Ícone Tabler do widget. |

### Observações de comportamento

- `agent` vale para novas sessões; uma sessão existente mantém o agente que já tem. O IPC `set_agent` troca o agente da sessão ativa.
- `max_tool_output` é usado por `store.sessionMarkdown` no export. No chat, o snapshot já entrega o `output` truncado em `MAX_SNAPSHOT_TOOL_OUTPUT` (2000) e a entrada limitada a 1200 por `format.toolInput`; o painel trunca de novo em 4000, mas o valor exibido já vem limitado a 2000.
- `panel_size` não altera o tamanho em runtime: o Noctalia não expõe API de resize. O engine edita a cópia instalada do `plugin.toml`.
- `background_opacity` é o alfa do fundo preto fixo do painel: `0` = totalmente transparente, `100` = totalmente preto. O frame usa padding negativo (`Style::panelPadding` = 14 px) para o preto cobrir o painel inteiro, então a borda e o raio do tema ficam atrás do fundo. Com o padrão `45`, o preto fica como um vidro escuro, deixando a transparência e o blur do sistema passarem.
- `auto_pair` controla o pareamento automático (sem pairing) e a recuperação de `401` na sonda e no SSE.

## Manifesto

### Identidade

```toml
id = "msbos/ai-chat"
name = "msbos AI Chat"
version = "0.2.0"
plugin_api = 34
author = "msbos"
license = "MIT"
icon = "message-chatbot"
dependencies = ["opencode", "niri", "noctalia"]
```

`plugin_api = 34` reflete o teto testado no Noctalia 5.3.0 instalado. Features usadas incluem `httpStream`, `runAsync` com argv, `ui.select`, `ui.input`, `ui.markdown`, `ui.scroll` com `stickToBottom`, `panel.setNeedsFrameTick` e `panel.layer = "overlay"`.

### Entradas

| Entrada | ID | Arquivo |
|---|---|---|
| Serviço | `engine` | `engine.luau` |
| Widget | `bar` | `bar.luau` |
| Painel | `panel` | `panel.luau` |

Não há entrada `picker` separada.

### Painel

```toml
[[panel]]
id = "panel"
entry = "panel.luau"
width = 460
height = 640
placement = "floating"
position = "top_right"
open_near_click = false
dismiss_on_outside_click = false
keyboard_focus = "on_demand"
persistent = false
layer = "overlay"
```

O host desenha fundo/borda; o `frame` do plugin é transparente. Não adicione `fill`/`border` ao frame sem remover o fundo do host, ou o painel parecerá duplicado.

### Presets de tamanho

```lua
compact = { width = 420, height = 560 }
medium  = { width = 460, height = 640 }
large   = { width = 620, height = 820 }
```

Quando o setting muda, `applyPanelSize()` executa, em background, `bash plugin/scripts/panel-size.sh <plugin.toml> <largura> <altura>`:

1. o script lê o `plugin.toml` instalado via `noctalia.pluginDir()`;
2. localiza a primeira seção `[[panel]]` e compara com o preset;
3. se mudou, grava `plugin.toml.bak-size`, reescreve `width`/`height` e sai com código `10`;
4. o engine então executa em background:
   `noctalia msg plugins disable msbos/ai-chat` → espera → `enable`.

A leitura/escrita fica no script (e não no callback Luau) porque fazê-la em `onConfigChanged`/`update` estourava o orçamento de CPU do Noctalia. O `plugin.toml` do repositório permanece em 460 × 640; a preferência do usuário fica na cópia instalada.

## Workspace

Padrão: `~/.msbos-ai-chat`.

```text
~/.msbos-ai-chat/
├── AGENTS.md
├── state/
│   ├── pairing.json     # 0600
│   └── ui.json          # 0600
└── sessions/
    ├── index.json       # 0600
    ├── <id>.json        # 0600
    └── <id>.md          # 0600
```

- `AGENTS.md` é criado por `store.ensure()` se não existir, com as regras essenciais da skill.
- O instalador cria as pastas com modo `700`.
- `pairing.json` guarda `baseUrl`, `token`, `version` e `pairedAt`.
- `ui.json` guarda `activeSessionID`, `model`, `preferredModel`, `agent` e `lastOpenedAt`.
- O índice de sessões é atualizado a cada export e ordenado por `updatedAt` decrescente.

### Variáveis de ambiente do instalador

| Variável | Efeito |
|---|---|
| `XDG_DATA_HOME` | Base de `noctalia/plugins`; padrão `~/.local/share`. |
| `XDG_CONFIG_HOME` | Base de `opencode/agents`; padrão `~/.config`. |
| `MSBOS_AI_CHAT_DIR` | Workspace criado pelo `install.sh`; padrão `~/.msbos-ai-chat`. |

> O setting `directory` do plugin é independente de `MSBOS_AI_CHAT_DIR`. Se usar um diretório customizado no instalador, ajuste também **Settings → Plugins → Diretório do chat** para o mesmo caminho.

## Configuração do agente

Arquivo instalado: `~/.config/opencode/agents/msbos-chat.md`.

```yaml
permission:
  edit: allow
  shell: allow
  read: allow
  webfetch: allow
  skill: allow
  question: allow
  task: deny
```

- O agente é `primary`.
- A skill `msbos` deve existir em `~/.agents/skills/msbos/` (ou em um dos diretórios globais descobertos pelo OpenCode).
- A confirmação de mudanças é feita no texto; não há cartão de permissão para shell/edit no painel.
- Para root, o agente usa `niri msg action spawn -- alacritty -e /usr/bin/pkexec /usr/local/libexec/msbos-priv ...` (TTY + polkit) porque o servidor do OpenCode Desktop roda com `NoNewPrivs=1`; veja [Segurança](seguranca.md).
- O instalador faz backup do agente anterior como `msbos-chat.md.bak-<timestamp>`.

## Configuração do host (Noctalia)

- O painel usa a transparência, o raio e a sombra definidos pelo tema/host. O plugin não força `shadow` nem desenha fundo próprio.
- O widget precisa ser adicionado manualmente em **Settings → Bar → Widgets → `msbos/ai-chat:bar`**; o instalador não edita `settings.toml` (arquivo do host).
- O plugin pode ser habilitado por **Settings → Plugins** ou:

```bash
noctalia msg plugins enable msbos/ai-chat
```

## Reload e aplicação de mudanças

Depois de editar arquivos no repositório, instale a cópia nova:

```bash
./install.sh
```

Para recarregar sem reinstalar:

```bash
noctalia msg plugins disable msbos/ai-chat
noctalia msg plugins enable msbos/ai-chat
```

Para validar o manifesto:

```bash
noctalia plugins lint ~/.local/share/noctalia/plugins/msbos-ai-chat
```

## Arquivos de configuração relacionados

| Caminho | Dono | Observação |
|---|---|---|
| `plugin/plugin.toml` | Projeto | Fonte do manifesto; não é o arquivo que recebe o preset de tamanho. |
| `~/.local/share/noctalia/plugins/msbos-ai-chat/plugin.toml` | Plugin instalado | Recebe `width`/`height` do preset e backup `.bak-size`. |
| `~/.config/opencode/agents/msbos-chat.md` | OpenCode | Agente instalado pelo script. |
| `~/.agents/skills/msbos/SKILL.md` | Skill global | Não é instalada por este projeto. |
| `~/.config/noctalia/config.toml` | Noctalia | Tema/transparência do host; não é editado pelo plugin. |
| `~/.local/state/noctalia/settings.toml` | Noctalia | Estado de plugins/widgets; não editar à mão. |
