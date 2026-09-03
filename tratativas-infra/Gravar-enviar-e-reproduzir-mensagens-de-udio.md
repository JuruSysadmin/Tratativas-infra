---
title: Gravar enviar e reproduzir mensagens de áudio
type: feature
created: "2026-08-31T15:11:12Z"
modified: "2026-08-31T22:02:24Z"
author: user
status: delivered
estimate: "8"
started: "2026-08-31T15:13:18Z"
finished: "2026-08-31T23:45:00Z"
delivered: "2026-08-31T23:45:00Z"
---

## Objetivo

Adicionar gravação, envio e reprodução de mensagens de áudio no frontend usando o pipeline existente de attachments e mensagens.

## Acceptance

- `audioRecording` encapsula MediaRecorder, MediaStream, codecs, timer, amplitude e cleanup.
- Máquina de estados cobre gravação, pausa, preview, envio e erro.
- MessageComposer não conhece APIs nativas de gravação.
- Upload usa `useMessageFileUpload` e envio usa `sendMessage`/`client_id` existentes.
- Preview libera Object URLs em todos os caminhos.
- AudioMessagePlayer usa `download_url`, suporta seek, duração e velocidades de 1x a 2x.
- Apenas um áudio reproduz por vez via coordenador semântico.
- Arquivos externos usam o uploader existente.
- Não há mudanças em `useRoomChannel`, Phoenix ou infraestrutura de storage.
- Testes cobrem lifecycle, codecs, permissões, cleanup, envio, retry e playback.

## Decisão pendente

Confirmar o limite máximo de gravação antes de congelar `MAX_RECORDING_DURATION`. A story sugere 10 minutos como valor inicial, mas o texto exige confirmação de produto.

## Tasks

- [x] Confirmar `MAX_RECORDING_DURATION`.
- [x] Implementar `audioRecording` com capability detection, estados e cleanup.
- [x] Implementar `VoiceRecorder` e preview no `MessageComposer`.
- [x] Integrar gravação ao uploader e envio idempotente existentes.
- [x] Implementar `AudioMessagePlayer` e `AudioPlaybackCoordinator`.
- [x] Cobrir testes unitários e de integração dos fluxos.
- [x] Executar testes, build e lint do frontend.

- [x] Corrigir normalização de `audio/webm;codecs=opus` para o MIME de contêiner aceito pelo backend.
- [x] Refinar barra do composer com padrões Carbon, ícones semânticos, superfície única e comportamento dinâmico de microfone/envio.
- [x] Refinar AudioMessagePlayer: remover controles nativos duplicados, normalizar tempo, compactar velocidade e garantir layout Carbon responsivo.
- [x] Traduzir erros técnicos de edição e exclusão de mensagens para mensagens pt-BR sem alterar contratos.
- [x] Refinar VoiceRecorder para modo dedicado recording/paused, preview local e envio sem sair do composer.
- [x] Corrigir a exclusão visual dos controles normais e dos controles de voz não ativos no composer.
- [x] Validar recording, paused/preview e retorno ao modo normal via Chrome DevTools.
- [x] Corrigir regressão pós-envio mantendo o controller de áudio montado durante o upload.
- [x] Corrigir indicador Enviando áudio persistente fora do voice-mode.
- [x] Corrigir WebM sem duração/cues e validar reprodutibilidade antes do upload.
- [x] Rejeitar gravações vazias ou sem dados antes de presign/upload.
- [x] Alinhar VoiceRecorder aos layouts finais de recording e paused/preview fornecidos pelo produto.
- [x] Alinhar layout da mensagem de áudio no corpo do chat com avatar, waveform, duração, hora e status no padrão WhatsApp.
- [x] Aplicar InlineLoading Carbon e estados acessíveis ao envio de áudio no composer.
- [x] Refatorar captura, preview e reprodução para WaveSurfer v7, @wavesurfer/react e RecordPlugin oficial.
## Comments

@assistant 2026-08-31
Refatoração de áudio para WaveSurfer concluída:
1. Instaladas dependências wavesurfer.js@7.12.11 e @wavesurfer/react@1.0.12 com plugin oficial RecordPlugin.
2. audioRecording.ts refatorado para encapsular WaveSurfer + RecordPlugin com capability check, mapeamento semântico de erros, limite de 10 min e fixWebmDuration.
3. VoiceRecorder refatorado para layout dedicado: gravação com waveform ao vivo e timer; pausa como preview com waveform navegável e seek; sem elementos manuais de áudio/slider.
4. AudioMessagePlayer refatorado com useWavesurfer para renderização de waveform, seek nativo e controle de velocidade (1x a 2x).
5. AudioPlaybackCoordinator adaptado para pausar players WaveSurfer ativos.
6. Suíte de testes: 45 arquivos de teste e 309 testes passando, lint dos módulos de áudio limpo e build de produção validado.

@user 2026-08-31
Implementados captura encapsulada em `audioRecording`, capability detection, estados idle/recording/paused/preview/error, limite de 10 minutos, cleanup de stream/timer/AudioContext, VoiceRecorder, preview com revogação de Object URL, upload via hook existente, player remoto com seek/velocidade e coordenador de playback exclusivo. Testes frontend: 288 passaram; TypeScript e lint específico passaram.

@user 2026-08-31
Corrigido erro de produção no presign: MediaRecorder gera `audio/webm;codecs=opus`, enquanto a allowlist aceita `audio/webm`. Criado `audioRecordingToFile`, que normaliza apenas o MIME do `File` para o contrato de upload e preserva o Blob. Teste específico reproduz e cobre a correção. Suite frontend final: 289 testes passando; TypeScript e build verificados.

@user 2026-08-31
Teste manual em `https://vm.jurunense.com/atendimentos`, pedido `9998043931`, usuário Joelson.R: gravação e preview funcionaram; presign retornou 201 com `audio/webm`; PUT para `teste2.jurunense.com` falhou por CORS (`Access-Control-Allow-Origin` ausente), portanto a mensagem não foi persistida/enviada.

@user 2026-08-31
Refinamento visual do composer concluído com Carbon: microfone e controles em `IconButton`, labels acessíveis, microfone exibido apenas sem texto/anexo, superfície única, textarea sem underline e envio circular. Testes: 290 passaram; TypeScript, build e lint específico dos componentes passaram.

@user 2026-08-31
Refinamento visual do AudioMessagePlayer concluído: removidos controles nativos duplicados, labels visuais redundantes e select de velocidade; adicionados controles Carbon compactos, timeline flexível, normalização defensiva de tempo, fallback de metadata e layout responsivo. Suite frontend: 296 testes passaram; TypeScript, build e lint do player passaram.

@user 2026-08-31
Corrigida a exibição de erros técnicos de edição/exclusão no frontend. `already_read` e `message_already_read` agora aparecem como mensagem pt-BR clara; também foram mapeados autorização, mensagem inexistente, timeout e canal desconectado. Contratos backend/Channel permaneceram inalterados.

@user 2026-08-31
VoiceRecorder refinado para modo dedicado no composer: recording substitui os controles normais, pausa funciona como preview local, resume preserva a mesma sessão, envio funciona durante gravação ou pausa, cancelamento limpa recursos e layout permanece compacto com Carbon IconButtons. Suite frontend: 300 testes passaram; TypeScript, build e lint específico passaram.

@assistant 2026-08-31
Imagem de validação revelou regressão visual: controles normais, recording, preview e envio aparecem simultaneamente. Investigando conflito entre o atributo hidden e regras display do composer.

@assistant 2026-08-31
Corrigida a regressão adicionando ocultação explícita para qualquer elemento [hidden] dentro do composer, evitando que display: contents e estilos Carbon revelem estados inativos. Suite: 300 testes passando; TypeScript e build passando. A validação visual pós-correção requer atualizar o frontend no ambiente vm.

@assistant 2026-08-31
Regressão corrigida estruturalmente: VoiceRecorder monta apenas os controles do estado ativo; o composer normal tem ocultação explícita quando voice-mode está ativo. Adicionados 2 testes de regressão (RED/GREEN). Suite final: 302 testes; TypeScript, build e lint passaram. Chrome DevTools em vm.jurunense.com/atendimentos confirmou idle, recording, paused e descarte sem controles simultâneos, overflow ou erros no console.

@assistant 2026-08-31
Implementado fluxo estilo WhatsApp: durante o upload, o VoiceRecorder sai do composer, o composer normal retorna imediatamente e a Promise de upload continua sob responsabilidade do callback existente. Adicionado teste de regressão para upload pendente. Suite: 303 testes passando; TypeScript, build e lint passando. Chrome DevTools em vm.jurunense.com/atendimentos confirmou idle, recording, paused, descarte, ausência de controles simultâneos e ausência de overflow/erros.

@assistant 2026-08-31
Corrigida regressão pós-envio: VoiceRecorder permanece montado durante finish/upload, evitando que o cleanup destrua o MediaRecorder; composer normal fica visível durante o envio e controles de descarte/envio são ocultados. Suite: 303 testes passando; TypeScript, build e lint passando.

@assistant 2026-08-31
Corrigido diretamente o seletor CSS: o indicador `Enviando áudio...` com `data-visible=false` agora é ocultado em qualquer estado do composer, inclusive idle. Nenhum teste novo foi adicionado conforme solicitado.

@assistant 2026-08-31
Corrigido o principal problema de reprodução: WebM do MediaRecorder agora passa por `fix-webm-duration` antes do upload, com duração preservada no contêiner; gravações vazias são rejeitadas e `finish()` rejeita em falhas/cancelamento para não deixar o envio travado. Dependência `fix-webm-duration@1.0.6` adicionada. Validação: áudio real de 62 KB era WebM/Opus sem duration e o Chromium falhava no demux; suíte 303 testes, TypeScript, build e lint passaram.

@assistant 2026-08-31
Layout de produto aplicado: recording exibe timer, waveform de barras, pausa e envio; paused/preview exibe play, timeline, duração, retomada e envio. Amplitude passou a iniciar após o estado recording para alimentar as barras. Suite: 303 testes; TypeScript, build e lint passaram.

@assistant 2026-08-31
Waveform visual final implementado com barras nativas alimentadas pela amplitude real do AnalyserNode; wavesurfer.js foi avaliado e não adicionado porque duplicaria a captura existente e não resolveria o problema de estados/contêiner WebM. Dependência removida após avaliação.

@assistant 2026-08-31
Desfeito o último refinamento visual das barras de amplitude a pedido do usuário; restaurados o elemento `progress`, estilos anteriores e o posicionamento anterior da amostragem de amplitude. Correções de upload/WebM foram preservadas.

@assistant 2026-08-31
Mensagem de áudio foi movida para dentro do corpo da bolha, antes da meta; anexos não-áudio permanecem no fluxo original. A meta de hora e visto passa a ficar no rodapé da bolha, alinhada à direita, e o player foi compactado para o layout de áudio.

@assistant 2026-08-31
MCP Carbon confirmou ausência de player/recorder/waveform oficial e recomendou componentes primitivos: TextArea, IconButton, FileUploader e InlineLoading. Ajustes serão limitados a esses padrões.

@assistant 2026-08-31
Aplicado padrão confirmado pelo MCP Carbon: estado de envio agora usa InlineLoading com status active, descrição pt-BR e anúncio aria-live. TextArea, FileUploaderItem, ProgressBar e IconButton existentes foram preservados; player/recorder seguem customizados porque Carbon não fornece componentes de áudio. Suite: 304 testes; TypeScript, build, lint e diff-check passaram.
