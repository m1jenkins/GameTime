/** Rollback-only persisted weekly fixtures -> real evaluator -> optimistic worker.
 * deno run --allow-run=psql --allow-read=scripts/examples scripts/weekly-lifecycle-local-smoke.ts 56322
 */
import {
  evaluateWeeklyLifecycle,
  runWeeklyLifecycle,
  type WeeklyLifecycleDatabase,
  type WeeklyLifecycleInput,
} from "../supabase/functions/_shared/weekly-lifecycle.ts";
// An optional port selects another disposable stack; the host stays loopback.
const port = Deno.args[0] ?? "56322";
if (
  Deno.args.length > 1 || !/^[1-9][0-9]{0,4}$/.test(port) ||
  Number(port) > 65535
) {
  throw new Error("Expected one local PostgreSQL port (1–65535)");
}
const child = new Deno.Command("psql", {
  args: [
    `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`,
    "-X",
    "-qAt",
    "-v",
    "ON_ERROR_STOP=1",
  ],
  stdin: "piped",
  stdout: "piped",
  stderr: "piped",
}).spawn();
const writer = child.stdin.getWriter();
const reader = child.stdout.pipeThrough(new TextDecoderStream()).getReader();
const errors = new Response(child.stderr).text();
let buffer = "";
let sequence = 0;
const quote = (s: string) => "'" + s.replaceAll("'", "''") + "'";
async function sql(statement: string): Promise<string> {
  const marker = `END_WEEKLY_${++sequence}`;
  await writer.write(
    new TextEncoder().encode(`${statement}\n\\echo ${marker}\n`),
  );
  while (!buffer.includes(marker + "\n")) {
    const chunk = await reader.read();
    if (chunk.done) throw new Error(await errors);
    buffer += chunk.value;
  }
  const index = buffer.indexOf(marker + "\n");
  const output = buffer.slice(0, index).trim();
  buffer = buffer.slice(index + marker.length + 1);
  return output;
}
async function value<T>(expression: string): Promise<T> {
  return JSON.parse(
    await sql(`select coalesce(to_jsonb(${expression}),'null'::jsonb);`),
  ) as T;
}
function check(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
  console.log(`PASS: ${message}`);
}

let now = "2026-09-15T05:00:00.000001Z";
const database: WeeklyLifecycleDatabase = {
  load: (id) => value(`app.weekly_load_at_v1(${quote(id)},${quote(now)})`),
  commit: (input, decision) =>
    value(
      `app.weekly_commit_at_v1(${quote(JSON.stringify(input))}::jsonb,${
        quote(JSON.stringify(decision))
      }::jsonb,${quote(now)})`,
    ),
  settle: (id) => value(`public.settle_weekly_simulation_v1(${quote(id)})`),
};
async function load(id: string): Promise<WeeklyLifecycleInput> {
  const v = await database.load(id);
  if (!v) throw new Error("missing input");
  return v;
}
async function tick(id: string, t: string, expected: string) {
  now = t;
  check(await runWeeklyLifecycle(database, id) === expected, `${id}: ${expected} at ${t}`);
}
try {
  await sql("begin;");
  await sql(await Deno.readTextFile(new URL("./examples/weekly-fixture.sql", import.meta.url)));
  const pair = await value<string>("pg_temp.make_friend(1,2)");
  await value(`pg_temp.capture(${quote(pair)},10000)`);
  await tick(pair, "2026-09-15T05:00:00.000001Z", "notice");
  let snapshot = await load(pair);
  check(
    snapshot.notices.length === 1,
    "persisted W1A snapshot produced one durable complete-roster notice",
  );
  check(
    snapshot.notices[0]?.qualifications.every((q) => q.qualification === "met"),
    "all met fixture from actual W1A evaluator",
  );
  now = "2026-09-16T04:59:59.999999Z";
  const stale = await load(pair);
  await value(
    `app.weekly_fixture_at_v1(pg_temp.req(1000),${
      quote(pair)
    },pg_temp.actor(1),'2026-09-07','complete',0,${quote(now)})`,
  );
  check(
    await database.commit(stale, evaluateWeeklyLifecycle(stale)) === "stale",
    "downward correction invalidates stale worker input",
  );
  await tick(pair, now, "notice");
  snapshot = await load(pair);
  check(
    snapshot.notices.length === 2,
    "downward correction produces a NEW full filing/resolution window",
  );
  check(
    snapshot.notices[1]?.qualifications[0]?.qualification === "confirmed_miss",
    "last eligible microsecond downward correction reaches scorer",
  );
  await sql(
    `select pg_temp.login(1); select pg_temp.file(pg_temp.req(1001),${
      quote(pair)
    },2,'wrong_total','2026-09-17T04:00:00Z'); reset role;`,
  );
  await tick(pair, "2026-09-18T04:59:59.999999Z", "review");
  await tick(pair, "2026-09-21T04:59:59.999998Z", "review");
  await tick(pair, "2026-09-21T04:59:59.999999Z", "final");
  snapshot = await load(pair);
  check(
    snapshot.result?.qualifications.every((q) => q.qualification === "refund"),
    "unresolved review refunds entire friend group",
  );
  const allocation = await value<
    {
      total_entry_cents: number;
      unallocated_cents: number;
      allocations: { returnedCents: number; bonusCents: number }[];
    }
  >(`public.settle_weekly_simulation_v1(${quote(pair)})`);
  check(
    allocation.total_entry_cents === 4000 && allocation.unallocated_cents === 0 &&
      allocation.allocations.every((a) => a.returnedCents === 2000 && a.bonusCents === 0),
    "safe conservative group refund conserves simulation",
  );
  await tick(pair, now, "final");
  check(
    await value<number>(
      `(select count(*) from app.weekly_allocations where challenge_id=${quote(pair)})`,
    ) === 1,
    "final replay never allocates twice",
  );
  // Every 2–5 group size is scored through persisted fixtures, including all miss.
  for (const [first, count, steps] of [[3, 3, 0], [6, 4, 10000], [10, 5, 0]] as const) {
    const id = await value<string>(`pg_temp.make_friend(${first},${count})`);
    await value(`pg_temp.capture(${quote(id)},${steps})`);
    await tick(id, "2026-09-16T05:00:00.000001Z", "notice");
    await tick(id, "2026-09-18T05:00:00.000001Z", "final");
    const a = await value<{ total_entry_cents: number; unallocated_cents: number }>(
      `public.settle_weekly_simulation_v1(${quote(id)})`,
    );
    check(
      a.total_entry_cents === count * 2000 &&
        a.unallocated_cents === (steps === 0 ? count * 2000 : 0),
      `${count}-person ${steps === 0 ? "none" : "all"} met conservation`,
    );
  }
  // Five-entry community: three qualifiers, one confirmed miss, one unknown.
  const community = await value<string>(
    "app.weekly_curate_at_v1(pg_temp.req(2000),'2026-09-07','America/Chicago',70000,30,'2026-08-31T10:00:00Z')",
  );
  for (let actor = 20; actor < 25; actor++) {
    await sql(
      `select pg_temp.login(${actor}); select pg_temp.accept(pg_temp.req(${2100 + actor}),${
        quote(community)
      }); reset role;`,
    );
  }
  for (let actor = 20; actor < 24; actor++) {
    for (let day = 7; day < 14; day++) {
      await value(
        `app.weekly_fixture_at_v1(extensions.gen_random_uuid(),${
          quote(community)
        },pg_temp.actor(${actor}),'2026-09-${day.toString().padStart(2, "0")}','complete',${
          actor === 23 ? 0 : 10000
        },'2026-09-15T04:00:00Z')`,
      );
    }
  }
  await tick(community, "2026-09-16T05:00:00.000001Z", "notice");
  await tick(community, "2026-09-18T05:00:00.000001Z", "final");
  const ca = await value<
    {
      total_entry_cents: number;
      unallocated_cents: number;
      allocations: { participantId: string; returnedCents: number; bonusCents: number }[];
    }
  >(`public.settle_weekly_simulation_v1(${quote(community)})`);
  check(
    ca.total_entry_cents === 10000 && ca.unallocated_cents === 2 &&
      ca.allocations.filter((a) => a.bonusCents === 666).length === 3,
    "community common-target some-met allocation leaves integer remainder unallocated",
  );
  check(
    ca.allocations.find((a) => a.participantId.endsWith("24"))?.returnedCents === 2000,
    "missing community data individually refunded",
  );
  // Zero / one entrants close without dividing by zero or fabricating loss.
  for (const entrants of [0, 1]) {
    const id = await value<string>(
      `app.weekly_curate_at_v1(pg_temp.req(${
        3000 + entrants
      }),'2026-09-14','America/Chicago',70000,30,'2026-08-31T10:00:00Z')`,
    );
    if (entrants) {
      await sql(
        `select pg_temp.login(30); select pg_temp.accept(pg_temp.req(3100),${
          quote(id)
        }); reset role;`,
      );
    }
    await tick(id, "2026-09-14T04:00:00Z", "final");
    const a = await value<{ total_entry_cents: number; unallocated_cents: number }>(
      `public.settle_weekly_simulation_v1(${quote(id)})`,
    );
    check(
      a.total_entry_cents === entrants * 2000 && a.unallocated_cents === 0,
      `${entrants} entrant minimum refund/no divide by zero`,
    );
  }
  const late = await value<string>("pg_temp.make_friend(31,2)");
  await tick(late, "2026-09-17T05:00:00.000001Z", "final");
  check(
    (await load(late)).result?.reason === "notice_window_unavailable",
    "delayed worker safely refunds instead of truncating notice windows",
  );
  // Regression: a service tick before the final explicit consent must not
  // change an invitation into a native-unacceptable state (two and five people).
  await sql(
    `create function pg_temp.try_accept(r uuid,c uuid,n timestamptz) returns text language plpgsql as $f$
    begin perform pg_temp.accept(r,c,n); return 'accepted'; exception when others then return sqlstate; end; $f$;`,
  );
  for (const [first, count] of [[33, 2], [35, 5]] as const) {
    await sql(`select pg_temp.login(${first});`);
    const id = await value<string>(
      `pg_temp.create_friend(extensions.gen_random_uuid(),pg_temp.terms(${first},${count}))`,
    );
    await sql("reset role;");
    await tick(id, "2026-09-01T05:00:00Z", "scheduled");
    const pending = await load(id);
    check(
      pending.status === "invited" && pending.consents.length === 1,
      `${count}-person early worker preserves named invitation and only creator consent`,
    );
    for (let actor = first + 1; actor < first + count; actor++) {
      await sql(`select pg_temp.login(${actor});`);
      check(
        await value<string>(
          `pg_temp.try_accept(extensions.gen_random_uuid(),${quote(id)},'2026-09-07T04:00:00Z')`,
        ) === "55000",
        `${count}-person invitation cutoff equality is closed`,
      );
      await value(
        `pg_temp.accept(extensions.gen_random_uuid(),${quote(id)},'2026-09-01T06:00:00Z')`,
      );
      await sql("reset role;");
    }
    check(
      (await load(id)).consents.length === count,
      `${count}-person remaining explicit consents work after early service tick`,
    );
  }
  // Save representative native JSON to stdout only: native can regenerate safely.
  await sql(`select pg_temp.login(1);`);
  const view = await value<Record<string, unknown>>(`public.get_weekly_v1(${quote(pair)})`);
  check(
    view.result !== null && view.allocation !== null,
    "own native projection separates final and recorded simulation",
  );
  await sql("reset role; rollback;");
  console.log("All persisted weekly lifecycle checks passed; rollback completed.");
} finally {
  try {
    await writer.write(new TextEncoder().encode("rollback;\n\\q\n"));
  } catch { /* psql may already have stopped on an assertion */ }
  await writer.close();
  await child.status;
  const stderr = await errors;
  if (stderr.trim()) console.error(stderr.trim());
}
