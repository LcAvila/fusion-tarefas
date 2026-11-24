# Instalação

Este documento descreve o empacotamento, a instalação automatizada e a
instalação manual do Fusion Tarefas em um contexto Fusion já instalado.

## Pré-requisitos

No servidor:

- Linux com Bash 4+, Python 3, `systemd` e `sudo`.
- Fusion Platform em execução, com contexto expandido em `webapps/fusion`.
- Tomcat compatível com Jakarta (10.1 no ambiente testado).
- JDK com `javac` e `javap` acessível pelo processo do Fusion.
- Bibliotecas no Fusion: `servlet-api.jar` (Tomcat) e, em `WEB-INF/lib`, MySQL
  Connector/J, Jakarta Mail API, Angus Mail, Jakarta Activation API e Angus
  Activation.
- Banco MySQL acessível com conta dedicada de leitura.
- SMTP com STARTTLS e autenticação.

No cliente (para instalação remota):

- Bash, `ssh`, `scp` e `sha256sum`.

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

Coloque `install-fusion-tarefas.sh` e `dist/fusion-tarefas.tar.gz` no mesmo
diretório. Use apenas pacotes confiáveis e revisados: o instalador executa
operações administrativas.

```bash
bash -n install-fusion-tarefas.sh
bash install-fusion-tarefas.sh fusion-tarefas.tar.gz
```

O script oferece **instalação local** (no próprio computador Linux) ou
**remota**. Na remota, informe o IP/hostname do servidor, o usuário SSH e a
porta (padrão 22). Confirme a identidade do servidor SSH.

### O que o instalador faz

1. Transfere o pacote e o próprio instalador via SSH/SCP para um diretório
   temporário no servidor.
2. Confere o SHA-256 do pacote transferido.
3. Interrompe se outra instalação estiver em andamento.
4. Extrai o pacote com validações (sem links, caminhos absolutos, travessia de
   diretório ou entradas duplicadas).
5. Localiza o projeto verificando `src/br/com/fusion/tarefas` junto de
   `web/tarefas-atrasadas.jsp`.
6. Deteta o processo Tomcat do Fusion (`-Dcatalina.base`, contexto
   `webapps/fusion`), o JDK utilizado, o proprietário e o serviço `systemd`.
7. Verifica `servlet-api.jar` e as bibliotecas Java necessárias.
8. Compila todas as classes Java em um diretório temporário. Se a compilação
   falhar, a instalação é interrompida sem alterar o ambiente.
9. Cria um backup em `/var/backups/fusion-tarefas.*` antes de modificar qualquer
   arquivo.
10. Prepara ou preserva o arquivo externo de propriedades, atualizando apenas
    `fusion.url`.
11. Confirma, com você, a autorização para parar o serviço, publicar e
    reiniciar.
12. Publica os recursos web em `webapps/fusion/custom/fusion-tarefas` e as
    classes compiladas em `webapps/fusion/WEB-INF/classes/br/com/fusion/tarefas`.
13. Ajusta proprietário e permissões e apresenta os endereços de teste e as
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

O instalador **não solicita** senhas de banco de dados nem de SMTP.

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
