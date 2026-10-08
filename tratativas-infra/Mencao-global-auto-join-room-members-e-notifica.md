---
title: Mencao global auto-join room_members e notifica
type: feature
created: "2026-10-08T13:48:39Z"
modified: "2026-10-08T13:52:22Z"
author: JuruSysadmin
status: delivered
estimate: "5"
started: "2026-10-08T13:48:39Z"
finished: "2026-10-08T13:52:22Z"
delivered: "2026-10-08T13:52:22Z"
---

## Summary

Permitir mencionar qualquer usuário resolvível por handle (não só membros da sala). Ao mencionar alguém que ainda não é membro, auto-join em `room_members` e disparar notificação como hoje.

## Acceptance criteria

- [ ] `mentionable_users_by_handle` resolve handles entre usuários mentionable do sistema (não só `room_members`).
- [ ] Ao persistir menções, usuários mencionados que não são membros são adicionados à sala (idempotente).
- [ ] Broadcast `mention:created` continua via `user:{id}` para os mencionados.
- [ ] `list_mention_notifications` / topbar funcionam para o mencionado após o auto-join (membership presente).
- [ ] Membros já existentes não são duplicados em `room_members`.
- [ ] Testes cobrem: menção a não-membro → vira membro + mention row; menção a membro → comportamento atual; handle inexistente → ignorado.

## Out of scope

- Frontend / Presence global (já feito).
- Nest / Java / auth.
- Mudar ACL de escrita além do auto-join na menção.

## Tasks

- [x] Resolver mentionable por username global

- [x] Auto-join room_members ao mencionar

- [x] Testes TDD menção não-membro
