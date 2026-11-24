# Changelog

Todas as mudanças relevantes deste projeto são registradas neste arquivo.
O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

Preparação do projeto para distribuição pública. As mudanças abaixo descrevem
o estado do código reorganizado; não representam garantias de homologação.

### Adicionado

- Estrutura de repositório com `src/`, `web/`, `config/`, `scripts/` e `docs/`.
- `config/fusion-tarefas.properties.example` com as chaves efetivamente
  utilizadas pelo código (`fusion.url`, `db.*`, `smtp.*`).
- `scripts/build-release.sh` para gerar `dist/fusion-tarefas.tar.gz` e o
  respectivo checksum SHA-256.
- Documentação em `docs/` (instalação, configuração, arquitetura, solução de
  problemas e rollback) e arquivos de governança do repositório
  (`README`, `LICENSE`, `CONTRIBUTING`, `SECURITY`).
- Suporte a **PostgreSQL** além do MySQL, com detecção automática do banco
  (`db.type` explícito ou deduzido do prefixo de `db.url`), seleção dinâmica do
  driver JDBC e adaptação do dialeto (`TIMESTAMPDIFF`/`DATE_ADD`/`active = 1`
  no MySQL; `EXTRACT(EPOCH ...)`/`INTERVAL '1 day'`/`active = TRUE` no
  PostgreSQL), preservando o comportamento original.
- Classes `br.com.fusion.tarefas.config.BancoDados` (detecção do banco e trechos
  de SQL específicos de cada dialeto) e
  `br.com.fusion.tarefas.repository.TarefasSql` (montagem centralizada das
  consultas parametrizadas, reutilizada pela JSP, pelo repositório e pela
  validação do instalador).
- Propriedade opcional `db.type` (`mysql` ou `postgresql`) no arquivo de
  configuração; quando ausente, o tipo é deduzido do prefixo de `db.url`.

### Alterado

- Instalador `install-fusion-tarefas-v2.sh` adaptado ao novo layout (`src/` e
  `web/`), com detecção de Tomcat/JDK/serviço, verificação de integridade,
  backup antes de alterações e rollback automático em falha de publicação.
- `TaskNotificationServlet` passou a exigir autenticação no POST, verificação
  de mesma origem (mitigação de CSRF) e autorização pelo grupo administrativo.
- Identificação de usuário e verificação de autorização centralizadas em
  `br.com.fusion.tarefas.security.Autorizacao`, reutilizada pela JSP e pelo
  servlet.
- `fusion.url` tornou-se propriedade obrigatória, sem valor padrão corporativo.
- Template de e-mail sem identificação de organização específica.
- Instalador passou a identificar o banco do Fusion (configuração anterior,
  driver presente em `WEB-INF/lib` ou pergunta ao operador), usar a porta padrão
  correspondente (3306 ou 5432), gerar a URL JDBC do banco escolhido e exigir
  apenas o driver necessário — removendo a dependência obrigatória do MySQL
  quando o ambiente é PostgreSQL.
- Instalador passou a validar a conexão e todas as consultas do recurso (apenas
  `SELECT`) contra o banco informado antes de publicar qualquer arquivo,
  abortando sem publicar em caso de falha.
- `TarefaRepository`, `Autorizacao` e `web/tarefas-atrasadas.jsp` passaram a usar
  as consultas centralizadas (`TarefasSql`) e o dialeto de `BancoDados`.
- Instalador passou a exibir o passo a passo da execução (blocos de etapa,
  mensagens de progresso e erros com prefixo `[ERRO]`) e a formular perguntas
  mais descritivas, com explicação, exemplo e valor padrão sugerido entre `[ ]`.

### Corrigido

- Instalação remota deixou de usar multiplexação SSH
  (`ControlMaster`/`ControlPersist`/`ControlPath`) e `SCP`, que falhavam no Git
  Bash para Windows com `mux_client_request_session: read from master failed:
  Connection reset by peer`. O envio passou a usar uma única sessão SSH
  interativa (`ssh -tt`), com o pacote e o instalador trafegando em base64 para
  preservar a integridade, garantindo uma senha SSH e, no máximo, uma senha
  `sudo`, sem `sshpass` e sem armazenamento de senhas.
- O envio remoto passou a sincronizar cliente e servidor antes de transmitir o
  pacote (o servidor envia um marcador — um byte de controle — e o cliente só
  então libera o envio), a manter o eco do pseudo-terminal remoto desligado e a
  ler a digitação explicitamente de `/dev/tty`, mantendo a sessão SSH aberta
  durante todos os prompts (`sudo`, banco e SMTP). O eco visível passou a ser o
  do terminal local do cliente, de modo que o que o operador digita (URL,
  escolhas, usuários) aparece na tela; apenas as senhas são digitadas sem eco,
  sob sinalização do servidor. Isso corrigiu a exibição do conteúdo Base64 na
  tela, o encerramento prematuro da sessão antes de concluir a autenticação
  `sudo` e a digitação invisível. A integridade do instalador e do pacote passou
  a ser conferida por SHA-256 no servidor antes da execução privilegiada, e o
  estado do terminal é restaurado em sucesso, erro ou interrupção.

### Removido

- Referências a domínio, caminho e identidade corporativos no código e na
  configuração de exemplo.
- Classes não utilizadas em tempo de execução e artefatos de backup,
  compilação antiga e metadados de IDE.

### Segurança

- Mensagens de erro internas genéricas para o cliente, com registro detalhado
  apenas no log do servidor.
- Validação do identificador de tarefa recebido no endpoint de notificação.

## Limitações conhecidas

- A instalação automatizada teve a sintaxe Bash validada, mas ainda não foi
  executada por completo em um ambiente limpo de produção.
- O fluxo de transferência remota e de interação com o pseudo-terminal foi
  validado por um harness automatizado (sincronização, Base64 oculto, senha
  entregue ao processo remoto, restauração do terminal), mas a interação por
  `/dev/tty` depende de um terminal real e deve ser confirmada em Git Bash
  interativo ou em Linux/macOS.
- A autorização do endpoint de notificação depende do grupo administrativo do
  banco do Fusion e precisa ser validada no ambiente alvo.
- O suporte a PostgreSQL foi validado contra um **PostgreSQL 18 real** (conexão,
  contagem, listagem com `LIMIT/OFFSET`, filtros de período e de atraso, valores
  distintos e a consulta de autorização), inclusive sob um usuário somente
  leitura com a escrita negada. O teste contra um **MySQL real permanece
  pendente**: o SQL específico do MySQL (`TIMESTAMPDIFF`, `DATE_ADD`,
  `active = 1`) foi verificado por testes de dialeto e por emulação (H2) e é
  validado contra o SGBD real pelo próprio instalador antes da publicação.
- As consultas usam identificadores sem aspas; no PostgreSQL isso corresponde a
  nomes dobrados para minúsculas (`neoId` → `neoid`). Ambientes cujo esquema do
  Fusion no PostgreSQL tenha sido criado com identificadores aspados em caixa
  mista exigirão aspear os identificadores.
