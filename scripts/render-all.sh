#!/usr/bin/env bash
# Render every kustomization under the given roots into $OUT (default: out/).
set -euo pipefail

OUT="${OUT:-out}"
roots=("$@")
if [ "${#roots[@]}" -eq 0 ]; then
  roots=(deploy platform)
fi

rm -rf "$OUT"
mkdir -p "$OUT"

status=0
while IFS= read -r file; do
  dir="$(dirname "$file")"
  target="$OUT/${dir//\//__}.yaml"
  if kustomize build "$dir" > "$target"; then
    echo "rendered $dir"
  else
    echo "FAILED  $dir" >&2
    status=1
  fi
done < <(find "${roots[@]}" -name kustomization.yaml -not -path "*/base/*" 2>/dev/null | sort)

while IFS= read -r dir; do
  if [ -f "$dir/kustomization.yaml" ] || ! ls "$dir"/*.yaml >/dev/null 2>&1; then
    continue
  fi
  target="$OUT/${dir//\//__}.yaml"
  find "$dir" -maxdepth 1 -name '*.yaml' -not -name 'secret.example.yaml' | sort \
    | xargs awk 'FNR == 1 { print "---" } { print }' > "$target"
  echo "copied   $dir"
done < <(find "${roots[@]}" -type d 2>/dev/null | sort)

exit "$status"
