#!/usr/bin/env bash
# Fusion Tarefas — instalador Linux / SSH. Bash 4+, Python 3, Tomcat 10.1, JDK 21.
set -Eeuo pipefail
umask 077
fail(){ printf 'ERRO: %s\n' "$*" >&2; exit 1; }
ask(){ local answer; read -r -p "$1" answer </dev/tty; printf '%s' "$answer"; }
yesno(){ [[ $(ask "$1 [s/N] ") =~ ^[sS]$ ]]; }
need(){ command -v "$1" >/dev/null || fail "Dependência ausente: $1"; }
if [[ ${1:-} != --server ]]; then
  for c in ssh sha256sum tar base64 mkfifo stty; do need "$c"; done
  archive=${1:-$(ask 'Caminho do arquivo .tar.gz: ')}
  [[ -f $archive ]] || fail 'Pacote não encontrado.'
  if yesno 'Instalar neste computador Linux (sem SSH)?'; then
    exec sudo bash "$0" --server "$archive"
  fi
  host=$(ask 'Servidor (IP ou hostname): '); user=$(ask 'Usuário SSH: '); port=$(ask 'Porta SSH [22]: '); port=${port:-22}
  [[ $host =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && $user =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ && $port =~ ^[0-9]{1,5}$ ]] || fail 'Dados SSH inválidos.'
  target="$user@$host"
  relay=
  bundle=$(mktemp -d); trap 'rm -rf -- "$bundle"' EXIT
  cp -- "$archive" "$bundle/project.tar.gz"; cp -- "$0" "$bundle/install.sh"
  hash=$(sha256sum < "$archive"); hash=${hash%% *}
  tar -czf "$bundle/payload.tar.gz" -C "$bundle" project.tar.gz install.sh
  # base64 mantém o pacote íntegro mesmo trafegando por um terminal (só ASCII).
  base64 < "$bundle/payload.tar.gz" > "$bundle/payload.b64"
  # Rotina executada no servidor, dentro da única sessão SSH: consome o pacote
  # até o marcador, decodifica, extrai e chama o instalador (que segue inalterado).
  remote=$(cat <<'REMOTE'
umask 077
stty -echo 2>/dev/null || true
d=$(mktemp -d /tmp/fusion-tarefas-upload.XXXXXXXX) || { printf 'ERRO: diretório remoto\n' >&2; exit 1; }
trap 'rm -rf -- "$d"' EXIT HUP INT TERM
{
  while IFS= read -r line; do
    [ "$line" = __FUSION_PAYLOAD_END__ ] && break
    printf '%s\n' "$line"
  done
} | base64 -d > "$d/payload.tar.gz" || { stty echo 2>/dev/null || true; printf 'ERRO: transferência do pacote incompleta\n' >&2; exit 1; }
stty echo 2>/dev/null || true
tar -xzf "$d/payload.tar.gz" -C "$d" || { printf 'ERRO: pacote inválido\n' >&2; exit 1; }
rm -f -- "$d/payload.tar.gz"
sudo bash "$d/install.sh" --server "$d/project.tar.gz" __HASH__
REMOTE
)
  remote=${remote/__HASH__/$hash}
  # A digitação aparece pelo pseudo-terminal remoto; desativamos o eco local para
  # não duplicar o que é digitado e para ocultar as senhas do sudo/MySQL/SMTP.
  local_tty=
  if [[ -t 0 ]]; then local_tty=$(stty -g); stty -echo; fi
  restore(){ if [[ -n $local_tty ]]; then stty "$local_tty" 2>/dev/null || true; fi; return 0; }
  fifo="$bundle/in.fifo"; mkfifo "$fifo"
  # Uma única sessão SSH (-tt força o pseudo-terminal): envia o pacote e, em
  # seguida, repassa o terminal para os prompts interativos do instalador — uma
  # senha SSH e, no máximo, uma senha sudo.
  { cat -- "$bundle/payload.b64"; printf '\n%s\n' __FUSION_PAYLOAD_END__; exec cat; } > "$fifo" &
  relay=$!
  trap 'kill "${relay:-}" 2>/dev/null || true; wait "${relay:-}" 2>/dev/null || true; restore; rm -rf -- "$bundle"' EXIT
  rc=0
  ssh -tt -p "$port" "$target" "$remote" < "$fifo" || rc=$?
  kill "$relay" 2>/dev/null || true; wait "$relay" 2>/dev/null || true
  restore
  [[ $rc == 0 ]] || fail 'A sessão SSH falhou.'
  exit
fi
shift
[[ $EUID == 0 ]] || fail 'Execute com sudo.'
for c in python3 systemctl ps sha256sum diff find flock install; do need "$c"; done
archive=$(realpath "${1:?Informe o pacote}"); [[ -f $archive ]] || fail 'Pacote ausente.'
actual=$(sha256sum < "$archive"); actual=${actual%% *}; [[ -z ${2:-} || $actual == "$2" ]] || fail 'Checksum da transferência incorreto.'
exec 9>/run/lock/fusion-tarefas-install.lock; flock -n 9 || fail 'Outra instalação em andamento.'
work=$(mktemp -d /tmp/fusion-tarefas-install.XXXXXXXX); trap 'rm -rf -- "$work"' EXIT
# Não extrair links, dispositivos, caminhos absolutos ou travessia de diretório.
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
mapfile -t roots < <(find "$work" -type d -path '*/src/br/com/fusion/tarefas' | while IFS= read -r d; do p=${d%/src/br/com/fusion/tarefas}; [[ -f $p/web/tarefas-atrasadas.jsp ]] && printf '%s\n' "$p"; done)
[[ ${#roots[@]} == 1 ]] || fail 'Estrutura web/src inválida.'
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
[[ ${#pids[@]} -gt 0 ]] || fail 'Nenhum Tomcat Fusion ativo com contexto expandido detectado.'
for p in "${pids[@]}"; do printf 'PID %s: ' "$p"; tr '\0' '\n' < "/proc/$p/cmdline" | grep '^-Dcatalina.base='; done
pid=${pids[0]}; if ((${#pids[@]}>1)); then pid=$(ask 'PID do Fusion correto: '); fi
[[ " ${pids[*]} " == *" $pid "* ]] || fail 'PID inválido.'
mapfile -d '' -t args < "/proc/$pid/cmdline"
base= home= current_config=
for a in "${args[@]}"; do case $a in -Dcatalina.base=*) base=${a#*=};; -Dcatalina.home=*) home=${a#*=};; -Dfusion.config.path=*) current_config=${a#*=};; esac; done
[[ -n $base && -n $home ]] || fail 'Tomcat não identificado.'
app="$base/webapps/fusion"; classes="$app/WEB-INF/classes"; dest="$app/custom/fusion-tarefas"; pkg="$classes/br/com/fusion/tarefas"
java=$(readlink -f "/proc/$pid/exe"); jdk=${java%/bin/java}; [[ -x $jdk/bin/javac && -x $jdk/bin/javap ]] || fail 'JDK do processo sem javac/javap.'
owner=$(ps -o euser:128= -p "$pid" | xargs); group=$(id -gn "$owner")
service=$(grep -oE '[^/]+\.service' "/proc/$pid/cgroup" | tail -1 || true)
[[ -n $service ]] || service=$(ask 'Serviço systemd do Fusion: ')
[[ $service =~ ^[a-zA-Z0-9_.@-]+\.service$ ]] || fail 'Serviço inválido.'
[[ $(systemctl show -p LoadState --value "$service") == loaded ]] || fail 'Serviço não encontrado.'
[[ $(systemctl show -p MainPID --value "$service") == "$pid" ]] || fail 'MainPID não corresponde ao Tomcat; requer adaptação manual.'
config=/opt/neomind/fusion/config/fusion-tarefas.properties
[[ $(realpath -m "$config") == "$config" ]] || fail 'Caminho de configuração contém link simbólico.'
setenv="$base/bin/setenv.sh"
printf 'Tomcat: %s\nFusion: %s\nServiço: %s\nUsuário: %s\nConfiguração: %s\nSHA256: %s\n' "$base" "$app" "$service" "$owner" "$config" "$actual"
yesno 'Confirma que este é o ambiente correto e que há autorização para instalação?' || exit 0
url=$(ask 'URL pública do Fusion (incluindo /fusion): '); url=${url%/}
[[ $url =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?/fusion$ ]] || fail 'URL inválida; esperado https://servidor/fusion.'
[[ -f $home/lib/servlet-api.jar ]] || fail 'servlet-api.jar ausente.'
for pattern in 'mysql-connector*.jar' 'jakarta.mail-api*.jar' 'angus-mail*.jar' 'jakarta.activation-api*.jar' 'angus-activation*.jar'; do compgen -G "$app/WEB-INF/lib/$pattern" >/dev/null || fail "Biblioteca ausente: $pattern (instale versão compatível manualmente)."; done
# Não publicar fontes, backups, bin, configurações ou bibliotecas do pacote na web.
mkdir "$work/web" "$work/build"
cp -a "$project/web/." "$work/web/"
find "$work/web" -type f \( -iname '*.bak*' -o -iname '*.log' -o -iname '*.properties' -o -iname '*.env*' -o -iname '*.java' -o -iname '*.class' -o -iname '*.jar' -o -iname '*.zip' -o -iname '*.tar*' \) -delete
find "$work/web" -type d \( -name backup -o -name .git \) -prune -exec rm -rf {} +
if grep -qiE 'jdbc:mysql|JDBC_PASSWORD|JDBC_USER|hml\.' "$work/web/tarefas-atrasadas.jsp"; then printf 'ATENÇÃO: JSP contém referências de banco ou homologação; revise sem expor segredos.\n'; fi
yesno 'Você revisou o pacote, a JSP, os segredos e a autorização do POST para este ambiente?' || fail 'Revisão obrigatória.'
mapfile -d '' -t sources < <(find "$project/src/br/com/fusion/tarefas" -type f -name '*.java' -print0)
((${#sources[@]} > 0)) || fail 'Fontes ausentes.'
"$jdk/bin/javac" -proc:none -encoding UTF-8 -cp "$classes:$home/lib/servlet-api.jar:$app/WEB-INF/lib/*" -sourcepath "$project/src" -d "$work/build" "${sources[@]}"
built="$work/build/br/com/fusion/tarefas"
for c in config/AppConfig controller/TaskNotificationServlet 'controller/TaskNotificationServlet$1' repository/TarefaRepository model/TarefaNotificacao model/DestinatarioNotificacao model/ResultadoEnvioNotificacao security/Autorizacao; do [[ -f $built/$c.class ]] || fail "Classe ausente: $c"; done
"$jdk/bin/javap" -classpath "$work/build" br.com.fusion.tarefas.repository.TarefaRepository | grep -q obterDestinatariosComNome || fail 'Método obrigatório ausente.'
printf 'Classes compiladas: '; find "$built" -name '*.class' | wc -l
# Preparar alterações sem modificar o servidor antes da confirmação.
[[ ! -L $setenv ]] || fail 'setenv.sh é link simbólico.'
if [[ $current_config != "$config" ]]; then
  systemctl show -p ExecStart --value "$service" | grep -Fq "path=$base/bin/startup.sh" || fail 'Inicialização não reconhecida; configure a JVM manualmente.'
  [[ ! -e $setenv || -f $setenv ]] || fail 'setenv.sh inválido.'
  yesno 'Autoriza configurar automaticamente o setenv.sh?' || exit 0
  python3 - "$setenv" "$work/setenv" "$config" <<'PYENV'
import pathlib,sys,re
p=pathlib.Path(sys.argv[1]); s=p.read_text() if p.exists() else '#!/bin/sh\n'
# Aceitar apenas parâmetros literais simples; outros formatos exigem revisão.
s=re.sub(r'(?<=\s)-Dfusion\.config\.path=[^\s"\']+', '', s)
if 'fusion.config.path' in s: raise SystemExit('Parâmetro JVM em formato não reconhecido')
pathlib.Path(sys.argv[2]).write_text(s.rstrip()+'\nexport CATALINA_OPTS="$CATALINA_OPTS -Dfusion.config.path='+sys.argv[3]+'"\n')
PYENV
  bash -n "$work/setenv"
fi
backup=$(mktemp -d /var/backups/fusion-tarefas.XXXXXXXX); chmod 700 "$backup"
for pair in "web:$dest" "classes:$pkg" "config:$config" "setenv:$setenv"; do name=${pair%%:*}; path=${pair#*:}; [[ ! -L $path ]] || fail "Destino é link simbólico: $path"; if [[ -e $path ]]; then cp -a -- "$path" "$backup/$name"; else touch "$backup/$name.absent"; fi; done
printf '%s\n' "$actual" > "$backup/package.sha256"
printf 'Backup: %s\n' "$backup"
# Java Properties: usar a própria implementação Java para preservar e escapar valores.
cat > "$work/Configure.java" <<'JAVA'
import java.io.*; import java.nio.file.*; import java.util.*;
class Configure {
 public static void main(String[] a) throws Exception {
  Console c=System.console(); if(c==null) throw new IOException("Terminal interativo necessário");
  Properties p=new Properties(); Path old=Path.of(a[0]);
  if(Files.isRegularFile(old)) try(var in=Files.newInputStream(old)){p.load(in);}
  boolean db=true, smtp=true;
  if(!p.isEmpty()){String mode=c.readLine("Configuração existente: [1] manter [2] banco [3] SMTP [4] tudo: "); if(!List.of("1","2","3","4").contains(mode)) throw new IOException("Opção inválida"); db=mode.equals("2")||mode.equals("4"); smtp=mode.equals("3")||mode.equals("4");}
  if(db){String host=ask(c,"Host MySQL", "localhost"); if(!host.matches("[a-zA-Z0-9.-]+")) throw new IOException("Host inválido"); String port=port(c,"Porta MySQL","3306"); String name=ask(c,"Banco", ""); if(!name.matches("[a-zA-Z0-9_-]+")) throw new IOException("Nome de banco inválido"); p.setProperty("db.url","jdbc:mysql://"+host+":"+port+"/"+name+"?sslMode="+tls(c)); p.setProperty("db.user",ask(c,"Usuário MySQL","")); secret(c,p,"db.password","Senha MySQL");}
  if(smtp){p.setProperty("smtp.host",ask(c,"Servidor SMTP","")); p.setProperty("smtp.port",port(c,"Porta SMTP","587")); String user=ask(c,"Usuário SMTP",""); p.setProperty("smtp.username",user); secret(c,p,"smtp.password","Senha SMTP"); p.setProperty("smtp.from",ask(c,"Remetente",user)); p.setProperty("smtp.from.name",ask(c,"Nome remetente","Fusion"));}
  p.setProperty("fusion.url",a[2]);
  for(String k:List.of("db.url","db.user","db.password","smtp.host","smtp.port","smtp.username","smtp.password","smtp.from")) if(p.getProperty(k,"").isBlank()) throw new IOException("Propriedade ausente: "+k);
  try(var out=Files.newOutputStream(Path.of(a[1]))){p.store(out,"Fusion Tarefas");}
 }
 static String ask(Console c,String label,String def)throws IOException{String v=c.readLine("%s [%s]: ",label,def); if(v==null)throw new EOFException(); return v.isBlank()?def:v;}
 static String port(Console c,String label,String def)throws IOException{String v=ask(c,label,def); if(!v.matches("[0-9]{1,5}")||Integer.parseInt(v)<1||Integer.parseInt(v)>65535)throw new IOException("Porta inválida"); return v;}
 static String tls(Console c)throws IOException{String v=ask(c,"TLS MySQL (VERIFY_IDENTITY, REQUIRED, DISABLED)","VERIFY_IDENTITY"); if(!List.of("VERIFY_IDENTITY","REQUIRED","DISABLED").contains(v))throw new IOException("TLS inválido");return v;}
 static void secret(Console c,Properties p,String key,String label)throws IOException{char[] v=c.readPassword("%s: ",label); if(v==null||v.length==0)throw new IOException("Senha vazia"); try{p.setProperty(key,new String(v));}finally{Arrays.fill(v,(char)0);}}
}
JAVA
old="$config"
if [[ ! -e $config && -n $current_config && -f $current_config ]]; then
  yesno 'Importar configuração existente do caminho anterior?' && old="$current_config"
fi
"$jdk/bin/java" "$work/Configure.java" "$old" "$work/config" "$url" </dev/tty
chmod 600 "$work/config"
yesno 'Confirma banco restrito a SELECT e configuração privada?' || exit 0
yesno 'Autoriza parar o Fusion, publicar e reiniciar agora?' || exit 0
# Parar antes de trocar arquivos; rollback automático em falha de publicação/start.
restore(){ local rc=$?; trap - ERR; set +e; printf 'Falha (%s). Restaurando backup %s\n' "$rc" "$backup" >&2; systemctl stop "$service"; for pair in "web:$dest" "classes:$pkg" "config:$config" "setenv:$setenv"; do name=${pair%%:*}; path=${pair#*:}; rm -rf -- "$path"; [[ ! -e $backup/$name ]] || cp -a -- "$backup/$name" "$path"; done; systemctl start "$service"; exit "$rc"; }
systemctl stop "$service"
trap restore ERR
mkdir -p "$(dirname "$config")"
stage=$(mktemp "$(dirname "$config")/.fusion-tarefas.XXXXXXXX")
install -m 600 -o "$owner" -g "$group" "$work/config" "$stage"
mv -fT "$stage" "$config"
if [[ -f $work/setenv ]]; then
  if [[ -f $setenv ]]; then cat "$work/setenv" > "$setenv"; else install -m 755 "$work/setenv" "$setenv"; fi
fi
runuser -u "$owner" -- test -r "$config"
mkdir -p "$(dirname "$dest")" "$(dirname "$pkg")"
rm -rf -- "$dest" "$pkg"
cp -a "$work/web" "$dest"; cp -a "$built" "$pkg"
chown -R "$owner:$group" "$dest" "$pkg"
find "$dest" "$pkg" -type d -exec chmod 755 {} +; find "$dest" "$pkg" -type f -exec chmod 644 {} +
diff -qr "$work/web" "$dest"; diff -qr "$built" "$pkg"
systemctl start "$service"; systemctl is-active --quiet "$service"
newpid=$(systemctl show -p MainPID --value "$service")
grep -zFxq -- "-Dfusion.config.path=$config" "/proc/$newpid/cmdline"
trap - ERR
printf '\nPublicação concluída (inicialização funcional ainda não verificada).\nBackup: %s\nEndpoint: %s/custom/task-notification\nTela: %s/custom/fusion-tarefas/tarefas-atrasadas.jsp\n' "$backup" "$url" "$url"
printf 'Valide logs, banco, menu, autorização GET/POST e somente então um envio controlado. Não repita POST automaticamente.\n'
