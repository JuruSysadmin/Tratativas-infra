---
title: Permitir reabrir Tratativa
type: feature
created: "2026-08-21T14:35:51Z"
modified: "2026-08-21T15:12:00Z"
author: JuruSysadmin
status: delivered
estimate: "3"
tags: [backend, elixir, treatments, authorization, tdd]
started: "2026-08-21T14:36:30Z"
finished: "2026-08-21T15:12:00Z"
delivered: "2026-08-21T15:12:00Z"
---

## Problem statement

Como usuario autorizado, quero reabrir uma Tratativa resolvida para que o atendimento possa continuar quando o problema ainda exigir acao.

A reabertura e uma transicao de dominio, nao uma mudanca visual. No primeiro corte, deve preservar `assigned_agent_id` e `assigned_at`, limpar `resolved_by_id` e `resolved_at` e mudar `resolved` para `in_progress`.

## Contrato

Adicionar `Chat.Treatments.reopen/2` com resultados:

    {:ok, treatment, :reopened}
    {:error, :forbidden}
    {:error, :invalid_status}
    {:error, :not_found}

Usar `Authorization.authorize(user, "treatment.reopen")`. Commercial e logistics_agent sao permitidos conforme a matriz atual. A decisao deve recarregar o estado persistido com `FOR UPDATE`, sem confiar no struct do caller.

Update e `treatment_reopened` AuditEvent pertencem a mesma transaction. Falha da auditoria deve reverter integralmente a Treatment.

## Acceptance

- [x] TDD iniciado antes da implementacao e RED observado para `reopen/2` inexistente.
- [x] Commercial e logistics_agent podem reabrir.
- [x] Autorizacao reutiliza `Authorization.authorize/2` sem duplicar roles.
- [x] Usuario com role permitida, mas sem membership da Room, recebe `not_found` sem alteracao nem auditoria.
- [x] Somente `resolved` pode ser reaberta.
- [x] Estado persistido e recarregado sob `FOR UPDATE`; struct stale nao decide.
- [x] Reabertura muda status para `in_progress`.
- [x] `assigned_agent_id` e `assigned_at` sao preservados.
- [x] `resolved_by_id` e `resolved_at` sao limpos.
- [x] Exatamente um `treatment_reopened` e criado atomicamente.
- [x] Falha da auditoria causa rollback integral.
- [x] Concorrencia permite uma reabertura; segunda tentativa retorna `invalid_status`.
- [x] Treatment inexistente retorna `not_found` sem exception.
- [x] Nenhum Channel, broadcast, Presence ou frontend e alterado.
- [x] Testes focados, `mix format --check-formatted`, `mix test`, `mix precommit` e `git diff --check` dos arquivos da story passam.
- [x] Story e entregue para revisao humana sem aceite automatico.

## Tasks

- [x] Ler `resolve/2`, `assign_agent/2`, helpers transacionais e `Treatment.resolution_changeset/3`.
- [x] Escrever TDD-01 e confirmar RED.
- [x] Implementar changeset de reabertura.
- [x] Implementar `Treatments.reopen/2` com autorizacao, transaction e `FOR UPDATE`.
- [x] Preservar assignment e limpar campos de resolucao.
- [x] Auditar `treatment_reopened` na mesma transaction.
- [x] Testar roles permitidas e role proibida.
- [x] Testar estados invalidos e not_found.
- [x] Testar estado stale, rollback da auditoria e concorrencia.
- [x] Refatorar mantendo testes verdes.
- [x] Rodar testes focados e todos os gates solicitados.
- [x] Marcar story como delivered e aguardar revisao humana.

- [x] Adicionar regressao para usuario autorizado fora da Room
- [x] Restringir a query FOR UPDATE por room_members sem revelar existencia
- [x] Reexecutar gates e atualizar PR 11
## Fora do escopo

`treatment:reopen` no RoomChannel, broadcast `treatment:reopened`, unassign, transfer, frontend, Carbon AI Chat e Presence.

## Proxima story

Expor reabertura da Tratativa via Phoenix Channel.

## Comments
@JuruSysadmin 2026-08-21
TDD concluido. RED inicial observado por UndefinedFunctionError de reopen/2; segundo RED confirmou resolved_by_id ainda persistido antes da limpeza. GREEN: resolved -> in_progress sob FOR UPDATE, assignment preservado, resolucao limpa e treatment_reopened atomico. Cobertos commercial, logistics_agent, forbidden, estados invalidos, stale state, rollback de auditoria, concorrencia, retry e not_found. Verificacao: 44 testes focados, ad-hoc com 38, mix test e mix precommit com 496, format check e diff check dos arquivos da story passaram. O diff check global preserva somente a linha em branco preexistente em _icebox.md, fora do escopo.

@JuruSysadmin 2026-08-21
Request changes de membership atendido. RED confirmou que commercial autorizado fora da Room conseguia reabrir. A query contextual de authorized_treatment/2 foi extraida e reutilizada com FOR UPDATE; ausencia de Treatment ou membership retorna not_found sem update nem treatment_reopened. O teste de logistics_agent agora explicita membership. Verificacao: 45 focados, ad-hoc especifico, mix test e mix precommit com 497, format e diff check focado passaram. Normalizers permaneceram fora do escopo. O check global preserva somente a linha em branco preexistente em _icebox.md.

## Attachments

## Rejection notes

- 2026-08-21: PR review: reopen/2 valida role, mas nao restringe a Treatment por membership da Room
