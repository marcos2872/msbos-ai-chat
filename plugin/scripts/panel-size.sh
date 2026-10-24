#!/usr/bin/env bash
# Aplica o preset de tamanho no plugin.toml instalado.
# Roda fora do callback Luau: ler+reescrever o manifesto dentro do engine
# estourava o orçamento de CPU dos scripts do Noctalia.
#
# Uso: panel-size.sh <plugin.toml> <largura> <altura>
# Saída: 0 = nada mudou; 10 = manifesto reescrito; outro = erro.
set -euo pipefail

manifest="${1:?manifesto ausente}"
width="${2:?largura ausente}"
height="${3:?altura ausente}"

if [[ ! -f "$manifest" ]]; then
  echo "manifesto não encontrado: $manifest" >&2
  exit 1
fi

# Só inteiros de até 5 dígitos entram no awk — evita corromper o manifesto.
if [[ ! "$width" =~ ^[0-9]{1,5}$ || ! "$height" =~ ^[0-9]{1,5}$ ]]; then
  echo "largura/altura inválidas: '$width' x '$height'" >&2
  exit 1
fi

read_size() {
  awk -v key="$1" '
    /^\[\[panel\]\]/ { inpanel = 1; next }
    inpanel && /^\[\[/ { exit }
    inpanel && $0 ~ "^" key "[ \t]*=" {
      sub(/^[^=]*=[ \t]*/, "")
      print
      exit
    }
  ' "$manifest"
}

current_width="$(read_size width)"
current_height="$(read_size height)"

if [[ "$current_width" == "$width" && "$current_height" == "$height" ]]; then
  exit 0
fi

# Temporário imprevisível no mesmo diretório (evita symlink/TOCTOU).
tmp="$(mktemp "$manifest.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

awk -v w="$width" -v h="$height" '
  /^\[\[panel\]\]/ { inpanel = 1; print; next }
  inpanel && /^\[\[/ { inpanel = 0 }
  inpanel && /^width[ \t]*=/ { print "width = " w; next }
  inpanel && /^height[ \t]*=/ { print "height = " h; next }
  { print }
' "$manifest" > "$tmp"

cp -a "$manifest" "$manifest.bak-size"
mv "$tmp" "$manifest"
exit 10
