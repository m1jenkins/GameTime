/** Synthetic App Attest -> actual Edge handler -> owned PostgREST -> SQL.
 * Requires the private manifest created by p8-real-health-verify.py. It never
 * reads physical Health data or accepts a hosted URL. Test clock replacements
 * are confined to this disposable DB and restored in finally.
 */
import { assert, assertEquals } from "@std/assert";
import {
  buildAssertion,
  makeDevice,
} from "../supabase/functions/_test/appattest_fixtures.ts";
import { mintAccessToken } from "../supabase/functions/_test/tokens.ts";
import { toHex, utf8 } from "../supabase/functions/_shared/bytes.ts";
import { deviceKeyLookup } from "../supabase/functions/_shared/database.ts";
import { createAccessTokenVerifier } from "../supabase/functions/_shared/jwt.ts";
import {
  realHealthDatabase,
  realHealthReadinessDatabase,
} from "../supabase/functions/ingest-challenge-health/database.ts";
import { createIngestChallengeHealthHandler } from "../supabase/functions/ingest-challenge-health/handler.ts";

const metric = Deno.args[1] ?? "steps";
assert(
  ["steps", "distance", "timed"].includes(metric),
  "only available real metric software checks",
);
const source = metric === "steps"
  ? "apple_watch_steps_v1"
  : metric === "distance"
  ? "apple_workout_outdoor_distance_v1"
  : "apple_workout_outdoor_timed_v1";
const selectedDistance = metric === "timed" ? { distance_mm: 5_000_000 } : {};
const target = metric === "timed"
  ? 300
  : metric === "distance"
  ? 1_000_000
  : 100;
const initialValue = metric === "distance" ? 2_000_000 : 200;
const correctedValue = metric === "distance" ? 1_500_000 : 150;
const retainActive = Deno.args[2] === "--retain-active";
assert(Deno.args[2] === undefined || retainActive, "unknown test option");
const manifestPath = Deno.args[0];
assert(
  manifestPath && manifestPath.startsWith("/private/tmp/"),
  "owned private manifest required",
);
const stat = await Deno.stat(manifestPath);
assert(
  stat.mode !== null && (stat.mode & 0o077) === 0,
  "private manifest permissions",
);
const manifest = JSON.parse(await Deno.readTextFile(manifestPath));
assert(/^gametime-p8-real-health-[a-f0-9]+$/.test(manifest.owner));
const inspect = await new Deno.Command("docker", {
  args: ["inspect", manifest.db],
  stdout: "piped",
  stderr: "piped",
}).output();
assert(inspect.success);
const container = JSON.parse(new TextDecoder().decode(inspect.stdout))[0];
assertEquals(container.Config.Labels.owner, manifest.owner);
assertEquals(container.HostConfig.PortBindings["5432/tcp"], [{
  HostIp: "127.0.0.1",
  HostPort: String(manifest.db_port),
}]);
assert(
  Number.isInteger(manifest.rest_port) && manifest.rest_port > 0 &&
    manifest.rest_port < 65536,
);

async function sql(query: string): Promise<string> {
  const child = new Deno.Command("docker", {
    args: [
      "exec",
      "-i",
      manifest.db,
      "psql",
      "-XqAt",
      "-v",
      "ON_ERROR_STOP=1",
      "-U",
      "postgres",
      "-d",
      "postgres",
    ],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(utf8(query));
  await writer.close();
  const result = await child.output();
  if (!result.success) {
    throw new Error(
      "P8 synthetic SQL control failed: " +
        new TextDecoder().decode(result.stderr),
    );
  }
  return new TextDecoder().decode(result.stdout).trim();
}
const literal = (value: string) => "'" + value.replaceAll("'", "''") + "'";
const ids = [crypto.randomUUID(), crypto.randomUUID()];
const sessions = [crypto.randomUUID(), crypto.randomUUID()];
const devices = [await makeDevice(), await makeDevice()];
const handles = ids.map((id) => "p8http" + id.replaceAll("-", "").slice(0, 12));
const appId = "ABCDE12345.test.gametime.app";
const issuer = `http://127.0.0.1:${manifest.auth_port}/auth/v1`;
async function token(
  index: number,
  expires = Math.floor(Date.now() / 1000) + 3600,
) {
  return await mintAccessToken(ids[index]!, {
    secret: manifest.jwt_secret,
    claims: {
      sub: ids[index],
      role: "authenticated",
      session_id: sessions[index],
      exp: expires,
      aud: "authenticated",
      iss: issuer,
    },
  });
}
const serviceKey = await mintAccessToken(null, {
  secret: manifest.jwt_secret,
  role: "service_role",
});
const priorClock = await sql(
  "select pg_get_functiondef('app.challenge_real_health_now_v1()'::regprocedure)",
);
async function clock(time: string) {
  await sql(
    `create or replace function app.challenge_real_health_now_v1() returns timestamptz language sql stable set search_path='' as $$ select ${
      literal(time)
    }::timestamptz $$;`,
  );
}
let handler: (request: Request) => Promise<Response>;
const server = Deno.serve(
  { hostname: "127.0.0.1", port: 0, onListen() {} },
  (request) => {
    const path = new URL(request.url).pathname;
    if (path === "/functions/v1/ingest-challenge-health") {
      return handler(
        request,
      );
    }
    if (path.startsWith("/rest/v1/")) {
      const target = new URL(request.url);
      const targetURL = `http://127.0.0.1:${manifest.rest_port}${
        target.pathname.slice(8)
      }${target.search}`;
      return fetch(new Request(targetURL, request), { redirect: "error" });
    }
    return new Response(null, { status: 404 });
  },
);
const origin = `http://127.0.0.1:${(server.addr as Deno.NetAddr).port}`;
const database = { url: origin, serviceRoleKey: serviceKey };
function edge(enabled: boolean) {
  return createIngestChallengeHealthHandler({
    enabled,
    appId,
    verifyToken: createAccessTokenVerifier({
      kind: "legacy-hs256",
      secret: manifest.jwt_secret,
      expectedIssuer: issuer,
      expectedAudience: "authenticated",
    }),
    publicKeyFor: deviceKeyLookup(database, ["development"]),
    ingest: realHealthDatabase(database),
    readiness: realHealthReadinessDatabase(database),
  });
}
handler = edge(true);
const checks: string[] = [];
function check(condition: unknown, label: string) {
  assert(condition, label);
  checks.push(label);
  console.log("PASS " + label);
}

async function rpc(
  name: string,
  payload: unknown,
  index: number | null = null,
) {
  const response = await fetch(`${origin}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${
        index === null ? serviceKey : await token(index)
      }`,
    },
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  const result = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(
      `${name} HTTP ${response.status}: ${result?.message ?? "refused"}`,
    );
  }
  return result;
}
let cid: string;
async function command(
  index: number,
  op: string,
  fields: Record<string, unknown> = {},
) {
  const revision = Number(
    await sql(
      `select revision from app.challenge_lobbies_v1 where id=${literal(cid)}`,
    ),
  );
  return rpc("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: { op, id: cid, revision, ...fields },
  }, index);
}
const count = [0, 0];
async function signed(index: number, body: Record<string, unknown>) {
  const bytes = utf8(JSON.stringify(body));
  const assertion = await buildAssertion(devices[index]!, bytes, {
    appId,
    signCount: ++count[index]!,
  });
  return {
    bytes,
    key: btoa(String.fromCharCode(...devices[index]!.keyId)),
    assertion: btoa(String.fromCharCode(...assertion.assertionObject)),
  };
}
async function upload(
  index: number,
  material: Awaited<ReturnType<typeof signed>>,
  status = 200,
  authToken?: string,
) {
  const response = await fetch(
    `${origin}/functions/v1/ingest-challenge-health`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${authToken ?? await token(index)}`,
        "content-type": "application/json",
        "x-gametime-key-id": material.key,
        "x-gametime-assertion": material.assertion,
      },
      body: material.bytes,
    },
  );
  const result = await response.json();
  assertEquals(
    response.status,
    status,
    `signed ingestion HTTP status (${result.error ?? "receipt"}: ${
      result.message ?? "saved"
    })`,
  );
  return result;
}

try {
  for (let i = 0; i < 2; i++) {
    await sql(`insert into auth.users(id) values(${literal(ids[i]!)});
      insert into public.profiles(id,handle,display_name,timezone) values(${
      literal(ids[i]!)
    },${literal(handles[i]!)},'Synthetic P8','UTC');
      insert into auth.sessions(id,user_id) values(${literal(sessions[i]!)},${
      literal(ids[i]!)
    });
      insert into public.device_attestations(key_id,user_id,public_key,environment) values(decode('${
      toHex(devices[i]!.keyId)
    }','hex'),${literal(ids[i]!)},decode('${
      toHex(devices[i]!.publicKey)
    }','hex'),'development');
      insert into app.device_attestation_receipts(key_id,initial_receipt,current_receipt,current_receipt_verified_at) values(decode('${
      toHex(devices[i]!.keyId)
    }','hex'),'\\x01','\\x01',clock_timestamp());`);
    await rpc("challenge_command_v1", {
      p_request_id: crypto.randomUUID(),
      p_payload: { op: "confirm_age", confirmed: true },
    }, i);
  }
  await sql(
    `insert into public.friendships(user_a,user_b,requested_by,status) values(least(${
      literal(ids[0]!)
    }::uuid,${literal(ids[1]!)}::uuid),greatest(${literal(ids[0]!)}::uuid,${
      literal(ids[1]!)
    }::uuid),${literal(ids[0]!)},'accepted')`,
  );
  await rpc("challenge_real_health_runtime_v1", {
    p_admission_enabled: true,
    p_ingestion_enabled: true,
    p_processing_enabled: true,
  });
  await clock("2026-10-01T12:00:00Z");
  for (let i = 0; i < 2; i++) {
    const receipt = await upload(
      i,
      await signed(i, {
        contract_version: 1,
        actor_id: ids[i],
        source_policy_version: source,
        ...selectedDistance,
        observed_at: "2026-10-01T12:00:00Z",
        request_id: crypto.randomUUID(),
      }),
    );
    check(
      receipt.version === "challenge_real_health_readiness_receipt_v1",
      "real readiness accepted without uploading baseline or history",
    );
  }
  cid = (await rpc("challenge_command_v1", {
    p_request_id: crypto.randomUUID(),
    p_payload: {
      op: "create",
      policy: `friend_${metric}_goal_v1`,
      source_policy_version: source,
      config: {
        start_date: "2026-10-03",
        days: 1,
        timezone: "UTC",
        amount_cents: 100,
        ...selectedDistance,
      },
    },
  }, 0)).id;
  await command(0, "target", { target });
  await command(0, "invite", { username: handles[1] });
  await command(1, "target", { target });
  await command(0, "select", { actor_id: ids[1], selected: true });
  await command(0, "freeze");
  const detail = await rpc("challenge_detail_v1", { p_id: cid }, 0);
  const digest = detail.agreement.digest;
  check(
    detail.agreement.terms.source === source,
    "new agreement freezes real policy before consent",
  );
  for (let i = 0; i < 2; i++) {
    await command(i, "consent", { consent: true, digest });
  }
  await clock("2026-10-03T12:00:00Z");
  await rpc("challenge_process_v1", { p_id: cid });
  const payload = (
    i: number,
    revision: number,
    value: number | null = initialValue,
    state = "value",
  ) => ({
    contract_version: 1,
    actor_id: ids[i],
    challenge_id: cid,
    agreement_version: 1,
    terms_digest: digest,
    source_policy_version: source,
    metric,
    ...selectedDistance,
    window_starts_at: "2026-10-03T00:00:00Z",
    window_ends_at: "2026-10-04T00:00:00Z",
    request_id: crypto.randomUUID(),
    revision,
    previous_revision: revision === 1 ? null : revision - 1,
    state,
    value,
    observed_at: "2026-10-03T12:00:00Z",
    queried_through_at: "2026-10-03T12:00:00Z",
  });
  const original = await signed(0, payload(0, 1));
  const originalReceipt = await upload(0, original);
  check(
    originalReceipt.revision === 1,
    `signed ${metric} accepted through actual handler and RPC`,
  );
  check(
    (await rpc("challenge_detail_v1", { p_id: cid }, 0)).members
      .find((member: { actor_id: string }) => member.actor_id === ids[0])?.fact
      ?.value === initialValue,
    "ordinary participant projection exposes the real progress value",
  );
  await upload(1, await signed(1, payload(1, 1)));
  check(
    await sql(
      `select count(*) from app.challenge_facts_v1 where challenge_id=${
        literal(cid)
      }`,
    ) ===
      "0",
    "real facts never enter fictional storage",
  );
  handler = edge(false);
  check(
    JSON.stringify(await upload(0, original)) ===
      JSON.stringify(originalReceipt),
    "lost response recovers exact committed receipt while Edge disabled",
  );
  await upload(0, await signed(0, payload(0, 2, correctedValue)), 403);
  handler = edge(true);
  await upload(0, original, 403, await token(1));
  await upload(
    0,
    original,
    401,
    await token(0, Math.floor(Date.now() / 1000) - 1),
  );
  const wrongBinding = await signed(0, {
    ...payload(0, 2, correctedValue),
    terms_digest: "0".repeat(64),
  });
  await upload(0, wrongBinding, 422);
  if (metric === "timed") {
    await upload(
      0,
      await signed(0, {
        ...payload(0, 2, correctedValue),
        distance_mm: 10_000_000,
      }),
      422,
    );
    check(true, "timed record must match the frozen selected distance");
  }
  await upload(0, await signed(0, payload(0, 2, correctedValue)));
  check(
    await sql(
      `select value from app.challenge_real_health_facts_v1 where challenge_id=${
        literal(cid)
      } and actor_id=${literal(ids[0]!)} order by revision desc limit 1`,
    ) === String(correctedValue),
    "downward correction replaces rather than maximizes",
  );
  check(
    (await rpc("challenge_detail_v1", { p_id: cid }, 0)).members
      .find((member: { actor_id: string }) => member.actor_id === ids[0])?.fact
      ?.value === correctedValue,
    "ordinary participant projection reflects the downward correction",
  );
  if (!retainActive) {
    await clock("2026-10-06T00:00:01Z");
    await rpc("challenge_process_v1", { p_id: cid });
    const notice = JSON.parse(
      await sql(
        `select row_to_json(n) from app.challenge_notices_v1 n where challenge_id=${
          literal(cid)
        } order by revision desc limit 1`,
      ),
    );
    check(
      Date.parse(notice.review_by) - Date.parse(notice.recorded_at) ===
        48 * 3600_000,
      "review deadline is 48 hours after actual provisional notice",
    );
    await command(0, "review", {
      notice_revision: notice.revision,
      reason: "wrong_total",
    });
    check(
      await sql(
        `select bool_and(resolve_by-filed_at=interval '72 hours') from app.challenge_reviews_v1 where challenge_id=${
          literal(cid)
        }`,
      ) === "t",
      "resolution deadline starts at actual review filing",
    );
    await clock("2026-10-10T00:00:02Z");
    await rpc("challenge_process_v1", { p_id: cid });
    // Review timeout can publish a new safe result and must give its own full notice window.
    await clock("2026-10-13T00:00:03Z");
    await rpc("challenge_process_v1", { p_id: cid });
    check(
      await sql(
        `select count(*) from app.challenge_finals_v1 where challenge_id=${
          literal(cid)
        }`,
      ) ===
        "1",
      "real processing reaches final simulated history after review",
    );
    check(
      (await rpc("challenge_detail_v1", { p_id: cid }, 0)).id === cid,
      "participant can recover final history through authorized projection",
    );
    await sql(`delete from auth.sessions where id=${literal(sessions[0]!)}`);
    await upload(0, original, 403);
    check(true, "revoked current session cannot recover a committed response");
  }
  console.log(
    JSON.stringify({
      metric,
      retained_active_fixture: retainActive,
      checks: checks.length,
      synthetic_only: true,
      physical_data_used: false,
    }),
  );
} finally {
  await sql(priorClock);
  await rpc("challenge_real_health_runtime_v1", {
    p_admission_enabled: false,
    p_ingestion_enabled: false,
    p_processing_enabled: false,
  });
  await server.shutdown();
}
