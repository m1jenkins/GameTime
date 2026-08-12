#!/usr/bin/env bash
# Fixture coverage for scripts/check-beta-candidate.sh.
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
checker="${test_dir}/../check-beta-candidate.sh"
fixture_root="$(
  mktemp -d "${TMPDIR:-/tmp}/gametime-beta-preflight-test.XXXXXX"
)"

cleanup() {
  rm -rf "$fixture_root"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    fail "expected output to contain: ${expected}"
  fi
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"
  if [[ "$output" == *"$unexpected"* ]]; then
    fail "output exposed a forbidden fixture value"
  fi
}

write_project_fixture() {
  local root="$1"
  local bundle_identifier="$2"
  local device_family="$3"
  local icon_name="$4"

  mkdir -p "${root}/ios/GameTime/GameTime.xcodeproj"
  cat >"${root}/ios/GameTime/GameTime.xcodeproj/project.pbxproj" <<EOF
{
  "objects": {
    "TARGET": {
      "isa": "PBXNativeTarget",
      "name": "GameTime",
      "productName": "GameTime",
      "productType": "com.apple.product-type.application",
      "buildConfigurationList": "CONFIG_LIST",
      "dependencies": [],
      "buildPhases": []
    },
    "CONFIG_LIST": {
      "isa": "XCConfigurationList",
      "buildConfigurations": ["RELEASE"]
    },
    "RELEASE": {
      "isa": "XCBuildConfiguration",
      "name": "Release",
      "buildSettings": {
        "PRODUCT_BUNDLE_IDENTIFIER": "${bundle_identifier}",
        "TARGETED_DEVICE_FAMILY": "${device_family}",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "${icon_name}",
        "MARKETING_VERSION": "1.0.0",
        "CURRENT_PROJECT_VERSION": "42"
      }
    }
  }
}
EOF
}

write_info_fixture() {
  local root="$1"
  local scheme="$2"

  cat >"${root}/ios/GameTime/Configuration/AppInfo.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>${scheme}</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF
}

write_privacy_fixture() {
  local root="$1"

  cat >"${root}/ios/GameTime/GameTime/PrivacyInfo.xcprivacy" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyTrackingDomains</key>
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array/>
</dict>
</plist>
EOF
}

write_icon_fixture() {
  local root="$1"
  local asset_dir="${root}/ios/GameTime/GameTime/Assets.xcassets"
  local icon_dir="${asset_dir}/AppIcon.appiconset"

  mkdir -p "$icon_dir"
  cat >"${asset_dir}/Contents.json" <<'EOF'
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
EOF
  cat >"${icon_dir}/Contents.json" <<'EOF'
{
  "images": [
    {
      "filename": "AppIcon-1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
EOF
  python3 - "${icon_dir}/AppIcon-1024.png" <<'PY'
import binascii
import struct
import sys
import zlib

output_path = sys.argv[1]
width = 1024
height = 1024
row = b"\x00" + (b"\x1f\x4f\x46" * width)
pixels = row * height


def chunk(kind, data):
    checksum = binascii.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(pixels, 9))
png += chunk(b"IEND", b"")

with open(output_path, "wb") as output_file:
    output_file.write(png)
PY
}

write_release_fixture() {
  local root="$1"
  local scheme="$2"
  local include_public_client="${3:-yes}"
  local public_client_include=""

  if [[ "$include_public_client" == "yes" ]]; then
    public_client_include='#include "PublicClient.xcconfig"'
  fi

  cat >"${root}/ios/GameTime/Configuration/Release.xcconfig" <<EOF
${public_client_include}
GAMETIME_ENV = release
GAMETIME_PERSONAL_SETTLEMENT_MODE = stripe_sandbox
GAMETIME_STRIPE_RETURN_URL = ${scheme}:/$()/stripe-redirect
EOF
}

write_safe_public_fixture() {
  local root="$1"

  cat >"${root}/ios/GameTime/Configuration/PublicClient.xcconfig" <<'EOF'
SUPABASE_URL = https://fixture-beta.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_fixture_value
GAMETIME_PRIVACY_POLICY_URL = https://example.com/privacy
GAMETIME_BETA_TERMS_URL = https://example.com/beta-terms
GAMETIME_SUPPORT_EMAIL = support@example.com
EOF
}

make_passing_fixture() {
  local root="$1"
  local scheme="gametime-beta"

  mkdir -p \
    "${root}/ios/GameTime/Configuration" \
    "${root}/ios/GameTime/GameTime"

  write_project_fixture \
    "$root" \
    "com.acme.gametime" \
    "1" \
    "AppIcon"
  write_release_fixture "$root" "$scheme"
  write_safe_public_fixture "$root"
  write_info_fixture "$root" "$scheme"
  write_privacy_fixture "$root"
  write_icon_fixture "$root"

  cat >"${root}/ios/GameTime/GameTime/GameTimeApp.swift" <<'EOF'
import SwiftUI

@main
struct GameTimeApp: App {
    #if DEBUG || STAGING
    private let watchConnectivity = PhoneWatchConnectivityCoordinator()
    #endif

    var body: some Scene {
        WindowGroup { Text("Fixture") }
    }
}
EOF
}

make_blocked_fixture() {
  local root="$1"
  local fake_secret="sk_test_fixture_value_never_print"

  mkdir -p \
    "${root}/ios/GameTime/Configuration" \
    "${root}/ios/GameTime/GameTime"

  write_project_fixture \
    "$root" \
    "com.example.gametime.staging" \
    "1,2" \
    ""
  write_release_fixture "$root" "gametime-staging"
  write_info_fixture "$root" "gametime-staging"

  cat >"${root}/ios/GameTime/Configuration/PublicClient.xcconfig" <<EOF
SUPABASE_URL = https://beta-project.example.invalid
STRIPE_SECRET_KEY = ${fake_secret}
EOF

  cat >"${root}/ios/GameTime/GameTime/GameTimeApp.swift" <<'EOF'
import SwiftUI
import WatchConnectivity

@main
struct GameTimeApp: App {
    private let watchSession = WCSession.default

    var body: some Scene {
        WindowGroup { Button("Sync my steps") {} }
    }
}
EOF
}

passing_root="${fixture_root}/passing"
blocked_root="${fixture_root}/blocked"
corrupt_icon_root="${fixture_root}/corrupt-icon"
nested_include_root="${fixture_root}/nested-include"
unbound_public_root="${fixture_root}/unbound-public"
disguised_include_root="${fixture_root}/disguised-include"
make_passing_fixture "$passing_root"
make_blocked_fixture "$blocked_root"
make_passing_fixture "$corrupt_icon_root"
make_passing_fixture "$nested_include_root"
make_passing_fixture "$unbound_public_root"
make_passing_fixture "$disguised_include_root"

: >"${corrupt_icon_root}/ios/GameTime/GameTime/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
cat >>"${nested_include_root}/ios/GameTime/Configuration/PublicClient.xcconfig" <<'EOF'
#include "Secrets.xcconfig"
EOF
write_release_fixture "$unbound_public_root" "gametime-beta" "no"
cat >>"${disguised_include_root}/ios/GameTime/Configuration/Release.xcconfig" <<'EOF'
#include "Secrets.xcconfig" // "PublicClient.xcconfig"
EOF

passing_output=""
if ! passing_output="$(bash "$checker" --root "$passing_root" 2>&1)"; then
  echo "$passing_output" >&2
  fail "passing fixture was rejected"
fi

assert_contains "$passing_output" "PASS release-bundle-id"
assert_contains "$passing_output" "PASS personal-snapshot-auth"
assert_contains "$passing_output" "PASS personal-automatic-copy"
assert_contains "$passing_output" "PASS iphone-only"
assert_contains "$passing_output" "PASS watch-isolation"
assert_contains "$passing_output" "PASS privacy-policy-url"
assert_contains "$passing_output" "PASS beta-terms-url"
assert_contains "$passing_output" "PASS support-contact"
assert_contains "$passing_output" "0 blocker(s)"
assert_not_contains "$passing_output" "app-attest-environment"

set +e
blocked_output="$(bash "$checker" --root "$blocked_root" 2>&1)"
blocked_status=$?
set -e

if [[ "$blocked_status" -ne 1 ]]; then
  echo "$blocked_output" >&2
  fail "blocked fixture should exit 1"
fi

for blocker_id in \
  stripe-return-scheme \
  app-url-scheme \
  release-bundle-id \
  iphone-only \
  app-icon-setting \
  app-icon-catalog \
  privacy-manifest \
  watch-isolation \
  privacy-policy-url \
  beta-terms-url \
  support-contact \
  personal-automatic-copy \
  public-client-secrets
do
  assert_contains "$blocked_output" "BLOCKER ${blocker_id}"
done

assert_not_contains "$blocked_output" "sk_test_fixture_value_never_print"

copy_only_output=""
if ! copy_only_output="$(
  bash "$checker" --root "$passing_root" --personal-copy-only 2>&1
)"; then
  echo "$copy_only_output" >&2
  fail "passing fixture failed the Personal automatic-copy-only audit"
fi
assert_contains "$copy_only_output" "PASS personal-automatic-copy"
assert_contains "$copy_only_output" "0 blocker(s)"

set +e
blocked_copy_output="$(
  bash "$checker" --root "$blocked_root" --personal-copy-only 2>&1
)"
blocked_copy_status=$?
set -e
if [[ "$blocked_copy_status" -ne 1 ]]; then
  echo "$blocked_copy_output" >&2
  fail "blocked fixture should fail the Personal automatic-copy-only audit"
fi
assert_contains "$blocked_copy_output" "BLOCKER personal-automatic-copy"

set +e
corrupt_icon_output="$(
  bash "$checker" --root "$corrupt_icon_root" 2>&1
)"
corrupt_icon_status=$?
set -e

if [[ "$corrupt_icon_status" -ne 1 ]]; then
  echo "$corrupt_icon_output" >&2
  fail "corrupt icon fixture should exit 1"
fi
assert_contains "$corrupt_icon_output" "BLOCKER app-icon-catalog"

set +e
nested_include_output="$(
  bash "$checker" --root "$nested_include_root" 2>&1
)"
nested_include_status=$?
set -e

if [[ "$nested_include_status" -ne 1 ]]; then
  echo "$nested_include_output" >&2
  fail "nested include fixture should exit 1"
fi
assert_contains "$nested_include_output" "BLOCKER public-client-secrets"

set +e
unbound_public_output="$(
  bash "$checker" --root "$unbound_public_root" 2>&1
)"
unbound_public_status=$?
set -e

if [[ "$unbound_public_status" -ne 1 ]]; then
  echo "$unbound_public_output" >&2
  fail "unbound public client fixture should exit 1"
fi
assert_contains "$unbound_public_output" "BLOCKER public-client-binding"

set +e
disguised_include_output="$(
  bash "$checker" --root "$disguised_include_root" 2>&1
)"
disguised_include_status=$?
set -e

if [[ "$disguised_include_status" -ne 1 ]]; then
  echo "$disguised_include_output" >&2
  fail "disguised include fixture should exit 1"
fi
assert_contains "$disguised_include_output" "BLOCKER public-client-secrets"

echo "PASS: beta candidate preflight fixtures"
