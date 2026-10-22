# AGENTS.md — omyfedora AI Chat

Instruções para agentes que trabalham neste repositório. A documentação funcional atual está em [`docs/index.md`](docs/index.md); o `MAPEAMENTO.md` é histórico.

## Comandos

Não há `package.json`, `Makefile`, workflow de CI, build step nem suíte automatizada neste repositório. Os comandos abaixo foram confirmados em `install.sh`, `uninstall.sh`, `plugin/engine.luau`, `plugin/panel.luau` e `plugin/bar.luau`.

### Instalação e operação

| Objetivo | Comando | Fonte |
|---|---|---|
| Instalar/atualizar plugin, agente e workspace | `./install.sh` | `install.sh` |
| Instalar com outro workspace | `OMYFEDORA_AI_CHAT_DIR=/caminho ./install.sh` | `install.sh` |
| Desinstalar preservando o workspace | `./uninstall.sh` | `uninstall.sh` |
| Desinstalar e apagar workspace/sessões | `./uninstall.sh --purge` | `uninstall.sh` |
| Lint do plugin instalado | `noctalia plugins lint "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/omyfedora-ai-chat"` | `install.sh` |
| Habilitar o plugin | `noctalia msg plugins enable omyfedora/ai-chat` | `install.sh` |
| Desabilitar o plugin | `noctalia msg plugins disable omyfedora/ai-chat` | `uninstall.sh`, `engine.luau` |
| Recarregar após editar | desabilitar + habilitar (comandos acima) | `engine.luau`, `uninstall.sh` |
| Abrir/fechar o painel | `noctalia msg panel-toggle omyfedora/ai-chat:panel` | `install.sh` |
| Parear manualmente | `opencode pair` | `install.sh`, `engine.luau` |
| Iniciar um servidor OpenCode local | `opencode serve` | `panel.luau` (estado offline) |
| Listar plugins descobertos | `noctalia msg plugins list` | `install.sh` |

### Build, teste e lint

| Etapa | Situação |
|---|---|
| Build | Não existe. Os arquivos `.luau` são copiados e carregados diretamente pelo Noctalia. |
| Teste automatizado | Não existe. Use o checklist manual de [`docs/desenvolvimento.md`](docs/desenvolvimento.md). |
| Lint | `noctalia plugins lint …`; o esperado é `0 errors, 0 warnings`. |

Ao concluir uma mudança, rode o lint e informe a evidência. Se a mudança for visual, a validação final é do usuário.

## Arquitetura

O projeto é um plugin do **Noctalia 5.3** (`plugin_api = 34`) com três entradas e um serviço. O `engine` é a fonte de verdade; o painel é uma view e a barra apenas observa o status.

| Caminho | Papel |
|---|---|
| `plugin/plugin.toml` | Manifesto, settings, serviço `engine`, widget `bar` e painel `panel`. |
| `plugin/bar.luau` | Ícone/status na barra e toggle do painel. |
| `plugin/panel.luau` | Chat, compositor, formulários, onboarding e view do seletor de modelo/sessão. |
| `plugin/engine.luau` | Pareamento, SSE, estado, sessões, permissões, formulários, exports e tamanho do painel. |
| `plugin/lib/api.luau` | Cliente HTTP/SSE da API v2 do OpenCode. |
| `plugin/lib/store.luau` | Workspace, `pairing.json`, `ui.json` e exports JSON/Markdown. |
| `plugin/lib/format.luau` | Formatação de modelos, ferramentas, erros e tempo. |
| `plugin/translations/` | Labels dos settings em pt-BR/en. |
| `opencode/agents/omyfedora-chat.md` | Agente primário e regras de segurança/root. |
| `install.sh` / `uninstall.sh` | Instalação e remoção local. |

Fluxo resumido:

```text
panel.luau --IPC--> engine.luau --HTTP/SSE--> OpenCode local
   ^                    |
   |                    +--> ~/.omyfedora-ai-chat/{state,sessions}
   +---- noctalia.state (chat.snapshot/status/models/sessions)
```

- O painel **não** fala direto com o OpenCode; toda ação passa por IPC (`noctalia msg plugin …:engine all <evento> [payload]`).
- O engine publica `chat.snapshot`, `chat.status`, `chat.models` e `chat.sessions`; o painel publica `chat.panel_open`.
- O SSE (`/api/event`) alimenta o streaming; `/context` reconcilia as mensagens ao selecionar a sessão e ao final da execução.
- O seletor está dentro de `panel.luau`; não existem `picker.luau` nem `lib/sse.luau` no código atual.
- O painel é `persistent = false`, `position = "top_right"`, `layer = "overlay"`; o host desenha fundo/borda. O frame do plugin é transparente.
- O tamanho usa presets (`compact` 420×560, `medium` 460×640, `large` 620×820); o engine reescreve `width`/`height` do `plugin.toml` instalado e recarrega o plugin.
- Novas conversas herdam o modelo/variante atuais; a precedência é `opts.model` → `preferredModel` em `ui.json` → modelo da sessão ativa. `variant = "default"` é omitido.
- Ao apagar a sessão ativa, o engine limpa a sessão ativa e o painel permanece no seletor; não abre a primeira sessão. Clicar em uma linha do seletor abre a sessão.
- `shell`/`edit` são automáticos (sem cartão de permissão). Formulários da ferramenta `question` são renderizados e respondidos pelo painel.
- No ambiente atual, o servidor do OpenCode Desktop roda com `NoNewPrivs=1`. Root é acionado pelo helper via `niri msg action spawn -- alacritty -e /usr/bin/pkexec /usr/local/libexec/omyfedora-priv …`, nunca por `sudo`; o terminal fornece TTY, e o agente localiza/foca a janela do polkit e valida o resultado com leitura.
- Estado e exports ficam em `~/.omyfedora-ai-chat`; `pairing.json`/`ui.json` e sessões são gravados com `0600`.

## Convenções

- Responda e documente em **português brasileiro**; identificadores de código/API permanecem em inglês.
- Luau com `--!nonstrict`; sem dependências externas, bundler ou etapa de build.
- O engine é o único que faz rede; o painel só envia IPC e lê `noctalia.state`.
- Use `noctalia.runAsync` com argv para IPC; não monte comandos de shell para ações do painel.
- Em callbacks assíncronos, respeite `generation`/`streamGeneration` para ignorar respostas antigas.
- Não adicione `fill`/`border`/`shadow` ao frame do painel; o tema do host já desenha o fundo.
- Use roles do tema (`primary`, `on_primary`, `surface_variant`, `outline`, `error` etc.). Seleção: `primary` no item ativo e `surface_variant/0.35` nos demais.
- Modelo/raciocínio usam os IDs crus (`default`, `low`, `high`, `max`); não traduza variantes. Novas conversas devem preservar modelo e variante.
- Não presuma cartão de permissão para shell/edit; o fluxo atual é automático. Só os subcomandos da skill `omyfedora` podem ser acionados como root.
- Root: nunca `sudo`; use `pkexec` pelo `niri` devido ao `NoNewPrivs`, valide depois com `rpm -q`, `systemctl status` ou `dnf history list`, e não afirme sucesso sem evidência.
- Segurança: não logue token/link de pareamento; mantenha `pairing.json`, `ui.json` e exports com `0600`; não apague o workspace sem `--purge` explícito.
- **A documentação evolui com o código.** Mudou IPC, evento, setting, estado, fluxo de UI, conexão, segurança ou instalação? Atualize o arquivo correspondente em `docs/` e o `README.md` no mesmo trabalho. O `MAPEAMENTO.md` é histórico; não o use como fonte do estado atual.
- Não invente comandos, endpoints ou campos. Confirme em `install.sh`, `uninstall.sh`, `plugin.toml`, no código Luau ou na API real antes de documentar.
- Teste manual: siga o checklist de [`docs/desenvolvimento.md`](docs/desenvolvimento.md); registre lint e resultados no final.

## Memória do projeto

- Ao aprender algo durável sobre este projeto (decisão, convenção, armadilha, preferência do usuário), salve com a tool `memory_write` — uma frase objetiva por memória.
- As memórias são injetadas automaticamente no seu contexto (bloco `<project-memory>`); siga-as.
- Liste com `memory_list` e remova memórias obsoletas com `memory_delete`; o usuário também gerencia via `/memory`.
