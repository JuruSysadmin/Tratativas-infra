---
title: Publicar transferencia da Tratativa em realtime
type: feature
estimate: 2
tags: [backend, elixir, phoenix, channels, treatments, realtime, tdd]
created: "2026-08-21T20:21:30Z"
modified: "2026-08-21T20:25:45Z"
author: JuruSysadmin
status: delivered
started: "2026-08-21T20:22:02Z"
finished: "2026-08-21T20:25:29Z"
delivered: "2026-08-21T20:25:29Z"
---

## Problem statement

Como participante de uma Room, quero receber em tempo real quando uma Tratativa for transferida de um agente para outro, para que todos os clientes conectados atualizem imediatamente o responsável pelo atendimento.

O comando `treatment:transfer` já delega para `Treatments.transfer_agent_for_room/3`, que confirma uma transferência efetiva com `{:ok, treatment, :transferred}`. Esta story publica `treatment:transferred` somente quando esse marcador retornado pelo domínio confirma a transição persistida.

## Acceptance

- [ ] Publicar `treatment:transferred` somente para `{:ok, treatment, :transferred}`.
- [ ] Publicar depois do sucesso do domínio e nunca dentro da transação.
- [ ] Publicar para todos os participantes de `room:<room_id>`.
- [ ] Payload vem exclusivamente da Treatment retornada pelo domínio e contém `treatment_id`, `status`, `assigned_agent_id` e `assigned_at`.
- [ ] Campos enviados pelo cliente não controlam o payload.
- [ ] Erros, retries/idempotência, estado stale e falhas de auditoria não geram broadcast.
- [ ] Concorrência gera uma única transição, AuditEvent e publicação.
- [ ] Reply e evento representam o mesmo estado persistido.
- [ ] Nenhuma regra de domínio, acesso direto ao Repo, frontend ou Presence é alterado.
- [ ] Testes focados, `mix format --check-formatted`, `mix test`, `mix precommit` e `git diff --check` passam.

## Tasks

- [x] Ler implementação atual de `treatment:transfer` e broadcasts de outros comandos.
- [x] Escrever teste RED para `treatment:transferred` e confirmar a falha esperada.
- [x] Publicar somente no resultado `:transferred`, reutilizando o payload retornado.
- [x] Testar payload, múltiplos participantes e consistência entre reply/evento.
- [x] Testar campos maliciosos do cliente e todos os erros sem broadcast.
- [x] Testar estado stale, concorrência e atomicidade com auditoria.
- [x] Refatorar mantendo os testes verdes.
- [ ] Executar testes focados, format check, `mix test`, `mix precommit` e `git diff --check`.
- [x] Marcar story como delivered e aguardar revisão humana.

## Fora do escopo

Não implementar novas regras de transferência, mudanças no domínio sem necessidade, frontend, auto-membership ou Presence.

## Comments
@user 2026-08-21
Implementado o broadcast pós-domínio para treatment:transferred, com payload da Treatment retornada. RED confirmado no teste do Channel antes da implementação; GREEN com 46 testes focados e 537 testes totais. mix format --check-formatted e mix precommit passaram. O git diff --check global permanece bloqueado por linha em branco extra preexistente em tratativas-infra/_icebox.md, alteração não relacionada preservada; o diff dos arquivos desta story passou.

## Attachments
