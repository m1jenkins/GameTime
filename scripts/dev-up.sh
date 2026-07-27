#!/usr/bin/env bash
# Bring up the local Supabase stack.
#
# Realtime and analytics are disabled in config.toml (see the comments there).
# EXCLUDE_SERVICES lets a constrained host skip more; for example a sandbox
# that cannot raise RLIMIT_NOFILE has to skip edge-runtime:
#   EXCLUDE_SERVICES=edge-runtime ./scripts/dev-up.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# See scripts/db-test.sh for why. Keep these in step.
export DO_NOT_TRACK=1

if [[ -f .env.local ]]; then
  echo "==> Loading .env.local"
  set -a
  # shellcheck disable=SC1091
  source .env.local
  set +a
fi

args=()
if [[ -n "${EXCLUDE_SERVICES:-}" ]]; then
  args+=(-x "${EXCLUDE_SERVICES}")
fi

supabase start ${args[@]+"${args[@]}"}
