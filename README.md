# Fusion Tarefas

Extensão para a **Fusion Platform** para consultar tarefas atrasadas, aplicar
filtros e enviar notificações por e-mail aos responsáveis.

O projeto disponibiliza uma tela de relatório de tarefas atrasadas (JSP) e um
endpoint de envio de notificações, publicados em um contexto Fusion já
existente. Não inclui dependências proprietárias: usa a API de Servlet padrão,
o banco de dados do Fusion e a API Jakarta Mail.

> **Status:** a instalação manual foi validada em um ambiente de homologação com
> Tomcat 10.1.34, Java 21, MySQL e Jakarta Mail. O suporte a **MySQL e
> PostgreSQL** foi implementado: o dialeto, as consultas e a conexão foram
> executados contra um **PostgreSQL 18 real** (inclusive sob usuário somente
> leitura); o teste contra um **MySQL real está pendente** — veja
> [Bancos de dados suportados](#bancos-de-dados-suportados) e
> [Compatibilidade](#compatibilidade). O instalador automatizado teve a sintaxe,
> o dialeto e a compatibilidade do pacote verificadas, mas ainda precisa ser
> executado por completo em um servidor limpo. Não há garantia de compatibilidade
> universal.

## Funcionalidades

- Relatório de tarefas atrasadas com paginação.
- Filtros por solicitante, processo, nome da tarefa, período de solicitação e
  faixa de dias de atraso.
- Classificação visual do atraso (atenção, alerta, crítico).
- Detalhamento da tarefa em janela modal.
- Seleção de uma ou várias tarefas e envio de notificação por e-mail aos
  responsáveis, com resumo do resultado.
- Identificação do destinatário principal pelo responsável atual da tarefa, com
  alternativa de destinatários por papel atribuído.
- Link direto para a tarefa no Fusion no corpo do e-mail.

## Tecnologias

- Java 21
- Jakarta Servlet 6.0 e JSP
- Apache Tomcat 10.1 (compatível com Jakarta)
- MySQL (Connector/J) e PostgreSQL (driver JDBC oficial)
- Jakarta Mail (Angus Mail)
- HTML, CSS e JavaScript (sem frameworks)
- Bash para instalador e empacotamento

## Arquitetura

Resumo dos componentes:

- `web/tarefas-atrasadas.jsp` — tela de consulta, filtros e seleção de tarefas.
- `web/script/script.js` — comportamento da interface e chamada ao endpoint de
  notificação.
- `web/css/style.css` — estilos da tela.
- `TaskNotificationServlet` (`/custom/task-notification`) — endpoint de envio de
  notificações.
- `br.com.fusion.tarefas.repository.TarefaRepository` — acesso ao banco do
  Fusion.
- `br.com.fusion.tarefas.repository.TarefasSql` — montagem centralizada das
  consultas parametrizadas.
- `br.com.fusion.tarefas.config.BancoDados` — detecção do banco (MySQL ou
  PostgreSQL) e trechos de SQL específicos de cada dialeto.
- `br.com.fusion.tarefas.security.Autorizacao` — identificação do usuário e
  verificação de autorização.
- `br.com.fusion.tarefas.config.AppConfig` — leitura do arquivo de propriedades
  externo.

Detalhes em [docs/arquitetura.md](docs/arquitetura.md).

## Requisitos

- Servidor Linux com Bash 4+, Python 3, `systemd` e acesso administrativo via
  `sudo` (para a instalação automatizada).
- Fusion Platform instalada e em execução, com contexto expandido em
  `webapps/fusion` e Tomcat compatível com Jakarta (10.1 no ambiente testado).
- JDK com `javac` e `javap` acessível pelo processo do Fusion.
- Cliente com Bash, `ssh`, `sha256sum`, `tar`, `base64`, `mkfifo` e `stty`
  (para instalação remota). Compatível com Git Bash no Windows e Bash no Linux.
- Bibliotecas disponíveis no Fusion: `servlet-api.jar` (Tomcat) e, em
  `WEB-INF/lib`, o driver JDBC do banco utilizado (MySQL Connector/J **ou** o
  driver JDBC do PostgreSQL), Jakarta Mail API, Angus Mail, Jakarta Activation
  API e Angus Activation.
- Banco MySQL **ou** PostgreSQL acessível com conta dedicada de leitura e SMTP
  autorizado com STARTTLS e autenticação.
- Janela de manutenção autorizada e revisão prévia de segurança do código.

## Estrutura do repositório

```text
fusion-tarefas/
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── .gitignore
├── install-fusion-tarefas-v2.sh
├── src/br/com/fusion/tarefas/     # fontes Java
├── web/                          # JSP, CSS e JavaScript
├── config/                       # exemplo de configuração
├── scripts/build-release.sh
├── docs/
├── screenshots/
└── dist/                         # pacote gerado (não versionado)
```

## Empacotamento

Gere o pacote de distribuição e o checksum a partir da raiz do projeto:

```bash
bash scripts/build-release.sh
```

Isso produz `dist/fusion-tarefas.tar.gz` e `dist/fusion-tarefas.tar.gz.sha256`.
O pacote contém `web/`, `src/` e `config/fusion-tarefas.properties.example` sob
a raiz `fusion-tarefas/`, compatível com o instalador.

## Instalação automatizada

Coloque `install-fusion-tarefas-v2.sh` e `fusion-tarefas.tar.gz` no mesmo diretório
e execute:

```bash
bash -n install-fusion-tarefas-v2.sh
bash install-fusion-tarefas-v2.sh fusion-tarefas.tar.gz
```

O script oferece instalação local ou remota. Na opção remota, informe
hostname/IP, usuário SSH e porta (padrão 22). A senha SSH é solicitada uma única
vez e a senha `sudo`, no máximo uma vez. Informe também a URL pública do Fusion,
por exemplo `https://fusion.exemplo.com/fusion`. O instalador:

- abre uma única sessão SSH interativa e, após sincronizar cliente e servidor,
  transfere o pacote e o instalador codificados em base64, sem exibi-los na
  tela, conferindo o SHA-256 de ambos antes da execução privilegiada;
- mantém a sessão aberta durante todos os prompts (`sudo`, banco e SMTP) e
  restaura o estado do terminal ao final, em sucesso, erro ou interrupção;
- extrai o pacote com validações;
- identifica o banco do Fusion (MySQL ou PostgreSQL) pela configuração anterior,
  pelo driver presente em `WEB-INF/lib` ou, quando não for possível deduzir, por
  pergunta ao operador, exigindo apenas o driver do banco escolhido;
- gera a URL JDBC e usa a porta padrão do banco (3306 no MySQL, 5432 no
  PostgreSQL) e, antes de publicar, valida a conexão e todas as consultas do
  recurso com a configuração informada (somente `SELECT`);
- detecta o Tomcat ativo, o JDK e o serviço `systemd` do Fusion;
- verifica as bibliotecas necessárias e compila as fontes;
- cria backup antes de alterar qualquer arquivo;
- publica os recursos web e as classes e, opcionalmente, reinicia o serviço;
- apresenta instruções de rollback e os endereços de teste.

Instruções detalhadas em [docs/instalacao.md](docs/instalacao.md).

## Instalação manual

O roteiro manual (útil quando a detecção automática não se aplica) está em
[docs/instalacao.md](docs/instalacao.md#instalação-manual).

## Configuração

As credenciais de banco e SMTP ficam em um arquivo de propriedades externo
(preenchido manualmente ou pelo instalador). Defina o caminho no arranque do
Fusion:

```text
-Dfusion.config.path=/opt/fusion/config/fusion-tarefas.properties
```

Use [config/fusion-tarefas.properties.example](config/fusion-tarefas.properties.example)
como base. Detalhes em [docs/configuracao.md](docs/configuracao.md).

## Bancos de dados suportados

O recurso funciona com **MySQL** e **PostgreSQL**, mantendo compatibilidade com
as instalações MySQL existentes.

- **Detecção automática:** o instalador identifica o banco pela configuração
  anterior do recurso (`db.type`/`db.url`), pelo driver JDBC presente em
  `WEB-INF/lib` ou, quando não for possível deduzir, pergunta ao operador
  (`MySQL` ou `PostgreSQL`).
- **Porta padrão:** `3306` (MySQL) ou `5432` (PostgreSQL).
- **URL JDBC:** `jdbc:mysql://host:3306/banco?...` ou
  `jdbc:postgresql://host:5432/banco?...`.
- **Driver:** `com.mysql.cj.jdbc.Driver` (MySQL Connector/J) ou
  `org.postgresql.Driver` (driver oficial do PostgreSQL); o instalador exige
  apenas o driver do banco escolhido em `WEB-INF/lib`.
- **Tipo explícito (opcional):** `db.type=mysql` ou `db.type=postgresql`. Quando
  ausente, o tipo é deduzido do prefixo de `db.url`, preservando a
  compatibilidade com os arquivos de propriedades de instalações anteriores.

As consultas ficam centralizadas em `TarefasSql` e as diferenças de dialeto
(funções de data e predicado de "ativo") em `BancoDados`. As adaptações
preservam o comportamento original — por exemplo,
`TIMESTAMPDIFF(DAY, coluna, NOW())` (MySQL) equivale a
`TRUNC(EXTRACT(EPOCH FROM (NOW() - coluna)) / 86400)` (PostgreSQL). Todas as
consultas usam `PreparedStatement` e apenas `SELECT`.

> **Identificadores no PostgreSQL:** o PostgreSQL converte identificadores não
> aspados para minúsculas (`neoId` → `neoid`). As consultas usam os nomes sem
> aspas, o que corresponde ao esquema do Fusion quando criado com a mesma
> convenção (nomes não aspados). Se o esquema do Fusion no PostgreSQL tiver sido
> criado com identificadores aspados em maiúsculas/minúsculas mistas, será
> necessário aspear os identificadores. Confirme a convenção do ambiente antes
> de publicar.

## Testes de funcionamento

Substitua a URL de exemplo pelo endereço do ambiente:

- Tela: `https://fusion.exemplo.com/fusion/custom/fusion-tarefas/tarefas-atrasadas.jsp`
- Endpoint (GET autenticado): `https://fusion.exemplo.com/fusion/custom/task-notification`

O GET autenticado deve retornar `{"success":true,"message":"Endpoint funcionando"}`.
Isso não comprova acesso ao banco nem funcionamento do SMTP. Roteiro completo em
[docs/instalacao.md](docs/instalacao.md#testes-de-funcionamento).

## Solução de problemas

Veja [docs/troubleshooting.md](docs/troubleshooting.md).

## Backup e rollback

Veja [docs/rollback.md](docs/rollback.md).

## Compatibilidade

O instalador exige `systemd`, contexto `fusion` expandido e um Tomcat ativo
detectável. Ambientes com contêineres, outros gerenciadores de serviço,
múltiplos nós, WAR não expandido ou caminhos diferentes podem exigir adaptação.
Quando o ambiente não for reconhecido, o instalador interrompe e orienta a
configuração manual.

**Bancos de dados:**

- MySQL e PostgreSQL são suportados, com detecção do banco e seleção dinâmica do
  driver.
- A validação real foi executada contra um **PostgreSQL 18** (conexão, contagem,
  listagem com `LIMIT/OFFSET`, filtros de período e de atraso, valores distintos
  e a consulta de autorização), inclusive sob um usuário **somente leitura** com
  a escrita negada.
- O teste contra um **MySQL real está pendente** nesta versão do ambiente de
  desenvolvimento. O SQL específico do MySQL (`TIMESTAMPDIFF`, `DATE_ADD`,
  `active = 1`) foi verificado por testes de dialeto e por emulação; a
  validação contra o SGBD real ocorre na instalação, quando o instalador executa
  todas as consultas contra o banco do Fusion antes de publicar.
- O PostgreSQL converte identificadores não aspados para minúsculas; veja a
  observação em [Bancos de dados suportados](#bancos-de-dados-suportados).

## Contribuições

Veja [CONTRIBUTING.md](CONTRIBUTING.md).

## Licenciamento

Distribuído sob a licença MIT — veja [LICENSE](LICENSE). A Fusion Platform e
suas dependências (Tomcat, MySQL Connector/J, PostgreSQL JDBC Driver, Jakarta
Mail, Angus Mail) possuem seus próprios termos de licenciamento, que devem ser
observados separadamente.
