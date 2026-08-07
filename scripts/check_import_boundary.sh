#!/usr/bin/env bash
# offline-first-target-architecture.md §8 Phase 1 / §11 step 2.
#
# Enforces §10's dependency-graph rule: only the Synchronization Engine (and
# the Lease Manager / Leader Election components that talk to the LAN
# transport) may import DioClient/ListAPI/Dio. Nothing under
# lib/features/**/presentation/** or lib/features/**/cubit/** should reach
# the network directly — reads/writes go through a LocalRepository backed by
# LocalDatabase instead (§1, §9).
#
# Deliberately a grep-based check, not a new static-analysis dependency —
# the design doc explicitly recommends this ("no need for a new tooling
# dependency"). Run from the repo root: scripts/check_import_boundary.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Exemptions: directories that still legitimately import Dio-adjacent types
# because Phase 2 (rewriting the six core Blocs onto LocalRepository/
# LocalDatabase streams) hasn't reached them yet. Remove each entry from
# this list in the same change that finishes that Bloc's Phase 2 rewrite —
# per §11 step 2, this check must go live immediately for every file NOT
# already violating it, so new violations are caught from day one.
EXEMPT_DIRS=(
  "lib/features/view/main/presentation/cubit/detail"
)

PATTERN='package:dio/dio\.dart|core/api/dio_client\.dart|core/api/list_api\.dart'

violations=""
while IFS= read -r -d '' file; do
  exempt=false
  for dir in "${EXEMPT_DIRS[@]}"; do
    case "$file" in
      "$dir"/*) exempt=true ;;
    esac
  done
  if [ "$exempt" = false ] && grep -Eq "$PATTERN" "$file"; then
    violations="$violations$file"$'\n'
  fi
done < <(find lib/features -type f -name '*.dart' \( -path '*/presentation/*' -o -path '*/cubit/*' \) -print0)

if [ -n "$violations" ]; then
  echo "Import-boundary violation: the following files under" >&2
  echo "lib/features/**/presentation/** or lib/features/**/cubit/** import" >&2
  echo "DioClient/ListAPI/Dio directly. Per offline-first-target-architecture.md" >&2
  echo "§1/§10, only the Synchronization Engine (and Lease Manager/Leader" >&2
  echo "Election) may touch the network — route this through a" >&2
  echo "LocalRepository instead, or add the file's directory to EXEMPT_DIRS" >&2
  echo "in scripts/check_import_boundary.sh ONLY if it's a not-yet-migrated" >&2
  echo "Phase 2 Bloc:" >&2
  echo "" >&2
  echo "$violations" >&2
  exit 1
fi

echo "check_import_boundary: OK"
