---
title: Expor transferencia da Tratativa via Phoenix Channel
type: feature
estimate: 2
tags: [backend, elixir, phoenix, channels, treatments, authorization, tdd]
status: delivered
modified: "2026-08-21T19:55:14Z"
started: "2026-08-21T19:47:41Z"
finished: "2026-08-21T19:55:05Z"
delivered: "2026-08-21T19:55:05Z"
---

## Problem statement

Como agente da logistica responsavel por uma Tratativa, quero transferir o
atendimento diretamente para outro agente da logistica atraves do Phoenix
Channel.

A regra de dominio ja existe em `Chat.Treatments.transfer_agent/3`. Esta story
somente a expoe pelo `RoomChannel`. Autorizacao, membership, ownership,
validacao do destino, status, locking, concorrencia, persistencia e auditoria
continuam no contexto/dominio.

## Comando

No topico `room:<room_id>`, adicionar:

    treatment:transfer

Payload:

    %{"target_agent_id" => target_agent_id}

`target_agent_id` e o unico identificador operacional recebido do cliente.
`current_user` e `room_id` devem vir exclusivamente de:

    socket.assigns.current_user
    socket.assigns.room_id

O cliente nao controla current agent, assigned agent, status, timestamps ou
qualquer outro campo da Treatment.

## API por Room

Adicionar, se necessario:

    Chat.Treatments.transfer_agent_for_room(room_id, current_agent, target_agent_id)

Essa funcao deve validar membership do agente atual, localizar a Treatment da
Room, carregar o target e delegar para `transfer_agent/3`, preservando os erros
de dominio. O Channel nao deve acessar `Repo` nem duplicar regras de negocio.

## Replies

Sucesso:

    %{
      treatment_id: treatment.id,
      status: treatment.status,
      assigned_agent_id: treatment.assigned_agent_id,
      assigned_at: treatment.assigned_at
    }

Mapear erros conhecidos para replies estaveis:

    forbidden
    not_found
    not_assigned_agent
    invalid_target_agent
    same_agent
    invalid_status

Payload sem `target_agent_id` deve seguir o padrao atual do Channel, sem criar
convencao desnecessaria. Retornos inesperados devem usar fallback seguro, como
`treatment_transfer_failed`, sem expor changesets, SQL ou exceptions.

## Acceptance

- [ ] TDD iniciado e RED observado antes do handler.
- [ ] Existe `treatment:transfer`.
- [ ] Payload recebe `target_agent_id`.
- [ ] Current agent e Room vem do socket.
- [ ] Existe API `transfer_agent_for_room/3`, se necessaria.
- [ ] Channel delega ao contexto e nao acessa Repo.
- [ ] Channel nao duplica authorization, role, membership, ownership ou status.
- [ ] Transferencia valida funciona.
- [ ] Commercial recebe `forbidden`.
- [ ] Outro agente recebe `not_assigned_agent`.
- [ ] Target commercial, sem membership ou inexistente recebe `invalid_target_agent`.
- [ ] Mesmo agente recebe `same_agent`.
- [ ] Current agent sem membership recebe `not_found`.
- [ ] Status invalido e Room sem Treatment retornam `not_found`/`invalid_status` conforme o dominio.
- [ ] Campos extras do cliente nao controlam a operacao.
- [ ] Auditoria continua pertencendo ao dominio.
- [ ] Sucesso gera exatamente um `treatment_transferred`.
- [ ] Nenhum `treatment:transferred` e publicado nesta story.
- [ ] Existe fallback seguro.
- [ ] Nenhum frontend ou Presence e alterado.
- [ ] Testes focados, format, test, precommit e diff check passam.

## Tasks

- [x] Ler handlers de assign, resolve, reopen e unassign.
- [x] Ler testes de comandos e replies do RoomChannel.
- [x] Ler `transfer_agent/3` e APIs `*_for_room`.
- [x] Escrever primeiro teste RED com `Phoenix.ChannelTest`.
- [x] Confirmar RED pela ausencia do comando.
- [x] Implementar `transfer_agent_for_room/3`, se necessario.
- [x] Implementar `handle_in("treatment:transfer", ...)`.
- [x] Mapear sucesso e erros conhecidos.
- [x] Adicionar fallback seguro.
- [x] Testar payload extra/malicioso e target inexistente.
- [x] Confirmar auditoria e ausencia de broadcast.
- [x] Refatorar mantendo testes verdes.
- [x] Executar testes focados.
- [x] Executar `mix format --check-formatted`.
- [x] Executar `mix test`.
- [x] Executar `mix precommit`.
- [x] Executar `git diff --check`.
- [x] Marcar como delivered.
- [ ] Aguardar revisao humana.

## Fora do escopo

- `treatment:transferred` broadcast;
- auto-membership do agente destino;
- frontend, Carbon AI Chat e Presence.

## Proxima story

    Publicar transferencia da Tratativa em realtime

## Comments

@user 2026-08-21
Implementado na branch feat/expose-treatment-transfer-channel. RED observado no Phoenix Channel com FunctionClauseError antes do handler. GREEN com transfer_agent_for_room/3, handle_in treatment:transfer, replies estaveis, payload target_agent_id, campos extras ignorados e nenhum broadcast treatment:transferred. Verificado: foco dominio + Channel 111 testes; mix test 536 testes; mix precommit passou com Credo 1061 mods/funs sem issues; mix format --check-formatted e git diff --check passaram. Avisos PubSub/broadcast sao observacoes de infraestrutura.
