#!/usr/bin/env bash
set -euo pipefail
set +x

CERT_FILE="${1:-}"
KEY_FILE="${2:-}"
TOKEN_FILE="${3:-}"
SEALING_CERT="${4:-/tmp/sealed-cert.pem}"
DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="jenkins-hook"
SECRET="hook-listener"
OUT="$DIR/sealedsecrets/hook-listener.yaml"
PARTIAL="$OUT.partial"

if [ "$#" -lt 3 ]; then
  echo "usage: seal-secrets.sh <certificate> <private key> <token file> [sealing cert]" >&2
  exit 2
fi

for INPUT_FILE in "$CERT_FILE" "$KEY_FILE" "$TOKEN_FILE"; do
  if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: $INPUT_FILE not found" >&2
    exit 1
  fi
done

if [ ! -f "$SEALING_CERT" ]; then
  echo "ERROR: sealing certificate $SEALING_CERT not found" >&2
  exit 1
fi

if [ "$(wc -l < "$TOKEN_FILE")" -ne 0 ]; then
  printf '%s\n' "ERROR: $TOKEN_FILE ends in a newline. Write it with tr -d '\n'" >&2
  exit 1
fi

install -d "$DIR/sealedsecrets"
trap 'rm -f "$PARTIAL"' EXIT

kubectl create secret generic "$SECRET" -n "$NAMESPACE" \
  --from-file=tls.crt="$CERT_FILE" \
  --from-file=tls.key="$KEY_FILE" \
  --from-file=trigger-token="$TOKEN_FILE" \
  --dry-run=client -o yaml \
  | kubeseal --cert "$SEALING_CERT" --format=yaml > "$PARTIAL"

grep -q -F "tls.crt:" "$PARTIAL"
grep -q -F "tls.key:" "$PARTIAL"
grep -q -F "trigger-token:" "$PARTIAL"
mv "$PARTIAL" "$OUT"
echo "sealed ok"
