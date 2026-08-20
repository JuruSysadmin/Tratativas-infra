# Suporte de plataformas operacionais

## Decisão

O Chat usa FreeBSD como plataforma operacional primária neste ambiente, com serviço `rc.d` e gerenciamento via `service`. O arquivo `priv/chat.service` é mantido apenas como referência para um futuro alvo Linux/systemd e não participa do deploy FreeBSD.

O usuário final da aplicação não escolhe o sistema operacional. A plataforma
operacional é uma decisão do operador responsável pela instalação e pelo
ambiente de execução.

## Justificativa

A aplicação é um serviço web. O sistema operacional do servidor não altera a
experiência funcional do usuário final. Expor essa escolha na aplicação criaria
complexidade sem benefício de produto.

FreeBSD é o alvo primário porque é o sistema operacional do ambiente atual e
possui suporte nativo a serviços via `rc.d` e `service`.

## Limites da decisão

Esta decisão não declara que FreeBSD é incompatível. Ela evita declarar duas
plataformas como igualmente suportadas antes que existam scripts, testes e
procedimentos verificáveis para ambas.

O suporte operacional usa `rc.d` e comandos nativos do sistema, sem inserir
condicionais de sistema operacional no domínio ou nos componentes Phoenix.

## Modelo de implementação futuro

O fluxo de release deve ser comum às plataformas:

1. construir a release;
2. instalar a release;
3. executar migrações compatíveis;
4. iniciar ou reiniciar o serviço;
5. verificar `/health` e `/ready`;
6. executar um smoke test;
7. preservar a versão anterior para rollback.

Somente a integração com o gerenciador de serviços, os caminhos do sistema,
as permissões e os comandos de operação devem variar por plataforma.

Quando Linux se tornar requisito concreto, a implementação deverá ser separada,
por exemplo:

- Linux: `systemd` e `systemctl`;
- FreeBSD: `rc.d` e `service` (alvo atual).

## Critério para adicionar uma plataforma

Uma nova plataforma somente deve ser considerada oficialmente suportada quando
houver:

- procedimento de instalação versionado;
- configuração de serviço versionada;
- build ou release reproduzível;
- health check e readiness check;
- smoke test pós-deploy;
- rollback documentado e validado;
- ambiente de CI ou teste para detectar regressões;
- responsável definido pelo suporte operacional.

Até que esses critérios sejam atendidos, a plataforma é experimental e não
constitui alvo oficial de produção.
