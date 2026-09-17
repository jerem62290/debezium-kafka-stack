#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
secret_dir="${project_dir}/.state/secrets"

if [[ ! -d "${secret_dir}" ]]; then
  printf 'Aucun secret généré : exécutez d’abord site.yml.\n' >&2
  exit 2
fi

printf 'Grafana   utilisateur=admin mot_de_passe=%s\n' "$(<"${secret_dir}/grafana_admin_password")"
printf 'AKHQ      utilisateur=admin mot_de_passe=%s\n' "$(<"${secret_dir}/akhq_admin_password")"
printf 'AKHQ      utilisateur=lecture mot_de_passe=%s\n' "$(<"${secret_dir}/akhq_reader_password")"

