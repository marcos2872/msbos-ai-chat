# 0005 — Modelo e variante em novos chats

## Status

aceito

## Contexto

O modelo e a variante são propriedades da sessão no OpenCode. Ao criar uma nova conversa, o plugin precisava evitar voltar ao modelo padrão toda vez que o usuário já tinha escolhido um modelo/raciocínio.

## Decisão

Ao criar uma sessão, resolver o modelo nesta ordem:

1. `opts.model` enviado pelo painel (modelo da sessão atual);
2. `preferredModel` persistido em `state/ui.json`;
3. modelo da sessão ativa;
4. sem modelo (o OpenCode escolhe o padrão).

`copyModelRef` normaliza o ref e remove `variant = "default"`. `setModel` atualiza `preferredModel` após sucesso e persiste no `ui.json`.

## Consequências

- (+) Novas conversas mantêm o modelo e a variante escolhidos.
- (+) A preferência sobrevive a recarregamentos do plugin.
- (+) Conversas existentes não são alteradas.
- (-) Se o usuário selecionar uma sessão antiga com outro modelo e clicar em **+**, o painel envia o modelo dessa sessão (o comportamento segue a sessão atual).
- (-) A variante só existe se o modelo oferecer `variants`; `default` é omitido.
- (-) O modelo pode ser recusado pelo servidor se a variante não estiver mais disponível.
