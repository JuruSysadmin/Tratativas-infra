---
title: Corrigir construção opaca de Ecto.Multi em Chat.Messages
type: chore
created: "2026-08-24T16:07:39Z"
modified: "2026-08-24T16:11:20Z"
author: JuruSysadmin
status: unstarted
blocked: true
blocked_reason: Chat.Messages já usa Ecto.Multi.new/0; o Dialyzer continua reportando call_without_opaque nas chamadas públicas Multi.run/3 por incompatibilidade de tipos opacos da versão atual do Ecto, também reproduzida em Chat.Rooms.
---

## Problem statement

## Possible solution

## Comments
@JuruSysadmin 2026-08-24
Investigação concluída sem alteração de código: Chat.Messages já usava Multi.new() no HEAD e não contém construção manual de %Ecto.Multi{}. mix compile --warnings-as-errors passou; test/chat/messages_test.exs passou com 56 testes; arquivos envolvidos passaram na formatação e git diff --check. mix dialyzer ainda retorna 6 call_without_opaque: Chat.Messages nas linhas 353, 729 e 1235, além de Chat.Rooms nas linhas 129, 204 e 221. O wrapper privado com @spec Multi.t() foi testado e apenas deslocou os avisos, portanto foi removido. Bloqueio: incompatibilidade entre Dialyzer/Ecto.Multi nesta versão, fora da construção manual descrita.

## Attachments

## Tasks

- [x] Confirmar que Chat.Messages não constrói Ecto.Multi manualmente e usa a API pública Multi.new/0.

- [x] Executar os testes de Chat.Messages e validações de compilação/formatação.

- [x] Executar mix dialyzer, separar o erro apontado de warnings fora do escopo e registrar o bloqueio.
