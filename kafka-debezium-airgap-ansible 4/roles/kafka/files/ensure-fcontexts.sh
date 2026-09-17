#!/bin/bash
# Bash 4.4 (RHEL 8). Aucun code Python personnalisé, ni jq, ni collection Galaxy.
set -euo pipefail
export LC_ALL=C

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ $# == 11 ]] || fail 'Attendu : 5 chemins, 5 types SELinux, true|false.'
roots=( "$1" "$2" "$3" "$4" "$5" )
types=( "$6" "$8" "$9" "$9" "${10}" )
exec_type=$7
fix_parents=${11}
[[ $fix_parents == true || $fix_parents == false ]] || fail 'Booléen invalide.'
for kind in "${types[@]}" "$exec_type"; do
    [[ $kind =~ ^[A-Za-z0-9_]+_t$ ]] || fail "Type SELinux invalide : $kind"
done

declare -A ancestor_set=() current=()
patterns=() contexts=() parents=()
for path in "${roots[@]}"; do
    [[ $path =~ ^/[A-Za-z0-9_./-]+$ && $path != */ ]] || fail "Chemin invalide : $path"
    case "$path/" in
        *//*|*/./*|*/../*) fail "Chemin non normalisé : $path" ;;
    esac
    resolved=$(realpath -e -- "$path")
    [[ $resolved == "$path" ]] || fail "Lien symbolique interdit : $path"
    parent=${path%/*}
    while [[ -n $parent ]]; do
        ancestor_set["$parent"]=1
        parent=${parent%/*}
    done
done
if (( ${#ancestor_set[@]} )); then
    sorted_parents=$(printf '%s\n' "${!ancestor_set[@]}" | sort)
    mapfile -t parents <<< "$sorted_parents"
fi

add_rule() {
    # Seul le point est spécial dans les chemins autorisés ci-dessus.
    local pattern=${1//./\\.}
    patterns+=( "$pattern$3" )
    contexts+=( "$2" )
}
if [[ $fix_parents == true ]]; then
    for path in "${parents[@]}"; do
        expected=$(matchpathcon -n "$path")
        IFS=: read -r sel_user sel_role kind sel_range <<< "$expected"
        [[ -n $sel_user && -n $sel_role && -n $kind ]] || fail "Contexte introuvable : $path"
        case "$kind" in
            default_t|file_t|unlabeled_t) add_rule "$path" usr_t '' ;;
        esac
    done
fi
for i in "${!roots[@]}"; do
    add_rule "${roots[$i]}" "${types[$i]}" '(/.*)?'
done
# Les associations locales les plus récentes sont prioritaires : bin en dernier.
add_rule "${roots[0]}/bin" "$exec_type" '(/.*)?'

listing=$(semanage fcontext -l)
while read -r pattern file_word files_word context extra; do
    [[ $file_word == all && $files_word == files && $context == *:*:* ]] || continue
    IFS=: read -r sel_user sel_role kind sel_range <<< "$context"
    current["$pattern"]=$kind
done <<< "$listing"
changed=0
for i in "${!patterns[@]}"; do
    [[ ${current["${patterns[$i]}"]-} == "${contexts[$i]}" ]] || changed=1
done
if (( changed )); then
    # Rejouer dans l'ordre pour ne pas masquer bin_t par une règle plus large.
    for i in "${!patterns[@]}"; do
        pattern=${patterns[$i]}
        operation=-a
        [[ -v current["$pattern"] ]] && operation=-m
        semanage fcontext "$operation" -f a -t "${contexts[$i]}" "$pattern" >&2
        current["$pattern"]=${contexts[$i]}
    done
fi

# Protocole texte : les chemins validés ne contiennent ni espace ni saut de ligne.
printf 'CHANGED=%s\n' "$changed"
for path in "${parents[@]}"; do printf 'PARENT=%s\n' "$path"; done
for path in "${roots[@]}"; do printf 'ROOT=%s\n' "$path"; done
