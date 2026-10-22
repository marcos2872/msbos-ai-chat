# Configuração

## Settings do plugin

Definidos em `plugin/plugin.toml` e exibidos em **Settings → Plugins → omyfedora AI Chat**. As labels vêm de `plugin/translations/pt-BR.json` (fallback `en.json`).

| Chave | Tipo | Padrão | Efeito |
|---|---|---|---|
| `directory` | string | `~/.omyfedora-ai-chat` | Workspace do chat: escopo das sessões, `state/` e `sessions/`. |
| `agent` | string | `omyfedora-chat` | Agente usado em **novas** sessões e na checagem `agentMissing`. |
| `opencode_bin` | string | `opencode` | Binário executado para `opencode pair`. |
| `auto_pair` | bool | `true` | Re-pareia automaticamente em `401` do SSE. |
| `auto_export` | bool | `true` | Espelha cada conversa em JSON/Markdown. |
| `notify_on_finish` | bool | `true` | Notifica quando a resposta termina com o painel fechado. |
| `show_bar_label` | bool | `false` | Mostra o título curto ao lado do ícone da barra. |
| `max_tool_output` | int | `4000` (500–20000) | Limite de saída de ferramenta no **Markdown exportado**. |
| `panel_size` | select | `medium` | Preset de tamanho; reescreve o manifesto instalado e recarrega. |
| `glyph` (widget) | glyph | `message-chatbot` | Ícone Tabler do widget. |

### Observações de comportamento

- `agent` vale para novas sessões; uma sessão existente mantém o agente que já tem. O IPC `set_agent` troca o agente da sessão ativa.
- `max_tool_output` é usado por `store.sessionMarkdown` no export. O cartão de ferramenta da UI usa um limite fixo de 4000 caracteres; a entrada é limitada a 1200 por `format.toolInput`.
- `panel_size` não altera o tamanho em runtime: o Noctalia não expõe API de resize. O engine edita a cópia instalada do `plugin.toml`.
- `auto_pair` não é usado no health check; apenas na queda do SSE com `401`.

## Manifesto

### Identidade

```toml
id = "omyfedora/ai-chat"
name = "omyfedora AI Chat"
version = "0.1.0"
plugin_api = 34
author = "omyfedora"
license = "MIT"
icon = "message-chatbot"
dependencies = ["opencode", "niri", "noctalia"]
```

`plugin_api = 34` reflete o teto testado no Noctalia 5.3.0 instalado. Features usadas incluem `httpStream`, `runAsync` com argv, `ui.select`, `ui.input` multiline, `ui.markdown`, `ui.scroll` com `stickToBottom`, `panel.setNeedsFrameTick` e `panel.layer = "overlay"`.

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

Quando o setting muda, `applyPanelSize()`:

1. lê o `plugin.toml` instalado via `noctalia.pluginDir()`;
2. localiza a primeira seção `[[panel]]`;
3. reescreve `width` e `height`;
4. grava um backup `plugin.toml.bak-size`;
5. executa em background:
   `noctalia msg plugins disable omyfedora/ai-chat` → espera → `enable`.

O `plugin.toml` do repositório permanece em 460 × 640; a preferência do usuário fica na cópia instalada.

## Workspace

Padrão: `~/.omyfedora-ai-chat`.

```text
~/.omyfedora-ai-chat/
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
| `OMYFEDORA_AI_CHAT_DIR` | Workspace criado pelo `install.sh`; padrão `~/.omyfedora-ai-chat`. |

> O setting `directory` do plugin é independente de `OMYFEDORA_AI_CHAT_DIR`. Se usar um diretório customizado no instalador, ajuste também **Settings → Plugins → Diretório do chat** para o mesmo caminho.

## Configuração do agente

Arquivo instalado: `~/.config/opencode/agents/omyfedora-chat.md`.

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
- A skill `omyfedora` deve existir em `~/.agents/skills/omyfedora/` (ou em um dos diretórios globais descobertos pelo OpenCode).
- A confirmação de mudanças é feita no texto; não há cartão de permissão para shell/edit no painel.
- Para root, o agente usa `niri msg action spawn -- alacritty -e /usr/bin/pkexec /usr/local/libexec/omyfedora-priv ...` (TTY + polkit) porque o servidor do OpenCode Desktop roda com `NoNewPrivs=1`; veja [Segurança](seguranca.md).
- O instalador faz backup do agente anterior como `omyfedora-chat.md.bak-<timestamp>`.

## Configuração do host (Noctalia)

- O painel usa a transparência, o raio e a sombra definidos pelo tema/host. O plugin não força `shadow` nem desenha fundo próprio.
- O widget precisa ser adicionado manualmente em **Settings → Bar → Widgets → `omyfedora/ai-chat:bar`**; o instalador não edita `settings.toml` (arquivo do host).
- O plugin pode ser habilitado por **Settings → Plugins** ou:

```bash
noctalia msg plugins enable omyfedora/ai-chat
```

## Reload e aplicação de mudanças

Depois de editar arquivos no repositório, instale a cópia nova:

```bash
./install.sh
```

Para recarregar sem reinstalar:

```bash
noctalia msg plugins disable omyfedora/ai-chat
noctalia msg plugins enable omyfedora/ai-chat
```

Para validar o manifesto:

```bash
noctalia plugins lint ~/.local/share/noctalia/plugins/omyfedora-ai-chat
```

## Arquivos de configuração relacionados

| Caminho | Dono | Observação |
|---|---|---|
| `plugin/plugin.toml` | Projeto | Fonte do manifesto; não é o arquivo que recebe o preset de tamanho. |
| `~/.local/share/noctalia/plugins/omyfedora-ai-chat/plugin.toml` | Plugin instalado | Recebe `width`/`height` do preset e backup `.bak-size`. |
| `~/.config/opencode/agents/omyfedora-chat.md` | OpenCode | Agente instalado pelo script. |
| `~/.agents/skills/omyfedora/SKILL.md` | Skill global | Não é instalada por este projeto. |
| `~/.config/noctalia/config.toml` | Noctalia | Tema/transparência do host; não é editado pelo plugin. |
| `~/.local/state/noctalia/settings.toml` | Noctalia | Estado de plugins/widgets; não editar à mão. |
