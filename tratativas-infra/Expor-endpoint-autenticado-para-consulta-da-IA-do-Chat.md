---
title: Expor endpoint autenticado para consulta da IA do Chat
type: feature
created: "2026-08-25T23:31:22Z"
modified: "2026-08-25T23:35:01Z"
author: assistant
status: delivered
started: "2026-08-25T23:32:02Z"
finished: "2026-08-25T23:35:01Z"
delivered: "2026-08-25T23:35:01Z"
---

## Problem statement
O Chat precisa oferecer uma forma autenticada de consultar a IA local sobre o contexto das tratativas.

## Acceptance
- `POST /api/ai/ask` aceita um campo JSON `prompt`.
- A rota exige autenticação da API.
- O endpoint retorna a resposta da LLM em JSON.
- Prompts ausentes ou vazios retornam `400`.
- Falhas do Ollama retornam `502` sem expor detalhes internos.

## Possible solution
Adicionar um controller pequeno que delega a `Chat.AI.Ollama` e uma rota dentro do escopo autenticado da API.

## Tasks

- [x] Escrever testes para sucesso, prompt inválido e falha do Ollama

- [x] Implementar controller e rota autenticada POST /api/ai/ask

- [x] Executar testes específicos e verificações sem dialyzer
