#!/usr/bin/env bash
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

exit "$status"
