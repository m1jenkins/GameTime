# Focused P6 self-review

Scope: the forward community migration, new native projections/actions, tests and
short HTTP harness. This was a main-agent self-review, not an independent swarm.

Checked the shared projection path and legacy list/section/receipt endpoints;
publication/member/capacity metadata grants; exact-request recovery; report scope
under overlapping rosters; grant expiry and revocation; cross-challenge admission
and suspension lock order; source corrections; safe exits and final allocation.

Concrete findings closed:

1. Shared revisions and catalog counts revealed current membership. Private member
   revisions and a common delayed-count projection close both paths; old stored
   receipt bytes remain unchanged and their obsolete display revision is masked.
2. Reports inferred from co-membership crossed moderation scopes. Explicit scope
   rows and separate global grants replace that inference. Ordinary moderators'
   global suspension action is rejected.
3. A scoped report's local `target` name conflicted with a table column. Rename
   to `resolved_subject`; the full SQL pass includes both subject/subjectless paths.
4. Replacing an exited member broke settlement at 251 historical rows. The pure
   community evaluator now bounds nonexcluded participants and retains former
   entries/returns. The real HTTP replacement race closes successfully.
5. A closed join returned HTTP 500 through PostgREST. Its generic client rejection
   now returns HTTP 400 without identifying a live capacity count.
6. A suspension could miss an admission committed while its profile lock waited.
   The complete challenge/profile union is locked and rechecked; a changed union
   aborts for exact retry, and synchronous safe ticks precede reinstatement.
7. Null/delayed counts could fail native decoding or display a legacy count without
   privacy metadata. Optional models plus an explicit five-member/900-second
   display guard fail closed; actual join/detail renders passed.

Remaining limits are in the completion report. No unresolved correctness finding
from this scoped review is being treated as passed; physical/hosted/operator
staffing acceptance is outside this local implementation.
