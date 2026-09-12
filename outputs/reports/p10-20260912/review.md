# P10 focused review

Reviewed the final preparation scope against Prompt 10, D134/D135, P4 claims,
P6 permissions/disclosure, the public API catalog, native identities and existing
release-readiness decision. This is a focused self-review, not an independent
release audit.

- All unselected target, identity, publication, policy, staff and data-retention
  values are null. Proposed schedules/alerts/session settings are explicitly
  unapproved and disabled. Apple sign-in and the five-person/900-second privacy
  contract remain adopted requirements rather than reopened decisions.
- No native/backend/migration/configuration/runtime behavior changes. The audit
  SQL uses a repeatable-read, read-only transaction, bounded timeouts and catalog
  metadata; runtime output excludes actors and the fictional clock. Permission
  inventory and HTTP denials agree: zero anonymous challenge RPCs; authenticated
  operators still require current scoped capability/session.
- Current service authority is deliberately reported as broad. Fixture-dependent
  scheduling, raw service shortcuts and legacy public API exposure are unresolved
  hosted boundaries, not accepted least privilege. No credential was issued or
  altered. No enabled scheduler/deployment file was created.
- Corrected the stale local runbook's claim that a challenge moderator can suspend
  globally and that a paused worker creates safety-processing leases. P6 global
  support is separate; P4 pauses new leases while explicit safe actions continue.
- Recorded that the local CLI lacks P6 support/appeal/revocation commands, that
  native invitation parsing is custom-scheme-only, and that status excludes work
  outside the eligible set. Do not bypass those limitations during hosting.
- Added the concrete migration hazard: four active historical jobs, including
  push and retention, require review/prevention before hosted migration application.
  Current owned audit data contained no user accounts/challenges/provider secrets.
- Recovery preserves requests, consent, agreements, exits and actual review
  timestamps. Database restore, code rollback and privacy deletion are separate.
  Retention includes token-bearing issuance retry receipts, derived projections,
  backup revocation replay and external support/log providers.
- Existing product tests and all migration bytes are preserved. 203 affected SQL
  assertions, 68 local HTTP denials and two worker transport tests passed. The
  source preflight remains blocked at the three expected unconfigured destinations.
  No broader SQL/native/device/hosted/release acceptance is inferred.

No unresolved defect in this preparation scope was identified. Hosted least
privilege, actual support/alerts, real worker/admission/ingestion and all P7–P9
source-backed claims remain explicitly unaccepted. No later prompt was started.
