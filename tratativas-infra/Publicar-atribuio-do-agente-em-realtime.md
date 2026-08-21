---
title: Publicar atribuição do agente em realtime
type: feature
created: "2026-08-21T01:50:10Z"
modified: "2026-08-21T13:11:49Z"
author: JuruSysadmin
status: delivered
started: "2026-08-21T01:58:15Z"
finished: "2026-08-21T13:11:43Z"
delivered: "2026-08-21T13:11:43Z"
---

# Publicar atribuição do agente em realtime

**Type:** Feature
**Estimate:** TBD
**Labels:** `backend`, `elixir`, `phoenix`, `channels`, `realtime`, `treatments`, `tdd`

## Problem statement

Como participante da sala de uma Tratativa, quero receber em realtime o evento de atribuição do agente depois que a atribuição for persistida com sucesso.

A story depende de `Chat.Treatments.assign_agent/2` e do comando Channel `treatment:assign_to_me`, já implementados. O broadcast deve ocorrer somente após sucesso da atribuição. Não alterar a regra de autorização, concorrência ou persistência.

## Contract

Comando recebido no tópico `room:<room_id>`:

```text
treatment:assign_to_me
```

Evento publicado aos participantes após atribuição bem-sucedida:

```text
treatment:agent_assigned
```

Payload mínimo:

```elixir
%{
  treatment_id: treatment.id,
  assigned_agent_id: treatment.assigned_agent_id,
  assigned_at: treatment.assigned_at
}
```

O broadcast deve ser emitido exatamente uma vez por atribuição bem-sucedida. Não emitir broadcast para `forbidden`, `already_assigned` ou `not_found`.

## TDD

RED: a atribuição bem-sucedida ainda não gera `treatment:agent_assigned`.

GREEN: após persistir a atribuição, os participantes da sala recebem exatamente um evento com `treatment_id`, `assigned_agent_id` e `assigned_at`.

Casos obrigatórios:

- sucesso gera exatamente um broadcast;
- payload contém `treatment_id`;
- payload contém `assigned_agent_id`;
- payload contém `assigned_at`;
- `forbidden` não gera broadcast;
- `already_assigned` não gera broadcast;
- `not_found` não gera broadcast.

## Acceptance

* [x] Desenvolvimento iniciado com TDD.
* [x] RED observado antes do broadcast.
* [x] Evento `treatment:agent_assigned` é publicado após sucesso.
* [x] Participantes da sala recebem o evento.
* [x] Sucesso gera exatamente um broadcast.
* [x] Payload contém `treatment_id`.
* [x] Payload contém `assigned_agent_id`.
* [x] Payload contém `assigned_at`.
* [x] `forbidden` não gera broadcast.
* [x] `already_assigned` não gera broadcast.
* [x] `not_found` não gera broadcast.
* [x] Broadcast ocorre depois da persistência bem-sucedida.
* [x] Não há broadcast duplicado em retry idempotente sem nova atribuição.
* [x] Não há alteração indevida na regra de domínio.
* [x] Não há frontend nesta story.
* [x] `mix format --check-formatted` passa.
* [x] `mix test` passa.
* [x] `mix precommit` passa.
* [x] `git diff --check` passa.

## Tasks

* [x] Ler `RoomChannel`, `Chat.Treatments.assign_agent/2`, broadcaster e testes atuais.
* [x] Identificar o mecanismo atual de broadcast por tópico.
* [x] Escrever RED para ausência de `treatment:agent_assigned`.
* [x] Definir o ponto após persistência em que o broadcast deve ocorrer.
* [x] Implementar broadcast único após sucesso.
* [x] Definir payload estável do evento.
* [x] Testar entrega aos participantes da sala.
* [x] Testar exatamente um broadcast em sucesso.
* [x] Testar ausência de broadcast em `forbidden`.
* [x] Testar ausência de broadcast em `already_assigned`.
* [x] Testar ausência de broadcast em `not_found`.
* [x] Testar retry idempotente sem broadcast duplicado.
* [x] Refatorar mantendo testes verdes.
* [x] Executar testes focados.
* [x] Executar `mix format --check-formatted`.
* [x] Executar `mix test`.
* [x] Executar `mix precommit`.
* [x] Executar `git diff --check` (diff da story passa; check global mantém ressalva preexistente em `tratativas-infra/_icebox.md`).
* [x] Marcar como `delivered` e aguardar aceite humano.
* [x] Adicionar regressão forte: estado do caller stale, banco já atribuído ao mesmo agente e retry sem novo `treatment:agent_assigned`.

## Fora do escopo

```text
alterar Authorization
alterar Treatments.assign_agent/2
alterar concorrência
alterar assigned_at
frontend
Carbon AI Chat
Presence como fonte de verdade
```

## Próxima story

Integrar o evento `treatment:agent_assigned` na interface de usuário.

## Comments

@JuruSysadmin 2026-08-21
PM iniciou a story. Estimate permanece `TBD` por enquanto; decisão funcional confirmada: broadcast `treatment:agent_assigned` somente após sucesso persistido, exatamente uma vez, sem broadcast para forbidden/already_assigned/not_found ou retry idempotente.

@JuruSysadmin 2026-08-21
Implementação concluída na branch `feat/expose-treatment-assignment-channel`: após `assign_agent/2` retornar sucesso para uma Treatment livre, o Channel publica exatamente uma vez `treatment:agent_assigned` com `treatment_id`, `assigned_agent_id` e `assigned_at`. Retry idempotente do mesmo agente não publica duplicata. `forbidden`, `already_assigned` e `not_found` não publicam evento. TDD RED observado antes do broadcast; 15 testes do Channel passaram; `mix format --check-formatted`, `mix test` (462 testes), `mix precommit` e diff focado passaram. Warnings existentes de PubSub/broadcast não causaram falha.

@Hermes 2026-08-21
Request changes do commit e2e1831 tratado. A análise confirmou a janela stale original: o Channel inferia transição a partir do %Treatment{} lido antes do lock. O código atual já corrige a raiz ao propagar :assigned | :idempotent do estado carregado sob FOR UPDATE e publicar somente :assigned. Adicionada regressão forte mantendo struct stale no caller, atribuindo no banco ao mesmo agente, confirmando :idempotent por room_id e zero novos treatment:agent_assigned no retry do Channel. O novo teste passou imediatamente, demonstrando que a correção posterior já estava ativa. Verificação: 25 testes do Channel, 484 testes completos, mix precommit e diff focado passaram; Credo sem issues.
