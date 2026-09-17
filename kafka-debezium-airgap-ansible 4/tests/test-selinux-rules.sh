#!/bin/bash
# Tests locaux sans privilège et sans modification de la politique SELinux.
set -euo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper=$project/roles/kafka/files/ensure-fcontexts.sh
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export MOCK_STATE=$test_dir/state MOCK_LOG=$test_dir/operations
mkdir -p "$test_dir/mock-bin" "$test_dir/install.v1/bin" "$test_dir/config" \
    "$test_dir/data" "$test_dir/metadata" "$test_dir/log"
touch "$MOCK_STATE" "$MOCK_LOG"
cat > "$test_dir/mock-bin/semanage" <<'BASH'
#!/bin/bash
set -euo pipefail
[[ ${MOCK_FAIL_LIST:-0} != 1 || $2 != -l ]] || exit 41
if [[ $* == 'fcontext -l' ]]; then
    printf 'SELinux fcontext type Context\n'
    while IFS=$'\t' read -r pattern kind; do
        printf '%s all files system_u:object_r:%s:s0\n' "$pattern" "$kind"
    done < "$MOCK_STATE"
    exit 0
fi
[[ $# == 7 && $1 == fcontext && ( $2 == -a || $2 == -m ) && $3 == -f && $4 == a && $5 == -t ]] || exit 42
[[ ${MOCK_FAIL_WRITE:-0} != 1 ]] || exit 43
pattern=$7
kind=$6
found=0
while IFS=$'\t' read -r old_pattern old_kind; do
    [[ $old_pattern != "$pattern" ]] || found=1
done < "$MOCK_STATE"
[[ ( $2 == -a && $found == 0 ) || ( $2 == -m && $found == 1 ) ]] || exit 44
while IFS=$'\t' read -r old_pattern old_kind; do
    if [[ $old_pattern != "$pattern" ]]; then printf '%s\t%s\n' "$old_pattern" "$old_kind"; fi
done < "$MOCK_STATE" > "$MOCK_STATE.next"
printf '%s\t%s\n' "$pattern" "$kind" >> "$MOCK_STATE.next"
mv "$MOCK_STATE.next" "$MOCK_STATE"
printf '%s\t%s\t%s\n' "$2" "$pattern" "$kind" >> "$MOCK_LOG"
BASH
cat > "$test_dir/mock-bin/matchpathcon" <<'BASH'
#!/bin/bash
set -euo pipefail
[[ ${MOCK_FAIL_MATCH:-0} != 1 ]] || exit 45
[[ $# == 2 && $1 == -n ]] || exit 46
pattern=${2//./\\.}
kind=default_t
[[ $2 != /tmp ]] || kind=tmp_t
while IFS=$'\t' read -r stored stored_kind; do
    [[ $stored != "$pattern" ]] || kind=$stored_kind
done < "$MOCK_STATE"
printf 'system_u:object_r:%s:s0\n' "$kind"
BASH
chmod +x "$test_dir/mock-bin/"*
export PATH=$test_dir/mock-bin:$PATH
args=( "$test_dir/install.v1" "$test_dir/config" "$test_dir/data" \
    "$test_dir/metadata" "$test_dir/log" usr_t bin_t etc_t var_lib_t var_log_t true )
fail() { printf 'ECHEC : %s\n' "$*" >&2; exit 1; }
assert_line() { grep -Fxq -- "$2" "$1" || fail "Ligne absente : $2"; }
reject() {
    if /bin/bash "$helper" "$@" > "$test_dir/rejected.out" 2> "$test_dir/rejected.err"; then
        fail 'Une entrée invalide ou une erreur de commande a été acceptée.'
    fi
    [[ ! -s $test_dir/rejected.out ]] || fail 'Annonce de succès après erreur.'
}

/bin/bash "$helper" "${args[@]}" > "$test_dir/first"
assert_line "$test_dir/first" CHANGED=1
assert_line "$test_dir/first" "ROOT=$test_dir/install.v1"
escaped=${test_dir//./\\.}
assert_line "$MOCK_STATE" "$escaped"$'\tusr_t'
assert_line "$MOCK_STATE" "$escaped/install\\.v1(/.*)?"$'\tusr_t'
[[ $(tail -n 1 "$MOCK_STATE") == "$escaped/install\\.v1/bin(/.*)?"$'\tbin_t' ]] || fail 'Priorité bin_t'
[[ $(wc -l < "$MOCK_STATE") == 7 ]] || fail 'Périmètre des règles trop large'
printf 'OK 1 : création ciblée, points échappés et priorité des exécutables\n'

cp "$MOCK_LOG" "$test_dir/log.before"
/bin/bash "$helper" "${args[@]}" > "$test_dir/second"
assert_line "$test_dir/second" CHANGED=0
cmp "$MOCK_LOG" "$test_dir/log.before"
printf 'OK 2 : second passage sans écriture semanage\n'

sed -i 's/var_lib_t/wrong_t/g' "$MOCK_STATE"
/bin/bash "$helper" "${args[@]}" > "$test_dir/repair"
assert_line "$test_dir/repair" CHANGED=1
! grep -q wrong_t "$MOCK_STATE" || fail 'Dérive non corrigée'
[[ $(tail -n 1 "$MOCK_STATE") == "$escaped/install\\.v1/bin(/.*)?"$'\tbin_t' ]] || fail 'Priorité après réparation'
printf 'OK 3 : réparation de dérive et ordre préservé\n'

: > "$MOCK_STATE"
args[10]=false
/bin/bash "$helper" "${args[@]}" > "$test_dir/no-parents"
[[ $(wc -l < "$MOCK_STATE") == 6 ]] || fail 'Option de gestion des parents ignorée'
printf 'OK 4 : correction des parents désactivable\n'

original=${args[0]}
for invalid in "$test_dir/../install" "$test_dir//install" "$test_dir/./install" "$test_dir/install/" "$test_dir/bad name"; do
    args[0]=$invalid
    reject "${args[@]}"
done
ln -s "$original" "$test_dir/link"
args[0]=$test_dir/link
reject "${args[@]}"
args[0]=$original
printf 'OK 5 : chemins non normalisés et liens refusés\n'

args[5]='invalid;type'
reject "${args[@]}"
args[5]=usr_t
args[10]=maybe
reject "${args[@]}"
args[10]=true
printf 'OK 6 : types et booléens contrôlés\n'

export MOCK_FAIL_LIST=1
reject "${args[@]}"
unset MOCK_FAIL_LIST
export MOCK_FAIL_MATCH=1
reject "${args[@]}"
unset MOCK_FAIL_MATCH
printf 'OK 7 : erreurs de lecture propagées\n'

: > "$MOCK_STATE"
export MOCK_FAIL_WRITE=1
reject "${args[@]}"
unset MOCK_FAIL_WRITE
printf 'OK 8 : erreur semanage sans annonce de succès\n'
