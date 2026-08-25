---
title: Corrigir alias de módulo aninhado em Chat.Treatments
type: chore
created: "2026-08-24T15:54:27Z"
modified: "2026-08-24T15:55:18Z"
author: JuruSysadmin
status: delivered
started: "2026-08-24T15:54:35Z"
finished: "2026-08-24T15:55:18Z"
delivered: "2026-08-24T15:55:18Z"
---

## Problem statement

## Possible solution

## Comments
@JuruSysadmin 2026-08-24
Adicionado alias Chat.Orders.Mock em lib/chat/treatments.ex e substituída apenas a referência em get_preview/2. Validação: mix test test/chat/treatments_test.exs --no-start passou com 81 testes; Credo não reporta mais Nested modules em Chat.Treatments e mantém apenas o aviso preexistente de with em treatment_preview_controller.ex; mix format --check-formatted falha somente em test/chat_web/channels/room_channel_authorization_test.exs, fora do escopo; git diff --check passou.

## Attachments

## Tasks

- [x] Adicionar alias para Chat.Orders.Mock no topo de Chat.Treatments e substituir a referência completa em get_preview.

- [x] Executar os testes existentes de Chat.Treatments sem alterar a lógica do preview.

- [x] Executar mix format --check-formatted, mix credo e git diff --check; registrar achados não relacionados.
