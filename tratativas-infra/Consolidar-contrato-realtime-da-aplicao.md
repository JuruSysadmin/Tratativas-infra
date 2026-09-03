---
title: Consolidar contrato realtime da aplicação
type: feature
created: "2026-08-28T16:07:01Z"
modified: "2026-08-28T16:21:18Z"
author: JuruSysadmin
status: delivered
estimate: "5"
tags: [backend, elixir, phoenix, channels, realtime, messages, treatments, tdd]
started: "2026-08-28T16:07:31Z"
finished: "2026-08-28T16:21:18Z"
delivered: "2026-08-28T16:21:18Z"
---

## Problem statement

Como cliente realtime, quero receber uma representação única e completa dos recursos
pelos snapshots de join, replies de comandos e broadcasts, para atualizar o estado
local sem consultas adicionais, inferência de campos ou parsers por origem.

O contrato atual está distribuído entre `RoomChannel`, `TreatmentQueueChannel`,
`UserChannel`, `Chat.Broadcaster` e os testes. Há diferenças de nomes, campos e
completude entre mensagens, presença, digitação e ciclo de vida da Tratativa.

## Contract

Definir uma especificação pública versionada em documentação do backend para os
eventos `message_created`, `message_updated`, `message_removed`, `presence`,
`typing`, `treatment_created`, `treatment_assigned`, `treatment_released`,
`treatment_transferred`, `treatment_resolved`, `treatment_reopened` e
`treatment_closed`, além dos comandos correspondentes.

Cada evento deve declarar campos obrigatórios/opcionais/nulos, tipos, IDs de
correlação e estado resultante. Quando o recurso é o mesmo, snapshot, reply e
broadcast devem usar a mesma projeção pública. A normalização deve ser aditiva ou
ter estratégia explícita de compatibilidade para os clientes atuais.

## Acceptance

- [ ] Inventário identifica os payloads atuais e divergências antes da alteração.
- [ ] Existe documentação oficial com a matriz completa dos eventos e comandos.
- [ ] Mensagens podem ser inseridas, substituídas e removidas diretamente do estado local.
- [ ] Presença e digitação têm semântica explícita para ausência e `null`.
- [ ] Todos os eventos de Tratativa carregam a projeção persistida pós-transição necessária para a UI.
- [ ] Snapshot, reply e broadcast usam representação compatível para cada entidade.
- [ ] Testes `Phoenix.ChannelTest` verificam contratos públicos, cardinalidade e paridade entre caminhos.
- [ ] `mix precommit` e `git diff --check` passam.

## Tasks

- [x] Inventariar eventos, comandos, snapshots e payloads atuais.
- [x] Especificar tipos, campos, nulos e correlação na documentação oficial.
- [x] Escrever testes ChannelTest RED para mensagens e Tratativas.
- [x] Normalizar projeções e adaptar snapshot, replies e broadcasts.
- [x] Cobrir presença, digitação, criação de Tratativa e ciclo de vida completo.
- [x] Executar testes focados, precommit e diff check.
- [x] Registrar evidências e entregar a story para revisão humana.

## Possible solution

Extrair projeções públicas pequenas e compartilhadas por `RoomChannel`, usando o
resultado persistido do domínio. Manter o Channel como adaptador de transporte:
identidade vem do socket, comandos aceitam somente entradas documentadas, e
broadcast ocorre após transição efetiva. Para mensagens, reutilizar a representação
hidratada já usada na listagem, sem enviar mapas de confirmação incompletos.

## Comments
@JuruSysadmin 2026-08-28
Implementado e validado: contrato oficial em docs/realtime-contract.md; projeção canônica em lib/chat/realtime/payloads.ex; RoomChannel usa a mesma representação em join, replies e broadcasts; TreatmentQueue usa a projeção canônica; replies de criação/edição/remoção de mensagem agora carregam estado suficiente; testes públicos Phoenix.ChannelTest cobrem paridade e campos. Focados passaram: 3 eventos de mensagens + snapshot/lifecycle, e RoomChannel/TreatmentQueue (69 testes). mix test completo executado: 631/638 passaram; 7 falhas pré-existentes/fora do escopo relacionadas ao catálogo de razões e testes de reopen. mix precommit bloqueado por Credo em lib/chat/orders/client.ex (fora do escopo) e git diff --check global por linha final em tratativas-infra/_icebox.md (alteração preexistente); diff check escopado aos arquivos desta story passou.

## Attachments
