# P5 concise review

One read-only review-and-simplify pass covered cursor/authorization correctness,
query efficiency, and reuse/clarity. Main agent alone applied fixes.

- Restricted member-trigger history refresh to the changed actor. The 250-person
  exit fixture previously repeated 62,500 upsert/delete attempts; the corrected
  path visits 250 members. Four actual SQL measurements fell from 242–264 ms to
  19–20 ms, retaining all 250 history rows. Lobby/final changes still update the
  entire affected roster.
- Restored final session validation before both page response paths. A shared
  session lock prevents committed revocation but cannot stop clock expiry.
  Actual-session tests now hold page creation across not_after expiry and assert
  denial for both history and upcoming pages. They also prove cancellation can
  commit while a history read waits and that the read expires on order change.
- Added expected-source marker checks to migration function adapters, following
  the existing forward-migration convention.

No new client code is necessary: ChallengeJSON cursors are already opaque, and
projection_revision remains stable for each accepted page chain. New history
chains expire explicitly on ordering/membership changes; old offset snapshots
remain readable during their existing lifetime.

Remaining discovery/status work is linear in live eligible challenges/members;
this change does not make exact global operational counts constant-cost or
establish hosted capacity. No follow-up review loop or release matrix was run.
