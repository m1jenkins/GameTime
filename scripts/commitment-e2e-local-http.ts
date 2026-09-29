/** D144 commitment end-to-end test on a disposable local stack.
 *
 * Usage: deno run --config supabase/functions/deno.json -A \
 *   scripts/commitment-e2e-local-http.ts <disposable stack directory> [emulator|test]
 *
 * The stack must be one scripts/commitment-e2e-local-verify.sh created: a
 * loopback API and a project ID that starts with "gametime-commitment-". The
 * driver runs the actual challenge-commitment-setup, -charge and -webhook
 * handlers, the ingest-challenge-health handler in account mode and the D144
 * database functions, with fictional local Auth accounts and a $1 amount.
 *
 * Stripe is either a local emulator of the endpoints those handlers call
 * ("emulator", the default) or Stripe test mode ("test", keys from
 * STRIPE_SECRET_KEY / STRIPE_PUBLISHABLE_KEY, which must be sk_test_/pk_test_).
 * Webhook events are signed here with a signing secret generated for this run;
 * the handler still re-reads every object from Stripe. The real-activity test
 * clock is replaced only in this disposable database and restored in finally.
 * Output names outcomes and counts only: no IDs, keys, secrets or card numbers.
 */
// Server replies are untyped JSON checked field by field below.
// deno-lint-ignore-file no-explicit-any
import Stripe from "stripe";
import { assert, assertEquals } from "@std/assert";
import { createAccessTokenVerifier } from "../supabase/functions/_shared/jwt.ts";
import type { JsonWebKeySet } from "../supabase/functions/_shared/jwt.ts";
import {
  STRIPE_API_VERSION,
  stripeSandboxConfig,
} from "../supabase/functions/_shared/stripe_sandbox.ts";
import {
  realHealthDatabase,
  realHealthReadinessDatabase,
} from "../supabase/functions/ingest-challenge-health/database.ts";
import { createIngestChallengeHealthHandler } from "../supabase/functions/ingest-challenge-health/handler.ts";
import { postgrestCommitmentSetupDatabase } from "../supabase/functions/challenge-commitment-setup/database.ts";
import { createCommitmentSetupHandler } from "../supabase/functions/challenge-commitment-setup/handler.ts";
import { stripeSetupGateway } from "../supabase/functions/personal-payment-setup/stripe.ts";
import { postgrestCommitmentChargeDatabase } from "../supabase/functions/challenge-commitment-charge/database.ts";
import {
  COMMITMENT_DISPATCH_SECRET_HEADER,
  type CommitmentChargeGateway,
  CommitmentTransportAmbiguousError,
  createCommitmentChargeHandler,
} from "../supabase/functions/challenge-commitment-charge/handler.ts";
import { stripeCommitmentChargeGateway } from "../supabase/functions/challenge-commitment-charge/stripe.ts";
import { postgrestCommitmentWebhookDatabase } from "../supabase/functions/challenge-commitment-webhook/database.ts";
import {
  createCommitmentWebhookHandler,
  STRIPE_SIGNATURE_HEADER,
} from "../supabase/functions/challenge-commitment-webhook/handler.ts";
import { stripeWebhookGateway } from "../supabase/functions/personal-stripe-sandbox-webhook/stripe.ts";

const root = Deno.args[0];
assert(root, "pass the disposable stack directory");
const mode = Deno.args[1] ?? "emulator";
assert(mode === "emulator" || mode === "test", "Stripe mode is emulator or test");
const config = await Deno.readTextFile(`${root}/supabase/config.toml`);
const project = /^project_id\s*=\s*"([^"]+)"/m.exec(config)?.[1] ?? "";
assert(project.startsWith("gametime-commitment-"), "only a disposable commitment stack");
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
const supabasePublishableKey: string = status.PUBLISHABLE_KEY;

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
/** Outcome rows for the receipt: labels and states only, never IDs. */
const outcomes: Record<string, Record<string, unknown>> = {};

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

type Actor = { id: string; token: string; label: string };
function as(actor: Actor | null) {
  return actor === null ? service : {
    apikey: supabasePublishableKey,
    authorization: `Bearer ${actor.token}`,
  };
}
async function rpc(name: string, body: unknown, actor: Actor | null): Promise<Reply> {
  return await http("POST", `/rest/v1/rpc/${name}`, body, as(actor));
}
function errorOf(reply: Reply): string | null {
  if (reply.status >= 300) return reply.body?.message ?? `http_${reply.status}`;
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
async function account(label: string): Promise<Actor> {
  const email = `commitment-e2e-${crypto.randomUUID()}@example.invalid`;
  const created = await http("POST", "/auth/v1/admin/users", {
    email,
    password,
    email_confirm: true,
  }, service);
  assertEquals(created.status, 200, "fictional account created");
  const signedIn = await http("POST", "/auth/v1/token?grant_type=password", { email, password }, {
    apikey: supabasePublishableKey,
  });
  assertEquals(signedIn.status, 200, "fictional account signed in");
  const actor: Actor = { id: created.body.id, token: signedIn.body.access_token, label };
  actors.push(actor);
  const profile = await http("POST", "/rest/v1/profiles", {
    id: actor.id,
    handle: "ce2e" + crypto.randomUUID().replaceAll("-", "").slice(0, 14),
    display_name: `Fictional ${label}`,
    timezone: "UTC",
  }, { ...as(actor), prefer: "return=minimal" });
  assertEquals(profile.status, 201, "profile saved through the app's insert");
  await ok("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: { op: "confirm_age", confirmed: true },
  }, actor);
  return actor;
}

// ---------------------------------------------------------------- Stripe

/** A small stand-in for the Stripe endpoints the commitment functions call:
 * customers, SetupIntents, off-session PaymentIntents and idempotent replay.
 * Test payment methods follow Stripe's: pm_card_visa (4242...) saves and
 * charges; pm_card_chargeCustomerFail (4000 0000 0000 0341) saves and is
 * declined off-session. Everything it returns is livemode=false. */
function stripeEmulator() {
  const objects = new Map<string, any>();
  const paymentMethodBehavior = new Map<string, "charge" | "decline">();
  const replays = new Map<string, { body: string; status: number; response: string }>();
  const counts = { paymentIntentsCreated: 0, idempotentReplays: 0 };
  let sequence = 0;
  const id = (prefix: string) =>
    `${prefix}_emu${(++sequence).toString().padStart(6, "0")}${
      crypto.randomUUID().replaceAll("-", "").slice(0, 10)
    }`;
  const reply = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json", "request-id": id("req") },
    });
  const invalid = (message: string) =>
    reply(400, { error: { type: "invalid_request_error", message } });
  const created = () => Math.floor(Date.now() / 1000);

  function paymentIntent(form: URLSearchParams): Response {
    const customer = objects.get(form.get("customer") ?? "");
    const method = form.get("payment_method") ?? "";
    if (customer?.object !== "customer") return invalid("No such customer");
    if (objects.get(method)?.customer !== customer.id) {
      return invalid("The payment method is not attached to this customer");
    }
    if (form.get("confirm") !== "true" || form.get("off_session") !== "true") {
      return invalid("The emulator only confirms off-session charges");
    }
    const intent: any = {
      id: id("pi"),
      object: "payment_intent",
      amount: Number(form.get("amount")),
      currency: form.get("currency"),
      customer: customer.id,
      payment_method: method,
      livemode: false,
      created: created(),
      metadata: Object.fromEntries(
        [...form].filter(([key]) => key.startsWith("metadata[")).map((
          [key, value],
        ) => [key.slice(9, -1), value]),
      ),
      last_payment_error: null,
      status: "succeeded",
    };
    counts.paymentIntentsCreated += 1;
    objects.set(intent.id, intent);
    if (paymentMethodBehavior.get(method) === "decline") {
      intent.status = "requires_payment_method";
      intent.last_payment_error = {
        type: "card_error",
        code: "card_declined",
        decline_code: "generic_decline",
        message: "Your card was declined.",
      };
      return reply(402, {
        error: {
          type: "card_error",
          code: "card_declined",
          decline_code: "generic_decline",
          message: "Your card was declined.",
          payment_intent: intent,
        },
      });
    }
    return reply(200, intent);
  }

  function route(method: string, path: string, form: URLSearchParams): Response {
    let match: RegExpExecArray | null;
    if (method === "POST" && path === "/v1/customers") {
      const customer = { id: id("cus"), object: "customer", livemode: false, created: created() };
      objects.set(customer.id, customer);
      return reply(200, customer);
    }
    if (method === "POST" && path === "/v1/setup_intents") {
      if (objects.get(form.get("customer") ?? "")?.object !== "customer") {
        return invalid("No such customer");
      }
      const intentId = id("seti");
      const intent = {
        id: intentId,
        object: "setup_intent",
        client_secret: `${intentId}_secret_${crypto.randomUUID().replaceAll("-", "")}`,
        customer: form.get("customer"),
        payment_method: null,
        usage: form.get("usage"),
        livemode: false,
        created: created(),
        status: "requires_payment_method",
      };
      objects.set(intentId, intent);
      return reply(200, intent);
    }
    if ((match = /^\/v1\/setup_intents\/([A-Za-z0-9_]+)\/confirm$/.exec(path)) && method === "POST") {
      const intent = objects.get(match[1]!);
      if (intent?.object !== "setup_intent") return invalid("No such setup intent");
      const test = form.get("payment_method");
      if (test !== "pm_card_visa" && test !== "pm_card_chargeCustomerFail") {
        return invalid("Unknown test payment method");
      }
      const methodId = id("pm");
      objects.set(methodId, { id: methodId, object: "payment_method", customer: intent.customer });
      paymentMethodBehavior.set(methodId, test === "pm_card_visa" ? "charge" : "decline");
      intent.payment_method = methodId;
      intent.status = "succeeded";
      return reply(200, intent);
    }
    if ((match = /^\/v1\/(setup_intents|payment_intents)\/([A-Za-z0-9_]+)$/.exec(path)) && method === "GET") {
      const object = objects.get(match[2]!);
      return object === undefined ? reply(404, { error: { type: "invalid_request_error" } }) : reply(200, object);
    }
    if (method === "POST" && path === "/v1/payment_intents") return paymentIntent(form);
    if (method === "GET" && path === "/v1/payment_intents") {
      const customer = form.get("customer");
      const data = [...objects.values()].filter((o) =>
        o.object === "payment_intent" && (customer === null || o.customer === customer)
      );
      return reply(200, { object: "list", data, has_more: false, url: path });
    }
    return reply(404, { error: { type: "invalid_request_error", message: "not emulated" } });
  }

  const server = Deno.serve({ hostname: "127.0.0.1", port: 0, onListen: () => {} }, async (request) => {
    const url = new URL(request.url);
    const body = await request.text();
    const form = request.method === "GET" ? url.searchParams : new URLSearchParams(body);
    const key = request.headers.get("idempotency-key");
    if (request.method === "POST" && key !== null) {
      const seen = replays.get(key);
      if (seen !== undefined) {
        if (seen.body !== url.pathname + "?" + body) {
          return reply(400, {
            error: { type: "idempotency_error", message: "Keys are for one request only" },
          });
        }
        counts.idempotentReplays += 1;
        return new Response(seen.response, {
          status: seen.status,
          headers: { "content-type": "application/json", "idempotent-replayed": "true" },
        });
      }
      const response = route(request.method, url.pathname, form);
      const text = await response.text();
      replays.set(key, { body: url.pathname + "?" + body, status: response.status, response: text });
      return new Response(text, { status: response.status, headers: response.headers });
    }
    return route(request.method, url.pathname, form);
  });
  return { server, counts, port: (server.addr as Deno.NetAddr).port };
}

const emulator = mode === "emulator" ? stripeEmulator() : undefined;
const stripeKeys = mode === "test" ? stripeSandboxConfig() : {
  secretKey: "sk_test_emulator" + crypto.randomUUID().replaceAll("-", ""),
  publishableKey: "pk_test_emulator" + crypto.randomUUID().replaceAll("-", ""),
};
if (mode === "test") {
  assert(stripeKeys.secretKey.startsWith("sk_test_"), "Stripe test mode only");
}
const stripe = new Stripe(stripeKeys.secretKey, {
  apiVersion: STRIPE_API_VERSION,
  httpClient: Stripe.createFetchHttpClient(),
  ...(emulator === undefined
    ? {}
    : { host: "127.0.0.1", port: emulator.port, protocol: "http" as const }),
});
const webhookSecret = "whsec_" + crypto.randomUUID().replaceAll("-", "");
const dispatchSecret = crypto.randomUUID() + crypto.randomUUID();

/** What the card sheet does after the first setup call: confirm with a test card. */
async function confirmCard(clientSecret: string, testCard: "pm_card_visa" | "pm_card_chargeCustomerFail") {
  const setupIntentId = clientSecret.slice(0, clientSecret.indexOf("_secret_"));
  const confirmed = await stripe.setupIntents.confirm(setupIntentId, {
    payment_method: testCard,
    ...(mode === "test" ? { return_url: "https://example.invalid/commitment-e2e" } : {}),
  });
  assertEquals(confirmed.status, "succeeded", "the test card saved");
  assertEquals(confirmed.livemode, false, "the saved card is a test object");
}
async function paymentIntentsFor(customerId: string) {
  return (await stripe.paymentIntents.list({ customer: customerId, limit: 100 })).data;
}

// ---------------------------------------------------------------- handlers

const jwks = (await http("GET", "/auth/v1/.well-known/jwks.json", undefined, {
  apikey: supabasePublishableKey,
})).body as JsonWebKeySet;
const verifyToken = createAccessTokenVerifier({
  kind: "jwks",
  jwks,
  expectedIssuer: `${api}/auth/v1`,
  expectedAudience: "authenticated",
});
const database = { url: api, serviceRoleKey: serviceKey };
const ingest = createIngestChallengeHealthHandler({
  enabled: true,
  appId: "ABCDE12345.test.gametime.app",
  verifyToken,
  publicKeyFor: () => Promise.resolve(undefined),
  ingest: realHealthDatabase(database),
  readiness: realHealthReadinessDatabase(database),
});
const setupHandler = createCommitmentSetupHandler({
  database: postgrestCommitmentSetupDatabase(database),
  stripe: stripeSetupGateway(stripe),
  publishableKey: stripeKeys.publishableKey,
  verifyToken,
});
const chargeGateway = stripeCommitmentChargeGateway(stripe);
function chargeHandler(gateway: CommitmentChargeGateway = chargeGateway) {
  return createCommitmentChargeHandler({
    deploymentEnvironment: "local",
    dispatchSecret,
    database: postgrestCommitmentChargeDatabase(database),
    stripe: gateway,
  });
}
const webhookHandler = createCommitmentWebhookHandler({
  stripe: stripeWebhookGateway(stripe, webhookSecret),
  database: postgrestCommitmentWebhookDatabase(database),
});

async function call(handler: (r: Request) => Promise<Response>, path: string, init: RequestInit) {
  const response = await handler(new Request(`http://127.0.0.1/functions/v1/${path}`, init));
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
async function setup(actor: Actor, requestId: string, amountCents = 100) {
  return await call(setupHandler, "challenge-commitment-setup", {
    method: "POST",
    headers: { authorization: `Bearer ${actor.token}`, "content-type": "application/json" },
    body: JSON.stringify({ requestId, amountCents }),
  });
}
/** The manual dispatch invocation: one POST with the dispatch secret header. */
async function dispatch(gateway?: CommitmentChargeGateway, secret = dispatchSecret) {
  return await call(chargeHandler(gateway), "challenge-commitment-charge", {
    method: "POST",
    headers: { [COMMITMENT_DISPATCH_SECRET_HEADER]: secret },
  });
}
async function webhook(event: Record<string, unknown>, secret = webhookSecret) {
  const payload = JSON.stringify(event);
  const header = await stripe.webhooks.generateTestHeaderStringAsync({
    payload,
    secret,
    cryptoProvider: Stripe.createSubtleCryptoProvider(),
  });
  return await call(webhookHandler, "challenge-commitment-webhook", {
    method: "POST",
    headers: { [STRIPE_SIGNATURE_HEADER]: header, "content-type": "application/json" },
    body: payload,
  });
}
function event(type: string, objectId: string, livemode = false) {
  return {
    id: "evt_e2e" + crypto.randomUUID().replaceAll("-", ""),
    object: "event",
    api_version: STRIPE_API_VERSION,
    created: Math.floor(Date.now() / 1000),
    livemode,
    type,
    data: { object: { id: objectId, object: type.split(".")[0] } },
  };
}

// Test clock for real-activity rows. Token, setup expiry and charge leases keep wall time.
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
async function upload(actor: Actor, body: Record<string, unknown>) {
  const response = await ingest(
    new Request("http://127.0.0.1/functions/v1/ingest-challenge-health", {
      method: "POST",
      headers: { authorization: `Bearer ${actor.token}`, "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
  );
  return { status: response.status, body: await response.json() };
}
const STEPS = "apple_watch_steps_v1";
const TARGET = 8_000;
async function ready(actor: Actor) {
  const reply = await upload(actor, {
    contract_version: 1,
    actor_id: actor.id,
    source_policy_version: STEPS,
    observed_at: now,
    request_id: crypto.randomUUID(),
  });
  assertEquals(reply.status, 200, `readiness saved (${reply.body?.error ?? "ok"})`);
}

type Goal = {
  actor: Actor;
  id: string;
  digest: string;
  terms: any;
  customerId: string;
  revision: number;
};
/** Share one fact for the goal, as the app's Health upload does. */
async function progress(goal: Goal, value: number, queriedThrough?: string) {
  const starts = new Date(goal.terms.config.starts_at).toISOString();
  const ends = new Date(goal.terms.config.ends_at).toISOString();
  const through = queriedThrough ?? (Date.parse(now) < Date.parse(ends) ? now : ends);
  const revision = goal.revision + 1;
  const reply = await upload(goal.actor, {
    contract_version: 1,
    actor_id: goal.actor.id,
    challenge_id: goal.id,
    agreement_version: goal.terms.version,
    terms_digest: goal.digest,
    source_policy_version: STEPS,
    metric: "steps",
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
  assertEquals(reply.status, 200, `upload ${reply.body?.error ?? ""} ${reply.body?.message ?? ""}`);
  goal.revision = revision;
}
async function work() {
  const due = (await sql("select id from app.challenge_work_v1()")).split("\n").filter(Boolean);
  for (const id of due) await ok("challenge_process_v1", { p_id: id }, null);
}
const lobbyStatus = async (goal: Goal) =>
  await sql(`select status from app.challenge_lobbies_v1 where id=${literal(goal.id)}`);
const chargeRow = async (goal: Goal) => {
  const raw = await sql(
    `select row_to_json(c) from (select status, failure_code, attempt_count, livemode, amount_cents,
       idempotency_key = 'gt:challenge-commitment:v1:' || challenge_id || ':' || actor_id as keyed,
       stripe_payment_intent_id from app.challenge_commitment_charges_v1
      where challenge_id=${literal(goal.id)}) c`,
  );
  return raw ? JSON.parse(raw) : null;
};
const ownerStatus = async (goal: Goal) =>
  await ok("challenge_commitment_status_v1", { p_challenge_id: goal.id }, goal.actor);
const chargeCount = async () =>
  Number(await sql("select count(*) from app.challenge_commitment_charges_v1"));

/** Save a $1 test card for this account, as the app does: start, the card
 * sheet confirms, then the same request again records the saved card. */
async function saveCard(
  actor: Actor,
  testCard: "pm_card_visa" | "pm_card_chargeCustomerFail",
  options: { webhookFirst?: boolean } = {},
) {
  const requestId = crypto.randomUUID();
  const started = await setup(actor, requestId);
  assertEquals(started.status, 201, `setup started (${started.body?.message ?? "ok"})`);
  assertEquals(started.body.status, "pending_provider");
  assert(started.body.publishableKey === stripeKeys.publishableKey);
  await confirmCard(started.body.setupIntentClientSecret, testCard);
  const secret: string = started.body.setupIntentClientSecret;
  const setupIntentId = secret.slice(0, secret.indexOf("_secret_"));
  let webhookFirst: { applied: any; duplicate: any } | undefined;
  if (options.webhookFirst) {
    const signed = event("setup_intent.succeeded", setupIntentId);
    webhookFirst = { applied: await webhook(signed), duplicate: await webhook(signed) };
  }
  const finished = await setup(actor, requestId);
  assertEquals(finished.status, 200, "setup recorded");
  assertEquals(finished.body.status, "succeeded");
  const customerId = await sql(
    `select stripe_customer_id from app.challenge_commitment_customers_v1 where actor_id=${
      literal(actor.id)
    }`,
  );
  return { setupId: started.body.setupId as string, customerId, setupIntentId, webhookFirst };
}

/** Preview and commit a one-day $1 Personal Steps goal with the saved card. */
async function commit(actor: Actor, card: { setupId: string; customerId: string }, startDate: string) {
  const cfg = { start_date: startDate, days: 1, timezone: "UTC", amount_cents: 100 };
  const preview = await ok("challenge_commitment_preview_v1", {
    p_policy: "personal_steps_goal_v1",
    p_config: cfg,
    p_target: TARGET,
    p_source_policy_version: STEPS,
    p_setup_id: card.setupId,
  }, actor);
  const saved = await ok("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: {
      op: "personal_commit",
      policy: "personal_steps_goal_v1",
      config: cfg,
      target: TARGET,
      digest: preview.digest,
      consent: true,
      source_policy_version: STEPS,
      commitment_setup_id: card.setupId,
    },
  }, actor);
  return {
    actor,
    id: saved.id,
    digest: preview.digest,
    terms: preview.terms,
    customerId: card.customerId,
    revision: 0,
  } as Goal;
}

// ---------------------------------------------------------------- run

const runtimeBefore = await sql(
  "select enabled from app.challenge_commitment_runtime_v1 where singleton",
);
try {
  await sql(
    await Deno.readTextFile(new URL("./fixtures/friends-build1-settings.sql", import.meta.url)),
  );
  await ok("challenge_real_health_runtime_v1", {
    p_admission_enabled: true,
    p_ingestion_enabled: true,
    p_processing_enabled: true,
  }, null);
  await clock("2026-11-02T12:00:00Z");
  check(runtimeBefore === "f", "commitments start switched off on a fresh stack");

  // ======================================================= isolation and gates
  check(
    (await dispatch(undefined, "x".repeat(40))).status === 401,
    "dispatch without the dispatch secret is refused",
  );
  let refused = false;
  try {
    createCommitmentChargeHandler({
      deploymentEnvironment: "production",
      dispatchSecret,
      database: postgrestCommitmentChargeDatabase(database),
      stripe: chargeGateway,
    });
  } catch {
    refused = true;
  }
  check(refused, "the charge worker refuses to start in production");
  const labels = ["met", "no data", "partial window", "shortfall", "shortfall, lost reply", "decline"];
  const people: Record<string, Actor> = {};
  for (const label of labels) people[label] = await account(label);
  const offSetup = await setup(people["met"]!, crypto.randomUUID());
  check(
    offSetup.status === 403 && offSetup.body?.message === "challenge_commitment_unavailable",
    "no card can be saved while the switch is off",
  );
  await ok("challenge_commitment_set_runtime_v1", { p_enabled: true }, null);
  const notEligible = await setup(people["met"]!, crypto.randomUUID());
  check(
    notEligible.status === 403 && notEligible.body?.message === "challenge_commitment_unavailable",
    "an account must also be eligible",
  );
  for (const actor of Object.values(people)) {
    await ok("challenge_commitment_set_eligibility_v1", { p_actor: actor.id, p_eligible: true }, null);
  }
  const availability = await ok("challenge_commitment_availability_v1", {}, people["met"]!);
  check(
    availability.available === true && availability.recipient === "gametime" &&
      availability.provider === "stripe_sandbox" && availability.minimum_cents === 100,
    "an eligible account sees commitments available, $1 minimum, GameTime as recipient",
  );

  // ======================================================= save a $1 card
  const cards: Record<string, Awaited<ReturnType<typeof saveCard>>> = {};
  for (const label of labels) {
    cards[label] = await saveCard(
      people[label]!,
      label === "decline" ? "pm_card_chargeCustomerFail" : "pm_card_visa",
      { webhookFirst: label === "met" },
    );
  }
  const setupRows = JSON.parse(
    await sql(`select json_agg(json_build_object('status', status, 'amount', amount_cents,
      'livemode', livemode, 'customer', stripe_customer_id is not null,
      'method', stripe_payment_method_id is not null)) from app.challenge_commitment_setups_v1
      where actor_id in (${actors.map((a) => literal(a.id)).join(",")})`),
  );
  check(
    setupRows.length === labels.length &&
      setupRows.every((r: any) =>
        r.status === "succeeded" && r.amount === 100 && r.livemode === false && r.customer &&
        r.method
      ),
    "each $1 test card is saved: one setup per account, succeeded, test mode",
  );
  check(
    Number(
      await sql(`select count(*) from app.challenge_commitment_customers_v1 where not livemode
        and actor_id in (${actors.map((a) => literal(a.id)).join(",")})`),
    ) === labels.length,
    "one Stripe test customer per account is recorded",
  );
  const setupWebhook = cards["met"]!.webhookFirst!;
  check(
    setupWebhook.applied.status === 200 && setupWebhook.applied.body.disposition === "applied" &&
      setupWebhook.duplicate.status === 200 &&
      setupWebhook.duplicate.body.disposition === "duplicate",
    "a signed setup_intent.succeeded webhook applies once; its duplicate is ignored",
  );
  let stripeCharges = 0;
  for (const card of Object.values(cards)) {
    stripeCharges += (await paymentIntentsFor(card.customerId)).length;
  }
  check(
    stripeCharges === 0 && await chargeCount() === 0,
    "saving the cards charged nothing: no Stripe payments, no charge rows",
  );

  // ======================================================= commit
  await clock("2026-11-02T12:00:00Z");
  const goals: Record<string, Goal> = {};
  for (const label of labels) {
    await ready(people[label]!);
    goals[label] = await commit(people[label]!, cards[label]!, "2026-11-04");
  }
  const sample = goals["shortfall"]!;
  const block = sample.terms.commitment;
  check(
    block.amount_cents === 100 && block.currency === "usd" && block.recipient === "gametime" &&
      block.recipient_version === "gametime_recipient_v1" &&
      block.charge_rule === "one_charge_after_confirmed_miss_v1" &&
      block.proof_rule === "complete_window_v1" && block.provider === "stripe_sandbox" &&
      sample.terms.config.amount_cents === 100,
    "frozen terms: $1, GameTime as recipient, one charge after a confirmed miss, complete_window_v1",
  );
  const digests = JSON.parse(
    await sql(`select json_agg(json_build_object(
        'stored', agreement.terms_digest,
        'recomputed', encode(extensions.digest(terms.terms::text, 'sha256'), 'hex'),
        'consent', consent.digest,
        'setup', setup.status, 'amount', agreement.amount_cents))
      from app.challenge_commitment_agreements_v1 agreement
      join app.challenge_agreements_v1 terms on terms.challenge_id = agreement.challenge_id and terms.version = 1
      join app.challenge_consents_v1 consent on consent.challenge_id = agreement.challenge_id
      join app.challenge_commitment_setups_v1 setup on setup.id = agreement.setup_id
      where agreement.actor_id in (${actors.map((a) => literal(a.id)).join(",")})`),
  );
  check(
    digests.length === labels.length &&
      digests.every((d: any) =>
        d.stored === d.recomputed && d.stored === d.consent && d.setup === "consumed" &&
        d.amount === 100
      ) &&
      Object.values(goals).every((g) => digests.some((d: any) => d.stored === g.digest)),
    "each agreement's digest matches the terms, the consent and the preview; the card is used up",
  );
  const secondCard = await setup(people["met"]!, crypto.randomUUID());
  check(
    secondCard.status === 422 && secondCard.body?.message === "challenge_commitment_limit",
    "an open committed goal blocks another commitment",
  );
  stripeCharges = 0;
  for (const goal of Object.values(goals)) {
    stripeCharges += (await paymentIntentsFor(goal.customerId)).length;
  }
  check(stripeCharges === 0 && await chargeCount() === 0, "committing charged nothing");
  check(
    (await ownerStatus(sample)).state === "committed",
    "the owner reads the goal as committed",
  );

  // ======================================================= the window
  await clock("2026-11-04T12:00:00Z");
  await work();
  check(
    (await Promise.all(Object.values(goals).map(lobbyStatus))).every((s) => s === "active"),
    "every committed goal is active in its window",
  );
  // Met partway through the day counts.
  await progress(goals["met"]!, 9_100);
  // A total through noon only, never completed.
  await progress(goals["partial window"]!, 3_000);
  // After the window: a complete-day total below the goal.
  await clock("2026-11-05T06:00:00Z");
  await work();
  for (const label of ["shortfall", "shortfall, lost reply", "decline"]) {
    await progress(goals[label]!, 6_500);
  }
  check(await chargeCount() === 0, "nothing is charged before the goals are final");

  // ======================================================= provisional and final
  await clock("2026-11-07T00:00:01Z");
  await work();
  await clock("2026-11-09T00:00:02Z");
  await work();
  const finals: Record<string, { status: string; outcome: string; person: string }> = {};
  for (const label of labels) {
    const goal = goals[label]!;
    const raw = await sql(
      `select result from app.challenge_finals_v1 where challenge_id=${literal(goal.id)}`,
    );
    const result = raw ? JSON.parse(raw) : null;
    finals[label] = {
      status: await lobbyStatus(goal),
      outcome: result?.outcome,
      person: result?.participants?.[goal.actor.id]?.status,
    };
  }
  check(
    finals["met"]!.status === "final" && finals["met"]!.outcome === "scored" &&
      finals["met"]!.person === "met" && await chargeRow(goals["met"]!) === null,
    "met: final, met, no charge",
  );
  for (const label of ["no data", "partial window"]) {
    check(
      finals[label]!.status === "void" && await chargeRow(goals[label]!) === null,
      `${label}: the goal voids and nothing is charged`,
    );
  }
  for (const label of ["shortfall", "shortfall, lost reply", "decline"]) {
    const row = await chargeRow(goals[label]!);
    check(
      finals[label]!.status === "final" && finals[label]!.outcome === "scored" &&
        finals[label]!.person === "missed" && row?.status === "pending" &&
        row.amount_cents === 100 && row.keyed && row.attempt_count === 0 && !row.livemode,
      `${label}: a complete-day shortfall is final as a miss and queues one pending $1 charge`,
    );
  }
  check(await chargeCount() === 3, "exactly three charges are queued: one per confirmed miss");
  // A second finality pass can't queue a second charge.
  await work();
  check(await chargeCount() === 3, "reprocessing after finality queues nothing more");
  for (const label of ["met", "no data", "partial window"]) {
    check(
      (await ownerStatus(goals[label]!)).state === "not_charged",
      `${label}: the owner reads "not charged"`,
    );
  }

  // ======================================================= kill switch
  await ok("challenge_commitment_set_runtime_v1", { p_enabled: false }, null);
  const killed = await dispatch();
  const statusWhileOff = await ownerStatus(goals["shortfall"]!);
  check(
    killed.status === 200 && killed.body.claimed === 0 &&
      (await chargeRow(goals["shortfall"]!)).status === "pending" &&
      statusWhileOff.state === "charge_processing" && statusWhileOff.amount_cents === 100,
    "switch off: dispatch claims nothing, the charge stays pending, the owner still reads it",
  );
  const offAvailability = await ok("challenge_commitment_availability_v1", {}, people["met"]!);
  check(
    offAvailability.available === false &&
      offAvailability.reason === "challenge_commitment_unavailable",
    "switch off: new commitments are unavailable",
  );
  await ok("challenge_commitment_set_runtime_v1", { p_enabled: true }, null);

  // ======================================================= send the charges
  // The lost-reply goal's first attempt reaches Stripe, but its reply is lost.
  const lostReplyGoal = goals["shortfall, lost reply"]!.id;
  const lossy: CommitmentChargeGateway = {
    async createAndConfirm(claim) {
      const result = await chargeGateway.createAndConfirm(claim);
      if (claim.challengeId === lostReplyGoal) throw new CommitmentTransportAmbiguousError();
      return result;
    },
  };
  const first = await dispatch(lossy);
  check(
    first.status === 200 && first.body.claimed === 3 && first.body.succeeded === 1 &&
      first.body.failed === 1 && first.body.transport_ambiguous === 1,
    "first dispatch: one succeeded, one declined, one reply lost",
  );
  const paid = await chargeRow(goals["shortfall"]!);
  const paidIntent = await stripe.paymentIntents.retrieve(paid.stripe_payment_intent_id);
  check(
    paid.status === "succeeded" && paidIntent.status === "succeeded" &&
      paidIntent.livemode === false && paidIntent.amount === 100 && paidIntent.currency === "usd",
    "shortfall: the charge succeeded in Stripe test mode (livemode=false), $1",
  );
  const declined = await chargeRow(goals["decline"]!);
  check(
    declined.status === "failed" && declined.failure_code === "card_declined" &&
      declined.attempt_count === 1,
    "decline: the off-session charge failed with card_declined",
  );
  const lost = await chargeRow(goals["shortfall, lost reply"]!);
  check(
    lost.status === "processing" && lost.attempt_count === 1 && lost.stripe_payment_intent_id === null,
    "lost reply: the charge waits to be retried with the same key",
  );
  const second = await dispatch();
  const recovered = await chargeRow(goals["shortfall, lost reply"]!);
  const recoveredIntents = await paymentIntentsFor(goals["shortfall, lost reply"]!.customerId);
  check(
    second.status === 200 && second.body.claimed === 1 && second.body.succeeded === 1 &&
      recovered.status === "succeeded" && recovered.attempt_count === 2 &&
      recoveredIntents.length === 1 && recoveredIntents[0]!.id === recovered.stripe_payment_intent_id,
    "lost reply: the retry reuses the idempotency key and Stripe returns the same payment, not a second one",
  );
  const third = await dispatch();
  check(
    third.status === 200 && third.body.claimed === 0,
    "dispatching again claims nothing: succeeded charges are never resent",
  );
  // A worker that crashed after Stripe answered would resend the same key.
  const replayed = await chargeGateway.createAndConfirm({
    chargeId: await sql(
      `select id from app.challenge_commitment_charges_v1 where challenge_id=${
        literal(goals["shortfall"]!.id)
      }`,
    ),
    challengeId: goals["shortfall"]!.id,
    amountCents: 100,
    currency: "usd",
    idempotencyKey: `gt:challenge-commitment:v1:${goals["shortfall"]!.id}:${people["shortfall"]!.id}`,
    stripeCustomerId: goals["shortfall"]!.customerId,
    stripePaymentMethodId: await sql(
      `select stripe_payment_method_id from app.challenge_commitment_agreements_v1 where challenge_id=${
        literal(goals["shortfall"]!.id)
      }`,
    ),
  });
  const shortfallIntents = await paymentIntentsFor(goals["shortfall"]!.customerId);
  check(
    shortfallIntents.length === 1 && replayed.status === "succeeded" &&
      replayed.stripePaymentIntentId === paid.stripe_payment_intent_id,
    "resending the same idempotency key returns the same payment; Stripe holds one",
  );
  const declinedIntents = await paymentIntentsFor(goals["decline"]!.customerId);
  check(
    (await chargeRow(goals["decline"]!)).attempt_count === 1 && declinedIntents.length === 1,
    "decline: no retry, one Stripe attempt only",
  );

  // ======================================================= decline blocks
  const unpaid = await setup(people["decline"]!, crypto.randomUUID());
  const unpaidAvailability = await ok("challenge_commitment_availability_v1", {}, people["decline"]!);
  check(
    unpaid.status === 422 && unpaid.body?.message === "challenge_commitment_unpaid" &&
      unpaidAvailability.reason === "challenge_commitment_unpaid",
    "decline: new commitments are blocked with challenge_commitment_unpaid",
  );
  const declinedStatus = await ownerStatus(goals["decline"]!);
  check(
    declinedStatus.state === "charge_failed" && declinedStatus.failure_code === "card_declined",
    "decline: the owner reads the failed charge",
  );

  // ======================================================= webhooks
  const paidEvent = event("payment_intent.succeeded", paid.stripe_payment_intent_id);
  const paidOnce = await webhook(paidEvent);
  const paidTwice = await webhook(paidEvent);
  check(
    paidOnce.status === 200 && paidOnce.body.disposition === "ignored" &&
      paidTwice.body.disposition === "duplicate" &&
      (await chargeRow(goals["shortfall"]!)).status === "succeeded",
    "payment_intent.succeeded: a succeeded charge is left as is; the duplicate is ignored",
  );
  const failedEvent = event("payment_intent.payment_failed", declined.stripe_payment_intent_id);
  const failedOnce = await webhook(failedEvent);
  const failedTwice = await webhook(failedEvent);
  const afterFailedWebhook = await chargeRow(goals["decline"]!);
  check(
    failedOnce.body.disposition === "applied" && failedTwice.body.disposition === "duplicate" &&
      afterFailedWebhook.status === "failed" && afterFailedWebhook.attempt_count === 1,
    "payment_intent.payment_failed: applied once, the charge stays failed, no retry; the duplicate is ignored",
  );
  const forged = await webhook(event("payment_intent.succeeded", paid.stripe_payment_intent_id), "whsec_" + "0".repeat(32));
  check(forged.status === 401, "a webhook with a bad signature is refused");
  const live = await webhook(event("payment_intent.succeeded", paid.stripe_payment_intent_id, true));
  check(live.status === 403, "a live-mode webhook event is refused");
  const receipts = JSON.parse(
    await sql(`select json_object_agg(disposition, n) from (select disposition, count(*) n
      from app.challenge_commitment_webhook_receipts_v1 group by disposition) r`),
  );
  check(
    receipts.applied === 2 && receipts.ignored === 1 && receipts.duplicate === undefined,
    "webhook receipts: each event recorded once (duplicates add no row)",
  );

  // ======================================================= owner status and totals
  check(
    (await ownerStatus(goals["shortfall"]!)).state === "charged" &&
      (await ownerStatus(goals["shortfall, lost reply"]!)).state === "charged",
    "shortfall: the owner reads the goal as charged",
  );
  let allIntents = 0;
  for (const goal of Object.values(goals)) allIntents += (await paymentIntentsFor(goal.customerId)).length;
  check(
    allIntents === 3 && await chargeCount() === 3,
    "in total: three Stripe test payments for three confirmed misses, none for met or void goals",
  );
  check(
    await sql(`select bool_and(not livemode) from app.challenge_commitment_charges_v1`) === "t",
    "every charge row is test mode",
  );

  for (const label of labels) {
    const goal = goals[label]!;
    const row = await chargeRow(goal);
    outcomes[label] = {
      goal: finals[label]!.status,
      result: finals[label]!.outcome ?? null,
      person: finals[label]!.person ?? null,
      charge: row?.status ?? "none",
      failure_code: row?.failure_code ?? null,
      attempts: row?.attempt_count ?? 0,
      owner_reads: (await ownerStatus(goal)).state,
      stripe_payments: (await paymentIntentsFor(goal.customerId)).length,
    };
  }
  if (emulator !== undefined) {
    outcomes["stripe emulator"] = { ...emulator.counts };
  }
  console.log(
    JSON.stringify({ stripe: mode, checks: checks.length, outcomes }, null, 2),
  );
} finally {
  await sql(priorClock);
  await ok("challenge_commitment_set_runtime_v1", { p_enabled: runtimeBefore === "t" }, null)
    .catch(() => {});
  const restored = await sql(
    "select enabled from app.challenge_commitment_runtime_v1 where singleton",
  ).catch(() => "unknown");
  console.log(`Commitment switch restored to its starting state: ${restored === runtimeBefore}`);
  await ok("challenge_real_health_runtime_v1", {
    p_admission_enabled: false,
    p_ingestion_enabled: false,
    p_processing_enabled: false,
  }, null).catch(() => {});
  if (actors.length) {
    await sql(
      `delete from auth.sessions where user_id in (${actors.map((a) => literal(a.id)).join(",")})`,
    );
  }
  await emulator?.server.shutdown();
}
