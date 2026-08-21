---
title: Expandir lifecycle da Tratativa
type: feature
estimate: 3
tags: [backend, elixir, treatments, lifecycle, tdd]
created: "2026-08-21T02:13:05Z"
modified: "2026-08-21T02:30:18Z"
author: JuruSysadmin
status: delivered
started: "2026-08-21T02:13:46Z"
finished: "2026-08-21T02:30:18Z"
delivered: "2026-08-21T02:30:18Z"
---

# Expandir lifecycle da Tratativa

## Problem statement

Como sistema, quero evoluir o lifecycle da Tratativa para controlar explicitamente o atendimento desde a abertura até o fechamento definitivo.

As transições formais desta story são:

```text
open
  ↓ agente assume
in_progress
  ↓ resolve
resolved
  ↓ fechamento definitivo
closed
```

A decisão desta story é que `Chat.Treatments.assign_agent/2` deve executar a atribuição e, na mesma operação de domínio, mover uma Tratativa `open` para `in_progress`. A transição de atribuição deve ser idempotente para retry do mesmo agente e não deve reabrir nem alterar uma Tratativa que já esteja em outro estado sem uma regra explícita.

Esta story implementa somente a primeira transição do lifecycle. `resolve` e fechamento definitivo serão stories posteriores.

## Contract

### Comportamento de `assign_agent/2`

```text
open + sem agente
  → atribui
  → status = in_progress
  → {:ok, treatment}

in_progress + mesmo agente
  → retry idempotente
  → preserva assigned_at
  → {:ok, treatment}

in_progress + outro agente
  → {:error, :already_assigned}

resolved/closed + qualquer agente
  → {:error, :invalid_status}
```

`assign_agent/2` não decide reabertura implicitamente. A transição `resolved → ...` será responsabilidade de uma futura `reopen/2`.

- Uma Treatment nova inicia em `open`.
- Agente autorizado assume uma Treatment `open`.
- A atribuição bem-sucedida persiste `assigned_agent_id`, `assigned_at` e `status: "in_progress"` atomicamente.
- Retry do mesmo agente em uma Treatment já atribuída mantém `assigned_at` e o estado atual.
- Outro agente não substitui o responsável existente.
- A atribuição de uma Treatment que não está `open` não deve ser inferida como válida; o comportamento deve ser coberto por teste e permanecer explícito no domínio.
- Não implementar `resolve`, `closed`, frontend ou broadcast adicional nesta story.

## Acceptance

* [x] Desenvolvimento iniciado com TDD.
* [x] RED observado para a transição `open` → `in_progress`.
* [x] Treatment nova inicia com status `open`.
* [x] `assign_agent/2` persiste atribuição e muda `open` para `in_progress` na mesma transação.
* [x] Retry idempotente do mesmo agente preserva `assigned_at` e status.
* [x] Outro agente não substitui o responsável.
* [x] Estados não cobertos pela transição não são alterados silenciosamente.
* [x] `resolve` e `closed` permanecem fora do escopo.
* [x] `mix format --check-formatted` passa.
* [x] `mix test` passa.
* [x] `mix precommit` passa.
* [x] `git diff --check` do escopo passa.
* [x] Story entregue para revisão humana.

## Tasks

* [x] Ler `Treatment`, `Chat.Treatments.assign_agent/2`, migrations e testes atuais.
* [x] Confirmar vocabulário e default atual de status.
* [x] Definir comportamento para atribuição fora de `open` antes da implementação.
* [x] Escrever teste RED para `open` → `in_progress`.
* [x] Executar o teste e confirmar a falha esperada.
* [x] Implementar a transição mínima na operação de domínio.
* [x] Garantir atomicidade entre atribuição, timestamp e status.
* [x] Testar retry idempotente e preservação do timestamp.
* [x] Testar conflito com outro agente.
* [x] Testar estados fora da transição explícita.
* [x] Refatorar mantendo os testes verdes.
* [x] Executar testes focados.
* [x] Executar `mix format --check-formatted`.
* [x] Executar `mix test`.
* [x] Executar `mix precommit`.
* [x] Executar `git diff --check` focado.
* [x] Marcar a story como `delivered` e aguardar aceite humano.

- [x] Registrar a matriz formal de assign_agent/2 no contrato.
- [x] Adicionar teste explícito para resolved/closed com qualquer agente retornando invalid_status.
- [x] Executar a matriz completa e atualizar a evidência da story.
## Fora do escopo

```text
resolve
closed
reopen
unassign
transfer
frontend
Phoenix Channel
broadcast adicional
Presence
```

## Próxima story

Implementar `in_progress` → `resolved` com autorização e invariantes próprias.

## Comments

@JuruSysadmin 2026-08-21
Decisão funcional: assumir uma Tratativa `open` move o status para `in_progress` na mesma operação de domínio. A implementação deve preservar a atribuição e o timestamp em retry idempotente e não inventar transições para `resolve` ou `closed`.

@JuruSysadmin 2026-08-21
Implementação concluída: Treatments.assign_agent/2 agora exige Treatment open para nova atribuição, persiste assigned_agent_id, assigned_at e status in_progress na mesma atualização, preserva retry idempotente e rejeita closed com invalid_status. O Channel traduz invalid_status sem crash. RED observado no teste de transição; 32 testes focados passaram; mix format --check-formatted, mix precommit (463 testes) e git diff --check focado passaram. Warnings existentes de PubSub/broadcast não causaram falha. Story entregue para revisão humana.

@JuruSysadmin 2026-08-21
Feedback incorporado: contrato formal da matriz de assign_agent/2 adicionado ao card. A cobertura explícita de resolved e closed confirma {:error, :invalid_status}; não há reabertura implícita. A futura reopen/2 será responsável por qualquer transição a partir de resolved.

@JuruSysadmin 2026-08-21
Revisão incorporada: o card agora documenta a matriz open sem agente → in_progress/ok; in_progress com mesmo agente → retry idempotente; in_progress com outro agente → already_assigned; resolved/closed com qualquer agente → invalid_status. Teste explícito cobre resolved e closed sem alterar atribuição. A matriz focada passou com 33 testes; mix format --check-formatted, mix precommit (464 testes) e git diff --check focado passaram. Não há reabertura implícita; reopen/2 ficará em story futura.
