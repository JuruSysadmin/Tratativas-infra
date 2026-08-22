---
title: Implementar Treatment Header e UI de ownership
type: feature
estimate: "3"
tags: [frontend, chat, treatments, carbon, ownership]
created: "2026-08-22T01:30:00Z"
modified: "2026-08-22T01:56:27Z"
author: JuruSysadmin
status: started
started: "2026-08-22T01:31:46Z"
---

## Problem statement

A interface da Tratativa precisa apresentar um cabeçalho claro com o estado
atual e as ações de ownership no contexto correto da conversa. A UI deve usar
o `TreatmentState` persistido e as capacidades de ownership já calculadas, sem
duplicar autorização ou alterar estado de forma otimista.

## Scope

- Criar um `TreatmentHeader` responsável por status, responsável atual e ações.
- Integrar a UI de ownership ao cabeçalho sem remontar a conversa.
- Reutilizar `TreatmentOwnershipActions` e `TreatmentState` existentes.
- Preservar identidade, matriz de capacidades, pending/error e eventos realtime.
- Usar componentes e tokens Carbon já adotados pelo frontend.
- Manter a transferência condicionada à fonte válida de agentes elegíveis.

## Out of scope

- Novos comandos Phoenix ou eventos realtime.
- Alterações no backend, autorização ou domínio de Treatments.
- Optimistic update.
- Definição de uma fonte nova de agentes elegíveis.
- Redesign completo do `CarbonAiChatPanel`.

## Acceptance

- [ ] O cabeçalho exibe o status atual da Tratativa com texto de apresentação.
- [ ] O cabeçalho exibe o agente responsável quando houver um responsável.
- [ ] O cabeçalho trata uma Tratativa sem responsável sem quebrar a renderização.
- [ ] As ações exibidas respeitam a matriz de capacidades já implementada.
- [ ] Pending e erros continuam visíveis no contexto do cabeçalho.
- [ ] Eventos realtime atualizam o cabeçalho sem optimistic update.
- [ ] A conversa não é desmontada/remontada ao executar uma ação.
- [ ] Testes focados, TypeScript, lint, build e `git diff --check` passam.

## Tasks

- [x] Mapear o contrato visual atual do `CarbonAiChatPanel` e `TreatmentState`.
- [x] Escrever testes RED do `TreatmentHeader` para status e responsável.
- [x] Implementar o componente usando Carbon e composição.
- [x] Integrar `TreatmentOwnershipActions` ao header sem duplicar comandos.
- [x] Cobrir estados sem responsável, pending, erro e atualização realtime.
- [x] Executar testes focados, TypeScript, lint, build e diff check.
- [ ] Marcar como delivered e aguardar revisão humana.

## Comments
@JuruSysadmin 2026-08-22
Implementação concluída na branch feat/treatment-header-ownership-ui. O CarbonAiChatPanel agora usa TreatmentHeader com pedido, protocolo, status Carbon IconIndicator, responsável e TreatmentOwnershipActions. A matriz de capabilities existente permanece responsável pela visibilidade das ações; transferAgents é opcional e não é inventado. Eventos realtime continuam atualizando TreatmentState, que alimenta o header. Testes focados: 34 passando em 5 arquivos; npx tsc -b, npm run lint -- --quiet, npm run build e git diff --check passaram. Build mantém apenas avisos preexistentes de @position-try, chunks grandes e eval em dependências. Story permanece started aguardando revisão humana.

## Attachments
