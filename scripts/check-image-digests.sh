#!/usr/bin/env bash
# Confirm every digest-pinned image in the rendered manifests exists in its registry.
# Usage: scripts/check-image-digests.sh out/*.yaml
set -euo pipefail

OWN_PREFIX="${OWN_PREFIX:-ghcr.io/your-org/}"
PLACEHOLDER_DIGEST="sha256:0000000000000000000000000000000000000000000000000000000000000000"
status=0

images=$(grep -hoE '^\s+(- )?image: \S+' "$@" | awk '{print $NF}' | sort -u)
for image in $images; do
  if [[ "$image" == *@"$PLACEHOLDER_DIGEST" ]]; then
    echo "placeholder $image (CI writes the first real pin)"
  elif [[ "$image" == *@sha256:* ]]; then
    if docker buildx imagetools inspect "$image" >/dev/null 2>&1; then
      echo "ok       $image"
    else
      echo "MISSING  $image" >&2
      status=1
    fi
  elif [[ "$image" == ${OWN_PREFIX}* ]]; then
    echo "tag-only $image (pin the digest)"
  else
    echo "skipped  $image (third-party tag)"
  fi
done

exit "$status"
