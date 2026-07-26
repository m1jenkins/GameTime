#!/usr/bin/env bash
set -euo pipefail

# Upload the security-sensitive M6.5 staging configuration without placing any
# secret in argv or in the repository. The caller supplies:
#
#   SUPABASE_PROJECT_REF
#   APPLE_TEAM_ID
#   APPLE_BUNDLE_ID
#   GAMETIME_ATTEST_CHALLENGE_SECRET  (32+ URL-safe characters)
#
# A debug-signed conformance target produces App Attest development
# attestations, so staging accepts that environment. The verification bypass is
# removed, not merely set false.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "${script_dir}/.." && pwd)"
project_ref_file="${repository_root}/supabase/staging-project-ref"

for required_name in \
  SUPABASE_PROJECT_REF \
  APPLE_TEAM_ID \
  APPLE_BUNDLE_ID \
  GAMETIME_ATTEST_CHALLENGE_SECRET
do
  if [[ -z "${!required_name:-}" ]]; then
    echo "Missing required environment variable: ${required_name}" >&2
    exit 2
  fi
done

if [[ ! "$SUPABASE_PROJECT_REF" =~ ^[a-z0-9]{20}$ ]]; then
  echo "SUPABASE_PROJECT_REF must be a 20-character project ref" >&2
  exit 2
fi
if [[ ! -f "$project_ref_file" ]]; then
  echo "Missing checked-in staging identity: ${project_ref_file}" >&2
  exit 2
fi
IFS= read -r recorded_ref <"$project_ref_file"
if [[ ! "$recorded_ref" =~ ^[a-z0-9]{20}$ ]]; then
  echo "The checked-in staging project ref is not configured; refusing to mutate any project." >&2
  exit 2
fi
if [[ "$SUPABASE_PROJECT_REF" != "$recorded_ref" ]]; then
  echo "SUPABASE_PROJECT_REF is not the checked-in staging project; refusing to mutate it." >&2
  exit 2
fi
if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "APPLE_TEAM_ID must be ten uppercase alphanumerics" >&2
  exit 2
fi
if [[ ! "$APPLE_BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || [[ "$APPLE_BUNDLE_ID" != *.* ]]; then
  echo "APPLE_BUNDLE_ID does not look like a bundle identifier" >&2
  exit 2
fi
if [[ ! "$GAMETIME_ATTEST_CHALLENGE_SECRET" =~ ^[A-Za-z0-9_-]{32,}$ ]]; then
  echo "GAMETIME_ATTEST_CHALLENGE_SECRET must be 32+ URL-safe characters" >&2
  exit 2
fi

for command_name in curl openssl supabase; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

staging_tmp="$(mktemp -d "${TMPDIR:-/tmp}/gametime-m65.XXXXXX")"
trap 'rm -rf -- "$staging_tmp"' EXIT

attestation_root_pem="${staging_tmp}/Apple_App_Attestation_Root_CA.pem"
receipt_root_der="${staging_tmp}/AppleRootCA-G3.cer"
receipt_root_pem="${staging_tmp}/AppleRootCA-G3.pem"
secret_file="${staging_tmp}/staging-secrets.env"
existing_secrets_file="${staging_tmp}/existing-secrets.json"
attestation_root_url="https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem"
receipt_root_url="https://www.apple.com/certificateauthority/AppleRootCA-G3.cer"
expected_attestation_fingerprint="1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32"
expected_receipt_fingerprint="63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79"

curl --fail --silent --show-error --location \
  "$attestation_root_url" --output "$attestation_root_pem"
actual_attestation_fingerprint="$(
  openssl x509 -in "$attestation_root_pem" -noout -fingerprint -sha256
)"
actual_attestation_fingerprint="${actual_attestation_fingerprint#*=}"
if [[ "$actual_attestation_fingerprint" != "$expected_attestation_fingerprint" ]]; then
  echo "Apple App Attestation root fingerprint changed; refusing to upload it" >&2
  echo "Expected: ${expected_attestation_fingerprint}" >&2
  echo "Received: ${actual_attestation_fingerprint}" >&2
  exit 1
fi

curl --fail --silent --show-error --location \
  "$receipt_root_url" --output "$receipt_root_der"
actual_receipt_fingerprint="$(
  openssl x509 -inform DER -in "$receipt_root_der" -noout -fingerprint -sha256
)"
actual_receipt_fingerprint="${actual_receipt_fingerprint#*=}"
if [[ "$actual_receipt_fingerprint" != "$expected_receipt_fingerprint" ]]; then
  echo "Apple receipt root fingerprint changed; refusing to upload it" >&2
  echo "Expected: ${expected_receipt_fingerprint}" >&2
  echo "Received: ${actual_receipt_fingerprint}" >&2
  exit 1
fi
openssl x509 -inform DER -in "$receipt_root_der" -out "$receipt_root_pem"

escaped_attestation_root="$(awk '{printf "%s\\n", $0}' "$attestation_root_pem")"
escaped_receipt_root="$(awk '{printf "%s\\n", $0}' "$receipt_root_pem")"
{
  printf 'GAMETIME_ENV=staging\n'
  printf 'APPLE_TEAM_ID=%s\n' "$APPLE_TEAM_ID"
  printf 'APPLE_BUNDLE_ID=%s\n' "$APPLE_BUNDLE_ID"
  printf 'GAMETIME_ATTEST_CHALLENGE_SECRET=%s\n' "$GAMETIME_ATTEST_CHALLENGE_SECRET"
  printf 'APP_ATTEST_ALLOW_DEVELOPMENT=true\n'
  printf 'APP_ATTEST_ROOT_CA_PEM="%s"\n' "$escaped_attestation_root"
  printf 'APP_ATTEST_RECEIPT_ROOT_CA_PEM="%s"\n' "$escaped_receipt_root"
} >"$secret_file"

supabase secrets list \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --output-format json \
  --agent no >"$existing_secrets_file"
if grep -Eq '"name"[[:space:]]*:[[:space:]]*"ATTEST_DEV_BYPASS"' "$existing_secrets_file"; then
  supabase secrets unset ATTEST_DEV_BYPASS \
    --project-ref "$SUPABASE_PROJECT_REF" \
    --yes \
    --agent no
fi
supabase secrets set \
  --env-file "$secret_file" \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --yes \
  --agent no

echo "M6.5 staging configuration uploaded; both public roots were fingerprint-verified and ATTEST_DEV_BYPASS is absent."
