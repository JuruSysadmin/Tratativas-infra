---
title: Corrigir auditoria e contrato do PR 6
type: bug
created: "2026-08-21T03:35:18Z"
modified: "2026-08-21T03:44:19Z"
author: JuruSysadmin
status: delivered
started: "2026-08-21T03:35:54Z"
finished: "2026-08-21T03:44:19Z"
delivered: "2026-08-21T03:44:19Z"
---

## Problem statement

O PR #6 precisa manter o `RoomChannel` como adaptador de transporte, responder de
forma estável a retornos inesperados e registrar atribuição/resolução no histórico
sem permitir divergência entre a `Treatment` e seu `AuditEvent`.

## Possible solution

Manter as regras em `Chat.Treatments`, preservar as transações e locks existentes,
inserir os eventos dentro das mesmas transações e cobrir idempotência, falhas e
concorrência com testes de comportamento.

## Acceptance

* [x] `RoomChannel` não acessa diretamente `Repo` ou `Treatment` para atribuição.
* [x] Erros conhecidos preservam seus reasons e retornos inesperados usam um reason genérico estável.
* [x] Atribuição nova cria exatamente um `treatment_assigned`; retry/falha não duplicam eventos.
* [x] Resolução cria exatamente um `treatment_resolved`; falha e concorrência não duplicam eventos.
* [x] Persistência da transição e do evento é atômica, mantendo `FOR UPDATE` sem transações aninhadas.
* [x] Testes focados, format, suíte completa e precommit passam; o diff check do escopo passa e o global mantém apenas a falha preexistente em `_icebox.md`.

## Tasks

* [x] Inspecionar contexto, schemas, autorização, Channel, testes, migrations e diff do PR.
* [x] Adicionar testes de domínio para lookup por sala e contagem exata de eventos.
* [x] Confirmar RED para a API de lookup ausente e demais lacunas aplicáveis.
* [x] Implementar a correção mínima no contexto e no Channel.
* [x] Verificar atomicidade e preservar locks, idempotência e ownership.
* [x] Executar testes focados de Treatments e RoomChannel.
* [x] Executar format check, suíte completa, precommit e diff check.
* [x] Entregar a story para revisão humana sem aceitá-la.

## Comments
@JuruSysadmin 2026-08-21
Revisão concluída com TDD: RED observado para get_by_room_id/1 ausente; API adicionada ao contexto; assign_agent_for_room/2 reutiliza a transação de membership sem Repo.transaction aninhada; locks FOR UPDATE, idempotência e ownership preservados. Cobertura reforçada para contagem exata de treatment_assigned/treatment_resolved em sucesso, retry, falhas e concorrência. Testes focados: 44 passaram. mix format --check-formatted passou. mix test: 475 passaram. mix precommit: Credo sem issues e 475 testes passaram. git diff --check do escopo passou; o global continua apontando somente a linha em branco preexistente em tratativas-infra/_icebox.md. Sem commit, push, merge ou deploy.

## Attachments
