---
title: Publicar resolucao da Tratativa em realtime
type: feature
created: "2026-08-21T13:59:15Z"
modified: "2026-08-21T14:07:14Z"
author: JuruSysadmin
status: delivered
estimate: "2"
tags: [backend, elixir, phoenix, channels, treatments, realtime, tdd]
started: "2026-08-21T14:00:09Z"
finished: "2026-08-21T14:07:14Z"
delivered: "2026-08-21T14:07:14Z"
---

## Problem statement

Como participante de uma sala de Tratativa, quero receber uma notificacao realtime quando a Tratativa for resolvida, para que todos os participantes atualizem seu estado sem recarregar a pagina.

O comando `treatment:resolve` e a regra `Chat.Treatments.resolve/2` ja existem. A integracao por sala continua atraves de `Chat.Treatments`; o `RoomChannel` nao acessa `Repo` nem cria auditoria.

## Contrato

Apos uma resolucao efetivamente confirmada pelo dominio, publicar no topico `room:<room_id>` o evento `treatment:resolved` com:

    %{
      treatment_id: treatment.id,
      status: "resolved",
      resolved_by_id: treatment.resolved_by_id,
      resolved_at: treatment.resolved_at
    }

O payload vem da Treatment persistida retornada pela operacao. Nenhum valor de identidade, status ou timestamp aceito do cliente controla a operacao.

A decisao de publicar deve vir de um resultado explicito produzido pelo dominio depois de `SELECT FOR UPDATE`, por exemplo `{:ok, treatment, :resolved}`. Retry, forbidden, not_assigned_agent, invalid_status e not_found nao publicam evento. O broadcast ocorre depois do commit e nao dentro da transaction.

## TDD

Implementar RED -> GREEN -> REFACTOR, observando RED antes da implementacao. Cobrir resolucao valida, segunda tentativa sem duplicata, forbidden, agente nao responsavel, sala sem Treatment, status invalido e duas tentativas concorrentes com exatamente um broadcast. Tambem cobrir payload derivado do estado persistido e auditoria unica `treatment_resolved` criada por `Chat.Treatments`.

## Acceptance

- [x] Resolucao valida publica exatamente um `treatment:resolved`.
- [x] Payload possui `treatment_id`, `status: "resolved"`, `resolved_by_id` e `resolved_at` derivados da Treatment retornada.
- [x] Segunda tentativa retorna `invalid_status` e nao publica novamente.
- [x] `forbidden`, `not_assigned_agent`, `invalid_status` e `not_found` nao publicam.
- [x] Concorrencia produz uma resolucao e um broadcast.
- [x] Auditoria continua em `Chat.Treatments`; Channel nao cria `AuditEvent`.
- [x] Broadcast ocorre somente apos sucesso do dominio e fora da transaction.
- [x] Nenhuma regra de role/ownership ou acesso direto a `Repo` e adicionada ao Channel.
- [x] Nenhum frontend ou Presence e alterado.
- [x] Testes focados, `mix format --check-formatted`, `mix test`, `mix precommit` e `git diff --check` passam.
- [x] Story e entregue para revisao humana; nao aceitar automaticamente.

## Tasks

- [x] Ler fluxo atual de `treatment:resolve`, `Treatments.resolve/2` e `resolve_for_room/2`.
- [x] Comparar com semantica `:assigned` / `:idempotent` do assignment.
- [x] Escrever TDD-01 para broadcast e observar RED.
- [x] Fazer o dominio informar resolucao efetiva explicitamente.
- [x] Publicar evento somente para resolucao efetiva com payload persistido.
- [x] Testar retry, erros conhecidos, concorrencia e estado stale.
- [x] Confirmar auditoria no dominio e broadcast fora da transaction.
- [x] Refatorar mantendo testes verdes.
- [x] Executar testes focados e verificacoes completas.
- [x] Marcar story como delivered e aguardar revisao humana.

## Fora do escopo

Reopen, unassign, transfer, Presence, frontend, notificacoes externas, persistencia de eventos Phoenix e outbox.

## Comments
@JuruSysadmin 2026-08-21
TDD concluido: RED observado pela ausencia de treatment:resolved; GREEN com resultado explicito :resolved produzido sob lock e broadcast apos retorno do dominio. Cobertos sucesso, retry, erros conhecidos, concorrencia e estado stale. Verificacao final: 56 testes focados, mix format --check-formatted, git diff --check e mix precommit com 487 testes passaram. Story entregue para revisao humana, sem aceite automatico.

## Attachments
