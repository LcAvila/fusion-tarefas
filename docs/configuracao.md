# Configuração

O Fusion Tarefas lê um único arquivo de propriedades Java, mantido **fora** do
diretório web. As credenciais de banco de dados e SMTP podem ser preenchidas
manualmente ou durante a instalação (o instalador solicita os dados de conexão),
mas o arquivo nunca é publicado no diretório web.

## Localização do arquivo

Sugestão de caminho (ajuste ao seu ambiente):

```text
/opt/fusion/config/fusion-tarefas.properties
```

O caminho é informado ao Fusion por meio de uma propriedade de sistema no
arranque da JVM:

```text
-Dfusion.config.path=/opt/fusion/config/fusion-tarefas.properties
```

Adicione essa opção ao mecanismo de inicialização efetivamente usado pelo Fusion
(por exemplo, `JAVA_OPTS` no script de início ou `Environment=` na unidade
`systemd`), preservando as opções já existentes. Reinicie o Fusion em uma janela
autorizada após alterar o arranque.

> Sem `-Dfusion.config.path`, o servlet de notificação não inicializa e a tela
> não consegue ler a configuração.

## Propriedades

| Propriedade | Obrigatória | Descrição |
|---|---|---|
| `fusion.url` | Sim | URL pública do Fusion, incluindo o contexto, sem barra final. Ex.: `https://fusion.exemplo.com/fusion`. Usada para montar o link da tarefa no e-mail. |
| `db.type` | Não | Tipo do banco: `mysql` ou `postgresql`. Quando ausente, é deduzido do prefixo de `db.url` (`jdbc:mysql:` ou `jdbc:postgresql:`), preservando os arquivos de instalações anteriores. |
| `db.url` | Sim | URL JDBC do banco. MySQL: `jdbc:mysql://host:3306/fusion`. PostgreSQL: `jdbc:postgresql://host:5432/fusion`. |
| `db.user` | Sim | Usuário do banco, restrito a leitura nas tabelas utilizadas. |
| `db.password` | Sim | Senha do usuário do banco. |
| `smtp.host` | Sim | Servidor SMTP. |
| `smtp.port` | Sim | Porta SMTP. O código usa STARTTLS; `587` é o valor usual. |
| `smtp.username` | Sim | Usuário de autenticação SMTP. |
| `smtp.password` | Sim | Senha de autenticação SMTP. |
| `smtp.from` | Sim | Endereço remetente. |
| `smtp.from.name` | Não | Nome exibido do remetente. Padrão: `Fusion`. |

`fusion.url` é obrigatória e não possui valor padrão. Sem ela, o envio de
notificação falha de forma controlada.

## Banco de dados

O recurso é compatível com **MySQL** e **PostgreSQL** e o acesso é feito via
JDBC com declarações preparadas (apenas `SELECT`). O tipo é definido por
`db.type` ou deduzido do prefixo de `db.url`; o driver correspondente
(`com.mysql.cj.jdbc.Driver` ou `org.postgresql.Driver`) precisa estar em
`WEB-INF/lib`. As tabelas consultadas dependem do esquema do Fusion, incluindo
`taskinstance`, `wfprocess`, `processmodel`, `neouser`, `securityentity`,
`activity`, `activitymodel` e `roletaskassigner_roleset`.

As diferenças de dialeto ficam isoladas em
`br.com.fusion.tarefas.config.BancoDados`. O comportamento é preservado entre os
bancos: por exemplo, `TIMESTAMPDIFF(DAY, coluna, NOW())` (MySQL) equivale a
`TRUNC(EXTRACT(EPOCH FROM (NOW() - coluna)) / 86400)` (PostgreSQL), e o
predicado de coluna ativa usa `= 1` (MySQL) ou `= TRUE` (PostgreSQL).

> **Identificadores no PostgreSQL:** identificadores não aspados são convertidos
> para minúsculas (`neoId` → `neoid`). As consultas do recurso usam os nomes sem
> aspas, o que corresponde ao esquema do Fusion quando criado com a mesma
> convenção. Se o esquema no PostgreSQL usar identificadores aspados em caixa
> mista, ele precisará ser ajustado (ou as consultas, aspeadas).

Recomendações:

- Crie um usuário dedicado com permissão apenas de `SELECT` nas tabelas
  utilizadas.
- Não reutilize credenciais administrativas do Fusion.
- Restrinja o acesso por rede (host de origem do servidor Fusion).

## SMTP

O envio usa a API Jakarta Mail com autenticação e STARTTLS:

- `mail.smtp.auth=true`
- `mail.smtp.starttls.enable=true`
- `mail.smtp.starttls.required=true`

O servidor SMTP precisa aceitar esse mecanismo. Outros modos de autenticação
(como OAuth2) não foram implementados nem validados. Garanta que o remetente
configurado esteja autorizado a enviar pelo servidor.

## Permissões

- O arquivo de propriedades deve pertencer ao usuário do processo Fusion e ter
  permissão restrita, por exemplo:

  ```bash
  sudo chown <usuario-do-fusion>:<grupo-do-fusion> /opt/fusion/config/fusion-tarefas.properties
  sudo chmod 600 /opt/fusion/config/fusion-tarefas.properties
  ```

- Mantenha o arquivo fora do diretório web e fora do controle de versão.
- Nunca versione valores reais; use
  `config/fusion-tarefas.properties.example` como referência.

## Exemplo

```properties
fusion.url=https://fusion.exemplo.com/fusion

# Banco: use o bloco do MySQL ou o do PostgreSQL.
# MySQL (porta padrão 3306)
db.type=mysql
db.url=jdbc:mysql://servidor-exemplo:3306/fusion
db.user=fusion_readonly
db.password=

# PostgreSQL (porta padrão 5432) - use no lugar do bloco MySQL acima
# db.type=postgresql
# db.url=jdbc:postgresql://servidor-exemplo:5432/fusion
# db.user=fusion_readonly
# db.password=

smtp.host=smtp.exemplo.com
smtp.port=587
smtp.username=notificacoes@exemplo.com
smtp.password=
smtp.from=notificacoes@exemplo.com
smtp.from.name=Fusion
```

## Autorização de acesso

A tela e o endpoint de notificação exigem que o usuário autenticado pertença ao
grupo administrativo definido em
`br.com.fusion.tarefas.security.Autorizacao` (código `admG`). A verificação é
feita por consulta ao banco do Fusion, nas tabelas `securityentity` e
`neouser`.

Se o modelo de grupos do seu ambiente utilizar um código diferente, ajuste a
constante `GRUPO_ADMIN` e revalide o acesso. Caso o esquema de segurança do
ambiente seja incompatível com essa consulta, a verificação precisa ser adaptada
antes do uso em produção.
