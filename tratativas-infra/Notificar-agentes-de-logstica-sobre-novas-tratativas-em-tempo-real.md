---
title: Notificar agentes de logística sobre novas tratativas em tempo real
type: feature
created: "2026-08-25T19:35:48Z"
modified: "2026-08-28T15:16:30Z"
author: JuruSysadmin
status: started
started: "2026-08-25T19:36:25Z"
---

## Problem statement

Quando o Comercial cria uma tratativa, os agentes de Logística online não recebem a atualização da fila e precisam recarregar a página.

## Acceptance

- Todos os agentes de Logística conectados recebem `treatment:created` após uma criação bem-sucedida.
- Usuários sem perfil de Logística não podem entrar no canal global da fila.
- O frontend sincroniza a fila sem F5 e mostra uma notificação Carbon para a nova tratativa.
- Eventos repetidos da mesma tratativa não geram notificações duplicadas.
- Ao reconectar, o frontend invalida a fila para recuperar eventos perdidos.

## Possible solution

Adicionar um Phoenix Channel global autorizado para a fila, publicar o evento após a persistência e conectar a página de atendimentos por um hook dedicado. Usar `ToastNotification` para avisos transitórios e `InlineNotification` para indisponibilidade persistente da conexão.

## Tasks

- [x] Adicionar testes backend para autorização e broadcast de criação
- [x] Implementar canal global e broadcast backend
- [x] Adicionar testes frontend para sincronização, deduplicação e notificações
- [x] Implementar hook realtime e notificações Carbon
- [x] Executar verificações relevantes de backend e frontend

- [x] Corrigir o retorno de handle_out/3 no UserChannel para preservar o socket
- [x] Adicionar teste do encaminhamento privado via handle_out/3
- [ ] Executar Dialyzer, testes focados, git diff --check e registrar o resultado
- [x] Adicionar teste que confirme visibilidade commitada da mensagem durante o callback de broadcast
- [x] Reorganizar testes de Chat.Messages por área de comportamento
- [x] Migrar todos os testes sem alterar comportamento ou produção
- [x] Executar testes focados, suíte de mensagens, formatação e diff check
- [x] Validar idempotência observável de retry por client_id: mesma mensagem, uma persistência e um broadcast
- [x] Criar teste de integração para desconectar, reconectar, recuperar contexto e reconciliar outbox por client_id sem duplicidade
## Comments

## Attachments
