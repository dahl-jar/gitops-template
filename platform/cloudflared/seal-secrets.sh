#!/usr/bin/env bash
set -euo pipefail
set +x

CREDENTIALS_FILE="${1:-}"
SEALING_CERT="${2:-/tmp/sealed-cert.pem}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="cloudflared"
SECRET="cloudflared-creds"
OUT="$DIR/sealedsecret.yaml"
PARTIAL="$OUT.partial"

if [ "$#" -lt 1 ]; then
  echo "usage: seal-secrets.sh <credentials file> [sealing cert]" >&2
  exit 2
fi

if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "ERROR: $CREDENTIALS_FILE not found" >&2
  exit 1
fi

if [ ! -f "$SEALING_CERT" ]; then
  echo "ERROR: sealing certificate $SEALING_CERT not found" >&2
  exit 1
fi

trap 'rm -f "$PARTIAL"' EXIT

kubectl create secret generic "$SECRET" -n "$NAMESPACE" \
  --from-file=credentials.json="$CREDENTIALS_FILE" \
  --dry-run=client -o yaml \
  | kubeseal --cert "$SEALING_CERT" --format=yaml > "$PARTIAL"

grep -q -F "credentials.json:" "$PARTIAL"
mv "$PARTIAL" "$OUT"
echo "sealed ok"
