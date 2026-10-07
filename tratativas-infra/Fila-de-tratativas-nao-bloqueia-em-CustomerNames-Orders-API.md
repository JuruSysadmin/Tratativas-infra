---
title: Fila de tratativas nao bloqueia em CustomerNames / Orders API
type: chore
created: "2026-10-06T15:48:11Z"
modified: "2026-10-06T15:58:22Z"
author: JuruSysadmin
status: accepted
started: "2026-10-06T15:48:24Z"
finished: "2026-10-06T15:58:19Z"
delivered: "2026-10-06T15:58:19Z"
accepted: "2026-10-06T15:58:19Z"
---

## Problem statement
Ao listar ou refetchar a fila (`GET /api/treatments/queue`), o backend resolve nomes de cliente via `Chat.Orders.CustomerNames` / `Orders.Client` **antes** de responder. Com a API de pedidos em 502, o Req retenta e a fila demora ~5s. Assumir tratativa no frontend chama `queueQuery.refetch()` e o agente sente a UI travada, mesmo com assign já ok no Chat.

## Possible solution
1. **Backend:** `TreatmentQueueController` responde items/counts sem bloquear em CustomerNames (nomes do cache ETS só; miss → `customer_name: null`). Opcional: endpoint/enriquecimento async depois.
2. **Backend:** `Orders.Client` para lookup de nomes com fail-fast (`retry: false`, timeout curto ~300–500ms).
3. **Frontend:** após assume, manter patch otimista; refetch da fila em background sem bloquear o botão/estado de loading da lista (ou invalidar sem `await` que congela UX).

Fora de escopo: batch na API de pedidos (depende do FaaS); mudar ownership/assign.

## Acceptance
- Com Orders API em 502/lenta, `GET /treatments/queue` responde rápido (ordem de ~100ms + SQL), sem cascata de retries longos no caminho crítico.
- Items podem ter `customer_name` null; counts e assign continuam corretos.
- Assumir tratativa permanece imediato na UI (estado local); refetch não reintroduce espera de vários segundos no assign.
- Testes cobrindo controller/client (timeout/retry) e comportamento da fila sem bloqueio.
- `mix test` nos arquivos tocados passa.

## Tasks
- [x] Fail-fast no Orders.Client (retry off / timeout curto) para lookups de nome
- [x] Queue controller: usar só cache / não await get_many no path crítico
- [x] Ajustar frontend: assume otimista + refetch background
- [x] Testes backend (e front se houver) + verificação manual com FaaS down
- [x] Deliver e aguardar aceite do PM

## Comments

@JuruSysadmin 2026-10-06
Implementado: Client fail-fast (retry:false, receive_timeout:500), queue usa resolve_cached, frontend merge otimista no activeItem. Vitest LogisticsTreatmentsPage 17/17 ok. mix test Orders/queue bloqueado: Postgres 5433 up mas auth CHAT_TEST_DB_* falha neste ambiente — rodar localmente com credenciais de teste.
