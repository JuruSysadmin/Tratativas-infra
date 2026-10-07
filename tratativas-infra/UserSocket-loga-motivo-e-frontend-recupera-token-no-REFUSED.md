---
title: UserSocket loga motivo e frontend recupera token no REFUSED
type: chore
created: "2026-10-07T19:43:27Z"
modified: "2026-10-07T19:45:16Z"
author: JuruSysadmin
status: accepted
started: "2026-10-07T19:43:27Z"
finished: "2026-10-07T19:45:16Z"
delivered: "2026-10-07T19:45:16Z"
accepted: "2026-10-07T19:45:16Z"
---

## Problem statement
`REFUSED CONNECTION TO ChatWeb.UserSocket` sem motivo no log. Abas com JWT expirado/inválido reconectam em loop. Frontend não força refresh no erro do socket.

## Possible solution
1. Backend: logar `reason` em `UserSocket.connect/3` (sem token).
2. Frontend: no erro do socket compartilhado, `refreshAccessToken` + reconnect uma vez; se refresh falhar, deixar o fluxo de refresh failure existente.

## Acceptance
- Log mostra reason (`:token_expired`, `:invalid_token`, `:missing_token`, etc.).
- Socket tenta refresh+reconnect após recusa.
- Testes cobrindo log/reason e recovery do chatSocket.

## Tasks
- [x] UserSocket logging + teste
- [x] chatSocket auth recovery + teste
- [x] Deliver

## Comments

@JuruSysadmin 2026-10-07
Backend loga reason; frontend refresh+reconnect com cooldown 5s. Vitest chatSocket 5/5.
