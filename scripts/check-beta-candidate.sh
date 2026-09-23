#!/usr/bin/env bash
# Read-only source preflight for the external iPhone beta candidate.
#
# This script never builds, signs, deploys, uploads, or changes project files.
# It checks source inputs that must be settled before those consequential steps.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/check-beta-candidate.sh [--root PATH] [--personal-copy-only] [--testflight]

--testflight checks the D142 friends TestFlight configuration instead of
Release: TestFlight.xcconfig and TestFlightAppInfo.plist, the P11B backend,
challenges and account mode on, and no payment provider.

Checks the GameTime Release source configuration for:
  - Release runtime configuration without a Personal App Attest dependency
  - Stripe sandbox-only settlement and a non-staging return scheme
  - A final non-staging bundle identifier
  - iPhone-only targeting and Watch isolation
  - App icon and privacy manifest inputs
  - App version and build number
  - A published privacy policy URL and a support contact
  - Secret-shaped literals in public client configuration
  - Removed Personal manual-sync copy and accessibility identifiers

The command exits 0 when every check passes, 1 when candidate blockers remain,
and 2 when the checker itself cannot inspect the requested project.
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
requested_root="${script_dir}/.."
personal_copy_only="0"
candidate="release"

while (( $# > 0 )); do
  case "$1" in
    --root)
      if (( $# < 2 )); then
        echo "error: --root requires a path" >&2
        exit 2
      fi
      requested_root="$2"
      shift 2
      ;;
    --personal-copy-only)
      personal_copy_only="1"
      shift
      ;;
    --testflight)
      candidate="testflight"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$requested_root" ]]; then
  echo "error: project root does not exist" >&2
  exit 2
fi

repo_root="$(cd "$requested_root" && pwd -P)"
# The selected candidate's configuration. Variable names keep "release" for
# the historical contract; --testflight points them at the D142 inputs.
if [[ "$candidate" == "testflight" ]]; then
  configuration_name="TestFlight"
  expected_environment="testflight"
  release_config="${repo_root}/ios/GameTime/Configuration/TestFlight.xcconfig"
  app_info="${repo_root}/ios/GameTime/Configuration/TestFlightAppInfo.plist"
else
  configuration_name="Release"
  expected_environment="release"
  release_config="${repo_root}/ios/GameTime/Configuration/Release.xcconfig"
  app_info="${repo_root}/ios/GameTime/Configuration/AppInfo.plist"
fi
public_config="${repo_root}/ios/GameTime/Configuration/PublicClient.xcconfig"
project_file="${repo_root}/ios/GameTime/GameTime.xcodeproj/project.pbxproj"
app_source="${repo_root}/ios/GameTime/GameTime"
asset_catalog="${app_source}/Assets.xcassets"
app_icon_set="${asset_catalog}/AppIcon.appiconset"
privacy_manifest="${app_source}/PrivacyInfo.xcprivacy"

for command_name in plutil python3 awk grep mktemp sips; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

pass_count=0
blocker_count=0

pass_check() {
  local check_id="$1"
  local message="$2"
  pass_count=$((pass_count + 1))
  printf 'PASS %s: %s\n' "$check_id" "$message"
}

block_check() {
  local check_id="$1"
  local message="$2"
  blocker_count=$((blocker_count + 1))
  printf 'BLOCKER %s: %s\n' "$check_id" "$message"
}

personal_copy_violations=""
if [[ -d "$app_source" ]]; then
  personal_copy_violations="$(
    grep -R -n -i -E \
      --include='*.swift' \
      'Sync my steps|Send saved steps|Not synced|Steps received|Step syncing|steps synced|Last synced|personal\.sync(\.pending)?|personal\.diagnostic\.run|personal\.eligibility-hold|steps[^\"]*not confirmed|not confirmed[^\"]*steps' \
      "$app_source" || true
  )"
else
  personal_copy_violations="missing product source directory"
fi

if [[ -z "$personal_copy_violations" ]]; then
  pass_check \
    "personal-automatic-copy" \
    "Personal shipping source contains no removed manual-sync copy or hooks."
else
  block_check \
    "personal-automatic-copy" \
    "Remove Personal manual-sync, confirmation, diagnostic, and hold copy/hooks."
fi

if [[ "$personal_copy_only" == "1" ]]; then
  printf '\nPersonal automatic-flow copy audit: %d passed, %d blocker(s).\n' \
    "$pass_count" \
    "$blocker_count"
  if (( blocker_count > 0 )); then
    exit 1
  fi
  exit 0
fi

xcconfig_value() {
  local file_path="$1"
  local setting_name="$2"

  awk -v setting="$setting_name" '
    /^[[:space:]]*\/\// { next }
    $0 ~ "^[[:space:]]*" setting "[[:space:]]*=" {
      value = $0
      sub("^[^=]*=[[:space:]]*", "", value)
      sub("[[:space:]]+//.*$", "", value)
      sub("[[:space:]]+$", "", value)
      result = value
    }
    END {
      if (result != "") {
        print result
      }
    }
  ' "$file_path"
}

release_environment=""
settlement_mode=""
stripe_return_url=""

if [[ -f "$release_config" ]]; then
  release_environment="$(xcconfig_value "$release_config" GAMETIME_ENV)"
  settlement_mode="$(
    xcconfig_value "$release_config" GAMETIME_PERSONAL_SETTLEMENT_MODE
  )"
  stripe_return_url="$(
    xcconfig_value "$release_config" GAMETIME_STRIPE_RETURN_URL
  )"
else
  block_check \
    "release-config" \
    "${configuration_name}.xcconfig is missing, so the candidate contract cannot be checked."
fi

if [[ "$release_environment" == "$expected_environment" ]]; then
  pass_check \
    "release-environment" \
    "${configuration_name} uses the ${expected_environment} runtime environment."
else
  block_check \
    "release-environment" \
    "${configuration_name} must declare GAMETIME_ENV as ${expected_environment}."
fi

pass_check \
  "personal-snapshot-auth" \
  "Personal snapshot v2 uses the signed-in account rather than App Attest."

if [[ "$candidate" == "testflight" ]]; then
  # D142: simulated stakes only. No payment provider, no redirect back from one.
  if [[ "$settlement_mode" == "test_only" ]] && [[ -z "$stripe_return_url" ]]; then
    pass_check \
      "no-payment-provider" \
      "TestFlight selects no payment provider and no payment redirect."
  else
    block_check \
      "no-payment-provider" \
      "TestFlight must use test_only settlement with an empty GAMETIME_STRIPE_RETURN_URL."
  fi

  if [[ "$(xcconfig_value "$release_config" GAMETIME_CHALLENGE_V1_ENABLED)" == "YES" ]] &&
    [[ "$(xcconfig_value "$release_config" GAMETIME_PRIVATE_HEALTH_ACCOUNT_MODE)" == "YES" ]]
  then
    pass_check \
      "challenge-account-mode" \
      "TestFlight turns on challenges and account-mode activity."
  else
    block_check \
      "challenge-account-mode" \
      "Set GAMETIME_CHALLENGE_V1_ENABLED and GAMETIME_PRIVATE_HEALTH_ACCOUNT_MODE to YES."
  fi

  testflight_url="$(xcconfig_value "$release_config" SUPABASE_URL)"
  if [[ "${testflight_url//\$\(\)/}" == "https://lyushhqoednheqwzsmxh.supabase.co" ]]; then
    pass_check \
      "testflight-backend" \
      "TestFlight selects the P11B backend that account mode is limited to."
  else
    block_check \
      "testflight-backend" \
      "TestFlight must override SUPABASE_URL with the P11B project."
  fi

  health_usage=""
  account_mode_key="0"
  if [[ -f "$app_info" ]] && plutil -lint "$app_info" >/dev/null 2>&1; then
    health_usage="$(plutil -extract NSHealthShareUsageDescription raw -o - "$app_info" 2>/dev/null || true)"
    if plutil -extract GAMETIME_PRIVATE_HEALTH_ACCOUNT_MODE raw -o - "$app_info" >/dev/null 2>&1; then
      account_mode_key="1"
    fi
  else
    block_check \
      "app-info" \
      "TestFlightAppInfo.plist is missing or is not a valid property list."
  fi
  if [[ "$health_usage" == *"Apple Watch"* ]] && [[ "$health_usage" != *"step counts"* ]] &&
    [[ "$account_mode_key" == "1" ]]
  then
    pass_check \
      "testflight-app-info" \
      "TestFlightAppInfo.plist carries account mode and describes the Apple Watch activity it reads."
  else
    block_check \
      "testflight-app-info" \
      "TestFlightAppInfo.plist needs the account-mode key and a Health description naming Apple Watch activity."
  fi
else
if [[ "$settlement_mode" == "stripe_sandbox" ]]; then
  pass_check \
    "settlement-mode" \
    "Release exposes only the Stripe sandbox settlement path."
else
  block_check \
    "settlement-mode" \
    "Release must use stripe_sandbox; live settlement is not beta-approved."
fi

stripe_return_scheme=""
if [[ "$stripe_return_url" == *:* ]]; then
  stripe_return_scheme="${stripe_return_url%%:*}"
fi

normalized_stripe_return_url="${stripe_return_url//\$\(\)/}"
if
  [[ "$stripe_return_scheme" =~ ^gametime([.-][a-z0-9]+)*$ ]] &&
    [[ "$stripe_return_scheme" != *"staging"* ]] &&
    [[ "$stripe_return_scheme" != *"debug"* ]] &&
    [[ "$stripe_return_scheme" != *"test"* ]] &&
    [[ "$stripe_return_scheme" != *"example"* ]] &&
    [[ "$normalized_stripe_return_url" == "${stripe_return_scheme}://stripe-redirect" ]]
then
  pass_check \
    "stripe-return-scheme" \
    "Release declares a non-development GameTime Stripe redirect contract."
else
  block_check \
    "stripe-return-scheme" \
    "Replace the staging redirect with the reviewed GameTime beta scheme and host."
fi

app_url_scheme_matches="0"
if [[ -f "$app_info" ]]; then
  if ! plutil -lint "$app_info" >/dev/null 2>&1; then
    block_check \
      "app-info" \
      "AppInfo.plist is not a valid property list."
  else
    if ! app_url_scheme_matches="$(
      python3 - "$app_info" "$stripe_return_scheme" <<'PY'
import plistlib
import sys

plist_path, expected_scheme = sys.argv[1:3]

try:
    with open(plist_path, "rb") as plist_file:
        plist = plistlib.load(plist_file)
except (OSError, plistlib.InvalidFileException):
    print("0")
    raise SystemExit(0)

schemes = []
for url_type in plist.get("CFBundleURLTypes", []):
    schemes.extend(url_type.get("CFBundleURLSchemes", []))

print("1" if expected_scheme and expected_scheme in schemes else "0")
PY
    )"; then
      app_url_scheme_matches="0"
    fi
  fi
else
  block_check \
    "app-info" \
    "AppInfo.plist is missing."
fi

if [[ "$app_url_scheme_matches" == "1" ]] &&
  [[ "$stripe_return_scheme" != *"staging"* ]]
then
  pass_check \
    "app-url-scheme" \
    "The declared Stripe scheme is registered in AppInfo.plist."
else
  block_check \
    "app-url-scheme" \
    "The app URL scheme must match the final non-staging Stripe return scheme."
fi

fi

temporary_dir="$(
  mktemp -d "${TMPDIR:-/tmp}/gametime-beta-preflight.XXXXXX"
)"
cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT

bundle_identifier=""
targeted_device_family=""
app_icon_name=""
marketing_version=""
build_number=""

if [[ ! -f "$project_file" ]]; then
  block_check \
    "xcode-project" \
    "The GameTime Xcode project file is missing."
else
  project_json="${temporary_dir}/project.json"
  if ! plutil -convert json -o "$project_json" "$project_file" 2>/dev/null; then
    block_check \
      "xcode-project" \
      "The GameTime Xcode project could not be parsed."
  else
    project_snapshot=""
    if ! project_snapshot="$(
      python3 - "$project_json" "$configuration_name" <<'PY'
import json
import sys

project_path, configuration_name = sys.argv[1:3]

with open(project_path, "r", encoding="utf-8") as project_file:
    project = json.load(project_file)

objects = project.get("objects", {})
target = next(
    (
        value
        for value in objects.values()
        if value.get("isa") == "PBXNativeTarget"
        and value.get("name") == "GameTime"
    ),
    None,
)

if target is None:
    raise SystemExit("GameTime target missing")

configuration_list = objects.get(target.get("buildConfigurationList"), {})
release_configuration = None
for configuration_id in configuration_list.get("buildConfigurations", []):
    candidate = objects.get(configuration_id, {})
    if candidate.get("name") == configuration_name:
        release_configuration = candidate
        break

if release_configuration is None:
    raise SystemExit(configuration_name + " configuration missing")

settings = release_configuration.get("buildSettings", {})

def safe_value(value):
    return str(value or "").replace("\n", " ").replace("\t", " ")


values = {
    "bundle_identifier": settings.get("PRODUCT_BUNDLE_IDENTIFIER", ""),
    "targeted_device_family": settings.get("TARGETED_DEVICE_FAMILY", ""),
    "app_icon_name": settings.get(
        "ASSETCATALOG_COMPILER_APPICON_NAME",
        "",
    ),
    "marketing_version": settings.get("MARKETING_VERSION", ""),
    "build_number": settings.get("CURRENT_PROJECT_VERSION", ""),
}

for key, value in values.items():
    print(f"{key}\t{safe_value(value)}")
PY
    )"; then
      echo \
        "error: the GameTime target or ${configuration_name} build settings could not be read" \
        >&2
      exit 2
    fi

    while IFS=$'\t' read -r key value; do
      case "$key" in
        bundle_identifier) bundle_identifier="$value" ;;
        targeted_device_family) targeted_device_family="$value" ;;
        app_icon_name) app_icon_name="$value" ;;
        marketing_version) marketing_version="$value" ;;
        build_number) build_number="$value" ;;
      esac
    done <<<"$project_snapshot"
  fi
fi

normalized_bundle_identifier="$bundle_identifier"
normalized_bundle_identifier="${normalized_bundle_identifier//\"/}"
lowercase_bundle_identifier="$(
  printf '%s' "$normalized_bundle_identifier" |
    tr '[:upper:]' '[:lower:]'
)"

if
  [[ "$normalized_bundle_identifier" =~ ^[A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$ ]] &&
    [[ "$lowercase_bundle_identifier" != *".staging"* ]] &&
    [[ "$lowercase_bundle_identifier" != *".debug"* ]] &&
    [[ "$lowercase_bundle_identifier" != *".test"* ]] &&
    [[ "$lowercase_bundle_identifier" != *".example"* ]] &&
    [[ "$lowercase_bundle_identifier" != *"conformance"* ]] &&
    [[ "$normalized_bundle_identifier" != *'$('* ]]
then
  pass_check \
    "release-bundle-id" \
    "${configuration_name} declares a resolved non-development app identity."
else
  block_check \
    "release-bundle-id" \
    "Replace the development identity with the reviewed distribution bundle ID."
fi

normalized_device_family="${targeted_device_family//\"/}"
normalized_device_family="${normalized_device_family// /}"
if [[ "$normalized_device_family" == "1" ]]; then
  pass_check \
    "iphone-only" \
    "${configuration_name} targets iPhone only."
else
  block_check \
    "iphone-only" \
    "${configuration_name} must target device family 1 only; iPad is deferred."
fi

if [[ "$app_icon_name" == "AppIcon" ]]; then
  pass_check \
    "app-icon-setting" \
    "${configuration_name} selects the AppIcon asset set."
else
  block_check \
    "app-icon-setting" \
    "Set the ${configuration_name} app icon asset name to AppIcon."
fi

icon_catalog_ready="0"
icon_source_path=""
asset_contents="${asset_catalog}/Contents.json"
icon_contents="${app_icon_set}/Contents.json"
if [[ -f "$asset_contents" ]] && [[ -f "$icon_contents" ]]; then
  if ! icon_source_path="$(
    python3 - "$asset_contents" "$icon_contents" "$app_icon_set" <<'PY'
import json
import os
import sys

asset_contents_path, icon_contents_path, icon_directory = sys.argv[1:4]

try:
    with open(
        asset_contents_path,
        "r",
        encoding="utf-8",
    ) as asset_contents_file:
        json.load(asset_contents_file)
    with open(
        icon_contents_path,
        "r",
        encoding="utf-8",
    ) as icon_contents_file:
        contents = json.load(icon_contents_file)
except (OSError, ValueError):
    raise SystemExit(0)

for image in contents.get("images", []):
    filename = image.get("filename")
    if not filename:
        continue
    if image.get("size") != "1024x1024":
        continue
    candidate_path = os.path.join(icon_directory, filename)
    if os.path.isfile(candidate_path):
        print(candidate_path)
        break
PY
  )"; then
    icon_source_path=""
  fi
fi

if [[ -n "$icon_source_path" ]]; then
  icon_properties="$(
    sips \
      -g pixelWidth \
      -g pixelHeight \
      -g hasAlpha \
      "$icon_source_path" \
      2>/dev/null || true
  )"
  if
    [[ "$icon_properties" == *"pixelWidth: 1024"* ]] &&
      [[ "$icon_properties" == *"pixelHeight: 1024"* ]] &&
      [[ "$icon_properties" == *"hasAlpha: no"* ]]
  then
    icon_catalog_ready="1"
  fi
fi

if [[ "$icon_catalog_ready" == "1" ]]; then
  pass_check \
    "app-icon-catalog" \
    "The main app catalog has a decodable opaque 1024 px icon."
else
  block_check \
    "app-icon-catalog" \
    "Add the main iPhone AppIcon catalog and its 1024 px source image."
fi

if [[ -f "$privacy_manifest" ]] &&
  plutil -lint "$privacy_manifest" >/dev/null 2>&1
then
  pass_check \
    "privacy-manifest" \
    "The main app has a parseable privacy manifest input."
else
  block_check \
    "privacy-manifest" \
    "Add and validate the main app PrivacyInfo.xcprivacy file."
fi

if
  [[ -n "$marketing_version" ]] &&
    [[ "$marketing_version" != *'$('* ]] &&
    [[ "$marketing_version" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]
then
  pass_check \
    "marketing-version" \
    "${configuration_name} has a resolved marketing version."
else
  block_check \
    "marketing-version" \
    "Set a resolved numeric marketing version for the candidate."
fi

if
  [[ -n "$build_number" ]] &&
    [[ "$build_number" != *'$('* ]] &&
    [[ "$build_number" =~ ^[1-9][0-9]*$ ]]
then
  pass_check \
    "build-number" \
    "${configuration_name} has a positive resolved build number."
else
  block_check \
    "build-number" \
    "Set a positive resolved build number; verify uniqueness at candidate freeze."
fi

# D135 applies to every configuration and shared scheme, including standalone
# targets. Historical source must be outside target membership, not hidden by
# Release-only preprocessor flags or EXCLUDED_SOURCE_FILE_NAMES.
if python3 "${script_dir}/check-iphone-product.py" --root "$repo_root" >/dev/null; then
  pass_check \
    "watch-isolation" \
    "All active iPhone targets and schemes exclude the dedicated Watch runtime."
else
  block_check \
    "watch-isolation" \
    "Remove Watch targets, launch entries and connectivity from active product inputs."
fi

supabase_url=""
supabase_publishable_key=""
if [[ -f "$public_config" ]]; then
  supabase_url="$(xcconfig_value "$public_config" SUPABASE_URL)"
  supabase_publishable_key="$(
    xcconfig_value "$public_config" SUPABASE_PUBLISHABLE_KEY
  )"
fi
if [[ -f "$release_config" ]]; then
  override_url="$(xcconfig_value "$release_config" SUPABASE_URL)"
  override_key="$(xcconfig_value "$release_config" SUPABASE_PUBLISHABLE_KEY)"
  [[ -n "$override_url" ]] && supabase_url="$override_url"
  [[ -n "$override_key" ]] && supabase_publishable_key="$override_key"
fi
normalized_supabase_url="${supabase_url//\$\(\)/}"

if
  [[ "$normalized_supabase_url" =~ ^https://[A-Za-z0-9-]+[.]supabase[.]co/?$ ]] &&
    [[ "$supabase_publishable_key" =~ ^sb_publishable_[A-Za-z0-9._-]{12,}$ ]]
then
  pass_check \
    "public-client-config" \
    "${configuration_name} has a Supabase HTTPS URL and public publishable key."
else
  block_check \
    "public-client-config" \
    "Configure the reviewed beta Supabase URL and a public publishable key."
fi

privacy_policy_url=""
beta_terms_url=""
support_email=""
if [[ -f "$public_config" ]]; then
  privacy_policy_url="$(
    xcconfig_value "$public_config" GAMETIME_PRIVACY_POLICY_URL
  )"
  beta_terms_url="$(
    xcconfig_value "$public_config" GAMETIME_BETA_TERMS_URL
  )"
  support_email="$(xcconfig_value "$public_config" GAMETIME_SUPPORT_EMAIL)"
fi
normalized_privacy_policy_url="${privacy_policy_url//\$\(\)/}"
normalized_beta_terms_url="${beta_terms_url//\$\(\)/}"

# Apple will not let a build reach external testers without a reachable policy
# URL, and rejects an app whose support contact goes nowhere. Neither value can
# be derived from this repository, so both stay blockers until a person sets
# them. The app itself treats them as absent and still runs.
if [[ "$normalized_privacy_policy_url" =~ ^https://[A-Za-z0-9.-]+[.][A-Za-z]{2,}(/[^[:space:]]*)?$ ]]; then
  pass_check \
    "privacy-policy-url" \
    "${configuration_name} points at a published HTTPS privacy policy."
else
  block_check \
    "privacy-policy-url" \
    "Publish the privacy policy (docs/PRIVACY_POLICY.md) and set GAMETIME_PRIVACY_POLICY_URL."
fi

if [[ "$normalized_beta_terms_url" =~ ^https://[A-Za-z0-9.-]+[.][A-Za-z]{2,}(/[^[:space:]]*)?$ ]]; then
  pass_check \
    "beta-terms-url" \
    "${configuration_name} points at published HTTPS beta terms."
else
  block_check \
    "beta-terms-url" \
    "Publish the beta terms and set GAMETIME_BETA_TERMS_URL."
fi

if [[ "$support_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$ ]]; then
  pass_check \
    "support-contact" \
    "${configuration_name} has a support address a tester can write to."
else
  block_check \
    "support-contact" \
    "Open a monitored support inbox and set GAMETIME_SUPPORT_EMAIL."
fi

public_client_include_count="0"
if [[ -f "$release_config" ]]; then
  public_client_include_count="$(
    awk '
      /^[[:space:]]*#include\??[[:space:]]+["<]PublicClient[.]xcconfig[">][[:space:]]*$/ {
        count += 1
      }
      END { print count + 0 }
    ' "$release_config"
  )"
fi

if [[ "$public_client_include_count" == "1" ]]; then
  pass_check \
    "public-client-binding" \
    "${configuration_name} includes the public client configuration exactly once."
else
  block_check \
    "public-client-binding" \
    "${configuration_name} must include PublicClient.xcconfig exactly once."
fi

secret_shaped_literal="0"
secret_pattern='-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|(=[[:space:]]*["'\'']?|<string>[[:space:]]*)(sk|rk)_(live|test)_[A-Za-z0-9_]{12,}|(=[[:space:]]*["'\'']?|<string>[[:space:]]*)sb_secret_[A-Za-z0-9._-]{12,}|(=[[:space:]]*["'\'']?|<string>[[:space:]]*)service_role([[:space:]"'\'']|</string>|$)|eyJ[A-Za-z0-9_-]{20,}[.][A-Za-z0-9_-]{20,}[.][A-Za-z0-9_-]{10,}'

for client_file in \
  "$release_config" \
  "$public_config" \
  "$app_info" \
  "$project_file"
do
  if [[ -f "$client_file" ]] &&
    LC_ALL=C grep -Eq -- "$secret_pattern" "$client_file"
  then
    secret_shaped_literal="1"
    break
  fi
done

if [[ -f "$release_config" ]] &&
  ! awk '
    /^[[:space:]]*#include/ {
      if ($0 !~ /^[[:space:]]*#include\??[[:space:]]+["<]PublicClient[.]xcconfig[">][[:space:]]*$/) {
        invalid = 1
      }
    }
    END { exit invalid }
  ' "$release_config"
then
  secret_shaped_literal="1"
fi

if [[ -f "$public_config" ]] &&
  LC_ALL=C grep -Eq '^[[:space:]]*#include' "$public_config"
then
  secret_shaped_literal="1"
fi

if [[ "$secret_shaped_literal" == "0" ]]; then
  pass_check \
    "public-client-secrets" \
    "No secret-shaped literal was found in public ${configuration_name} inputs."
else
  block_check \
    "public-client-secrets" \
    "Remove secret-shaped values or private includes from public ${configuration_name} inputs."
fi

printf '\nBeta candidate source preflight: %d passed, %d blocker(s).\n' \
  "$pass_count" \
  "$blocker_count"
echo \
  "Evidence boundary: this does not prove account identity, hosted runtime, signing, archive contents, Apple Health behavior, snapshot authorization, device behavior, or TestFlight."

if (( blocker_count > 0 )); then
  exit 1
fi
