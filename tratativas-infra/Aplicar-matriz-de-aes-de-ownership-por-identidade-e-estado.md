---
title: Aplicar matriz de ações de ownership por identidade e estado
type: feature
estimate: "3"
tags: [frontend, chat, treatments, authorization, ux]
created: "2026-08-22T01:13:41Z"
modified: "2026-08-22T01:18:52Z"
author: JuruSysadmin
status: started
started: "2026-08-22T01:14:21Z"
---

## Problem statement

As ações de ownership da Tratativa devem refletir a identidade autenticada e o
estado persistido da Tratativa. O frontend não deve exibir ações para usuários
ou estados que não possam executar a operação, mas o backend continua sendo a
autoridade final para autorização, ownership e concorrência.

## Scope

- Aplicar a matriz de capacidades `canAssign`, `canUnassign` e `canTransfer`.
- Usar somente a identidade do Chat validada por Zod (`id` e `role`).
- Falhar fechado quando a identidade estiver ausente ou inválida.
- Manter comandos, eventos realtime, pending/error e ausência de optimistic update.
- Não criar autorização nova nem alterar o backend de Treatments.

## Decision matrix

| Caso | Assumir | Liberar | Transferir |
| --- | --- | --- | --- |
| `commercial` + `open` | não | não | não |
| `logistics_agent` + `open` + livre | sim | não | não |
| `logistics_agent` responsável + `in_progress` | não | sim | sim |
| outro `logistics_agent` + `in_progress` | não | não | não |
| `resolved` ou `closed` | não | não | não |
| identidade ausente/inválida | não | não | não |

A transferência também exige uma fonte válida de agentes elegíveis, conforme o
contrato já existente da UI.

## Acceptance

- [ ] `commercial` nunca vê ações de ownership.
- [ ] `logistics_agent` pode assumir somente Tratativa `open` sem responsável.
- [ ] Somente o agente responsável pode liberar ou transferir uma Tratativa `in_progress`.
- [ ] Tratativas `resolved` e `closed` não exibem ações de ownership.
- [ ] Identidade ausente ou inválida resulta em nenhuma ação visível.
- [ ] A matriz é coberta pelos cenários RED-01 a RED-06.
- [ ] O frontend não altera `TreatmentState` diretamente nem implementa autorização de backend.
- [ ] TypeScript, testes focados, lint, build e `git diff --check` passam.

## Tasks

- [x] Criar testes RED para a função pura de capacidades usando RED-01 a RED-06.
- [x] Implementar a matriz de capacidades com fail closed.
- [x] Integrar identidade autenticada ao componente/hook de ações.
- [x] Atualizar testes de renderização para a visibilidade correta dos botões.
- [x] Confirmar que comandos e eventos realtime permanecem inalterados.
- [x] Executar testes focados, TypeScript, lint, build e diff check.
- [ ] Marcar como delivered e aguardar revisão humana.

## Comments
@JuruSysadmin 2026-08-22
Implementação concluída na branch feat/treatment-ownership-capabilities. Criada função pura de capacidades com validação Zod da identidade e fail closed. RED-01 a RED-06 cobertos; 17 testes da matriz/componente e 32 testes focados passaram. npx tsc -b, ESLint dos arquivos afetados, bun run build e git diff --check passaram. Build mantém apenas avisos preexistentes de @position-try, chunks grandes e eval em dependências. Story permanece started aguardando revisão humana.

## Attachments
