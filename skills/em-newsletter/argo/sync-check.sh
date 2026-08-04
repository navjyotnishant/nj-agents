#!/usr/bin/env bash
# Verify the two Argo skills carry identical reference files.
#
# Author: Navjyot Nishant
# Created: 2026-08-03
# Last updated: 2026-08-03
# Description: Argo uploads file bytes, so the shared references cannot be
#              symlinks and exist as real copies in both skills. This catches the
#              drift that duplication invites.
#
# Usage:  ./sync-check.sh          verify the copies match
#         ./sync-check.sh --fix    overwrite vertical-pulse's copies from em-newsletter
#
# em-newsletter/argo is the source of truth.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE"
DST="$HERE/../../vertical-pulse/argo"

REFS=(reference-taxonomy.md reference-trust.md reference-render.md reference-skeleton.md schema.md)

if [[ ! -d "$DST" ]]; then
  echo "BLOCK: $DST not found" >&2
  exit 2
fi

fix=0
[[ "${1:-}" == "--fix" ]] && fix=1

drift=0
for f in "${REFS[@]}"; do
  if [[ ! -f "$DST/$f" ]]; then
    if (( fix )); then
      cp "$SRC/$f" "$DST/$f"
      echo "restored  $f"
    else
      echo "MISSING   $f"
      drift=1
    fi
    continue
  fi

  if cmp -s "$SRC/$f" "$DST/$f"; then
    (( fix )) || echo "ok        $f"
  elif (( fix )); then
    cp "$SRC/$f" "$DST/$f"
    echo "synced    $f"
  else
    echo "DRIFT     $f"
    drift=1
  fi
done

if (( fix )); then
  echo "vertical-pulse/argo now matches em-newsletter/argo."
  exit 0
fi

if (( drift )); then
  echo
  echo "The two Argo skills disagree. Run './sync-check.sh --fix' to copy from" >&2
  echo "em-newsletter/argo, or reconcile by hand if the edit belongs upstream." >&2
  exit 1
fi

echo "In sync."
