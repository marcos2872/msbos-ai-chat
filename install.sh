#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="msbos/ai-chat"
PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/msbos-ai-chat"
AGENT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"
AGENT_FILE="$AGENT_DIR/msbos-chat.md"
WORKSPACE="${MSBOS_AI_CHAT_DIR:-$HOME/.msbos-ai-chat}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Nomes da geração anterior (antes do rebranding omyfedora -> msbos).
OLD_PLUGIN_ID="omyfedora/ai-chat"
OLD_PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/omyfedora-ai-chat"
OLD_AGENT="$AGENT_DIR/omyfedora-chat.md"
OLD_WORKSPACE="$HOME/.omyfedora-ai-chat"
NOCT_SETTINGS="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/settings.toml"

echo "==> msbos AI Chat"
echo "plugin:    $PLUGIN_DIR"
echo "agente:    $AGENT_FILE"
echo "workspace: $WORKSPACE"

mkdir -p "$AGENT_DIR"

# Workspace: move as sessões/pareamento antigos sem perder o histórico.
if [[ -d "$OLD_WORKSPACE" ]]; then
  if [[ ! -e "$WORKSPACE" ]]; then
    mv "$OLD_WORKSPACE" "$WORKSPACE"
    echo "workspace migrado: $OLD_WORKSPACE -> $WORKSPACE"
  else
    cp -an "$OLD_WORKSPACE/." "$WORKSPACE/" || true
    mv "$OLD_WORKSPACE" "$WORKSPACE.old-$STAMP"
    echo "workspace antigo mesclado e arquivado em $WORKSPACE.old-$STAMP"
  fi
fi

# Agente antigo: guarda como backup com nome novo (sem deixar o nome antigo ativo).
if [[ -f "$OLD_AGENT" ]]; then
  mv "$OLD_AGENT" "$AGENT_FILE.old-$STAMP"
  echo "agente antigo arquivado: $AGENT_FILE.old-$STAMP"
fi

mkdir -p "$PLUGIN_DIR" "$WORKSPACE/state" "$WORKSPACE/sessions"
chmod 700 "$WORKSPACE" "$WORKSPACE/state" "$WORKSPACE/sessions"

if [[ -f "$AGENT_FILE" ]]; then
  cp -a "$AGENT_FILE" "$AGENT_FILE.bak-$STAMP"
  echo "backup do agente: $AGENT_FILE.bak-$STAMP"
fi

if command -v noctalia >/dev/null 2>&1; then
  echo "==> desabilitando plugin antigo (se existir)"
  noctalia msg plugins disable "$OLD_PLUGIN_ID" >/dev/null 2>&1 || true
fi

cp -r "$ROOT/plugin/." "$PLUGIN_DIR/"
cp "$ROOT/opencode/agents/msbos-chat.md" "$AGENT_FILE"

# O plugin antigo não tem dados do usuário (as settings ficam no Noctalia);
# arquiva o diretório fora de plugins/ para o Noctalia não descobri-lo.
if [[ -d "$OLD_PLUGIN_DIR" && "$OLD_PLUGIN_DIR" != "$PLUGIN_DIR" ]]; then
  PLUGIN_BACKUP="${XDG_STATE_HOME:-$HOME/.local/state}/msbos/plugin-backups"
  mkdir -p "$PLUGIN_BACKUP"
  mv "$OLD_PLUGIN_DIR" "$PLUGIN_BACKUP/msbos-ai-chat-old-$STAMP"
  echo "plugin antigo arquivado: $PLUGIN_BACKUP/msbos-ai-chat-old-$STAMP"
fi

# Atualiza o ID do plugin na barra/estado do Noctalia.
if [[ -f "$NOCT_SETTINGS" ]] && grep -qF "$OLD_PLUGIN_ID" "$NOCT_SETTINGS"; then
  cp -a "$NOCT_SETTINGS" "$NOCT_SETTINGS.bak-msbos-$STAMP"
  sed -i "s|${OLD_PLUGIN_ID}|${PLUGIN_ID}|g" "$NOCT_SETTINGS"
  echo "settings do Noctalia migradas ($OLD_PLUGIN_ID -> $PLUGIN_ID)"
fi

if command -v noctalia >/dev/null 2>&1; then
  echo "==> lint do plugin"
  noctalia plugins lint "$PLUGIN_DIR" || true

  # O shell descobre o plugin de forma assíncrona; aguarde até ~15s.
  # Guarde a listagem antes do grep: com `pipefail`, `grep -q` fecha o pipe
  # cedo e o SIGPIPE do noctalia faria a descoberta falhar.
  discovered=0
  for _ in $(seq 1 15); do
    listing="$(noctalia msg plugins list 2>/dev/null || true)"
    if grep -q "$PLUGIN_ID" <<<"$listing"; then
      discovered=1
      break
    fi
    sleep 1
  done

  if [[ "$discovered" == 1 ]]; then
    echo "==> habilitando $PLUGIN_ID"
    noctalia msg plugins enable "$PLUGIN_ID" || true
  else
    echo "O Noctalia ainda não descobriu o plugin."
    echo "Abra Settings → Plugins e habilite $PLUGIN_ID."
  fi
  # Recarrega a config/estado para a barra pegar o novo ID, quando suportado.
  sleep 1
  noctalia msg config-reload >/dev/null 2>&1 || true
else
  echo "Noctalia não encontrado no PATH; habilite o plugin pela GUI."
fi

cat <<EOF

Instalado.

1. Adicione o widget na barra:
   Settings → Bar → Widgets → "msbos/ai-chat:bar"
2. Abra o painel:
   noctalia msg panel-toggle $PLUGIN_ID:panel
3. No boot, o próprio chat inicia o servidor do OpenCode (opencode service
   start) e pareia sozinho. Se precisar, use "Tentar novamente" no painel ou
   rode opencode pair e cole o link.

Sessões e espelhos: $WORKSPACE
EOF
