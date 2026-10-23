# omyfedora AI Chat

Chat de IA para o desktop **omyfedora** (Fedora + niri + Noctalia), exibido em um painel flutuante do Noctalia e conectado ao **OpenCode local**. O agente `omyfedora-chat` segue a skill `omyfedora` para propor mudanças no sistema, pedir confirmação, aplicar, validar e registrar o resultado.

> Status: implementação local `0.1.0`, testada em Fedora 44, niri, Noctalia 5.3.0 (plugin API 34) e OpenCode 2.1.4.
> O `MAPEAMENTO.md` registra o levantamento inicial. A documentação em [`docs/`](docs/index.md) reflete o código atual.

## Stack

- **Interface/host:** Noctalia 5.3 (Luau, plugin API 34)
- **Motor:** OpenCode 2.x (API v2 local, HTTP + SSE, Basic auth)
- **Desktop:** Fedora + niri
- **Persistência:** JSON e Markdown em `~/.omyfedora-ai-chat`

## Pré-requisitos

- Fedora com niri e Noctalia 5.3 ou superior.
- OpenCode 2.x instalado, com `opencode` no `PATH`.
- Skill `omyfedora` instalada em `~/.agents/skills/omyfedora/` para o agente especialista.
- `bash` e utilitários básicos (`cp`, `chmod`, `nohup`).

O plugin **não** instala o OpenCode, o Noctalia nem a skill `omyfedora`; ele usa o que já está no sistema. O servidor local do OpenCode é iniciado pelo próprio plugin (`opencode service start`) quando necessário — não é preciso abrir o app desktop nem um terminal.

## Instalação

No diretório do projeto:

```bash
cd /caminho/para/omyfedora-ai-chat
./install.sh
```

O instalador:

1. copia o plugin para `~/.local/share/noctalia/plugins/omyfedora-ai-chat/`;
2. copia o agente para `~/.config/opencode/agents/omyfedora-chat.md` (com backup do anterior);
3. cria `~/.omyfedora-ai-chat/{state,sessions}` com permissões restritas;
4. roda o lint do plugin e tenta habilitá-lo no Noctalia.

Depois da instalação:

1. Adicione o widget na barra em **Settings → Bar → Widgets → `omyfedora/ai-chat:bar`**.
2. Abra o painel:

```bash
noctalia msg panel-toggle omyfedora/ai-chat:panel
```

3. No painel, clique em **Conectar automaticamente** ou cole o link exibido por `opencode pair`.
4. Em **Settings → Plugins → omyfedora AI Chat**, ajuste o tamanho da janela, o diretório, o agente e as demais opções.

## Uso rápido

- Clique no ícone da barra para abrir ou fechar o painel.
- **+** cria uma nova conversa herdando o modelo e a variante atuais.
- **Histórico** abre o seletor de modelo, raciocínio e sessões.
- **−** minimiza/fecha o painel; o serviço continua rodando e a resposta não é perdida.
- Pedidos de mudança no sistema seguem o ritual da skill `omyfedora`: descrição, confirmação, backup, aplicação, validação e diff.
- O painel não envia anexos de arquivo/imagem nesta versão.

> **Importante:** nesta versão, `shell` e `edit` estão como `allow` no agente e não há cartão técnico de permissão; a confirmação é conversacional. Veja [Segurança](docs/seguranca.md).

## Estrutura do projeto

```text
omyfedora-ai-chat/
├── README.md
├── MAPEAMENTO.md          # levantamento inicial (histórico)
├── install.sh
├── uninstall.sh
├── opencode/agents/       # agente omyfedora-chat
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

O comando desabilita e remove o plugin, move o agente para um backup e **preserva** o workspace `~/.omyfedora-ai-chat`. Para apagar também sessões e pareamento:

```bash
./uninstall.sh --purge
```

## Licença

Distribuído sob a licença **MIT**. Veja [LICENSE](LICENSE).
