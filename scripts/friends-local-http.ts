/** Friends TestFlight Phase 4: HTTP verification on a disposable local stack.
 *
 * Usage: deno run --config supabase/functions/deno.json -A \
 *   scripts/friends-local-http.ts <disposable stack directory>
 *
 * The stack must be one scripts/friends-local-verify.sh created: a loopback
 * API and a project ID that starts with "gametime-friends-". The driver applies
 * the settings proposed for hosted gametime-p11b in Phase 5, then drives
 * fictional local Auth accounts through PostgREST and the actual
 * ingest-challenge-health handler in account mode. The real-activity test
 * clock is replaced only in this disposable database and restored in finally.
 * No hosted URL, Health data, device key, payment or notification is used.
 */
// Server replies are untyped JSON checked field by field below.
// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from "@std/assert";
import { createAccessTokenVerifier } from "../supabase/functions/_shared/jwt.ts";
import type { JsonWebKeySet } from "../supabase/functions/_shared/jwt.ts";
import {
  realHealthDatabase,
  realHealthReadinessDatabase,
} from "../supabase/functions/ingest-challenge-health/database.ts";
import { createIngestChallengeHealthHandler } from "../supabase/functions/ingest-challenge-health/handler.ts";

const root = Deno.args[0];
assert(root, "pass the disposable stack directory");
const config = await Deno.readTextFile(`${root}/supabase/config.toml`);
const project = /^project_id\s*=\s*"([^"]+)"/m.exec(config)?.[1] ?? "";
assert(project.startsWith("gametime-friends-"), "only a disposable friends stack");
const status = JSON.parse(
  new TextDecoder().decode(
    (await new Deno.Command("supabase", {
      args: ["status", "--workdir", root, "-o", "json"],
      stdout: "piped",
      stderr: "null",
    }).output()).stdout,
  ),
);
const api: string = status.API_URL;
const dbUrl: string = status.DB_URL;
assert(/^http:\/\/127\.0\.0\.1:\d+$/.test(api), "loopback API only");
assert(/@127\.0\.0\.1:\d+\/postgres$/.test(dbUrl), "loopback database only");
const serviceKey: string = status.SERVICE_ROLE_KEY;
const publishableKey: string = status.PUBLISHABLE_KEY;

// ---------------------------------------------------------------- plumbing

async function sql(query: string): Promise<string> {
  const child = new Deno.Command("psql", {
    args: [dbUrl, "-XqAt", "-v", "ON_ERROR_STOP=1"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(query));
  await writer.close();
  const result = await child.output();
  if (!result.success) {
    throw new Error("SQL control failed: " + new TextDecoder().decode(result.stderr));
  }
  return new TextDecoder().decode(result.stdout).trim();
}
const literal = (value: string) => "'" + value.replaceAll("'", "''") + "'";

const checks: string[] = [];
function check(condition: unknown, label: string) {
  if (!condition) throw new Error("FAIL " + label);
  checks.push(label);
  console.log("PASS " + label);
}
const observations: Record<string, unknown> = {};

type Reply = { status: number; body: any };
async function http(
  method: string,
  path: string,
  body: unknown,
  headers: Record<string, string>,
): Promise<Reply> {
  const response = await fetch(api + path, {
    method,
    headers: { "content-type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
    redirect: "error",
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
const service = { apikey: serviceKey, authorization: `Bearer ${serviceKey}` };

type Actor = { id: string; email: string; username: string; token: string; label: string };
function as(actor: Actor | null) {
  return actor === null ? service : {
    apikey: publishableKey,
    authorization: `Bearer ${actor.token}`,
  };
}
/** An RPC as a signed-in account or the service role. Errors come back as
 * { message } from PostgREST, or as an error body some quotas return. */
async function rpc(name: string, body: unknown, actor: Actor | null): Promise<Reply> {
  return await http("POST", `/rest/v1/rpc/${name}`, body, as(actor));
}
function errorOf(reply: Reply): string | null {
  if (reply.status >= 300) return reply.body?.message ?? `http_${reply.status}`;
  if (
    reply.body && typeof reply.body === "object" && typeof reply.body.message === "string" &&
    !("state" in reply.body) && !("id" in reply.body)
  ) return reply.body.message;
  return null;
}
async function ok(name: string, body: unknown, actor: Actor | null) {
  const reply = await rpc(name, body, actor);
  const error = errorOf(reply);
  if (error !== null) throw new Error(`${name} refused: ${error}`);
  return reply.body;
}

// Fictional local Auth accounts. The disposable copy enables password sign-in
// for these admin-created users only; hosted build 1 is Apple sign-in.
const password = crypto.randomUUID() + crypto.randomUUID();
const actors: Actor[] = [];
async function account(label: string, options: { age?: boolean } = {}): Promise<Actor> {
  const email = `friends-p4-${crypto.randomUUID()}@example.invalid`;
  const created = await http("POST", "/auth/v1/admin/users", {
    email,
    password,
    email_confirm: true,
  }, service);
  assertEquals(created.status, 200, "fictional account created");
  const signedIn = await http("POST", "/auth/v1/token?grant_type=password", { email, password }, {
    apikey: publishableKey,
  });
  assertEquals(signedIn.status, 200, "fictional account signed in");
  const actor: Actor = {
    id: created.body.id,
    email,
    username: "fp4" + crypto.randomUUID().replaceAll("-", "").slice(0, 14),
    token: signedIn.body.access_token,
    label,
  };
  actors.push(actor);
  // The app's own profile insert, through RLS, then its age confirmation.
  const profile = await http("POST", "/rest/v1/profiles", {
    id: actor.id,
    handle: actor.username,
    display_name: `Fictional ${label}`,
    timezone: "UTC",
  }, { ...as(actor), prefer: "return=minimal" });
  assertEquals(profile.status, 201, "profile saved through the app's insert");
  if (options.age ?? true) {
    await ok("challenge_command_v1", {
      p_request_id: crypto.randomUUID(),
      p_payload: { op: "confirm_age", confirmed: true },
    }, actor);
  }
  return actor;
}

// Friend commands, exactly as FriendCommand.body sends them.
async function friend(
  op: string,
  actor: Actor,
  subject: Actor,
  extra: Record<string, unknown> = {},
  id = crypto.randomUUID(),
) {
  return await rpc(`friend_${op}_v1`, { p_request_id: id, p_subject: subject.id, ...extra }, actor);
}
async function befriend(a: Actor, b: Actor) {
  assertEquals(errorOf(await friend("request", a, b)), null);
  assertEquals((await friend("accept", b, a)).body?.state, "friends");
}
const list = async (actor: Actor) => await ok("friend_list_v1", {}, actor);
const lookup = async (actor: Actor, username: string) =>
  await rpc("friend_lookup_v1", { p_username: username }, actor);
const ids = (rows: { id: string }[]) => rows.map((row) => row.id);

// Test clock for real-activity rows. Token and session checks keep wall time.
const priorClock = await sql(
  "select pg_get_functiondef('app.challenge_real_health_now_v1()'::regprocedure)",
);
let now = "";
async function clock(time: string) {
  now = time;
  await sql(
    `create or replace function app.challenge_real_health_now_v1() returns timestamptz language sql stable set search_path='' as $$ select ${
      literal(time)
    }::timestamptz $$;`,
  );
}

// The ingest handler, in account mode: no device key or assertion headers.
const jwks = (await http("GET", "/auth/v1/.well-known/jwks.json", undefined, {
  apikey: publishableKey,
})).body as JsonWebKeySet;
const handler = createIngestChallengeHealthHandler({
  enabled: true,
  appId: "ABCDE12345.test.gametime.app",
  verifyToken: createAccessTokenVerifier({
    kind: "jwks",
    jwks,
    expectedIssuer: `${api}/auth/v1`,
    expectedAudience: "authenticated",
  }),
  publicKeyFor: () => Promise.resolve(undefined),
  ingest: realHealthDatabase({ url: api, serviceRoleKey: serviceKey }),
  readiness: realHealthReadinessDatabase({ url: api, serviceRoleKey: serviceKey }),
});
async function upload(actor: Actor, body: Record<string, unknown>) {
  const response = await handler(
    new Request("http://127.0.0.1/functions/v1/ingest-challenge-health", {
      method: "POST",
      headers: { authorization: `Bearer ${actor.token}`, "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
  );
  return { status: response.status, body: await response.json() };
}

// ---------------------------------------------------------------- policies

type Metric = "steps" | "exercise" | "distance" | "timed";
const source: Record<Metric, string> = {
  steps: "apple_watch_steps_v1",
  exercise: "apple_watch_exercise_credit_v2",
  distance: "apple_workout_outdoor_distance_v1",
  timed: "apple_workout_outdoor_timed_v1",
};
/** A goal target and a met and missed value in each policy's unit. */
const sample: Record<Metric, { target: number; met: number; missed: number }> = {
  steps: { target: 8_000, met: 9_100, missed: 6_500 },
  exercise: { target: 1_800, met: 2_400, missed: 900 },
  distance: { target: 5_000_000, met: 5_250_000, missed: 3_100_000 },
  timed: { target: 1_800, met: 1_700, missed: 1_900 },
};
const timedDistance = { distance_mm: 5_000_000 };
const extra = (metric: Metric) => metric === "timed" ? timedDistance : {};

async function ready(actor: Actor, metric: Metric) {
  const reply = await upload(actor, {
    contract_version: 1,
    actor_id: actor.id,
    source_policy_version: source[metric],
    ...extra(metric),
    observed_at: now,
    request_id: crypto.randomUUID(),
  });
  assertEquals(reply.status, 200, `readiness saved (${reply.body?.error ?? "ok"})`);
  return reply.body;
}

type Lobby = {
  id: string;
  metric: Metric;
  creator: Actor;
  members: Actor[];
  digest?: string;
  terms?: any;
};
async function command(
  actor: Actor,
  lobby: Lobby,
  op: string,
  fields: Record<string, unknown> = {},
) {
  const detail = await ok("challenge_detail_v1", { p_id: lobby.id }, actor);
  return await rpc("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: { op, id: lobby.id, revision: detail.revision, ...fields },
  }, actor);
}
async function must(actor: Actor, lobby: Lobby, op: string, fields: Record<string, unknown> = {}) {
  const reply = await command(actor, lobby, op, fields);
  const error = errorOf(reply);
  if (error !== null) throw new Error(`${op} by ${actor.label} refused: ${error}`);
  return reply.body;
}
const detail = async (lobby: Lobby, actor: Actor = lobby.creator) =>
  await ok("challenge_detail_v1", { p_id: lobby.id }, actor);
const lobbyStatus = async (lobby: Lobby) =>
  await sql(`select status from app.challenge_lobbies_v1 where id=${literal(lobby.id)}`);

async function createFriendLobby(
  creator: Actor,
  metric: Metric,
  startDate: string,
  policy = `friend_${metric}_goal_v1`,
) {
  const reply = await rpc("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: {
      op: "create",
      policy,
      source_policy_version: source[metric],
      config: {
        start_date: startDate,
        days: 1,
        timezone: "UTC",
        amount_cents: 100,
        ...extra(metric),
      },
    },
  }, creator);
  return reply;
}
/** Create, invite, set targets, select and freeze, as the app's creation flow does. */
async function friendLobby(
  creator: Actor,
  others: Actor[],
  metric: Metric,
  startDate: string,
): Promise<Lobby> {
  const created = await createFriendLobby(creator, metric, startDate);
  if (errorOf(created) !== null) throw new Error("create refused: " + errorOf(created));
  const lobby: Lobby = { id: created.body.id, metric, creator, members: [creator, ...others] };
  await must(creator, lobby, "target", { target: sample[metric].target });
  for (const other of others) await must(creator, lobby, "invite", { username: other.username });
  for (const other of others) await must(other, lobby, "target", { target: sample[metric].target });
  for (const other of others) {
    await must(creator, lobby, "select", { actor_id: other.id, selected: true });
  }
  return lobby;
}
async function freeze(lobby: Lobby) {
  await must(lobby.creator, lobby, "freeze");
  const agreed = await detail(lobby);
  lobby.digest = agreed.agreement.digest;
  lobby.terms = agreed.agreement.terms;
}
async function consentAll(lobby: Lobby, who: Actor[] = lobby.members) {
  for (const actor of who) {
    await must(actor, lobby, "consent", { consent: true, digest: lobby.digest });
  }
}

const revisions = new Map<string, number>();
async function progress(lobby: Lobby, actor: Actor, value: number) {
  const key = lobby.id + actor.id;
  const revision = (revisions.get(key) ?? 0) + 1;
  const config = lobby.terms.config;
  const starts = new Date(config.starts_at).toISOString();
  const ends = new Date(config.ends_at).toISOString();
  // A later correction still reports activity only through the window's end.
  const through = Date.parse(now) < Date.parse(ends) ? now : ends;
  const reply = await upload(actor, {
    contract_version: 1,
    actor_id: actor.id,
    challenge_id: lobby.id,
    agreement_version: lobby.terms.version,
    terms_digest: lobby.digest,
    source_policy_version: source[lobby.metric],
    metric: lobby.metric,
    ...extra(lobby.metric),
    window_starts_at: starts,
    window_ends_at: ends,
    request_id: crypto.randomUUID(),
    revision,
    previous_revision: revision === 1 ? null : revision - 1,
    state: "value",
    value,
    observed_at: now,
    queried_through_at: through,
  });
  if (reply.status === 200) revisions.set(key, revision);
  return reply;
}

/** What the scheduled worker would do: process every row the work inventory
 * reports, without naming challenges. */
async function work() {
  const due = (await sql("select id from app.challenge_work_v1()")).split("\n").filter(Boolean);
  for (const id of due) await ok("challenge_process_v1", { p_id: id }, null);
  return due;
}
async function finalResult(lobby: Lobby) {
  const raw = await sql(
    `select result from app.challenge_finals_v1 where challenge_id=${literal(lobby.id)}`,
  );
  return raw ? JSON.parse(raw) : null;
}

// ---------------------------------------------------------------- run

try {
  // Phase 5 proposed values for gametime-p11b, applied by an operator.
  await sql(
    await Deno.readTextFile(new URL("./fixtures/friends-build1-settings.sql", import.meta.url)),
  );
  await ok("challenge_real_health_runtime_v1", {
    p_admission_enabled: true,
    p_ingestion_enabled: true,
    p_processing_enabled: true,
  }, null);
  check(
    await sql(`select not enabled from app.challenge_private_device_trial_v1 where singleton`) ===
        "t" &&
      await sql(
          `select not admission and not fixtures from app.challenge_runtime_v1 where singleton`,
        ) === "t",
    "the private trial and the fictional fixture runtime stay off",
  );
  await clock("2026-11-02T12:00:00Z");

  // ======================================================= availability
  const owner = await account("Owner");
  const availability = await ok("challenge_availability_v1", {}, owner);
  check(
    availability.restricted === true && availability.admission === true,
    "the server reports it is restricted and open",
  );
  check(
    JSON.stringify(
      availability.policies.map((p: any) => `${p.policy}/${p.source_policy_version}`),
    ) ===
      JSON.stringify([
        "friend_distance_goal_v1/apple_workout_outdoor_distance_v1",
        "friend_exercise_goal_v1/apple_watch_exercise_credit_v2",
        "friend_steps_goal_v1/apple_watch_steps_v1",
        "friend_timed_goal_v1/apple_workout_outdoor_timed_v1",
        "personal_distance_goal_v1/apple_workout_outdoor_distance_v1",
        "personal_steps_goal_v1/apple_watch_steps_v1",
      ]),
    "the server offers exactly the four friend goals and Personal Steps and Outdoor runs",
  );
  check(
    availability.links === false && availability.community === false &&
      availability.verification_mode === "private_account" && availability.account_allowed === true,
    "links and community are reported closed, and uploads use account mode",
  );

  // ======================================================= friendship matrix
  const ana = await account("Ana"), ben = await account("Ben"), cal = await account("Cal");
  const under21 = await account("Under 21", { age: false });

  check(
    (await lookup(ana, ben.username)).body.relation === "none",
    "lookup finds an exact username",
  );
  check(
    (await lookup(ana, ben.username.toUpperCase())).body.found === true,
    "lookup ignores letter case",
  );
  check(
    (await lookup(ana, ben.username.slice(0, -1))).body.found === false,
    "lookup never matches a prefix",
  );
  check((await lookup(ana, ana.username)).body.relation === "self", "lookup of yourself says so");
  check(
    (await lookup(ana, under21.username)).body.found === false,
    "an account that never confirmed 21+ is not found",
  );
  check(
    errorOf(await friend("request", under21, ana)) === "friend_age_required",
    "an account that never confirmed 21+ cannot send a request",
  );

  const requestId = crypto.randomUUID();
  const first = await friend("request", ana, ben, {}, requestId);
  check(first.body?.state === "outgoing", "Ana sends Ben a request");
  const replay = await friend("request", ana, ben, {}, requestId);
  check(
    JSON.stringify(replay.body) === JSON.stringify(first.body),
    "a retried request returns the saved answer",
  );
  check(
    errorOf(await friend("request", ana, cal, {}, requestId)) === "friend_request_conflict",
    "the same request ID for another person is refused",
  );
  check(
    (await lookup(ana, ben.username)).body.relation === "outgoing",
    "Ana sees her request as sent",
  );
  check(
    (await lookup(ben, ana.username)).body.relation === "incoming",
    "Ben sees it as a request for him",
  );
  check(
    errorOf(await friend("request", ben, ana)) === "friend_incoming_request_exists",
    "a crossed request is refused with the incoming-request answer",
  );
  check(
    ids((await list(ben)).incoming).includes(ana.id) &&
      ids((await list(ana)).outgoing).includes(ben.id),
    "both lists show the pending request",
  );
  check(errorOf(await friend("accept", ben, ana)) === null, "Ben accepts");
  check(
    ids((await list(ana)).friends).includes(ben.id) &&
      ids((await list(ben)).friends).includes(ana.id),
    "both people see each other as friends",
  );
  check(
    errorOf(await friend("cancel", ana, ben)) === "friend_state_changed",
    "a stale cancel after acceptance is refused",
  );

  // Silent decline: the request disappears; nothing tells the sender.
  check(errorOf(await friend("request", cal, ana)) === null, "Cal sends Ana a request");
  check(errorOf(await friend("decline", ana, cal)) === null, "Ana declines");
  const calAfter = await list(cal);
  check(
    !ids(calAfter.outgoing).includes(ana.id) && !ids(calAfter.friends).includes(ana.id) &&
      (await lookup(cal, ana.username)).body.relation === "none",
    "after a decline the sender sees no request and no friendship",
  );
  check(
    errorOf(await friend("request", cal, ana)) === null,
    "the sender can ask again after a decline",
  );
  check(errorOf(await friend("cancel", cal, ana)) === null, "and cancel that request");
  check(
    !ids((await list(ana)).incoming).includes(cal.id),
    "a cancelled request leaves the other list",
  );

  // Direct table writes are closed once commands_only is on.
  const direct = await http("POST", "/rest/v1/friendships", {
    user_a: [ana.id, cal.id].sort()[0],
    user_b: [ana.id, cal.id].sort()[1],
    requested_by: cal.id,
    status: "pending",
  }, { ...as(cal), prefer: "return=minimal" });
  check(
    direct.status >= 400 && direct.body?.message === "friend_command_required",
    "a direct friendship insert is refused",
  );
  const directDelete = await http(
    "DELETE",
    `/rest/v1/friendships?user_a=eq.${[ana.id, ben.id].sort()[0]}&user_b=eq.${
      [ana.id, ben.id].sort()[1]
    }`,
    undefined,
    { ...as(ben), prefer: "return=minimal" },
  );
  check(
    directDelete.status >= 400 && directDelete.body?.message === "friend_command_required" &&
      ids((await list(ana)).friends).includes(ben.id),
    "a direct friendship delete is refused and the friendship stays",
  );

  // Remove, block, unblock, report.
  check(errorOf(await friend("remove", ana, ben)) === null, "Ana removes Ben");
  check(!ids((await list(ben)).friends).includes(ana.id), "the removal shows on both sides");
  await befriend(ana, ben);
  check(errorOf(await friend("block", ana, ben)) === null, "Ana blocks Ben");
  check(
    (await lookup(ben, ana.username)).body.found === false &&
      (await lookup(ana, ben.username)).body.found === false,
    "a block hides both people from each other's lookups",
  );
  const benView = await list(ben), anaView = await list(ana);
  check(
    !ids(benView.friends).includes(ana.id) && ids(anaView.blocked).includes(ben.id) &&
      !JSON.stringify(benView).includes(ana.id),
    "the block ends the friendship and only Ana's list shows it",
  );
  check(
    errorOf(await friend("request", ben, ana)) === "friend_unavailable",
    "Ben cannot send Ana a request",
  );
  check(
    errorOf(await friend("block", ana, ben)) === "friend_state_changed",
    "a repeated block is refused as stale",
  );
  check(
    errorOf(await friend("unblock", ben, ana)) === "friend_state_changed",
    "the blocked person cannot unblock",
  );
  check(errorOf(await friend("unblock", ana, ben)) === null, "Ana unblocks Ben");
  check(
    (await lookup(ana, ben.username)).body.relation === "none" &&
      !ids((await list(ana)).friends).includes(ben.id),
    "unblocking does not restore the friendship",
  );
  check(
    errorOf(await friend("report", cal, ana, { p_reason: "free text" })) ===
      "friend_invalid_request",
    "a report takes only a stored reason",
  );
  const report = await friend("report", cal, ana, { p_reason: "unwanted_contact" });
  check(report.body?.saved === true, "a report works without a shared challenge");

  // The owner reads the report queue with a global support grant.
  // Grants last at most 7 days from wall time, so the owner's grant is renewed.
  const grantUntil = new Date(Date.now() + 6 * 86_400_000).toISOString();
  await ok("challenge_grant_support_v1", { p_actor: owner.id, p_expires: grantUntil }, null);
  const queue = await ok("challenge_support_reports_v1", {}, owner);
  const filed = queue.find((row: any) => row.subject === ana.id);
  check(
    filed?.reason === "unwanted_contact" && filed.challenge_id === null,
    "the report reaches the support queue",
  );
  check(!JSON.stringify(queue).includes(cal.id), "the queue does not name who reported");

  // Suspension hides the account and stops new requests.
  await ok("challenge_support_suspend_v1", {
    p_request_id: crypto.randomUUID(),
    p_subject: cal.id,
    p_reason: "unwanted_contact",
  }, owner);
  check((await lookup(ana, cal.username)).body.found === false, "a suspended account is not found");
  check(
    errorOf(await friend("request", cal, ben)) === "friend_account_restricted",
    "a suspended account cannot send requests",
  );

  // Lookup budget: 30 a minute, answered as an error body.
  const looker = await account("Looker");
  let lastLookup: Reply | null = null;
  for (let i = 0; i < 31; i++) lastLookup = await lookup(looker, "nobody_" + i);
  check(
    errorOf(lastLookup!) === "friend_lookup_rate_limited",
    "the 31st lookup in a minute is refused",
  );
  observations.lookup_limit_http_status = lastLookup!.status;

  // Daily request cap: 20 created requests.
  const sender = await account("Sender");
  const recipients: Actor[] = [];
  for (let i = 0; i < 21; i++) recipients.push(await account(`Recipient ${i + 1}`));
  for (let i = 0; i < 20; i++) {
    assertEquals(errorOf(await friend("request", sender, recipients[i]!)), null);
  }
  check(
    errorOf(await friend("request", sender, recipients[20]!)) === "friend_request_limit",
    "the 21st request in a day is refused",
  );

  // Invites need a friendship; removing a friend leaves a lobby alone.
  await ready(ana, "steps");
  const strangerLobby = await createFriendLobby(ana, "steps", "2026-11-04");
  const sl: Lobby = { id: strangerLobby.body.id, metric: "steps", creator: ana, members: [ana] };
  check(
    errorOf(await command(ana, sl, "invite", { username: ben.username })) ===
      "challenge_friend_unavailable",
    "you can invite only a friend",
  );
  await befriend(ana, ben);
  await must(ana, sl, "invite", { username: ben.username });
  check(errorOf(await friend("remove", ana, ben)) === null, "Ana removes Ben after inviting him");
  check(
    (await detail(sl)).members.some((m: any) => m.actor_id === ben.id),
    "removing a friend leaves an existing lobby unchanged",
  );
  await must(ana, sl, "cancel");

  // ======================================================= friend goals: 4 x {2, 6}
  const runs: {
    metric: Metric;
    size: number;
    lobby: Lobby;
    plan: Record<string, number | null>;
  }[] = [];
  for (const metric of ["steps", "exercise", "distance", "timed"] as Metric[]) {
    for (const size of [2, 6]) {
      const creator = await account(`${metric} ${size} creator`);
      const others: Actor[] = [];
      for (let i = 1; i < size; i++) {
        const other = await account(`${metric} ${size} friend ${i}`);
        await befriend(creator, other);
        others.push(other);
      }
      for (const actor of [creator, ...others]) await ready(actor, metric);
      const lobby = await friendLobby(creator, others, metric, "2026-11-04");
      await freeze(lobby);
      check(
        lobby.terms.source === source[metric] && lobby.terms.participants.length === size &&
          lobby.terms.simulation === "nonredeemable",
        `${metric} goal for ${size}: the agreement names the source, all ${size} people and simulated stakes`,
      );
      await consentAll(lobby);
      check(
        await lobbyStatus(lobby) === "scheduled",
        `${metric} goal for ${size}: everyone agreed and it is scheduled`,
      );
      // Creator meets; first friend misses then corrects; in the six, one
      // friend meets, one misses, one never uploads, one meets and corrects down.
      const plan: Record<string, number | null> = { [creator.id]: sample[metric].met };
      plan[others[0]!.id] = sample[metric].missed;
      if (size === 6) {
        plan[others[1]!.id] = sample[metric].met;
        plan[others[2]!.id] = sample[metric].missed;
        plan[others[3]!.id] = null;
        plan[others[4]!.id] = sample[metric].met;
      }
      runs.push({ metric, size, lobby, plan });
    }
  }

  // ======================================================= membership and limits
  // A seventh person cannot be selected.
  const seven = await account("Seven creator");
  const sixFriends: Actor[] = [];
  for (let i = 1; i <= 6; i++) {
    const other = await account(`Seven friend ${i}`);
    await befriend(seven, other);
    sixFriends.push(other);
  }
  const big = await createFriendLobby(seven, "steps", "2026-11-20");
  const bigLobby: Lobby = { id: big.body.id, metric: "steps", creator: seven, members: [seven] };
  for (const other of sixFriends) {
    await must(seven, bigLobby, "invite", { username: other.username });
  }
  for (const other of sixFriends.slice(0, 5)) {
    await must(seven, bigLobby, "select", { actor_id: other.id, selected: true });
  }
  check(
    errorOf(
      await command(seven, bigLobby, "select", { actor_id: sixFriends[5]!.id, selected: true }),
    ) === "challenge_capacity",
    "a seventh person is refused",
  );
  await must(seven, bigLobby, "cancel");

  // A member at a limit fails the whole freeze.
  const busy = await account("Busy friend");
  const busyHost = await account("Busy host"), otherHost = await account("Other host");
  await befriend(busyHost, busy);
  await befriend(otherHost, busy);
  for (const actor of [busy, busyHost, otherHost]) await ready(actor, "steps");
  const first4 = await friendLobby(busyHost, [busy], "steps", "2026-11-04");
  await freeze(first4);
  const overlap = await friendLobby(otherHost, [busy], "steps", "2026-11-04");
  const overlapFreeze = await command(otherHost, overlap, "freeze");
  check(
    errorOf(overlapFreeze) === "challenge_member_unavailable",
    "a friend already in a same-activity challenge on those dates fails the freeze without a reason",
  );
  check(await lobbyStatus(overlap) === "lobby_open", "the failed freeze leaves the lobby open");
  // The creator's own limit keeps its specific reason.
  const ownOverlap = await friendLobby(busy, [busyHost], "steps", "2026-11-04");
  check(
    errorOf(await command(busy, ownOverlap, "freeze")) === "challenge_metric_overlap",
    "a creator's own overlap keeps its reason",
  );
  // Three unsettled challenges for one member.
  const loaded = await account("Loaded friend");
  const loadedHost = await account("Loaded host");
  await befriend(loadedHost, loaded);
  for (const metric of ["exercise", "distance", "timed"] as Metric[]) {
    const host = await account(`Loaded ${metric} host`);
    await befriend(host, loaded);
    await ready(host, metric);
    await ready(loaded, metric);
    const busyLobby = await friendLobby(host, [loaded], metric, "2026-11-04");
    await freeze(busyLobby);
  }
  await ready(loadedHost, "steps");
  await ready(loaded, "steps");
  const fourth = await friendLobby(loadedHost, [loaded], "steps", "2026-11-10");
  const fourthFreeze = await command(loadedHost, fourth, "freeze");
  check(
    errorOf(fourthFreeze) === "challenge_member_unavailable",
    "a friend with three unsettled challenges fails the freeze without a reason",
  );

  // Any change after the freeze needs fresh agreement from everyone.
  const redo = await account("Redo creator"),
    redoA = await account("Redo friend A"),
    redoB = await account("Redo friend B");
  await befriend(redo, redoA);
  await befriend(redo, redoB);
  for (const actor of [redo, redoA, redoB]) await ready(actor, "steps");
  const redoLobby = await friendLobby(redo, [redoA, redoB], "steps", "2026-11-04");
  await freeze(redoLobby);
  const firstDigest = redoLobby.digest!;
  await must(redoA, redoLobby, "consent", { consent: true, digest: firstDigest });
  await must(redo, redoLobby, "reopen");
  await must(redoA, redoLobby, "target", { target: 9_000 });
  await must(redo, redoLobby, "select", { actor_id: redoB.id, selected: false });
  redoLobby.members = [redo, redoA];
  await freeze(redoLobby);
  check(
    redoLobby.digest !== firstDigest && redoLobby.terms.version === 2,
    "a change after the freeze makes new terms",
  );
  check(
    errorOf(await command(redoA, redoLobby, "consent", { consent: true, digest: firstDigest })) ===
      "challenge_consent_mismatch",
    "agreement to the old terms is refused",
  );
  check(
    await lobbyStatus(redoLobby) === "consent_pending",
    "the earlier agreement does not count toward the new terms",
  );
  await consentAll(redoLobby);
  check(await lobbyStatus(redoLobby) === "scheduled", "fresh agreement from everyone schedules it");

  // ======================================================= outcome setups
  // Consent incomplete at the start: cancelled.
  const partial = await account("Partial creator"), partialFriend = await account("Partial friend");
  await befriend(partial, partialFriend);
  for (const actor of [partial, partialFriend]) await ready(actor, "exercise");
  const partialLobby = await friendLobby(partial, [partialFriend], "exercise", "2026-11-04");
  await freeze(partialLobby);
  await consentAll(partialLobby, [partial]);
  // Fewer than two after a leave: void. And a block between the only two: void.
  const pairs: Lobby[] = [];
  for (const label of ["Leave", "Block"]) {
    const a = await account(`${label} creator`), b = await account(`${label} friend`);
    await befriend(a, b);
    for (const actor of [a, b]) await ready(actor, "distance");
    const lobby = await friendLobby(a, [b], "distance", "2026-11-04");
    await freeze(lobby);
    await consentAll(lobby);
    pairs.push(lobby);
  }

  // ======================================================= Personal goals
  const personal: { lobby: Lobby; value: number | null }[] = [];
  const solo = await account("Personal");
  for (
    const [metric, policy, value] of [
      ["steps", "personal_steps_goal_v1", sample.steps.met],
      ["distance", "personal_distance_goal_v1", sample.distance.missed],
      ["steps", "personal_steps_goal_v1", null],
    ] as [Metric, string, number | null][]
  ) {
    await ready(solo, metric);
    const start = value === null ? "2026-11-05" : "2026-11-04";
    const cfg = { start_date: start, days: 1, timezone: "UTC", amount_cents: 2_000 };
    const preview = await ok("challenge_personal_preview_v1", {
      p_policy: policy,
      p_config: cfg,
      p_target: sample[metric].target,
      p_source_policy_version: source[metric],
    }, solo);
    const saved = await ok("challenge_command_v1", {
      p_request_id: crypto.randomUUID(),
      p_payload: {
        op: "personal_commit",
        policy,
        config: cfg,
        target: sample[metric].target,
        digest: preview.digest,
        consent: true,
        source_policy_version: source[metric],
      },
    }, solo);
    const lobby: Lobby = {
      id: saved.id,
      metric,
      creator: solo,
      members: [solo],
      digest: preview.digest,
      terms: preview.terms,
    };
    personal.push({ lobby, value });
  }
  check(
    personal.every((p) => p.lobby.id),
    "Personal Steps and Outdoor runs goals save after one agreement",
  );
  for (
    const [metric, policy] of [["timed", "personal_timed_goal_v1"], [
      "exercise",
      "personal_exercise_goal_v1",
    ]] as [Metric, string][]
  ) {
    // The source stays open because a friend goal uses it.
    const readiness = await upload(solo, {
      contract_version: 1,
      actor_id: solo.id,
      source_policy_version: source[metric],
      ...extra(metric),
      observed_at: now,
      request_id: crypto.randomUUID(),
    });
    check(readiness.status === 200, `${metric} readiness saves because friend goals use it`);
    const config = {
      start_date: "2026-11-04",
      days: 1,
      timezone: "UTC",
      amount_cents: 2_000,
      ...extra(metric),
    };
    const preview = await ok("challenge_personal_preview_v1", {
      p_policy: policy,
      p_config: config,
      p_target: sample[metric].target,
      p_source_policy_version: source[metric],
    }, solo);
    const commit = await rpc("challenge_command_v1", {
      p_request_id: crypto.randomUUID(),
      p_payload: {
        op: "personal_commit",
        policy,
        config,
        target: sample[metric].target,
        digest: preview.digest,
        consent: true,
        source_policy_version: source[metric],
      },
    }, solo);
    check(
      errorOf(commit) === "challenge_policy_unavailable",
      `a Personal ${metric} goal cannot be saved`,
    );
  }

  // ======================================================= closed features
  check(
    errorOf(
      await createFriendLobby(owner, "steps", "2026-11-04", "friend_steps_leaderboard_v2"),
    ) ===
      "challenge_policy_unavailable",
    "friend leaderboards are refused",
  );
  const openLobby = await createFriendLobby(owner, "steps", "2026-11-20");
  const linkReply = await rpc("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: { op: "issue_link", id: openLobby.body.id },
  }, owner);
  observations.issue_link = errorOf(linkReply);
  check(errorOf(linkReply) !== null, "issuing an invitation link for an open lobby is refused");
  // Not build 1: would an operator's links_enabled open links for real lobbies?
  await sql(`update app.challenge_policy_runtime_v1 set links_enabled = true`);
  observations.issue_link_with_links_enabled = errorOf(
    await rpc("challenge_command_v1", {
      p_request_id: crypto.randomUUID(),
      p_payload: { op: "issue_link", id: openLobby.body.id },
    }, owner),
  ) ?? "issued";
  await sql(`update app.challenge_policy_runtime_v1 set links_enabled = false`);
  const redeemReply = await rpc("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: { op: "redeem_link", token: "a".repeat(43) },
  }, owner);
  check(
    errorOf(redeemReply) === "challenge_link_unavailable",
    "redeeming an invitation link is refused",
  );
  // A community published before enforcement cannot be joined after it.
  await sql(`update app.challenge_policy_runtime_v1 set allowlist_enforced = false`);
  const operator = await account("Community operator");
  const community: unknown = await ok("challenge_publish_community_real_health_v1", {
    p_request_id: crypto.randomUUID(),
    p_operator: operator.id,
    p_config: { start_date: "2026-11-04", days: 1, timezone: "UTC", amount_cents: 100 },
    p_target: 8_000,
    p_minimum: 2,
    p_capacity: 6,
    p_source_policy_version: "apple_watch_steps_v1",
  }, null).catch((error) => ({ error: String(error) }));
  await sql(`update app.challenge_policy_runtime_v1 set allowlist_enforced = true`);
  check(typeof community === "string", "an operator published a community before enforcement");
  const catalog = await rpc("challenge_community_catalog_v1", {}, owner);
  check(
    errorOf(catalog) === null && catalog.body.length === 0,
    "the community list is empty under enforcement",
  );
  const join = await rpc("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: { op: "join_community", id: community, digest: "0".repeat(64), consent: true },
  }, owner);
  check(errorOf(join) === "challenge_join_closed", "joining that community is refused");

  // ======================================================= clock: the window
  await clock("2026-11-04T12:00:00Z");
  await work();
  for (const run of runs) {
    check(
      await lobbyStatus(run.lobby) === "active",
      `${run.metric} goal for ${run.size} is active in its window`,
    );
    for (const actor of run.lobby.members) {
      const value = run.plan[actor.id];
      if (value === null || value === undefined) continue;
      const reply = await progress(run.lobby, actor, value);
      assertEquals(
        reply.status,
        200,
        `upload ${reply.body?.error ?? ""} ${reply.body?.message ?? ""}`,
      );
    }
  }
  check(true, "every participant's activity saved without a device check");
  const modes = await sql(
    `select string_agg(distinct verification_mode, ',') from app.challenge_real_health_requests_v1 where actor_id in (${
      actors.map((a) => literal(a.id)).join(",")
    })`,
  );
  check(modes === "private_account", "every saved update records account mode");
  check(
    await lobbyStatus(partialLobby) === "cancelled",
    "a challenge without everyone's agreement is cancelled at its start",
  );
  const partialResult = await finalResult(partialLobby);
  check(
    Object.values(partialResult.participants).every((p: any) => p.returned_cents === 100),
    "everyone's simulated entry returns after the cancellation",
  );
  // Leave and block during the window.
  const [leaveLobby, blockLobby] = pairs as [Lobby, Lobby];
  await must(leaveLobby.members[1]!, leaveLobby, "leave");
  check(
    errorOf(await friend("block", blockLobby.creator, blockLobby.members[1]!)) === null,
    "a participant blocks the other",
  );
  await work();
  for (
    const [lobby, label] of [[leaveLobby, "a leave"], [blockLobby, "a block"]] as [Lobby, string][]
  ) {
    check(await lobbyStatus(lobby) === "void", `fewer than two after ${label} voids the challenge`);
  }
  for (const lobby of [leaveLobby, blockLobby]) {
    const result = await finalResult(lobby);
    check(
      result.outcome === "void" &&
        Object.values(result.participants).every((p: any) => p.returned_cents === 100),
      "a voided challenge returns everyone's simulated entry",
    );
  }
  for (const p of personal) {
    if (p.value !== null) {
      const reply = await progress(p.lobby, solo, p.value);
      assertEquals(reply.status, 200, "personal upload");
    }
  }

  // ======================================================= corrections
  await clock("2026-11-05T06:00:00Z");
  await work();
  for (const run of runs) {
    // The first friend's missed total is corrected upward to a met total.
    const corrected = await progress(run.lobby, run.lobby.members[1]!, sample[run.metric].met);
    assertEquals(corrected.status, 200, "correction saved");
    if (run.size === 6) {
      // The sixth person's met total is corrected down to a miss.
      const down = await progress(run.lobby, run.lobby.members[5]!, sample[run.metric].missed);
      assertEquals(down.status, 200, "downward correction saved");
    }
  }
  check(true, "corrections after the window save as new revisions");

  // ======================================================= provisional and final
  await clock("2026-11-07T00:00:01Z");
  await work();
  const reviewed = runs.find((r) => r.metric === "steps" && r.size === 6)!;
  for (const run of runs) {
    check(
      await lobbyStatus(run.lobby) === "review",
      `${run.metric} goal for ${run.size} has a provisional result`,
    );
  }
  const notice = JSON.parse(
    await sql(
      `select row_to_json(n) from app.challenge_notices_v1 n where challenge_id=${
        literal(reviewed.lobby.id)
      } order by revision desc limit 1`,
    ),
  );
  await clock("2026-11-07T01:00:00Z");
  await must(reviewed.lobby.members[3]!, reviewed.lobby, "review", {
    notice_revision: notice.revision,
    reason: "wrong_total",
  });
  await clock("2026-11-09T00:00:02Z");
  await work();
  for (const run of runs.filter((r) => r !== reviewed)) {
    check(
      await lobbyStatus(run.lobby) === "final",
      `${run.metric} goal for ${run.size} is final after the review window`,
    );
  }
  check(await lobbyStatus(reviewed.lobby) === "review", "an open review holds its challenge");
  await clock("2026-11-10T01:00:01Z");
  await work();
  await clock("2026-11-12T01:00:02Z");
  await work();
  check(
    await lobbyStatus(reviewed.lobby) === "final",
    "the reviewed challenge becomes final after its review closes",
  );
  for (const run of runs) {
    const result = await finalResult(run.lobby);
    const [creator, ...others] = run.lobby.members;
    // Met, or corrected up to met, returns the entry. Below the goal, no data
    // and a correction down are excluded and refunded: an incomplete Apple
    // Health total can't prove a miss.
    const expected: Record<string, string> = { [creator!.id]: "met", [others[0]!.id]: "met" };
    if (run.size === 6) {
      expected[others[1]!.id] = "met";
      expected[others[2]!.id] = "excluded";
      expected[others[3]!.id] = "excluded";
      expected[others[4]!.id] = "excluded";
    }
    const statuses = Object.fromEntries(
      Object.entries(result.participants).map(([id, p]: [string, any]) => [id, p.status]),
    );
    check(
      result.outcome === "scored" && result.simulation === "nonredeemable" &&
        result.entry_cents === 100 * run.size && result.unallocated_cents === 0 &&
        JSON.stringify(Object.keys(statuses).sort()) ===
          JSON.stringify(Object.keys(expected).sort()) &&
        Object.entries(expected).every(([id, status]) => statuses[id] === status) &&
        Object.values(result.participants).every((p: any) => p.returned_cents === 100),
      `${run.metric} goal for ${run.size}: each result follows the saved activity and corrections`,
    );
    const seen = await detail(run.lobby, others[0]!);
    check(
      seen.final?.result?.outcome === "scored" && seen.members.length === run.size,
      `${run.metric} goal for ${run.size}: a participant can read the final result`,
    );
  }
  const [metGoal, shortGoal, emptyGoal] = personal;
  const metResult = await finalResult(metGoal!.lobby);
  check(
    await lobbyStatus(metGoal!.lobby) === "final" &&
      metResult.participants[solo.id].status === "met" &&
      metResult.participants[solo.id].returned_cents === 2_000,
    "Personal Steps: a met goal is final and returns the simulated stake",
  );
  for (
    const [goal, label] of [[shortGoal!, "a total below the goal"], [
      emptyGoal!,
      "no activity",
    ]] as const
  ) {
    const result = await finalResult(goal.lobby);
    check(
      await lobbyStatus(goal.lobby) === "void" &&
        result.participants[solo.id].returned_cents === 2_000,
      `Personal: ${label} doesn't count against the person`,
    );
  }
  console.log(JSON.stringify({ checks: checks.length, observations }, null, 2));
} finally {
  await sql(priorClock);
  await ok("challenge_real_health_runtime_v1", {
    p_admission_enabled: false,
    p_ingestion_enabled: false,
    p_processing_enabled: false,
  }, null).catch(() => {});
  // Sign every fictional account out; their records stay in the disposable DB.
  if (actors.length) {
    await sql(
      `delete from auth.sessions where user_id in (${actors.map((a) => literal(a.id)).join(",")})`,
    );
  }
}
