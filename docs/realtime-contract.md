# Contrato realtime

Este documento define o contrato público do socket Phoenix. Os nomes abaixo são os
nomes wire atuais; clientes não devem inferir estado a partir da origem do payload.
Replies de comandos bem-sucedidos usam o mesmo payload do broadcast, exceto comandos
sem evento de estado (`messages:read`, `messages:delivered`, `typing:*`).

## Convenções

- IDs são `string` UUID. `order_id` é `integer`.
- Datas são strings ISO-8601 UTC quando serializadas pelo socket. No teste Channel
  elas aparecem como `DateTime`/`NaiveDateTime` antes da serialização.
- Campo obrigatório sempre aparece. Campo nullable aparece com `null` quando não há
  valor; não é omitido. Não existem campos opcionais nas projeções de recurso abaixo.
- Campos enviados pelo cliente fora do comando documentado são ignorados e nunca
  controlam identidade, status ou datas.
- `treatment_id`, `room_id` e `id` são as chaves de correlação. `client_id` correlaciona
  uma tentativa local de criação de mensagem com a mensagem persistida.

## Mensagem

A projeção `Message` é a mesma em `message:new` (criada), `message:updated` e nos
replies de `message:new`/`message:edit`.

Campos obrigatórios: `id: string`, `room_id: string`, `client_id: string | null`,
`content: string`, `user: {id: string, username: string}`,
`inserted_at: datetime`, `edited_at: datetime | null`,
`attachments: Attachment[]`.

`Attachment` contém `id: string`, `filename: string`, `content_type: string`,
`size: integer` e `download_url: string | null`. A lista é sempre presente,
inclusive vazia; `download_url: null` significa que o cliente deve solicitar/gerar
o download por outro fluxo, e não que o anexo deixou de existir.

- Comando `message:new`: requer `content: string`, `client_id: string` UUID; aceita
  `attachment_ids: string[]` opcional (ausente equivale a `[]`). Reply `:ok` contém
  `Message`; o broadcast `message:new` contém o mesmo `Message`.
- Comando `message:edit`: requer `message_id: string` e `content: string`. Reply
  `:ok` e broadcast `message:updated` contêm o `Message` completo. O frontend
  substitui a mensagem por `id`.
- Comando `message:delete`: requer `message_id: string`. Reply `:ok` e broadcast
  `message:deleted` contêm `{id: string, room_id: string}`. Esse é um tombstone;
  o frontend remove exatamente `id` dentro de `room_id`. Não há conteúdo opcional.

## Tratativa

`Treatment` é uma única projeção usada no join de `room:<room_id>`, no evento de
fila `treatment:created`, em todos os replies bem-sucedidos e nos broadcasts de
transição.

Campos obrigatórios: `id: string` (igual a `treatment_id`), `treatment_id: string`, `room_id: string`, `order_id: integer`,
`protocol: string`, `status: "open" | "in_progress" | "resolved" | "closed"`,
`assigned_agent_id: string | null`, `assigned_agent_username: string | null`,
`assigned_agent_name: string | null` (alias compatível, mesmo valor),
`assigned_at: datetime | null`, `resolved_by_id: string | null`,
`resolved_at: datetime | null`, `closed_by_id: string | null`,
`closed_at: datetime | null`, `inserted_at: datetime`,
`can_assign: boolean`, `reason: {code: string, label: string, priority: string} | null`.

`assigned_agent_name` permanece apenas para compatibilidade com a fila. A fonte
oficial é `assigned_agent_username`; os dois campos são publicados juntos e nunca
podem divergir. `can_assign` é uma projeção de UI, não autorização.

- Join: retorna `Treatment` quando existe na sala; para sala sem Tratativa retorna
  `{room_id: string, treatment: null}`.
- Comando `treatment:assign_to_me`: não requer campos. Reply e broadcast
  `treatment:agent_assigned` usam `Treatment` pós-transação.
- Comando `treatment:unassign`: não requer campos. Reply e broadcast
  `treatment:unassigned` usam `Treatment` com assignment nulo e status `open`.
- Comando `treatment:transfer`: requer `target_agent_id: string`. Reply e broadcast
  `treatment:transferred` usam `Treatment` pós-transferência.
- Comando `treatment:resolve`: não requer campos. Reply e broadcast
  `treatment:resolved` usam `Treatment` com `resolved_by_id` e `resolved_at`
  persistidos.
- Comando `treatment:reopen`: não requer campos. Reply e broadcast
  `treatment:reopened` usam `Treatment` com `resolved_by_id: null` e
  `resolved_at: null`; assignment é preservado.
- Comando `treatment:close` e `treatment:confirm_resolution`: não requerem campos.
  Reply e broadcast `treatment:closed` usam `Treatment` com `closed_by_id` e
  `closed_at` persistidos.

Em erro, o reply é `{reason: string}` e não há broadcast. Retry idempotente de
atribuição retorna o estado persistido sem novo broadcast.

## Presença

No join, o canal envia `presence_state` com o mapa nativo Phoenix:
`{user_id: string => {metas: PresenceMeta[]}}`. Cada `PresenceMeta` contém
`id: string`, `username: string`, `joined_at: datetime`, `typing: boolean`; `typing_at`
é opcional e só aparece quando `typing` é `true`.

Depois do join, `presence_diff` tem `{joins: PresenceMap, leaves: PresenceMap}`;
ambos os campos são obrigatórios e podem ser mapas vazios. Uma saída é representada
por `leaves`, não por um usuário parcialmente preenchido. `user:joined` é uma
notificação compatível com `{user_id: string, username: string}` e não substitui o
estado de presença.

Presença é efêmera e não é fonte de autorização ou ownership.

## Digitação

Os comandos `typing:start` e `typing:stop` não têm campos obrigatórios nem payload
semântico de reply. Eles atualizam a presença do usuário autenticado. O estado
observável é um `presence_diff` contendo a `PresenceMeta` completa; `typing` é sempre
booleano. `typing_at` é opcional (presente apenas durante `true`) e pode ser
considerado nulo quando ausente. O usuário do socket é a única identidade válida.

## Estado inicial de mensagens e eventos auxiliares

O histórico de mensagens continua sendo carregado pela consulta de histórico
existente. Quando uma mensagem chega realtime, `Message` é completo e não exige
refetch. `read_receipts:updated` e `delivery_receipts:updated` têm campos
obrigatórios `user_id: string` e `message_ids: string[]`; são deltas, não mensagens.

## Compatibilidade e evolução

Novos campos devem ser aditivos. Renomear ou remover campo exige versão/rollout
compatível. Um teste público deve comparar reply e broadcast e verificar que o
snapshot da mesma entidade tem as mesmas chaves e semântica nullable.
