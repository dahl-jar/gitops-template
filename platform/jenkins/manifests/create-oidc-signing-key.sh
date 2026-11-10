#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SEAL_SCRIPT="$ROOT/platform/jenkins/manifests/seal-secrets.sh"
JWKS_FILE="${JWKS_OUT:-$ROOT/infra/aws/account/oidc/jwks.json}"
SECRET=jenkins-oidc-signing-key
KEY_IDS=(aws-infra aws-config-read aws-image-signing aws-image-push aws-image-pull aws-deploy-request aws-deploy-pin aws-dependency-fetch)
KEY_BITS=2048

WORK="$(mktemp -d "${TMPDIR:-/tmp}/oidc-signing-key.XXXXXX")"
cleanup() {
  rm -f "$WORK/$SECRET/private-key" "$WORK/key.der" "$WORK/public.pem"
  rmdir "$WORK/$SECRET" "$WORK" 2>/dev/null || true
}
trap cleanup EXIT
mkdir "$WORK/$SECRET"

openssl genpkey -algorithm RSA -pkeyopt "rsa_keygen_bits:$KEY_BITS" -outform DER \
  | openssl pkcs8 -topk8 -nocrypt -inform DER -outform DER > "$WORK/key.der"
if [ "$(openssl asn1parse -inform DER -in "$WORK/key.der" | grep -c rsaEncryption)" -ne 1 ]; then
  echo "generated key is not PKCS#8 rsaEncryption" >&2
  exit 1
fi
base64 < "$WORK/key.der" | tr -d '\n' > "$WORK/$SECRET/private-key"
openssl pkey -inform DER -in "$WORK/key.der" -pubout -out "$WORK/public.pem"
MODULUS="$(openssl rsa -pubin -in "$WORK/public.pem" -noout -modulus | cut -d= -f2)"
EXPONENT="$(openssl rsa -pubin -in "$WORK/public.pem" -noout -text | sed -n 's/^Exponent: \([0-9]*\) .*/\1/p')"

"$SEAL_SCRIPT" "$WORK" "$SECRET"
python3 -I - "$MODULUS" "$EXPONENT" "${KEY_IDS[@]}" > "$JWKS_FILE" <<'PY'
import base64
import json
import sys


def encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


modulus, exponent, kids = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
keys = [
    {
        "kty": "RSA",
        "kid": kid,
        "use": "sig",
        "alg": "RS256",
        "n": encode(bytes.fromhex(modulus)),
        "e": encode(exponent.to_bytes((exponent.bit_length() + 7) // 8, "big")),
    }
    for kid in kids
]
print(json.dumps({"keys": keys}, indent=2))
PY
echo "wrote $JWKS_FILE"
