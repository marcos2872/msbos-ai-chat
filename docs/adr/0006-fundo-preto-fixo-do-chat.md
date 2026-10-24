# 0006 — Fundo preto fixo no painel do chat

## Status

aceito

## Contexto

O painel do Noctalia desenha o próprio fundo usando a cor de **superfície** do tema (`ColorRole::Surface`). No tema em uso (`macOS-roxo`, modo escuro) essa cor é um azul-escuro (`#0A1220`). O plugin não tem API para trocar a cor do painel: o manifesto `[[panel]]` só expõe `placement`, `position`, `open_near_click` e `layer`. Além disso, o conteúdo do plugin é posicionado inset por `Style::panelPadding` (14 px) dentro do painel.

O usuário pediu que o painel do chat tenha **sempre** um fundo preto fixo, que não muda com o tema, mantendo a transparência e o blur do sistema.

Isso revisa o ponto 1 do [ADR 0003](0003-painel-transparente-e-tamanho-por-manifesto.md) (frame transparente).

## Decisão

O `frame()` do `panel.luau` pinta o **painel inteiro** com um fundo **preto fixo translúcido**:

- `fill = "#000000"` com o alfa vindo do ajuste `background_opacity` (0–100, padrão `45`) — cor em hex, fora dos roles do tema, porque a intenção é justamente não seguir o tema;
- `radius = 12`, acompanhando o raio do painel (`Style::radiusXl` × `corner_radius_scale`, 1.0 por padrão);
- um container externo com padding negativo de 14 px (`Style::panelPadding`) faz o preto alcançar a borda do painel e cobri-la; um container interno com padding de 14 px devolve o conteúdo à posição original.

O alfa mantém a transparência e o blur do sistema: o vidro do shell aparece através do preto em vez de ser tapado. A decisão de tamanho por manifesto do ADR 0003 permanece válida.

## Consequências

- (+) O painel do chat fica sempre preto, independente da paleta do Noctalia.
- (+) Transparência e blur do sistema continuam visíveis através do fundo.
- (+) A borda e o raio do tema ficam cobertos pelo preto (sem "painel duplicado").
- (+) O usuário ajusta a intensidade em **Settings → Plugins → `background_opacity`** (0–100), sem editar código.
- (+) Mudança isolada ao plugin; nenhum setting global do shell é alterado.
- (-) Exceção explícita à convenção de usar apenas roles do tema (hex fixo `#000000`); registrada aqui e em `docs/interface.md`.
- (-) O padding negativo depende do inset do host (`Style::panelPadding` = 14 px) e da escala de acessibilidade (1.0); se o Noctalia mudar o inset ou a escala, o preto pode voltar a deixar uma faixa da borda/raio do tema à mostra.
- (-) O preto é aplicado por cima do fundo do host (superfície do tema @ 55%), então a opacidade total é maior que a do vidro sozinho.
- (-) Cobre a borda do tema, mas não a sombra (que fica fora do painel).
