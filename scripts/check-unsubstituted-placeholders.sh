#!/bin/bash

set -euo pipefail

if (( $# > 0 )); then
  scan_paths=("$@")
else
  # These Flux Kustomizations do not enable postBuild substitution. Uppercase
  # deployment variables in their output would therefore reach Kubernetes
  # literally. Lowercase application templates such as Grafana's
  # ${datasource} variables are intentionally allowed.
  scan_paths=(
    infrastructure/monitoring/setup
    infrastructure/monitoring/kube-prometheus
  )
fi

matches="$({
  grep \
    --recursive \
    --line-number \
    --with-filename \
    --include='*.yaml' \
    --include='*.yml' \
    --extended-regexp \
    '\$\{[A-Z][A-Z0-9_]*([:][^}]*)?\}' \
    "${scan_paths[@]}" || true
})"

if [[ -n "${matches}" ]]; then
  echo 'Unresolved deployment placeholders found in manifests without Flux postBuild substitution:' >&2
  echo "${matches}" >&2
  exit 1
fi

echo 'No unresolved deployment placeholders found in unsubstituted manifests.'
