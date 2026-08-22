---
title: Implementar Treatment Header e UI de ownership
type: feature
estimate: "3"
tags: [frontend, chat, treatments, carbon, ownership]
created: "2026-08-22T01:30:00Z"
modified: "2026-08-22T03:05:17Z"
author: JuruSysadmin
status: delivered
started: "2026-08-22T01:31:46Z"
finished: "2026-08-22T03:05:17Z"
delivered: "2026-08-22T03:05:17Z"
---

## Problem statement

A interface da Tratativa precisa apresentar um cabeçalho claro com o estado
atual e as ações de ownership no contexto correto da conversa. A UI deve usar
o `TreatmentState` persistido e as capacidades de ownership já calculadas, sem
duplicar autorização ou alterar estado de forma otimista.

## Scope

- Criar um `TreatmentHeader` responsável por status, responsável atual e ações.
- Integrar a UI de ownership ao cabeçalho sem remontar a conversa.
- Reutilizar `TreatmentOwnershipActions` e `TreatmentState` existentes.
- Preservar identidade, matriz de capacidades, pending/error e eventos realtime.
- Usar componentes e tokens Carbon já adotados pelo frontend.
- Manter a transferência condicionada à fonte válida de agentes elegíveis.

## Out of scope

- Novos comandos Phoenix ou eventos realtime.
- Alterações no backend, autorização ou domínio de Treatments.
- Optimistic update.
- Definição de uma fonte nova de agentes elegíveis.
- Redesign completo do `CarbonAiChatPanel`.

## Acceptance

- [x] O cabeçalho exibe o status atual da Tratativa com texto de apresentação.
- [x] O cabeçalho exibe o agente responsável quando houver um responsável.
- [x] O cabeçalho trata uma Tratativa sem responsável sem quebrar a renderização.
- [x] As ações exibidas respeitam a matriz de capacidades já implementada.
- [x] Pending e erros continuam visíveis no contexto do cabeçalho.
- [x] Eventos realtime atualizam o cabeçalho sem optimistic update.
- [x] A conversa não é desmontada/remontada ao executar uma ação.
- [x] Testes focados, TypeScript, lint, build e `git diff --check` passam.

## Tasks

- [x] Mapear o contrato visual atual do `CarbonAiChatPanel` e `TreatmentState`.
- [x] Escrever testes RED do `TreatmentHeader` para status e responsável.
- [x] Implementar o componente usando Carbon e composição.
- [x] Integrar `TreatmentOwnershipActions` ao header sem duplicar comandos.
- [x] Cobrir estados sem responsável, pending, erro e atualização realtime.
- [x] Executar testes focados, TypeScript, lint, build e diff check.
- [x] Marcar como delivered e aguardar revisão humana.

- [x] Alinhar o layout do header com grupos distintos de contexto, status, responsável e ações, sem incluir resolver/reabrir no ownership.
- [x] Exibir o nome persistido do agente responsável no snapshot e nos eventos de ownership, com fallback seguro.
- [x] Adicionar testes focados para commercial, logistics_agent, responsável atual, outro agente, resolvida e sem responsável.
- [x] Remover a duplicação do texto de status causada pelo IconIndicator e pelo texto manual.
- [x] Compactar o header em duas linhas: título/contexto + status; responsável + ações.
- [x] Atualizar testes focados para a marcação compacta e status sem duplicação.
- [x] Definir e implementar a separação entre header host e header interno do Carbon AI Chat.
- [x] Remover redundância acessível do status e desacoplar CSS de aria-label.
- [x] Adicionar testes de fallback do responsável, acessibilidade e contrato de configuração.
- [x] Limpar explicitamente assigned_agent_username no handler de treatment:unassigned.
- [x] Adicionar testes verticais do CarbonAiChatPanel integrando TreatmentHeader e ChatCustomElement com ações do canal.
- [x] Cobrir erro de ownership no painel e fluxo real Phoenix Channel -> useRoomChannel -> TreatmentHeader com eventos realtime.
## Comments
@JuruSysadmin 2026-08-22
Implementação concluída na branch feat/treatment-header-ownership-ui. O CarbonAiChatPanel agora usa TreatmentHeader com pedido, protocolo, status Carbon IconIndicator, responsável e TreatmentOwnershipActions. A matriz de capabilities existente permanece responsável pela visibilidade das ações; transferAgents é opcional e não é inventado. Eventos realtime continuam atualizando TreatmentState, que alimenta o header. Testes focados: 34 passando em 5 arquivos; npx tsc -b, npm run lint -- --quiet, npm run build e git diff --check passaram. Build mantém apenas avisos preexistentes de @position-try, chunks grandes e eval em dependências. Story permanece started aguardando revisão humana.

@JuruSysadmin 2026-08-22
Contrato visual confirmado pelo usuário: header contém pedido/protocolo, status, responsável e TreatmentOwnershipActions; resolver e reabrir permanecem fora do Ownership UI. Ações: logistics_agent pode assumir Tratativa open livre; responsável pode liberar/transferir em in_progress; commercial, outro agente, resolvida e encerrada não exibem ownership.

@JuruSysadmin 2026-08-22
Contrato implementado: header separa pedido/protocolo, status, Responsável e ações; o snapshot/eventos agora carregam assigned_agent_username para exibir o nome persistido. Resolver e reabrir continuam fora do Ownership UI. Verificação: frontend 29 testes focados, tsc -b, lint e build passaram; backend mix format --check-formatted e room_channel_authorization_test (46 testes) passaram; git diff --check passou. Build reportou apenas avisos preexistentes de @position-try, chunks grandes e eval em dependências.

@JuruSysadmin 2026-08-22
Feedback visual aplicado: IconIndicator agora é a única fonte visual do status, removendo a duplicação. Header compactado com eyebrow Tratativa, pedido/protocolo e status na primeira linha; responsável e ações na segunda. Verificação: bun run test focado (5 testes), bun run lint (0 erros, warning preexistente), bun run build passou e git diff --check passou.

@JuruSysadmin 2026-08-22
Melhorias do Carbon MCP aplicadas: header interno do Carbon AI Chat desativado com header.isOn=false para evitar duplicação; status mantém IconIndicator como fonte acessível única; ações usam classes semânticas, aria-busy e feedback de loading; testes cobrem fallback do responsável e contrato de configuração. Verificação: 14 testes focados, tsc, lint, build e git diff --check passaram. Build mantém apenas avisos preexistentes de @position-try, chunks grandes e eval em dependências.

@JuruSysadmin 2026-08-22
Correção semântica e testes verticais concluídos: tratamento de desatribuição em treatment:unassigned agora limpa explicitamente assigned_agent_username=null evitando dado stale; adicionada suite vertical em CarbonAiChatPanel.test.tsx e CarbonAiChatPanel.channel.test.tsx cobrindo renderização de erros de ownership no cabeçalho e o fluxo end-to-end do Phoenix Channel com WebSocket pushes/events refletindo no TreatmentHeader. Verificação: 48 testes passando em 7 arquivos focados, tsc -b, lint e git diff --check passaram.

## Attachments
