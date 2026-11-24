# Solução de problemas

Esta página reúne sintomas comuns e o que verificar. Substitua `<servidor>` e
`<serviço>` pelos valores do seu ambiente.

## Durante a instalação

| Sintoma | Verificação |
|---|---|
| `systemctl não encontrado` | O instalador exige `systemd`. Em ambientes sem `systemd` (contêineres, outros gerenciadores), faça a publicação manual conforme [instalacao.md](instalacao.md#instalação-manual). |
| `Nenhum Tomcat Fusion ativo ... detectado` | Confirme que o Fusion está em execução e que existe o contexto expandido `webapps/fusion/WEB-INF/classes`. |
| `Serviço systemd não encontrado` | Verifique se o serviço é gerenciado pelo `systemd` e se o nome está correto. |
| `MainPID do serviço não corresponde ...` | O processo Tomcat pode ser iniciado por um wrapper. Localize o serviço correto ou faça a publicação manual. |
| `JDK do processo sem javac/javap` | O Fusion foi iniciado com um JRE. Use um JDK compatível (21 no ambiente testado). |
| `Biblioteca ausente: ...` | Instale a biblioteca indicada em `WEB-INF/lib` do Fusion (driver JDBC do banco — MySQL Connector/J **ou** driver PostgreSQL —, Jakarta Mail, Angus Mail, ativação). O instalador verifica apenas o driver do banco selecionado. |
| `Driver JDBC do banco ... não encontrado` | O driver do banco escolhido não está em `WEB-INF/lib`. Coloque o JAR correspondente (MySQL Connector/J ou `postgresql-*.jar`) e execute novamente. |
| `Não foi possível detectar o banco` / prompt inesperado | O instalador não achou `db.type` nem o prefixo de `db.url` nas configurações. Ele solicitará o tipo (`[1] MySQL` / `[2] PostgreSQL`); confirme o banco que o Fusion realmente usa. |
| `Validação do banco falhou` / erro de consulta na pré-publicação | A conexão ou uma consulta do recurso falhou antes da publicação. Confira host/porta, credenciais, permissões de leitura e o dialeto do banco. Nada foi publicado. |
| `A compilação falhou` | Verifique o JDK, as bibliotecas e os fontes. A instalação é interrompida sem alterar o ambiente. |
| `Checksum da transferência incorreto` | Refaça a transferência; confirme o pacote e o arquivo `.sha256`. |

## Após a instalação

| Sintoma | Verificação |
|---|---|
| HTTP 404 na tela | Confirme o contexto (`/fusion`), os arquivos em `custom/fusion-tarefas` e o mapeamento do servlet. |
| HTTP 401 | O usuário não está autenticado no Fusion. Faça login e tente novamente. |
| HTTP 403 | O usuário não pertence ao grupo administrativo configurado (`admG`). Ajuste o grupo ou a constante `GRUPO_ADMIN`, conforme [configuracao.md](configuracao.md#autorização-de-acesso). |
| HTTP 500 / `NoSuchMethodError` / `ClassNotFoundException` | Publique o conjunto completo de classes, verifique o log do Fusion e reinicie o serviço. Confirme que a compilação usou as bibliotecas corretas. |
| Servlet não inicializa / erro de configuração | Verifique se `-Dfusion.config.path` está definida e aponta para um arquivo legível pelo processo do Fusion. |
| Erro de banco de dados | Verifique conectividade, nome do schema, credenciais, permissões de leitura e a consulta informada no log. Confirme que `db.type` (ou o prefixo de `db.url`) corresponde ao banco em uso. |
| No PostgreSQL: `column ... does not exist` | No PostgreSQL, identificadores não aspados são convertidos para minúsculas (`neoId` → `neoid`). As consultas usam os nomes sem aspas; se o esquema do Fusion foi criado com identificadores aspeados (maiúsculas), alinhe a convenção. Veja [arquitetura.md](arquitetura.md). |
| Lista vazia sem erro | Pode não haver tarefas que atendam ao filtro (processo em andamento, prazo vencido e status elegível). Revise os filtros. |
| Falha de e-mail | Verifique host/porta SMTP, STARTTLS, credenciais, remetente autorizado e conectividade de rede. Consulte o log do servidor. |
| Envio parcial | Não repita automaticamente o POST. Verifique o resumo retornado e os logs; parte dos e-mails pode ter sido enviada. |
| Erro genérico ao notificar | A mensagem ao cliente é intencionalmente genérica. Consulte o log do servidor para o detalhe. |

## Logs

- Logs do Fusion/Tomcat (por exemplo, `logs/catalina.out` ou `logs/localhost.*`).
- Os eventos do recurso são registrados com marcadores como
  `TASK_NOTIFICATION_ACESSO_NEGADO`, `TASK_NOTIFICATION_CSRF_BLOQUEADO`,
  `TASK_NOTIFICATION_ERROR`, `TASK_NOTIFICATION_SEND_ERROR` e
  `ERRO_CONSULTA_TAREFAS` / `ERRO_AUTORIZACAO_JSP`.

Ao compartilhar logs, remova nomes, e-mails, identificadores e quaisquer dados
pessoais.
