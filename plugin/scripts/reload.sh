#!/usr/bin/env bash
# Recarrega o plugin para aplicar o novo tamanho do painel (chamado pelo
# engine no lugar de uma string de shell). Desabilita, espera e reabilita.
set -euo pipefail

sleep 0.2
noctalia msg plugins disable msbos/ai-chat >/dev/null 2>&1 || true
sleep 0.5
noctalia msg plugins enable msbos/ai-chat >/dev/null 2>&1 || true
