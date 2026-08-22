---
title: Integrar comandos de resolução no useRoomChannel
type: feature
created: "2026-08-21T23:29:08Z"
modified: "2026-08-22T16:11:47Z"
author: JuruSysadmin
status: accepted
started: "2026-08-21T23:29:44Z"
finished: "2026-08-21T23:52:31Z"
delivered: "2026-08-21T23:52:31Z"
accepted: "2026-08-22T16:11:47Z"
---

## Problem statement

O frontend já mantém `TreatmentState` sincronizado pelos eventos realtime e possui os comandos de ownership. Esta story adiciona `resolveTreatment()` e `reopenTreatment()` ao `useRoomChannel`, usando `treatment:resolve` e `treatment:reopen`, sem optimistic update.

## Acceptance

- [ ] `resolveTreatment()` e `reopenTreatment()` são expostos pelo hook.
- [ ] Ambos enviam payload `{}` e validam replies `ok` com Zod.
- [ ] Replies inválidos resultam em `treatment_command_failed`; timeout resulta em `treatment_command_timeout`.
- [ ] Reasons reais de erro são preservados, sem mensagens de UI no hook.
- [ ] Pending bloqueia comandos duplicados e encerra em sucesso, erro ou timeout.
- [ ] Replies de sucesso não alteram `TreatmentState`; somente `treatment:resolved` e `treatment:reopened` atualizam a projeção.
- [ ] Eventos externos continuam funcionando sem comando local.
- [ ] Não há alteração no backend, componentes visuais, listeners duplicados ou regras de autorização no frontend.
- [ ] Testes focados, TypeScript, ESLint dos arquivos afetados, build e `git diff --check` passam.

## Tasks

- [x] Confirmar contratos reais de payload, replies e reasons no `RoomChannel` e testes backend.
- [x] Escrever testes RED do adapter para resolve/reopen, replies inválidos, errors e timeout.
- [x] Criar/reutilizar schemas Zod do reply real.
- [x] Implementar `treatmentResolution.commands.ts` com payload vazio e erro tipado.
- [x] Escrever testes RED do `useRoomChannel` para pending, duplicidade e ausência de optimistic update.
- [x] Integrar `resolveTreatment()` e `reopenTreatment()` no hook.
- [x] Confirmar que broadcasts externos e eventos vencedores após erro local atualizam o lifecycle.
- [x] Executar testes focados, TypeScript, ESLint, build e diff check.
- [x] Marcar como delivered e aguardar revisão humana.

- [x] Adicionar fluxo local completo de reopenTreatment sem optimistic update
- [x] Adicionar regressão contra reopenTreatment duplicado enquanto pending
- [x] Refatorar FakePush para declarar joinResponse explicitamente
- [x] Resetar phoenixState e mocks em afterEach e renomear teste de broadcasts
- [x] Executar testes focados, TypeScript, ESLint, build e git diff --check
- [x] Criar módulo compartilhado de types da Treatment
- [x] Mover tipos dos hooks e atualizar imports sem alterar contratos
- [x] Verificar testes, TypeScript, lint, build e diff check
## Possible solution

## Comments
@JuruSysadmin 2026-08-21
Implementação concluída na camada funcional frontend. Contratos reais confirmados no RoomChannel: resolve envia {} e retorna treatment_id/status resolved/resolved_by_id/resolved_at; reopen envia {} e retorna treatment_id/status in_progress/assigned_agent_id/assigned_at. Reasons confirmados: resolve forbidden, not_assigned_agent, invalid_status, not_found; reopen forbidden, not_found, invalid_status. Criados schemas Zod e adapter treatmentResolution.commands.ts com normalização de erro e timeout. useRoomChannel expõe resolveTreatment(), reopenTreatment() e treatmentResolutionState, com guarda por ref contra duplicidade e sem optimistic update. Testes do hook cobrem reply sem alteração de TreatmentState, timeout, erro local seguido de broadcast vencedor e eventos externos. Verificação final focada: 43 testes passando, TypeScript, ESLint afetado, build e git diff --check passaram. Suíte completa não executada para evitar o timeout conhecido; nenhuma alteração no backend.

@JuruSysadmin 2026-08-21
Correção de preservação do workspace: o teste pré-existente useRoomChannel.test.ts foi mantido intacto e o teste novo foi separado em useRoomChannel.resolution.test.tsx. Verificação final focada passou com 47 testes em 6 arquivos; TypeScript, ESLint afetado e git diff --check passaram. O build já havia passado após a integração de produção; a renomeação afetou somente arquivos de teste. Story permanece delivered aguardando revisão humana.

@JuruSysadmin 2026-08-21
Review humano incorporado: adicionadas regressões para o fluxo local de reopen sem optimistic update e para reopen duplicado; FakePush agora recebe joinResponse explícito; estado hoisted e mocks são resetados em afterEach; nomenclatura diferencia broadcasts de comandos. Evidências: npm run test:run -- src/modules/chat/hooks/useRoomChannel.resolution.test.tsx (6 testes passando); suíte relacionada (3 arquivos, 27 testes passando); ESLint do arquivo alterado passou; npm run build passou com avisos preexistentes de @position-try, chunks grandes e eval em dependências; git diff --check passou. Suíte completa não foi executada por não ser necessária para este review e pelo timeout conhecido registrado anteriormente.

@JuruSysadmin 2026-08-21
Tipos da Treatment centralizados em frontend/src/modules/chat/types/treatment.types.ts. Os hooks treatmentLifecycle.state.ts, treatmentOwnership.commands.ts, treatmentResolution.commands.ts e useRoomChannel.ts não declaram mais os tipos compartilhados; componentes e testes foram atualizados para importar do módulo. Sem alteração de comportamento. Verificação: npx tsc -b passou; testes focados em 5 arquivos passaram (45 testes); npm run lint -- --quiet passou; npm run build passou com avisos já existentes de chunks/eval em dependências; git diff --check passou.

## Attachments
