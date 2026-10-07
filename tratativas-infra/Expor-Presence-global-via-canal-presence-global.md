---
title: Expor Presence global via canal presence:global
type: feature
created: "2026-10-07T21:57:07Z"
modified: "2026-10-07T21:59:40Z"
author: JuruSysadmin
status: delivered
estimate: "3"
started: "2026-10-07T21:57:25Z"
finished: "2026-10-07T21:59:40Z"
delivered: "2026-10-07T21:59:40Z"
---

## Summary

Expor Presence global de usuários autenticados no socket Phoenix via canal `presence:global`, para o frontend listar quem está online no app (não só em uma sala).

## Acceptance criteria

- [ ] `UserSocket` registra o canal `presence:global`.
- [ ] Qualquer usuário autenticado pode fazer join; sem token/usuário → join recusado como os demais canais.
- [ ] No join, o canal faz `Presence.track` com meta mínima: `id`, `username`, `joined_at` (sem typing).
- [ ] Após o join, o cliente recebe `presence_state` com o snapshot do tópico `presence:global`.
- [ ] Chave de Presence = `user_id` (string); múltiplas conexões do mesmo usuário acumulam metas.
- [ ] Presence de `room:*` permanece inalterada.
- [ ] Testes de canal cobrem join autenticado, presence_state e listagem online no tópico global.

## Out of scope

- Relaxar `mentionable_users_by_handle` / menções cross-room.
- Endpoint HTTP `/users/online`.
- Frontend / Nest / app Java.

## Tasks

- [x] Registrar canal presence:global no UserSocket

- [x] Implementar GlobalPresenceChannel com track + presence_state

- [x] Testes de join e Presence no tópico global
