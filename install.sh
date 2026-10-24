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

# ── Verificações de pré-requisitos ─────────────────────────────────────────
# O plugin não instala o OpenCode, a skill `msbos` nem o terminal do polkit.
# Em vez de falhar no meio do uso, o instalador diz em português o que falta e
# como resolver. Nada aqui aborta a instalação: as pendências são listadas no
# fim. Desative com MSBOS_AI_CHAT_CHECKS=0.
PENDING=()
ok()   { printf '  ✓ %s\n' "$1"; }
miss() { printf '  ✗ %s\n      %s\n' "$1" "$2"; PENDING+=("$1"); }

if [[ "${MSBOS_AI_CHAT_CHECKS:-1}" != "0" ]]; then
  echo
  echo "==> verificando pré-requisitos"

  if command -v opencode >/dev/null 2>&1; then
    ok "OpenCode no PATH ($(opencode --version 2>/dev/null | head -1))"
    # A conta de IA é o que faz o painel ter modelos. Sem ela o chat abre, mas
    # não responde — por isso a checagem e a instrução de login.
    auth_list="$(opencode auth list 2>/dev/null || true)"
    if grep -qi "stored" <<<"$auth_list"; then
      ok "conta de IA configurada"
    else
      miss "nenhuma conta de IA configurada" "Conecte uma conta: opencode auth login"
    fi
  else
    miss "OpenCode não encontrado no PATH" "Instale o OpenCode 2.x e confirme com: opencode --version"
  fi

  if command -v noctalia >/dev/null 2>&1; then
    ok "Noctalia no PATH ($(noctalia --version 2>/dev/null | head -1))"
  else
    miss "Noctalia não encontrado no PATH" "Instale o Noctalia 5.3+ (sem ele não há barra nem painel)"
  fi

  if [[ -f "$HOME/.agents/skills/msbos/SKILL.md" ]]; then
    ok "skill msbos instalada"
  else
    miss "skill msbos ausente" "Instale em ~/.agents/skills/msbos/ (o agente usa as regras de segurança dela)"
  fi

  if [[ -x /usr/local/libexec/msbos-priv ]]; then
    ok "helper privilegiado instalado"
  elif [[ -f "$ROOT/plugin/scripts/msbos-priv" ]]; then
    echo "  • helper privilegiado ausente — será instalado agora (pede a senha)"
  else
    miss "helper privilegiado ausente" "Instale em /usr/local/libexec/msbos-priv (ações de root do agente)"
  fi

  if command -v alacritty >/dev/null 2>&1; then
    ok "terminal alacritty presente"
  else
    miss "alacritty não encontrado" "Instale o alacritty (a janela de senha do polkit abre nele)"
  fi

  if command -v pkexec >/dev/null 2>&1; then
    ok "pkexec presente"
  else
    miss "pkexec não encontrado" "Instale o polkit (é o portão das ações de root)"
  fi
fi

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
# Não leva backups de desenvolvimento para o plugin instalado.
rm -f "$PLUGIN_DIR"/plugin.toml.bak-* "$PLUGIN_DIR"/*.bak-* "$PLUGIN_DIR"/*.bak 2>/dev/null || true
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

# ── Helper privilegiado (root) ─────────────────────────────────────────────
# O agente só faz ações de root por este helper (allowlist fechada). Ele é
# instalado apenas quando ausente: uma cópia local modificada é preservada.
HELPER_SRC="$PLUGIN_DIR/scripts/msbos-priv"
HELPER_DST="/usr/local/libexec/msbos-priv"
if [[ -f "$HELPER_SRC" && ! -x "$HELPER_DST" ]] && command -v pkexec >/dev/null 2>&1; then
  echo "==> instalando o helper privilegiado (pode pedir a senha)"
  if pkexec install -m 0755 -- "$HELPER_SRC" "$HELPER_DST" 2>/dev/null; then
    echo "helper instalado: $HELPER_DST"
  else
    echo "helper NÃO instalado (sem root). Para instalar depois:"
    echo "  pkexec install -m 0755 -- '$HELPER_SRC' '$HELPER_DST'"
  fi
elif [[ -x "$HELPER_DST" && -f "$HELPER_SRC" ]] && ! cmp -s "$HELPER_SRC" "$HELPER_DST"; then
  echo "aviso: $HELPER_DST difere da cópia do pacote; mantendo a instalada."
fi

# ── Hardening (root): regra de polkit ──────────────────────────────────────
# Impede `pkexec` de abrir um shell como root — defesa em profundidade contra o
# agente usar `pkexec /bin/sh -c ...` e contornar a allowlist do helper. É
# cirúrgica: só nega shells, apps de desktop que usam pkexec seguem normais.
# Desative com MSBOS_AI_CHAT_HARDEN=0.
HARDEN="${MSBOS_AI_CHAT_HARDEN:-1}"
RULE_SRC="$PLUGIN_DIR/scripts/msbos-priv.rules"
RULE_DST="/etc/polkit-1/rules.d/49-msbos-priv.rules"
# Selo com o hash da regra aplicada: /etc/polkit-1/rules.d não é legível pelo
# usuário, então a idempotência é feita por hash, não por `cmp` no destino.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/msbos"
STAMP="$STATE_DIR/polkit-rule.sha"
if [[ "$HARDEN" != "0" && -f "$RULE_SRC" ]] && command -v pkexec >/dev/null 2>&1; then
  want_hash="$(sha256sum "$RULE_SRC" | awk '{print $1}')"
  have_hash="$(cat "$STAMP" 2>/dev/null || true)"
  if [[ "$want_hash" != "$have_hash" ]]; then
    echo "==> aplicando regra de polkit (pode pedir a senha)"
    if pkexec install -m 0644 -- "$RULE_SRC" "$RULE_DST" 2>/dev/null; then
      mkdir -p "$STATE_DIR" && printf '%s\n' "$want_hash" > "$STAMP"
      echo "regra de polkit aplicada: $RULE_DST"
    else
      echo "regra de polkit NÃO aplicada (sem root). Para aplicar depois:"
      echo "  pkexec install -m 0644 -- '$RULE_SRC' '$RULE_DST'"
    fi
  fi
fi

cat <<EOF

Instalado.

1. Adicione o widget na barra (uma vez só):
   Settings → Bar → Widgets → procure "msbos/ai-chat:bar"
   Atalho: noctalia msg settings-open-plugin $PLUGIN_ID
2. Abra o painel:
   noctalia msg panel-toggle $PLUGIN_ID:panel
3. O chat inicia o servidor do OpenCode sozinho (opencode service start) e
   conecta sem pedir nada. Se não conectar, use "Tentar novamente" no painel.

Suas conversas ficam salvas em $WORKSPACE (somente o seu usuário lê).
EOF

if [[ ${#PENDING[@]} -gt 0 ]]; then
  echo
  echo "Pendências (o chat funciona, mas estes recursos não):"
  printf '  - %s\n' "${PENDING[@]}"
  echo "Resolva e rode ./install.sh de novo para conferir."
fi
