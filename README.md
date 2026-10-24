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
- Skill `msbos` instalada em `~/.agents/skills/msbos/` para o agente especialista.
- `bash` e utilitários básicos (`cp`, `chmod`, `nohup`).

O plugin **não** instala o OpenCode, o Noctalia nem a skill `msbos`; ele usa o que já está no sistema. O servidor local do OpenCode é iniciado pelo próprio plugin (`opencode service start`) quando necessário — não é preciso abrir o app desktop nem um terminal.

## Instalação

No diretório do projeto:

```bash
cd /caminho/para/msbos-ai-chat
./install.sh
```

O instalador:

1. copia o plugin para `~/.local/share/noctalia/plugins/msbos-ai-chat/`;
2. copia o agente para `~/.config/opencode/agents/msbos-chat.md` (com backup do anterior);
3. cria `~/.msbos-ai-chat/{state,sessions}` com permissões restritas;
4. roda o lint do plugin e tenta habilitá-lo no Noctalia.

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

3. No painel, clique em **Conectar automaticamente** ou cole o link exibido por `opencode pair`.
4. Em **Settings → Plugins → msbos AI Chat**, ajuste o tamanho da janela, o diretório, o agente e as demais opções.

## Uso rápido

- Clique no ícone da barra para abrir ou fechar o painel.
- **+** cria uma nova conversa herdando o modelo e a variante atuais.
- **Histórico** abre o seletor de modelo, raciocínio e sessões.
- **−** minimiza/fecha o painel; o serviço continua rodando e a resposta não é perdida.
- Pedidos de mudança no sistema seguem o ritual da skill `msbos`: descrição, confirmação, backup, aplicação, validação e diff.
- O painel não envia anexos de arquivo/imagem nesta versão.

> **Importante:** nesta versão, `shell` e `edit` estão como `allow` no agente e não há cartão técnico de permissão; a confirmação é conversacional. Veja [Segurança](docs/seguranca.md).

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
