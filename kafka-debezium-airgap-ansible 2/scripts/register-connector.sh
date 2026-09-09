#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  printf 'Usage: %s URL_CONNECT FICHIER_JSON\n' "$0" >&2
  exit 2
fi

connect_url="${1%/}"
connector_file="$2"
connector_name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "${connector_file}")"

if curl --fail --silent "${connect_url}/connectors/${connector_name}" >/dev/null; then
  python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["config"]))' "${connector_file}" \
    | curl --fail-with-body --silent --show-error \
        -X PUT -H 'Content-Type: application/json' --data-binary @- \
        "${connect_url}/connectors/${connector_name}/config"
else
  curl --fail-with-body --silent --show-error \
    -X POST -H 'Content-Type: application/json' --data-binary "@${connector_file}" \
    "${connect_url}/connectors"
fi
printf '\nConnecteur %s appliqué.\n' "${connector_name}"

