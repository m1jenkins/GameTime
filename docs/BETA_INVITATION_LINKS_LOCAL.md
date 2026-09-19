# Local HTTPS invitations

This slice implements native parsing, formatting and durable intake for one
explicit `GAMETIME_INVITATION_HTTPS_ORIGIN`, followed by
`/challenge-invite/<64 lowercase hexadecimal characters>`. It does not choose
or activate a domain, Apple identity, associated-domain entitlement or backend.
Checked-in origin is `UNCONFIGURED`; challenge transport remains `NO`.

`AppConfiguration` supplies the same `ChallengeInvitation` value to the saved
intent, entry panel and issued-link display. The origin must be a bare HTTPS
DNS origin, optionally ending in `/`. Host and scheme case are normalized;
ports, credentials, wildcard/trailing-dot hosts, IP literals, encoded authority,
paths, queries, fragments and whitespace are rejected. No backend host is
inferred. An invalid/missing origin closes HTTPS intake and generation while
allowing the app to launch. Existing issued links remain revocable.

Incoming links require that exact host and path, with no percent encoding,
extra segment, query or fragment (even empty `?`/`#`). The existing
`gametime-beta://challenge-invite/<token>` intake remains compatible. Only the
explicit `.localFixture` configuration generates that custom-scheme format;
`ChallengeLocalLaunchView` uses it for the existing local preview. Historical
duel and Stripe callback handling is preserved.

## Durable delivery and consent

The existing root `onOpenURL` handler receives both cold and warm deliveries.
It saves only the opaque link in the existing protected, backup-excluded intent
file. Receipt does not fetch details, submit a request, choose a roster or agree
to anything. Cancelled/failed sign-in and relaunch retain the intent. A saved
HTTPS intent is exposed only with the same configured origin on relaunch;
changing or removing configuration does not delete the saved file.

After sign-in and age confirmation, **Use invitation** deliberately submits
through the existing actor-scoped request journal. Its action checks age,
current actor and pending/busy state as well as the button. Lost responses keep
the exact actor, request ID and payload for **Retry saved action**. Retry never
migrates to another account. A successful response clears only its unchanged
submitted link, and only while that submitting actor is still active; a newer
delivery survives. The unopened opaque intent is device-scoped, as before;
it can be deliberately used by a subsequently signed-in person, while submitted
requests and issued links remain account-scoped. Opening a link never consents
to challenge terms or creates financial exposure.

## Inactive deployment preparation

- [Configuration template](release/beta/InvitationLinks.xcconfig.template): one
  hostname derives the app's origin and the entitlement host. It is not included
  in any active build configuration.
- [Entitlement fragment](release/beta/InvitationLinks.entitlements.template):
  add to the approved target's existing entitlements only after approval. It is
  not a replacement for the current entitlements and is not referenced by Xcode.
- [AASA template](release/beta/apple-app-site-association.json.template): retains
  unselected application-identifier prefix and bundle-ID placeholders. It excludes
  nonempty queries/fragments and matches exactly 64 characters under the invitation
  path. The native parser additionally checks the hex alphabet and empty delimiters.

For purely local parser tests, `https://invites.example.invalid` is fictional.
No DNS, web request, Apple registration or HTTPS server is needed. A local
Debug override, if separately desired, uses xcconfig's escaped-slash spelling:

```xcconfig
GAMETIME_INVITATION_HTTPS_ORIGIN = https:/$()/invites.example.invalid
```

This changes parsing/formatting only. Do not enable transport to test a URL.

SwiftUI delivers universal links through
[`onOpenURL`](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:));
there is no second `NSUserActivity` redemption path. Association preparation
follows Apple's [associated-domain guidance](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
and [AASA component matching](https://developer.apple.com/documentation/bundleresources/applinks/details-swift.dictionary/components-swift.dictionary).

## Remaining acceptance

Local injected deliveries and fixture clients do not establish OS association,
Apple sign-in, hosted redemption or device acceptance. Those still require:

1. Approval of the exact owned HTTPS host, application identifier, target bundle
   and provisioning. Publish the AASA without redirects at the approved host's
   `/.well-known/apple-app-site-association`, then verify the signed entitlement,
   Apple association/CDN behavior and web fallback.
2. An authorized physical candidate: tap links from another app with GameTime
   terminated and running, with interrupted Apple sign-in, relaunch, expired
   sessions, account changes and invalid/expired/revoked links. Verify installed
   and uninstalled behavior. Simulator handler tests do not prove these taps.
3. Separately authorized backend integration and actual recipient/admission,
   expiry/revocation and lost-response checks with that target.

All source, hosted, human, device and distribution gates remain unchanged.
