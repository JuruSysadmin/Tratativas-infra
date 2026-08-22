---
title: Estabilizar contrato realtime de resolução e reabertura da Tratativa
type: feature
created: "2026-08-22T13:35:22Z"
modified: "2026-08-22T16:11:47Z"
author: JuruSysadmin
status: accepted
estimate: "3"
tags: [backend, elixir, phoenix, channels, treatments, realtime, tdd]
started: "2026-08-22T16:11:47Z"
finished: "2026-08-22T16:11:47Z"
delivered: "2026-08-22T16:11:47Z"
accepted: "2026-08-22T16:11:47Z"
---

## Problem statement

Como cliente realtime de uma sala de Tratativa, quero receber uma projeção completa e persistida após resolver ou reabrir, para atualizar o estado local sem manter campos de resolução obsoletos nem reconstruir regras do domínio.

Hoje `treatment:resolved` publica os campos de resolução e assignment, mas `treatment:reopened` usa o payload de assignment e não publica explicitamente `resolved_by_id: nil` e `resolved_at: nil`. Os testes frontend simulam esses campos, embora eles não façam parte do evento real. Após uma reabertura, um cliente pode mudar para `in_progress` e ainda conservar metadados da resolução anterior.

## Contract

Os replies e broadcasts de `treatment:resolve` e `treatment:reopen` devem ser construídos exclusivamente a partir da Treatment retornada pela operação persistida e devem preservar os campos públicos existentes.

A projeção de estado para resolução e reabertura deve incluir:

- `treatment_id`;
- `status`;
- `assigned_agent_id`;
- `assigned_agent_username`;
- `assigned_at`;
- `resolved_by_id`;
- `resolved_at`.

Em `treatment:resolved`, `resolved_by_id` e `resolved_at` devem conter os valores persistidos. Em `treatment:reopened`, ambos devem ser publicados como `nil`, enquanto assignment e responsável permanecem preservados.

A alteração é aditiva. Não deve remover nem renomear campos já consumidos pelo frontend.

O frontend pode continuar limpando semanticamente `resolved_by_id` e `resolved_at` ao consumir `treatment:reopened` como compatibilidade defensiva. Assim, cada aplicação permanece correta durante uma implantação independente e o frontend não fica dependente da ordem de publicação entre backend e frontend.

## Acceptance

- [x] `treatment:resolved` mantém payload completo derivado da Treatment persistida.
- [x] `treatment:reopened` publica explicitamente `resolved_by_id: nil` e `resolved_at: nil`.
- [x] Assignment, nome persistido do responsável e `assigned_at` permanecem preservados após resolve e reopen.
- [x] Reply e broadcast de cada comando usam a mesma projeção pós-transação.
- [x] A implementação reutiliza um helper de payload coerente, sem duplicar a matriz de estado entre resolve, reopen e snapshot.
- [x] Retry, `forbidden`, `not_found`, `not_assigned_agent`, `invalid_status` e resultado inesperado não publicam eventos.
- [x] Nenhum campo enviado pelo cliente controla identidade, status ou timestamps.
- [x] Nenhuma alteração nas regras de autorização, ownership, membership, lock, auditoria ou transações já existentes.
- [x] A alteração do contrato realtime é aditiva e backward-compatible: `treatment:reopened` passa a incluir `resolved_by_id` e `resolved_at`; nenhum campo realtime existente é removido ou renomeado.
- [x] Testes focados, `mix format --check-formatted`, `mix precommit` e `git diff --check` passam.
- [x] Story é entregue para revisão humana e não aceita automaticamente.

## Tasks

- [x] Confirmar o payload real de join, reply, `treatment:resolved` e `treatment:reopened`.
- [x] Escrever teste RED com o payload real de reabertura sem os campos de resolução limpos.
- [x] Consolidar a projeção pública completa da Treatment no helper apropriado.
- [x] Publicar os campos de resolução persistidos em resolve e explicitamente nulos em reopen.
- [x] Garantir igualdade entre payload de reply e payload de broadcast.
- [x] Preservar os testes de cardinalidade: uma transição efetiva produz um broadcast e retries/erros produzem zero.
- [x] Executar testes focados do `RoomChannel`.
- [x] Executar `mix format --check-formatted`, `mix precommit` e `git diff --check`.
- [x] Registrar evidências e marcar a story como delivered para revisão humana.

## Out of scope

- Novas transições de lifecycle.
- Mudança da matriz de permissões.
- Alterações no frontend.
- Optimistic update.
- Presence, notificações externas, outbox ou persistência de eventos Phoenix.
- Migration ou alteração de schema Ecto/banco.
- Alteração do contrato das mensagens de chat fora dos eventos de Treatment explicitamente descritos nesta story.

## Possible solution

Evoluir o helper compartilhado de estado da Treatment para aceitar a projeção completa e usá-lo nos replies, broadcasts e snapshot aplicáveis. O `RoomChannel` continua fino: delega ao domínio, usa somente o resultado pós-transação e publica apenas quando recebe o marcador explícito `:resolved` ou `:reopened`.

## Comments

@JuruSysadmin 2026-08-22
Story criada a partir da revisão do contrato vertical Resolver/Reabrir. O domínio, os comandos e os broadcasts já existem; o valor desta story é remover o drift entre payload backend real e projeção esperada pelo frontend, sem reimplementar autorização ou transições.

Decisão arquitetural: a estimativa é de 3 pontos porque o domínio já existe e o trabalho está concentrado na correção e consolidação do contrato do `RoomChannel`. A limpeza defensiva de `resolved_*` no frontend permanece válida durante o rollout independente das aplicações.

@Antigravity 2026-08-22
Story implementada e entregue para revisão humana:
- `ChatWeb.RoomChannel`: consolidou a projeção pública de Treatment em `treatment_lifecycle_payload/1`, reutilizado em `treatment:resolve`, `treatment:reopen` e no snapshot de join do canal (`treatment_snapshot_payload/1`).
- `treatment:reopened`: agora publica explicitamente `resolved_by_id: nil` e `resolved_at: nil` em paridade exata entre reply e broadcast.
- `treatment:resolved`: mantém payload completo derivado da Treatment persistida (`resolved_by_id`, `resolved_at`, `assigned_agent_id`, `assigned_agent_username`, `assigned_at`).
- Validação estrita de `assert reply_payload == broadcast_payload` e snapshot de canal em `test/chat_web/channels/room_channel_authorization_test.exs`.
- Precommit executado com sucesso: 543 testes passando (100%), Credo sem issues (strict), formatação limpa e `git diff --check` sem avisos.

## Attachments
