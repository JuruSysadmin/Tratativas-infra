---
title: Integrar lifecycle da Tratativa no frontend
type: feature
created: "2026-08-21T21:34:00Z"
modified: "2026-08-22T16:11:47Z"
author: JuruSysadmin
status: accepted
estimate: "5"
started: "2026-08-21T21:34:46Z"
finished: "2026-08-21T21:50:52Z"
delivered: "2026-08-21T21:50:52Z"
accepted: "2026-08-22T16:11:47Z"
---

## Problem statement

Como frontend da Tratativa, quero conhecer e manter sincronizado o estado atual da Treatment para refletir status, agente responsável, resolução, reabertura, liberação e transferência.

O backend já publica os eventos de lifecycle. Esta story cria somente a camada de estado e sincronização realtime. Não implementa botões, ações operacionais ou layout final.

## Escopo

- Representação única da Treatment no frontend com `id`, `status`, `assigned_agent_id`, `assigned_at`, `resolved_by_id` e `resolved_at`.
- Status reconhecidos: `open`, `in_progress`, `resolved` e `closed`.
- Estado inicial reconstruído a partir do payload persistido já disponível no fluxo atual; não criar segunda chamada HTTP sem necessidade.
- Integração dos eventos Phoenix Channel `treatment:agent_assigned`, `treatment:unassigned`, `treatment:transferred`, `treatment:resolved` e `treatment:reopened`.
- Eventos devem atualizar o estado sem reload e sem desmontar/recriar a conversa Carbon.
- Eventos de outra Treatment devem ser ignorados quando o payload permitir essa validação; o isolamento do Channel deve ser documentado quando já garantir a invariável.
- Refresh e reconnect devem reconstruir o estado persistido, sem depender do histórico anterior de eventos.

## Contrato de transições

- `agent_assigned`: aplicar `assigned_agent_id`, `assigned_at` e `status` fornecidos pelo backend.
- `unassigned`: preferir os valores do evento; fallback compatível limpa assignment e usa `open`.
- `transferred`: aplicar novo assignment e status do payload sem remontar Carbon.
- `resolved`: aplicar status e dados de resolução, preservando assignment.
- `reopened`: aplicar status e demais campos enviados; não inferir campos ausentes além do contrato conhecido.

O backend permanece como fonte da verdade. O frontend não deve inferir status a partir de uma ação ou evento isolado quando o payload persistido/publicado fornecer o estado.

## Fora do escopo

Botões Assumir, Liberar, Transferir, Resolver ou Reabrir; seleção de agente; novo layout visual; ServiceDesk; typing Carbon; regras de autorização; mudanças no backend.

## Acceptance

- [ ] Existe uma representação única do estado da Treatment.
- [ ] Estado inicial, assignment e resolution vêm do backend/fluxo existente.
- [ ] Os cinco eventos de lifecycle atualizam o estado sem reload.
- [ ] Reconnect/refresh reconstrói o estado persistido.
- [ ] A conversa Carbon não é remontada por alteração de lifecycle.
- [ ] Não há botões, layout definitivo ou autorização duplicada nesta story.
- [ ] Testes, lint, typecheck e build passam.

## Tasks

- [x] Mapear como Treatment chega hoje ao frontend

- [x] Mapear useRoomChannel e listeners Phoenix atuais

- [x] Definir tipo TypeScript da Treatment/lifecycle

- [x] Escrever testes RED para estado inicial e transições realtime

- [x] Implementar estado inicial e integração dos cinco eventos

- [x] Garantir reconstrução após reconnect/refresh e isolamento por Treatment

- [x] Refatorar mantendo testes verdes

- [x] Rodar testes focados e suíte relevante

- [x] Rodar lint, typecheck e build

- [x] Marcar como delivered e aguardar revisão humana

- [x] Incorporar feedback de revisão nos testes da fronteira Treatment
## Comments

@JuruSysadmin 2026-08-21
Implementado em feat/treatment-lifecycle-state. Criado treatmentLifecycle.state.ts com estados open/in_progress/resolved/closed, snapshot inicial do join Phoenix, transições para agent_assigned/unassigned/transferred/resolved/reopened e isolamento por treatment_id. useRoomChannel expõe treatment e reconstrói o snapshot no join/reconnect; Carbon não depende desse estado para remontagem. Evidências: npm run test:run -- src/modules/chat/hooks/treatmentLifecycle.state.test.ts src/modules/chat/hooks/useRoomChannel.test.ts src/modules/carbon-ai/CarbonAiChatPanel.test.tsx (13 testes passando); npx tsc -b --pretty false (passou); npm run lint (0 erros, 1 warning preexistente em src/modules/8045/hooks/usePriceTags8045FilterForm.ts); npm run build (passou, com avisos existentes do Carbon/Vite e chunks grandes); git diff --check (passou). A suíte completa npm run test:run excedeu 180s com falhas de handlers MSW/requisições externas fora do escopo, especialmente OrdersContent e módulos de-por.

@JuruSysadmin 2026-08-21
Feedback incorporado: removido o teste que comparava um objeto consigo mesmo; o reconnect agora exerce treatmentStateFromPayload. Unassigned usa payload completo com status open e campos de assignment nulos. Adicionados testes para snapshot sem id, status desconhecido e resolved parcial preservando assignment. Verificação: bun run test focado passou com 16 testes; npx tsc -b passou; bun run lint passou com 1 warning preexistente; bun run build passou; git diff --check passou.
