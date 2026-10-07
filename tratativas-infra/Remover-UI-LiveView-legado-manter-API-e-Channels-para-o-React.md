---
title: Remover UI LiveView legado; manter API e Channels para o React
type: chore
created: "2026-09-18T00:20:24Z"
modified: "2026-09-18T00:24:32Z"
author: JuruSysadmin
status: accepted
started: "2026-09-18T00:20:33Z"
finished: "2026-09-18T00:24:32Z"
delivered: "2026-09-18T00:24:32Z"
accepted: "2026-09-18T00:24:32Z"
---

## Problem statement
A UI Phoenix LiveView (login cookie, /chat, /tratativas, /home, /perfil) é legado. O produto usa o React em /home/jurusysadmin/chat/frontend via JWT + /socket. Manter as duas superfícies gera drift de contrato e custo de manutenção.

## Possible solution
Remover a árvore LiveView, sessão browser, layouts/core_components, assets/hooks LV e testes associados. Manter API /api/*, Channels, Presence, Auth JWT e LiveDashboard em dev. Host Phoenix fica API-only (sem HTML de produto em /).

## Acceptance
- Nenhum live_session / LoginLive / ChatLive / TreatmentLive / HomeLive / ProfileLive no router.
- SessionController e UserAuth removidos.
- Endpoint sem socket /live de produto (LiveDashboard pode permanecer em /dev).
- API, Channels, Presence e auth JWT intactos; testes de canal/API passam.
- Testes e assets exclusivos de LiveView removidos.
- mix compile e mix test (suíte restante) passam.

## Tasks
- [x] Remover rotas LiveView e SessionController do router
- [x] Remover lib/chat_web/live/ e módulos LV-only (UserAuth, layouts, core_components, TypingManager, order_presentation, time)
- [x] Limpar chat_web.ex, endpoint (/live) e assets JS/CSS de LiveView
- [x] Remover testes LiveView/componentes/carbon/session; ajustar presence_test
- [x] Rodar mix compile e mix test; corrigir quebras
- [x] Marcar delivered e aguardar aceite do PM
