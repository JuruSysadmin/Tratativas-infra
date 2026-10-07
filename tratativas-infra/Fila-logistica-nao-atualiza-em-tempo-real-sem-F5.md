---
title: Fila logistica nao atualiza em tempo real sem F5
type: bug
created: "2026-10-06T16:06:27Z"
modified: "2026-10-06T16:08:02Z"
author: JuruSysadmin
status: delivered
started: "2026-10-06T16:06:35Z"
finished: "2026-10-06T16:08:02Z"
delivered: "2026-10-06T16:08:02Z"
---

## Problem statement
Ao abrir tratativa no Comercial, a fila da Logística só refletiu o pedido após F5. O canal `treatments:queue` / `treatment:created` deveria atualizar a lista sem reload.

## Cause
`updateTreatmentQueueItemInCache` grava em `treatmentQueueQueryKeys.list()` (`['treatment-queue','list']`), mas `useTreatmentQueueQuery` lê `['treatment-queue','list', { search, limit, status }]`. O prepend otimista nunca entra na cache visível; só o `invalidateQueries` + refetch salva — e com a fila lenta no Orders API isso falhava na prática.

## Possible solution
Usar `setQueriesData` com partial key para atualizar todas as variantes da lista; manter invalidate. Testes com a key real parametrizada.

## Acceptance
- Novo `treatment:created` aparece na fila ativos sem F5 (cache e/ou refetch).
- Testes do realtime da fila cobrem key parametrizada.
- Vitest dos hooks/página passa.

## Tasks
- [x] Corrigir setQueriesData para keys parametrizadas
- [x] Atualizar testes do treatmentQueue.realtime
- [x] Verificar vitest e entregar
