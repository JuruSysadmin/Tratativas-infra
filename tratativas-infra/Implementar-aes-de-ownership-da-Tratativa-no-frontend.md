---
title: Implementar ações de ownership da Tratativa no frontend
type: feature
created: "2026-08-21T21:57:46Z"
modified: "2026-08-22T01:05:55Z"
author: JuruSysadmin
status: delivered
estimate: "8"
started: "2026-08-21T21:58:24Z"
finished: "2026-08-22T01:05:55Z"
delivered: "2026-08-22T01:05:55Z"
---

## Problem statement

Como frontend da Tratativa, quero operar o ownership da Treatment pela interface usando os comandos Phoenix existentes e mantendo os eventos realtime como fonte de atualização do `TreatmentState`.

## Escopo

- Criar ações de Assumir, Liberar e Transferir em uma camada própria de UI, sem concentrar a lógica no `CarbonAiChatPanel`.
- Integrar os comandos Phoenix `treatment:assign_to_me`, `treatment:unassign` e `treatment:transfer`.
- Não enviar identidade, status ou timestamps controlados pelo frontend. Transferência envia somente `target_agent_id`.
- Não fazer optimistic update: comandos apenas aguardam confirmação; `TreatmentState` muda somente pelos eventos `treatment:agent_assigned`, `treatment:unassigned` e `treatment:transferred`.
- Expor pending/error por ação e bloquear clique duplicado durante a operação local.
- Mapear erros do RoomChannel para mensagens de apresentação sem exibir atoms/códigos internos.
- Investigar fonte real de agentes elegíveis para transferência. Não usar Presence ou lista hardcoded sem contrato; documentar a lacuna se não houver fonte.
- Aplicar apenas bloqueios de UX óbvios; autorização e concorrência permanecem no backend.

## Fora do escopo

Resolver, Reabrir, ServiceDesk, Presence como eligibility sem contrato, novas regras de autorização, optimistic updates, mudanças backend, novos eventos Phoenix, redesign completo do chat e deploy.

## Acceptance

- [ ] Assumir envia `treatment:assign_to_me` com payload vazio.
- [ ] Liberar envia `treatment:unassign` com payload vazio.
- [ ] Transferir envia `treatment:transfer` somente com `target_agent_id`, se houver fonte válida de agentes.
- [ ] Nenhuma ação modifica `TreatmentState` diretamente ou de forma otimista.
- [ ] Eventos realtime continuam sendo a única atualização de estado.
- [ ] Pending bloqueia clique duplicado por ação.
- [ ] Erros reais do comando encerram pending, preservam estado e exibem feedback adequado.
- [ ] Ações não implementam autorização própria do backend.
- [ ] Testes, lint, typecheck e build passam; sem commit, push, merge ou deploy.

## Tasks

- [x] Mapear contratos reais dos comandos Phoenix e razões de erro

- [x] Investigar fonte real de agentes elegíveis para transferência

- [x] Escrever testes RED do assign, unassign e transfer sem optimistic update

- [x] Implementar operações de ownership no useRoomChannel

- [x] Criar camada TreatmentOwnershipActions com pending/error e UX

- [x] Integrar ações ao Carbon sem remontar a conversa

- [x] Adicionar testes de erros, clique duplicado e atualização realtime externa

- [x] Rodar testes focados, suíte, lint, typecheck, build e diff check

- [ ] Marcar como delivered e aguardar revisão humana

- [x] Centralizar schemas Zod para commandErrorReason e snapshot inicial de Treatment
- [x] Refatorar payloads de lifecycle para safeParse e tipos confiáveis
- [x] Adicionar testes de payloads inválidos nas fronteiras unknown
- [x] Cobrir reasons conhecidos, payload malformado e timeout do comando
- [x] Tipar transfer para exigir targetAgentId e validar reply de sucesso consumido
- [x] Cobrir não-optimistic update e cliques duplicados no hook
- [x] Confirmar contrato de identidade atual: disponibilidade de current_user.id e current_user.role no frontend
- [x] Expor identidade autenticada do Chat com id e role sem duplicar autorização no frontend
- [x] Adicionar testes backend/frontend para o contrato de identidade do Chat
- [x] Atualizar documentação e executar gates focados da identidade
## Comments

@JuruSysadmin 2026-08-21
Implementação parcial concluída na branch feat/treatment-ownership-actions. Contratos reais confirmados nos cards de backend: assign_to_me/unassign com payload vazio e transfer somente com target_agent_id. Criados helpers de comandos, estado pending/error no useRoomChannel, ações assignTreatment/unassignTreatment/transferTreatment sem optimistic update e componente TreatmentOwnershipActions integrado ao CarbonAiChatPanel. Testes focados: 26 passando; npx tsc -b passou; bun run lint passou com 1 warning preexistente; bun run build passou; git diff --check passou. Lacuna: frontend não possui endpoint/fonte de agentes logísticos elegíveis; endpoints encontrados são de vendedores ERP, então Transferir não é renderizado sem transferAgents fornecidos por fonte validada. Suíte completa bun run test: 55 falhas em 24 arquivos não relacionados, principalmente MSW/fixtures de Orders, de-por, order-details e tags; nenhum teste desta story falhou. Story permanece started aguardando resolução/revisão da suíte completa.

@JuruSysadmin 2026-08-21
Ajuste adicional: commandErrorReason foi movido para api/schemas/treatmentOwnership.schemas.ts e passou a validar respostas Phoenix com Zod, usando fallback treatment_command_failed. Adicionados testes de payload válido e inválido. Verificação após o ajuste: 13 testes focados passando, bun run lint passou com 1 warning preexistente, bun run build passou e git diff --check passou. A suíte completa permanece com 55 falhas não relacionadas.

@JuruSysadmin 2026-08-21
Refatoração Zod concluída: commandErrorReason, snapshot inicial e payloads de lifecycle usam schemas compartilhados com safeParse; removidos os helpers manuais de typeof/'in' do tratamento de Treatment. Adicionados testes para respostas Phoenix sem reason, lifecycle inválido e payload não-objeto. Verificação: 31 testes focados passaram, npx tsc -b passou, npm run lint passou com 1 warning preexistente, npm run build passou com warnings preexistentes do Carbon/Vite, git diff --check passou. Suíte completa: 55 falhas em 24 arquivos não relacionados (MSW/fixtures de Orders, de-por, order-details e tags); 2074 passaram. Story permanece started e não foi marcada delivered.

@JuruSysadmin 2026-08-21
Revisão adicional concluída: adicionados testes para not_assigned_agent, erro malformado com fallback treatment_command_failed, timeout, reply de sucesso inválido e resposta válida validada por Zod. Transfer agora exige targetAgentId por overload TypeScript; a validação runtime permanece como defesa adicional. O adapter de transporte continua separado da mensagem de UI. O comando bem-sucedido somente resolve a Promise, sem alterar TreatmentState; a projeção permanece atualizada exclusivamente pelos eventos realtime. Ações pendentes permanecem bloqueadas e o teste cobre cliques duplicados. Verificação focada: 32 testes passaram, npx tsc -b passou, ESLint dos arquivos afetados passou e git diff --check passou.

@JuruSysadmin 2026-08-22
Investigação de autenticação concluída. No backend, UserSocket e Chat.Auth.Plug atribuem o struct %Chat.Accounts.User completo em current_user; portanto current_user.id e current_user.role existem no contexto Phoenix. No frontend atual, useAuthStore mantém somente token/username e useMeQuery consulta usersApi /users/me com schema contendo dados ERP, sem id nem role. O login do backend retorna user.id mas não role; o frontend não usa esse contrato diretamente e não modela esses campos. A menor disponibilização segura, se a UI precisar filtrar ações, é expor id e role no contrato autenticado já consumido pelo frontend (ou integrar explicitamente o /me do Chat), atualizar schema/tipo e usar somente esses dados para UX. Não foi adicionada autorização no frontend nem feita alteração de código nesta investigação. Bloqueio/decisão: alinhar qual serviço é a fonte oficial da sessão antes de implementar.

@JuruSysadmin 2026-08-22
Identidade do Chat exposta sem alterar o contrato ERP. Backend: GET /api/auth/me protegido por Bearer, resposta {user: {id, role}}, com role limitado ao usuário persistido e autorização mantida no backend. Frontend: chatIdentityResponseSchema, chatIdentityRequest via chatApi e useChatIdentityQuery separado do /users/me; Query key auth.chat-identity. Testes RED/GREEN: auth_controller_test 4 passando, chatIdentity.api + auth.query 12 passando; rota confirmada em mix phx.routes; npx tsc -b, mix format --check-formatted, bun run lint -- --quiet, bun run build e git diff --check passaram. Build tem apenas avisos preexistentes de dependências/chunks/eval. Nenhuma UI ou regra de autorização foi alterada.
