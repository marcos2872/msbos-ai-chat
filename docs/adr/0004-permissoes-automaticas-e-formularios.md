# 0004 — Permissões automáticas e formulários

## Status

aceito

## Contexto

O assistente precisa executar comandos e editar arquivos para aplicar mudanças no desktop. O agente atual foi configurado com `edit: allow` e `shell: allow`; o painel não implementa cartões de permissão. A ferramenta `question` do OpenCode cria formulários para decisões.

## Decisão

- Manter o agente com `edit`, `shell`, `read`, `webfetch`, `skill` e `question` em `allow`; `task` em `deny`.
- No engine, responder `permission.asked` automaticamente:
  - `shell`, `edit`, `question`, `form` → `once`;
  - outras ações → `reject`.
- Renderizar formulários de `question` como cartões no painel e responder via `reply_form`.
- Manter a confirmação de mudanças no texto, seguindo o ritual da skill `msbos`.

## Consequências

- (+) Menos atrito para o assistente de desktop e para o fluxo de mudanças.
- (+) Formulários permitem decisões estruturadas sem sair do painel.
- (-) **Não há barreira técnica de permissão para shell/edit**; a confirmação é conversacional.
- (-) A segurança depende das instruções do agente/skill e do usuário.
- (-) A lista `pending.permissions` existe no snapshot, mas não é renderizada.
- (-) O servidor do OpenCode Desktop roda com `NoNewPrivs=1`; o agente precisa iniciar `pkexec` via `niri msg action spawn` e validar o resultado depois, pois o comando é assíncrono.
- (-) Endurecer o fluxo exige mudar o agente para `ask`, remover a autoaprovação de shell/edit e implementar o cartão.
