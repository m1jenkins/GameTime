# Integrated local candidate — September 19, 2026

Candidate branch: **`codex/integrated-candidate-20260919`**. Retained review
worktree: `/private/tmp/gametime-integrated-20260919`. Base and unchanged main:
**`9f116ac4954594a8d64467f78a6dca55d3cc2ce4`**. No push, main merge, hosted
mutation, deployment or release action was performed.

Runtime and migration code is integrated at `e0e9ef26fb5b508cac0f004b24090144c47a84f7`.
Strict combined snapshot verification is committed at
`ac0d20589c8f6da41a90bfb8dd94c09690fff809`; the deletion race harness's shutdown
argument is corrected at `f88657a5cc6d7c116a215dfbf0ac32b0becaa008` (the final code/test commit). Subsequent
candidate commits record status and evidence only. The [input manifest](integrated-candidate-20260919/tested-inputs.json)
records exact hashes. Native products were built at `e0e9ef2`; all native inputs
are unchanged through the final code commit. Later SQL/HTTP runs used the same
85 migration files; the concurrency rerun used the corrected deletion harness.

## Delivered source and integration decisions

| Delivered branch | Exact integrated tip | Behavior |
| --- | --- | --- |
| `codex/https-invitations` | `a2cd5091d32ce18ef63cd2669ebef3393b7ea9b9` | Configured exact-origin HTTPS intake/formatting, durable opaque intent and deliberate redemption; implementation `71fc742ca96fc7406558d2dfe3b122b8308e1045` |
| `codex/review-appeal-monitoring` | `3f62ff88d2638b4569ac9d8b36d3b4a33a78879b` | Service-only saved review/appeal counts and current independent-operator authorization projection |
| `codex/admin-grant-response-recovery` | `c547471e508c30346ee43e2738300af340f96c68` | Versioned administrator requests, immutable exact receipts and private CLI journals |
| `codex/suspended-account-access` | `8c4f4388f64e77b3e65c0e82763dd1186c6e5ddd` | Restores permitted suspended own reads, appeals, safe actions and exact recovery while retaining deletion/session fences and operation restrictions |
| `codex/community-snapshot-status` | `d44fe7b2db07095ba919ac6dcf4d5df5a04abd7a` | Selected-cohort read-only snapshot monitoring; implementation `a9530702597b9da4f788585a53897352453f8d79` |

All five tips are merge ancestors. Main's profile retry at
`70584f16959885b4610cd635d3e8b81e70f85f4f` and actor-switch correction at
`9f116ac4954594a8d64467f78a6dca55d3cc2ce4` remain ancestors and are included in
combined native verification. No cancelled or archived candidate was imported.

Two independently completed snapshot implementations were available. This
candidate selects `codex/community-snapshot-status`, with explicit wall-clock
field names, unavailable selection states and its separate verification runner.
The alternative `codex/community-snapshot-freshness` at
`044263834e5fffd9711c3005d34f56024a1b7c8e` remains untouched and is **not merged**.
They define the same RPC with different output field contracts; installing both
would be invalid. The chosen contract is [documented here](../../docs/COMMUNITY_SNAPSHOT_STATUS_LOCAL.md).
Neither branch supplies an approved freshness threshold or hosted monitor.

The only merge conflict was the shared operator smoke. Both behavior sets remain:
run administrator response-loss/concurrency/authority checks before deliberately
suspending their moderator fixture, then exercise suspended operator denial and
expired/revoked-session access. Shared credential scans and equivalent authority
checks are kept once. The full default smoke runs all these checks together;
`--administration-only` was not used for acceptance.

Migration timestamps are distinct; all four delivered forward migrations are
unchanged. Existing migration bytes are unchanged. Review-monitor suite 515 and
snapshot suite 515 originally shared a numeric prefix; snapshot is now 518, with
identical assertions. The snapshot runner now requires full 494/506/507 TAP
success and no longer accepts the earlier suspended-session failure as a limit.
It also waits for final database startup and requires the explicit loopback
security advisor to pass. Current status documents are reconciled separately;
all five delivered dated reports and their original evidence remain unchanged.

## Actual combined verification

| Check on integrated source | Actual result |
| --- | --- |
| Debug native build-for-testing, Xcode 27 / iPhone 17 Pro / iOS 27.0 | Passed; existing `WeeklyModels.swift:275` trailing-closure warning |
| Focused native invitation/account isolation/profile retry/deletion/retained Personal tests | **159 passed, 0 failed, 0 skipped**; [suite counts](integrated-candidate-20260919/native-verification.json) |
| Fresh final-schema SQL: 440, 493, 494, 497, 501, 502, 506–509, 512–518 | **614 assertions / 17 suites**, complete contiguous TAP plans, no failure/skip/TODO/SQL error; [results](integrated-candidate-20260919/combined-run2-sql-results.json) |
| Complete default operator CLI/Auth/PostgREST smoke | **230 checks passed**, including all six lost administrator responses, duplicate/conflicting concurrent requests, human review/moderation/suspension/independent appeal recovery, and expired/revoked suspended sessions |
| Operator journal/parser units | **11/11 passed** |
| Review/appeal actual local Auth/PostgREST smoke after upgrade | **18/18 passed**, including ordinary/reviewer/support denial, real local sign-in, scope/independence and paused/disabled states |
| Separate final snapshot runner | **218 SQL assertions / 6 suites**, **48 runner checks** including setup, SQL summaries and HTTP checks; these are not 48 independent HTTP scenarios. [Final verification](integrated-candidate-20260919/snapshot-verification.json) |
| Populated forward upgrade from main's complete 81-migration schema | **431/431 assertions** after all four forward migrations; [results](integrated-candidate-20260919/upgrade-run2-sql-results.json) |
| Affected deletion concurrency | **23/23 passed**; [concurrency verification](integrated-candidate-20260919/concurrency-verification.json); actual separate PostgreSQL sessions and observed lock waits |
| Suspended-session lock waits | **12/12 passed** in the same record; actual expiry while waiting, unchanged locked rows, deletion winning a wait, live/expired/missing sessions and exact receipt recovery |
| Deletion handler / Apple-adapter units | **14 passed, 0 failed** with `deno test --allow-env --cached-only delete-account`; providers mocked |
| Security advisors | Explicit owned loopback targets: combined, populated upgrade, snapshot and final concurrency stacks; exit 0, no warning/error issues |
| Product/configuration/preservation checks | iPhone source and built-bundle guard passed (156 source files, three iPhone targets, no Watch payload/link); readiness, entitlements, origin/default-off configuration and source preservation passed |

The fresh SQL run includes safety **22**, private community **67**, community
guards **18**, suspension access **71**, deletion **32**, deletion restore **21**
and deletion preservation **19** assertions. The previous suspended-account
failures are repaired and rerun successfully, not waived or relabeled. Their
original failures remain in the individual delivery reports.

The upgrade populated two- and five-person historical weekly agreements, seven
historical consents, Personal terms, new-domain agreements/request receipts,
three reviews, two appeals, scoped/support grants and a community capture plus
its dispatched invocation. It compared all **207** existing app/public tables
before/after migration and again after monitoring reads (414 table assertions).
All prior function ACLs/search paths were preserved. Every prior function
body was preserved except the expressly repaired `app.challenge_session_v1`.
No administrator receipt was backfilled. Old own reads and exact request replay
still work. This is a logical populated forward upgrade, not hosted rollout or
a physical backup/restore drill.

Snapshot checks verify that replay and throttled success cannot refresh capture
age, failures disclose only SQLSTATE, disabled/missing runtime remains explicit,
under-five privacy is preserved and status reads leave application/Auth rows
unchanged. GET and SQL READ ONLY calls pass. Snapshot HTTP roles use locally
signed fictional JWTs; the separate review and operator smokes use actual local
Auth. None establishes Apple authentication, gateway or physical-source acceptance.

## Reproduction and resource ownership

The checked-in [verification helper](integrated-candidate-20260919/verify.py)
reproduces the SQL/operator, populated-upgrade/review and concurrency lanes using
new labeled stacks and cached PostgreSQL `17.6.1.143`, GoTrue `v2.192.0` and
PostgREST `v14.14` images. It never resets an existing project. Run each lane
with a new private evidence directory; run lanes sequentially so subnet
allocation cannot race. From the candidate worktree:

```sh
export GAMETIME_INTEGRATION_EVIDENCE_DIR="$(mktemp -d /private/tmp/gametime-integration-repeat.XXXXXX)"
python3 outputs/reports/integrated-candidate-20260919/verify.py combined
python3 outputs/reports/integrated-candidate-20260919/verify.py upgrade
python3 outputs/reports/integrated-candidate-20260919/verify.py concurrency
python3 scripts/community-snapshot-status-verify.py \
  --evidence-dir "$GAMETIME_INTEGRATION_EVIDENCE_DIR/snapshot"
python3 scripts/tests/beta-operator.test.py
```

The private original run ledger is `/private/tmp/gametime-integration-lab-20260919`;
final snapshot receipts are `/private/tmp/gametime-integration-snapshot-final-20260919`.
The committed helper only relocates repository/evidence paths from that executed
helper; it adds no product behavior. Native manifest and result bundle paths are
in the [native record](integrated-candidate-20260919/native-verification.json).
Native tests used `--fixture-mode --fixture-product-shell`, an isolated derived
product and task-created Simulator `4957DF75-29CC-4D21-8C00-8E372C413C76`.
The test runner shut down that simulator; it was then deleted. No existing
simulator, preview controller, retained database or other worktree was driven.

All owned database/Auth/REST containers and their volumes/networks were removed.
Cron launching was disabled from first start; no jobs executed. Final combined,
upgrade and concurrency cleanup closed runtime gates, revoked local sessions,
removed connection credentials and verified closed ports. Snapshot's runner
verified read-only behavior even with runtime removed, then removed its entire
owned stack. [Disposition records](integrated-candidate-20260919/disposition.json)
retain exact owners and failed-attempt cleanup. No machine-wide unchanged-state
claim is made; cleanup was restricted to verified owned resources.

Failed attempts are preserved separately from passing acceptance:

- Initial combined/upgrade bootstrap used the temporary startup socket too early
  and omitted the private container listener. Neither reached product tests.
  Both stacks were removed; fresh corrected runs passed.
- The first integrated snapshot run passed SQL/HTTP but its advisor connection
  failed. The runner was corrected to use explicit TCP listening and non-TLS
  loopback, and now requires advisor success. The final committed-source rerun
  passed all checks and its advisor; the first attempt is not complete acceptance.
- The first deletion race run passed its assertions, but its cleanup used a
  fictional clock with fixtures disabled, which the existing runtime contract
  rejects. The suspended-wait harness correctly refused that open runtime.
  The outer owner cleanup closed and disposed it. The one-line deletion-harness
  correction uses null; both race lanes were rerun on a fresh stack.

No product assertion failure remains in accepted checks. The reports do not
convert earlier failures into passes or count repeated SQL suites as new coverage.

## Remaining dependencies and closed gates

- P7: four physical source policies, overlap/completeness/correction rules and
  measured timed-run tolerance. Existing private observations remain partial.
- P8/P9: versioned real ingestion/adapters, accepted-source journeys for all
  thirteen policies and actual approved Apple identity/HTTPS delivery. Domain,
  AASA/CDN/provisioning, signed entitlements, physical taps, uninstalled fallback
  and hosted invitation journeys remain unperformed.
- P10/P11: approved target/settings, scoped hosted credentials, staffed support,
  actual scheduler/alert delivery, retention/deletion/restore and capacity/recovery
  acceptance. Monitoring reports authorization/capture facts, not staffing or
  an accepted freshness threshold. Historical v1 grants still require manual
  reconciliation; v2 receipts do not backfill them.
- P12: full relevant native/SQL/historical/controller matrix, minimum/current iOS,
  supported sanitizers, signed Release packaging and physical/accessibility/human
  acceptance. The focused integration checks do not satisfy that matrix.
- P13: replacement acceptance before legacy shell retirement, then separately
  authorized private Beta/distribution. Public release and funded operation remain
  distinct decisions.

Checked-in challenge configuration stays **off**; invitation origin remains
**UNCONFIGURED**, associated-domain templates remain inactive, and all **18**
readiness gates remain **false**. Historical Personal/Solo/charity agreements,
consents and availability remain unchanged. No source, money, analytics,
notification, hosting or release gate was opened.
