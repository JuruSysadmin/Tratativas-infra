---
title: Expor resolucao da Tratativa via Phoenix Channel
type: feature
created: "2026-08-21T12:43:02Z"
modified: "2026-08-21T12:54:03Z"
author: JuruSysadmin
status: delivered
estimate: "2"
tags: [backend, elixir, phoenix, channels, treatments, tdd]
started: "2026-08-21T12:44:13Z"
finished: "2026-08-21T12:53:51Z"
delivered: "2026-08-21T12:53:51Z"
---

## Problem statement

Como agente da logística responsável por uma Tratativa, quero resolvê-la através do Phoenix Channel para que o frontend possa concluir o atendimento usando a regra de domínio já implementada.

A regra de resolução já existe em `Chat.Treatments.resolve/2`.

O Channel deve funcionar somente como adaptador de transporte. Ele não deve duplicar autorização, ownership, validação de status, locking ou persistência.

## Contrato

Adicionar ao tópico `room:<room_id>` o evento `treatment:resolve` com payload `{}`.

O usuário responsável deve vir exclusivamente de `socket.assigns.current_user`.

Não aceitar do cliente `user_id`, `agent_id`, `resolved_by_id`, `resolved_at` ou `status` como fonte de dados de domínio.

## Fluxo esperado

`channel.push("treatment:resolve", {})` → `RoomChannel` → `socket.assigns.current_user` + `room_id` → `Chat.Treatments` → `resolve/2` → reply.

Preferir uma API no contexto baseada na sala, seguindo o padrão adotado para assignment, por exemplo `Treatments.resolve_for_room(room_id, current_user)`. O nome final deve seguir as APIs já existentes em `Chat.Treatments`.

## TDD primeiro

Implementar obrigatoriamente RED → GREEN → REFACTOR. O primeiro teste deve existir antes do `handle_in/3`.

### TDD-01 — Agente responsável resolve pelo Channel

Preparar Treatment `in_progress`, atribuída ao Agent A. Conectar Agent A à sala e enviar `treatment:resolve` com `{}`. Esperar sucesso e confirmar no banco `status == "resolved"`, `resolved_by_id == Agent A.id`, `resolved_at != nil`; `assigned_agent_id` e `assigned_at` permanecem inalterados.

### TDD-02 — Commercial recebe forbidden

Commercial envia `treatment:resolve`. Esperar `forbidden`; Treatment permanece inalterada.

### TDD-03 — Outro agente não pode resolver

Treatment atribuída ao Agent A; Agent B envia o evento. Esperar `not_assigned_agent` e nenhuma resolução.

### TDD-04 — Status inválido

Cobrir pelo Channel pelo menos um estado que não pode ser resolvido, por exemplo `resolved`. Esperar `invalid_status`. A lista de estados válidos continua pertencendo a `Treatments.resolve/2`.

### TDD-05 — Sala sem Treatment

Enviar `treatment:resolve` em Room válida sem Treatment. Esperar `not_found`, sem exception.

### TDD-06 — Cliente não escolhe resolved_by

Enviar propositalmente `resolved_by_id` e `agent_id` de outro usuário. Esses valores nunca determinam quem resolveu. Se campos extras forem ignorados, persistir o usuário de `socket.assigns.current_user`; se forem rejeitados, seguir o padrão existente.

### TDD-07 — Cliente não escolhe timestamp/status

Enviar `resolved_at: "2000-01-01T00:00:00Z"` e `status: "resolved"`. O cliente não controla esses campos; são definidos pelo domínio.

### TDD-08 — Auditoria continua pertencendo ao domínio

Após sucesso pelo Channel, deve existir exatamente um `treatment_resolved`, sem o RoomChannel criar AuditEvent. Em `forbidden`, `not_assigned_agent`, `invalid_status` e `not_found`, nenhum novo `treatment_resolved` deve existir.

## Tratamento de erros

Mapear `forbidden`, `not_assigned_agent`, `invalid_status` e `not_found` para replies estáveis. Possuir fallback seguro `treatment_resolution_failed` para erro inesperado. Não expor Ecto.Changeset, exceptions, SQL ou detalhes internos.

## Acceptance

* [x] Desenvolvimento iniciado com TDD.
* [x] RED observado antes da implementação do handler.
* [x] Existe evento `treatment:resolve`.
* [x] Usuário vem de `socket.assigns.current_user`.
* [x] Treatment é localizada através da camada `Chat.Treatments`.
* [x] Channel não acessa `Repo` diretamente.
* [x] Channel não acessa `Treatment` diretamente para persistência.
* [x] Regra é delegada para `Treatments.resolve/2`.
* [x] Agente responsável consegue resolver.
* [x] Commercial recebe `forbidden`.
* [x] Outro agente recebe `not_assigned_agent`.
* [x] Estado inválido retorna `invalid_status`.
* [x] Room sem Treatment retorna `not_found`.
* [x] Cliente não controla `resolved_by_id`.
* [x] Cliente não controla `resolved_at`.
* [x] Cliente não controla `status`.
* [x] Sucesso mantém `assigned_agent_id`.
* [x] Sucesso mantém `assigned_at`.
* [x] Auditoria continua sendo criada pelo domínio.
* [x] Erros conhecidos possuem replies estáveis.
* [x] Erro inesperado possui fallback seguro.
* [x] Nenhuma regra de role foi duplicada no Channel.
* [x] Nenhuma regra de ownership foi duplicada no Channel.
* [x] Nenhum `FOR UPDATE` foi adicionado ao Channel.
* [x] Nenhum broadcast foi implementado.
* [x] Nenhum Presence foi implementado.
* [x] Nenhum frontend foi alterado.
* [x] Testes focados passam.
* [x] `mix format --check-formatted` passa.
* [x] `mix test` passa.
* [x] `mix precommit` passa.
* [x] `git diff --check` dos arquivos da story passa.

## Tasks

* [x] Ler o handler atual de assignment no `RoomChannel`.
* [x] Ler `Treatments.resolve/2`.
* [x] Identificar o padrão atual `assign_agent_for_room/2`.
* [x] Escrever teste RED para resolução bem-sucedida.
* [x] Criar operação de contexto por `room_id`, se necessária.
* [x] Implementar `treatment:resolve`.
* [x] Traduzir sucesso para reply estável.
* [x] Testar `forbidden`.
* [x] Testar `not_assigned_agent`.
* [x] Testar `invalid_status`.
* [x] Testar `not_found`.
* [x] Testar tentativa de fornecer `resolved_by_id`.
* [x] Testar tentativa de fornecer `resolved_at`.
* [x] Garantir fallback para erro inesperado.
* [x] Verificar auditoria integrada.
* [x] Refatorar mantendo os testes verdes.
* [x] Executar testes focados.
* [x] Executar `mix format --check-formatted`.
* [x] Executar `mix test`.
* [x] Executar `mix precommit`.
* [x] Executar `git diff --check`.
* [x] Marcar como `delivered`.
* [x] Aguardar revisão humana antes de `accepted`.

## Fora do escopo

Não implementar broadcast `treatment_resolved`, broadcast `treatment_assigned`, Presence, frontend, Carbon AI Chat, reopen, unassign, transfer ou closed.

## Próxima story

Depois desta: `[Feature] Publicar mudanças da Tratativa em realtime`, tratando broadcasts de `treatment_assigned` e `treatment_resolved` sem misturar transporte de comando com propagação de estado.

## Comments
@Hermes 2026-08-21
Implementação concluída com TDD. RED inicial observado por ausência de `handle_in("treatment:resolve", ...)`; REDs adicionais observaram cada erro conhecido cair no fallback antes do respectivo mapeamento. `RoomChannel` usa exclusivamente `socket.assigns.current_user` e delega a `Treatments.resolve_for_room/2`, que localiza a Treatment por sala e reutiliza `Treatments.resolve/2`; não há Repo, persistência, locking, auditoria, broadcast ou Presence no handler. Verificação: 52 testes focados passaram; `mix format --check-formatted` passou; `mix test` e `mix precommit` passaram com 483 testes e Credo sem issues; `git diff --check` dos arquivos da story passou. O check global mantém somente a linha em branco preexistente em `tratativas-infra/_icebox.md`, fora do escopo.

## Attachments
