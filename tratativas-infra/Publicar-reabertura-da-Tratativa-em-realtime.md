---
title: Publicar reabertura da Tratativa em realtime
type: feature
estimate: 2
tags: [backend, elixir, phoenix, channels, treatments, realtime, tdd]
status: delivered
modified: "2026-08-21T16:40:42Z"
started: "2026-08-21T16:36:16Z"
finished: "2026-08-21T16:40:42Z"
delivered: "2026-08-21T16:40:42Z"
---

## Problem statement

Como participante de uma sala de Tratativa, quero receber uma notificacao
realtime quando uma Tratativa for reaberta, para que todos os participantes
atualizem imediatamente o estado do atendimento sem precisar recarregar a
pagina.

O comando de reabertura ja existe:

    treatment:reopen

A regra de dominio ja existe em:

    Chat.Treatments.reopen/2

E a operacao por sala ja existe atraves de:

    Chat.Treatments.reopen_for_room/2

Esta story adiciona somente a propagacao realtime de uma reabertura
efetivamente realizada.

## Dependencias

Esta story depende de:

- `Treatments.reopen/2`;
- `Treatments.reopen_for_room/2`;
- autorizacao `treatment.reopen`;
- verificacao de membership da Room;
- transicao `resolved -> in_progress`;
- auditoria `treatment_reopened`;
- comando `treatment:reopen` no `RoomChannel`.

## Evento

Publicar no topico:

    room:<room_id>

o evento:

    treatment:reopened

Payload sugerido:

    %{
      treatment_id: treatment.id,
      status: treatment.status,
      assigned_agent_id: treatment.assigned_agent_id,
      assigned_at: treatment.assigned_at
    }

O payload deve ser construido exclusivamente a partir da Treatment retornada
pela operacao de dominio.

O cliente nao fornece nenhum desses valores para determinar o broadcast.

## Regra principal

O broadcast representa uma transicao de dominio realmente persistida.

Fluxo:

    treatment:reopen
            |
            v
       RoomChannel
            |
            v
    reopen_for_room(...)
            |
            v
       Authorization
            |
            v
        membership
            |
            v
       FOR UPDATE
            |
            v
    resolved -> in_progress
            |
            +-- update Treatment
            +-- treatment_reopened AuditEvent
            |
          COMMIT
            |
            v
       :reopened
            |
            v
    treatment:reopened

O Channel deve publicar somente quando o dominio confirmar que ocorreu uma
reabertura.

## Regra contra estado stale

O `RoomChannel` nao deve inferir uma reabertura usando um `%Treatment{}`
carregado antes da operacao.

Nao fazer:

    if treatment.status == "resolved" do
      broadcast(...)
    end

A decisao deve vir do resultado de `reopen_for_room/2`, depois da avaliacao do
estado persistido sob `FOR UPDATE`.

Seguir o principio ja adotado para assignment:

    estado antes da operacao != prova de transicao

    resultado confirmado pelo dominio = prova de transicao

## Contrato do dominio

Preferencialmente, o resultado bem-sucedido deve permitir distinguir
explicitamente a transicao:

    {:ok, treatment, :reopened}

O contrato existente deve ser preservado se ja fornecer essa informacao.

Somente:

    :reopened

autoriza o broadcast.

## Broadcast fora da transaction

Nao executar Phoenix broadcast dentro da transaction do banco.

Fluxo:

    BEGIN
      |
      +-- SELECT FOR UPDATE
      +-- update Treatment
      +-- AuditEvent treatment_reopened
      |
    COMMIT
      |
      v
    broadcast treatment:reopened

Falha de PubSub nao deve provocar rollback de uma reabertura ja persistida.

## TDD

Desenvolver obrigatoriamente usando:

    RED
     |
    GREEN
     |
    REFACTOR

### TDD-01 - Reabertura publica exatamente um evento

Preparar:

    Treatment:
      status = resolved
      assigned_agent_id = Agent A
      assigned_at != nil
      resolved_by_id != nil
      resolved_at != nil

Usuario autorizado e membro envia:

    treatment:reopen

Esperar sucesso.

Esperar exatamente:

    1 treatment:reopened

Validar:

    treatment_id == treatment.id
    status == "in_progress"
    assigned_agent_id == Agent A.id
    assigned_at == timestamp original

Confirmar no banco:

    resolved_by_id == nil
    resolved_at == nil

### TDD-02 - Segunda tentativa nao publica novamente

Primeira chamada:

    treatment:reopen
        -> :reopened
        -> 1 treatment:reopened

Segunda chamada:

    treatment:reopen
        -> invalid_status
        -> 0 novos broadcasts

Total:

    exatamente 1 treatment:reopened

### TDD-03 - Commercial membro recebe o broadcast

Como `commercial` possui `treatment.reopen`, um commercial membro da Room deve
conseguir reabrir.

Esperar:

    reply sucesso
    +
    1 treatment:reopened

O evento deve identificar o estado da Treatment, nao transformar o commercial
em agente.

### TDD-04 - Logistics agent membro recebe o broadcast

Um `logistics_agent` membro tambem pode reabrir.

Esperar:

    reply sucesso
    +
    1 treatment:reopened

### TDD-05 - Usuario sem membership nao publica

Usuario com role permitida, mas fora da Room:

    treatment:reopen
        ->
    not_found

Esperar:

    0 treatment:reopened

Confirmar:

    status permanece resolved
    assignment preservado
    resolution preservada
    0 novos treatment_reopened AuditEvents

### TDD-06 - Forbidden nao publica

Role sem permissao:

    treatment:reopen
        ->
    forbidden

Esperar:

    0 treatment:reopened

### TDD-07 - Invalid status nao publica

Treatment em:

    in_progress

Recebe:

    treatment:reopen

Esperar:

    invalid_status
    0 treatment:reopened

### TDD-08 - Room sem Treatment nao publica

Room valida, usuario membro, mas sem Treatment:

    treatment:reopen
        ->
    not_found

Esperar:

    0 treatment:reopened

### TDD-09 - Estado stale nao produz broadcast incorreto

Criar um cenario onde o estado mantido pelo caller nao representa mais o
estado persistido.

Exemplo:

    caller acredita:
        status = resolved

    banco:
        status = in_progress

Executar a operacao.

O resultado deve ser baseado no estado persistido sob lock:

    invalid_status

E:

    0 treatment:reopened

O teste nao deve depender da struct stale para decidir se houve broadcast.

### TDD-10 - Concorrencia publica exatamente uma vez

Executar duas tentativas concorrentes de reabrir a mesma Treatment.

Resultado esperado:

    tentativa A -> :reopened
    tentativa B -> invalid_status

ou ordem equivalente.

No realtime:

    exatamente 1 treatment:reopened

Na auditoria:

    exatamente 1 treatment_reopened

Nunca:

    2 broadcasts
    2 AuditEvents

### TDD-11 - Payload vem do estado persistido

O payload do evento deve refletir a Treatment retornada pela operacao.

Validar especialmente:

    status == "in_progress"
    assigned_agent_id preservado
    assigned_at preservado

Nao reutilizar valores enviados pelo cliente.

## Auditoria

A auditoria continua pertencendo ao dominio.

Uma reabertura bem-sucedida deve produzir:

    1 AuditEvent:
        treatment_reopened

E:

    1 Phoenix event:
        treatment:reopened

Sao responsabilidades diferentes:

    AuditEvent
        -> registro persistente

    treatment:reopened
        -> propagacao realtime

O `RoomChannel` nao deve criar `AuditEvent`.

## Tratamento de erros

Manter os replies ja existentes de `treatment:reopen`.

Erros como:

    forbidden
    not_found
    invalid_status

nao publicam evento.

Resultados inesperados continuam usando o fallback seguro existente:

    treatment_reopen_failed

Nao expor:

    Ecto.Changeset
    SQL
    exceptions
    detalhes internos

## Acceptance

- [x] Desenvolvimento iniciado com TDD.
- [x] RED observado antes da implementacao do broadcast.
- [x] Existe evento `treatment:reopened`.
- [x] Reabertura efetiva publica exatamente um evento.
- [x] Evento e publicado no topico `room:<room_id>`.
- [x] Payload possui `treatment_id`.
- [x] Payload possui `status`.
- [x] `status` publicado e `in_progress`.
- [x] Payload possui `assigned_agent_id`.
- [x] Payload possui `assigned_at`.
- [x] Assignment original e preservado.
- [x] Payload vem da Treatment retornada pelo dominio.
- [x] Channel nao decide broadcast usando estado stale.
- [x] Somente resultado `:reopened` permite broadcast.
- [x] Segunda tentativa nao publica novamente.
- [x] `forbidden` nao publica.
- [x] `not_found` nao publica.
- [x] `invalid_status` nao publica.
- [x] Usuario sem membership nao publica.
- [x] Room sem Treatment nao publica.
- [x] Concorrencia produz exatamente um broadcast.
- [x] Concorrencia continua produzindo exatamente um AuditEvent.
- [x] AuditEvent continua pertencendo a `Chat.Treatments`.
- [x] Broadcast ocorre depois da operacao transacional.
- [x] Broadcast nao participa da transaction do banco.
- [x] Nenhum acesso direto a `Repo` e adicionado ao Channel.
- [x] Nenhuma regra de role e duplicada no Channel.
- [x] Nenhuma regra de membership e duplicada no Channel.
- [x] Nenhuma regra de status e duplicada no Channel.
- [x] Nenhum Presence e alterado.
- [x] Nenhum frontend e alterado.
- [x] Testes focados passam.
- [x] `mix format --check-formatted` passa.
- [x] `mix test` passa.
- [x] `mix precommit` passa.
- [x] `git diff --check` dos arquivos da story passa.

## Tasks

- [x] Ler o fluxo atual de `treatment:reopen`.
- [x] Ler `Treatments.reopen/2`.
- [x] Ler `Treatments.reopen_for_room/2`.
- [x] Comparar com `treatment:agent_assigned`.
- [x] Comparar com `treatment:resolved`.
- [x] Confirmar como o dominio sinaliza `:reopened`.
- [x] Escrever teste RED para o primeiro `treatment:reopened`.
- [x] Executar o teste e registrar RED.
- [x] Implementar broadcast somente para `:reopened`.
- [x] Construir payload a partir da Treatment retornada.
- [x] Garantir broadcast depois da operacao transacional.
- [x] Testar commercial membro.
- [x] Testar logistics_agent membro.
- [x] Testar segunda tentativa.
- [x] Testar usuario sem membership.
- [x] Testar forbidden.
- [x] Testar invalid_status.
- [x] Testar Room sem Treatment.
- [x] Testar estado stale.
- [x] Testar concorrencia.
- [x] Confirmar exatamente um AuditEvent na concorrencia.
- [x] Confirmar exatamente um broadcast na concorrencia.
- [x] Refatorar mantendo testes verdes.
- [x] Executar testes focados.
- [x] Executar `mix format --check-formatted`.
- [x] Executar `mix test`.
- [x] Executar `mix precommit`.
- [x] Executar `git diff --check`.
- [x] Marcar story como delivered.
- [x] Aguardar revisao humana antes de accepted.

## Fora do escopo

Nao implementar nesta story:

- unassign;
- transfer;
- frontend;
- Carbon AI Chat;
- Presence;
- notificacoes externas;
- outbox;
- persistencia do evento Phoenix.

## Proxima story

Se `unassign` fizer parte do MVP:

    Permitir liberar Tratativa

Caso `unassign` fique fora do MVP:

    Integrar estado da Tratativa no frontend

## Comments
@JuruSysadmin 2026-08-21
Plano: adicionar primeiro o teste de reabertura válida esperando `treatment:reopened`; confirmar RED; implementar somente o caminho `{:ok, treatment, :reopened}` no RoomChannel; cobrir erros, stale state, payload e concorrência; executar todos os gates.

@JuruSysadmin 2026-08-21
Implementação concluída com TDD. RED observado na reabertura válida sem `treatment:reopened`. GREEN com broadcast somente no resultado `{:ok, treatment, :reopened}` e payload derivado da Treatment retornada, incluindo `assigned_at`. Cobertos commercial, logistics_agent, retry, membership, forbidden, invalid_status, Room sem Treatment, stale state, payload e concorrência. Verificação: 76 testes focados, 507 testes em `mix test`, Credo/precommit, format check e diff check passaram. Concorrência usa dois subscribers: uma publicação gera uma entrega por subscriber, sem terceira entrega; domínio e auditoria confirmam uma transição.

## Attachments
