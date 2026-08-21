---
title: Refatorar payload compartilhado de Tratativa
type: chore
estimate: 1
tags: [backend, elixir, phoenix, refactor, treatments]
created: "2026-08-21T20:35:25Z"
modified: "2026-08-21T20:46:14Z"
author: JuruSysadmin
status: accepted
started: "2026-08-21T20:45:21Z"
finished: "2026-08-21T20:46:14Z"
delivered: "2026-08-21T20:46:14Z"
accepted: "2026-08-21T20:46:14Z"
---

## Problem statement

As funções privadas de payload para reopen e transfer possuem implementação idêntica em `ChatWeb.RoomChannel`. Consolidar a representação compartilhada sem alterar os contratos dos eventos ou replies.

## Acceptance

- [ ] Existe uma única função privada para o payload de estado atribuído da Treatment.
- [ ] `treatment:reopened` e `treatment:transferred` mantêm o payload atual.
- [ ] Testes focados e `mix precommit` passam.
- [ ] Nenhuma alteração de domínio ou contrato público.

## Tasks

- [x] Extrair helper privado compartilhado.
- [x] Atualizar os dois handlers.
- [x] Executar testes focados e `mix precommit`.
- [ ] Entregar para revisão humana.

## Comments

## Attachments
