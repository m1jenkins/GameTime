# Export-compliance review draft — September 30, 2026

The existing archive has no `ITSAppUsesNonExemptEncryption` declaration.
The proposed operating-system-only/exempt answer remains **pending the owner's
confirmation**. No answer was filed, plist changed or archive replaced.

Apple requires a determination even when an app uses operating-system crypto.
Its current documentation says that encryption confined to Apple's operating
system requires no encryption documentation in App Store Connect. These are
distinct questions; exemption from documentation does not mean the app has
no crypto. See [Apple's overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
and [documentation matrix](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/).

## Technical evidence actually inspected

Native app/configuration source matches the September 29 `b16685b` archive.
The resolved dependencies used by the fresh builds include Supabase 2.46.0,
Swift Crypto 4.5.1 and Stripe 26.4.1. The checked-in package resolution is
unchanged from the archive's recorded source.

| Input | Local finding |
| --- | --- |
| App source | URLSession HTTPS, Apple sign-in nonce hashing, CryptoKit SHA-256, Keychain storage and the Apple device-check path |
| Supabase Auth | PKCE imports `Crypto`; RSA token verification calls `SecKeyVerifySignature` |
| Swift Crypto | Its selected Apple-platform `Crypto` target reexports CryptoKit. That target's BoringSSL dependencies and forced implementation are conditional on other platforms; development override is false. Other package targets were not treated as selected app inputs |
| Stripe 3DS2 source | The dependency includes JSON Web Encryption code. AES/HMAC calls use CommonCrypto; RSA-OAEP calls `SecKeyCreateEncryptedData`. Payments being disabled does not justify omitting the dependency from this review |
| Archived arm64 binary | `nm -arch arm64 -m` exited 0. Imports include `CCCrypt` from libSystem, RSA encryption/signature verification from Security, and 16 CryptoKit symbols. No symbol name matched `CCryptoBoringSSL` |

The SDK checks used the ignored resolved checkout under
`tmp/testflight-readiness-2026-09-30/native/DerivedData/SourcePackages/checkouts/`:
`supabase-swift/Sources/Auth/Internal/PKCE.swift`, `JWK+RSA.swift` and
`JWTAlgorithm.swift`; `swift-crypto/Package.swift` and the `Sources/Crypto`
conditional imports; `stripe-ios-spm/Stripe3DS2/Stripe3DS2/STDSJSONWebEncryption.m`
and `STDSDirectoryServerCertificate.m`.

The symbol check targeted the actual existing archived `GameTime` executable.
Absence of a symbol-name match is a bounded observation, not a complete
binary-level proof that no other implementation exists.

## Proposed answer and remaining action

The inspected operations support an **inference** that this iOS candidate
uses operating-system crypto and qualifies for Apple's no-documentation path.
The old “only HTTPS and Sign in with Apple” description was incomplete.
The private ASC draft now includes the hashing, storage, device-check and
resolved SDK scope above.

The owner must confirm the declaration for this exact candidate before it is
entered in App Store Connect. If confirmed, a future candidate may set
`ITSAppUsesNonExemptEncryption = NO` with separate authorization. Adding that
key is unnecessary to inspect or re-sign the already preserved archive;
Apple also provides a [per-build beta compliance flow](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/).
