#!/usr/bin/env bash
# Fusion Tarefas - gera o pacote de distribuição e o checksum SHA-256.
#
# Uso:
#   bash scripts/build-release.sh
#
# Saída:
#   dist/fusion-tarefas.tar.gz
#   dist/fusion-tarefas.tar.gz.sha256
#
# O pacote contém apenas o necessário para compilar e instalar:
#   fusion-tarefas/web/, fusion-tarefas/src/ e
#   fusion-tarefas/config/fusion-tarefas.properties.example
#
# A raiz interna "fusion-tarefas/" é compatível com install-fusion-tarefas-v2.sh,
# que localiza o projeto por src/br/com/fusion/tarefas + web/tarefas-atrasadas.jsp.
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail(){ printf 'ERRO: %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null || fail "Dependência ausente: $1"; }

need tar
need find
need sha256sum

NAME=fusion-tarefas
DIST="$ROOT/dist"
ARCHIVE="$DIST/$NAME.tar.gz"

for arquivo in web/tarefas-atrasadas.jsp web/css/style.css \
        web/script/script.js config/fusion-tarefas.properties.example; do
    [[ -f $arquivo ]] || fail "Arquivo necessário ausente: $arquivo"
done
[[ -d src/br/com/fusion/tarefas ]] || fail 'Diretório de fontes ausente: src/br/com/fusion/tarefas'

stage=$(mktemp -d "${TMPDIR:-/tmp}/build-release.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT

out="$stage/$NAME"
mkdir -p "$out"

# Copia somente os diretórios previstos na distribuição.
cp -a web "$out/web"
cp -a src "$out/src"
mkdir -p "$out/config"
cp -a config/fusion-tarefas.properties.example \
    "$out/config/fusion-tarefas.properties.example"

# Remove o que nunca deve ser distribuído, mesmo que exista nos diretórios copiados.
find "$out" -depth \( \
    -name '.*' \
    -o -path '*/backup/*' -o -path '*/backups/*' \
    -o -name '*.bak' -o -name '*.bak[0-9]' -o -name '*.orig' -o -name '*.rej' \
    -o -name '*.log' -o -name '*.class' -o -name '*.jar' \
    -o -name '*.war' -o -name '*.zip' -o -name '*.tar' \
    -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.env' \
    -o -name '*.properties' -o -name '*.swp' -o -name '*~' \
\) -exec rm -rf -- {} +

# Revalida o conteúdo essencial após a limpeza.
[[ -f $out/web/tarefas-atrasadas.jsp ]] || fail 'JSP removida indevidamente durante a limpeza.'
[[ -f $out/config/fusion-tarefas.properties.example ]] || fail 'Exemplo de configuração removido indevidamente.'
[[ -d $out/src/br/com/fusion/tarefas ]] || fail 'Fontes removidas indevidamente.'

# Falha se houver atribuição literal de segredo (valor entre aspas) nos arquivos
# empacotados. Leituras de configuração não são consideradas segredos.
if grep -rInE "(password|senha|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*['\"][^'\"]+['\"]" \
        "$out/web" "$out/src" 2>/dev/null >/dev/null; then
    fail 'Possível segredo literal encontrado nos arquivos do pacote; revise antes de publicar.'
fi

mkdir -p "$DIST"
rm -f -- "$ARCHIVE" "$ARCHIVE.sha256"

# Cria o TAR com raiz "fusion-tarefas/". Sem caminhos absolutos, links ou "..".
tar -czf "$ARCHIVE" -C "$stage" "$NAME"

# Checksum do pacote (formato compatível com sha256sum -c).
( cd "$DIST" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )

printf 'Pacote:   %s\n' "$ARCHIVE"
printf 'Checksum: %s\n' "$ARCHIVE.sha256"
printf 'Tamanho:  %s bytes\n' "$(wc -c < "$ARCHIVE" | tr -d ' ')"
printf 'Conteúdo:\n'
tar -tzf "$ARCHIVE" | sed 's/^/  /'
