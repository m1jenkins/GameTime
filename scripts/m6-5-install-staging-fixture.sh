#!/usr/bin/env bash
set -euo pipefail

# The SQL fixture deletes and recreates one reserved synthetic contest. Resolve
# the database host from a separately reviewed, checked-in staging project ref
# before letting psql make any change.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "${script_dir}/.." && pwd)"
project_ref_file="${repository_root}/supabase/staging-project-ref"

for required_name in STAGING_DATABASE_URL CONFORMANCE_USER_ID; do
  if [[ -z "${!required_name:-}" ]]; then
    echo "Missing required environment variable: ${required_name}" >&2
    exit 2
  fi
done

if [[ ! -f "$project_ref_file" ]]; then
  echo "Missing checked-in staging identity: ${project_ref_file}" >&2
  exit 2
fi
IFS= read -r recorded_ref <"$project_ref_file"
if [[ ! "$recorded_ref" =~ ^[a-z0-9]{20}$ ]]; then
  echo "The checked-in staging project ref is not configured; refusing to connect." >&2
  exit 2
fi

# Require Supabase's direct database URI. Its host carries the project ref, so
# this checks the actual connection target rather than trusting a caller's
# `environment=staging` label. Password characters that delimit a URI must be
# percent-encoded.
database_url_pattern="^postgres(ql)?://postgres:[^/@]+@db\\.${recorded_ref}\\.supabase\\.co:5432/postgres$"
if [[ ! "$STAGING_DATABASE_URL" =~ $database_url_pattern ]]; then
  echo "STAGING_DATABASE_URL does not target the recorded staging project." >&2
  exit 2
fi
if [[ ! "$CONFORMANCE_USER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "CONFORMANCE_USER_ID must be a UUID." >&2
  exit 2
fi

latitude="${CONFORMANCE_LATITUDE:-41.8781136}"
longitude="${CONFORMANCE_LONGITUDE:--87.6297982}"
coordinate_pattern='^-?[0-9]{1,3}([.][0-9]+)?$'
if [[ ! "$latitude" =~ $coordinate_pattern ]] || [[ ! "$longitude" =~ $coordinate_pattern ]]; then
  echo "Conformance latitude and longitude must be decimal numbers." >&2
  exit 2
fi
if ! command -v psql >/dev/null 2>&1; then
  echo "Required command is unavailable: psql" >&2
  exit 2
fi

psql "$STAGING_DATABASE_URL" \
  -v gametime_environment=staging \
  -v verified_staging_project_ref="$recorded_ref" \
  -v conformance_user_id="$CONFORMANCE_USER_ID" \
  -v latitude="$latitude" \
  -v longitude="$longitude" \
  -f "${script_dir}/m6-5-staging-fixture.sql"
