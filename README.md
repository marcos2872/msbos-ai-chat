# msbos AI Chat

Chat de IA para o desktop **msbos** (Fedora + niri + Noctalia), exibido em um painel flutuante do Noctalia e conectado ao **OpenCode local**. O agente `msbos-chat` segue a skill `msbos` para propor mudanças no sistema, pedir confirmação, aplicar, validar e registrar o resultado.

> Status: implementação local `0.2.0`, testada em Fedora 44, niri, Noctalia 5.3.0 (plugin API 34) e OpenCode 2.1.4.
> O `MAPEAMENTO.md` registra o levantamento inicial. A documentação em [`docs/`](docs/index.md) reflete o código atual.

## Stack

- **Interface/host:** Noctalia 5.3 (Luau, plugin API 34)
- **Motor:** OpenCode 2.x (API v2 local, HTTP + SSE, Basic auth)
- **Desktop:** Fedora + niri
- **Persistência:** JSON e Markdown em `~/.msbos-ai-chat`

## Pré-requisitos

- Fedora com niri e Noctalia 5.3 ou superior.
- OpenCode 2.x instalado, com `opencode` no `PATH`.
- Uma conta de IA conectada ao OpenCode (`opencode auth login`). Sem isso o painel abre, mas não tem modelos para conversar.
- Skill `msbos` instalada em `~/.agents/skills/msbos/` para o agente especialista.
- Helper privilegiado em `/usr/local/libexec/msbos-priv` (allowlist das ações de root). O `install.sh` instala a cópia de `plugin/scripts/msbos-priv` quando ele não existe.
- `alacritty` e `pkexec` (a confirmação de root abre um terminal com a janela de senha do polkit).
- `bash` e utilitários básicos (`cp`, `chmod`, `cmp`).

O plugin **não** instala o OpenCode, o Noctalia nem a skill `msbos`; ele usa o que já está no sistema. O servidor local do OpenCode é iniciado pelo próprio plugin (`opencode service start`) quando necessário — não é preciso abrir o app desktop nem um terminal.

## Instalação

No diretório do projeto:

```bash
cd /caminho/para/msbos-ai-chat
./install.sh
```

Antes de copiar qualquer coisa, o instalador verifica OpenCode, conta de IA, Noctalia, skill `msbos`, helper privilegiado, `alacritty` e `pkexec`, e mostra em português o que falta e como resolver. Nada aborta a instalação: o que faltar aparece no fim como **Pendências** (o chat funciona, mas os recursos que dependem daquilo não). Para pular a verificação, use `MSBOS_AI_CHAT_CHECKS=0 ./install.sh`.

Depois disso, o instalador:

1. copia o plugin para `~/.local/share/noctalia/plugins/msbos-ai-chat/`;
2. copia o agente para `~/.config/opencode/agents/msbos-chat.md` (com backup do anterior);
3. cria `~/.msbos-ai-chat/{state,sessions}` com permissões restritas;
4. roda o lint do plugin e tenta habilitá-lo no Noctalia;
5. instala o helper privilegiado (se ausente) e a regra de polkit que bloqueia `pkexec` para shells.

### Migrando da versão anterior

Se você já tinha o plugin antigo instalado, `./install.sh`:

- move `~/.omyfedora-ai-chat` para `~/.msbos-ai-chat` (sem perder sessões);
- arquiva o plugin e o agente antigos;
- troca o ID `omyfedora/ai-chat` por `msbos/ai-chat` no
  `~/.local/state/noctalia/settings.toml` (com backup).

Depois da instalação:

1. Adicione o widget na barra em **Settings → Bar → Widgets → `msbos/ai-chat:bar`**.
2. Abra o painel:

```bash
noctalia msg panel-toggle msbos/ai-chat:panel
```

3. No painel, clique em **Conectar agora**. Se não conectar, abra **Avançado** e cole o link exibido por `opencode pair`.
4. Em **Settings → Plugins → msbos AI Chat**, ajuste o tamanho da janela, o diretório, o agente e as demais opções.

## Uso rápido

- Clique no ícone da barra para abrir ou fechar o painel.
- **+** cria uma nova conversa herdando o modelo e a variante atuais.
- **Modelos e sessões** (ícone de relógio) abre o seletor de modelo, raciocínio e sessões, com busca e agrupamento por data. Por padrão lista só as conversas criadas pelo painel; sessões de outros clientes do OpenCode ficam ocultas (`only_own_sessions`).
- **Alterações no sistema** (no rodapé do seletor) lista o que o assistente mudou, com **Pedir para desfazer** e o comando de reversão registrado.
- **−** minimiza/fecha o painel; o serviço continua rodando e a resposta não é perdida.
- Pedidos de mudança no sistema seguem o ritual da skill `msbos`: descrição, confirmação, backup, aplicação, validação e diff.
- O painel não envia anexos de arquivo/imagem nesta versão.
- As conversas ficam em `~/.msbos-ai-chat` (workspace com permissão `0700`); o painel avisa isso no rodapé do seletor.

> **Importante:** `shell` e `edit` param no **cartão de permissão** do painel (Permitir uma vez / Permitir sempre / Recusar). O ajuste `permission_mode` alterna entre **Perguntar** (padrão) e **Permitir sempre** (autoaprova). `webfetch` é negado no agente. Veja [Segurança](docs/seguranca.md).

## Estrutura do projeto

```text
msbos-ai-chat/
├── README.md
├── MAPEAMENTO.md          # levantamento inicial (histórico)
├── install.sh
├── uninstall.sh
├── opencode/agents/       # agente msbos-chat
├── plugin/                # plugin do Noctalia (Luau)
│   ├── plugin.toml
│   ├── bar.luau
│   ├── panel.luau
│   ├── engine.luau
│   ├── lib/
│   └── translations/
└── docs/                  # documentação técnica atual
```

## Documentação

- [AGENTS.md](AGENTS.md) — comandos, arquitetura e convenções para agentes.
- [Índice da documentação](docs/index.md)
- [Arquitetura](docs/arquitetura.md)
- [Conexão com o OpenCode](docs/conexao.md)
- [API do OpenCode usada](docs/api-opencode.md)
- [Eventos SSE](docs/eventos.md)
- [Segurança](docs/seguranca.md)

## Desinstalação

```bash
./uninstall.sh
```

O comando desabilita e remove o plugin, move o agente para um backup e **preserva** o workspace `~/.msbos-ai-chat`. Para apagar também sessões e pareamento:

```bash
./uninstall.sh --purge
```

## Licença

Distribuído sob a licença **MIT**. Veja [LICENSE](LICENSE).
