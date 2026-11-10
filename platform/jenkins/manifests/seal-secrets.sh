#!/usr/bin/env bash
set -euo pipefail

VALUES_DIR="${1:?usage: seal-secrets.sh <values-dir> [secret ...]}"
shift
CERT="${SEALED_CERT:-/tmp/sealed-cert.pem}"
OUT_DIR="${SEALED_OUT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sealedsecrets}"
NAMESPACE=jenkins
SECRETS="jenkins-admin jenkins-github-app jenkins-gitops-deploy jenkins-cloudflare-pages jenkins-chat-webhook jenkins-github-hook-token jenkins-oidc-signing-key jenkins-tls"

trap 'rm -f "${PARTIAL:-}"' EXIT

if [ ! -f "$CERT" ]; then
  echo "missing sealing certificate: $CERT" >&2
  exit 1
fi

value_file() {
  local path="$VALUES_DIR/$1/$2"
  if [ ! -f "$path" ]; then
    echo "missing value file: $path" >&2
    exit 1
  fi
  printf '%s\n' "$path"
}

write_sealed() {
  PARTIAL="$OUT_DIR/$1.yaml.partial"
  trap 'rm -f "$PARTIAL"' EXIT
  kubeseal --cert "$CERT" --format=yaml > "$PARTIAL"
  mv -f "$PARTIAL" "$OUT_DIR/$1.yaml"
  echo "sealed $1"
}

seal_generic() {
  local secret="$1" key path
  local line_keys=() file_keys=() args=()
  read -r -a line_keys <<< "$2"
  read -r -a file_keys <<< "$3"
  for key in ${line_keys[@]+"${line_keys[@]}"}; do
    path="$(value_file "$secret" "$key")"
    if [ "$(tail -c 1 "$path" | wc -l)" -ne 0 ]; then
      echo "value file ends in a newline: $path" >&2
      exit 1
    fi
    args+=("--from-file=$key=$path")
  done
  for key in ${file_keys[@]+"${file_keys[@]}"}; do
    path="$(value_file "$secret" "$key")"
    args+=("--from-file=$key=$path")
  done
  kubectl create secret generic "$secret" -n "$NAMESPACE" ${args[@]+"${args[@]}"} --dry-run=client -o yaml \
    | write_sealed "$secret"
}

seal_tls() {
  local cert_file key_file
  cert_file="$(value_file "$1" tls.crt)"
  key_file="$(value_file "$1" tls.key)"
  kubectl create secret tls "$1" -n "$NAMESPACE" --cert="$cert_file" --key="$key_file" --dry-run=client -o yaml \
    | write_sealed "$1"
}

seal_one() {
  case "$1" in
    jenkins-admin) seal_generic "$1" "jenkins-admin-user jenkins-admin-password" "" ;;
    jenkins-github-app) seal_generic "$1" "app-id" "private-key" ;;
    jenkins-gitops-deploy) seal_generic "$1" "" "private-key" ;;
    jenkins-cloudflare-pages) seal_generic "$1" "api-token account-id" "" ;;
    jenkins-chat-webhook) seal_generic "$1" "url" "" ;;
    jenkins-github-hook-token) seal_generic "$1" "token" "" ;;
    jenkins-oidc-signing-key) seal_generic "$1" "private-key" "" ;;
    jenkins-tls) seal_tls "$1" ;;
    *) echo "unknown secret: $1" >&2; exit 1 ;;
  esac
}

if [ "$#" -gt 0 ]; then
  for secret in "$@"; do
    if [ ! -d "$VALUES_DIR/$secret" ]; then
      echo "missing value folder: $VALUES_DIR/$secret" >&2
      exit 1
    fi
    seal_one "$secret"
  done
  exit 0
fi

skipped=0
for secret in $SECRETS; do
  if [ -d "$VALUES_DIR/$secret" ]; then
    seal_one "$secret"
  else
    echo "skipped $secret"
    skipped=$((skipped + 1))
  fi
done

if [ "$skipped" -gt 0 ]; then
  echo "skipped $skipped" >&2
  exit 1
fi
