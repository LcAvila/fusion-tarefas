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

### Corrigido

- Instalação remota deixou de usar multiplexação SSH
  (`ControlMaster`/`ControlPersist`/`ControlPath`) e `SCP`, que falhavam no Git
  Bash para Windows com `mux_client_request_session: read from master failed:
  Connection reset by peer`. O envio passou a usar uma única sessão SSH
  interativa (`ssh -tt`), com o pacote e o instalador trafegando em base64 para
  preservar a integridade, garantindo uma senha SSH e, no máximo, uma senha
  `sudo`, sem `sshpass` e sem armazenamento de senhas.

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
- A autorização do endpoint de notificação depende do grupo administrativo do
  banco do Fusion e precisa ser validada no ambiente alvo.
