---
title: Expor Assumir Tratativa via Phoenix Channel
type: feature
created: "2026-08-21T01:23:50Z"
modified: "2026-08-21T03:25:38Z"
author: JuruSysadmin
status: delivered
started: "2026-08-21T01:27:12Z"
finished: "2026-08-21T03:25:38Z"
delivered: "2026-08-21T03:25:38Z"
---

# Expor Assumir Tratativa via Phoenix Channel

**Type:** Feature
**Estimate:** 2
**Labels:** `backend`, `elixir`, `phoenix`, `channels`, `treatments`, `tdd`

## Problem statement

Como agente da logística conectado à sala de uma Tratativa, quero assumir o atendimento através do Phoenix Channel para que o frontend possa iniciar a atribuição em tempo real.

A regra de negócio já existe em `Chat.Treatments.assign_agent/2`. O Channel deve identificar o usuário autenticado pelo socket, localizar a Treatment da sala, chamar `Treatments.assign_agent/2` e traduzir o resultado para replies estáveis. Não duplicar autorização, concorrência ou atribuição.

## Contract

No tópico `room:<room_id>`, aceitar o evento `treatment:assign_to_me` com payload `{}`. A identidade deve vir exclusivamente de `socket.assigns.current_user`; não aceitar `agent_id`, `assigned_agent_id` ou `assigned_at` como fonte de atribuição.

Sucesso deve retornar payload com `treatment_id`, `assigned_agent_id` e `assigned_at`. Mapear erros para replies estáveis compatíveis com `RoomChannel`: `forbidden`, `already_assigned` e `not_found`.

## TDD

Começar pelos testes de Channel antes de adicionar `handle_in/3`:

- TDD-01: `logistics_agent` assume pela sala e a atribuição é persistida.
- TDD-02: `commercial` recebe `forbidden` e não altera a Treatment.
- TDD-03: outro agente recebe `already_assigned` e não substitui o atual.
- TDD-04: retry do mesmo agente retorna sucesso e preserva `assigned_at`.
- TDD-05: campos `agent_id`/`assigned_agent_id` enviados pelo cliente não controlam identidade.
- TDD-06: `assigned_at` enviado pelo cliente é ignorado ou rejeitado conforme padrão do Channel; nunca é persistido.
- TDD-07: sala sem Treatment retorna `not_found` sem exception. Se a invariável do domínio impedir essa situação, documentar e adaptar o teste.

## Acceptance

* [x] Desenvolvimento iniciado com TDD.
* [x] RED observado antes de `handle_in/3`.
* [x] `RoomChannel` aceita `treatment:assign_to_me`.
* [x] O agente vem exclusivamente de `socket.assigns.current_user`.
* [x] O Channel encontra a Treatment correspondente à sala.
* [x] O Channel chama `Chat.Treatments.assign_agent/2`.
* [x] Nenhuma regra de role ou concorrência é duplicada no Channel.
* [x] `logistics_agent` consegue assumir uma Treatment livre.
* [x] `commercial` recebe `forbidden`.
* [x] Outro agente recebe `already_assigned`.
* [x] Retry do mesmo agente permanece idempotente.
* [x] `assigned_at` continua controlado pelo backend.
* [x] Dados enviados pelo cliente não selecionam outro agente nem timestamp.
* [x] `not_found` é tratado sem crash.
* [x] Falhas não modificam a atribuição existente.
* [x] Não há broadcast, Presence ou frontend nesta story.
* [x] Testes focados passam.
* [x] `mix format --check-formatted` passa.
* [x] `mix test` passa.
* [x] `mix precommit` passa.
* [x] `git diff --check` passa para o diff da story; o check global mantém apenas a linha em branco preexistente documentada em `tratativas-infra/_icebox.md`.

## Tasks

* [x] Ler `RoomChannel` e testes atuais do Channel.
* [x] Identificar relação entre `room_id` e Treatment.
* [x] Identificar padrão atual de replies `ok/error`.
* [x] Escrever TDD-01.
* [x] Executar e confirmar RED.
* [x] Implementar `handle_in("treatment:assign_to_me", ...)` mínimo.
* [x] Obter agente via `socket.assigns.current_user`.
* [x] Obter Treatment correspondente à Room.
* [x] Chamar `Treatments.assign_agent/2`.
* [x] Mapear sucesso para reply.
* [x] Escrever testes de `forbidden`, `already_assigned` e retry idempotente.
* [x] Escrever testes contra `agent_id` e `assigned_at` enviados pelo cliente.
* [x] Cobrir `not_found`.
* [x] Refatorar mantendo testes verdes.
* [x] Executar testes focados.
* [x] Executar `mix format --check-formatted`.
* [x] Executar `mix test`.
* [x] Executar `mix precommit`.
* [x] Executar `git diff --check` (diff focado passa; verificação global é bloqueada por linha em branco preexistente em `tratativas-infra/_icebox.md`).
* [x] Marcar como `delivered` e aguardar revisão humana antes de `accepted`.

- [x] Revisão manual: reforçar o teste de sala sem Treatment para monitorar o processo do Channel e confirmar que o reply `not_found` não encerra o Channel.
- [x] Adicionar teste RED para auditoria treatment_assigned após nova atribuição.
- [x] Adicionar teste RED para auditoria treatment_resolved e preservar assignment.
- [x] Cobrir resposta estável para erro inesperado do domínio no Channel.
- [x] Mover busca da Treatment e atribuição para Chat.Treatments.
- [x] Tornar o handler treatment:assign_to_me exaustivo.
- [x] Revalidar membership durante treatment:assign_to_me mantendo a membership bloqueada na operação.
- [x] Testar socket existente após revogação de membership.
## Fora do escopo

```text
treatment:agent_joined
broadcast realtime
Phoenix Presence para atribuição
open -> in_progress
resolve
reopen
unassign
transfer
frontend
Carbon AI Chat
```

## Próxima story

Publicar a atribuição do agente em realtime somente depois que `assign_agent/2` retornar sucesso.

## Comments

@JuruSysadmin 2026-08-21
Decisão do PM: `room:<room_id>` pode representar uma sala genérica sem Treatment. O Channel deve buscar a Treatment por `room_id` e retornar um erro estável com `reason: "not_found"`, sem exception. O teste de sala sem Treatment é obrigatório. `Chat.Treatments.assign_agent/2` continua retornando `:not_found` quando a Treatment persistida não existe.

@JuruSysadmin 2026-08-21
Implementação concluída na branch `feat/expose-treatment-assignment-channel`: `RoomChannel` aceita `treatment:assign_to_me`, busca Treatment por `room_id`, usa `socket.assigns.current_user`, delega para `Treatments.assign_agent/2` e mapeia sucesso/erros para replies estáveis. Payloads com `agent_id`, `assigned_agent_id` e `assigned_at` não controlam a atribuição. Sala sem Treatment retorna `not_found` sem exception. TDD-01 RED observado por ausência do handler. Testes do Channel: 15 passaram; `mix format --check-formatted`, `mix test` (462 testes) e `mix precommit` passaram. `git diff --check` do diff da story passa; o check global permanece bloqueado por linha em branco preexistente em `tratativas-infra/_icebox.md`.

@JuruSysadmin 2026-08-21
Revisão manual concluída: `logistics_agent + Treatment livre` retorna sucesso; `commercial` retorna `forbidden`; Treatment já atribuída a outro agente retorna `already_assigned`; sala sem Treatment retorna `not_found` e o teste monitora o processo para confirmar que o Channel continua vivo. Verificação após o ajuste: 15 testes do Channel passaram, `mix format --check-formatted`, `mix precommit` e diff focado passaram. A suíte completa no precommit passou com 462 testes; warnings de broadcast e ExAws metadata não causaram falha.

@JuruSysadmin 2026-08-21
Aceite humano confirmado pelo PM após revisão manual dos contratos: `ok`, `forbidden`, `already_assigned` e `not_found` com Channel vivo. Acceptance Criteria encerrados. O check global de diff mantém a ressalva já registrada para linha em branco preexistente em `_icebox.md`; o diff da story passa.

@JuruSysadmin 2026-08-21
Revisão tratada: RoomChannel agora chama Chat.Treatments.assign_agent_for_room/2, não acessa Repo/Treatment diretamente, diferencia atribuição nova de retry idempotente e possui fallback para erros inesperados. Atribuição e resolução gravam treatment_assigned/treatment_resolved na auditoria dentro da transação; retry não duplica evento. Verificação: 42 testes focados, precommit com 473 testes, Credo sem issues e diff focado limpo.

@JuruSysadmin 2026-08-21
Revisão adicional tratada: assign_agent_for_room/2 agora executa sob Rooms.with_member_room/3, revalidando e mantendo a membership bloqueada durante a atribuição. Socket já conectado após revogação recebe forbidden e não altera a Treatment. O handler mantém fallback para retorno inesperado. Verificação atual: 43 testes focados, precommit com 474 testes e Credo sem issues.
