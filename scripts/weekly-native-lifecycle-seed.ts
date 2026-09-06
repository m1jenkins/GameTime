/** Creates historical fictional receipts for real native HTTP decoding.
 * Uses two existing loopback actors, temporary fixture Auth sessions, and the
 * actual policy/lifecycle evaluator. Restores gates, revokes fixture sessions.
 * CLI: deno run --allow-run=psql scripts/weekly-native-lifecycle-seed.ts <actor1> <actor2>
 */
import {
  runWeeklyLifecycle,
  type WeeklyLifecycleDatabase,
} from "../supabase/functions/_shared/weekly-lifecycle.ts";
const actors = Deno.args;
if (
  actors.length !== 2 || actors[0] === actors[1] ||
  actors.some((id) => !/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(id))
) throw new Error("Two distinct local fixture actor UUIDs required");
const child = new Deno.Command("psql", {
  args: [
    `postgresql://postgres:postgres@127.0.0.1:56322/postgres`,
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

let now = "";
const database: WeeklyLifecycleDatabase = {
  load: (id) => value(`app.weekly_load_at_v1(${quote(id)},${quote(now)})`),
  commit: (input, decision) =>
    value(
      `app.weekly_commit_at_v1(${quote(JSON.stringify(input))},${quote(JSON.stringify(decision))},${
        quote(now)
      })`,
    ),
  settle: (id) => value(`public.settle_weekly_simulation_v1(${quote(id)})`),
};
const sessions = actors.map(() => crypto.randomUUID());
async function login(index: number) {
  await sql(
    `select set_config('request.jwt.claim.sub',${
      quote(actors[index]!)
    },true); select set_config('request.jwt.claims',${
      quote(JSON.stringify({ sub: actors[index], session_id: sessions[index] }))
    },true); set local role authenticated;`,
  );
}
function after(base: string, hours: number, micro = false) {
  const t = new Date(Date.parse(base) + hours * 3600000).toISOString();
  return micro ? t.replace(".000Z", ".000001Z") : t;
}
const output: Record<string, string | number> = {};
try {
  await sql("begin;");
  await sql(
    "create temp table prior_runtime as select * from app.weekly_runtime;",
  );
  for (let i = 0; i < actors.length; i++) {
    await sql(
      `insert into auth.sessions(id,user_id) values(${quote(sessions[i]!)},${quote(actors[i]!)});`,
    );
  }
  await sql(
    `select public.set_weekly_runtime_v1(true,true,true,(select array(select distinct unnest(actor_ids||array[${
      actors.map(quote).join(",")
    }]::uuid[])) from prior_runtime));`,
  );
  await sql(
    `create function pg_temp.create_week(r uuid,t jsonb,n timestamptz) returns uuid language sql security definer set search_path='' as $f$select app.weekly_create_at_v1(r,t,encode(extensions.digest(t::text,'sha256'),'hex'),true,n)$f$;
 create function pg_temp.join_week(r uuid,c uuid,n timestamptz) returns uuid language sql security definer set search_path='' as $f$select app.weekly_join_at_v1(r,c,(select terms_digest from app.weekly_agreements where id=c),true,'friend',n)$f$;
 create function pg_temp.review_week(r uuid,c uuid,n timestamptz) returns uuid language sql security definer set search_path='' as $f$select app.weekly_file_at_v1(r,c,1,'wrong_total',n)$f$;`,
  );
  for (const [index, name] of ["noticeID", "reviewID", "finalID"].entries()) {
    const week = await value<string>(
      `(date_trunc('week',clock_timestamp() at time zone 'America/Chicago')-interval '${
        28 + index * 7
      } days')::date`,
    );
    const created = week + "T00:00:00Z";
    const createdAt = after(created, -7 * 24);
    const terms = await value<{ endsAt: string; days: { date: string }[] }>(
      `app.weekly_terms_v1(${
        quote(
          JSON.stringify(
            actors.map((actor_id) => ({ actor_id, target_steps: 70000 })),
          ),
        )
      },${quote(week)},'America/Chicago',${quote(actors[0]!)},${quote(createdAt)})`,
    );
    await login(0);
    const id = await value<string>(
      `pg_temp.create_week(${quote(crypto.randomUUID())},${quote(JSON.stringify(terms))},${
        quote(createdAt)
      })`,
    );
    await sql("reset role;");
    await login(1);
    await value(
      `pg_temp.join_week(${quote(crypto.randomUUID())},${quote(id)},${quote(after(createdAt, 1))})`,
    );
    await sql("reset role;");
    for (const actor of actors) {
      for (const day of terms.days) {
        await value(
          `app.weekly_fixture_at_v1(${quote(crypto.randomUUID())},${quote(id)},${quote(actor)},${
            quote(day.date)
          },'complete',10000,${quote(after(terms.endsAt, 23))})`,
        );
      }
    }
    now = after(terms.endsAt, 24, true);
    if (await runWeeklyLifecycle(database, id) !== "notice") {
      throw new Error("weekly_seed_notice_failed");
    }
    if (name === "reviewID") {
      const request = crypto.randomUUID();
      await login(0);
      await value(
        `pg_temp.review_week(${quote(request)},${quote(id)},${quote(after(terms.endsAt, 25))})`,
      );
      await sql("reset role;");
      output.reviewRequestID = request;
      output.reviewNoticeRevision = 1;
    }
    now = after(terms.endsAt, 145);
    if (await runWeeklyLifecycle(database, id) !== "final") {
      throw new Error("weekly_seed_final_failed");
    }
    output[name] = id;
  }
  await sql(
    `select public.set_weekly_runtime_v1(enabled,fixture_enabled,worker_enabled,actor_ids) from prior_runtime; delete from auth.sessions where id in (${
      sessions.map(quote).join(",")
    }); commit;`,
  );
  console.log(JSON.stringify(output));
} finally {
  try {
    await writer.write(new TextEncoder().encode("rollback;\n\\q\n"));
  } catch { /* preserve originating failure */ }
  await writer.close();
  await child.status;
  const stderr = await errors;
  if (stderr.trim() && !stderr.includes("there is no transaction")) {
    console.error(stderr.trim());
  }
}
