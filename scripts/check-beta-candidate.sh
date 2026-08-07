#!/usr/bin/env bash
# Read-only source preflight for the external iPhone beta candidate.
#
# This script never builds, signs, deploys, uploads, or changes project files.
# It checks source inputs that must be settled before those consequential steps.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/check-beta-candidate.sh [--root PATH]

Checks the GameTime Release source configuration for:
  - Release and production App Attest environments
  - Stripe sandbox-only settlement and a non-staging return scheme
  - A final non-staging bundle identifier
  - iPhone-only targeting and Watch isolation
  - App icon and privacy manifest inputs
  - App version and build number
  - Secret-shaped literals in public client configuration

The command exits 0 when every check passes, 1 when candidate blockers remain,
and 2 when the checker itself cannot inspect the requested project.
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
requested_root="${script_dir}/.."

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
release_config="${repo_root}/ios/GameTime/Configuration/Release.xcconfig"
public_config="${repo_root}/ios/GameTime/Configuration/PublicClient.xcconfig"
app_info="${repo_root}/ios/GameTime/Configuration/AppInfo.plist"
project_file="${repo_root}/ios/GameTime/GameTime.xcodeproj/project.pbxproj"
app_source="${repo_root}/ios/GameTime/GameTime"
asset_catalog="${app_source}/Assets.xcassets"
app_icon_set="${asset_catalog}/AppIcon.appiconset"
privacy_manifest="${app_source}/PrivacyInfo.xcprivacy"

for command_name in plutil python3 awk grep find mktemp sips; do
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
attest_environment=""
settlement_mode=""
stripe_return_url=""

if [[ -f "$release_config" ]]; then
  release_environment="$(xcconfig_value "$release_config" GAMETIME_ENV)"
  attest_environment="$(
    xcconfig_value "$release_config" APP_ATTEST_ENVIRONMENT
  )"
  settlement_mode="$(
    xcconfig_value "$release_config" GAMETIME_PERSONAL_SETTLEMENT_MODE
  )"
  stripe_return_url="$(
    xcconfig_value "$release_config" GAMETIME_STRIPE_RETURN_URL
  )"
else
  block_check \
    "release-config" \
    "Release.xcconfig is missing, so the candidate contract cannot be checked."
fi

if [[ "$release_environment" == "release" ]]; then
  pass_check \
    "release-environment" \
    "Release uses the distribution runtime environment."
else
  block_check \
    "release-environment" \
    "Release must declare GAMETIME_ENV as release."
fi

if [[ "$attest_environment" == "production" ]]; then
  pass_check \
    "app-attest-environment" \
    "Release.xcconfig declares production App Attest."
else
  block_check \
    "app-attest-environment" \
    "Release must require production App Attest for TestFlight."
fi

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
excluded_sources=""
watch_project_integration="1"

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
      python3 - "$project_json" <<'PY'
import json
import sys

project_path = sys.argv[1]

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
    if candidate.get("name") == "Release":
        release_configuration = candidate
        break

if release_configuration is None:
    raise SystemExit("Release configuration missing")

settings = release_configuration.get("buildSettings", {})


def safe_value(value):
    return str(value or "").replace("\n", " ").replace("\t", " ")


def object_label(value):
    return " ".join(
        safe_value(value.get(key))
        for key in ("name", "path", "productName")
    ).lower()


watch_integration = False

for dependency_id in target.get("dependencies", []):
    dependency = objects.get(dependency_id, {})
    dependency_target = objects.get(dependency.get("target"), {})
    if "watch" in object_label(dependency_target):
        watch_integration = True

for phase_id in target.get("buildPhases", []):
    phase = objects.get(phase_id, {})
    if phase.get("isa") != "PBXCopyFilesBuildPhase":
        continue
    if "watch" in object_label(phase):
        watch_integration = True
    for build_file_id in phase.get("files", []):
        build_file = objects.get(build_file_id, {})
        reference_id = build_file.get("fileRef") or build_file.get("productRef")
        reference = objects.get(reference_id, {})
        if "watch" in object_label(reference):
            watch_integration = True

values = {
    "bundle_identifier": settings.get("PRODUCT_BUNDLE_IDENTIFIER", ""),
    "targeted_device_family": settings.get("TARGETED_DEVICE_FAMILY", ""),
    "app_icon_name": settings.get(
        "ASSETCATALOG_COMPILER_APPICON_NAME",
        "",
    ),
    "marketing_version": settings.get("MARKETING_VERSION", ""),
    "build_number": settings.get("CURRENT_PROJECT_VERSION", ""),
    "excluded_sources": settings.get("EXCLUDED_SOURCE_FILE_NAMES", ""),
    "watch_project_integration": "1" if watch_integration else "0",
}

for key, value in values.items():
    print(f"{key}\t{safe_value(value)}")
PY
    )"; then
      echo \
        "error: the GameTime target or Release build settings could not be read" \
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
        excluded_sources) excluded_sources="$value" ;;
        watch_project_integration) watch_project_integration="$value" ;;
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
    "Release declares a resolved non-development app identity."
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
    "Release targets iPhone only."
else
  block_check \
    "iphone-only" \
    "Release must target device family 1 only; iPad is deferred."
fi

if [[ "$app_icon_name" == "AppIcon" ]]; then
  pass_check \
    "app-icon-setting" \
    "Release selects the AppIcon asset set."
else
  block_check \
    "app-icon-setting" \
    "Set the Release app icon asset name to AppIcon."
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
    "Release has a resolved marketing version."
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
    "Release has a positive resolved build number."
else
  block_check \
    "build-number" \
    "Set a positive resolved build number; verify uniqueness at candidate freeze."
fi

watch_source_reachable="0"
if [[ -d "$app_source" ]]; then
  watch_source_reachable="$(
    python3 - "$app_source" "$excluded_sources" <<'PY'
import ast
import pathlib
import re
import sys

app_source = pathlib.Path(sys.argv[1])
excluded_sources = set(sys.argv[2].split())
watch_pattern = re.compile(
    r"import\s+WatchConnectivity|WCSession|"
    r"PhoneWatchConnectivityCoordinator|GameTimeWatch"
)
directive_pattern = re.compile(
    r"^\s*#(if|elseif|else|endif)\b(?:\s+(.*))?$"
)


def release_condition(expression):
    """Evaluate only conditions composed of known Release-false flags."""
    if expression is None:
        return None

    identifiers = set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", expression))
    if not identifiers.issubset({"DEBUG", "STAGING"}):
        return None

    translated = re.sub(r"\bDEBUG\b", "False", expression)
    translated = re.sub(r"\bSTAGING\b", "False", translated)
    translated = translated.replace("&&", " and ")
    translated = translated.replace("||", " or ")
    translated = re.sub(r"!(?!=)", " not ", translated)

    try:
        tree = ast.parse(translated.strip(), mode="eval")
    except SyntaxError:
        return None

    allowed_nodes = (
        ast.Expression,
        ast.BoolOp,
        ast.UnaryOp,
        ast.Constant,
        ast.And,
        ast.Or,
        ast.Not,
        ast.Load,
    )
    if any(not isinstance(node, allowed_nodes) for node in ast.walk(tree)):
        return None

    return bool(eval(compile(tree, "<release-condition>", "eval"), {}, {}))


def contains_release_watch_reference(source_file):
    active = True
    frames = []

    for line in source_file.read_text(encoding="utf-8").splitlines():
        directive = directive_pattern.match(line)
        if directive:
            kind, expression = directive.groups()
            if kind == "if":
                condition = release_condition(expression)
                if condition is None:
                    frames.append(
                        {
                            "parent_active": active,
                            "passthrough": True,
                            "branch_taken": False,
                        }
                    )
                else:
                    frames.append(
                        {
                            "parent_active": active,
                            "passthrough": False,
                            "branch_taken": condition,
                        }
                    )
                    active = active and condition
            elif kind == "elseif" and frames:
                frame = frames[-1]
                if frame["passthrough"]:
                    active = frame["parent_active"]
                elif frame["branch_taken"]:
                    active = False
                else:
                    condition = release_condition(expression)
                    if condition is None:
                        frame["passthrough"] = True
                        active = frame["parent_active"]
                    else:
                        frame["branch_taken"] = condition
                        active = frame["parent_active"] and condition
            elif kind == "else" and frames:
                frame = frames[-1]
                if frame["passthrough"]:
                    active = frame["parent_active"]
                else:
                    active = frame["parent_active"] and not frame["branch_taken"]
                    frame["branch_taken"] = True
            elif kind == "endif" and frames:
                frame = frames.pop()
                active = frame["parent_active"]
            continue

        if active and watch_pattern.search(line):
            return True

    return False


for source_file in app_source.rglob("*.swift"):
    if source_file.name in excluded_sources:
        continue
    if contains_release_watch_reference(source_file):
        print("1")
        break
else:
    print("0")
PY
  )"
fi

if
  [[ "$watch_project_integration" == "0" ]] &&
    [[ "$watch_source_reachable" == "0" ]]
then
  pass_check \
    "watch-isolation" \
    "Watch work is not embedded in or reachable from the iPhone candidate."
else
  block_check \
    "watch-isolation" \
    "Keep concurrent Watch work outside the iPhone beta target and root journey."
fi

supabase_url=""
supabase_publishable_key=""
if [[ -f "$public_config" ]]; then
  supabase_url="$(xcconfig_value "$public_config" SUPABASE_URL)"
  supabase_publishable_key="$(
    xcconfig_value "$public_config" SUPABASE_PUBLISHABLE_KEY
  )"
fi
normalized_supabase_url="${supabase_url//\$\(\)/}"

if
  [[ "$normalized_supabase_url" =~ ^https://[A-Za-z0-9-]+[.]supabase[.]co/?$ ]] &&
    [[ "$supabase_publishable_key" =~ ^sb_publishable_[A-Za-z0-9._-]{12,}$ ]]
then
  pass_check \
    "public-client-config" \
    "Release has a Supabase HTTPS URL and public publishable key."
else
  block_check \
    "public-client-config" \
    "Configure the reviewed beta Supabase URL and a public publishable key."
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
    "Release includes the public client configuration exactly once."
else
  block_check \
    "public-client-binding" \
    "Release must include PublicClient.xcconfig exactly once."
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
    "No secret-shaped literal was found in public Release inputs."
else
  block_check \
    "public-client-secrets" \
    "Remove secret-shaped values or private includes from public Release inputs."
fi

printf '\nBeta candidate source preflight: %d passed, %d blocker(s).\n' \
  "$pass_count" \
  "$blocker_count"
echo \
  "Evidence boundary: this does not prove account identity, hosted runtime, signing, archive contents, App Attest client/server compatibility, device behavior, or TestFlight."

if (( blocker_count > 0 )); then
  exit 1
fi
