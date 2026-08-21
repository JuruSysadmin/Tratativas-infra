---
modified: "2026-08-21T00:04:06Z"
status: delivered
started: "2026-08-20T23:54:23Z"
finished: "2026-08-21T00:04:06Z"
delivered: "2026-08-21T00:04:06Z"
---

# Adicionar agente responsável à Tratativa

**Type:** Feature
**Labels:** `backend`, `elixir`, `treatments`, `database`, `tdd`
**Estimate:** 2

## Problem statement

Como sistema, quero persistir qual agente da logística é responsável por uma Tratativa, para que a atribuição continue válida mesmo quando o agente estiver offline ou desconectado.

Hoje a `Treatment` possui `opened_by`, mas não possui um responsável pelo atendimento.

Uma Tratativa deve poder existir inicialmente sem agente atribuído.

## Estratégia de desenvolvimento

Implementar esta story usando **TDD**.

Fluxo obrigatório:

```text
RED
↓
escrever teste que representa o comportamento desejado
↓
executar teste e confirmar falha pelo motivo esperado

GREEN
↓
implementar o mínimo necessário
↓
executar teste até passar

REFACTOR
↓
melhorar implementação sem alterar comportamento
↓
executar novamente os testes
```

Não criar migration/schema completos antes de definir os testes principais.

## Possible solution

Adicionar inicialmente à `Treatment`:

```text
assigned_agent_id
assigned_at
```

`assigned_agent_id` deve referenciar `users.id`.

Adicionar associação Ecto:

```elixir
belongs_to :assigned_agent, Chat.Accounts.User
```

A atribuição deve ser estado persistido de domínio.

Não usar Phoenix Presence como fonte de verdade para o responsável.

Exemplo:

```text
ANA assume Tratativa
        ↓
assigned_agent_id = ANA.id
assigned_at = timestamp
        ↓
ANA perde conexão
        ↓
Presence = offline

MAS

assigned_agent continua ANA
```

Nesta story, não implementar ainda o comando:

```text
treatment:assign_to_me
```

---

## Testes TDD recomendados

### TDD-01 — Tratativa pode existir sem agente

Escrever primeiro um teste garantindo que a modelagem continua aceitando uma Tratativa sem responsável.

Exemplo conceitual:

```elixir
test "treatment can exist without an assigned agent" do
  treatment = treatment_fixture()

  assert treatment.assigned_agent_id == nil
  assert treatment.assigned_at == nil
end
```

**RED esperado**

Antes da implementação, os campos ainda não existem.

**Objetivo**

Garantir que a nova associação seja opcional.

---

### TDD-02 — Tratativa pode persistir um agente responsável

Criar um usuário com:

```text
role = logistics_agent
```

e persistir sua associação à Treatment.

Exemplo conceitual:

```elixir
test "treatment can persist an assigned agent" do
  agent = user_fixture(role: "logistics_agent")
  treatment = treatment_fixture()

  assert {:ok, treatment} =
           Treatments.assign_agent_fields(
             treatment,
             agent,
             DateTime.utc_now()
           )

  assert treatment.assigned_agent_id == agent.id
  assert treatment.assigned_at != nil
end
```

O nome da função é apenas ilustrativo.

Antes de implementar, verificar a API atual de `Chat.Treatments` e escolher um nome coerente.

Não criar uma API pública definitiva apenas para satisfazer o teste se ela pertencer à próxima story.

---

### TDD-03 — Associação `assigned_agent` pode ser preloadada

Testar a associação Ecto real.

```elixir
test "assigned agent can be preloaded from a treatment" do
  agent = user_fixture(role: "logistics_agent")
  treatment = treatment_fixture(assigned_agent: agent)

  treatment =
    Repo.get!(Treatment, treatment.id)
    |> Repo.preload(:assigned_agent)

  assert treatment.assigned_agent.id == agent.id
  assert treatment.assigned_agent.role == "logistics_agent"
end
```

**Objetivo**

Não testar somente o UUID armazenado. Garantir que a associação Ecto funciona.

---

### TDD-04 — FK rejeita usuário inexistente

Esse teste deve validar a proteção do PostgreSQL.

Exemplo conceitual:

```elixir
test "assigned_agent_id must reference an existing user" do
  treatment = treatment_fixture()

  invalid_user_id = Ecto.UUID.generate()

  changeset =
    Ecto.Changeset.change(
      treatment,
      assigned_agent_id: invalid_user_id
    )

  assert {:error, changeset} = Repo.update(changeset)

  assert "does not exist" in errors_on(changeset).assigned_agent_id
end
```

Para isso, o changeset usado no teste precisa mapear a `foreign_key_constraint/3` correspondente.

Se a API interna da Treatment já tiver um changeset específico para atribuição, utilizar esse changeset.

---

### TDD-05 — `assigned_at` é persistido

Não testar apenas `assigned_agent_id`.

```elixir
test "assignment timestamp is persisted" do
  agent = user_fixture(role: "logistics_agent")
  assigned_at = DateTime.utc_now() |> DateTime.truncate(:second)

  treatment =
    treatment_fixture(
      assigned_agent_id: agent.id,
      assigned_at: assigned_at
    )

  persisted = Repo.get!(Treatment, treatment.id)

  assert persisted.assigned_at == assigned_at
end
```

Utilizar a precisão temporal realmente definida pela migration/schema.

Se o projeto usa `:utc_datetime_usec`, adaptar o teste à precisão correta.

---

### TDD-06 — Desconexão/Presence não altera atribuição

Não precisa simular toda uma conexão Phoenix nesta story.

O teste deve proteger conceitualmente que a atribuição é persistida independentemente do Presence.

Pode ser suficiente demonstrar:

```elixir
test "assignment remains persisted independently of presence state" do
  agent = user_fixture(role: "logistics_agent")
  treatment = treatment_fixture(assigned_agent: agent)

  persisted =
    Repo.get!(Treatment, treatment.id)
    |> Repo.preload(:assigned_agent)

  assert persisted.assigned_agent_id == agent.id
end
```

Não acoplar `Treatment` a `Phoenix.Presence`.

O critério principal é garantir que nenhum código da modelagem de atribuição dependa de Presence.

---

### TDD-07 — Usuário pode ser removido conforme estratégia de FK escolhida

Antes de implementar, decidir conscientemente o comportamento da FK.

Duas opções aceitáveis:

#### Opção A — impedir exclusão

```text
Treatment aponta para User
↓
User não pode ser apagado enquanto estiver referenciado
```

Teste deve provar que a exclusão falha.

#### Opção B — `nilify_all`

```text
Treatment aponta para User
↓
User é removido
↓
assigned_agent_id = nil
```

Teste deve provar que a Treatment permanece e a referência vira `nil`.

Não utilizar:

```text
on_delete: :delete_all
```

porque excluir um usuário não deve excluir uma Tratativa.

Registrar no card qual estratégia foi escolhida.

---

### TDD-08 — Changeset comum não permite atribuição arbitrária

Se a `Treatment` possui changeset usado para criação/edição comum, testar que:

```elixir
%{
  assigned_agent_id: "qualquer-id"
}
```

não pode ser mass-assigned por esse changeset.

Exemplo conceitual:

```elixir
test "regular treatment changeset does not mass-assign assigned_agent_id" do
  agent = user_fixture(role: "logistics_agent")

  changeset =
    Treatment.changeset(%Treatment{}, %{
      order_id: 123,
      assigned_agent_id: agent.id
    })

  refute Ecto.Changeset.get_change(changeset, :assigned_agent_id)
end
```

Adaptar ao changeset real existente.

A atribuição deve possuir uma API/changeset específico do domínio.

---

### TDD-09 — Changeset específico aceita atribuição

Caso seja criado um changeset dedicado, testar diretamente:

```elixir
test "assignment changeset accepts agent and timestamp" do
  agent = user_fixture(role: "logistics_agent")
  treatment = treatment_fixture()

  changeset =
    Treatment.assignment_changeset(
      treatment,
      %{
        assigned_agent_id: agent.id,
        assigned_at: DateTime.utc_now()
      }
    )

  assert changeset.valid?
end
```

Não colocar ainda:

```text
Authorization.authorize(...)
```

nesse changeset.

Autorização pertence à operação de domínio da próxima story.

---

## Testes que NÃO pertencem a esta story

Não adicionar ainda testes para:

```text
commercial não pode assumir
logistics_agent pode assumir
dois agentes tentando simultaneamente
already_assigned
treatment:assign_to_me
broadcast treatment:agent_joined
status open → in_progress
```

Esses comportamentos pertencem às próximas stories.

Esta story testa somente:

```text
estrutura persistida
associação
integridade
API interna de mudança
```

---

## Regras

A Tratativa deve aceitar:

```text
assigned_agent = nil
```

antes de alguém assumir.

O campo `assigned_agent_id` deve aceitar somente um usuário existente.

A migration deve definir comportamento explícito de FK para exclusão do usuário.

Preferir uma regra que preserve a integridade histórica da Tratativa.

Não implementar `TreatmentAssignment` nesta story.

O primeiro modelo será uma atribuição atual simples.

Histórico de transferência pode ser evoluído posteriormente caso o produto precise.

---

## Acceptance

* [ ] Desenvolvimento foi iniciado pelos testes TDD.
* [ ] Foi observado RED antes da implementação principal.
* [ ] `Treatment` possui `assigned_agent_id`.
* [ ] `Treatment` possui `assigned_at`.
* [ ] `assigned_agent_id` referencia `users.id`.
* [ ] Existe associação `belongs_to :assigned_agent`.
* [ ] Tratativa pode existir sem agente atribuído.
* [ ] Um usuário existente pode ser associado à Treatment no nível de persistência.
* [ ] O agente associado pode ser preloadado.
* [ ] `assigned_at` é persistido corretamente.
* [ ] FK rejeita referência a usuário inexistente.
* [ ] A atribuição não depende de Phoenix Presence.
* [ ] Desconexão não altera estado persistido.
* [ ] Migration possui FK e índice adequados.
* [ ] Estratégia `on_delete` foi definida e testada.
* [ ] Changeset comum não permite mass assignment indevido do agente.
* [ ] Existe API/changeset interno apropriado para alteração da atribuição, caso necessário.
* [ ] Não foi adicionada lógica de autorização ao schema.
* [ ] Testes cobrem Treatment sem agente.
* [ ] Testes cobrem Treatment com agente.
* [ ] Testes cobrem preload.
* [ ] Testes cobrem integridade da FK.
* [ ] Testes cobrem persistência de `assigned_at`.
* [ ] `mix format --check-formatted` passa.
* [ ] `mix test` passa.
* [ ] `mix precommit` passa.

---

## Tasks

* [x] Ler `Chat.Treatments.Treatment`, `Chat.Treatments` e migrations atuais.
* [x] Identificar fixtures/helpers existentes.
* [x] Escrever TDD-01 e executar confirmando RED.
* [x] Escrever TDD-02 e executar confirmando RED.
* [x] Escrever TDD-03 e executar confirmando RED.
* [x] Escrever teste de integridade da FK.
* [x] Definir estratégia de `on_delete`.
* [x] Escrever teste da estratégia de `on_delete`.
* [x] Escrever teste contra mass assignment.
* [x] Criar migration.
* [x] Adicionar `assigned_agent_id`.
* [x] Adicionar `assigned_at`.
* [x] Adicionar associação `assigned_agent`.
* [x] Adicionar constraint/foreign key mapping no changeset apropriado.
* [x] Implementar o mínimo necessário até os testes ficarem GREEN.
* [x] Refatorar mantendo testes verdes.
* [x] Executar testes focados da Treatment.
* [x] Executar `mix format --check-formatted`.
* [x] Executar `mix test`.
* [x] Executar `mix precommit`.
* [x] Revisar Acceptance Criteria.
* [x] Marcar story como `delivered`, deixando aceite para revisão humana.

---

- [x] Registrar decisões de implementação: FK com `on_delete: :nilify_all` e changeset dedicado interno `assignment_changeset/2`.
- [x] Implementação: adicionar migration, campos, associação e changeset dedicado interno sem autorização no schema.
- [x] Verificação: executar testes focados, `mix format --check-formatted`, `mix test` e `mix precommit`.
## Ordem TDD sugerida

```text
TDD-01 Treatment sem agente
          ↓
TDD-02 persistir agente
          ↓
TDD-03 preload
          ↓
TDD-04 foreign key
          ↓
TDD-05 assigned_at
          ↓
TDD-07 estratégia on_delete
          ↓
TDD-08 impedir mass assignment
          ↓
TDD-09 changeset específico
          ↓
GREEN completo
          ↓
REFACTOR
          ↓
precommit
```

---

## Fora do escopo

Não implementar nesta story:

```text
treatment:assign_to_me
Authorization.authorize(user, "treatment.assign")
treatment:agent_joined
concorrência de atribuição
already_assigned
mudança para in_progress
treatment:resolve
treatment:reopen
treatment:unassign
transferência
frontend
Carbon AI Chat
```

---

## Dependências

Depende de:

```text
[Feature] Adicionar papel ao usuário
[Feature] Centralizar autorização de Tratativas
```

## Próxima story

```text
[Feature] Permitir que agente assuma Tratativa
```

Essa próxima story deverá combinar:

```text
Authorization.authorize(user, "treatment.assign")
          +
regra contextual da Treatment
          +
atribuição atômica
```

e usar o usuário autenticado como agente.

## Comments

@user 2026-08-20
Decisões de alinhamento confirmadas pelo PM: usar `on_delete: :nilify_all` na FK de `assigned_agent_id`; criar changeset dedicado e interno, por exemplo `assignment_changeset/2`; mover a story da icebox para a prioridade. Permanecem fora do escopo autorização, comando `treatment:assign_to_me`, concorrência e frontend.

@user 2026-08-21
Implementação concluída na branch `feat/add-treatment-assigned-agent`: migration `20260820235854_add_assignment_fields_to_treatments.exs`, campos `assigned_agent_id`/`assigned_at`, associação `assigned_agent` e `Treatment.assignment_changeset/2`. A FK usa `on_delete: :nilify_all`; o changeset comum não inclui os campos; não foi adicionada autorização nem dependência de Presence. Evidência: TDD-01 RED por campo ausente; TDD-02 RED por função ausente; depois `mix format --check-formatted`, `mix test` (449 testes) e `mix precommit` passaram; `git diff --check` passou. Warnings de PubSub/broadcast existentes não causaram falha.
