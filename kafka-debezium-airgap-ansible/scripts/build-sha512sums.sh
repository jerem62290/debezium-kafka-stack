#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../airgap-bundle" && pwd)}"
checksum_file="${bundle_dir}/checksums/SHA512SUMS"
temporary_file="${checksum_file}.tmp"

mkdir -p "${bundle_dir}/checksums"
(
  cd "${bundle_dir}"
  find artifacts -type f ! -name .gitkeep -print0 \
    | sort -z \
    | xargs -0 -r sha512sum
) > "${temporary_file}"

if [[ ! -s "${temporary_file}" ]]; then
  rm -f "${temporary_file}"
  printf 'Aucun artefact trouvé sous %s/artifacts\n' "${bundle_dir}" >&2
  exit 2
fi
mv "${temporary_file}" "${checksum_file}"
printf 'SHA-512 écrits dans %s\n' "${checksum_file}"

