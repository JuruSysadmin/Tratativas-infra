---
title: Permitir que agente assuma Tratativa
type: feature
created: "2026-08-21T00:59:00Z"
modified: "2026-08-21T01:12:14Z"
author: JuruSysadmin
status: delivered
started: "2026-08-21T01:06:28Z"
finished: "2026-08-21T01:12:14Z"
delivered: "2026-08-21T01:12:14Z"
---

# Permitir que agente assuma Tratativa

**Type:** Feature
**Labels:** `backend`, `elixir`, `treatments`, `authorization`, `tdd`
**Estimate:** 3

## Problem statement

Como agente da logística, quero assumir uma Tratativa disponível para me tornar o responsável pelo atendimento.

A operação deve usar o usuário autenticado recebido pelo domínio e nunca aceitar um `assigned_agent_id` arbitrário vindo do cliente.

Esta story implementa a regra de domínio de atribuição. A integração com Phoenix Channel, broadcast realtime, Presence e frontend ficam fora do escopo.

## Dependências

Depende de:

* `[Feature] Adicionar papel ao usuário`
* `[Feature] Centralizar autorização de Tratativas`
* `[Feature] Adicionar agente responsável à Tratativa`

Já existem `User.role`, `Authorization.authorize/2`, `Treatment.assigned_agent_id`, `Treatment.assigned_at` e `Treatment.assignment_changeset/2`.

## Estratégia TDD

Implementar em ciclos RED → GREEN → REFACTOR. O primeiro RED deve falhar porque `Chat.Treatments.assign_agent/2` ainda não existe.

## API de domínio

Adicionar em `Chat.Treatments`:

```elixir
assign_agent(%Treatment{} = treatment, %User{} = user)
```

Retornos esperados:

```elixir
{:ok, treatment}
{:error, :forbidden}
{:error, :already_assigned}
```

A API não deve aceitar `agent_id`, atributos livres ou timestamp vindo do cliente. `assigned_at` deve ser criado pelo backend.

## Regras de domínio

1. `logistics_agent` pode assumir uma Treatment sem agente.
2. A operação deve reutilizar `Authorization.authorize(user, "treatment.assign")` e não duplicar regras por `user.role`.
3. `commercial` recebe `{:error, :forbidden}` sem alterar a persistência.
4. Outro agente não pode substituir o agente atual; retornar `{:error, :already_assigned}`.
5. Repetir a operação com o mesmo agente é idempotente e preserva `assigned_at`.
6. A decisão usa o estado persistido atual, não apenas o struct stale recebido pelo caller.
7. A atribuição deve ser atomicamente segura contra concorrência: duas tentativas simultâneas resultam em um sucesso e um `:already_assigned`.
8. Falhas preservam `assigned_agent_id` e `assigned_at` anteriores.
9. Não adicionar autorização ao schema, Presence, Channel, broadcast ou frontend.

## Testes TDD

- TDD-01: agente logístico assume Treatment livre; observar RED por `assign_agent/2` inexistente.
- TDD-02: usuário commercial recebe `{:error, :forbidden}` e a Treatment permanece sem agente.
- TDD-03: implementação reutiliza `Authorization.authorize/2`; o teste funcional de commercial deve proteger esse comportamento sem mockar Authorization.
- TDD-04: agente diferente recebe `{:error, :already_assigned}` e não substitui o responsável.
- TDD-05: repetição pelo mesmo agente é idempotente e preserva `assigned_at`.
- TDD-06: `assigned_at` é definido pelo backend dentro de uma janela temporal razoável; a API não recebe timestamp.
- TDD-07: struct stale não permite sobrescrever atribuição persistida.
- TDD-08: duas tentativas concorrentes resultam em somente um sucesso e um agente persistido; documentar qualquer requisito do SQL sandbox.
- TDD-09: falhas `:forbidden` e `:already_assigned` preservam o estado anterior.

## Acceptance

* [x] Desenvolvimento começou com TDD.
* [x] RED foi observado para `assign_agent/2` inexistente.
* [x] `logistics_agent` pode assumir Treatment disponível.
* [x] `commercial` recebe `{:error, :forbidden}`.
* [x] `Authorization.authorize/2` é reutilizado sem duplicar regra de papel.
* [x] API recebe `%User{}` e não ID arbitrário.
* [x] `assigned_agent_id` usa o usuário da operação.
* [x] `assigned_at` é definido pelo backend.
* [x] Outro agente recebe `{:error, :already_assigned}`.
* [x] Mesmo agente é idempotente e preserva `assigned_at`.
* [x] Estado stale não sobrescreve atribuição persistida.
* [x] Concorrência permite somente um agente.
* [x] Falhas não alteram dados persistidos.
* [x] Não há lógica de Phoenix Presence, Channel, broadcast ou frontend.
* [x] Testes focados passam.
* [x] `mix format --check-formatted` passa.
* [x] `mix test` passa.
* [x] `mix precommit` passa.
* [ ] `git diff --check` passa.

## Tasks

* [x] Ler `Chat.Treatments`, `Treatment.assignment_changeset/2`, autorização e testes existentes.
* [x] Escrever TDD-01 para agente logístico e confirmar RED.
* [x] Implementar o contrato mínimo de `assign_agent/2`.
* [x] Escrever TDD-02 para commercial e integrar `Authorization.authorize/2`.
* [x] Escrever TDD-04 para agente diferente.
* [x] Definir e testar idempotência para o mesmo agente.
* [x] Garantir `assigned_at` criado pelo backend.
* [x] Escrever teste de estado stale.
* [x] Escolher estratégia atômica PostgreSQL/Ecto.
* [x] Escrever teste concorrente.
* [x] Implementar proteção de concorrência.
* [x] Garantir que falhas não alterem dados persistidos.
* [x] Refatorar mantendo testes verdes.
* [x] Executar testes focados.
* [x] Executar `mix format --check-formatted`.
* [x] Executar `mix test`.
* [x] Executar `mix precommit`.
* [ ] Executar `git diff --check` (bloqueado por linha em branco preexistente em `tratativas-infra/_icebox.md`; diff focado passa).
* [x] Revisar Acceptance Criteria.
* [ ] Marcar story como `delivered` e aguardar revisão humana antes de `accepted`.

## Fora do escopo

```text
treatment:assign_to_me
RoomChannel
treatment:agent_joined
broadcast realtime
status open → in_progress
resolve
reopen
unassign
transferência
frontend
Carbon AI Chat
```

## Próxima story

Expor “Assumir Tratativa” via Phoenix Channel, mapeando `socket.assigns.current_user` para `Treatments.assign_agent/2` sem aceitar `agent_id` do cliente.

## Comments

@JuruSysadmin 2026-08-21
Decisão do PM: usar `SELECT ... FOR UPDATE` dentro de `Repo.transaction/1`; executar `Authorization.authorize/2` antes do lock; preservar `assigned_at` em retries do mesmo agente; retornar `:already_assigned` para agente diferente e preferir `:not_found` quando a Treatment persistida não existir.

@JuruSysadmin 2026-08-21
Implementação concluída: `Chat.Treatments.assign_agent/2` autoriza antes do lock, usa `Repo.transaction/1` com `SELECT ... FOR UPDATE`, retorna `:not_found`, `:forbidden` e `:already_assigned`, preserva `assigned_at` em retry do mesmo agente e não aceita ID/timestamp arbitrários. Testes cobrem agente logístico, commercial, agente diferente, idempotência, estado stale, concorrência e falha not_found. Evidência: TDD-01 RED por função inexistente; 16 testes focados passaram; `mix format --check-formatted`, `mix test` (456 testes) e `mix precommit` passaram. `git diff --check` do diff da story passa; a verificação global é bloqueada por linha em branco preexistente em `tratativas-infra/_icebox.md`, não relacionada a esta story.
