# 0002 — Serviço como fonte de verdade

## Status

aceito

## Contexto

O painel do Noctalia pode ser fechado/minimizado, mas a execução do OpenCode e o streaming precisam continuar. A barra também precisa refletir `busy`, `unread` e erro sem depender do painel estar aberto.

## Decisão

O `engine.luau` é o dono do pareamento, da conexão SSE, do estado da conversa e da persistência. O painel é uma view: lê `chat.snapshot`/`chat.models`/`chat.sessions` e envia comandos por IPC. A barra lê `chat.status`.

## Consequências

- (+) Uma única fonte de verdade e uma única conexão de dados.
- (+) A conversa continua com o painel fechado; a barra reflete o estado.
- (+) Reiniciar o painel não perde a execução em andamento.
- (-) A comunicação é assíncrona e Baseada em cópias de estado.
- (-) O payload do IPC é um argumento de linha de comando; prompts muito grandes exigiriam um mecanismo de arquivo (não implementado).
- (-) Depuração exige olhar o serviço e o painel separadamente.
