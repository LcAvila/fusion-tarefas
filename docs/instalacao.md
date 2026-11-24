# Instalação

Este documento descreve o empacotamento, a instalação automatizada e a
instalação manual do Fusion Tarefas em um contexto Fusion já instalado.

## Pré-requisitos

No servidor:

- Linux com Bash 4+, Python 3, `systemd` e `sudo`.
- Fusion Platform em execução, com contexto expandido em `webapps/fusion`.
- Tomcat compatível com Jakarta (10.1 no ambiente testado).
- JDK com `javac` e `javap` acessível pelo processo do Fusion.
- Bibliotecas no Fusion: `servlet-api.jar` (Tomcat) e, em `WEB-INF/lib`, o
  driver JDBC do banco utilizado (MySQL Connector/J **ou** o driver JDBC do
  PostgreSQL), Jakarta Mail API, Angus Mail, Jakarta Activation API e Angus
  Activation.
- Banco MySQL **ou** PostgreSQL acessível com conta dedicada de leitura.
- SMTP com STARTTLS e autenticação.

No cliente (para instalação remota):

- Bash, `ssh`, `sha256sum`, `tar`, `base64`, `mkfifo` e `stty`. Compatível com
  Git Bash no Windows e Bash no Linux.

## Empacotamento

Na raiz do repositório:

```bash
bash scripts/build-release.sh
```

Resultado:

- `dist/fusion-tarefas.tar.gz` — pacote de distribuição.
- `dist/fusion-tarefas.tar.gz.sha256` — checksum SHA-256.

O TAR tem a raiz `fusion-tarefas/` contendo `web/`, `src/` e
`config/fusion-tarefas.properties.example`. Essa estrutura é o que o instalador
espera.

## Instalação automatizada

Coloque `install-fusion-tarefas-v2.sh` e `dist/fusion-tarefas.tar.gz` no mesmo
diretório. Use apenas pacotes confiáveis e revisados: o instalador executa
operações administrativas.

```bash
bash -n install-fusion-tarefas-v2.sh
bash install-fusion-tarefas-v2.sh fusion-tarefas.tar.gz
```

O script oferece **instalação local** (no próprio computador Linux) ou
**remota**. Na remota, informe o IP/hostname do servidor, o usuário SSH e a
porta (padrão 22). Confirme a identidade do servidor SSH.

A conexão remota usa uma **única sessão SSH interativa** (`ssh -tt`), sem
multiplexação (`ControlMaster`/`ControlPersist`) e sem `sshpass`. A senha SSH é
solicitada uma única vez e a senha `sudo`, no máximo uma vez. Ao abrir a sessão,
o servidor desliga o eco do pseudo-terminal e envia um marcador de sincronização
(um byte de controle); só então o cliente envia o pacote e o instalador
codificados em base64. O eco visível passa a vir do terminal local do cliente,
de modo que tudo o que você digita (URL, escolhas, usuários) aparece na tela
enquanto o conteúdo Base64 permanece oculto. Nas senhas (`sudo`, banco e SMTP),
o servidor sinaliza o cliente para desligar o eco local apenas durante a
digitação. A sessão permanece aberta após o envio para atender a todos os prompts
interativos (tipo de banco quando não detectável, credenciais do banco e de SMTP,
lidas de `/dev/tty`).
O estado do terminal é restaurado ao final, em sucesso, erro ou interrupção.
Nenhuma senha é armazenada e os arquivos temporários (locais e remotos) são
removidos ao término.

### O que o instalador faz

1. Abre uma única sessão SSH interativa, aguarda a sincronização e transfere,
   codificados em base64 e sem exibi-los na tela, o pacote e o próprio
   instalador para um diretório temporário no servidor.
2. Confere o SHA-256 do instalador e do pacote transferidos antes de qualquer
   execução privilegiada.
3. Interrompe se outra instalação estiver em andamento.
4. Extrai o pacote com validações (sem links, caminhos absolutos, travessia de
   diretório ou entradas duplicadas).
5. Localiza o projeto verificando `src/br/com/fusion/tarefas` junto de
   `web/tarefas-atrasadas.jsp`.
6. Deteta o processo Tomcat do Fusion (`-Dcatalina.base`, contexto
   `webapps/fusion`), o JDK utilizado, o proprietário e o serviço `systemd`.
7. Detecta o banco de dados do Fusion (MySQL ou PostgreSQL) a partir das
   configurações existentes; se não for possível detectar, pergunta a você qual
   banco é utilizado. Define a porta padrão (3306 ou 5432), monta a URL JDBC e
   seleciona o driver correspondente.
8. Verifica `servlet-api.jar` e as bibliotecas Java necessárias, incluindo o
   driver JDBC do banco selecionado (e **somente** ele): a dependência
   obrigatória do MySQL é removida quando o ambiente usa PostgreSQL.
9. Compila todas as classes Java em um diretório temporário. Se a compilação
   falhar, a instalação é interrompida sem alterar o ambiente.
10. Cria um backup em `/var/backups/fusion-tarefas.*` antes de modificar qualquer
    arquivo.
11. Prepara ou preserva o arquivo externo de propriedades, atualizando apenas
    `fusion.url` (e o tipo/URL do banco quando necessário); as demais
    propriedades de instalações anteriores são preservadas.
12. **Valida a conexão e todas as consultas do recurso** contra o banco
    informado, em modo somente leitura, **antes** de publicar qualquer arquivo.
    Se a validação falhar, a publicação é abortada sem alterar o ambiente.
13. Confirma, com você, a autorização para parar o serviço, publicar e
    reiniciar.
14. Publica os recursos web em `webapps/fusion/custom/fusion-tarefas` e as
    classes compiladas em `webapps/fusion/WEB-INF/classes/br/com/fusion/tarefas`.
15. Ajusta proprietário e permissões e apresenta os endereços de teste e as
    instruções de rollback.

### Sobres systemd

O instalador exige `systemd`. Se `systemctl` não estiver disponível ou o serviço
não for identificado, ele interrompe com uma mensagem explicativa e orienta a
configuração manual. Ele não presume o mecanismo de inicialização.

### Informações solicitadas apenas quando necessário

- O pacote, caso não seja informado na linha de comando.
- O host, o usuário SSH e a porta, apenas no modo remoto.
- O PID do Fusion, se mais de um processo for detectado.
- O nome do serviço, se não for possível derivá-lo do `cgroup`.
- A URL pública do Fusion, na forma `https://servidor/fusion`.
- O tipo de banco (`[1] MySQL` / `[2] PostgreSQL`), apenas quando não for
  possível detectá-lo automaticamente.
- As credenciais de banco de dados e de SMTP, quando o arquivo de propriedades
  ainda não as contém. Os prompts são lidos de `/dev/tty`; apenas as senhas são
  digitadas sem eco (o servidor sinaliza o cliente durante a digitação), para não
  aparecerem na tela nem no terminal remoto.

## Instalação manual

Use este roteiro quando a detecção automática não se aplicar (por exemplo, sem
`systemd`, WAR não expandido ou caminho de contexto diferente).

1. Copie o conteúdo de `web/` para o diretório de recursos customizados do
   Fusion, por exemplo:

   ```bash
   sudo mkdir -p "$CATALINA_BASE/webapps/fusion/custom/fusion-tarefas"
   sudo cp -a web/. "$CATALINA_BASE/webapps/fusion/custom/fusion-tarefas/"
   ```

2. Compile os fontes apontando para as bibliotecas do Fusion:

   ```bash
   mkdir -p /tmp/fusion-tarefas-build
   javac -proc:none -encoding UTF-8 \
     -cp "$CATALINA_HOME/lib/servlet-api.jar:$CATALINA_BASE/webapps/fusion/WEB-INF/lib/*" \
     -sourcepath src -d /tmp/fusion-tarefas-build \
     $(find src/br/com/fusion/tarefas -name '*.java')
   ```

3. Publique as classes:

   ```bash
   sudo cp -a /tmp/fusion-tarefas-build/br \
     "$CATALINA_BASE/webapps/fusion/WEB-INF/classes/"
   ```

4. Crie o arquivo de propriedades fora da pasta web e informe o caminho ao
   Fusion via `-Dfusion.config.path` (veja
   [configuracao.md](configuracao.md)).

5. Ajuste proprietário e permissões para o usuário do processo Fusion.

6. Reinicie o Fusion em uma janela autorizada.

## Testes de funcionamento

Substitua a URL de exemplo pelo endereço do ambiente:

- Tela: `https://<servidor>/fusion/custom/fusion-tarefas/tarefas-atrasadas.jsp`
- Endpoint (GET autenticado):
  `https://<servidor>/fusion/custom/task-notification`

Verificações:

1. Um usuário autenticado e pertencente ao grupo administrativo deve abrir a
   tela e visualizar a lista de tarefas atrasadas.
2. Aplicar filtros e conferir a paginação.
3. O GET autenticado ao endpoint deve retornar
   `{"success":true,"message":"Endpoint funcionando"}`. Isso não comprova acesso
   ao banco nem funcionamento do SMTP.
4. Um usuário não autenticado deve receber `401`.
5. Um usuário autenticado sem autorização deve receber `403`.
6. Só após validar autorização e proteção CSRF, faça um envio controlado de
   notificação para um destinatário autorizado.

Não repita automaticamente um POST que falhou: pode ter ocorrido envio parcial.

## Desinstalação

Para remover a extensão, pare o serviço em uma janela autorizada e remova os
arquivos publicados:

```bash
sudo systemctl stop <serviço>
sudo rm -rf "$CATALINA_BASE/webapps/fusion/custom/fusion-tarefas"
sudo rm -rf "$CATALINA_BASE/webapps/fusion/WEB-INF/classes/br/com/fusion/tarefas"
sudo systemctl start <serviço>
```

Mantenha o arquivo de propriedades e o backup até confirmar que não serão mais
necessários. Consulte [rollback.md](rollback.md) para restaurar uma versão
anterior em vez de remover.
