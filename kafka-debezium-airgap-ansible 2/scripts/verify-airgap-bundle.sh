#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../airgap-bundle" && pwd)}"
checksum_file="${bundle_dir}/checksums/SHA512SUMS"

required=(
  artifacts/kafka/kafka_2.13-3.9.2.tgz
  artifacts/debezium/debezium-connector-postgres-3.1.3.Final-plugin.tar.gz
  artifacts/debezium/debezium-connector-oracle-3.1.3.Final-plugin.tar.gz
  artifacts/debezium/ojdbc11-21.15.0.0.jar
  artifacts/debezium/xdb-21.15.0.0.jar
  artifacts/debezium/xmlparserv2-21.15.0.0.jar
  artifacts/monitoring/jmx_prometheus_javaagent-1.6.0.jar
  artifacts/monitoring/prometheus-3.13.2.linux-amd64.tar.gz
  artifacts/monitoring/alertmanager-0.34.0.linux-amd64.tar.gz
  artifacts/monitoring/node_exporter-1.12.1.linux-amd64.tar.gz
  artifacts/monitoring/kafka_exporter-1.9.0.linux-amd64.tar.gz
  artifacts/monitoring/blackbox_exporter-0.28.0.linux-amd64.tar.gz
  artifacts/monitoring/grafana_13.2.0_32077357341_linux_amd64.rpm
  artifacts/toolbox/akhq-0.28.0-all.jar
  artifacts/toolbox/OpenJDK25U-jre_x64_linux_hotspot_25.0.4.1_1.tar.gz
)

missing=0
for relative_path in "${required[@]}"; do
  if [[ ! -s "${bundle_dir}/${relative_path}" ]]; then
    printf 'MANQUANT: %s\n' "${bundle_dir}/${relative_path}" >&2
    missing=1
  fi
done
if (( missing != 0 )); then
  exit 2
fi

if [[ ! -s "${checksum_file}" ]]; then
  printf 'MANQUANT: %s (exécutez scripts/build-sha512sums.sh)\n' "${checksum_file}" >&2
  exit 3
fi

for relative_path in "${required[@]}"; do
  if ! awk -v expected="${relative_path}" '{name=$2; sub(/^\*/, "", name); if (name == expected) found=1} END {exit !found}' "${checksum_file}"; then
    printf 'ABSENT DU MANIFESTE SHA-512: %s\n' "${relative_path}" >&2
    exit 4
  fi
done

(cd "${bundle_dir}" && sha512sum --check --strict checksums/SHA512SUMS)
printf 'Bundle air-gap complet et intègre.\n'
