#!/usr/bin/env bash
# Reset the local database from migrations and run the pgTAP suite.
#
# pgTAP is installed here rather than in a migration on purpose: it is test
# scaffolding, and shipping ~1000 assertion functions to production to satisfy
# a local test runner is the wrong trade. `supabase db reset` drops it, so the
# install has to happen after the reset and before the tests.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The CLI ships PostHog telemetry that runs on shutdown. Where the endpoint is
# unreachable — behind an egress proxy, on an air-gapped runner — the flush
# times out and the CLI exits non-zero even though every test passed. Opting
# out is both the correct default for this repo and the fix for that false
# failure.
export DO_NOT_TRACK=1

if ! supabase status >/dev/null 2>&1; then
  echo "error: local Supabase stack is not running. Start it with:" >&2
  echo "  ./scripts/dev-up.sh" >&2
  exit 1
fi

DB_URL="$(supabase status -o env | sed -n 's/^DB_URL="\(.*\)"$/\1/p')"
if [[ -z "${DB_URL}" ]]; then
  echo "error: could not read DB_URL from 'supabase status'" >&2
  exit 1
fi

echo "==> Resetting database from migrations"
supabase db reset

echo "==> Installing pgTAP (test-only)"
psql "${DB_URL}" --quiet --no-psqlrc \
  -c "create extension if not exists pgtap with schema extensions;"

echo "==> Running pgTAP suite"
supabase test db
