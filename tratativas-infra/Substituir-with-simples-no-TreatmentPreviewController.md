---
title: Substituir with simples no TreatmentPreviewController
type: chore
created: "2026-08-24T16:05:02Z"
modified: "2026-08-24T16:06:28Z"
author: JuruSysadmin
status: delivered
started: "2026-08-24T16:05:11Z"
finished: "2026-08-24T16:06:28Z"
delivered: "2026-08-24T16:06:28Z"
---

## Problem statement

## Possible solution

## Comments
@JuruSysadmin 2026-08-24
Refatorado lib/chat_web/controllers/treatment_preview_controller.ex: show/2 agora usa case e preserva o sucesso, os três erros, status HTTP e payloads existentes. Validação: testes do controller passaram (11); mix test --no-start passou com 609 testes; Credo passou sem issues; formatação dos arquivos envolvidos passou; mix format --check-formatted global falha somente no arquivo preexistente test/chat_web/channels/room_channel_authorization_test.exs; git diff --check passou.

## Attachments

## Tasks

- [x] Substituir o with simples de TreatmentPreviewController.show por case, mantendo todos os retornos atuais.

- [x] Executar os testes existentes do controller e os cenários de sucesso e erro do preview.

- [x] Executar mix format --check-formatted, mix credo e git diff --check; registrar falhas preexistentes.
