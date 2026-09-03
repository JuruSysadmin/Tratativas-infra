---
title: Suportar anexos de áudio nas mensagens
type: feature
created: "2026-08-31T14:47:22Z"
modified: "2026-08-31T14:54:45Z"
author: user
status: delivered
started: "2026-08-31T14:48:11Z"
finished: "2026-08-31T14:54:45Z"
delivered: "2026-08-31T14:54:45Z"
---

## Objetivo

Permitir que o pipeline existente de attachments aceite arquivos de áudio como mensagens sem conteúdo textual, reutilizando presign, upload direto S3/MinIO, confirmação, associação, idempotência e cleanup órfão.

## Escopo

- Controlar explicitamente os MIME types de áudio suportados pelo produto, sem criar infraestrutura específica.
- Preservar o limite backend de 10 MB.
- Persistir e devolver `metadata.duration_seconds` via JSONB quando enviado como metadata de UX.
- Manter ownership, confirmação, autorização e verificação de upload existentes.
- Não criar serviço, endpoint, bucket, streaming ou protocolo específico de áudio.

## Acceptance

- Áudio aceito como attachment válido e mensagem somente com áudio é criada.
- MIME desconhecido retorna `unsupported_content_type`.
- O pipeline continua usando presigned URL, PUT direto, confirmação e download URL.
- O limite de 10 MB continua protegido no backend.
- Metadata de duração persiste e volta no payload sem influenciar segurança ou integridade.
- Attachments órfãos continuam usando o cleanup existente.
- Testes backend relevantes permanecem verdes.

## Tasks

- [x] Confirmar matriz final de MIME types com o contrato atual do frontend.
- [x] Adicionar testes backend para MIME types, metadata e mensagem somente com áudio.
- [x] Implementar a lista controlada de MIME types e expor metadata no payload.
- [x] Cobrir limite, ownership, confirmação, upload incompleto e cleanup sem regressão.
- [x] Executar `mix precommit` e revisar o diff.

## Comments

@user 2026-08-31
Implementado o suporte aos sete MIME types de áudio controlados pela matriz do cliente. O metadata JSONB agora é incluído no payload; `duration_seconds` permanece apenas metadata de UX. Mantidos presign, PUT direto, confirmação, ownership, associação, limite de 10 MB e cleanup existentes. Backend: 670 testes passaram. Frontend: 284 testes e build passaram; lint global permanece bloqueado por problemas preexistentes fora dos arquivos alterados.
