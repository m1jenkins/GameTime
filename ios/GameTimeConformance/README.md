# GameTime M6.5 App Attest conformance target

This is a deliberately small iOS 18 SwiftUI target for one staging smoke test:

1. generate and persist one App Attest key ID;
2. fetch an account-bound challenge;
3. pass `SHA256(challenge bytes)` to `attestKey`;
4. register the attestation with Apple's returned key ID unchanged;
5. encode, assert, and send one metric request using
   `EncodedMetricRequest.body`;
6. send that same metric `URLRequest` again, preserving its exact body and
   assertion, and require HTTP 200, `replayed=true`, and the same batch ID;
7. encode, assert, and send one geofence check-in using
   `EncodedCheckInRequest.body`; and
8. send that same check-in `URLRequest` again, preserving its exact body and
   assertion, and require HTTP 200, `replayed=true`, and the same check-in ID.

The app decodes each assertion's local big-endian counter from bytes 33–36 of
`authenticatorData`. It shows counters, request digests, response outcomes, and
the exact GameTimeCore JSON bodies in the UI. Registration also displays the
server-verified App Attest validation category and bundle version for D46 when
the OS supplies those iOS 27 extensions. On earlier supported systems, each
field is reported explicitly as `unavailable on this OS` and registration
continues to require `registered=true` and `environment=development`.

## Provision staging

Staging must use the real verifier, not the unsigned development bypass:

```text
GAMETIME_ENV=staging
APP_ATTEST_ALLOW_DEVELOPMENT=true
ATTEST_DEV_BYPASS=<absent>
APPLE_TEAM_ID=<your-team-id>
APPLE_BUNDLE_ID=<your-conformance-bundle-id>
GAMETIME_ATTEST_CHALLENGE_SECRET=<dedicated 32+ character secret>
APP_ATTEST_ROOT_CA_PEM=<Apple App Attestation Root CA PEM>
APP_ATTEST_RECEIPT_ROOT_CA_PEM=<Apple Root CA G3 PEM>
```

Use `scripts/m6-5-configure-staging.sh` rather than copying certificate text by
hand; it fetches both public roots from Apple, verifies their recorded SHA-256
fingerprints, and removes `ATTEST_DEV_BYPASS`. The complete procedure and
observation record are in `docs/M6_5_DEVICE_CONFORMANCE.md`.

The signed-in user needs a profile and an accepted roster row in an active
contest. The contest must have at least one fully completed hour in the user's
frozen time zone. The geofence ID must belong to that contest, and the entered
coordinate should be inside it.

## Provision the iPhone target

Open `GameTimeConformance.xcodeproj`, select the **GameTimeConformance** target,
and select an active Apple Developer Program or Enterprise Program team with an
explicit App Attest-enabled App ID. A Personal Team cannot provision this
capability. Set the matching unique bundle identifier. No team ID, certificate,
profile, key, URL, or token is committed. The target already has the development
entitlement:

```text
com.apple.developer.devicecheck.appattest-environment = development
```

Run the `GameTimeConformance` shared scheme on a physical supported iPhone.
Simulator can compile the target but reports App Attest as unavailable.
If Xcode reports that the selected Personal Team does not support App Attest,
stop and change to an eligible team; do not remove the entitlement to force an
install.

## Runtime fields

Enter these values in the app:

- staging Supabase origin such as
  `https://abcdefghijklmnopqrst.supabase.co` (a complete `/functions/v1` base
  also works);
- the project's publishable key or legacy anon key;
- a currently valid user access JWT, without the `Bearer` prefix;
- contest UUID;
- geofence UUID;
- latitude and longitude inside that geofence; and
- the accepted participant's IANA time-zone identifier, such as
  `America/Chicago`.

The URL, API key, JWT, IDs, and coordinate remain in memory only. The Apple key
ID is the sole persisted runtime value. Its returned string is stored in
`UserDefaults` under `GameTimeConformance.appAttestKeyID.v1`; it is not stored
in Keychain. The private key remains managed by App Attest in the Secure
Enclave. A full run certifies the generated key with Apple, so do not start a
second full run with that already-attested key. Delete and reinstall the app
when another complete registration run is intentionally required.

For credential safety, the app refuses to send the API key or JWT unless the
URL host is exactly `<20 lowercase alphanumeric characters>.supabase.co`, has
no user info or port, and has either no path or exactly `/functions/v1`.

Tap **Run conformance** once. A successful run ends with a metric counter, a
strictly larger check-in counter, and identical metric and check-in replays
returning HTTP 200 with `replayed=true` and their original record IDs.

## Local validation

These commands are required local gates, not current CI evidence. The
conformance target is not continuously built.

Build the app without signing:

```sh
xcodebuild \
  -project ios/GameTimeConformance/GameTimeConformance.xcodeproj \
  -scheme GameTimeConformance \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the protocol/CBOR/exact-replay unit tests with an installed iOS Simulator:

```sh
xcodebuild \
  -project ios/GameTimeConformance/GameTimeConformance.xcodeproj \
  -scheme GameTimeConformance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test
```
