# Imagem de Perfil (S3)

Gerencia a imagem de perfil do usuário autenticado via S3 com URLs pre-assinadas.

## Design

Nada é gravado no banco. A chave do objeto no S3 é determinística a partir da matrícula:

```
profile-images/{matricula}/avatar
```

A matrícula vem dos claims do token JWT (`authService.getAuthenticatedUser`), então cada usuário só manipula a própria imagem. Não há coluna nova no banco.

## Endpoints

Base path:

- `/users/me/profile-image`

Todos exigem header:

```http
Authorization: Bearer SEU_TOKEN
```

### `POST /users/me/profile-image/presign-upload`

Gera uma URL pre-assinada (`PUT`) para envio direto da imagem ao S3, sem passar pela API.

Body:

```json
{
  "contentType": "image/png"
}
```

`contentType` é obrigatório e aceita apenas:

- `image/jpeg`
- `image/png`
- `image/webp`

Resposta (`200`):

```json
{
  "uploadUrl": "https://bucket.s3.amazonaws.com/profile-images/25/avatar?X-Amz-Signature=...",
  "contentType": "image/png"
}
```

O frontend deve enviar a imagem via `PUT` na `uploadUrl` usando exatamente o `contentType` retornado no header `Content-Type`. A URL expira em `upload-url-ttl-seconds` (padrão 5 minutos).

### `GET /users/me/profile-image/presign-download`

Gera uma URL pre-assinada (`GET`) para leitura direta da imagem no S3.

Resposta (`200`):

```json
{
  "downloadUrl": "https://bucket.s3.amazonaws.com/profile-images/25/avatar?X-Amz-Signature=...",
  "expiresAt": "2026-08-16T15:30:00Z"
}
```

A URL expira em `download-url-ttl-seconds` (padrão 15 minutos). Se o usuário ainda não tem imagem, o S3 retorna `404`.

### `DELETE /users/me/profile-image`

Remove a imagem de perfil do usuário autenticado.

Resposta:

- `204 No Content` em caso de sucesso

### Fluxo no frontend

1. `POST /users/me/profile-image/presign-upload` com o `contentType` desejado
2. `PUT` direto na `uploadUrl` com os bytes da imagem
3. `GET /users/me/profile-image/presign-download` para obter a URL assinada e usar como `src`
4. `DELETE /users/me/profile-image` para remover

### Códigos de erro

- `400`: `contentType` ausente ou não suportado
- `401`: token ausente ou inválido

## Configuração

| Propriedade | Variável de ambiente | Padrão | Descrição |
| --- | --- | --- | --- |
| `profile-image.s3.bucket` | `PROFILE_IMAGE_S3_BUCKET` | (obrigatório) | Bucket S3 |
| `profile-image.s3.region` | `PROFILE_IMAGE_S3_REGION` | `us-east-1` | Região AWS |
| `profile-image.s3.endpoint` | `PROFILE_IMAGE_S3_ENDPOINT` | — | Endpoint customizado (S3 compatível em dev) |
| `profile-image.s3.upload-url-ttl-seconds` | `PROFILE_IMAGE_S3_UPLOAD_URL_TTL_SECONDS` | `300` | Validade da URL de upload (segundos) |
| `profile-image.s3.download-url-ttl-seconds` | `PROFILE_IMAGE_S3_DOWNLOAD_URL_TTL_SECONDS` | `900` | Validade da URL de download (segundos) |

As credenciais AWS são lidas pela cadeia padrão do SDK (variáveis de ambiente, `~/.aws/credentials`, IMDS, etc.).

## Implementação

Arquivos:

- `src/main/java/com/jurunense/authapi/config/ProfileImageProperties.java` — propriedades `profile-image.*`
- `src/main/java/com/jurunense/authapi/config/S3Config.java` — beans `S3Client` e `S3Presigner`
- `src/main/java/com/jurunense/authapi/controller/ProfileImageController.java` — endpoints
- `src/main/java/com/jurunense/authapi/service/ProfileImageService.java` — presign PUT/GET e delete
- `src/main/java/com/jurunense/authapi/dto/PresignedUploadRequest.java`
- `src/main/java/com/jurunense/authapi/dto/PresignedUploadResponse.java`
- `src/main/java/com/jurunense/authapi/dto/PresignedDownloadResponse.java`
- `src/test/java/com/jurunense/authapi/controller/ProfileImageControllerTest.java` — testes do controller

## Segurança

- A chave é derivada da matrícula do JWT; o usuário nunca informa a matrícula.
- `contentType` é restrito a `jpeg`, `png` e `webp` antes da assinatura.
- A URL de upload só permite `PUT` no objeto do próprio usuário, com validade curta.
- Recomenda-se uma policy no bucket que restrinja escrita apenas ao prefixo `profile-images/*`.
- O tamanho máximo não é limitável na URL pré-assinada; limite no frontend e, se necessário, valide o objeto após o upload.