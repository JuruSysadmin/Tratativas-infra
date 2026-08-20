# Deploy e atualizações de release

## Estado atual

O projeto suporta deploy normal com `make deploy`.

Hot code upgrades por OTP **não são suportados pelo fluxo atual**. O Mix 1.20 não oferece `mix release --upgrade`; a própria documentação do Mix informa que hot upgrades não são fornecidos prontos para releases Elixir.

Por segurança, estes comandos abortam sem alterar o servidor:

```bash
make build-upgrade
make deploy-upgrade
```

Eles só devem voltar a existir como comandos operacionais depois de uma implementação completa e validada de `.appup` e `.relup`.

## Deploy normal — fluxo suportado

Use para qualquer release atual:

```bash
make deploy
```

O fluxo FreeBSD:

1. compila os assets e a release;
2. para o serviço `chat` via `service`;
3. copia a release para `/opt/chat/releases` e atualiza `/opt/chat/current`;
4. executa migrações;
5. reinicia o serviço via `rc.d`;
6. valida `/health` e `/ready`;
7. restaura a release anterior se a validação falhar.

Há uma interrupção durante a troca.

## Versionamento antes do deploy

A versão é definida em `mix.exs` e deve ser incrementada conforme o impacto:

```bash
# Correção compatível: 0.1.0 -> 0.1.1
make bump-patch

# Nova feature compatível: 0.1.0 -> 0.2.0
make bump-minor

# Mudança incompatível: 0.1.0 -> 1.0.0
make bump-major
```

Em seguida:

```bash
make check
make deploy
```

## Por que hot code upgrade não funciona automaticamente

Um upgrade real de OTP exige mais do que uma nova versão de release. Para cada aplicação alterada, são necessários:

- arquivos `.appup` com instruções de upgrade e downgrade;
- um `.relup` gerado a partir dessas receitas;
- processos preparados para mudar estado com `code_change/3`;
- compatibilidade temporária entre mensagens e formatos antigos/novos;
- migrações expand/contract que funcionem com código antigo e novo;
- validação em staging com pelo menos duas releases reais;
- plano de rollback de código e banco.

O projeto atual não possui esses artefatos nem a cobertura operacional necessária. Invocar `release_handler.install_release/1` sem um `.relup` válido é inseguro e não constitui hot upgrade funcional.

## Quando buscar zero downtime

Para disponibilidade sem interrupção, prefira uma estratégia de infraestrutura em vez de hot code upgrade:

### Blue/green

Execute duas instâncias da aplicação, por exemplo `chat-blue` e `chat-green`, atrás de Nginx ou outro proxy. Faça deploy na instância inativa, valide um health check e troque o tráfego.

Indicado para:

- atualizações frequentes;
- necessidade de rollback rápido;
- mudanças com migrações compatíveis;
- operação com proxy/load balancer.

### Rolling deployment

Execute duas ou mais instâncias atrás de um balanceador. Atualize uma instância por vez, removendo-a temporariamente do tráfego.

Indicado para:

- mais de uma VM/container;
- health checks confiáveis;
- sessões, presença e PubSub distribuídos corretamente.

## Caso seja necessário implementar hot upgrade no futuro

Abra uma tarefa específica de arquitetura. Ela deve incluir:

1. inventário dos GenServers, Supervisors e processos com estado;
2. implementação e testes de `code_change/3` onde houver mudança de estado;
3. `.appup` para a aplicação `chat` e dependências alteradas;
4. geração e inspeção do `.relup`;
5. cenário de upgrade e downgrade em staging;
6. estratégia expand/contract para banco;
7. observabilidade, health checks e rollback testado.

Até essa implementação estar validada, use `make deploy`.

## Checklist antes de deploy normal

- [ ] versão escolhida e incrementada quando houver release;
- [ ] `make format` passou;
- [ ] `make check` passou;
- [ ] backup do banco disponível para mudanças de esquema;
- [ ] migrações revisadas;
- [ ] logs e health check monitorados após o deploy.
