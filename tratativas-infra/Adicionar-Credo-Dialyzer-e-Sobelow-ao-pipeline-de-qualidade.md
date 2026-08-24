---
title: Adicionar Credo, Dialyzer e Sobelow ao pipeline de qualidade
type: chore
created: "2026-08-24T15:10:21Z"
modified: "2026-08-24T15:15:06Z"
author: JuruSysadmin
status: delivered
started: "2026-08-24T15:10:43Z"
finished: "2026-08-24T15:15:06Z"
delivered: "2026-08-24T15:15:06Z"
---

## Problem statement

## Possible solution

## Comments
@JuruSysadmin 2026-08-24
Implementado em mix.exs: Dialyxir ~> 1.4, Sobelow ~> 0.15 e alias quality integrado ao precommit; mix.lock atualizado. Validação: mix deps.get e mix compile --warnings-as-errors passaram; mix test --no-start passou com 609 testes. mix format --check-formatted falhou apenas por arquivo preexistente test/chat_web/channels/room_channel_authorization_test.exs. Credo encontrou 2 achados preexistentes; Sobelow encontrou CSP ausente em lib/chat_web/router.ex; Dialyzer terminou com 6 warnings, principalmente incompatibilidades de opacidade em Ecto.Multi nos módulos existentes.

## Attachments

## Tasks

- [x] Adicionar Dialyxir e Sobelow em mix.exs, atualizar mix.lock e manter o Credo existente integrado ao pipeline.

- [x] Configurar aliases de qualidade para executar Credo, Dialyzer e Sobelow de forma reproduzível.

- [x] Executar testes e validações das três ferramentas, registrando limitações ou achados preexistentes.
