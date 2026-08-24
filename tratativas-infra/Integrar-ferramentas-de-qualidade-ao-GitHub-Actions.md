---
title: Integrar ferramentas de qualidade ao GitHub Actions
type: chore
created: "2026-08-24T15:31:04Z"
modified: "2026-08-24T15:33:37Z"
author: JuruSysadmin
status: delivered
started: "2026-08-24T15:30:43Z"
finished: "2026-08-24T15:34:01Z"
delivered: "2026-08-24T15:34:01Z"
---

## Problem statement

## Possible solution

## Comments
@JuruSysadmin 2026-08-24
Atualizado .github/workflows/elixir.yaml: job test executa mix test e novo job quality executa Credo, Dialyzer e Sobelow em etapas separadas; Dialyzer e Sobelow usam always() para preservar todos os diagnósticos. Validação: YAML parse via Ruby passou; mix test --no-start passou com 609 testes; Credo retornou 2 achados preexistentes; Sobelow retornou CSP ausente em lib/chat_web/router.ex; Dialyzer retornou 6 warnings preexistentes de Ecto.Multi; git diff --check passou.

## Attachments

## Tasks

- [x] Criar um job quality no workflow existente com Credo, Dialyzer e Sobelow.

- [x] Manter o job de testes com PostgreSQL e separar a execução de mix test das análises estáticas.

- [x] Validar a sintaxe do workflow e executar localmente as etapas equivalentes disponíveis.
