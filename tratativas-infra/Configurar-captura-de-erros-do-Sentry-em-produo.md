---
title: Configurar captura de erros do Sentry em produção
type: chore
created: "2026-08-28T15:47:29Z"
modified: "2026-08-28T15:50:45Z"
author: JuruSysadmin
status: accepted
started: "2026-08-28T15:47:36Z"
finished: "2026-08-28T15:50:45Z"
delivered: "2026-08-28T15:50:45Z"
accepted: "2026-08-28T15:50:45Z"
---

## Problem statement

## Possible solution

## Comments

## Attachments

## Tasks

- [x] Configurar opções de produção do Sentry e ler o DSN por SENTRY_DSN no runtime.

- [x] Adicionar Sentry.PlugContext ao endpoint Phoenix e o handler de logger à aplicação.

- [x] Incluir mix sentry.package_source_code no fluxo de build da release.

- [x] Executar compilação, testes focados e mix precommit, registrando falhas preexistentes.
