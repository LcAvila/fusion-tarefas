#!/usr/bin/env bash
# Fusion Tarefas — instalador Linux / SSH. Bash 4+, Python 3, Tomcat 10.1, JDK 21.
set -Eeuo pipefail
umask 077
fail(){ printf '\n[ERRO] %s\n' "$*" >&2; exit 1; }
info(){ printf '%s\n' "$*"; }
step(){ printf '\n===== %s =====\n' "$*"; }
ask(){ local answer; read -r -p "$1" answer </dev/tty; printf '%s' "$answer"; }
yesno(){ [[ $(ask "$1 [s/N] ") =~ ^[sS]$ ]]; }
need(){ command -v "$1" >/dev/null || fail "Dependência ausente: $1"; }
if [[ ${1:-} != --server ]]; then
  for c in ssh sha256sum tar base64 mkfifo stty; do need "$c"; done
  step 'Instalação do Fusion Tarefas'
  info 'Este assistente publica o recurso Fusion Tarefas em um Fusion já instalado.'
  info 'Nada é alterado no servidor antes da sua confirmação final.'
  archive=${1:-$(ask 'Caminho do pacote .tar.gz (ex.: dist/fusion-tarefas.tar.gz): ')}
  [[ -f $archive ]] || fail 'Pacote não encontrado. Confira o caminho informado.'
  if yesno 'Instalar neste mesmo computador (Linux local, sem SSH)?'; then
    exec sudo bash "$0" --server "$archive"
  fi
  info ''
  info 'Instalação remota: informe os dados de acesso ao servidor do Fusion.'
  host=$(ask 'Endereço do servidor (IP ou hostname): '); user=$(ask 'Usuário SSH (com permissão de sudo): '); port=$(ask 'Porta do SSH [padrão 22]: '); port=${port:-22}
  [[ $host =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && $user =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ && $port =~ ^[0-9]{1,5}$ ]] || fail 'Dados SSH inválidos (revise host, usuário e porta).'
  [[ -r /dev/tty && -w /dev/tty ]] || fail 'Terminal interativo (/dev/tty) indisponível: a instalação remota exige um terminal.'
  target="$user@$host"
  # Reúne o pacote e o instalador em um único TAR e o codifica em base64, que é
  # composto apenas de ASCII, uma linha por vez, preservando os binários ao
  # trafegar pelo terminal.
  bundle=$(mktemp -d)
  cp -- "$archive" "$bundle/project.tar.gz"; cp -- "$0" "$bundle/install.sh"
  hash=$(sha256sum < "$archive"); hash=${hash%% *}
  ihash=$(sha256sum < "$0"); ihash=${ihash%% *}
  tar -czf "$bundle/payload.tar.gz" -C "$bundle" project.tar.gz install.sh
  base64 < "$bundle/payload.tar.gz" > "$bundle/payload.b64"
  rm -f -- "$bundle/payload.tar.gz"
  # Rotina remota: mantém o eco do pseudo-terminal DESLIGADO durante toda a
  # sessão (assim nada aparece em duplicidade, pois quem ecoa o que o usuário
  # digita é o terminal local do cliente), publica o marcador de sincronização,
  # consome o pacote até o marcador de fim, valida a integridade e só então chama
  # o instalador dentro da mesma sessão SSH.
  remote=$(cat <<'REMOTE'
umask 077
# Eco remoto desligado em toda a sessão: o eco visível vem do cliente.
stty -echo 2>/dev/null || true
printf '[fusion-tarefas] Conectado ao servidor; canal pronto para envio.\n'
printf '\003'
d=$(mktemp -d /tmp/fusion-tarefas-upload.XXXXXXXX) || { printf 'ERRO: falha ao criar diretório remoto\n' >&2; exit 1; }
trap 'stty echo 2>/dev/null || true; rm -rf -- "$d"' EXIT HUP INT TERM
{
  while IFS= read -r line; do
    [ "$line" = __FUSION_PAYLOAD_END__ ] && break
    printf '%s\n' "$line"
  done
} | base64 -d > "$d/payload.tar.gz" || { printf 'ERRO: transferência incompleta\n' >&2; exit 1; }
printf '[fusion-tarefas] Pacote recebido; verificando integridade...\n'
tar -xzf "$d/payload.tar.gz" -C "$d" || { printf 'ERRO: pacote inválido\n' >&2; exit 1; }
rm -f -- "$d/payload.tar.gz"
printf '%s  %s\n' __IHASH__ "$d/install.sh" | sha256sum -c - >/dev/null 2>&1 || { printf 'ERRO: instalador corrompido\n' >&2; exit 1; }
printf '%s  %s\n' __HASH__ "$d/project.tar.gz" | sha256sum -c - >/dev/null 2>&1 || { printf 'ERRO: pacote corrompido\n' >&2; exit 1; }
printf '[fusion-tarefas] Integridade confirmada (SHA-256). Iniciando o instalador.\n'
# Sudo: se já houver credencial em cache, não pede senha. Caso contrário, lê a
# senha com o eco local desligado (marcadores \001/\002 interpretados pelo
# cliente) e a repassa ao sudo via stdin, sem exibi-la na tela.
if sudo -n true 2>/dev/null; then
  sudo bash "$d/install.sh" --server "$d/project.tar.gz" __HASH__
else
  printf '\001'
  printf 'Senha de administrador (sudo) para %s: ' "$(id -un)"
  IFS= read -r -s sp </dev/tty || true
  printf '\002\n'
  printf '%s\n' "$sp" | sudo -S -p '' bash "$d/install.sh" --server "$d/project.tar.gz" __HASH__
  unset sp
fi
REMOTE
)
  remote=${remote//__IHASH__/$ihash}
  remote=${remote//__HASH__/$hash}
  # Estado do terminal preservado e restaurado em sucesso, erro ou interrupção.
  tty_saved=$(stty -g </dev/tty)
  in_fifo="$bundle/in.fifo"; out_fifo="$bundle/out.fifo"; ready="$bundle/ready"
  mkfifo "$in_fifo" "$out_fifo"
  feeder=; ssh_pid=
  cleanup(){
    local rc=$?
    trap - EXIT INT TERM HUP
    if [[ -n $feeder ]]; then kill "$feeder" 2>/dev/null || true; wait "$feeder" 2>/dev/null || true; fi
    if [[ -n $ssh_pid ]]; then kill "$ssh_pid" 2>/dev/null || true; wait "$ssh_pid" 2>/dev/null || true; fi
    stty "$tty_saved" </dev/tty 2>/dev/null || true
    rm -rf -- "$bundle"
    exit "$rc"
  }
  trap cleanup EXIT INT TERM HUP
  info ''
  info "Conectando a $target na porta $port..."
  info 'Você verá abaixo as etapas executadas no servidor. Digite normalmente:'
  info 'tudo o que não for senha aparece na tela enquanto você digita.'
  # Eco LOCAL ligado: é ele que mostra o que o usuário digita (URL, escolhas,
  # usuário de banco etc.). O eco remoto está desligado, então não há duplicação.
  # Nas senhas, o servidor envia \001/\002 para desligar/religar o eco local
  # apenas durante a leitura.
  stty echo </dev/tty 2>/dev/null || true
  # Alimenta o stdin da sessão SSH: aguarda a sincronização, envia o pacote e o
  # marcador de fim e, então, repassa o teclado lido EXPLICITAMENTE de /dev/tty.
  (
    while [[ ! -e $ready ]]; do sleep 0.1; done
    cat -- "$bundle/payload.b64"
    printf '\n%s\n' __FUSION_PAYLOAD_END__
    cat /dev/tty
  ) > "$in_fifo" &
  feeder=$!
  # Uma única conexão SSH com pseudo-terminal forçado (-tt), necessário para o
  # sudo e para os prompts interativos do instalador.
  ssh -tt -o ConnectTimeout=15 -p "$port" "$target" "$remote" < "$in_fifo" > "$out_fifo" 2>&1 &
  ssh_pid=$!
  # Relé byte a byte da saída da sessão para o terminal do usuário:
  #   \003  sincronização: habilita o envio do pacote;
  #   \001  desliga o eco local (durante a leitura de senha);
  #   \002  religa o eco local.
  exec 8>/dev/tty
  while IFS= read -r -N1 ch; do
    case $ch in
      $'\001') stty -echo </dev/tty 2>/dev/null || true ;;
      $'\002') stty echo  </dev/tty 2>/dev/null || true ;;
      $'\003') : > "$ready" ;;
      *) printf '%s' "$ch" >&8 ;;
    esac
  done < "$out_fifo" || true
  exec 8>&-
  rc=0; wait "$ssh_pid" || rc=$?
  [[ $rc == 0 ]] || fail 'A sessão SSH falhou.'
  exit
fi
shift
[[ $EUID == 0 ]] || fail 'Execute com sudo.'
step 'Instalador Fusion Tarefas — execução no servidor'
for c in python3 systemctl ps sha256sum diff find flock install; do need "$c"; done
archive=$(realpath "${1:?Informe o pacote}"); [[ -f $archive ]] || fail 'Pacote ausente.'
actual=$(sha256sum < "$archive"); actual=${actual%% *}; [[ -z ${2:-} || $actual == "$2" ]] || fail 'Checksum da transferência incorreto.'
info "Pacote recebido: $archive"
info "SHA-256: $actual"
exec 9>/run/lock/fusion-tarefas-install.lock; flock -n 9 || fail 'Outra instalação em andamento. Aguarde e tente novamente.'
work=$(mktemp -d /tmp/fusion-tarefas-install.XXXXXXXX); trap 'rm -rf -- "$work"' EXIT
info 'Verificando e extraindo o pacote (sem links, caminhos absolutos ou travessia de diretório)...'
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
info 'Localizando os fontes Java e a tela (JSP) do recurso no pacote...'
mapfile -t roots < <(find "$work" -type d -path '*/src/br/com/fusion/tarefas' | while IFS= read -r d; do p=${d%/src/br/com/fusion/tarefas}; [[ -f $p/web/tarefas-atrasadas.jsp ]] && printf '%s\n' "$p"; done)
[[ ${#roots[@]} == 1 ]] || fail 'Estrutura web/src inválida.'
project=${roots[0]}
info 'Procurando o Tomcat do Fusion em execução (contexto webapps/fusion)...'
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
[[ ${#pids[@]} -gt 0 ]] || fail 'Nenhum Tomcat Fusion ativo com contexto expandido detectado. Confirme que o Fusion está em execução.'
for p in "${pids[@]}"; do printf 'PID %s: ' "$p"; tr '\0' '\n' < "/proc/$p/cmdline" | grep '^-Dcatalina.base='; done
if ((${#pids[@]}>1)); then
  info 'Mais de um processo Tomcat do Fusion foi encontrado.'
  info 'Informe o PID do processo que atende à instalação (listados acima).'
  pid=$(ask 'PID correto do Fusion: ')
else
  pid=${pids[0]}
fi
[[ " ${pids[*]} " == *" $pid "* ]] || fail 'PID inválido (não é um dos processos listados).'
mapfile -d '' -t args < "/proc/$pid/cmdline"
base= home= current_config=
for a in "${args[@]}"; do case $a in -Dcatalina.base=*) base=${a#*=};; -Dcatalina.home=*) home=${a#*=};; -Dfusion.config.path=*) current_config=${a#*=};; esac; done
[[ -n $base && -n $home ]] || fail 'Tomcat não identificado.'
app="$base/webapps/fusion"; classes="$app/WEB-INF/classes"; dest="$app/custom/fusion-tarefas"; pkg="$classes/br/com/fusion/tarefas"
java=$(readlink -f "/proc/$pid/exe"); jdk=${java%/bin/java}; [[ -x $jdk/bin/javac && -x $jdk/bin/javap ]] || fail 'JDK do processo sem javac/javap.'
owner=$(ps -o euser:128= -p "$pid" | xargs); group=$(id -gn "$owner")
service=$(grep -oE '[^/]+\.service' "/proc/$pid/cgroup" | tail -1 || true)
if [[ -z $service ]]; then
  info 'Não foi possível deduzir o nome do serviço systemd do Fusion.'
  service=$(ask 'Nome do serviço systemd do Fusion (ex.: tomcat.service): ')
fi
[[ $service =~ ^[a-zA-Z0-9_.@-]+\.service$ ]] || fail 'Serviço inválido (use o formato nome.service).'
[[ $(systemctl show -p LoadState --value "$service") == loaded ]] || fail 'Serviço não encontrado pelo systemd.'
[[ $(systemctl show -p MainPID --value "$service") == "$pid" ]] || fail 'O MainPID do serviço não corresponde ao Tomcat; requer adaptação manual.'
config=/opt/neomind/fusion/config/fusion-tarefas.properties
[[ $(realpath -m "$config") == "$config" ]] || fail 'Caminho de configuração contém link simbólico.'
setenv="$base/bin/setenv.sh"
step 'Ambiente detectado'
printf '  Tomcat (catalina.base): %s\n  Aplicação Fusion: %s\n  Serviço systemd: %s\n  Usuário do processo: %s\n  Arquivo de configuração: %s\n  SHA-256 do pacote: %s\n' "$base" "$app" "$service" "$owner" "$config" "$actual"
yesno 'Confirma que este é o ambiente correto e que há autorização para instalar?' || { info 'Instalação cancelada pelo usuário. Nada foi alterado.'; exit 0; }
info ''
info 'A URL pública abaixo será usada nos links das notificações e nos endereços de teste.'
info 'Informe a URL completa do Fusion, terminando em /fusion. Ex.: https://servidor.exemplo.com/fusion'
url=$(ask 'URL pública do Fusion (ex.: https://servidor/fusion): '); url=${url%/}
[[ $url =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?/fusion$ ]] || fail 'URL inválida. Use o formato https://servidor/fusion (sem barra no final).'
[[ -f $home/lib/servlet-api.jar ]] || fail "servlet-api.jar ausente em $home/lib."
# Descobrir o banco do Fusion SEM consultar o banco: 1) configuração anterior do
# recurso (db.type/db.url); 2) driver JDBC presente no WEB-INF/lib; 3) pergunta,
# quando não for possível deduzir. Imprime "<tipo>\n<origem>".
detect_db(){
  local props=$1 libdir=$2 tipo
  if [[ -f $props ]]; then
    tipo=$(python3 - "$props" <<'PY' || true
import re,sys,pathlib
try: s=pathlib.Path(sys.argv[1]).read_text(errors='ignore')
except OSError: s=''
def get(k):
 m=re.search(r'(?m)^\s*'+re.escape(k)+r'\s*[:=]\s*(.*)$',s)
 return m.group(1).strip().lower() if m else ''
t,u=get('db.type'),get('db.url')
if t=='mysql' or u.startswith('jdbc:mysql:'): print('mysql')
elif t in ('postgres','postgresql') or u.startswith('jdbc:postgresql:'): print('postgresql')
PY
)
    if [[ -n $tipo ]]; then printf '%s\nconfiguração anterior do recurso\n' "$tipo"; return; fi
  fi
  local mysql=0 pg=0
  if compgen -G "$libdir/postgresql*.jar" >/dev/null; then pg=1; fi
  if compgen -G "$libdir/mysql-connector*.jar" >/dev/null; then mysql=1; fi
  if ((pg==1 && mysql==0)); then printf 'postgresql\ndriver em WEB-INF/lib\n'; return; fi
  if ((mysql==1 && pg==0)); then printf 'mysql\ndriver em WEB-INF/lib\n'; return; fi
  info 'Não foi possível detectar automaticamente o banco de dados do Fusion.'
  info 'Selecione o banco que o Fusion utiliza. O recurso apenas lê (somente SELECT).'
  local r; r=$(ask 'Banco de dados do Fusion — [1] MySQL, [2] PostgreSQL [padrão 1]: '); r=${r:-1}
  if [[ $r == 2 || $r =~ ^[Pp] ]]; then printf 'postgresql\nescolha do operador\n'; else printf 'mysql\nescolha do operador\n'; fi
}
mapfile -t db_detect < <(detect_db "$config" "$app/WEB-INF/lib")
db_kind=${db_detect[0]:-}; db_source=${db_detect[1]:-desconhecida}
if [[ $db_kind == postgresql ]]; then
  db_label='PostgreSQL'; db_port=5432; jdbc_pattern='postgresql*.jar'
else
  db_kind=mysql; db_label='MySQL'; db_port=3306; jdbc_pattern='mysql-connector*.jar'
fi
info "Banco de dados: $db_label (detectado por: $db_source; porta padrão: $db_port)"
info "Verificando as bibliotecas Java (mail, ativação e driver JDBC do $db_label) em WEB-INF/lib..."
for pattern in 'jakarta.mail-api*.jar' 'angus-mail*.jar' 'jakarta.activation-api*.jar' 'angus-activation*.jar'; do compgen -G "$app/WEB-INF/lib/$pattern" >/dev/null || fail "Biblioteca ausente: $pattern (instale versão compatível manualmente)."; done
compgen -G "$app/WEB-INF/lib/$jdbc_pattern" >/dev/null || fail "Biblioteca JDBC do $db_label ausente ($jdbc_pattern em WEB-INF/lib); instale o driver ou selecione o banco correto."
# Não publicar fontes, backups, bin, configurações ou bibliotecas do pacote na web.
info 'Preparando os arquivos web que serão publicados (removendo fontes, backups e segredos)...'
mkdir "$work/web" "$work/build"
cp -a "$project/web/." "$work/web/"
find "$work/web" -type f \( -iname '*.bak*' -o -iname '*.log' -o -iname '*.properties' -o -iname '*.env*' -o -iname '*.java' -o -iname '*.class' -o -iname '*.jar' -o -iname '*.zip' -o -iname '*.tar*' \) -delete
find "$work/web" -type d \( -name backup -o -name .git \) -prune -exec rm -rf {} +
if grep -qiE 'jdbc:(mysql|postgresql)|JDBC_PASSWORD|JDBC_USER|hml\.' "$work/web/tarefas-atrasadas.jsp"; then printf 'ATENÇÃO: a JSP contém referências de banco ou de homologação; revise antes de prosseguir sem expor segredos.\n'; fi
yesno 'Você revisou o pacote, a JSP, os segredos e a autorização do POST para este ambiente?' || fail 'Revisão obrigatória antes de continuar.'
info 'Compilando as classes Java do recurso com o JDK do Fusion...'
mapfile -d '' -t sources < <(find "$project/src/br/com/fusion/tarefas" -type f -name '*.java' -print0)
((${#sources[@]} > 0)) || fail 'Fontes Java ausentes no pacote.'
"$jdk/bin/javac" -proc:none -encoding UTF-8 -cp "$classes:$home/lib/servlet-api.jar:$app/WEB-INF/lib/*" -sourcepath "$project/src" -d "$work/build" "${sources[@]}"
built="$work/build/br/com/fusion/tarefas"
for c in config/AppConfig config/BancoDados controller/TaskNotificationServlet 'controller/TaskNotificationServlet$1' repository/TarefaRepository repository/TarefasSql model/TarefaNotificacao model/DestinatarioNotificacao model/ResultadoEnvioNotificacao security/Autorizacao; do [[ -f $built/$c.class ]] || fail "Classe ausente após a compilação: $c"; done
"$jdk/bin/javap" -classpath "$work/build" br.com.fusion.tarefas.repository.TarefaRepository | grep -q obterDestinatariosComNome || fail 'Método obrigatório ausente em TarefaRepository.'
printf 'Classes compiladas com sucesso: '; find "$built" -name '*.class' | wc -l
# Preparar alterações sem modificar o servidor antes da confirmação.
info 'Preparando a configuração da JVM (setenv.sh)...'
[[ ! -L $setenv ]] || fail 'setenv.sh é um link simbólico.'
if [[ $current_config != "$config" ]]; then
  systemctl show -p ExecStart --value "$service" | grep -Fq "path=$base/bin/startup.sh" || fail 'Inicialização não reconhecida; configure a JVM manualmente.'
  [[ ! -e $setenv || -f $setenv ]] || fail 'setenv.sh inválido.'
  yesno 'Autoriza configurar automaticamente o setenv.sh (apontando -Dfusion.config.path)?' || { info 'Instalação cancelada. Nada foi alterado.'; exit 0; }
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
info 'Criando backup dos arquivos que serão substituídos...'
backup=$(mktemp -d /var/backups/fusion-tarefas.XXXXXXXX); chmod 700 "$backup"
for pair in "web:$dest" "classes:$pkg" "config:$config" "setenv:$setenv"; do name=${pair%%:*}; path=${pair#*:}; [[ ! -L $path ]] || fail "Destino é link simbólico: $path"; if [[ -e $path ]]; then cp -a -- "$path" "$backup/$name"; else touch "$backup/$name.absent"; fi; done
printf '%s\n' "$actual" > "$backup/package.sha256"
info "Backup criado em: $backup"
# Java Properties: usar a própria implementação Java para preservar e escapar valores.
cat > "$work/Configure.java" <<'JAVA'
import java.io.*; import java.nio.file.*; import java.util.*;
class Configure {
 public static void main(String[] a) throws Exception {
  Console c=System.console(); if(c==null) throw new IOException("Terminal interativo necessário");
  Properties p=new Properties(); Path old=Path.of(a[0]);
  if(Files.isRegularFile(old)) try(var in=Files.newInputStream(old)){p.load(in);}
  boolean pg=a[3].equals("postgresql");
  String label=pg?"PostgreSQL":"MySQL", defPort=a[4];
  System.out.println("Configuração do banco de dados ("+label+") e do SMTP.");
  System.out.println("Pressione Enter para aceitar o valor sugerido entre [ ].");
  boolean db=true, smtp=true;
  if(!p.isEmpty()){System.out.println("Já existe uma configuração. O que deseja ajustar?");String mode=c.readLine("  [1] manter tudo  [2] banco de dados  [3] SMTP  [4] banco e SMTP: "); if(!List.of("1","2","3","4").contains(mode)) throw new IOException("Opção inválida (informe 1, 2, 3 ou 4)"); db=mode.equals("2")||mode.equals("4"); smtp=mode.equals("3")||mode.equals("4");}
  if(db){String host=ask(c,"Host do "+label,"localhost"); if(!host.matches("[a-zA-Z0-9.-]+")) throw new IOException("Host inválido"); String port=port(c,"Porta do "+label,defPort); String name=ask(c,"Nome do banco de dados "+label,""); if(!name.matches("[a-zA-Z0-9_-]+")) throw new IOException("Nome de banco inválido"); p.setProperty("db.type",pg?"postgresql":"mysql"); p.setProperty("db.url",pg?("jdbc:postgresql://"+host+":"+port+"/"+name+"?sslmode="+tls(c,"PostgreSQL","(verify-full, require, disable)","verify-full",List.of("verify-full","require","disable"))):("jdbc:mysql://"+host+":"+port+"/"+name+"?sslMode="+tls(c,"MySQL","(VERIFY_IDENTITY, REQUIRED, DISABLED)","VERIFY_IDENTITY",List.of("VERIFY_IDENTITY","REQUIRED","DISABLED")))); p.setProperty("db.user",ask(c,"Usuário do banco "+label,"")); secret(c,p,"db.password","Senha do banco "+label);}
  if(smtp){p.setProperty("smtp.host",ask(c,"Servidor SMTP","")); p.setProperty("smtp.port",port(c,"Porta SMTP","587")); String user=ask(c,"Usuário SMTP",""); p.setProperty("smtp.username",user); secret(c,p,"smtp.password","Senha SMTP"); p.setProperty("smtp.from",ask(c,"Remetente (e-mail de origem)",user)); p.setProperty("smtp.from.name",ask(c,"Nome exibido como remetente","Fusion"));}
  p.setProperty("fusion.url",a[2]);
  for(String k:List.of("db.url","db.user","db.password","smtp.host","smtp.port","smtp.username","smtp.password","smtp.from")) if(p.getProperty(k,"").isBlank()) throw new IOException("Propriedade ausente: "+k);
  try(var out=Files.newOutputStream(Path.of(a[1]))){p.store(out,"Fusion Tarefas");}
  System.out.println("Propriedades gravadas.");
 }
 static String ask(Console c,String label,String def)throws IOException{String v=c.readLine("%s [%s]: ",label,def); if(v==null)throw new EOFException(); return v.isBlank()?def:v;}
 static String port(Console c,String label,String def)throws IOException{String v=ask(c,label,def); if(!v.matches("[0-9]{1,5}")||Integer.parseInt(v)<1||Integer.parseInt(v)>65535)throw new IOException("Porta inválida"); return v;}
 static String tls(Console c,String label,String opts,String def,List<String> validos)throws IOException{String v=ask(c,"TLS "+label+" "+opts,def); if(!validos.contains(v))throw new IOException("TLS inválido");return v;}
 static void secret(Console c,Properties p,String key,String label)throws IOException{System.out.print("\u0001");System.out.flush();char[] v;try{v=c.readPassword("%s (não aparece na tela): ",label);}finally{System.out.print("\u0002");System.out.flush();} if(v==null||v.length==0)throw new IOException("Senha vazia"); try{p.setProperty(key,new String(v));}finally{Arrays.fill(v,(char)0);}}
}
JAVA
old="$config"
if [[ ! -e $config && -n $current_config && -f $current_config ]]; then
  yesno 'Importar configuração existente do caminho anterior?' && old="$current_config"
fi
info 'Configurando banco de dados e SMTP (responda às perguntas abaixo)...'
"$jdk/bin/java" "$work/Configure.java" "$old" "$work/config" "$url" "$db_kind" "$db_port" </dev/tty
chmod 600 "$work/config"
# Validar a conexão e TODAS as consultas do recurso com a configuração gerada,
# antes de publicar qualquer arquivo. Executa apenas SELECT (somente leitura).
cat > "$work/ValidarBanco.java" <<'JAVA'
import java.nio.file.*;
import java.sql.*;
import br.com.fusion.tarefas.config.AppConfig;
import br.com.fusion.tarefas.config.BancoDados;
import br.com.fusion.tarefas.repository.TarefasSql;
class ValidarBanco {
 public static void main(String[] a) throws Exception {
  AppConfig config=new AppConfig(Path.of(a[0]));
  String tipo=BancoDados.tipo(config);
  try(Connection conexao=BancoDados.conectar(config)){
   executar(conexao,TarefasSql.contar(tipo,"","","","","",null,null));
   executar(conexao,TarefasSql.listar(tipo,"","","","","",null,null,1,0));
   executar(conexao,TarefasSql.valoresDistintos(tipo,"U_REQ.fullname"));
   executar(conexao,TarefasSql.valoresDistintos(tipo,"PM.title"));
   executar(conexao,TarefasSql.valoresDistintos(tipo,"TI.taskName"));
  }
  System.out.println("Validacao concluida ("+tipo+", somente leitura).");
 }
 static void executar(Connection conexao,TarefasSql.Consulta consulta)throws Exception{
  try(PreparedStatement statement=conexao.prepareStatement(consulta.getSql())){
   TarefasSql.aplicar(statement,consulta.getParametros());
   try(ResultSet rs=statement.executeQuery()){rs.next();}
  }
 }
}
JAVA
mkdir -p "$work/validate"
info "Validando a conexão e as consultas no $db_label (somente leitura)..."
"$jdk/bin/javac" -proc:none -encoding UTF-8 -cp "$work/build:$app/WEB-INF/lib/*" -d "$work/validate" "$work/ValidarBanco.java" || fail 'Não foi possível compilar o validador de banco.'
"$jdk/bin/java" -cp "$work/validate:$work/build:$app/WEB-INF/lib/*" ValidarBanco "$work/config" || fail "Validação de conexão/consultas falhou para $db_label; nenhum arquivo foi publicado."
info "Conexão e consultas validadas com sucesso no $db_label (nenhum dado foi alterado)."
yesno 'Confirma que a conta de banco é restrita a SELECT e que a configuração ficará privada?' || { info 'Instalação cancelada. Nada foi alterado.'; exit 0; }
yesno 'Autoriza parar o Fusion, publicar os arquivos e reiniciar o serviço agora?' || { info 'Instalação cancelada. Nada foi alterado.'; exit 0; }
# Parar antes de trocar arquivos; rollback automático em falha de publicação/start.
restore(){ local rc=$?; trap - ERR; set +e; printf '\n[ERRO] Falha na publicação (código %s). Restaurando o backup %s e reiniciando o serviço...\n' "$rc" "$backup" >&2; systemctl stop "$service"; for pair in "web:$dest" "classes:$pkg" "config:$config" "setenv:$setenv"; do name=${pair%%:*}; path=${pair#*:}; rm -rf -- "$path"; [[ ! -e $backup/$name ]] || cp -a -- "$backup/$name" "$path"; done; systemctl start "$service"; exit "$rc"; }
info "Parando o serviço $service..."
systemctl stop "$service"
trap restore ERR
info 'Publicando arquivos e configuração...'
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
info "Reiniciando o serviço $service..."
systemctl start "$service"; systemctl is-active --quiet "$service"
newpid=$(systemctl show -p MainPID --value "$service")
grep -zFxq -- "-Dfusion.config.path=$config" "/proc/$newpid/cmdline"
trap - ERR
printf '\n[OK] Publicação concluída (a verificação funcional da tela ainda é manual).\n  Backup para rollback: %s\n  Endpoint: %s/custom/task-notification\n  Tela: %s/custom/fusion-tarefas/tarefas-atrasadas.jsp\n' "$backup" "$url" "$url"
printf 'Próximos passos: valide os logs, o banco, o menu, a autorização GET/POST e só então faça um envio controlado. Não repita o POST automaticamente.\n'
