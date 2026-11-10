#!/usr/bin/env bash
set -euo pipefail

# change this: the GHCR prefix of the org's own images
OWN_PREFIX="ghcr.io/your-org/"
# change this: the AWS account id of the image registry
readonly ECR_REGISTRY_ID="${ECR_REGISTRY_ID:-123456789012}"
# change this: the AWS region of the image registry
readonly ECR_REGION="eu-west-1"
readonly ECR_HOST="${ECR_REGISTRY_ID}.dkr.ecr.${ECR_REGION}.amazonaws.com"
readonly ECR_SKIP="${ECR_SKIP:-false}"
readonly DEFAULT_TAG="latest"
readonly PLACEHOLDER_DIGEST="sha256:0000000000000000000000000000000000000000000000000000000000000000"
status=0

ecr_repository() {
  local name="${1#"${ECR_HOST}/"}"
  name="${name%%@*}"
  printf '%s\n' "${name%%:*}"
}

ecr_image_id() {
  local image="$1"
  if [[ "$image" == *@sha256:* ]]; then
    printf 'imageDigest=%s\n' "${image#*@}"
  elif [[ "${image#"${ECR_HOST}/"}" == *:* ]]; then
    printf 'imageTag=%s\n' "${image##*:}"
  else
    printf 'imageTag=%s\n' "$DEFAULT_TAG"
  fi
}

ecr_image_exists() {
  local image="$1"
  aws ecr describe-images --region "$ECR_REGION" --registry-id "$ECR_REGISTRY_ID" \
    --repository-name "$(ecr_repository "$image")" --image-ids "$(ecr_image_id "$image")" \
    --output text >/dev/null
}

list_images() {
  { grep -hoE '^\s+(- )?image: \S+' "$@" || true; } | awk '{print $NF}' | sort -u
}

images=$(list_images "$@")
if [ -n "${BASE_DIR:-}" ] && compgen -G "${BASE_DIR}/*.yaml" >/dev/null; then
  images=$(comm -23 <(printf '%s\n' "$images") <(list_images "${BASE_DIR}"/*.yaml))
  if [ -z "$images" ]; then
    echo "no new images compared with ${BASE_DIR}"
  fi
fi
for image in $images; do
  if [[ "$image" == *@"$PLACEHOLDER_DIGEST" ]]; then
    echo "placeholder  $image (CI writes the first real pin)"
  elif [[ "$image" == "${ECR_HOST}/"* ]]; then
    if [ "$ECR_SKIP" = "true" ]; then
      echo "skipped  $image (AWS_VERIFY_ROLE_ARN is empty, ECR is unchecked)"
    elif ! ecr_image_exists "$image"; then
      echo "MISSING  $image (aws ecr describe-images failed)" >&2
      status=1
    elif [[ "$image" == *@sha256:* ]]; then
      echo "ok       $image"
    else
      echo "tag-only $image (pin the digest)"
    fi
  elif [[ "$image" == *@sha256:* ]]; then
    if docker buildx imagetools inspect "$image" >/dev/null 2>&1; then
      echo "ok       $image"
    else
      echo "MISSING  $image" >&2
      status=1
    fi
  elif [[ "$image" == ${OWN_PREFIX}* ]]; then
    if docker buildx imagetools inspect "$image" >/dev/null 2>&1; then
      echo "tag-only $image (pin the digest)"
    else
      echo "MISSING  $image (tag not in registry)" >&2
      status=1
    fi
  else
    echo "skipped  $image (third-party tag, checked by its own pin)"
  fi
done

exit "$status"
