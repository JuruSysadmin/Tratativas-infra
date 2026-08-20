---
title: Definir matriz de permissoes da Tratativa
type: feature
estimate: 1
tags: [backend, elixir, authorization, treatments]
created: "2026-08-20T22:16:37Z"
modified: "2026-08-20T22:19:59Z"
author: JuruSysadmin
status: delivered
started: "2026-08-20T22:19:32Z"
finished: "2026-08-20T22:19:59Z"
delivered: "2026-08-20T22:19:59Z"
---

## Problem statement

Como sistema, quero ter uma matriz explicita de permissoes por papel para as
operacoes de Tratativa, para que atribuicao, resolucao, reabertura e liberacao
tenham regras de autorizacao consistentes.

Papeis suportados:

- `commercial`
- `logistics_agent`

Permissoes:

- `treatment.assign`
- `treatment.resolve`
- `treatment.reopen`
- `treatment.unassign`

Matriz:

| Permissao | commercial | logistics_agent |
| --- | ---: | ---: |
| `treatment.assign` | nao | sim |
| `treatment.resolve` | nao | sim |
| `treatment.reopen` | sim | sim |
| `treatment.unassign` | nao | sim |

Esta story define capacidade por papel. Regras contextuais, como agente
responsavel, status atual e transicao valida, permanecem em
`Chat.Treatments`.

## Possible solution

Atualizar `Chat.Treatments.Authorization` para refletir explicitamente a
matriz. `allowed?/2` deve negar papeis ou permissoes desconhecidos e
`authorize/2` deve retornar `:ok` ou `{:error, :forbidden}`.

Nao implementar nesta story atribuicao, resolucao, reabertura, liberacao,
mudancas de status, broadcast, frontend ou Carbon AI Chat.

Dependencia: adicionar papel ao usuario.

Proxima story: adicionar agente responsavel a Tratativa.

## Acceptance

- [ ] `commercial` nao possui `treatment.assign`.
- [ ] `commercial` nao possui `treatment.resolve`.
- [ ] `commercial` possui `treatment.reopen`.
- [ ] `commercial` nao possui `treatment.unassign`.
- [ ] `logistics_agent` possui as quatro permissoes.
- [ ] Papel desconhecido e sempre negado.
- [ ] Permissao desconhecida e sempre negada.
- [ ] `authorize/2` retorna `:ok` para operacoes permitidas.
- [ ] `authorize/2` retorna `{:error, :forbidden}` para operacoes negadas.
- [ ] O modulo nao depende de uma instancia especifica de `Treatment`.
- [ ] Regras contextuais permanecem em `Chat.Treatments`.
- [ ] Os testes cobrem integralmente a matriz.
- [ ] `mix format --check-formatted` passa.
- [ ] `mix test` passa.
- [ ] `mix precommit` passa.

## Tasks

- [x] Ler `Chat.Treatments.Authorization` e os testes existentes.
- [x] Atualizar a matriz de permissoes por papel.
- [x] Garantir negacao para papel ausente ou desconhecido.
- [x] Garantir negacao para permissao desconhecida.
- [x] Atualizar os testes da matriz e de `authorize/2`.
- [x] Executar formatacao e verificacoes do projeto.
- [x] Executar `mix test` e `mix precommit`.
- [x] Revisar os criterios de aceitacao e entregar para revisao humana.

## Comments
@JuruSysadmin 2026-08-20
Implementado em Chat.Treatments.Authorization. commercial possui somente treatment.reopen; logistics_agent possui assign, resolve, reopen e unassign. Papeis e permissoes desconhecidos retornam {:error, :forbidden}. Testes focados: 6 passaram; mix precommit: 440 testes passaram e Credo sem issues. Commit 639264b publicado em feat/centralize-treatment-authorization.

## Attachments
