# 0003 — Painel transparente e tamanho por manifesto

## Status

aceito

## Contexto

O painel do Noctalia já desenha fundo/borda/sombra. Adicionar outro `fill` e outra borda no frame do plugin criava o efeito de painel duplicado. O host também não expõe API de redimensionamento em runtime; o tamanho vem do manifesto.

## Decisão

1. O `frame()` do painel é transparente; o host desenha o fundo e a borda.
2. O tamanho é ajustado por três presets (`compact`, `medium`, `large`) que reescrevem `width`/`height` da primeira seção `[[panel]]` do `plugin.toml` **instalado**, com backup `plugin.toml.bak-size`, e recarregam o plugin.

## Consequências

- (+) Visual consistente com o tema, sem fundo/borda duplicados.
- (+) O usuário escolhe o tamanho em Settings → Plugins.
- (-) Mudar o tamanho exige recarregar o plugin e reabrir o painel.
- (-) O manifesto instalado difere do manifesto do repositório (que permanece em 460 × 640).
- (-) É necessário ter permissão de escrita no diretório do plugin.
- (-) O host pode ignorar/limitar dimensões; não há fallback de resize em runtime.
