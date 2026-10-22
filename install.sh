#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="omyfedora/ai-chat"
PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/omyfedora-ai-chat"
AGENT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"
AGENT_FILE="$AGENT_DIR/omyfedora-chat.md"
WORKSPACE="${OMYFEDORA_AI_CHAT_DIR:-$HOME/.omyfedora-ai-chat}"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "==> omyfedora AI Chat"
echo "plugin:    $PLUGIN_DIR"
echo "agente:    $AGENT_FILE"
echo "workspace: $WORKSPACE"

mkdir -p "$PLUGIN_DIR" "$AGENT_DIR" "$WORKSPACE/state" "$WORKSPACE/sessions"
chmod 700 "$WORKSPACE" "$WORKSPACE/state" "$WORKSPACE/sessions"

if [[ -f "$AGENT_FILE" ]]; then
  cp -a "$AGENT_FILE" "$AGENT_FILE.bak-$STAMP"
  echo "backup do agente: $AGENT_FILE.bak-$STAMP"
fi

cp -r "$ROOT/plugin/." "$PLUGIN_DIR/"
cp "$ROOT/opencode/agents/omyfedora-chat.md" "$AGENT_FILE"

if command -v noctalia >/dev/null 2>&1; then
  echo "==> lint do plugin"
  noctalia plugins lint "$PLUGIN_DIR" || true

  sleep 1
  if noctalia msg plugins list 2>/dev/null | grep -q "$PLUGIN_ID"; then
    echo "==> habilitando $PLUGIN_ID"
    noctalia msg plugins enable "$PLUGIN_ID" || true
  else
    sleep 1
    if noctalia msg plugins list 2>/dev/null | grep -q "$PLUGIN_ID"; then
      echo "==> habilitando $PLUGIN_ID"
      noctalia msg plugins enable "$PLUGIN_ID" || true
    else
      echo "O Noctalia ainda não descobriu o plugin."
      echo "Abra Settings → Plugins e habilite $PLUGIN_ID."
    fi
  fi
else
  echo "Noctalia não encontrado no PATH; habilite o plugin pela GUI."
fi

cat <<EOF

Instalado.

1. Adicione o widget na barra:
   Settings → Bar → Widgets → "omyfedora/ai-chat:bar"
2. Abra o painel:
   noctalia msg panel-toggle $PLUGIN_ID:panel
3. No painel, clique em "Conectar automaticamente" ou cole o link de:
   opencode pair

Sessões e espelhos: $WORKSPACE
EOF
