---
title: Permitir liberar Tratativa
type: feature
estimate: 3
tags: [backend, elixir, treatments, authorization, audit, tdd]
status: delivered
modified: "2026-08-21T17:36:30Z"
started: "2026-08-21T17:30:24Z"
finished: "2026-08-21T17:36:30Z"
delivered: "2026-08-21T17:36:30Z"
---

## Problem statement

Como agente da logistica responsavel por uma Tratativa, quero poder liberar
uma Tratativa sob minha responsabilidade para que ela volte a ficar disponivel
para outro agente assumir.

Esta story implementa somente `unassign`. Transferencia direta entre agentes
sera implementada em story posterior e nao deve ser modelada como
`unassign + assign`, pois isso criaria uma janela em que outro agente poderia
assumir a Treatment.

## Modelo de ownership

Assign:

    open -> in_progress
    assigned_agent_id = Agent A

Unassign:

    in_progress / Agent A -> open / sem agente

Transfer futura:

    in_progress / Agent A -> in_progress / Agent B

`transfer` deve ser uma operacao atomica propria e esta story nao deve criar
`transfer_agent/3`.

## Regra de negocio

Somente o agente atualmente responsavel pode liberar a Treatment.

Antes:

    status = "in_progress"
    assigned_agent_id = Agent A
    assigned_at = timestamp

Depois:

    status = "open"
    assigned_agent_id = nil
    assigned_at = nil

## Autorizacao

Reutilizar:

    Authorization.authorize(user, "treatment.unassign")

Matriz atual:

    logistics_agent -> permitido
    commercial -> negado

Autorizacao por role nao substitui membership, ownership, status persistido ou
locking.

## Ownership e membership

Somente o agente atribuido pode executar `unassign`. Outro `logistics_agent`
recebe `{:error, :not_assigned_agent}`.

A API deve validar membership com `Rooms.with_member_room/3` ou helper
compartilhado equivalente. Usuario com role permitida fora da Room recebe
`{:error, :not_found}`, sem revelar a Treatment.

## Status permitido

Somente `in_progress` pode sofrer unassign. `open`, `resolved` e `closed`
retornam `{:error, :invalid_status}`.

A decisao deve usar o estado persistido atual.

## API

Adicionar em `Chat.Treatments`:

    unassign(treatment, user)

Contrato de sucesso:

    {:ok, treatment, :unassigned}

Erros:

    {:error, :forbidden}
    {:error, :not_found}
    {:error, :not_assigned_agent}
    {:error, :invalid_status}

O marcador `:unassigned` indica transicao efetiva e sera usado futuramente
pelo Channel para publicar `treatment:unassigned`.

## Concorrencia e transaction

Recarregar a Treatment dentro de `Repo.transaction/1` com `SELECT ... FOR
UPDATE`. Nao confiar no struct stale recebido pelo caller.

Fluxo:

    BEGIN
      |
      +-- buscar Treatment autorizada
      +-- FOR UPDATE
      +-- validar status persistido
      +-- validar ownership persistido
      +-- update in_progress -> open
      +-- limpar assigned_agent_id e assigned_at
      +-- AuditEvent treatment_unassigned
      |
    COMMIT

Falha ao persistir o AuditEvent deve executar rollback e preservar integralmente
o estado anterior.

## Auditoria

Uma liberacao efetiva cria exatamente um AuditEvent:

    event_type = "treatment_unassigned"
    treatment_id = treatment.id
    actor_id = user.id

O update e a auditoria pertencem a mesma transaction. Operacoes rejeitadas nao
criam auditoria.

## Preparacao para transfer

Nao implementar `transfer_agent/3`, `treatment:transfer` ou qualquer escolha de
agente destino. `unassign/2` nao deve depender de transferencia futura.

## TDD

Executar RED -> GREEN -> REFACTOR.

### TDD-01 - Agente responsavel consegue liberar

Treatment `in_progress`, atribuida a Agent A. `Treatments.unassign(treatment,
agent_a)` deve retornar `{:ok, treatment, :unassigned}` e persistir `open`,
`assigned_agent_id == nil` e `assigned_at == nil`.

### TDD-02 - Commercial recebe forbidden

Commercial membro recebe `{:error, :forbidden}` e a Treatment permanece
inalterada.

### TDD-03 - Outro logistics_agent nao pode liberar

Agent B recebe `{:error, :not_assigned_agent}` e assignment/status permanecem.

### TDD-04 - Usuario sem membership recebe not_found

Logistics agent autorizado fora da Room recebe `{:error, :not_found}` e zero
novos `treatment_unassigned`.

### TDD-05 - Estados invalidos

Treatments `open`, `resolved` e `closed` retornam `{:error, :invalid_status}`.

### TDD-06 - Assignment removido integralmente

Sucesso nao deixa estado parcial: status `open`, `assigned_agent_id nil` e
`assigned_at nil` na mesma persistencia.

### TDD-07 - Auditoria

Sucesso cria exatamente um `treatment_unassigned` com actor e treatment
corretos. Erros conhecidos criam zero eventos.

### TDD-08 - Falha na auditoria faz rollback

Usar o inserter injetavel existente para forcar erro e confirmar que status,
assignment e timestamp originais permanecem.

### TDD-09 - Estado stale

Caller pode possuir struct `in_progress`, mas a decisao deve usar o estado
persistido recarregado sob lock.

### TDD-10 - Concorrencia

Duas tentativas concorrentes sobre a mesma Treatment devem produzir exatamente
uma transicao `:unassigned` e um AuditEvent. A segunda reavalia o estado após o
lock e retorna erro consistente.

### TDD-11 - Concorrencia com outra transicao

Se simples com as APIs atuais, cobrir corrida entre `unassign` e `resolve`.
Nao criar infraestrutura artificial se a cobertura existente de locking for
suficiente.

### TDD-12 - Treatment inexistente

Referencia stale para Treatment removida retorna `{:error, :not_found}` sem
exception.

## Acceptance

- [x] Desenvolvimento iniciado com TDD.
- [x] RED observado antes da implementacao de `unassign/2`.
- [x] Existe `Treatments.unassign/2`.
- [x] Reutiliza `Authorization.authorize/2`.
- [x] Commercial recebe `forbidden`.
- [x] Logistics agent possui capacidade de unassign.
- [x] Membership da Room e validada.
- [x] Usuario fora da Room recebe `not_found`.
- [x] Somente o agente atribuido pode liberar.
- [x] Outro agente recebe `not_assigned_agent`.
- [x] Somente `in_progress` pode ser liberada.
- [x] Estados invalidos retornam `invalid_status`.
- [x] Treatment e recarregada sob `FOR UPDATE`.
- [x] Estado stale nao controla a operacao.
- [x] Sucesso retorna `:unassigned`.
- [x] Status volta para `open`.
- [x] `assigned_agent_id` e limpo.
- [x] `assigned_at` e limpo.
- [x] Nao existe estado intermediario persistido.
- [x] Existe auditoria `treatment_unassigned`.
- [x] AuditEvent e update sao atomicos.
- [x] Falha de auditoria causa rollback integral.
- [x] Operacoes rejeitadas nao geram auditoria.
- [x] Concorrencia permite somente uma transicao efetiva.
- [x] Concorrencia produz somente um AuditEvent.
- [x] Unassign representa devolucao para fila.
- [x] Unassign nao recebe `target_agent_id`.
- [x] Unassign nao implementa transferencia.
- [x] Nenhum Channel e alterado.
- [x] Nenhum broadcast e implementado.
- [x] Nenhum frontend e alterado.
- [x] Testes focados passam.
- [x] `mix format --check-formatted` passa.
- [x] `mix test` passa.
- [x] `mix precommit` passa.
- [x] `git diff --check` dos arquivos da story passa.

## Tasks

- [x] Ler `assign_agent/2`.
- [x] Ler `resolve/2`.
- [x] Ler `reopen/2`.
- [x] Ler helpers de membership existentes.
- [x] Ler estrategia atual de `FOR UPDATE`.
- [x] Ler mecanismo injetavel de AuditEvent.
- [x] Escrever primeiro teste de `unassign/2`.
- [x] Confirmar RED.
- [x] Implementar `unassign/2`.
- [x] Integrar `Authorization.authorize/2`.
- [x] Integrar membership.
- [x] Recarregar Treatment sob `FOR UPDATE`.
- [x] Validar `status == "in_progress"`.
- [x] Validar ownership.
- [x] Implementar `in_progress -> open`.
- [x] Limpar `assigned_agent_id`.
- [x] Limpar `assigned_at`.
- [x] Criar `treatment_unassigned`.
- [x] Garantir atomicidade da auditoria.
- [x] Testar commercial.
- [x] Testar outro agente.
- [x] Testar ausencia de membership.
- [x] Testar estados invalidos.
- [x] Testar falha de auditoria.
- [x] Testar estado stale.
- [x] Testar concorrencia.
- [x] Testar `not_found`.
- [x] Revisar compatibilidade com transferencia futura.
- [x] Refatorar mantendo testes verdes.
- [x] Executar testes focados.
- [x] Executar `mix format --check-formatted`.
- [x] Executar `mix test`.
- [x] Executar `mix precommit`.
- [x] Executar `git diff --check`.
- [x] Marcar story como delivered.
- [x] Aguardar revisao humana antes de accepted.

## Fora do escopo

Nao implementar nesta story:

- `treatment:unassign` no Channel;
- `treatment:unassigned` broadcast;
- `transfer_agent/3`;
- `treatment:transfer`;
- `treatment:transferred`;
- selecao de agente destino;
- frontend;
- Carbon AI Chat;
- Presence.

## Stories seguintes

1. Expor liberacao da Tratativa via Phoenix Channel.
2. Publicar liberacao da Tratativa em realtime.
3. Permitir transferir Tratativa diretamente para outro agente.
4. Expor transferencia via Phoenix Channel.
5. Publicar transferencia da Tratativa em realtime.
6. Integrar lifecycle da Tratativa no frontend.

## Comments
@JuruSysadmin 2026-08-21
Plano: escrever primeiro o teste de sucesso para `Treatments.unassign/2`, confirmar RED por função inexistente, implementar com membership, autorização, lock, ownership, transição atômica e auditoria, e então completar a matriz de rejeições, rollback, stale state e concorrência.

@JuruSysadmin 2026-08-21
Implementação concluída com TDD. RED observado por `UndefinedFunctionError` de `Treatments.unassign/2`; GREEN após adicionar a operação de domínio. A operação valida role e membership, recarrega a Treatment autorizada sob `FOR UPDATE`, valida ownership/status, limpa assignment e grava `treatment_unassigned` atomicamente. Cobertos commercial, outro agent, fora da Room, estados inválidos, rollback de auditoria, stale state, concorrência e not_found. Verificação: 49 testes focados, 516 testes em `mix test`, `mix precommit`, format check e diff check passaram.

## Attachments
