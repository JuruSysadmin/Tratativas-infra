O contrato abaixo representa o comportamento implementado atualmente, incluindo algumas diferenças entre o backend e a matriz de UI informada.



1. Autenticação

HTTP

As rotas da API ficam sob:

text
/api


E usam o pipeline:

elixir
pipe_through [:api, :auth]


A autenticação é feita pelo token processado em Chat.Auth.Plug.

WebSocket

Endpoint:

text
/socket


Conexão:

text
new Socket("/socket", {
  params: {
    token: accessToken
  }
})


O backend autentica o token em:

elixir
ChatWeb.UserSocket.connect/3


Se o token for válido, o socket recebe:

elixir
socket.assigns.current_user
socket.assigns.user_claims


Se o token estiver ausente ou inválido, a conexão falha.



2. Channel da sala

Tópico

text
room:<room_id>


Exemplo:

text
room:6f8...


Join

O cliente envia:

text
join("room:<room_id>", {})


O backend verifica:

elixir
Rooms.room_member?(current_user.id, room_id)


Sucesso

Resposta do join:

json
{
  "room_id": "room-uuid"
}


Além disso, o socket recebe:

text
presence_state


E os outros participantes recebem:

text
user:joined


Payload:

json
{
  "user_id": "user-uuid",
  "username": "nome-do-usuario"
}


Falha

Se o usuário não for membro da sala:

json
{
  "reason": "unauthorized"
}


Observação importante

O join atual não retorna o snapshot da Treatment.

O retorno atual contém somente:

json
{
  "room_id": "..."
}


Portanto, o frontend não pode depender do join para inicializar o estado da Tratativa. Para obter a Treatment atual, precisa usar um endpoint HTTP ou receber um evento posterior.



3. Histórico de mensagens

Endpoint

http
GET /api/rooms/:room_id/messages


Query params

text
limit
before


Exemplo:

http
GET /api/rooms/room-id/messages?limit=50&before=message-uuid


Valores aceitos

limit:

- padrão: 50;
- mínimo: 1;
- máximo: 100.

before:

- deve ser um UUID de mensagem;
- representa paginação para mensagens anteriores.

Resposta

json
{
  "messages": [
    {
      "id": "message-uuid",
      "content": "Mensagem",
      "user": {
        "id": "user-uuid",
        "username": "usuario"
      },
      "room_id": "room-uuid",
      "inserted_at": "2026-08-21T12:00:00Z",
      "edited_at": null,
      "attachments": []
    }
  ],
  "has_more": true
}


Autorização

O usuário precisa ser membro da sala.

Sem membership:

http
403


json
{
  "error": "not_a_member"
}




4. Criar mensagem

HTTP

http
POST /api/rooms/:room_id/messages


Payload:

json
{
  "message": {
    "content": "Mensagem",
    "client_id": "client-generated-id"
  }
}


O backend também suporta anexos quando o fluxo de upload estiver completo:

json
{
  "message": {
    "content": "Mensagem com arquivo",
    "client_id": "client-generated-id",
    "attachment_ids": [
      "attachment-uuid"
    ]
  }
}


Resposta

http
201


json
{
  "message": {
    "id": "message-uuid",
    "content": "Mensagem",
    "user": {
      "id": "user-uuid",
      "username": "usuario"
    },
    "room_id": "room-uuid",
    "inserted_at": "2026-08-21T12:00:00Z",
    "edited_at": null,
    "attachments": []
  }
}


Erros

text
client_id_conflict
invalid_client_id
not_a_member


O cliente deve tratar também erros de changeset como erro de validação.



5. Criar mensagem pelo Channel

Comando

text
message:new


Payload mínimo:

json
{
  "content": "Mensagem",
  "client_id": "client-generated-id"
}


Payload com anexos:

json
{
  "content": "Mensagem",
  "client_id": "client-generated-id",
  "attachment_ids": [
    "attachment-uuid"
  ]
}


Resposta de sucesso

text
ok


O reply não contém necessariamente a mensagem completa.

A mensagem completa é publicada para os subscribers por:

text
message:new


Evento message:new

json
{
  "id": "message-uuid",
  "content": "Mensagem",
  "user": {
    "id": "user-uuid",
    "username": "usuario"
  },
  "room_id": "room-uuid",
  "inserted_at": "2026-08-21T12:00:00Z",
  "edited_at": null,
  "attachments": []
}


Erros pelo Channel

json
{
  "reason": "invalid_client_id"
}


json
{
  "reason": "invalid_attachments"
}


json
{
  "reason": "invalid_message"
}




6. Eventos de mensagem

Mensagem criada

Evento:

text
message:new


Payload: mensagem completa.

Mensagem editada

Evento:

text
message:updated


Payload: mensagem completa.

Mensagem apagada

Evento:

text
message:deleted


Payload:

json
{
  "message_id": "message-uuid"
}




7. Editar mensagem

Comando

text
message:edit


Payload:

json
{
  "message_id": "message-uuid",
  "content": "Novo conteúdo"
}


Resposta de sucesso

text
ok


Eventos publicados

text
message:updated


com a mensagem completa.

Regras

O usuário só pode editar a própria mensagem e a operação depende das regras de mensagem não bloqueada do backend.



8. Apagar mensagem

Comando

text
message:delete


Payload:

json
{
  "message_id": "message-uuid"
}


Resposta de sucesso

text
ok


Evento publicado

text
message:deleted


Payload:

json
{
  "message_id": "message-uuid"
}


Possíveis erros

text
not_found
not_member
not_authorized
already_read
delete_failed




9. Presence

A presença é específica da sala:

text
room:<room_id>


Cada participante é identificado pelo próprio user_id.

presence_state

Enviado após o join.

Formato Phoenix Presence:

json
{
  "user-uuid": {
    "metas": [
      {
        "id": "user-uuid",
        "username": "usuario",
        "joined_at": "2026-08-21T12:00:00Z",
        "typing": false
      }
    ]
  }
}


O frontend normaliza isso para:

ts
{
  id: string
  username: string
  typing: boolean
}


presence_diff

Eventos padrão do Phoenix Presence:

text
presence_diff


O frontend usa Presence.onSync, onJoin e onLeave.

Usuário entrou

Evento adicional:

text
user:joined


Payload:

json
{
  "user_id": "user-uuid",
  "username": "usuario"
}




10. Digitação

Iniciar digitação

Comando:

text
typing:start


Payload:

json
{}


Parar digitação

Comando:

text
typing:stop


Payload:

json
{}


O backend atualiza a metadata de Presence:

json
{
  "typing": true
}


ou:

json
{
  "typing": false
}


Não existe um evento customizado typing:start ou typing:stop para os demais clientes. A atualização chega pela Presence.



11. Read receipts

Evento

text
read_receipts:updated


Payload:

json
{
  "user_id": "user-uuid",
  "message_ids": [
    "message-uuid-1",
    "message-uuid-2"
  ]
}


O evento informa que um usuário marcou determinadas mensagens como lidas.

O frontend mantém:

ts
Record<string, string[]>


No formato conceitual:

json
{
  "message-uuid-1": [
    "user-uuid"
  ]
}




12. Estado de conexão

Eventos importantes do Phoenix:

text
phx_error


Além disso, o frontend observa:

- abertura do socket;
- fechamento do socket;
- erro de conexão;
- rejoin do channel.

Estados utilizados no frontend:

text
idle
connecting
connected
error
recovering
disconnected




13. Estado atual da Treatment

Status possíveis

text
open
in_progress
resolved
closed


Campos persistidos relevantes:

json
{
  "id": "treatment-uuid",
  "order_id": 123,
  "room_id": "room-uuid",
  "status": "in_progress",
  "assigned_agent_id": "user-uuid",
  "assigned_at": "2026-08-21T12:00:00Z",
  "resolved_by_id": null,
  "resolved_at": null
}


O backend mantém uma Treatment única associada ao pedido e à sala.



14. Comando: assumir Tratativa

Event name

text
treatment:assign_to_me


Payload:

json
{}


O backend usa:

elixir
socket.assigns.current_user
socket.assigns.room_id


O frontend não deve enviar:

- agent_id;
- assigned_agent_id;
- assigned_at;
- status;
- identidade de outro usuário.

Sucesso: nova atribuição

Reply:

json
{
  "treatment_id": "treatment-uuid",
  "assigned_agent_id": "agent-uuid",
  "assigned_at": "2026-08-21T12:00:00Z"
}


Evento broadcast:

text
treatment:agent_assigned


Payload:

json
{
  "treatment_id": "treatment-uuid",
  "assigned_agent_id": "agent-uuid",
  "assigned_at": "2026-08-21T12:00:00Z"
}


Estado persistido:

text
open -> in_progress


Retry idempotente

Se o mesmo agente enviar o comando novamente enquanto já é o responsável:

- reply ok;
- retorna o estado existente;
- não altera o timestamp;
- não publica outro broadcast;
- não cria outro audit event.

Erros

text
forbidden
already_assigned
not_found
invalid_status
treatment_assignment_failed




15. Comando: resolver Tratativa

Event name

text
treatment:resolve


Payload:

json
{}


O backend ignora identidade enviada pelo cliente e usa:

elixir
socket.assigns.current_user


Pré-condições

- usuário autorizado para treatment.resolve;
- usuário é membro da sala;
- Treatment está em in_progress;
- usuário é o agente responsável.

Transição

text
in_progress -> resolved


Campos atualizados:

json
{
  "status": "resolved",
  "resolved_by_id": "current-user-id",
  "resolved_at": "server-generated-time"
}


Campos de ownership preservados:

text
assigned_agent_id
assigned_at


Reply de sucesso

json
{
  "treatment_id": "treatment-uuid",
  "status": "resolved",
  "resolved_by_id": "agent-uuid",
  "resolved_at": "2026-08-21T12:10:00Z"
}


Broadcast

Evento:

text
treatment:resolved


Payload igual ao reply:

json
{
  "treatment_id": "treatment-uuid",
  "status": "resolved",
  "resolved_by_id": "agent-uuid",
  "resolved_at": "2026-08-21T12:10:00Z"
}


Erros

text
forbidden
not_assigned_agent
invalid_status
not_found
treatment_resolution_failed


Retry após resolver:

text
invalid_status


Não há segundo broadcast nem segundo audit event.



16. Comando: reabrir Tratativa

Event name

text
treatment:reopen


Payload:

json
{}


Transição atual

text
resolved -> in_progress


O backend preserva o ownership:

text
assigned_agent_id
assigned_at


E limpa a resolução:

text
resolved_by_id: null
resolved_at: null


Reply de sucesso

json
{
  "treatment_id": "treatment-uuid",
  "status": "in_progress",
  "assigned_agent_id": "agent-uuid",
  "assigned_at": "2026-08-21T12:00:00Z"
}


Broadcast

Evento:

text
treatment:reopened


Payload:

json
{
  "treatment_id": "treatment-uuid",
  "status": "in_progress",
  "assigned_agent_id": "agent-uuid",
  "assigned_at": "2026-08-21T12:00:00Z"
}


Erros

text
forbidden
not_found
invalid_status
treatment_reopen_failed


Regra de autorização atual

O backend permite treatment.reopen para:

text
commercial
logistics_agent


Isso é importante porque diverge da matriz de UI informada anteriormente, que indicava Comercial sem ações na tela.

O contrato efetivo do backend hoje é:

elixir
"commercial" => ["treatment.reopen"]
"logistics_agent" => todas as permissões de Treatment




17. Comando: liberar Tratativa

Estado esperado do domínio

A operação de domínio existe:

elixir
Chat.Treatments.unassign/2


Regras:

- usuário deve ter treatment.unassign;
- usuário deve ser membro da sala;
- Treatment deve estar in_progress;
- usuário deve ser o agente responsável.

Transição:

text
in_progress -> open


Campos limpos:

json
{
  "assigned_agent_id": null,
  "assigned_at": null
}


Atenção: gap atual no Channel

O RoomChannel atual não possui um handler para:

text
treatment:unassign


Também não existe, no Channel atual, o broadcast:

text
treatment:unassigned


Portanto, embora o contexto de domínio tenha a operação, o contrato realtime do Channel ainda não está exposto para o frontend.

Isso explica por que o frontend possui o comando unassignTreatment(), mas o backend atual não apresenta um contrato funcional completo para ele pelo Phoenix Channel.



18. Comando: transferir Tratativa

Event name

text
treatment:transfer


Payload permitido:

json
{
  "target_agent_id": "target-agent-uuid"
}


O backend aceita o target_agent_id e ignora outros campos funcionais do cliente.

O cliente não deve enviar:

- current_agent_id;
- assigned_agent_id;
- assigned_at;
- status.

Pré-condições

- usuário atual autorizado para treatment.transfer;
- usuário atual é membro da sala;
- usuário atual é o responsável;
- Treatment está in_progress;
- alvo existe;
- alvo tem role logistics_agent;
- alvo é membro da mesma sala;
- alvo é diferente do agente atual.

Reply de sucesso

json
{
  "treatment_id": "treatment-uuid",
  "status": "in_progress",
  "assigned_agent_id": "target-agent-uuid",
  "assigned_at": "2026-08-21T12:20:00Z"
}


Broadcast

Evento:

text
treatment:transferred


Payload igual ao reply:

json
{
  "treatment_id": "treatment-uuid",
  "status": "in_progress",
  "assigned_agent_id": "target-agent-uuid",
  "assigned_at": "2026-08-21T12:20:00Z"
}


Erros

text
forbidden
not_found
not_assigned_agent
invalid_target_agent
same_agent
invalid_status
treatment_transfer_failed


Auditoria

A transferência registra:

json
{
  "previous_agent_id": "old-agent-uuid",
  "assigned_agent_id": "new-agent-uuid"
}




19. Eventos de lifecycle da Treatment

O frontend deve escutar:

text
treatment:agent_assigned
treatment:unassigned
treatment:transferred
treatment:resolved
treatment:reopened


Payloads atuais:

treatment:agent_assigned

json
{
  "treatment_id": "treatment-uuid",
  "assigned_agent_id": "agent-uuid",
  "assigned_at": "timestamp"
}


treatment:unassigned

Contrato esperado pelo lifecycle:

json
{
  "treatment_id": "treatment-uuid",
  "status": "open",
  "assigned_agent_id": null,
  "assigned_at": null
}


Mas o broadcast não está implementado atualmente no RoomChannel.

treatment:transferred

json
{
  "treatment_id": "treatment-uuid",
  "status": "in_progress",
  "assigned_agent_id": "new-agent-uuid",
  "assigned_at": "timestamp"
}


treatment:resolved

json
{
  "treatment_id": "treatment-uuid",
  "status": "resolved",
  "resolved_by_id": "agent-uuid",
  "resolved_at": "timestamp"
}


treatment:reopened

json
{
  "treatment_id": "treatment-uuid",
  "status": "in_progress",
  "assigned_agent_id": "agent-uuid",
  "assigned_at": "timestamp"
}


Observação: o frontend também preserva campos que não aparecem no evento. O evento não deve ser interpretado como um snapshot completo, exceto quando explicitamente documentado.



20. Auditoria e consistência

As transições de Treatment são persistidas junto com audit event dentro da mesma transação.

Eventos registrados:

text
treatment_created
treatment_assigned
treatment_unassigned
treatment_transferred
treatment_resolved
treatment_reopened
treatment_closed


A regra arquitetural é:

text
persistir alteração
persistir auditoria
commit
broadcast realtime


Em caso de falha ao criar o audit event:

- a alteração da Treatment deve sofrer rollback;
- nenhum broadcast de sucesso deve ser emitido.



21. Matriz de autorização efetiva no backend

O backend atual declara:

Comercial

text
treatment.reopen


Agente de logística

text
treatment.assign
treatment.resolve
treatment.reopen
treatment.unassign
treatment.transfer


Outros papéis

Nenhuma permissão de Treatment.

Resultado:

| Ação       | Comercial | Logística          |
|------------|-----------|--------------------|
| Assumir    | ❌        | ✅                 |
| Resolver   | ❌        | ✅, se responsável |
| Reabrir    | ✅        | ✅                 |
| Liberar    | ❌        | ✅, se responsável |
| Transferir | ❌        | ✅, se responsável |

Isso não é igual à matriz visual mencionada anteriormente, onde Comercial aparecia sem ações. O backend atualmente permite que Comercial reabra uma Treatment.



22. Endpoints auxiliares de sala

Listar salas

http
GET /api/rooms


Retorna salas do usuário autenticado.

Detalhar sala

http
GET /api/rooms/:id


Exige membership.

Entrar em sala

http
POST /api/rooms/:room_id/join


Sair da sala

http
POST /api/rooms/:room_id/leave


Usuários online

http
GET /api/rooms/:room_id/online


Resposta:

json
{
  "room_id": "room-uuid",
  "online_users": [
    {
      "id": "user-uuid",
      "username": "usuario",
      "joined_at": "timestamp",
      "typing": false
    }
  ],
  "online_count": 1
}




23. Anexos

Solicitar presigned URL

http
POST /api/rooms/:room_id/attachments/presign


Payload:

json
{
  "attachment": {
    "filename": "arquivo.pdf",
    "content_type": "application/pdf",
    "size": 12345
  }
}


Resposta:

json
{
  "attachment": {
    "id": "attachment-uuid",
    "filename": "arquivo.pdf",
    "content_type": "application/pdf",
    "size": 12345,
    "status": "pending",
    "upload_url": "https://...",
    "expires_at": "2026-08-21T12:10:00Z",
    "expires_in": 300
  }
}


Upload

O frontend envia o arquivo diretamente para:

http
PUT <upload_url>


Com:

http
Content-Type: <file.type>


Confirmar upload

http
POST /api/rooms/:room_id/attachments/:attachment_id/confirm


Resposta:

json
{
  "attachment": {
    "id": "attachment-uuid",
    "status": "available"
  }
}


Estados de anexo

text
pending
uploading
available
failed


Uso na mensagem

Depois da confirmação, o ID pode ser enviado em:

json
{
  "message": {
    "content": "Arquivo anexado",
    "attachment_ids": [
      "attachment-uuid"
    ]
  }
}




24. Contrato mínimo que o frontend deve implementar

Para o chat funcionar corretamente hoje, o frontend precisa:

1. Autenticar no /socket com token.
2. Entrar em room:<room_id>.
3. Confirmar membership via join.
4. Buscar histórico por HTTP.
5. Escutar:
   - message:new;
   - message:updated;
   - message:deleted;
   - read_receipts:updated;
   - presence_state;
   - presence_diff;
   - eventos de Treatment.
6. Enviar:
   - message:new;
   - message:edit;
   - message:delete;
   - typing:start;
   - typing:stop;
   - treatment:assign_to_me;
   - treatment:resolve;
   - treatment:reopen;
   - treatment:transfer.
7. Não aplicar optimistic update para Treatment.
8. Atualizar TreatmentState somente pelos broadcasts.
9. Bloquear comandos duplicados localmente.
10. Exibir ações conforme o contrato efetivo de autorização.