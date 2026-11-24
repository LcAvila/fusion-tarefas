# Fusion Tarefas

Extensão para a **Fusion Platform** para consultar tarefas atrasadas, aplicar
filtros e enviar notificações por e-mail aos responsáveis.

O projeto disponibiliza uma tela de relatório de tarefas atrasadas (JSP) e um
endpoint de envio de notificações, publicados em um contexto Fusion já
existente. Não inclui dependências proprietárias: usa a API de Servlet padrão,
o banco de dados do Fusion e a API Jakarta Mail.

> **Status:** a instalação manual foi validada em um ambiente de homologação com
> Tomcat 10.1.34, Java 21, MySQL e Jakarta Mail. O instalador automatizado teve a
> sintaxe e a compatibilidade do pacote verificadas, mas ainda precisa ser
> executado por completo em um servidor limpo. Não há garantia de compatibilidade
> universal — veja [Compatibilidade](#compatibilidade).

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
- MySQL (Connector/J)
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
- Cliente com Bash, SSH, SCP e `sha256sum` (para instalação remota).
- Bibliotecas disponíveis no Fusion: `servlet-api.jar` (Tomcat) e, em
  `WEB-INF/lib`, MySQL Connector/J, Jakarta Mail API, Angus Mail, Jakarta
  Activation API e Angus Activation.
- Banco MySQL acessível com conta dedicada de leitura e SMTP autorizado com
  STARTTLS e autenticação.
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
hostname/IP, usuário SSH e porta (padrão 22). Informe também a URL pública do
Fusion, por exemplo `https://fusion.exemplo.com/fusion`. O instalador:

- transfere o pacote e o instalador via SCP e confere o SHA-256;
- extrai o pacote com validações;
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

As credenciais de banco e SMTP são configuradas manualmente em um arquivo de
propriedades externo. Defina o caminho no arranque do Fusion:

```text
-Dfusion.config.path=/opt/fusion/config/fusion-tarefas.properties
```

Use [config/fusion-tarefas.properties.example](config/fusion-tarefas.properties.example)
como base. Detalhes em [docs/configuracao.md](docs/configuracao.md).

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

## Contribuições

Veja [CONTRIBUTING.md](CONTRIBUTING.md).

## Licenciamento

Distribuído sob a licença MIT — veja [LICENSE](LICENSE). A Fusion Platform e
suas dependências (Tomcat, MySQL Connector/J, Jakarta Mail, Angus Mail) possuem
seus próprios termos de licenciamento, que devem ser observados separadamente.
