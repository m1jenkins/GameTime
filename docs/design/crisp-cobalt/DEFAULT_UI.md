# Default Cobalt interface — September 11, 2026

The owner requested adoption of `codex/crisp-cobalt-ui` and installation on
Mason’s iPhone. The normal signed-in root now opens Cobalt Home, Challenges and
You in Debug, Staging and Release, without a preview launch argument.

The real authentication/onboarding path and account settings remain intact.
Existing challenges opens the retained Personal shell with its original
payment-test disclosure and exact agreements. The explicit historical demo and
fixture journeys remain available. The Debug local challenge preview stays
separate from ordinary launches.

The product challenge client has no transport and reports unavailable. Home
explains that new friend challenges and personal goals are not open, and New
challenge opens that explanation instead of a form that cannot submit. No
fictional scores are shown as signed-in account data. Hosted challenge
admission, Health scoring and money gates are unchanged. The local privacy and
fictional-account login views remain Debug-only; the regular You tab uses the
existing real-account privacy, support and sign-out destinations.

## Performed verification

- Signed Debug device compilation passed.
- Signed Release compilation passed with direct xcodebuild at 21:28:51 UTC
  (50.1 seconds). The existing WeeklyModels trailing-closure warning remains.
- Three Cobalt rendered tests passed on the final app code: current/compact/
  dark/accessibility Home, every metric/community privacy, and unknown/tied/
  redacted/recovery states.
- Existing signed-out/onboarding UI regression passed. Its pre-existing layout
  path emitted an invalid-frame warning; it is not an accessibility acceptance.
- The new product-shell UI journey passed at 21:30:11 UTC (55.6 seconds): Home,
  closed creation, retained Personal navigation/disclosure, return to Cobalt,
  real account support, and sign-out. The first run used a label instead of the
  existing compound button identifier; correcting the test selector made the
  rerun pass without an app-code change.
- The first incremental test run executed only four of five discovered tests;
  it was not counted as the new journey’s acceptance. Subsequent verification
  forced direct xcodebuild and confirmed the new test actually ran.
- `scripts/check-iphone-product.py --app` passed against the signed Release
  product: 148 active source files, HealthKit linked, no Watch payload or links.
- `git diff --check` passed.

The final Home capture uses a fictional signed-in test actor with the same
closed client as normal launch: [default Home](screenshots/native/cobalt-default-signed-in.png).
The broader human accessibility and physical Health limitations in
[VERIFICATION.md](VERIFICATION.md) remain open. This direct owner-device install
does not establish distribution acceptance.

## Owner-device installation

Signed Staging device build passed at 21:31:21 UTC (113.0 seconds). The iPhone
product guard also passed against this product. XcodeBuildMCP installed
`com.mjenkins.gametime.staging` successfully on the connected **Mason’s iPhone**
(iOS 27.0), preserving the app container by installing over the existing bundle.
The normal launch used no arguments. iOS refused to open it because the phone
was locked; physical launch/UI observation is therefore not claimed. Unlocking
the phone and opening GameTime uses the default Cobalt signed-in root.
