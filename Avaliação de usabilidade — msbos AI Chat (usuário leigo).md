# Avaliação de usabilidade — msbos AI Chat (usuário leigo)

Plugin do Noctalia (v0.2.0) avaliado do ponto de vista de uma pessoa leiga em Linux e Noctalia. A avaliação vem da leitura do código e da documentação; o plugin não foi executado.

## Veredito

Depois de instalado e funcionando, o plugin é razoavelmente amigável. Para uma pessoa leiga, porém, instalar, configurar e entender o que está sendo pedido são barreiras altas. Hoje ele é bom para quem já usa terminal e Noctalia, e ainda não para quem não conhece nenhum dos dois.

## O que funciona bem

- **Conexão automática.** O plugin inicia o OpenCode e pareia sozinho. Os campos técnicos ficam escondidos em "Avançado".
- **Estado vazio com atalhos clicáveis.** A tela inicial traz três exemplos e a frase "Toda mudança é confirmada antes de ser aplicada", que passa segurança.
- **Cartão de permissão.** "Permitir uma vez" é o botão de destaque, "Permitir sempre" é discreto e "Recusar" está em vermelho. Há também "Ver o alvo completo".
- **Agente em português.** Ele descreve a mudança, diz como desfazer e pede confirmação antes de agir.
- **Desinstalação segura.** Ela faz backup e preserva os dados do usuário por padrão.
- **Pequenos cuidados.** Há botão de regenerar, busca de sessões, tooltips e três tamanhos de janela.

## Problemas para um usuário leigo

### 1. Instalação e pré-requisitos (o mais grave)

- É preciso usar terminal (`./install.sh`) e ter OpenCode e a skill `msbos` já instalados.
- O agente depende do helper `/usr/local/libexec/msbos-priv` para instalar pacotes e mexer em serviços. Ele não está no pacote nem na lista de pré-requisitos do README. Sem ele, o exemplo "Instale o htop" provavelmente acaba em beco sem saída.
- O README não diz que o OpenCode precisa de um provedor de IA configurado (login ou chave de API). Sem isso o painel mostra "Nenhum modelo carregado" e nada explica o motivo.
- O widget não é adicionado à barra. É preciso ir a Settings → Bar → Widgets e procurar `msbos/ai-chat:bar`.
- O README oferece como forma de abrir o painel o comando `noctalia msg panel-toggle ...`.

### 2. Jargão na interface

- Aparecem termos como "OpenCode", "pareamento", "agente", "modelo", "raciocínio" (com valores crus como `low/high/max`), `opencode serve`, `opencode pair` e "rode ./install.sh".
- A tela offline sugere "abra o app OpenCode ou rode `opencode serve`", o que não ajuda quem não conhece isso.
- Os exemplos do estado vazio incluem "Ajuste o gap do niri para 8", que não significa nada para um leigo.

### 3. Decisões de segurança que o leigo não consegue avaliar

- O cartão de permissão mostra o nome técnico da ação (`shell`, `edit`) e o comando em código. Quem não lê shell aprova às cegas.
- "Permitir sempre" tem escopo indefinido ("definido pelo OpenCode"). Para esse público, é um botão arriscado.
- O ajuste "Permitir sempre" desliga a única barreira técnica e não traz aviso de risco.
- Ações que exigem root abrem um terminal (Alacritty) e uma janela de senha do polkit, que pode aparecer em outro workspace ou monitor. Isso desorienta e depende de o Alacritty estar instalado.

### 4. Confiança e privacidade

- O `install.sh` instala por padrão uma regra de polkit em `/etc/polkit-1/rules.d`, pedindo a senha de administrador com pouca explicação. A opção de desativar (`MSBOS_AI_CHAT_HARDEN=0`) é invisível para um leigo.
- As conversas ficam em texto puro em `~/.msbos-ai-chat`, incluindo comandos e trechos de configuração. O README não alerta sobre isso.

### 5. Recuperação de erros

- "Desfazer" é só texto no chat ("como reverter"). Não há botão que desfaça a última mudança, nem tela com o histórico de mudanças feitas.
- Várias mensagens de erro mandam consultar logs ou rodar comandos de terminal.

### 6. Detalhes de interface

- O campo de entrada tem uma linha só e não aceita anexos. Não dá para mandar uma captura de tela do problema, algo que leigos costumam querer.
- Muitos textos usam fonte de 9 a 10 px sobre fundo preto semitransparente (45% por padrão). Dependendo do papel de parede, o contraste cai.
- O botão com tooltip "Modelos e sessões" aparece na documentação como "Histórico", e o seletor mistura modelo, raciocínio e sessões numa única tela.
- Trocar o tamanho do painel recarrega o plugin, e a janela some por um instante sem aviso.
- Os textos do painel estão fixos em português. O `en.json` cobre só as configurações.

## Nota por etapa

| Etapa | Nota (leigo) | Motivo |
| --- | --- | --- |
| Instalar e configurar | 2/10 | Terminal, dependências externas e passos manuais |
| Primeira conexão | 6/10 | Automática, mas as falhas caem em jargão |
| Conversar e fazer perguntas | 7/10 | Simples e em português |
| Aprovar mudanças | 4/10 | Cartão técnico, "sempre" arriscado, janela de senha confusa |
| Desfazer e diagnosticar erros | 3/10 | Tudo depende de comandos de terminal |

## Recomendações, por prioridade

1. **Instalação guiada.** Faça o `install.sh` verificar tudo (OpenCode, skill, helper, provedor de IA, Alacritty) e dizer em português o que falta e como resolver. Se possível, adicione o widget à barra automaticamente ou mostre o caminho exato. Inclua o helper `msbos-priv` no pacote ou nos pré-requisitos.
2. **Tela de "primeiros passos" no painel.** Quando não houver modelo, mostre "Falta conectar uma conta de IA" com instruções, em vez de "Nenhum modelo carregado".
3. **Linguagem simples.** Troque "pareamento" por "conectando", "agente" e "modelo" por termos descritivos, e `low/high/max` por "Rápido / Equilibrado / Detalhado". Mova os comandos de terminal para "Detalhes técnicos".
4. **Cartão de permissão em duas camadas.** Mostre primeiro uma explicação em linguagem comum ("Instalar o programa htop") e deixe o comando real como detalhe expansível. Remova "Permitir sempre" para esse público, ou explique exatamente o que ele libera. Adicione um aviso de risco ao modo "Permitir sempre".
5. **Botão "Desfazer última mudança"** e uma tela com o histórico de alterações, em vez de depender do texto do agente.
6. **Exemplos acessíveis**, como "Deixe as janelas mais afastadas", "Instale um programa" e "Mude as cores do desktop".
7. **Pequenos ajustes:** entrada multilinha, fontes maiores, opacidade mínima para garantir contraste e aviso sobre o armazenamento das conversas.
