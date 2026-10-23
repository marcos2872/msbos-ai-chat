# Segurança

## Modelo de confiança

O plugin roda como o usuário do desktop e assume que:

- o servidor do OpenCode está em loopback e pertence ao mesmo usuário;
- o workspace e o token são privados ao usuário;
- comandos IPC do Noctalia são enviados por processos do mesmo usuário.

Não há sandbox próprio: o agente pode executar `shell` e editar arquivos com as permissões do usuário. A segurança depende da combinação de **permissões do OpenCode**, **instruções do agente/skill** e **hábitos do usuário**.

## Token de pareamento

- O token é uma credencial de portadora usada como senha do Basic auth (`opencode:<token>`).
- Fica em `~/.omyfedora-ai-chat/state/pairing.json`, gravado com modo `0600`.
- O código/link do `opencode pair` não é persistido.
- O token não é incluído no snapshot, no status da barra nem nas mensagens de erro.
- O link de pareamento é de uso único e expira em poucos minutos (referência: 5 min).
- Em `401`, o engine limpa o estado e tenta re-parear se `auto_pair = true`.

Se o token vazar:

1. rode `./uninstall.sh` (ou apague `state/pairing.json`);
2. re-pareie com `opencode pair`;
3. verifique se o servidor não está exposto fora de loopback.

## Workspace e exports

| Caminho | Proteção |
|---|---|
| `~/.omyfedora-ai-chat/` | O instalador cria com `700`. |
| `state/` e `sessions/` | O instalador cria com `700`. |
| `pairing.json` | `0600`. |
| `ui.json` | `0600`. |
| `sessions/index.json` | `0600`. |
| `sessions/<id>.json` e `.md` | `0600` (JSON na escrita; Markdown via `chmod` logo após). |

O export usa `sanitize=false`, então o texto real da conversa fica em disco. Isso é intencional para consulta/auditoria local, mas significa que:

- o workspace pode conter comandos, caminhos, trechos de configuração e dados sensíveis;
- backups e cópias do workspace herdam esse conteúdo;
- `./uninstall.sh` preserva o workspace por padrão; use `--purge` apenas quando quiser apagar tudo.

O `AGENTS.md` do workspace repete as regras da skill; ele não é um mecanismo de aplicação, apenas contexto para o agente.

## Permissões do agente

O agente instalado tem:

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

Consequências:

- `edit` e `shell` **não** geram cartão de permissão; o OpenCode executa direto.
- `task` está bloqueado (o agente não delega).
- A barreira para mudanças é o **ritual conversacional** da skill `omyfedora`: descrever, pedir confirmação, backup, aplicar, validar, diff e log.
- O agente é instruído a nunca usar `sudo`; root somente via `pkexec /usr/local/libexec/omyfedora-priv`.
- O agente não deve editar arquivos protegidos do omyfedora nem ler/guardar senhas.
- Conteúdo externo (web, README, saída de ferramentas) é tratado como dado, não instrução.

### Sandbox do OpenCode Desktop e `pkexec`

O servidor iniciado pelo **OpenCode Desktop** roda com `NoNewPrivs=1` (herdado do app Electron). Nesse estado, o bit setuid do `pkexec` é ignorado e o comando direto falha com `pkexec must be setuid root`.

Para o helper privilegiado funcionar, o agente é instruído a iniciar o `pkexec` dentro do **Alacritty** (TTY), pelo **niri**:

```bash
niri msg action spawn -- alacritty -e /usr/bin/pkexec /usr/local/libexec/omyfedora-priv <subcomando> [argumentos...]
```

- O Alacritty fornece um TTY e o polkit abre de forma confiável; o terminal pode fechar quando o helper terminar.
- O `niri` roda como o usuário e não eleva privilégios sozinho; o `pkexec` continua sendo a única via para root e o polkit pede a senha.
- O comando é assíncrono: o agente não recebe stdout/stderr. Depois do spawn, ele deve localizar a janela `org.kde.polkit-kde-authentication-agent-1` em `niri msg --json windows` e focá-la com `niri msg action focus-window --id <id>`; se a janela não existir, deve parar e reportar, sem esperar 90 s.
- A janela pode abrir no workspace/monitor focado pelo niri, que pode ser diferente do painel do chat; focar a janela resolve.
- Se o Alacritty não existir, use `niri msg action spawn -- /usr/bin/pkexec ...` e valide a janela.
- Só os subcomandos do helper devem ser usados; não é um caminho para comandos arbitrários.
- Se o host for reiniciado com um servidor standalone (sem `NoNewPrivs`), o `pkexec` direto também funciona; a instrução via niri continua válida.

### Autoaprovação no engine

Além da configuração do agente, o engine responde `permission.asked` automaticamente:

```text
shell, edit, question, form -> once
qualquer outra ação          -> reject
```

Isso significa que, mesmo que uma permissão seja solicitada, shell/edit não viram um cartão no painel. O painel atual **não renderiza** `pending.permissions`; a lista existe no snapshot apenas para diagnóstico.

### Como endurecer (não implementado)

Para restaurar uma barreira técnica:

1. mudar o agente para `edit: ask` e `shell: ask`;
2. alterar `handleEvent` para **não** autoaprovar `shell`/`edit` (deixar apenas `question`/`form`, ou nenhum);
3. adicionar um cartão de permissão no `chatView` com Permitir uma vez / Sempre / Recusar;
4. testar o fluxo de `permission.asked`/`permission.replied`.

Sem esses passos, a confirmação é apenas textual.

## Servidor OpenCode

- O servidor deve escutar em `127.0.0.1`, não em `0.0.0.0`.
- Não use `--remote`/exposição pública sem uma camada de autenticação e TLS.
- O plugin aceita link remoto colado; isso envia o token ao host remoto e faz o tráfego sair da máquina. Use apenas em túnel confiável.
- A sonda usa `GET /api/agent` com Basic auth; ela valida servidor e token. `/global/health` não é usado (sem auth e, no v2, pode devolver o HTML da SPA).
- O SSE usa Basic auth e não inclui `directory`; o filtro por sessão é feito no cliente.

## IPC do Noctalia

O painel envia comandos via:

```bash
noctalia msg plugin omyfedora/ai-chat:engine all <evento> [payload]
```

Qualquer processo do mesmo usuário que consiga executar `noctalia msg` pode, em tese, enviar prompts, trocar modelo ou responder formulários. O limite de confiança é o usuário local; não há autenticação adicional no IPC.

## Prompt injection e ferramentas

- O agente tem `webfetch: allow`; conteúdo externo pode tentar instruir o modelo. O prompt do agente diz explicitamente que conteúdo externo é dado, não instrução.
- Ferramentas de leitura podem trazer arquivos com instruções maliciosas; o agente deve avisar e perguntar antes de agir.
- O agente tem `shell: allow`; comandos destrutivos são limitados por instrução, não por sandbox. Revise pedidos que envolvam `rm`, `dnf remove`, `systemctl`, `pkexec`, `git push` etc.
- `task: deny` evita delegação para subagentes.

## Instalação e backups

- `install.sh` faz backup do agente anterior em `~/.config/opencode/agents/omyfedora-chat.md.bak-<timestamp>`.
- O preset de tamanho cria `plugin.toml.bak-size` na cópia instalada.
- `uninstall.sh` move o agente para backup e remove o plugin; o workspace só é apagado com `--purge`.
- O plugin não instala dependências do sistema nem altera `sudoers`, PAM, SELinux, greetd, fstab ou kernel.

## Checklist de segurança

- [ ] Servidor do OpenCode em loopback.
- [ ] `pairing.json` com `0600` e workspace com `700`.
- [ ] Token não aparece em logs, issues ou capturas de tela.
- [ ] Permissões do agente revisadas antes de usar em produção.
- [ ] Export `sanitize=false` tratado como dado sensível.
- [ ] `uninstall.sh --purge` usado com consciência.
- [ ] Conteúdo externo não é seguido como instrução.
