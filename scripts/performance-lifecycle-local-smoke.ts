/** Persistent psql transaction is test scaffolding only; it always rolls back.
 * Production adapter uses separate RPC transactions around the pure evaluation.
 * Run: deno run --allow-run=psql --allow-read=scripts/examples scripts/performance-lifecycle-local-smoke.ts
 */
import { evaluatePerformanceCommitment } from "../supabase/functions/_shared/performance_scoring.ts";
import type { PerformanceScoringInput } from "../supabase/functions/_shared/performance_scoring.ts";
import { runPerformanceLifecycle } from "../supabase/functions/performance-lifecycle/worker.ts";
import type {
  CommitStatus,
  PerformanceLifecycleDatabase,
} from "../supabase/functions/performance-lifecycle/worker.ts";

// An optional port selects another disposable stack; the host stays loopback.
const port = Deno.args[0] ?? "54322";
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
  const marker = `END_LIFECYCLE_${++sequence}`;
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
let now = "2026-08-01T18:00:00.000000Z";
const database: PerformanceLifecycleDatabase = {
  load: (id) =>
    value(`app.performance_lifecycle_load_at_v1(${quote(id)},${quote(now)})`),
  commit: (input, decision) =>
    value<CommitStatus>(
      `app.performance_lifecycle_commit_at_v1(${
        quote(JSON.stringify(input))
      }::jsonb,${quote(JSON.stringify(decision))}::jsonb,${quote(now)})`,
    ),
  settle: (id) =>
    value(`app.performance_lifecycle_settle_at_v1(${quote(id)},${quote(now)})`),
};
async function load(id: string): Promise<PerformanceScoringInput> {
  const result = await database.load(id);
  if (!result) throw new Error("missing accepted input");
  return result;
}
async function tick(id: string, t: string, expected: string) {
  now = t;
  check(
    await runPerformanceLifecycle(database, id) === expected,
    `worker ${expected} at ${t}`,
  );
}
try {
  await sql(
    await Deno.readTextFile(
      new URL("./examples/performance-lifecycle-setup.sql", import.meta.url),
    ),
  );
  await value("public.set_commitment_lifecycle_enabled_v1(true)");
  for (
    const [index, kind] of [
      "success",
      "strict_equal",
      "nonfinish",
      "missing",
      "silent",
      "no_attempts",
      "unconfirmed_miss",
    ].entries()
  ) {
    const n = index + 1;
    const id = await value<string>(`pg_temp.prepare(${n})`);
    if (!["silent", "no_attempts"].includes(kind)) {
      await value(
        `pg_temp.proof(${n},0,${
          kind === "success" ? 359 : kind === "nonfinish" ? 0 : 360
        },'2026-06-01T12:00:00.123456Z',${kind === "missing"})`,
      );
    }
    if (!["silent", "unconfirmed_miss"].includes(kind)) {
      await value(`pg_temp.confirm(${n})`);
    }
    await tick(id, "2026-07-04T12:00:00.123455Z", "awaiting_proof");
    const before = await load(id);
    now = "2026-07-04T12:00:00.123456Z";
    check(
      await database.commit(before, evaluatePerformanceCommitment(before)) ===
        "stale",
      "microsecond cutoff crossing forces reload",
    );
    await tick(id, now, "provisional");
    const notice = (await load(id)).notices;
    await tick(id, "2026-07-05T12:00:00.123456Z", "provisional");
    check(
      JSON.stringify((await load(id)).notices) === JSON.stringify(notice),
      "notice retry preserves original timestamp",
    );
    await tick(id, "2026-07-11T12:00:00.123455Z", "provisional");
    await tick(id, "2026-07-11T12:00:00.123456Z", "final");
    const final = (await load(id)).finalResult!;
    const expected = kind === "success"
      ? "success"
      : ["strict_equal", "nonfinish", "no_attempts"].includes(kind)
      ? "miss"
      : "inconclusive";
    check(final.outcome.kind === expected, `${kind}: persisted ${expected}`);
    const s = await value<
      {
        returned_cents: number;
        lost_cents: number;
        payee: null;
        redeemable: boolean;
      }
    >(`app.performance_lifecycle_settle_at_v1(${quote(id)},${quote(now)})`);
    check(
      s.returned_cents + s.lost_cents === 2000 &&
        s.lost_cents === (expected === "miss" ? 2000 : 0) && s.payee === null &&
        !s.redeemable,
      `${kind}: explicit simulation without payee`,
    );
    check(
      await value<number>(
        `(select count(*) from app.performance_commitment_enrollments where commitment_id=${
          quote(id)
        } and released_at is null)`,
      ) === 0,
      "final releases the commitment slot",
    );
    await tick(id, now, "final");
    check(
      await value<string>(
        `pg_temp.attempt(${
          quote(
            `select pg_temp.proof(${n},0,359,'2026-07-12T12:00:00.123456Z')`,
          )
        })`,
      ) === "55000",
      "post-final attempt ingestion refused",
    );
  }
  const corrected = await value<string>("pg_temp.prepare(8)");
  await value("pg_temp.proof(8,0,359)");
  await value("pg_temp.proof(8,1,400)");
  await value("pg_temp.confirm(8)");
  await tick(corrected, "2026-07-04T12:00:00.123456Z", "provisional");
  check(
    evaluatePerformanceCommitment(await load(corrected)).outcome?.kind ===
      "success",
    "slower later attempt does not undo success",
  );
  now = "2026-07-11T12:00:00.123456Z";
  const stale = await load(corrected);
  await value("pg_temp.proof(8,0,360,'2026-07-11T12:00:00.123455Z')");
  check(
    await database.commit(stale, evaluatePerformanceCommitment(stale)) ===
      "stale",
    "full proof correction invalidates final decision",
  );
  await tick(corrected, now, "provisional");
  check(
    (await load(corrected)).notices.length === 2,
    "new correction retains notice history",
  );
  await tick(corrected, "2026-07-18T12:00:00.123455Z", "provisional");
  await tick(corrected, "2026-07-18T12:00:00.123456Z", "final");
  check(
    (await load(corrected)).finalResult?.outcome.kind === "miss",
    "corrected strict-equal attempt gets full new window",
  );
  for (
    const [i, resolution] of ["uphold", "inconclusive", "timeout"].entries()
  ) {
    const n = 9 + i;
    const id = await value<string>(`pg_temp.prepare(${n})`);
    await value(`pg_temp.proof(${n},0,359)`);
    await tick(id, "2026-07-04T12:00:00.123456Z", "provisional");
    const k = await value<string>(
      `pg_temp.file(${n},1,'2026-07-11T12:00:00.123455Z')`,
    );
    await tick(id, "2026-07-11T12:00:00.123456Z", "provisional");
    if (resolution !== "timeout") {
      await value(
        `pg_temp.resolve(${n},${quote(k)},${
          quote(resolution)
        },'2026-07-12T12:00:00.123456Z')`,
      );
    }
    await tick(id, "2026-07-18T12:00:00.123455Z", "final");
    check(
      (await load(id)).finalResult?.outcome.kind ===
        (resolution === "uphold" ? "success" : "inconclusive"),
      `${resolution}: full independent review deadline`,
    );
  }
  const late = await value<string>("pg_temp.prepare(12)");
  await value("pg_temp.proof(12,0,359)");
  await tick(late, "2026-07-04T12:00:00.123456Z", "provisional");
  await value("pg_temp.proof(12,0,360,'2026-07-30T12:00:00.123456Z')");
  await tick(late, "2026-07-30T12:00:00.123456Z", "provisional");
  await tick(late, "2026-07-31T12:00:00.123456Z", "final");
  check(
    (await load(late)).finalResult?.outcome.reason === "finality_timeout",
    "late correction cannot shorten full notice window",
  );
  const noNotice = await value<string>("pg_temp.prepare(13)");
  await value("pg_temp.confirm(13)");
  await tick(noNotice, "2026-07-31T12:00:00.123456Z", "final");
  check(
    (await load(noNotice)).finalResult?.outcome.kind === "inconclusive",
    "miss without durable notice is zero consequence at cap",
  );
  for (const [i, kind] of ["cancel", "withdrawal", "injury"].entries()) {
    const n = 14 + i;
    const id = await value<string>(`pg_temp.prepare(${n})`);
    const at = kind === "cancel"
      ? "2026-05-01T15:00:00.123456Z"
      : "2026-05-03T15:00:00.123456Z";
    await value(`pg_temp.exit(${n},${quote(kind)},${quote(at)})`);
    await tick(id, at, "final");
    check(
      (await load(id)).finalResult?.outcome.reason === kind,
      `${kind}: preserved exit history`,
    );
  }
  const interrupted = await value<string>("pg_temp.prepare(17)");
  await value("pg_temp.confirm(17)");
  await tick(interrupted, "2026-07-04T12:00:00.123456Z", "provisional");
  now = "2026-07-11T12:00:00.123456Z";
  const input = await load(interrupted);
  check(
    await database.commit(input, evaluatePerformanceCommitment(input)) ===
      "final",
    "final can commit before simulation",
  );
  check(
    await value<number>(
      `(select count(*) from app.performance_lifecycle_settlements where commitment_id=${
        quote(interrupted)
      })`,
    ) === 0,
    "interruption leaves no fabricated simulation",
  );
  await tick(interrupted, now, "final");
  check(
    await value<number>(
      `(select lost_cents from app.performance_lifecycle_settlements where commitment_id=${
        quote(interrupted)
      })`,
    ) === 2000,
    "rerun appends exactly one simulated loss",
  );
  const frozen = JSON.stringify((await load(interrupted)).finalResult);
  await value(
    `public.set_commitment_lifecycle_operator_v1(pg_temp.req(900),${
      quote(interrupted)
    },pg_temp.actor(30),'support',clock_timestamp()+interval '1 day')`,
  );
  await sql("select pg_temp.login(30); set local role authenticated;");
  await value(
    `public.read_commitment_lifecycle_operator_v1(${
      quote(interrupted)
    },'support')`,
  );
  await value(
    `public.submit_commitment_support_correction_v1(pg_temp.req(901),${
      quote(interrupted)
    },'missing_result','Fictional correction reported after finality.')`,
  );
  await sql("reset role;");
  now = new Date().toISOString();
  check(
    JSON.stringify((await load(interrupted)).finalResult) === frozen,
    "support correction never rewrites final result",
  );
  await sql("set constraints all immediate; rollback;");
  console.log("Rollback-only persisted performance lifecycle smoke passed.");
} finally {
  try {
    await sql("rollback;");
  } catch { /* Connection may have stopped on SQL error. */ }
  await writer.close();
  await child.status;
}
