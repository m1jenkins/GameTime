/** Rollback-only fictional progress -> unchanged pure scorer; loopback only.
 * deno run --allow-run=psql --allow-read=scripts/examples scripts/performance-progress-local-smoke.ts
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
  "scripts/examples/performance-progress-fixture.sql",
);
const sql = `\\set ON_ERROR_STOP on
\\o /dev/null
begin;
set local timezone='UTC';
${fixture}
select public.set_commitment_attempts_enabled_v1(true);
select public.set_commitment_progress_enabled_v1(true);
\\o
select 'SNAPSHOT='||public.get_commitment_attempt_snapshot_v1(pg_temp.pp_id('main'))::text;
\\o /dev/null
set local role authenticated;
insert into pp_saved values('created',pg_temp.pp_milestone(20));
insert into pp_saved values('milestone',jsonb_build_array((select value->>'milestone_id' from pp_saved where name='created')));
select pg_temp.pp_note(21,'Ran 5K in 5:59',pg_temp.pp_id('milestone'));
select pg_temp.pp_status(22,'completed',1);
\\o
select 'PROGRESS='||public.get_commitment_progress_v1(pg_temp.pp_id('main'))::text;
\\o /dev/null
reset role;
\\o
select 'SNAPSHOT='||public.get_commitment_attempt_snapshot_v1(pg_temp.pp_id('main'))::text;
\\o /dev/null
select public.set_commitment_progress_enabled_v1(false);
set local role authenticated;
-- Exercise public recovery with precisely the original saved input.
\\o
select 'RECOVERY='||public.create_commitment_milestone_v1(pg_temp.pp_req(20),pg_temp.pp_id('main'),'Choose an event','2026-07-10T12:00:00.123456Z')::text;
\\o /dev/null
reset role;
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
const lines = new TextDecoder().decode(output.stdout).split("\n");
const values = (prefix: string) =>
  lines.filter((line) => line.startsWith(prefix))
    .map((line) => JSON.parse(line.slice(prefix.length)));
const snapshots = values("SNAPSHOT=");
const progress = values("PROGRESS=");
const recovery = values("RECOVERY=");
if (snapshots.length !== 2 || progress.length !== 1 || recovery.length !== 1) {
  throw new Error("Missing persisted smoke observations");
}
const decisions = snapshots.map((snapshot) => {
  const input: PerformanceScoringInput = {
    ...snapshot,
    now: "2026-09-03T12:00:00.123456Z",
    notices: [],
    reviews: [],
    finalResult: null,
  };
  return evaluatePerformanceCommitment(input);
});
if (
  JSON.stringify(decisions[0]) !== JSON.stringify(decisions[1]) ||
  decisions[1].outcome?.kind !== "inconclusive" ||
  decisions[1].phase !== "provisional"
) throw new Error("Manual progress changed proof authority");
if (
  progress[0].entries.length !== 3 ||
  progress[0].milestones[0].status !== "completed" ||
  progress[0].counts_as_proof !== false ||
  JSON.stringify(recovery[0]) !== JSON.stringify(progress[0].entries[0])
) throw new Error("Progress history or exact gate-off recovery mismatch");
console.log(
  "Persisted 60-day goal: milestone, manual time claim and completion retained as owner reports.",
);
console.log(
  "Scorer unchanged: missing organizer proof remains unresolved; no published result or consequence.",
);
console.log(
  "Public exact retry with gate off passed. Local fixtures and gate changes rolled back.",
);
