#!/usr/bin/env bash
# Seal the image-pull secret for a private GHCR image. Pass the PAT
# (read:packages) via GHCR_PAT so it never hits argv or shell history:
#   read -rs GHCR_PAT && export GHCR_PAT
#   GH_USER=your-org ./seal-ghcr-pull.sh
#   unset GHCR_PAT
set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KS=(kubeseal --controller-name=sealed-secrets-controller --controller-namespace=kube-system --format=yaml)

if [ -z "${GHCR_PAT:-}" ] || [ -z "${GH_USER:-}" ]; then
  echo "ERROR: set GH_USER and GHCR_PAT first" >&2
  exit 1
fi

kubectl create secret docker-registry ghcr-pull -n app \
  --docker-server=ghcr.io \
  --docker-username="$GH_USER" \
  --docker-password="$GHCR_PAT" \
  --dry-run=client -o yaml | "${KS[@]}" > "${SCRIPT_DIR}/ghcr-sealedsecret.yaml"

echo "wrote ghcr-sealedsecret.yaml"
