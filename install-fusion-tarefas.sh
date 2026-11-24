#!/usr/bin/env bash
# Fusion Tarefas - instalador Linux/SSH. Requer Bash 4+, Python 3, systemd,
# Tomcat compatível com Jakarta (10.1 no ambiente testado) e JDK 21.
#
# Modo cliente (sem privilégios): transfere o pacote via SSH/SCP.
#   bash install-fusion-tarefas.sh [pacote.tar.gz]
# Modo servidor (executado com sudo): instala localmente.
#   sudo bash install-fusion-tarefas.sh --server <pacote.tar.gz> [sha256]
#
# Este script não solicita senhas de banco nem de SMTP. Essas credenciais são
# configuradas manualmente no arquivo externo de propriedades.
set -Eeuo pipefail
umask 077
fail(){ printf 'ERRO: %s\n' "$*" >&2; exit 1; }
ask(){ local answer; read -r -p "$1" answer </dev/tty; printf '%s' "$answer"; }
yesno(){ [[ $(ask "$1 [s/N] ") =~ ^[sS]$ ]]; }
need(){ command -v "$1" >/dev/null || fail "Dependência ausente: $1"; }

if [[ ${1:-} != --server ]]; then
  need ssh; need scp; need sha256sum
  archive=${1:-$(ask 'Caminho do arquivo .tar.gz: ')}
  [[ -f $archive ]] || fail 'Pacote não encontrado.'
  if yesno 'Instalar neste computador Linux (sem SSH)?'; then
    exec sudo bash "$0" --server "$archive"
  fi
  host=$(ask 'Servidor (IP ou hostname): '); user=$(ask 'Usuário SSH: '); port=$(ask 'Porta SSH [22]: '); port=${port:-22}
  [[ $host =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && $user =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ && $port =~ ^[0-9]{1,5}$ ]] || fail 'Dados SSH inválidos.'
  target="$user@$host"
  remote=$(ssh -p "$port" "$target" 'umask 077; mktemp -d /tmp/fusion-tarefas-upload.XXXXXXXX')
  [[ $remote =~ ^/tmp/fusion-tarefas-upload\.[a-zA-Z0-9]+$ ]] || fail 'Diretório remoto inválido.'
  trap 'ssh -p "$port" "$target" "rm -rf -- $remote" || true' EXIT
  scp -P "$port" -- "$archive" "$target:$remote/project.tar.gz"
  scp -P "$port" -- "$0" "$target:$remote/install.sh"
  hash=$(sha256sum < "$archive"); hash=${hash%% *}
  ssh -t -p "$port" "$target" "sudo bash '$remote/install.sh' --server '$remote/project.tar.gz' '$hash'"
  exit
fi
shift
[[ $EUID == 0 ]] || fail 'Execute com sudo.'
for c in python3 ps sha256sum diff find flock install; do need "$c"; done
command -v systemctl >/dev/null || fail 'systemctl não encontrado. Este instalador exige systemd; ambientes sem systemd precisam ser configurados manualmente.'
archive=$(realpath "${1:?Informe o pacote}"); [[ -f $archive ]] || fail 'Pacote ausente.'
actual=$(sha256sum < "$archive"); actual=${actual%% *}; [[ -z ${2:-} || $actual == "$2" ]] || fail 'Checksum da transferência incorreto.'
exec 9>/run/lock/fusion-tarefas-install.lock; flock -n 9 || fail 'Outra instalação em andamento.'
work=$(mktemp -d /tmp/fusion-tarefas-install.XXXXXXXX); trap 'rm -rf -- "$work"' EXIT

# Extração segura: sem links, dispositivos, caminhos absolutos ou travessia de diretório.
python3 - "$archive" "$work" <<'PY'
import sys,tarfile,pathlib
with tarfile.open(sys.argv[1], 'r:*') as t:
    members=t.getmembers(); seen=set()
    if len(members)>50000 or sum(m.size for m in members)>1024**3: raise SystemExit('Pacote excede limite')
    for m in members:
        p=pathlib.PurePosixPath(m.name)
        if p.is_absolute() or '..' in p.parts or not (m.isfile() or m.isdir()) or '\\' in m.name: raise SystemExit('Entrada insegura no pacote: '+m.name)
        if p in seen and m.isfile(): raise SystemExit('Entrada duplicada: '+m.name)
        seen.add(p); m.mode=0o700 if m.isdir() else 0o600; m.uid=m.gid=0; m.uname=m.gname='root'
    t.extractall(sys.argv[2], members=members)
PY

# Localiza o projeto: web/tarefas-atrasadas.jsp ao lado de src/br/com/fusion/tarefas.
mapfile -t roots < <(find "$work" -type d -path '*/src/br/com/fusion/tarefas' | while IFS= read -r d; do p=${d%/src/br/com/fusion/tarefas}; [[ -f $p/web/tarefas-atrasadas.jsp ]] && printf '%s\n' "$p"; done)
[[ ${#roots[@]} == 1 ]] || fail 'Esperado um projeto com web/tarefas-atrasadas.jsp e src/br/com/fusion/tarefas.'
project=${roots[0]}

# Identificar apenas processos Tomcat com contexto Fusion expandido.
mapfile -t pids < <(python3 - <<'PY'
import glob,os
for p in glob.glob('/proc/[0-9]*/cmdline'):
 try:
  a=open(p,'rb').read().decode().split('\0'); b=next((x.split('=',1)[1] for x in a if x.startswith('-Dcatalina.base=')), '')
  if 'org.apache.catalina.startup.Bootstrap' in a and os.path.isdir(b+'/webapps/fusion/WEB-INF/classes'): print(p.split('/')[2])
 except (OSError,UnicodeError): pass
PY
)
[[ ${#pids[@]} -gt 0 ]] || fail 'Nenhum Tomcat Fusion ativo com contexto expandido detectado. Verifique se o Fusion está em execução e se webapps/fusion/WEB-INF/classes existe; neste caso a instalação deve ser feita manualmente.'
for p in "${pids[@]}"; do printf 'PID %s: ' "$p"; tr '\0' '\n' < "/proc/$p/cmdline" | grep '^-Dcatalina.base='; done
pid=${pids[0]}; if ((${#pids[@]}>1)); then pid=$(ask 'PID do Fusion correto: '); fi
[[ " ${pids[*]} " == *" $pid "* ]] || fail 'PID inválido.'
mapfile -d '' -t args < "/proc/$pid/cmdline"
base= home= current_config=
for a in "${args[@]}"; do case $a in -Dcatalina.base=*) base=${a#*=};; -Dcatalina.home=*) home=${a#*=};; -Dfusion.config.path=*) current_config=${a#*=};; esac; done
[[ -n $base && -n $home ]] || fail 'Tomcat não identificado (catalina.base/home ausentes).'
app="$base/webapps/fusion"; classes="$app/WEB-INF/classes"; dest="$app/custom/fusion-tarefas"; pkg="$classes/br/com/fusion/tarefas"
java=$(readlink -f "/proc/$pid/exe"); jdk=${java%/bin/java}; [[ -x $jdk/bin/javac && -x $jdk/bin/javap ]] || fail 'JDK do processo sem javac/javap.'
owner=$(ps -o euser:128= -p "$pid" | xargs); group=$(id -gn "$owner")
service=$(grep -oE '[^/]+\.service' "/proc/$pid/cgroup" | tail -1 || true)
[[ -n $service ]] || service=$(ask 'Serviço systemd do Fusion: ')
[[ $service =~ ^[a-zA-Z0-9_.@-]+\.service$ ]] || fail 'Serviço inválido.'
[[ $(systemctl show -p LoadState --value "$service") == loaded ]] || fail 'Serviço systemd não encontrado. Este instalador exige systemd; para outros gerenciadores, publique manualmente.'
[[ $(systemctl show -p MainPID --value "$service") == "$pid" ]] || fail 'MainPID do serviço não corresponde ao processo Tomcat; requer adaptação manual.'
config=${current_config:-/opt/fusion/config/fusion-tarefas.properties}
[[ $config == /* && $config != *[[:space:]]* && $config != *\'* ]] || fail 'Caminho de configuração não suportado.'
config=$(realpath -m "$config"); [[ $config != "$base/webapps/"* && $config != "$home/webapps/"* ]] || fail 'Configuração dentro da pasta web.'
printf 'Tomcat: %s\nFusion: %s\nServiço: %s\nUsuário: %s\nConfiguração: %s\nSHA256: %s\n' "$base" "$app" "$service" "$owner" "$config" "$actual"
yesno 'Confirma que este é o ambiente correto e que há autorização para instalação?' || exit 0
url=$(ask 'URL pública do Fusion (incluindo /fusion): '); url=${url%/}
[[ $url =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?/fusion$ ]] || fail 'URL inválida; esperado https://servidor/fusion.'
[[ -f $home/lib/servlet-api.jar ]] || fail 'servlet-api.jar ausente em CATALINA_HOME/lib.'
for pattern in 'mysql-connector*.jar' 'jakarta.mail-api*.jar' 'angus-mail*.jar' 'jakarta.activation-api*.jar' 'angus-activation*.jar'; do compgen -G "$app/WEB-INF/lib/$pattern" >/dev/null || fail "Biblioteca ausente: $pattern (instale versão compatível manualmente)."; done

# Não publicar fontes, backups, bin, configurações ou bibliotecas do pacote na web.
mkdir "$work/web" "$work/build"
cp -a "$project/web/." "$work/web/"
find "$work/web" -type f \( -iname '*.bak*' -o -iname '*.log' -o -iname '*.properties' -o -iname '*.env*' -o -iname '*.java' -o -iname '*.class' -o -iname '*.jar' -o -iname '*.zip' -o -iname '*.tar*' \) -delete
find "$work/web" -type d \( -name backup -o -name .git -o -name .settings -o -name dist \) -prune -exec rm -rf {} +
[[ -f $work/web/tarefas-atrasadas.jsp ]] || fail 'JSP ausente após preparação dos recursos web.'
if grep -qiE 'jdbc:mysql|JDBC_PASSWORD|JDBC_USER' "$work/web/tarefas-atrasadas.jsp"; then printf 'ATENÇÃO: a JSP contém referências de banco; revise sem expor segredos.\n'; fi
yesno 'Você revisou o pacote, a JSP, os segredos e a autorização do POST para este ambiente?' || fail 'Revisão obrigatória.'

mapfile -d '' -t sources < <(find "$project/src/br/com/fusion/tarefas" -type f -name '*.java' -print0)
((${#sources[@]} > 0)) || fail 'Fontes ausentes.'
"$jdk/bin/javac" -proc:none -encoding UTF-8 -cp "$classes:$home/lib/servlet-api.jar:$app/WEB-INF/lib/*" -sourcepath "$project/src" -d "$work/build" "${sources[@]}" || fail 'A compilação falhou; a instalação foi interrompida.'
built="$work/build/br/com/fusion/tarefas"
for c in config/AppConfig controller/TaskNotificationServlet 'controller/TaskNotificationServlet$1' repository/TarefaRepository model/TarefaNotificacao model/DestinatarioNotificacao model/ResultadoEnvioNotificacao security/Autorizacao; do [[ -f $built/$c.class ]] || fail "Classe ausente: $c"; done
"$jdk/bin/javap" -classpath "$work/build" br.com.fusion.tarefas.repository.TarefaRepository | grep -q obterDestinatariosComNome || fail 'Método obrigatório ausente.'
printf 'Classes compiladas: '; find "$built" -name '*.class' | wc -l

# Configuração de JVM: não editar unidade systemd ou scripts proprietários às cegas.
if [[ -z $current_config ]]; then
 printf 'Configure no mecanismo de inicialização do serviço %s o argumento JVM:\n-Dfusion.config.path=%s\nReinicie o Fusion e execute este instalador novamente.\n' "$service" "$config"
 fail 'Parâmetro JVM ausente; intervenção necessária para não alterar o serviço incorreto.'
fi
backup=$(mktemp -d /var/backups/fusion-tarefas.XXXXXXXX); chmod 700 "$backup"
for pair in "web:$dest" "classes:$pkg" "config:$config"; do name=${pair%%:*}; path=${pair#*:}; [[ ! -L $path ]] || fail "Destino é link simbólico: $path"; if [[ -e $path ]]; then cp -a -- "$path" "$backup/$name"; else touch "$backup/$name.absent"; fi; done
printf '%s\n' "$actual" > "$backup/package.sha256"
printf 'Backup: %s\n' "$backup"

# Configuração manual: preservar valores existentes e atualizar apenas fusion.url.
mkdir -p "$(dirname "$config")"
python3 - "$config" "$url" "$work/config" <<'PY'
import sys,pathlib,re
p=pathlib.Path(sys.argv[1]); data=p.read_text(encoding='utf-8') if p.exists() else 'db.url=\ndb.user=\ndb.password=\nsmtp.host=\nsmtp.port=587\nsmtp.username=\nsmtp.password=\nsmtp.from=\nsmtp.from.name=Fusion\n'
data=re.sub(r'(?m)^\s*fusion\.url\s*[:=].*$', '', data)
pathlib.Path(sys.argv[3]).write_text(data.rstrip()+'\nfusion.url='+sys.argv[2]+'\n',encoding='utf-8')
PY
install -m 600 -o "$owner" -g "$group" "$work/config" "$config"
printf 'Edite manualmente banco e SMTP: sudoedit %s\n' "$config"
if ! yesno 'As credenciais já estão corretas, o banco é restrito a SELECT e a JSP usa configuração privada?'; then printf 'Configuração preparada. Execute novamente após configurar. Backup: %s\n' "$backup"; exit 0; fi
python3 - "$config" <<'PY'
import sys
p={}
for l in open(sys.argv[1]):
 if '=' in l and not l.lstrip().startswith(('#','!')):
  k,v=l.split('=',1);p[k.strip()]=v.strip()
missing=[k for k in ['db.url','db.user','db.password','smtp.host','smtp.port','smtp.username','smtp.password','smtp.from','fusion.url'] if not p.get(k)]
if missing: raise SystemExit('Propriedades vazias: '+', '.join(missing))
PY
yesno 'Autoriza parar o Fusion, publicar e reiniciar agora?' || { printf 'Publicação cancelada. Configuração preparada. Backup: %s\n' "$backup"; exit 0; }

# Parar antes de trocar arquivos; rollback automático em falha de publicação/start.
restore(){ local rc=$?; trap - ERR; set +e; printf 'Falha (%s). Restaurando backup %s\n' "$rc" "$backup" >&2; systemctl stop "$service"; for pair in "web:$dest" "classes:$pkg" "config:$config"; do name=${pair%%:*}; path=${pair#*:}; rm -rf -- "$path"; [[ ! -e $backup/$name ]] || cp -a -- "$backup/$name" "$path"; done; systemctl start "$service"; exit "$rc"; }
systemctl stop "$service"
trap restore ERR
mkdir -p "$(dirname "$dest")" "$(dirname "$pkg")"
rm -rf -- "$dest" "$pkg"
cp -a "$work/web" "$dest"; cp -a "$built" "$pkg"
chown -R "$owner:$group" "$dest" "$pkg"
find "$dest" "$pkg" -type d -exec chmod 755 {} +; find "$dest" "$pkg" -type f -exec chmod 644 {} +
diff -qr "$work/web" "$dest"; diff -qr "$built" "$pkg"
systemctl start "$service"; systemctl is-active --quiet "$service"
trap - ERR

printf '\nPublicação concluída (inicialização funcional ainda não verificada).\n'
printf 'Backup: %s\n' "$backup"
printf 'Endpoint: %s/custom/task-notification\n' "$url"
printf 'Tela: %s/custom/fusion-tarefas/tarefas-atrasadas.jsp\n' "$url"
printf '\nRollback (se necessário), em janela autorizada:\n'
printf '  sudo systemctl stop %s\n' "$service"
printf '  sudo rm -rf %s %s\n' "$dest" "$pkg"
printf '  sudo cp -a %s/web %s\n' "$backup" "$dest"
printf '  sudo cp -a %s/classes %s\n' "$backup" "$pkg"
printf '  sudo cp -a %s/config %s\n' "$backup" "$config"
printf '  sudo chown -R %s:%s %s %s\n' "$owner" "$group" "$dest" "$pkg"
printf '  sudo systemctl start %s\n' "$service"
printf 'Obs.: se o backup contiver arquivos .absent, remova os destinos correspondentes em vez de restaurar.\n'
printf 'Valide logs, banco, menu, autorização GET/POST e somente então um envio controlado. Não repita POST automaticamente.\n'
