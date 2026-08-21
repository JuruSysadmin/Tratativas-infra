---
title: Expor reabertura da Tratativa via Phoenix Channel
type: feature
estimate: 2
tags: [backend, elixir, phoenix, channels, treatments, tdd]
status: delivered
modified: "2026-08-21T16:15:15Z"
started: "2026-08-21T15:58:56Z"
finished: "2026-08-21T16:15:15Z"
delivered: "2026-08-21T16:15:15Z"
---

## Problem statement

Como participante autorizado de uma Tratativa, quero reabrir uma Tratativa
resolvida através do Phoenix Channel para que o atendimento possa continuar
sem depender de uma chamada fora do canal realtime.

A regra de domínio já existe em:

    Chat.Treatments.reopen/2

Esta story deve somente expor essa operação através do `RoomChannel`.

Autorização por role, membership, validação de status, `FOR UPDATE`,
persistência, concorrência e auditoria continuam pertencendo a
`Chat.Treatments`.

## Dependencias

Depende de:

- matriz de autorização;
- membership das Rooms;
- `Treatments.reopen/2`;
- auditoria `treatment_reopened`;
- transição `resolved -> in_progress`.

A implementação deve seguir o padrão já consolidado por:

    treatment:assign_to_me
    treatment:resolve

## Contrato

Adicionar ao tópico:

    room:<room_id>

o comando:

    treatment:reopen

Payload:

    {}

O usuário deve vir exclusivamente de:

    socket.assigns.current_user

A Room deve vir exclusivamente de:

    socket.assigns.room_id

O cliente não deve controlar:

    user_id
    agent_id
    status
    assigned_agent_id
    assigned_at
    resolved_by_id
    resolved_at

## Fluxo

    channel.push("treatment:reopen", {})
                  |
                  v
              RoomChannel
                  |
                  +-- current_user
                  +-- room_id
                  |
                  v
          Chat.Treatments
                  |
                  v
            reopen_for_room
                  |
                  v
              reopen/2
                  |
                  +-- Authorization
                  +-- membership
                  +-- FOR UPDATE
                  +-- transition
                  +-- AuditEvent
                  |
                  v
                reply

O nome `reopen_for_room/2` é sugerido para manter simetria com as APIs por
Room já existentes. Antes de criar uma nova função, verificar o padrão atual
em `Chat.Treatments`.

## Regra arquitetural

O `RoomChannel` é somente adaptador de transporte.

Não fazer:

    Repo.get(...)
    Repo.get_by(...)
    Authorization.authorize(...)
    if user.role == ...
    if treatment.status == ...

no handler.

Todas essas decisões continuam no domínio.

## TDD

Desenvolver usando:

    RED
     |
    GREEN
     |
    REFACTOR

### TDD-01 - Commercial membro consegue reabrir

Preparar:

    user.role = commercial
    user pertence à Room

    Treatment:
      status = resolved
      assigned_agent_id = Agent A
      resolved_by_id = Agent A

Enviar:

    treatment:reopen

Esperar reply de sucesso.

Confirmar no banco:

    status == "in_progress"

    assigned_agent_id preservado
    assigned_at preservado

    resolved_by_id == nil
    resolved_at == nil

O primeiro RED deve ser observado antes da implementação do handler.

### TDD-02 - Logistics agent membro consegue reabrir

Um `logistics_agent` que pertence à Room também deve conseguir executar:

    treatment:reopen

Esperar sucesso.

### TDD-03 - Usuario sem membership recebe not_found

Um usuário possui role autorizada:

    commercial

mas não pertence à Room da Treatment.

Enviar:

    treatment:reopen

Esperar:

    not_found

Confirmar:

    status continua resolved
    assignment preservado
    resolution preservada
    0 novos treatment_reopened

O Channel não deve implementar essa verificação.

Ela deve vir de `Chat.Treatments`.

### TDD-04 - Role sem permissao recebe forbidden

Para uma role sem `treatment.reopen`:

    treatment:reopen
        ->
    forbidden

Nenhuma alteração deve ocorrer.

### TDD-05 - Status invalido

Uma Treatment que não esteja `resolved` deve resultar em:

    invalid_status

Cobrir pelo Channel pelo menos:

    in_progress

Não duplicar no Channel todos os estados possíveis.

### TDD-06 - Room sem Treatment

Uma Room válida e acessível, mas sem Treatment:

    treatment:reopen
        ->
    not_found

O processo do Channel deve continuar vivo.

### TDD-07 - Cliente nao controla campos

Enviar propositalmente:

    {
      "status": "resolved",
      "resolved_by_id": "...",
      "resolved_at": "...",
      "assigned_agent_id": "..."
    }

Esses valores devem ser ignorados ou rejeitados conforme o padrão atual do
Channel.

Nunca devem controlar a operação.

O resultado deve continuar sendo determinado por:

    socket.assigns.current_user
    socket.assigns.room_id
    estado persistido

### TDD-08 - Auditoria continua no dominio

Após sucesso pelo Channel deve existir exatamente:

    1 treatment_reopened

Mas o `RoomChannel` não deve criar o `AuditEvent`.

Isso deve continuar acontecendo dentro de `Treatments.reopen/2`.

### TDD-09 - Fallback seguro

Erros conhecidos:

    forbidden
    not_found
    invalid_status

devem possuir replies estáveis.

Um retorno inesperado do domínio não deve provocar `CaseClauseError`.

Usar um fallback consistente com assignment/resolution, por exemplo:

    treatment_reopen_failed

Não expor:

    Ecto.Changeset
    SQL
    exceptions
    detalhes internos

Não criar mocks artificiais somente para testar esse fallback se o projeto não
possuir mecanismo apropriado de injeção.

## Reply de sucesso

Payload sugerido:

    %{
      treatment_id: treatment.id,
      status: treatment.status,
      assigned_agent_id: treatment.assigned_agent_id
    }

Não é necessário devolver campos que o frontend não precise.

Antes de definir o payload final, comparar com os replies atuais de
`treatment:assign_to_me` e `treatment:resolve` e manter consistência.

## Broadcast

NÃO publicar nesta story:

    treatment:reopened

Inclusive adicionar, se adequado ao padrão atual dos testes:

    refute_push "treatment:reopened", _payload

Isso protege a separação entre:

    COMMAND
    treatment:reopen

e:

    EVENT
    treatment:reopened

que será implementado na próxima story.

## Acceptance

- [x] Desenvolvimento iniciado com TDD.
- [x] RED observado antes do handler.
- [x] Existe `treatment:reopen`.
- [x] Payload pode ser vazio.
- [x] Usuário vem de `socket.assigns.current_user`.
- [x] Room vem de `socket.assigns.room_id`.
- [x] Channel delega para `Chat.Treatments`.
- [x] Channel não acessa `Repo`.
- [x] Channel não implementa autorização por role.
- [x] Channel não implementa membership.
- [x] Channel não implementa regra de status.
- [x] Commercial membro consegue reabrir.
- [x] Logistics agent membro consegue reabrir.
- [x] Usuário sem membership recebe `not_found`.
- [x] Role não autorizada recebe `forbidden`.
- [x] Estado inválido retorna `invalid_status`.
- [x] Room sem Treatment retorna `not_found`.
- [x] Assignment é preservado.
- [x] Campos de resolução são limpos pelo domínio.
- [x] Cliente não controla campos da Treatment.
- [x] Auditoria continua pertencendo ao domínio.
- [x] Sucesso pelo Channel produz exatamente um `treatment_reopened` AuditEvent.
- [x] Erros conhecidos possuem replies estáveis.
- [x] Existe fallback seguro para resultado inesperado.
- [x] Nenhum broadcast `treatment:reopened` é publicado.
- [x] Nenhum Presence é alterado.
- [x] Nenhum frontend é alterado.
- [x] Testes focados passam.
- [x] `mix format --check-formatted` passa.
- [x] `mix test` passa.
- [x] `mix precommit` passa.
- [x] `git diff --check` dos arquivos da story passa.

## Tasks

- [x] Ler implementação atual de `treatment:resolve`.
- [x] Ler APIs `*_for_room` existentes em `Chat.Treatments`.
- [x] Ler `Treatments.reopen/2`.
- [x] Escrever TDD-01.
- [x] Confirmar RED.
- [x] Criar `reopen_for_room/2`, se necessário.
- [x] Implementar `handle_in("treatment:reopen", ...)`.
- [x] Mapear reply de sucesso.
- [x] Mapear `forbidden`.
- [x] Mapear `not_found`.
- [x] Mapear `invalid_status`.
- [x] Adicionar fallback seguro.
- [x] Testar commercial.
- [x] Testar logistics_agent.
- [x] Testar ausência de membership.
- [x] Testar Room sem Treatment.
- [x] Testar payload malicioso.
- [x] Confirmar auditoria integrada.
- [x] Confirmar ausência de broadcast.
- [x] Refatorar mantendo testes verdes.
- [x] Executar testes focados.
- [x] Executar `mix format --check-formatted`.
- [x] Executar `mix test`.
- [x] Executar `mix precommit`.
- [x] Executar `git diff --check`.
- [x] Marcar como delivered.
- [x] Aguardar revisão humana antes de accepted.

- [x] Revalidar membership em `reopen_for_room/2` com `Rooms.with_member_room/3`.
- [x] Adicionar regressão da API por Room para usuário sem membership.
- [x] Executar gates focados e completos após o feedback de revisão.
## Fora do escopo

Não implementar:

- `treatment:reopened` broadcast;
- unassign;
- transfer;
- frontend;
- Carbon AI Chat;
- Presence;
- notificações externas.

## Proxima story

    Publicar reabertura da Tratativa em realtime

## Comments
@JuruSysadmin 2026-08-21
Feedback de revisão: `reopen_for_room/2` deve validar membership no próprio contexto, seguindo o padrão das APIs `*_for_room`. A correção deve manter o Channel como adaptador e preservar o contrato `not_found` para usuário fora da Room.

@JuruSysadmin 2026-08-21
Feedback atendido: `reopen_for_room/2` agora executa `Rooms.with_member_room/3` no próprio contexto antes de localizar a Treatment. O caso de Room existente sem membership é normalizado para `not_found`, preservando o contrato não-discriminatório. Adicionada regressão direta da API por Room. Verificação: 74 testes focados, 505 testes em `mix test`, `mix format --check-formatted`, `mix precommit` e `git diff --check` passaram.

## Attachments
