# Native create and invite integration — September 21, 2026

The approved create/invite visual direction is now implemented in the ordinary
SwiftUI routes. The HTML files remain a dated design proposal; native screens use
real stores and retain the existing versioned agreements.

## Implemented

- `ChallengeV1Create` uses the locked light palette, neutral 24-point metric cards,
  athletic numeric typography, native SF Symbols, numbered progress and quiet
  agreement rows. Dates, amount editing, validation, Health readiness, explicit
  Personal consent and durable creation recovery keep their existing owners.
- A confirmed friend creation opens `ChallengeCreationInviteView` with the saved
  challenge ID. Existing lobbies also expose an Invite friends route.
- Direct invitations use exact accepted-friend usernames and the current lobby
  revision. Members and initials come from refreshed saved records. Invitation
  acknowledgement requires the correct successful receipt; interrupted actions
  retain the same persisted request when retried.
- Invitation links reuse `ChallengeLinkIssuer`, configured HTTPS origins, private
  token persistence, expiry, sharing and revocation. Opening the page sends nothing.
- Confirmation describes a saved lobby, not an agreed or active challenge. Each
  participant's goal, roster selection, final rules and consent remain in the lobby.
- Dark appearance and accessibility contrast retain native semantic adaptations;
  larger text reflows instead of fixing the design to a screenshot size.

## Deliberate contract differences from the HTML proposal

The current native contract keeps its $20 simulated default and $1–$500 range;
optional $0 entry and personal-only friend consequences need a new agreement
version. Existing friend allocation rules are visible in review. Arbitrary names,
address-book access and portrait discovery are not implemented. The native screen
uses real username and link invitations instead of the mock's fictional contacts.
Friend goals are proposed by each person in the saved lobby. No backend policy,
payment, notification delivery, deployment or installed physical-device app changed.

## Verification

- Debug build and simulator launch passed on iOS 26.5.
- 56 focused native tests passed, with no failures or skips: creation draft (12),
  new create/invite flow (9), Health flow (17), invitation recovery (15), and
  semantic theme checks (3).
- New tests verify automatic navigation only after a saved lobby, exact receipt
  identity, uncertain-response retry, account changes, stale roster privacy,
  saved confirmation and light/dark accessibility rendering.
- `scripts/check-iphone-product.py` and `git diff --check` passed.
- Initial verification found eight screenshot-test failures. Captures showed
  correct production text; tests were repaired for navigation chrome inserted
  between OCR pages, native hierarchy capture, and previously changed Share/Turn
  off link labels. Complete consent wording, exact recovered URL, revocation and
  account-isolation assertions remain checked. The complete 56-test rerun passed.

Native captures use fictional accounts and an in-memory service through the
production SwiftUI views and store. The loopback service UI journeys were updated
for the new route but not run in this task. Hosted invitation delivery, physical
Health, human VoiceOver and physical-device installation remain unperformed.

## Native captures

- [Goal entry](captures/native-create-goal-page-0.png)
- [Challenge review](captures/native-create-challenge-page-0.png) and
  [agreement/actions](captures/native-create-challenge-page-1.png)
- [Invite friends](captures/native-invite-friends-page-0.png) and
  [saved members](captures/native-invite-populated-page-0.png)
- [Confirmation](captures/native-create-confirm-page-0.png)
- [Dark accessibility confirmation](captures/native-create-confirm-dark-accessibility-page-0.png)
- [Verification record](captures/native-create-invite-checks.json)

The `native-*` capture pages include scrolling continuations and recovery states;
recognized-text transcripts accompany them. Original HTML mock captures stay
separate. The local result bundle is
`/private/tmp/gametime-native-create-invite-final.xcresult`.
