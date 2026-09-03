---
title: Cadastrar motivos padrão de Tratativa
type: chore
estimate: 1
tags: [backend, elixir, database, seeds]
created: "2026-08-28T15:17:00Z"
modified: "2026-08-28T15:18:00Z"
author: JuruSysadmin
status: delivered
started: "2026-08-28T15:17:30Z"
delivered: "2026-08-28T15:19:00Z"
---

# Cadastrar motivos padrão de Tratativa

## Problem statement

Como sistema, quero disponibilizar os motivos padrão de Tratativa no catálogo atual `treatment_reasons`, com suas prioridades e ordenação, para que novas instalações e ambientes locais tenham dados consistentes.

## Acceptance

- [x] A seed cadastra os 25 motivos padrão no formato atual da aplicação.
- [x] A seed é idempotente e atualiza registros existentes pelo código.
- [x] O motivo `ENTREGA_ATRASADA` possui prioridade `medium`.
- [x] A seed não tenta gravar campos ou tabelas que não existem no schema atual.
- [x] `mix run priv/repo/seeds.exs` executa sem erro.
- [x] A contagem final de motivos é 25.

## Tasks

- [x] Mapear o catálogo solicitado para `treatment_reasons`.
- [x] Implementar a seed idempotente.
- [x] Executar a seed no banco local.
- [x] Verificar contagem e prioridades persistidas.

## Fora do escopo

A tabela `regras_escalonamento_motivo` e a persistência de regras de escalonamento ficam fora desta seed porque não existem no schema atual; isso requer uma migration e uma story próprias.

## Comments

- O SQL original usa `motivos_tratativa` e `regras_escalonamento_motivo`, mas o projeto atual usa `treatment_reasons` com `code`, `label`, `priority`, `active` e `sort_order`.
