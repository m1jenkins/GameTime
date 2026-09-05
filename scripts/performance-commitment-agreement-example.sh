#!/usr/bin/env bash
# Loopback only; all fictional records and gate changes roll back.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# Optional port for a separate disposable stack; never accepts a remote host.
checkpoint_db_port="${1:-54322}"
if [[ $# -gt 1 || ! "${checkpoint_db_port}" =~ ^[1-9][0-9]{0,4}$ ]] || (( checkpoint_db_port > 65535 )); then
  echo "Expected one local PostgreSQL port (1–65535)" >&2
  exit 1
fi
psql "postgresql://postgres:postgres@127.0.0.1:${checkpoint_db_port}/postgres" \
  --no-psqlrc --set ON_ERROR_STOP=1 --file scripts/examples/performance-commitment-agreement.sql
