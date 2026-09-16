#!/usr/bin/env bash
# Encrypt the filled-in *.example.yaml files into committable SealedSecrets.
# Needs kubectl and kubeseal pointed at the cluster running the
# SealedSecrets controller.
set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KS=(kubeseal --controller-name=sealed-secrets-controller --controller-namespace=kube-system --format=yaml)

seal() {
  local example="$1" out="$2"
  if grep -q 'CHANGE_ME' "$example"; then
    echo "ERROR: fill the placeholders in $example first" >&2
    exit 1
  fi
  "${KS[@]}" < "$example" > "$out"
  echo "wrote $out"
}

seal "${SCRIPT_DIR}/secret.example.yaml"                 "${SCRIPT_DIR}/sealedsecret.yaml"
seal "${SCRIPT_DIR}/postgres/secret.example.yaml"       "${SCRIPT_DIR}/postgres/sealedsecret.yaml"
seal "${SCRIPT_DIR}/postgres/backup-secret.example.yaml" "${SCRIPT_DIR}/postgres/backup-sealedsecret.yaml"
seal "${SCRIPT_DIR}/meilisearch/secret.example.yaml"    "${SCRIPT_DIR}/meilisearch/sealedsecret.yaml"
