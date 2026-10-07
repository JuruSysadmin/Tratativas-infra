---
title: Alinhar testes e contrato realtime ao status pending_confirmation
type: chore
created: "2026-09-18T00:47:02Z"
modified: "2026-09-23T13:31:39Z"
author: JuruSysadmin
status: started
started: "2026-09-23T13:27:46Z"
---

## Problem statement
`Treatments.resolve` grava `pending_confirmation`, o React já trata esse status, mas testes Elixir e `docs/realtime-contract.md` ainda esperam `"resolved"`. A suíte falha (~22 testes) e o contrato documentado está stale.

## Possible solution
Atualizar asserções e o contrato para refletir o comportamento real: resolve → `pending_confirmation` (evento `treatment:resolved`); confirm → status seguinte conforme o fluxo atual. Não mudar produção neste chore — só testes + docs. Fila continua expondo count alias `"resolved"` ← `pending_confirmation` se for o contrato da API.

## Acceptance
- Testes de treatments/channels/queue que falhavam por status passam.
- `docs/realtime-contract.md` lista `pending_confirmation` e descreve resolve vs confirm.
- Nenhum comportamento de produção alterado (sem mudança em `resolution_changeset` / lifecycle).
- `mix test` nos arquivos tocados passa.

## Tasks
- [x] Mapear asserções `"resolved"` pós-resolve vs pós-confirm nos testes
- [x] Atualizar treatments_test, room_channel_authorization_test, realtime_contract_channel_test, treatment_queue_controller_test
- [x] Atualizar docs/realtime-contract.md
- [ ] Rodar mix test nos arquivos tocados e corrigir resíduos
- [ ] Marcar delivered e aguardar aceite do PM

## Comments

@JuruSysadmin 2026-09-23
Testes e docs atualizados. mix test bloqueado: Postgres local 5432 indisponível (só docker banco-grid em 5433 com credenciais diferentes). Aguardando DB de teste para rodar verificação.
