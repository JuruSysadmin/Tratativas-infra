---
title: Queue counts SQL e warm async CustomerNames
type: chore
created: "2026-10-07T18:57:42Z"
modified: "2026-10-07T18:59:39Z"
author: JuruSysadmin
status: accepted
started: "2026-10-07T18:57:59Z"
finished: "2026-10-07T18:59:30Z"
delivered: "2026-10-07T18:59:30Z"
accepted: "2026-10-07T18:59:30Z"
---

## Problem statement
Ainda restam dois custos na fila: `queue_counts` materializa todos os `{id,status}` em memória; e nomes de cliente só entram no cache se alguém chamar `resolve/2` (a fila usa só cache).

## Possible solution
1. `queue_counts` via `group_by status` + `count(distinct id)`.
2. `CustomerNames.warm_async/2` após responder a fila — preenche misses em background sem bloquear o JSON.

## Acceptance
- Counts da fila iguais ao comportamento atual, sem carregar todas as rows.
- Miss de nome na fila responde null imediato; warm async popula ETS para o próximo fetch.
- Testes CustomerNames + queue counts/controller passam.

## Tasks
- [x] Teste + implementação warm_async
- [x] Teste + queue_counts SQL aggregate
- [x] Controller dispara warm após resolve_cached
- [x] mix test focados / deliver

## Comments

@JuruSysadmin 2026-10-07
queue_counts validado em MIX_ENV=dev contra pg (GROUP BY + count DISTINCT). warm_async + testes escritos. mix test local bloqueado (Postgres test down).
