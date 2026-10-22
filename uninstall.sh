#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="omyfedora/ai-chat"
PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/omyfedora-ai-chat"
AGENT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"
AGENT_FILE="$AGENT_DIR/omyfedora-chat.md"
WORKSPACE="${OMYFEDORA_AI_CHAT_DIR:-$HOME/.omyfedora-ai-chat}"
STAMP="$(date +%Y%m%d-%H%M%S)"

if command -v noctalia >/dev/null 2>&1; then
  echo "==> desabilitando $PLUGIN_ID"
  noctalia msg plugins disable "$PLUGIN_ID" || true
fi

if [[ -d "$PLUGIN_DIR" ]]; then
  echo "==> removendo $PLUGIN_DIR"
  rm -rf "$PLUGIN_DIR"
fi

if [[ -f "$AGENT_FILE" ]]; then
  echo "==> movendo o agente para backup"
  mv "$AGENT_FILE" "$AGENT_FILE.bak-$STAMP"
fi

if [[ "${1:-}" == "--purge" ]]; then
  echo "==> apagando workspace $WORKSPACE"
  rm -rf "$WORKSPACE"
else
  echo "Workspace preservado em $WORKSPACE"
  echo "Use --purge para apagar também as sessões e o pareamento."
fi
