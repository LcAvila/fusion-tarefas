# Arquitetura

## Visão geral

O Fusion Tarefas é uma extensão publicada dentro de um contexto Fusion já
existente (`webapps/fusion`). Ele adiciona uma tela de consulta de tarefas
atrasadas e um endpoint de notificação por e-mail, sem substituir componentes da
plataforma.

```text
Navegador
   │  (sessão autenticada no Fusion)
   ▼
Fusion (webapps/fusion)
   ├── custom/fusion-tarefas/tarefas-atrasadas.jsp   → relatório (GET)
   ├── custom/fusion-tarefas/css/style.css           → estilos
   ├── custom/fusion-tarefas/script/script.js        → interface
   ├── WEB-INF/classes/br/com/fusion/tarefas/…        → classes Java
   └── /custom/task-notification                     → TaskNotificationServlet (POST)
            │                     │
            ▼                     ▼
        MySQL (Fusion)        SMTP (Jakarta Mail)
```

## Componentes

| Componente | Responsabilidade |
|---|---|
| `web/tarefas-atrasadas.jsp` | Consulta, filtros, paginação e renderização da tela; verifica autenticação e autorização; expõe os dados das tarefas para o JavaScript. |
| `web/script/script.js` | Interação da interface (filtros, modal, seleção), monta e envia o POST de notificação com `X-Requested-With: XMLHttpRequest`. |
| `web/css/style.css` | Estilos da tela. |
| `controller.TaskNotificationServlet` | Endpoint `/custom/task-notification`. No `POST`, verifica autenticação, autorização e mesma origem, valida os identificadores e dispara os e-mails. |
| `repository.TarefaRepository` | Acesso ao banco do Fusion (consultas parametrizadas) e resolução dos destinatários. |
| `security.Autorizacao` | Identifica o usuário (principal/remote user/atributos de sessão) e verifica se pertence ao grupo administrativo. |
| `config.AppConfig` | Leitura do arquivo de propriedades externo. |
| `model.*` | Estruturas de dados: `TarefaNotificacao`, `DestinatarioNotificacao`, `ResultadoEnvioNotificacao`. |

## Fluxo de consulta (GET)

1. O navegador acessa `custom/fusion-tarefas/tarefas-atrasadas.jsp` dentro da
   sessão autenticada do Fusion.
2. A JSP usa `Autorizacao.identificarUsuario` e `Autorizacao.ehAdministrador`;
   se não houver autenticação, responde `401`; se não houver autorização,
   responde `403`.
3. A JSP lê os filtros da requisição, valida-os e executa consultas
   parametrizadas:
   - contagem total (`COUNT(*)`);
   - página atual com `LIMIT/OFFSET`, ordenada por data de vencimento;
   - valores distintos para os campos de sugestão de filtro.
4. Os registros são renderizados na tabela; o JavaScript habilita seleção,
   detalhamento e notificação.

## Fluxo de notificação (POST)

1. O usuário seleciona tarefas e aciona a notificação.
2. O JavaScript envia `POST /custom/task-notification` com `taskInstanceId` e o
   cabeçalho `X-Requested-With: XMLHttpRequest`.
3. O servlet:
   - exige usuário autenticado (`401` se ausente);
   - exige autorização administrativa (`403` se ausente);
   - valida a origem da requisição (mitigação de CSRF) usando `Origin`/`Referer`
     quando presentes;
   - valida o `taskInstanceId`;
   - busca a tarefa, resolve os destinatários e envia os e-mails;
   - devolve um resumo em JSON (total, enviadas, falhas).
4. Erros internos são registrados no log do servidor e devolvidos ao cliente de
   forma genérica.

## Modelo de dados

As consultas usam as tabelas do Fusion, entre elas:

- `taskinstance` — instâncias de tarefa (prazo, status, responsável, atividade).
- `wfprocess` — processos (código/protocolo, datas, solicitante).
- `processmodel` — modelos de processo (título, tipo da entidade).
- `neouser` — usuários (nome, e-mail, grupo).
- `securityentity` — entidades de segurança, incluindo grupos.
- `activity`, `activitymodel`, `roletaskassigner_roleset` — atribuição de
  responsáveis por papel.

As consultas usam `PreparedStatement` e parâmetros vinculados, evitando
concatenação direta de valores.

## Segurança

- **Autenticação:** exigida na tela e no endpoint (GET e POST).
- **Autorização:** restrita ao grupo administrativo (código `admG`) por consulta
  ao banco.
- **CSRF:** `POST` exige `X-Requested-With: XMLHttpRequest` e valida a origem
  quando `Origin`/`Referer` estão presentes.
- **Validação de entrada:** identificadores numéricos validados antes do uso;
  filtros convertidos e verificados.
- **Exposição de erros:** mensagens genéricas ao cliente; detalhes apenas no log.
- **Segredos:** mantidos em arquivo externo, fora do diretório web e do
  versionamento.

## Empacotamento e publicação

`scripts/build-release.sh` monta `dist/fusion-tarefas.tar.gz` com a raiz
`fusion-tarefas/` contendo `web/`, `src/` e
`config/fusion-tarefas.properties.example`. O instalador publica:

- `web/…` → `webapps/fusion/custom/fusion-tarefas/…`
- classes compiladas → `webapps/fusion/WEB-INF/classes/br/com/fusion/tarefas/…`

O arquivo de propriedades permanece fora do diretório web.

## Limitações arquiteturais

- Não há empacotamento em `.war`; a publicação assume contexto expandido.
- A detecção automática de ambiente assume `systemd` e um único nó Tomcat.
- A autorização depende do esquema de grupos do Fusion; em ambientes com modelo
  diferente, a verificação precisa ser adaptada.
