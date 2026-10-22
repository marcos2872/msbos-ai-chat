# 0001 — Plugin do Noctalia em vez de app separado

## Status

aceito

## Contexto

O chat precisa ficar sempre acessível a partir da barra e acima das janelas, inclusive em fullscreen. O niri não oferece “always on top” para janelas comuns. O Noctalia já fornece widget de barra, painel layer-shell, serviço headless, estado compartilhado e IPC.

## Decisão

Implementar como plugin do Noctalia com três entradas — `bar.luau`, `panel.luau` e `engine.luau` — em vez de um aplicativo GTK/Qt separado.

## Consequências

- (+) Integração nativa com barra, tema, foco e camada `overlay`.
- (+) Sem gerenciamento de janela do niri nem dependência de um toolkit gráfico extra.
- (+) O serviço continua rodando com o painel fechado.
- (-) O plugin fica acoplado à API de plugins do Noctalia (neste ambiente, API 34).
- (-) O host é dono do tamanho, da transparência e do ciclo de vida do painel.
- (-) Recursos como `ui.select` e redimensionamento dependem das limitações do host.
