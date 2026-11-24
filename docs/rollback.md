# Backup e rollback

O Fusion Tarefas altera três destinos dentro do Fusion:

- recursos web em `webapps/fusion/custom/fusion-tarefas`;
- classes em `webapps/fusion/WEB-INF/classes/br/com/fusion/tarefas`;
- o arquivo externo de propriedades (`fusion-tarefas.properties`).

## Backup automático

Antes de alterar qualquer arquivo, o instalador cria um diretório de backup em:

```text
/var/backups/fusion-tarefas.XXXXXXXX
```

Conteúdo:

- `web/` — versão anterior dos recursos web (ou marcador `web.absent`);
- `classes/` — versão anterior das classes (ou marcador `classes.absent`);
- `config/` — versão anterior do arquivo de propriedades (ou marcador
  `config.absent`);
- `package.sha256` — checksum do pacote instalado.

O caminho do backup é exibido ao final da instalação. Guarde-o: o backup pode
conter credenciais, portanto proteja o acesso.

Se um marcador `*.absent` existir, significa que o destino não existia antes da
instalação; nesse caso, remova o destino em vez de restaurar.

## Rollback automático

Se ocorrer falha durante a publicação ou a inicialização do serviço, o
instalador tenta restaurar automaticamente os três destinos a partir do backup,
para o serviço e o inicia novamente. Isso cobre falhas de cópia e de início — não
detecta problemas funcionais posteriores (por exemplo, erros de consulta ou de
e-mail já em execução).

## Rollback manual

Use em uma janela de manutenção autorizada. Substitua `<serviço>`,
`<CATALINA_BASE>` e o caminho do backup pelos valores do seu ambiente.

```bash
sudo systemctl stop <serviço>

# Remova os arquivos introduzidos pela instalação
sudo rm -rf "<CATALINA_BASE>/webapps/fusion/custom/fusion-tarefas"
sudo rm -rf "<CATALINA_BASE>/webapps/fusion/WEB-INF/classes/br/com/fusion/tarefas"

# Restaure a versão anterior
sudo cp -a /var/backups/fusion-tarefas.XXXXXXXX/web \
    "<CATALINA_BASE>/webapps/fusion/custom/fusion-tarefas"
sudo cp -a /var/backups/fusion-tarefas.XXXXXXXX/classes \
    "<CATALINA_BASE>/webapps/fusion/WEB-INF/classes/br/com/fusion/tarefas"
sudo cp -a /var/backups/fusion-tarefas.XXXXXXXX/config \
    /opt/fusion/config/fusion-tarefas.properties

# Permissões
sudo chown -R <usuario-do-fusion>:<grupo-do-fusion> \
    "<CATALINA_BASE>/webapps/fusion/custom/fusion-tarefas" \
    "<CATALINA_BASE>/webapps/fusion/WEB-INF/classes/br/com/fusion/tarefas"

sudo systemctl start <serviço>
```

Depois, valide a aplicação (tela, filtros, acesso autorizado) antes de retomar a
operação normal.

## Cuidados

- Não restaure backups de outro ambiente.
- Não remova o backup até confirmar que a versão publicada está estável.
- Preserve proprietário e permissões ao restaurar.
- Se a instalação foi apenas parcial (sem reinício), o instalador exibe o
  caminho do backup e permite continuar depois; verifique o estado antes de
  repetir.
