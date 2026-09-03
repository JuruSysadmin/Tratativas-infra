---
title: Integrar Ollama local para respostas de IA no Chat
type: feature
created: "2026-08-25T23:14:58Z"
modified: "2026-08-25T23:18:51Z"
author: assistant
status: started
started: "2026-08-25T23:15:12Z"
---

## Problem statement
O aplicativo precisa consultar o Ollama local para validar uma primeira integração de IA sem depender de serviços externos.

## Acceptance
- `Chat.AI.Ollama.chat/2` envia um prompt para o endpoint configurado do Ollama.
- O cliente retorna o texto da mensagem quando a API responde com sucesso.
- Erros HTTP ou de transporte são retornados sem derrubar o processo chamador.
- A integração possui teste automatizado com `Req.Test` e teste manual contra o Ollama local.

## Possible solution
Criar um cliente pequeno usando `Req`, com URL e modelo configuráveis por aplicação e opções HTTP injetáveis nos testes.

## Tasks

- [x] Escrever teste para chamada ao Ollama usando um adaptador HTTP substituível

- [x] Implementar cliente Chat.AI.Ollama com modelo e URL configuráveis

- [ ] Executar teste real contra Ollama local e a suíte de verificação do projeto
