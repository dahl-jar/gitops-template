#!/usr/bin/env bash
# Mint the MinIO root pair and scoped app keys, then seal them.
set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KS=(kubeseal --controller-name=sealed-secrets-controller --controller-namespace=kube-system --format=yaml)

randsecret() { openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32; }

kubectl create secret generic app-minio -n app \
  --from-literal=MINIO_ROOT_USER="app-root" \
  --from-literal=MINIO_ROOT_PASSWORD="$(randsecret)" \
  --from-literal=MINIO_ACCESS_KEY="app" \
  --from-literal=MINIO_SECRET_KEY="$(randsecret)" \
  --dry-run=client -o yaml | "${KS[@]}" > "${SCRIPT_DIR}/minio/sealedsecret.yaml"

echo "wrote minio/sealedsecret.yaml"
