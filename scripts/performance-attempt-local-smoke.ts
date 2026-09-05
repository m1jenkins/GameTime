/** Rollback-only fictional DB -> pure evaluator integration; loopback only.
 * deno run --allow-run=psql --allow-read=scripts/examples scripts/performance-attempt-local-smoke.ts
 */
import {
  evaluatePerformanceCommitment,
  type PerformanceScoringInput,
} from "../supabase/functions/_shared/performance_scoring.ts";

// An optional port selects another disposable stack; the host stays loopback.
const port = Deno.args[0] ?? "54322";
if (
  Deno.args.length > 1 || !/^[1-9][0-9]{0,4}$/.test(port) ||
  Number(port) > 65535
) {
  throw new Error("Expected one local PostgreSQL port (1–65535)");
}
const fixture = await Deno.readTextFile(
  "scripts/examples/performance-attempt-fixture.sql",
);
const sql = `\\set ON_ERROR_STOP on
\\o /dev/null
begin;
set local timezone='UTC';
${fixture}
select public.set_commitment_attempts_enabled_v1(true);
set local role authenticated;
insert into pa_saved values('first',pg_temp.pa_nominate(11,101));
insert into pa_saved values('second',pg_temp.pa_nominate(12,102));
reset role;
select public.set_commitment_attempt_reviewer_v1(pg_temp.pa_req(201),pg_temp.pa_id('main'),pg_temp.pa_actor(2),true);
select pg_temp.pa_capture(301,'first',101,359,doc=>pg_temp.pa_document(101)||
 '{"started_at":"2026-07-03T07:00:00.123456-05:00","finished_at":"2026-07-03T07:05:59.123456-05:00"}');
select pg_temp.pa_capture(302,'second',102,400);
select pg_temp.pa_login(2);
set local role authenticated;
select public.get_commitment_attempt_source_v1(pg_temp.pa_id('main'),pg_temp.pa_req(301));
select public.get_commitment_attempt_source_v1(pg_temp.pa_id('main'),pg_temp.pa_req(302));
select pg_temp.pa_review(401,301);
select pg_temp.pa_review(402,302);
reset role;
\\o
select 'SNAPSHOT='||public.get_commitment_attempt_snapshot_v1(pg_temp.pa_id('main'))::text;
\\o /dev/null
create temp table pa_ids as select array_agg(id order by id) ids from app.performance_attempt_nominations where commitment_id=pg_temp.pa_id('main');
grant select on pa_ids to authenticated;
select pg_temp.pa_login(1);
set local role authenticated;
select pg_temp.pa_confirm(501,(select ids from pa_ids));
reset role;
select pg_temp.pa_capture(303,'first',101,360,'2026-09-04T12:00:00.123456Z');
select pg_temp.pa_login(2);
set local role authenticated;
select public.get_commitment_attempt_source_v1(pg_temp.pa_id('main'),pg_temp.pa_req(303));
select pg_temp.pa_review(403,303,1,'2026-09-04T13:00:00.123456Z');
reset role;
\\o
select 'SNAPSHOT='||public.get_commitment_attempt_snapshot_v1(pg_temp.pa_id('main'))::text;
\\o /dev/null
select pg_temp.pa_capture(304,'second',102,400,'2026-09-05T12:00:00.123456Z',
 pg_temp.pa_document(102)||'{"status":"ambiguous","chip_seconds":null,"started_at":null,"finished_at":null}');
set local role authenticated;
select public.get_commitment_attempt_source_v1(pg_temp.pa_id('main'),pg_temp.pa_req(304));
select pg_temp.pa_review(404,304,2,'2026-09-05T13:00:00.123456Z');
reset role;
\\o
select 'SNAPSHOT='||public.get_commitment_attempt_snapshot_v1(pg_temp.pa_id('main'))::text;
\\o /dev/null
set constraints all immediate;
rollback;
`;
const process = new Deno.Command("psql", {
  args: [
    `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`,
    "-X",
    "-q",
    "-A",
    "-t",
  ],
  stdin: "piped",
  stdout: "piped",
  stderr: "piped",
}).spawn();
const writer = process.stdin.getWriter();
await writer.write(new TextEncoder().encode(sql));
await writer.close();
const output = await process.output();
if (!output.success) throw new Error(new TextDecoder().decode(output.stderr));
const snapshots = new TextDecoder().decode(output.stdout).split("\n")
  .filter((line) => line.startsWith("SNAPSHOT=")).map((line) =>
    JSON.parse(line.slice(9))
  );
if (snapshots.length !== 3) {
  throw new Error("Expected three persisted snapshots");
}
const expected = ["success", "miss", "inconclusive"];
const times = [
  "2026-09-03T12:00:00.123456Z",
  "2026-09-04T13:00:00.123456Z",
  "2026-09-05T13:00:00.123456Z",
];
for (const [i, snapshot] of snapshots.entries()) {
  const input: PerformanceScoringInput = {
    ...snapshot,
    now: times[i],
    notices: [],
    reviews: [],
    finalResult: null,
  };
  const decision = evaluatePerformanceCommitment(input);
  if (
    decision.outcome?.kind !== expected[i] || decision.phase !== "provisional"
  ) {
    throw new Error(
      `Unexpected persisted decision: ${JSON.stringify(decision)}`,
    );
  }
  // Later lifecycle records are synthetic, not claimed as persisted notices.
  input.notices = [{
    proofRevision: decision.proofRevision,
    actorId: input.agreement.actor_id,
    recordedAt: input.now,
  }];
  input.now = new Date(Date.parse(input.now) + 7 * 86400000).toISOString()
    .replace(".123Z", ".123456Z");
  if (evaluatePerformanceCommitment(input).phase !== "ready_to_finalize") {
    throw new Error("Full review window did not elapse");
  }
  console.log(
    `Persisted snapshot ${i + 1}: ${
      expected[i]
    }; full injected review window passed`,
  );
}
console.log(
  "Rollback-only local attempt smoke passed; no result, settlement or fixture state persisted.",
);
