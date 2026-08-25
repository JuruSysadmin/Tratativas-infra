---
title: Adicionar comando /pedido com resumo e pedidos relacionados no Chat
type: feature
created: "2026-08-25T20:56:26Z"
modified: "2026-08-25T20:57:14Z"
author: JuruSysadmin
status: started
estimate: "5"
started: "2026-08-25T20:57:14Z"
---

## Problem statement
Como atendente do Chat de Tratativas, quero consultar o resumo do pedido e seus pedidos relacionados usando `/pedido`, para entender rapidamente o contexto TV7, TV8 e TV1 sem sair da conversa.

## Possible solution
Adicionar `/pedido` ao catálogo de slash commands e consultar `GET /orders?orderId={orderId}&page=1&limit=32` sob demanda. Renderizar no chat o tipo, status, cliente, valor, filial, data e os pedidos relacionados, sem persistir o comando como mensagem.

## Acceptance
- [ ] `/pedido` é o único novo comando funcional exibido no autocomplete.
- [ ] A seleção consulta somente o pedido ativo e seus relacionados.
- [ ] O resumo exibe número, tipo, status, cliente, valor, filial e data quando disponíveis.
- [ ] Pedidos TV7, TV8 e TV1 relacionados são identificados separadamente.
- [ ] O resultado possui estados de carregamento, vazio, erro e retry.
- [ ] O comando não altera tratativa, sala ou histórico de mensagens.
- [ ] Testes focados, typecheck, lint e build passam.

## Tasks
- [ ] Mapear o schema e o cliente existentes da busca de pedidos.
- [ ] Escrever testes RED para o comando e o resumo do pedido.
- [ ] Implementar consulta sob demanda para `/pedido`.
- [ ] Renderizar resumo e pedidos relacionados no chat.
- [ ] Cobrir estados de carregamento, vazio, erro e retry.
- [ ] Executar testes focados, typecheck, lint, build e `git diff --check`.
- [ ] Marcar como delivered e aguardar revisão humana.

## Comments

## Attachments
