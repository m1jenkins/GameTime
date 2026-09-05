/** Persistent psql transaction is test scaffolding only; it always rolls back.
 * Production adapter uses separate RPC transactions around the pure evaluation.
 * Run: deno run --allow-run=psql --allow-read=scripts/examples scripts/duel-lifecycle-local-smoke.ts
 */
import { evaluateDuel } from "../supabase/functions/_shared/duel_scoring.ts";
import type { DuelScoringInput } from "../supabase/functions/_shared/duel_scoring.ts";
import { runDuelLifecycle } from "../supabase/functions/duel-lifecycle/worker.ts";
import type {
  CommitStatus,
  DuelLifecycleDatabase,
} from "../supabase/functions/duel-lifecycle/worker.ts";

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
const database: DuelLifecycleDatabase = {
  load: (id) =>
    value(`app.duel_lifecycle_load_at_v1(${quote(id)},${quote(now)})`),
  commit: (input, decision) =>
    value<CommitStatus>(
      `app.duel_lifecycle_commit_at_v1(${quote(JSON.stringify(input))}::jsonb,${
        quote(JSON.stringify(decision))
      }::jsonb,${quote(now)})`,
    ),
  settle: (id) =>
    value(`app.duel_lifecycle_settle_at_v1(${quote(id)},${quote(now)})`),
};
async function load(id: string): Promise<DuelScoringInput> {
  const result = await database.load(id);
  if (!result) throw new Error("missing accepted input");
  return result;
}
async function tick(id: string, t: string, expected: string) {
  now = t;
  check(
    await runDuelLifecycle(database, id) === expected,
    `worker ${expected} at ${t}`,
  );
}
try {
  await sql(
    await Deno.readTextFile(
      new URL("./examples/duel-lifecycle-setup.sql", import.meta.url),
    ),
  );
  // Full persisted fixture matrix, with the unchanged evaluator as the decision source.
  for (
    const [index, kind] of [
      "winner",
      "tie",
      "only_finisher",
      "both_nonfinish",
      "missing",
      "wrong_bib",
    ].entries()
  ) {
    const n = index + 1;
    const id = await value<string>(`pg_temp.prepare(${n})`);
    await value(`pg_temp.proof(${n},0,${quote(kind)},'2026-08-01 18:00Z')`);
    const firstNotice = ["missing", "wrong_bib"].includes(kind)
      ? "2026-08-04T17:00:00Z"
      : "2026-08-01T19:00:00Z";
    await tick(id, firstNotice, "provisional");
    const sample = await load(id);
    check(
      sample.notices.length === 2,
      `${kind}: durable notices for both actors`,
    );
    const deadline = evaluateDuel(sample).disputeClosesAt!;
    const finalAt = new Date(Date.parse(deadline)).toISOString();
    await tick(id, finalAt, "final");
    const final = (await load(id)).finalResult!;
    check(
      final.outcome.kind ===
        (kind === "winner" || kind === "only_finisher"
          ? "winner"
          : kind === "tie"
          ? "tie"
          : "void"),
      `${kind}: persisted outcome`,
    );
    await tick(id, finalAt, "final");
    const settlement = await value<
      { creator_cents: number; invitee_cents: number; redeemable: boolean }
    >(`app.duel_lifecycle_settle_at_v1(${quote(id)},${quote(now)})`);
    check(
      settlement.creator_cents + settlement.invitee_cents === 4000 &&
        !settlement.redeemable,
      `${kind}: conserved nonredeemable simulation`,
    );
    check(
      await value<number>(
        `(select count(*) from app.duel_enrollments where challenge_id=${
          quote(id)
        } and released_at is null)`,
      ) === 0,
      `${kind}: final releases slots`,
    );
    check(
      await value<string>(
        `pg_temp.attempt(${
          quote(`select pg_temp.proof(${n},1,'corrected','2026-08-12 18:00Z')`)
        })`,
      ) === "55000",
      `${kind}: post-final proof refused`,
    );
  }
  const corrected = await value<string>("pg_temp.prepare(7)");
  await value("pg_temp.proof(7,0,'winner','2026-08-01 18:00Z')");
  await tick(corrected, "2026-08-01T19:00:00Z", "provisional");
  now = "2026-08-08T19:00:00Z";
  const stale = await load(corrected);
  await value("pg_temp.proof(7,1,'corrected','2026-08-08 18:59:59.999999Z')");
  check(
    await database.commit(stale, evaluateDuel(stale)) === "stale",
    "correction invalidates a ready-to-finalize snapshot",
  );
  await tick(corrected, now, "provisional");
  check(
    (await load(corrected)).notices.length === 4,
    "correction creates a fresh notice pair",
  );
  await tick(corrected, "2026-08-15T18:59:59.999999Z", "provisional");
  await tick(corrected, "2026-08-15T19:00:00Z", "final");
  check(
    (await load(corrected)).finalResult?.outcome.kind === "winner",
    "corrected result waits seven full elapsed days",
  );

  for (const [offset, resolution] of ["uphold", "void", "timeout"].entries()) {
    const n = 8 + offset;
    const id = await value<string>(`pg_temp.prepare(${n})`);
    await value(`pg_temp.proof(${n},0,'winner','2026-08-01 18:00Z')`);
    await tick(id, "2026-08-01T19:00:00Z", "provisional");
    const k = await value<string>(`pg_temp.file(${n},1,'2026-08-08 18:00Z')`);
    await tick(id, "2026-08-08T19:00:00Z", "provisional");
    if (resolution !== "timeout") {
      await value(
        `pg_temp.resolve(${n},${quote(k)},${
          quote(resolution)
        },'2026-08-09 18:00Z')`,
      );
    }
    await tick(id, "2026-08-15T18:00:00Z", "final");
    check(
      (await load(id)).finalResult?.outcome.kind ===
        (resolution === "uphold" ? "winner" : "void"),
      `${resolution}: review controls finality`,
    );
  }
  const late = await value<string>("pg_temp.prepare(11)");
  await value("pg_temp.proof(11,0,'winner','2026-08-01 18:00Z')");
  await tick(late, "2026-08-01T19:00:00Z", "provisional");
  await value("pg_temp.proof(11,1,'corrected','2026-08-30 18:00Z')");
  await tick(late, "2026-08-30T19:00:00Z", "provisional");
  await tick(late, "2026-08-31T17:00:00Z", "final");
  check(
    (await load(late)).finalResult?.outcome.reason === "finality_timeout",
    "hard cap never shortens the correction window",
  );
  for (
    const [offset, kind] of ["withdrawal", "injury", "event_cancelled"]
      .entries()
  ) {
    const n = 12 + offset;
    const id = await value<string>(`pg_temp.prepare(${n})`);
    await value(`pg_temp.exit(${n},${quote(kind)},'2026-08-01 16:00Z')`);
    await tick(id, "2026-08-01T16:00:00Z", "final");
    check(
      (await load(id)).finalResult?.outcome.kind ===
        (kind === "withdrawal" ? "withdrawn_no_contest" : "void"),
      `${kind}: zero-consequence exit`,
    );
  }
  const expired = await value<string>("pg_temp.prepare(15,false)");
  await tick(expired, "2026-08-01T14:00:00Z", "inactive");
  check(
    await value<string>(
      `(select status from public.duel_challenges where id=${quote(expired)})`,
    ) === "expired",
    "unaccepted invitation expires at cutoff",
  );

  const supportRequest = await value<string>("extensions.gen_random_uuid()");
  const beforeSupport = await load(corrected);
  const supportId = await value<string>(
    `pg_temp.support(7,${quote(supportRequest)})`,
  );
  check(
    await value<string>(`pg_temp.support(7,${quote(supportRequest)})`) ===
      supportId,
    "support correction exact retry",
  );
  check(
    JSON.stringify((await load(corrected)).finalResult) ===
      JSON.stringify(beforeSupport.finalResult),
    "support correction preserves immutable final result",
  );
  check(
    await value<number>(
      `(select count(*) from app.duel_proof_revisions where challenge_id=${
        quote(corrected)
      })`,
    ) === 2,
    "support intake never appends scoring proof",
  );
  const projection = await value<Record<string, unknown>>(
    "pg_temp.read_result(7)",
  );
  check(
    !JSON.stringify(projection).includes("fictional-bib") &&
      !JSON.stringify(projection).includes("reviewerId"),
    "participant result omits private proof and reviewer",
  );
  await value("pg_temp.block_pair(7)");
  const suppressed = await value<
    { contactSuppressed: boolean; notices: unknown[]; finalResult: unknown }
  >("pg_temp.read_result(7)");
  check(
    suppressed.contactSuppressed && suppressed.notices.length === 0 &&
      suppressed.finalResult === null,
    "blocking suppresses opponent result access",
  );
  const deleted = await value<string>(
    "pg_temp.prepare(16,true,clock_timestamp()-interval '1 day')",
  );
  now = await value<string>("clock_timestamp()");
  const beforeDeletion = await load(deleted);
  await sql(
    "do $$begin perform public.delete_account((select a from lifecycle_pairs where n=16)); end$$;",
  );
  now = await value<string>("clock_timestamp()");
  check(
    await database.commit(beforeDeletion, evaluateDuel(beforeDeletion)) ===
      "stale",
    "account deletion invalidates full snapshot",
  );
  await tick(deleted, now, "final");
  check(
    (await load(deleted)).finalResult?.outcome.reason === "account_deleted",
    "poststart deletion finalizes without consequence",
  );
  check(
    await value<string>(
      `pg_temp.attempt(${quote("select pg_temp.read_result(16)")})`,
    ) === "42501",
    "deleted participant loses result access",
  );
  const beforeCap = await value<string>("pg_temp.prepare(17)");
  now = "2026-08-04T16:59:59.999999Z";
  const oldClock = await load(beforeCap);
  now = "2026-08-04T17:00:00Z";
  check(
    await database.commit(oldClock, evaluateDuel(oldClock)) === "stale",
    "clock crossing cutoff forces reevaluation",
  );
  await tick(beforeCap, "2026-08-31T17:00:00Z", "final");
  check(
    (await load(beforeCap)).finalResult?.outcome.reason === "finality_timeout",
    "absent notices at cap voids without a shortened window",
  );

  const interrupted = await value<string>("pg_temp.prepare(18)");
  now = "2026-08-31T17:00:00Z";
  let failedAfterFinal = false;
  try {
    await runDuelLifecycle({
      ...database,
      settle: () => {
        throw new Error("fixture interruption");
      },
    }, interrupted);
  } catch {
    failedAfterFinal = true;
  }
  check(
    failedAfterFinal && (await load(interrupted)).finalResult !== null,
    "result commits before interrupted settlement",
  );
  check(
    await value<number>(
      `(select count(*) from app.duel_lifecycle_settlements where challenge_id=${
        quote(interrupted)
      })`,
    ) === 0,
    "settlement is a separate append",
  );
  await tick(interrupted, now, "final");
  check(
    await value<string>(
      `pg_temp.attempt(${
        quote(
          "update app.duel_lifecycle_results set result='{}' where challenge_id='" +
            interrupted + "'",
        )
      })`,
    ) === "23001",
    "persisted final result cannot be edited",
  );
  check(
    await value<string>(
      `pg_temp.attempt(${
        quote(
          "update app.duel_lifecycle_settlements set creator_cents=0 where challenge_id='" +
            interrupted + "'",
        )
      })`,
    ) === "23001",
    "simulated settlement cannot be edited",
  );
  await sql("set constraints all immediate;");
  console.log("All lifecycle fixtures and gate changes rolled back.");
} finally {
  try {
    await sql("rollback;");
  } catch { /* psql failure already rolled back */ }
  try {
    await writer.close();
  } catch { /* preserve the original failure */ }
  await child.status;
}
