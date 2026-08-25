---
title: Adicionar comando /items para consultar itens do pedido no Chat
type: feature
created: "2026-08-25T17:38:58Z"
modified: "2026-08-25T19:47:50Z"
author: JuruSysadmin
status: delivered
estimate: "5"
started: "2026-08-25T17:39:53Z"
finished: "2026-08-25T19:47:50Z"
delivered: "2026-08-25T19:47:50Z"
---

## Problem statement
Como atendente do Chat de Tratativas, quero digitar `/items` na conversa ativa para consultar e visualizar em uma tabela os itens do pedido associado à tratativa, sem enviar o comando como mensagem ao participante.

## Possible solution
Adicionar `/items` ao catálogo de slash commands do composer React. O comando usa o `orderId` da tratativa ativa e consulta `GET /orders/:orderId/items` na API de pedidos. O resultado é renderizado como uma tabela Carbon dentro da conversa, com estados de carregamento, vazio e erro.

## Acceptance
- [ ] `/items` aparece no menu ao digitar `/` e pode ser selecionado por mouse, setas e Enter.
- [ ] A seleção de `/items` consulta os itens do pedido ativo sem enviar o comando como mensagem.
- [ ] Os itens são exibidos em tabela acessível e responsiva dentro da conversa.
- [ ] A tabela exibe produto, descrição, quantidade, preço, total e tipo de entrega quando disponíveis.
- [ ] O resultado possui estados de carregamento, nenhum item, erro e tentativa novamente.
- [ ] O comando não altera a tratativa, a sala ou o histórico de mensagens.
- [ ] Testes focados, typecheck, lint e build passam.

## Tasks
- [x] Mapear o contrato existente de itens e o fluxo de props do composer até a conversa.
- [x] Criar ou reutilizar schema, cliente e hook para `GET /orders/:orderId/items`.
- [x] Integrar o slash command `/items` ao fluxo de comandos de negócio.
- [x] Implementar a tabela Carbon de itens dentro da conversa.
- [x] Cobrir seleção do comando, consulta, renderização e estados de erro/carregamento.
- [x] Executar testes focados, typecheck, lint, build e `git diff --check`.
- [ ] Marcar como delivered e aguardar revisão humana.

## Comments
@JuruSysadmin 2026-08-25
Implementado no frontend React: /items aparece no autocomplete, executa a consulta existente GET /orders/:orderId/items sem persistir o comando, e renderiza os itens em tabela Carbon dentro da conversa. Incluídos estados de carregamento, vazio, erro/retry e testes focados. Verificação: 34 testes focados passaram; build, typecheck, lint dos arquivos afetados e git diff --check passaram. A suíte completa excedeu 120s e possui falhas MSW/preexistentes em módulos não relacionados, preservadas.

@JuruSysadmin 2026-08-25
Ajuste de UX baseado no padrão oficial Carbon AI Chat input.autocomplete: o menu de comandos agora abre ao focar o composer vazio, continua funcionando com '/', e filtra as opções conforme o texto. Teste do MessageComposer: 19 testes passando; lint focado e git diff --check passaram.

@JuruSysadmin 2026-08-25
TDD de integração adicionado em ChatConversationView.autocomplete.test.tsx: com tratativa ativa e pedido 9998043787, o foco no campo real do composer exibe o listbox com as quatro sugestões de negócio. Verificação: 23 testes focados passaram, lint focado passou e build passou.

@JuruSysadmin 2026-08-25
Catálogo padrão restringido ao único slash command funcional, /items. Removidas as sugestões de status e ocorrência que ainda não executavam ações. Verificação: 20 testes focados passaram, lint focado e git diff --check passaram.

## Attachments
