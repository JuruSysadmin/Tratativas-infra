---
title: Disponibilizar agentes elegíveis para transferência da Tratativa
type: feature
estimate: "3"
tags: [backend, elixir, phoenix, treatments, transfer, users, authorization, contract, tdd]
status: accepted
created: "2026-08-22T13:28:21Z"
modified: "2026-08-22T17:17:45Z"
author: JuruSysadmin
started: "2026-08-22T17:17:45Z"
finished: "2026-08-22T17:17:45Z"
delivered: "2026-08-22T17:17:45Z"
accepted: "2026-08-22T17:17:45Z"
---

## Problem statement

Como agente de logística responsável por uma Tratativa, quero obter uma lista oficial de agentes elegíveis para transferência, para selecionar um novo responsável sem depender de Presence, inferências do frontend ou regras duplicadas fora do backend.

O comando de transferência já existe e continua sendo a autoridade final para validar o `target_agent_id`.

O que falta é uma operação de leitura explícita que responda:

> Para quais agentes esta Treatment pode ser transferida neste momento?

A lista deve ser orientada pelas regras reais já existentes no backend e servir somente como suporte de UX/discovery. Ela não substitui a validação executada por `treatment:transfer`.

## Objetivo

Disponibilizar uma fonte oficial e read-only de candidatos de transferência.

Fluxo:

```text
usuário responsável
    |
    v
solicitar candidatos
    |
    v
Chat.Treatments
    |
    v
regras de elegibilidade
    |
    v
[%{id: ..., username: ...}, ...]
```

Posteriormente o frontend utilizará essa lista para permitir seleção de destino.

Ao executar a transferência, `treatment:transfer` deve revalidar todas as regras:

```text
target_agent_id
    |
    v
treatment:transfer
    |
    v
backend revalida todas as regras
```

A lista nunca deve ser tratada como autorização prévia ou permanente.

## Princípio principal

Separar claramente:

```text
discovery / UX != autorização da mutation
```

A operação de listagem responde apenas quais candidatos fazem sentido apresentar.

A mutation continua verificando novamente identidade do ator, autorização, ownership atual, membership, status persistido, existência e role do target, elegibilidade, concorrência, lock e transação.

## Regras de domínio a confirmar antes da implementação

A implementação deve começar lendo a regra atual de `transfer_agent_for_room/3`. Não inventar regras novas apenas para a listagem.

Confirmar explicitamente:

- o target precisa ter `role == "logistics_agent"`;
- o target precisa ser membro da Room;
- o agente atual deve ser excluído da lista;
- o próprio usuário atual deve ser excluído;
- Presence/online influencia eligibility;
- filial, setor, equipe ou outra dimensão participa da regra;
- apenas o agente responsável pode consultar candidatos;
- a Treatment deve estar obrigatoriamente `in_progress`;
- Treatment `open`, `resolved` ou `closed` retorna lista vazia ou erro;
- existe limite ou ordenação oficial.

As respostas devem vir do código e das regras já existentes.

## Presence

Presence não deve ser fonte de elegibilidade.

Manter o invariante:

```text
membro da sala != online agora != agente elegível != responsável atual
```

Presence pode futuramente enriquecer a apresentação, mas não deve decidir se um agente pode receber a Tratativa.

## Contrato público

Retornar somente os campos necessários para seleção visual.

Contrato mínimo sugerido:

```json
{
  "agents": [
    {
      "id": "UUID",
      "username": "string"
    }
  ]
}
```

Não adicionar sem necessidade matrícula, codusur, permissions, token, `room_id`, status interno, dados pessoais, Presence ou campos de autenticação. Se a UI precisar de informação adicional, evoluir o contrato conscientemente.

## Fronteira recomendada

Preferir uma leitura HTTP para os candidatos:

```text
GET /api/chat/rooms/:room_id/transfer-agents
```

A rota pode seguir outra convenção já existente no projeto.

Motivo:

```text
HTTP              -> consultas/read models
Phoenix Channel   -> commands/mutations
Phoenix broadcast -> sincronização realtime
```

## Contexto

Criar uma função equivalente a:

```elixir
Chat.Treatments.list_transfer_candidates(room_id, current_user)
```

ou outro nome consistente com o projeto.

A função deve ser read-only, sem alteração de Treatment, audit event, broadcast, optimistic behavior ou dependência de dados enviados pelo frontend além do identificador necessário para localizar a Room/Treatment.

## Query

Evitar N+1. Preferir uma query única ou um conjunto pequeno e previsível de queries, seguindo os schemas existentes e as regras confirmadas em `transfer_agent_for_room/3`.

Exemplo conceitual:

```elixir
User
|> join(:inner, ..., room_membership)
|> where([user, membership], membership.room_id == ^room_id)
|> where([user, _membership], user.role == "logistics_agent")
|> where([user, _membership], user.id != ^assigned_agent_id)
```

A consulta não deve transformar a listagem em uma segunda implementação divergente da elegibilidade da mutation.

## Segurança

O frontend não deve enviar como valores autoritativos `current_user_id`, `current_user_role`, `assigned_agent_id` ou `treatment_status`.

Esses valores devem vir do backend. A identidade deve ser obtida pelo mecanismo autenticado atual. A operação deve falhar fechada quando o caller não puder consultar candidatos.

## Revalidação obrigatória

Mesmo que o backend retorne um agente como candidato, o comando posterior `treatment:transfer` deve repetir as validações relevantes. Entre a consulta e a mutation, membership, status, ownership ou role podem mudar.

Nunca confiar que:

```text
apareceu na lista == ainda é válido no momento da mutation
```

## TDD

Executar RED -> GREEN -> REFACTOR.

- TDD-01: agente com todas as regras atuais aparece.
- TDD-02: responsável atual não aparece quando a regra não permite auto-transferência.
- TDD-03: usuário com role inválida não aparece.
- TDD-04: usuário sem membership não aparece quando membership for requisito.
- TDD-05: agente elegível offline continua aparecendo se Presence não fizer parte da regra.
- TDD-06: Treatment incompatível segue o contrato confirmado: lista vazia ou erro conhecido.
- TDD-07: caller sem permissão não recebe uma lista utilizável.
- TDD-08: consulta não altera status, `assigned_agent_id`, `assigned_at`, auditoria ou broadcasts.
- TDD-09: `treatment:transfer` rejeita um target que deixou de ser válido antes da mutation.

## Acceptance

- [x] Existe uma operação read-only para listar agentes elegíveis.
- [x] A regra é derivada das regras reais do backend.
- [x] O frontend não precisa inferir eligibility.
- [x] Presence não é autoridade de elegibilidade.
- [x] O responsável atual é excluído quando exigido pela regra.
- [x] Roles incompatíveis não são retornadas.
- [x] Membership é respeitada quando fizer parte do domínio.
- [x] O contrato retorna somente campos necessários à UI.
- [x] A consulta não altera Treatment.
- [x] A consulta não cria audit event.
- [x] A consulta não publica evento Phoenix.
- [x] Não existe N+1 evidente na listagem.
- [x] A identidade do caller vem do backend autenticado.
- [x] `treatment:transfer` continua revalidando o target.
- [x] A listagem não enfraquece autorização.
- [x] Testes focados, `mix format --check-formatted`, `mix precommit` e `git diff --check` passam.
- [x] Story é entregue para revisão humana antes de `accepted`.

## Tasks

- [x] Ler `transfer_agent_for_room/3`.
- [x] Mapear todas as regras atuais de elegibilidade do target.
- [x] Confirmar papel de role, membership e Presence.
- [x] Confirmar exclusão do responsável atual.
- [x] Confirmar estados da Treatment em que a consulta é válida.
- [x] Definir comportamento para lista vazia.
- [x] Definir contrato mínimo `{id, username}`.
- [x] Definir rota HTTP seguindo convenção existente.
- [x] Escrever RED para candidato válido.
- [x] Escrever RED para responsável atual, role inválida e membership inválida.
- [x] Escrever RED garantindo independência de Presence.
- [x] Implementar query/context read-only.
- [x] Implementar controller/endpoint.
- [x] Validar autenticação do caller.
- [x] Testar ausência de mutations, audit e broadcast.
- [x] Testar revalidação no `treatment:transfer`.
- [x] Verificar plano/query para evitar N+1.
- [x] Executar testes focados.
- [x] Executar `mix format --check-formatted`.
- [x] Executar `mix precommit`.
- [x] Executar `git diff --check`.
- [x] Registrar evidências.
- [x] Marcar como `delivered`.
- [x] Aguardar revisão humana.

## Out of scope

- Modal no frontend.
- Select de agentes.
- Redesign do chat.
- Presence como autorização.
- Alteração de lifecycle.
- Alteração de `treatment:transfer` para confiar na lista.
- Novos campos de User sem necessidade comprovada.
- Migration sem necessidade comprovada.
- Deploy.

## Possible solution

Criar uma query read-only no contexto `Chat.Treatments` que utilize os mesmos critérios de elegibilidade já existentes para transferência e expor o resultado por HTTP em contrato mínimo. O comando de transferência continua independente e revalida todas as regras no momento da mutation.

## Branch sugerida

`feat/treatment-transfer-eligible-agents`

## Próxima story

Implementar modal e UX de transferência da Tratativa.

## Comments

@Antigravity 2026-08-22
Story implementada e entregue para revisão humana:
- `Chat.Treatments.list_transfer_candidates/2`: consulta read-only com query única (zero N+1), que valida caller room membership, autorização "treatment.transfer", status "in_progress", ownership do caller e filtra membros da sala com role "logistics_agent", excluindo o responsável atual e ordenando por username ASC.
- `ChatWeb.TreatmentTransferAgentController` e rota `GET /api/rooms/:room_id/transfer-agents` no escopo autenticado: serializa `%{agents: [%{id: ..., username: ...}]}` e mapeia erros estáveis (400, 403, 404, 422).
- Três regressões explícitas cobertas e validadas:
  1. Nenhum candidato elegível na sala -> Retorna status 200 com `%{agents: []}`.
  2. Candidato válido na listagem que se torna inválido antes da mutação (saiu da sala) -> `treatment:transfer` revalida via Phoenix Channel, rejeita com `invalid_target_agent`, emite 0 broadcasts e preserva o estado.
  3. Invariante fundamental: todos os candidatos retornados respeitam estritamente os critérios de target exigidos por `transfer_agent_for_room/3` (logistics role, membership, não-responsável, não-self).
- Testes TDD completos cobrindo contagem constante de queries (Telemetry), ausência de mutações/auditoria e autenticação da rota.
- `mix precommit`: 564 testes passando (100%), Credo sem issues (strict), formatação limpa e compilação sem warnings.
- `git diff --check`: limpo.

## Attachments
