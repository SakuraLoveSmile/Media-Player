#!/usr/bin/env bash
# Layer guard for lib/. Fails when an import points "upwards" or when the UI
# reaches past the data layer. Run locally and in CI (B1-2 / B1-4).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

status=0

# check <description> <regex> <dir>...
check() {
  local description="$1"
  local pattern="$2"
  shift 2

  local dirs=()
  local dir
  for dir in "$@"; do
    [[ -d "$dir" ]] && dirs+=("$dir")
  done
  [[ ${#dirs[@]} -eq 0 ]] && return 0

  local matches
  matches="$(grep -rnE "$pattern" "${dirs[@]}" --include='*.dart' || true)"
  if [[ -n "$matches" ]]; then
    echo "layering violation: $description" >&2
    echo "$matches" >&2
    status=1
  fi
}

# The UI talks to repositories, never to transport or player packages directly.
check "features import dio/media_kit" \
  "package:(dio|media_kit|media_kit_video)/" lib/features

# Data and core never depend on the UI.
check "core/data import features" \
  "package:media_player/features/" lib/core lib/data

# Features are wired together by app/router.dart, not by each other.
for feature_dir in lib/features/*/; do
  [[ -d "$feature_dir" ]] || continue
  self="$(basename "$feature_dir")"
  for other_dir in lib/features/*/; do
    [[ -d "$other_dir" ]] || continue
    other="$(basename "$other_dir")"
    [[ "$other" == "$self" ]] && continue
    check "feature '$self' imports feature '$other'" \
      "package:media_player/features/$other/|\.\./$other/" "$feature_dir"
  done
done

if [[ $status -eq 0 ]]; then
  echo "layering ok"
fi
exit $status
