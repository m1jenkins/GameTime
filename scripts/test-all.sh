#!/usr/bin/env bash
# Run every suite CI runs, in the same order. Keep this file and
# .github/workflows/ci.yml in step with each other.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

failed=()

run_suite() {
  local name="$1"
  shift
  echo
  echo "######## ${name} ########"
  if "$@"; then
    echo "-------- ${name}: PASS"
  else
    echo "-------- ${name}: FAIL"
    failed+=("${name}")
  fi
}

run_suite "database (pgTAP)" ./scripts/db-test.sh

run_suite "edge functions (Deno)" bash -c '
  cd supabase/functions
  deno fmt --check && deno lint && deno check . && deno test --allow-env
'

run_suite "client core (Swift Testing)" bash -c '
  cd ios/GameTimeCore
  swift build && swift test
'

echo
if (( ${#failed[@]} > 0 )); then
  printf 'FAILED: %s\n' "${failed[*]}"
  exit 1
fi
echo "All suites passed."
