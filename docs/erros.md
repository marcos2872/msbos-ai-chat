# Erros e diagnóstico

## Estados do serviço

| Estado | Significado | O que fazer |
|---|---|---|
| `unpaired` | Sem token válido. | Conectar automaticamente ou colar link de `opencode pair`. |
| `pairing` | Pareamento em andamento. | Aguardar; se demorar, verificar `opencode pair`/logs. |
| `offline` | Token existe, mas o health check falhou. | Abrir o app OpenCode ou `opencode serve`; **Tentar novamente**. |
| `idle` | Pronto. | Usar o chat. |
| `busy` | Execução em andamento. | Aguardar ou **Parar**. |
| `error` | Última operação falhou. | Ler a mensagem no painel e o log. |

## Mensagens da UI

| Mensagem | Causa provável | Resolução |
|---|---|---|
| “OpenCode não está respondendo.” | Servidor parado, porta errada ou health check falhou. | Abrir o app/`opencode serve`; conferir `baseUrl`; tentar novamente. |
| “Conecte o OpenCode primeiro.” | Ação de sessão/prompt sem pairing. | Parear. |
| “OpenCode não está pareado.” | Requisição de dados sem token. | Parear. |
| “Sem resposta do OpenCode.” | Falha de rede/host sem resposta HTTP. | Verificar servidor, firewall e túnel. |
| “Binário não encontrado: …” | `opencode_bin` errado ou fora do `PATH`. | Ajustar o setting ou instalar o OpenCode. |
| “Link inválido. Cole o link completo exibido por `opencode pair`.” | Link malformado. | Copiar novamente o link completo. |
| “Link expirado ou já usado. Rode `opencode pair` novamente.” | Link de uso único expirado. | Gerar novo link. |
| “`opencode pair` falhou.” | CLI retornou erro. | Rodar `opencode pair` no terminal e ler o erro. |
| “Não encontrei o link no output de `opencode pair`.” | Saída inesperada/versão diferente. | Rodar manualmente e colar o link. |
| “O servidor não devolveu um token de sessão.” | Resposta de pareamento sem `token`. | Verificar versão do OpenCode; tentar de novo. |
| “Falha ao criar sessão.” | API recusou a criação (agente/modelo/diretório). | Conferir agente, modelo e workspace; ver log. |
| “A execução falhou.” | Evento `session.execution.failed`. | Ver erro da última mensagem e log. |
| “Erro na execução.” | `session.error` sem detalhe. | Ver log/contexto; tentar novamente. |
| “O agente precisa de uma resposta.” | Formulário pendente com painel fechado. | Abrir o painel e responder. |
| “Ação sensível bloqueada automaticamente: …” | Permissão de ação não allowlisted foi recusada. | Avaliar se o agente precisa da ação; ver [Segurança](seguranca.md). |
| “Não consegui redimensionar o painel: …” | Falha ao gravar o `plugin.toml` instalado. | Conferir permissões do diretório do plugin. |
| “Não consegui recarregar o plugin para aplicar o novo tamanho.” | `nohup`/`noctalia` indisponível. | Recarregar manualmente em Settings → Plugins. |
| “Falha ao falar com o serviço do chat.” | IPC `noctalia msg plugin` falhou. | Verificar se o plugin/serviço está habilitado. |
| “Não foi possível falar com o serviço do chat.” | `runAsync` não iniciou. | Verificar `noctalia` no `PATH` e o serviço. |

## Diagnóstico rápido

```bash
# versão e saúde do plugin
noctalia msg status

# plugins descobertos
noctalia msg plugins list

# lint do plugin instalado
noctalia plugins lint ~/.local/share/noctalia/plugins/omyfedora-ai-chat

# saúde do OpenCode (sem auth)
curl -s http://127.0.0.1:49374/global/health

# log do Noctalia
tail -n 200 ~/.cache/noctalia/noctalia.log

# erros do plugin
grep -iE 'omyfedora-ai-chat|script-runtime.*error' ~/.cache/noctalia/noctalia.log | tail -n 80
```

### Abrir o painel e o seletor

```bash
noctalia msg panel-toggle omyfedora/ai-chat:panel
noctalia msg plugin omyfedora/ai-chat:panel all open_picker
```

### Recarregar o plugin

```bash
noctalia msg plugins disable omyfedora/ai-chat
noctalia msg plugins enable omyfedora/ai-chat
```

## Problemas comuns

### Plugin não aparece em Settings → Plugins

- Confirme que a pasta está em `~/.local/share/noctalia/plugins/omyfedora-ai-chat/`.
- Rode o lint; um manifesto inválido impede a descoberta.
- Reinicie o Noctalia ou aguarde a descoberta; depois habilite.
- Confira `noctalia msg plugins list`.

### Widget não aparece na barra

O instalador **não** adiciona o widget. Use **Settings → Bar → Widgets → `omyfedora/ai-chat:bar`**. Não edite `settings.toml` à mão.

### Painel offline mesmo com o OpenCode aberto

- Confira a porta em `state/pairing.json` e `curl /global/health`.
- Se o servidor mudou de porta, re-pareie.
- Se o token expirou, o SSE pode voltar `401`; com `auto_pair` ele tenta re-parear.
- O health check de recuperação roda a cada 15 s; **Tentar novamente** força `sync`.

### SSE cai e não volta

- O backoff chega a 30 s; aguarde.
- Verifique o log por “SSE caiu” e “SSE conectado”.
- Se o token estiver inválido, re-pareie.
- Eventos perdidos não têm replay; reabra a sessão para reconciliar `/context`.

### Sessão não aparece na lista

- A lista é escopada por `directory` e limitada a 50, ordem decrescente.
- Confirme que a sessão foi criada no workspace configurado.
- Use **refresh_sessions** via IPC ou reabra o seletor.

### Modelo ou variante não aparece

- O modelo precisa estar `enabled` e não `deprecated` em `/api/model`.
- O seletor de raciocínio só aparece se o modelo tiver `variants`.
- `variant: "default"` não é enviado; é o comportamento esperado.
- Recarregue o catálogo (`refresh_models`) ou reabra o seletor.

### Nova conversa não herda o modelo

- O painel envia o modelo da sessão atual; se não houver, o engine usa `preferredModel`.
- Se a sessão atual não tem modelo, o engine tenta o modelo da última mensagem do assistente.
- Confirme em `state/ui.json` se `preferredModel` foi gravado após um `set_model` bem-sucedido.
- Sessões existentes não são alteradas; a herança vale para novas.

### Formulário de pergunta não aparece

- O formulário só é mostrado para a **sessão ativa**.
- `form.created` pode trazer o `sessionID` em `data.form`; o engine já trata antes do filtro.
- Se o painel estava fechado, a notificação aparece; abra o painel.
- Recarregue o plugin se estiver em uma versão antiga.
- Verifique no log se o evento chegou.

### `pkexec must be setuid root` / polkit não abre

O servidor do OpenCode Desktop roda com `NoNewPrivs=1`; o `pkexec` direto pelo shell do agente não consegue elevar. O agente deve iniciar o helper pelo niri:

```bash
niri msg action spawn -- /usr/bin/pkexec /usr/local/libexec/omyfedora-priv <subcomando> [argumentos...]
```

- Confirme que `niri` está rodando e que existe um agente polkit na sessão (no ambiente de referência, `polkit-kde-authentication-agent-1`).
- O comando retorna imediatamente; a janela do polkit aparece para o usuário.
- Depois do spawn, procure a janela em `niri msg --json windows` (`app_id = org.kde.polkit-kde-authentication-agent-1`) e foque com `niri msg action focus-window --id <id>`. Ela pode abrir em outro workspace/monitor.
- Se a janela não existir, pare e reporte; não fique esperando 90 s nem presuma que a ação rodou.
- Valide o resultado com leitura (`rpm -q`, `systemctl status`, `dnf history list`).
- Se a janela não aparecer, não use `sudo`; pare e explique.
- `niri msg action spawn -- /usr/bin/pkexec --version` pode ser usado como teste seguro, sem pedir senha.

### Painel com fundo/borda duplicados

O `frame` do plugin deve permanecer transparente; o host desenha o fundo. Não adicione `fill`/`border` ao `frame()` nem um `shadow` próprio. Se o sintoma voltar, revise `panel.luau` e a configuração de transparência do host.

### Tamanho não muda

- O host não tem API de resize; o preset reescreve o `plugin.toml` **instalado** e recarrega.
- Confira `width`/`height` no arquivo instalado e o backup `plugin.toml.bak-size`.
- Se o arquivo não for gravável, o engine notifica erro.
- Recarregue manualmente o plugin.

### Export não é gerado

- `auto_export` precisa estar ligado.
- A execução precisa terminar (sucesso/falha/interrupção) para `finishRun` chamar o export.
- Confira permissões de `sessions/` e o log por “falha ao exportar sessão”.
- O endpoint é experimental e pode mudar entre versões do OpenCode.

### Notificação não aparece

- `notify_on_finish` precisa estar ligado.
- Só notifica quando o painel está fechado (`chat.panel_open = false`).
- Verifique as notificações do desktop/Noctalia.

## Códigos HTTP

| Código | Causa | Ação |
|---|---|---|
| `400` | Corpo inválido. | Ver mensagem do OpenCode. |
| `401` | Token ausente/inválido. | Re-parear. |
| `403` | Permissão negada pelo servidor. | Ver regras do OpenCode. |
| `404` | Sessão/form/permission não encontrado. | Recarregar sessões. |
| `422` | Validação falhou. | Corrigir payload/campo. |
| `500` | Erro interno do OpenCode. | Ver log do servidor; tentar novamente. |

## Limitações de diagnóstico

- Não há testes automatizados; a validação é manual (veja [Desenvolvimento](desenvolvimento.md)).
- Não há endpoint de métricas do plugin.
- O log do Noctalia é a principal fonte; o plugin usa `noctalia.log` para eventos de SSE, export, permissões e tamanho.
