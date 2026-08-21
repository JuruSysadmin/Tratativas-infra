---
title: Permitir transferir Tratativa diretamente para outro agente
type: feature
estimate: 3
tags: [backend, elixir, treatments, authorization, audit, concurrency, tdd]
status: delivered
modified: "2026-08-21T19:25:38Z"
started: "2026-08-21T19:16:30Z"
finished: "2026-08-21T19:23:57Z"
delivered: "2026-08-21T19:23:57Z"
---

## Problem statement

Como agente da logistica responsavel por uma Tratativa, quero transferir
atomica e diretamente o atendimento para outro agente da logistica, sem
passar por `open` e sem modelar a operacao como `unassign + assign`.

A transicao deve ser:

    in_progress / Agent A -> in_progress / Agent B

## API e contrato

Adicionar `Chat.Treatments.transfer_agent/3`:

    transfer_agent(treatment, current_agent, target_agent)

Resultados:

    {:ok, treatment, :transferred}
    {:error, :forbidden | :not_found | :not_assigned_agent |
             :invalid_target_agent | :same_agent | :invalid_status}

`current_agent` e `target_agent` sao structs autenticados. A struct de
Treatment recebida pelo caller nao e fonte de verdade.

## Autorizacao

Adicionar a capacidade `treatment.transfer` em
`Chat.Treatments.Authorization`:

- `logistics_agent`: permitido;
- `commercial`: negado.

A operacao deve usar `Authorization.authorize/2`, sem duplicar regras de role
em `Chat.Treatments`.

Somente o agente atualmente atribuido pode transferir. O agente atual precisa
ser membro da Room; se nao for, o resultado e `:not_found`.

O destino deve existir, ser `logistics_agent`, ser diferente do agente atual e
ser membro da mesma Room. Caso contrario, retornar `:invalid_target_agent`.
Nao adicionar automaticamente o destino a Room.

## Persistencia e concorrencia

A operacao deve ocorrer em uma unica transacao. Recarregar a Treatment com
`SELECT ... FOR UPDATE` e validar, nessa linha persistida, membership, status e
ownership.

Somente `in_progress` pode ser transferida. `open`, `resolved` e `closed`
retornam `:invalid_status`.

A atualizacao atomica deve preservar `status = "in_progress"`, trocar
`assigned_agent_id` para o destino e renovar `assigned_at` com
`DateTime.utc_now()`. Nao pode existir estado intermediario `open`.

A operacao deve permanecer segura contra concorrencia entre transferencias,
resolve e unassign. O vencedor e decidido pelo estado persistido sob lock.

## Auditoria

Criar exatamente um evento `treatment_transferred` na mesma transacao, com
`actor_id` igual ao agente atual. Usar o campo `metadata` existente para
registrar `previous_agent_id` e `assigned_agent_id` quando aplicavel.

Falha na insercao da auditoria deve causar rollback integral da transferencia.

## TDD e acceptance

- [ ] Escrever teste RED antes do codigo de producao.
- [ ] Atualizar e testar a permissao `treatment.transfer`.
- [ ] Agente responsavel logistics transfere para outro logistics membro.
- [ ] Commercial recebe `forbidden`.
- [ ] Agente diferente recebe `not_assigned_agent`.
- [ ] Current agent fora da Room recebe `not_found`.
- [ ] Target inexistente, commercial ou sem membership recebe `invalid_target_agent`.
- [ ] Mesmo agente recebe `same_agent`.
- [ ] Estados `open`, `resolved` e `closed` recebem `invalid_status`.
- [ ] Status permanece `in_progress`.
- [ ] Ownership e timestamp mudam atomicamente.
- [ ] Struct stale nao controla a operacao.
- [ ] Auditoria cria um `treatment_transferred` com metadata correta.
- [ ] Falha da auditoria faz rollback sem evento.
- [ ] Transferencias concorrentes produzem uma unica transicao efetiva.
- [ ] Concorrencia com resolve/unassign permanece segura.
- [ ] Treatment inexistente retorna `not_found` sem exception.
- [ ] Nenhum Channel, broadcast ou frontend e alterado.
- [ ] `mix format --check-formatted`, `mix test`, `mix precommit` e `git diff --check` passam.

## Tasks

- [x] Ler a matriz atual de autorizacao e seus testes.
- [x] Ler schemas de Treatment e AuditEvent e confirmar o campo metadata.
- [x] Ler APIs atuais de membership e os locks existentes.
- [x] Escrever o teste RED do caminho feliz.
- [x] Confirmar RED pela ausencia de `transfer_agent/3`.
- [x] Adicionar `treatment.transfer` a Authorization e testes.
- [x] Implementar `transfer_agent/3` e helper transacional.
- [x] Recarregar Treatment sob `FOR UPDATE`.
- [x] Validar current agent, target agent, membership e status persistidos.
- [x] Persistir troca de ownership e `assigned_at` em uma operacao.
- [x] Persistir auditoria `treatment_transferred` atomicamente.
- [x] Adicionar matriz de erros e testes de rollback.
- [x] Adicionar testes de estado stale e concorrencia.
- [x] Executar testes focados, format, precommit e diff check.
- [x] Marcar a story como delivered para revisao humana.
- [ ] Aguardar revisao humana antes de accepted.

## Fora do escopo

- `treatment:transfer` no Channel;
- `treatment:transferred` realtime;
- adicionar automaticamente o destino a Room;
- frontend, Presence e Carbon AI Chat.

## Stories seguintes

1. Expor transferencia via Phoenix Channel.
2. Publicar transferencia da Tratativa em realtime.
3. Integrar o lifecycle completo no frontend.

## Comments

@user 2026-08-21
Implementado na branch feat/transfer-treatment. RED observado com permissao ausente e UndefinedFunctionError; depois GREEN com transferencia atomica, ownership/status persistidos sob FOR UPDATE, membership do destino sob FOR SHARE, auditoria treatment_transferred com metadata e rollback. Verificado: mix test focado (65), mix test (526), mix format --check-formatted, mix precommit e git diff --check.

@user 2026-08-21
Verificacao final apos cobrir target inexistente e concorrencia transfer x resolve: mix precommit passou (Credo 1055 mods/funs, sem issues); mix format --check-formatted passou; mix test passou com 527 testes; git diff --check passou. Avisos de PubSub/broadcast permanecem observacoes de infraestrutura e nao alteraram o exit code.
