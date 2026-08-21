---
title: Permitir resolver Tratativa
type: feature
estimate: 3
tags: [backend, elixir, treatments, lifecycle, authorization, database, tdd]
created: "2026-08-21T02:36:06Z"
modified: "2026-08-21T03:18:48Z"
author: JuruSysadmin
status: delivered
started: "2026-08-21T02:40:20Z"
finished: "2026-08-21T02:49:13Z"
delivered: "2026-08-21T02:49:13Z"
---

# Permitir resolver Tratativa

## Problem statement

Como agente autorizado da logística, quero resolver uma Tratativa em atendimento para registrar que o trabalho foi concluído sem ainda realizar o fechamento definitivo.

Esta story implementa a transição:

```text
in_progress
  ↓ resolve
resolved
```

A resolução deve registrar quem executou a ação e quando ela ocorreu, usando exclusivamente o usuário autenticado recebido pelo domínio.

## Contract

### Operação `Chat.Treatments.resolve/2`

```text
in_progress + usuário autorizado + assigned_agent_id == user.id
  → status = resolved
  → resolved_by_id = usuário autenticado
  → resolved_at = DateTime.utc_now()
  → {:ok, treatment}

in_progress + usuário autorizado + assigned_agent_id != user.id
  → {:error, :not_assigned_agent}

in_progress + usuário sem autorização
  → {:error, :forbidden}

open + qualquer usuário autorizado
  → {:error, :invalid_status}

resolved/closed + qualquer usuário autorizado
  → {:error, :invalid_status}
```

- A autorização deve consultar `Chat.Treatments.Authorization` com `treatment.resolve` antes da transação.
- O domínio deve buscar a Treatment persistida com lock `FOR UPDATE`.
- A autorização de papel e a autorização de ownership são regras distintas: `treatment.resolve` confirma que o papel pode resolver; `assigned_agent_id == user.id` confirma que o agente autenticado é o responsável daquela Treatment.
- O teste de ownership deve ocorrer depois da aquisição do lock e antes da atualização.
- `resolved_by_id` deve referenciar `users.id`.
- A FK de `resolved_by_id` usa `on_delete: :restrict` para preservar a integridade da auditoria; um usuário que resolveu Tratativas não pode ser excluído sem uma política explícita de retenção.
- `resolved_at` deve ser `:utc_datetime_usec`.
- O domínio deve usar o usuário autenticado; não aceitar `resolved_by_id` ou `resolved_at` fornecidos pelo cliente.
- Retry em uma Treatment já `resolved` retorna `{:error, :invalid_status}`; não há reabertura nem nova alteração de `resolved_at`.
- Em uma corrida entre duas resoluções, a primeira transação que adquirir o lock resolve a Treatment; a segunda, após adquirir o lock, encontra `resolved` e retorna `{:error, :invalid_status}`.
- `closed` e a transição `resolved → closed` permanecem fora do escopo; serão tratados por story própria.
- Não implementar Channel, frontend ou broadcast nesta story.

## TDD

O ciclo deve começar por um teste de domínio que falha porque `resolve/2` ainda não existe ou não altera o estado correto.

Casos obrigatórios:

- agente autorizado resolve uma Treatment `in_progress`;
- agente autorizado, mas não atribuído à Treatment, recebe `:not_assigned_agent`;
- `resolved_by_id` usa o usuário autenticado;
- `resolved_at` é gerado pelo backend;
- o timestamp é persistido;
- usuário sem `treatment.resolve` recebe `:forbidden`;
- Treatment `open` não pode ser resolvida;
- Treatment `resolved` retorna `:invalid_status` em nova tentativa;
- Treatment `closed` não pode ser resolvida;
- campos de identidade e timestamp não podem ser controlados por entrada externa;
- estado persistido permanece inalterado em falhas de autorização ou estado;
- associação `resolved_by` pode ser preloaded;
- concorrência não permite duas resoluções inconsistentes.
- na resolução bem-sucedida, `assigned_agent_id` e `assigned_at` permanecem inalterados;

## Acceptance

* [x] Story iniciada com TDD.
* [x] `resolved_by_id` e `resolved_at` adicionados por migration forward-only.
* [x] Treatment aceita o estado `resolved`.
* [x] Associação `resolved_by` adicionada ao schema.
* [x] `Chat.Treatments.resolve/2` existe e usa o usuário autenticado.
* [x] Autorização usa `treatment.resolve` sem duplicar a matriz de permissões.
* [x] Somente o agente em `assigned_agent_id` pode resolver a Treatment.
* [x] `in_progress` pode transicionar para `resolved`.
* [x] `resolved_by_id` é persistido corretamente.
* [x] `resolved_at` é gerado e persistido pelo backend.
* [x] `open`, `resolved` e `closed` não são resolvidos implicitamente.
* [x] Falhas não alteram a Treatment.
* [x] `resolved_by` pode ser preloaded.
* [x] Concorrência é coberta por teste.
* [x] `resolve` não altera `assigned_agent_id` nem `assigned_at`.
* [x] Em corrida, a primeira resolução vence e a segunda retorna `:invalid_status` após o lock.
* [x] Não há Channel, frontend ou broadcast nesta story.
* [x] `mix format --check-formatted` passa.
* [x] `mix test` passa.
* [x] `mix precommit` passa.
* [x] `git diff --check` do escopo passa.
* [x] Story entregue para revisão humana.

## Tasks

* [x] Ler `Treatment`, `Chat.Treatments`, `Authorization`, migrations e testes atuais.
* [x] Definir a política de retry para uma Treatment já `resolved`.
* [x] Confirmar a matriz de autorização para `treatment.resolve`.
* [x] Definir que somente `assigned_agent_id == user.id` pode resolver.
* [x] Escrever RED para `in_progress` → `resolved`.
* [x] Executar o teste e confirmar a falha esperada.
* [x] Gerar migration com `mix ecto.gen.migration add_resolution_fields_to_treatments`.
* [x] Adicionar `resolved_by_id` e `resolved_at` com tipos e FK compatíveis.
* [x] Atualizar schema, associação e validação de status.
* [x] Implementar `resolve/2` com autorização antes do lock.
* [x] Implementar lock e transição atômica.
* [x] Testar persistência de `resolved_by_id` e `resolved_at`.
* [x] Testar autorização negada.
* [x] Testar agente autorizado, mas não atribuído, com `:not_assigned_agent`.
* [x] Testar estados inválidos.
* [x] Testar proteção contra identidade e timestamp externos.
* [x] Testar preload de `resolved_by`.
* [x] Testar concorrência.
* [x] Confirmar que atribuição e timestamp de assignment permanecem inalterados.
* [x] Confirmar que a primeira resolução vence a corrida e a segunda retorna `:invalid_status` após o lock.
* [x] Refatorar mantendo os testes verdes.
* [x] Executar testes focados.
* [x] Executar `mix format --check-formatted`.
* [x] Executar `mix test`.
* [x] Executar `mix precommit`.
* [x] Executar `git diff --check` focado.
* [x] Marcar a story como `delivered` e aguardar aceite humano.

## Fora do escopo

```text
resolved → closed
reopen
unassign
transfer
Phoenix Channel
frontend
broadcast
Presence
```

## Próxima story

Implementar o fechamento definitivo `resolved → closed`.

## Comments

@JuruSysadmin 2026-08-21
Story criada como próxima etapa do lifecycle. O contrato confirma `in_progress → resolved` com `resolved_by_id`, `resolved_at`, autorização centralizada e TDD. Nova tentativa em `resolved` retorna `:invalid_status`; não há reabertura implícita.

@JuruSysadmin 2026-08-21
Feedback incorporado: além de `treatment.resolve`, a operação exige `assigned_agent_id == user.id`. Agente autorizado, mas não atribuído, recebe `:not_assigned_agent`. Ownership é verificado depois do lock; em corrida, a primeira resolução vence e a segunda encontra `resolved` e retorna `:invalid_status`. Os testes devem confirmar que `assigned_agent_id` e `assigned_at` permanecem inalterados.

@JuruSysadmin 2026-08-21
Implementação concluída: migration adiciona resolved_by_id, resolved_at e índice; Treatment expõe resolved_by e aceita status resolved; Chat.Treatments.resolve/2 autoriza treatment.resolve antes da transação, bloqueia a linha com FOR UPDATE, exige assigned_agent_id == user.id e atualiza status/resolved_by/resolved_at atomicamente. Agente autorizado não atribuído retorna not_assigned_agent; estados open/resolved/closed retornam invalid_status; corrida permite uma resolução e retorna invalid_status para a segunda; assigned_agent_id e assigned_at permanecem inalterados. RED observado no teste inicial; 26 testes focados passaram; mix format --check-formatted, mix precommit (472 testes) e git diff --check focado passaram. Warnings existentes de PubSub/broadcast não causaram falha.

@JuruSysadmin 2026-08-21
Revisão independente tratou o risco da migration: `change/0` foi substituído por `up/0` e `down/0` irreversível para impedir remoção acidental do histórico de resolução. O uso de `on_delete: :restrict` foi documentado como política de retenção de auditoria. Após o ajuste: 42 testes focados, precommit com 473 testes, Credo sem issues e diff staged limpo.

@JuruSysadmin 2026-08-21
Auditoria adicionada como parte da resolução: evento treatment_resolved é persistido na mesma transação que status, resolved_by_id e resolved_at, sem alterar assigned_agent_id ou assigned_at.

## Attachments
