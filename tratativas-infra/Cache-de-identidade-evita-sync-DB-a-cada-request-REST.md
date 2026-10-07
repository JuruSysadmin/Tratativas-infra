---
title: Cache de identidade evita sync DB a cada request REST
type: chore
created: "2026-10-07T19:22:46Z"
modified: "2026-10-07T19:23:53Z"
author: JuruSysadmin
status: accepted
started: "2026-10-07T19:22:46Z"
finished: "2026-10-07T19:23:53Z"
delivered: "2026-10-07T19:23:53Z"
accepted: "2026-10-07T19:23:53Z"
---

## Problem statement
`Chat.Auth.Authenticator` chama `Identity.sync_user` → `Accounts.find_or_create_external_user/1` em **toda** request autenticada (incl. mensagens), pagando SELECT (~40–300ms com Postgres remoto) mesmo quando o perfil não mudou.

## Possible solution
1. Cache ETS `{auth_provider, auth_subject}` → user + fingerprint dos claims, TTL (~60s).
2. JWT continua validado a cada request; só o sync de usuário é cacheado.
3. Miss / fingerprint diferente / TTL → sync DB como hoje e repõe o cache.

## Acceptance
- Segunda auth com mesmos claims não hit o Repo (ou só após TTL).
- Mudança relevante de claims (email/username/…) invalida via fingerprint e re-sync.
- Testes Identity/Authenticator cobrem hit/miss.
- JWT inválido continua 401.

## Tasks
- [x] IdentityCache ETS + supervisão
- [x] Identity.sync_user usa cache
- [x] Testes + deliver

## Comments

@JuruSysadmin 2026-10-07
Smoke MIX_ENV=dev: 1o sync cria user (~4 queries); 2o sync same claims = 0ms, zero SQL. JWT segue validado no Authenticator.
