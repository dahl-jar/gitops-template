#!/usr/bin/env bash
set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOLDER="${1:-$SCRIPT_DIR}"
# change this: name and namespace of the Sealed Secrets controller
KS=(kubeseal --controller-name=sealed-secrets-controller --controller-namespace=kube-system --format=yaml)

seal() {
  local folder="$1"
  local secret="${folder}/secret.yaml"
  local sealed="${folder}/sealedsecret.yaml"
  if [ ! -f "$secret" ]; then
    echo "ERROR: ${secret} not found. Copy secret.example.yaml to secret.yaml and fill it in." >&2
    exit 1
  fi
  if grep -q 'CHANGE_ME' "$secret"; then
    echo "ERROR: ${secret} still has CHANGE_ME values." >&2
    exit 1
  fi
  local tmp
  tmp="$(mktemp "${sealed}.XXXXXX")"
  if ! "${KS[@]}" < "$secret" > "$tmp"; then
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$sealed"
  echo "Wrote ${sealed}"
}

while IFS= read -r example; do
  seal "$(dirname "$example")"
done < <(find "$FOLDER" -name secret.example.yaml | sort)
