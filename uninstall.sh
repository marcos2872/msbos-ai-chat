#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="msbos/ai-chat"
PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/msbos-ai-chat"
AGENT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"
AGENT_FILE="$AGENT_DIR/msbos-chat.md"
WORKSPACE="${MSBOS_AI_CHAT_DIR:-$HOME/.msbos-ai-chat}"
OLD_PLUGIN_ID="omyfedora/ai-chat"
OLD_PLUGIN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/omyfedora-ai-chat"
OLD_AGENT="$AGENT_DIR/omyfedora-chat.md"
OLD_WORKSPACE="$HOME/.omyfedora-ai-chat"
STAMP="$(date +%Y%m%d-%H%M%S)"

if command -v noctalia >/dev/null 2>&1; then
  echo "==> desabilitando $PLUGIN_ID"
  noctalia msg plugins disable "$PLUGIN_ID" || true
  noctalia msg plugins disable "$OLD_PLUGIN_ID" >/dev/null 2>&1 || true
fi

if [[ -d "$PLUGIN_DIR" ]]; then
  echo "==> removendo $PLUGIN_DIR"
  rm -rf "$PLUGIN_DIR"
fi
if [[ -d "$OLD_PLUGIN_DIR" ]]; then
  echo "==> removendo plugin legado $OLD_PLUGIN_DIR"
  rm -rf "$OLD_PLUGIN_DIR"
fi

if [[ -f "$AGENT_FILE" ]]; then
  echo "==> movendo o agente para backup"
  mv "$AGENT_FILE" "$AGENT_FILE.bak-$STAMP"
fi
if [[ -f "$OLD_AGENT" ]]; then
  echo "==> movendo o agente legado para backup"
  mv "$OLD_AGENT" "$OLD_AGENT.bak-$STAMP"
fi

if [[ "${1:-}" == "--purge" ]]; then
  echo "==> apagando workspace $WORKSPACE"
  rm -rf "$WORKSPACE" "$OLD_WORKSPACE"
else
  echo "Workspace preservado em $WORKSPACE"
  [[ -d "$OLD_WORKSPACE" ]] && echo "Workspace legado preservado em $OLD_WORKSPACE"
  echo "Use --purge para apagar também as sessões e o pareamento."
fi
