---
title: Garantir rollback transacional na atribuicao por sala
type: bug
created: "2026-08-21T14:14:54Z"
modified: "2026-08-21T14:21:16Z"
author: JuruSysadmin
status: delivered
started: "2026-08-21T14:15:18Z"
finished: "2026-08-21T14:21:16Z"
delivered: "2026-08-21T14:21:16Z"
---

## Problem statement

`Chat.Treatments.assign_agent_for_room/2` delega a `assign_room_treatment/2`, que atualmente chama `assign_locked_and_audit/2` sem garantir `Repo.transaction/1`. Quando a persistencia do `treatment_assigned` falha, `Repo.rollback/1` pode ser executado fora de uma transacao e levantar em vez de retornar um erro controlado.

O contrato publico deve permanecer inalterado: primeira atribuicao retorna `{:ok, treatment, :assigned}`, retry do mesmo agente retorna `{:ok, treatment, :idempotent}` e erros continuam como `{:error, reason}`. Lock `FOR UPDATE`, auditoria atomica e broadcasts existentes devem ser preservados.

## Acceptance

- [x] Falha da auditoria na atribuicao por sala retorna erro sem executar rollback fora de transacao.
- [x] Update da Treatment e AuditEvent permanecem atomicos.
- [x] `assign_agent_for_room/2` preserva seu contrato publico.
- [x] Idempotencia e `FOR UPDATE` permanecem ativos.
- [x] `RoomChannel` continua publicando somente o resultado `:assigned`.
- [x] Testes focados, `mix test`, `mix precommit`, `mix format --check-formatted` e `git diff --check` dos arquivos da story passam; o check global preserva apenas a falha preexistente fora do escopo em `_icebox.md`.

## Tasks

- [x] Tracar o fluxo `assign_agent_for_room/2` ate `Repo.rollback/1`.
- [x] Escrever regressao RED para falha de auditoria/rollback.
- [x] Reutilizar o helper transacional existente sem alterar o contrato publico.
- [x] Verificar idempotencia, lock e broadcasts.
- [x] Executar todos os gates solicitados.
- [x] Entregar para revisao humana sem aceitar automaticamente.

## Comments
@JuruSysadmin 2026-08-21
RED observado com auditoria injetada: inicialmente a falha era ignorada e a atribuicao persistia. A seam revelou que o wrapper de membership hoje abre transacao; o helper foi tornado transaction-aware para preservar o motivo do rollback em transacao aninhada. GREEN: Treatment permaneceu open, sem assignment nem AuditEvent. Verificacao: 57 testes focados, mix test e mix precommit com 488 testes, format check e diff check focado passaram. O diff check global continua apontando somente a linha em branco preexistente em _icebox.md, preservada fora do escopo.

## Attachments
