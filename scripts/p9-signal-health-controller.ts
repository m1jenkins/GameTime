/** Owned loopback adapter for the ordinary --authenticated-app-local harness.
 * Uses P8's actual ingestion handler, real Auth/REST and synthetic App Attest.
 * No physical Health APIs, hosted hosts, or provider activity are permitted.
 */
import { assert, assertEquals } from "@std/assert";
import { buildAssertion, makeDevice } from "../supabase/functions/_test/appattest_fixtures.ts";
import { mintAccessToken } from "../supabase/functions/_test/tokens.ts";
import { toHex } from "../supabase/functions/_shared/bytes.ts";
import {
  deviceKeyLookup,
  postgrestActivityDiagnosticDatabase,
} from "../supabase/functions/_shared/database.ts";
import { createActivityDiagnosticHandler } from "../supabase/functions/activity-diagnostic/handler.ts";
import { createAccessTokenVerifier } from "../supabase/functions/_shared/jwt.ts";
import {
  realHealthDatabase,
  realHealthReadinessDatabase,
} from "../supabase/functions/ingest-challenge-health/database.ts";
import { createIngestChallengeHealthHandler } from "../supabase/functions/ingest-challenge-health/handler.ts";

const [manifestPath, outputPath] = Deno.args;
assert(manifestPath && manifestPath.startsWith("/private/tmp/"));
assert(outputPath && outputPath.startsWith("/private/tmp/"));
assertEquals((await Deno.stat(manifestPath)).mode! & 0o077, 0);
const manifest = JSON.parse(await Deno.readTextFile(manifestPath));
assert(/^gametime-p8-real-health-[a-f0-9]+$/.test(manifest.owner));
const inspected = await new Deno.Command("docker", {
  args: ["inspect", manifest.db],
  stdout: "piped",
}).output();
assert(inspected.success);
const container = JSON.parse(new TextDecoder().decode(inspected.stdout))[0];
assertEquals(container.Config.Labels.owner, manifest.owner);
assertEquals(container.HostConfig.PortBindings["5432/tcp"], [{
  HostIp: "127.0.0.1",
  HostPort: String(manifest.db_port),
}]);
const literal = (value: string) => "'" + value.replaceAll("'", "''") + "'";
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
  await writer.write(new TextEncoder().encode(query));
  await writer.close();
  const result = await child.output();
  if (!result.success) {
    throw new Error("Owned P9 SQL control failed: " + new TextDecoder().decode(result.stderr));
  }
  return new TextDecoder().decode(result.stdout).trim();
}
const service = await mintAccessToken(null, { secret: manifest.jwt_secret, role: "service_role" });
const controlToken = crypto.randomUUID() + crypto.randomUUID();
const password = crypto.randomUUID() + "!aA9";
const devices = await Promise.all(Array.from({ length: 8 }, () => makeDevice()));
const actors: Array<{ id: string; email: string; username: string }> = [];
const counters = devices.map(() => 0);
const inputs = devices.map(() => ({ mode: "value", value: 10001 }));
let now = "2026-10-01T12:00:00Z", lose = false, enabled = true;
const appId = "ABCDE12345.test.gametime.app";
const priorClock = await sql(
  "select pg_get_functiondef('app.challenge_real_health_now_v1()'::regprocedure)",
);
let handler: (request: Request) => Promise<Response>;
const trace: Array<{ endpoint: string; actor: string; bytes: number; status: number }> = [];
const paceTimes = new Map<string, number[]>();
async function pace(request: Request, path: string) {
  const limit = path.endsWith("challenge_community_catalog_v1")
    ? 13
    : path.endsWith("challenge_command_v1")
    ? 52
    : 0;
  if (!limit) return;
  const key = path + (request.headers.get("authorization") ?? "");
  const recent = (paceTimes.get(key) ?? []).filter((time) => time > Date.now() - 30500);
  if (recent.length >= limit) {
    await new Promise((resolve) =>
      setTimeout(resolve, Math.max(0, recent[0]! + 30500 - Date.now()))
    );
  }
  recent.push(Date.now());
  paceTimes.set(key, recent);
}
async function clock(value: string) {
  assert(Number.isFinite(Date.parse(value)));
  now = value;
  await sql(
    `create or replace function app.challenge_real_health_now_v1() returns timestamptz language sql stable set search_path='' as $$ select ${
      literal(value)
    }::timestamptz $$;`,
  );
}
const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });
const server = Deno.serve({ hostname: "127.0.0.1", port: 0, onListen() {} }, async (request) => {
  try {
    const url = new URL(request.url), path = url.pathname;
    if (path.startsWith("/p9/")) {
      if (request.headers.get("x-p9-control") !== controlToken) {
        return json({ error: "local_fixture_required" }, 403);
      }
      if (path === "/p9/input") {
        const actor = actors.findIndex((a) => a.id === url.searchParams.get("actor"));
        assert(actor >= 0);
        return json({ ...inputs[actor], now });
      }
      if (path === "/p9/clock") return json({ now });
      if (path === "/p9/sign") {
        const { actor, body } = await request.json();
        const index = actors.findIndex((a) => a.id === actor);
        assert(index >= 0);
        const bytes = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
        assert(bytes.length <= 65536);
        const assertion = await buildAssertion(devices[index]!, bytes, {
          appId,
          signCount: ++counters[index]!,
        });
        return json({
          key: btoa(String.fromCharCode(...devices[index]!.keyId)),
          assertion: btoa(String.fromCharCode(...assertion.assertionObject)),
        });
      }
      if (path === "/p9/control") {
        const action = await request.json();
        if (action.action === "clock") await clock(action.now);
        else if (action.action === "input") {
          assert(Number.isInteger(action.actor) && inputs[action.actor]);
          assert(["value", "deleted", "unresolved", "empty"].includes(action.mode));
          assert(
            Number.isInteger(action.value) && action.value >= 0 && action.value <= 1_000_000_000,
          );
          inputs[action.actor] = { mode: action.mode, value: action.value };
        } else if (action.action === "latest") {
          const actor = actors[action.actor];
          assert(actor);
          const value = await sql(
            `select jsonb_build_object('id',id,'status',status,'config',config) from app.challenge_lobbies_v1 where creator_id=${
              literal(actor.id)
            } and real_source_policy_version is not null order by created_at desc,id desc limit 1`,
          );
          return json(value ? JSON.parse(value) : {});
        } else if (action.action === "community") {
          assert(/^\d{4}-\d{2}-\d{2}$/.test(action.start));
          assert([2, 5].includes(action.minimum));
          const id = await sql(
            `set role service_role; select public.challenge_publish_community_real_health_v1('${crypto.randomUUID()}',${
              literal(actors[6]!.id)
            },${
              literal(
                JSON.stringify({
                  start_date: action.start,
                  days: 1,
                  timezone: "UTC",
                  amount_cents: 100,
                }),
              )
            }::jsonb,1000,${action.minimum},6,'apple_watch_steps_v1');`,
          );
          return json({ id });
        } else if (action.action === "community_snapshot") {
          assert(/^[a-f0-9-]{36}$/i.test(action.id));
          assertEquals(
            await sql(
              `select creator_id=${
                literal(actors[6]!.id)
              }::uuid from app.challenge_lobbies_v1 where id=${literal(action.id)}::uuid`,
            ),
            "t",
          );
          await sql(
            `set role service_role; select public.challenge_capture_community_snapshot_v1(${
              literal(action.id)
            }::uuid);`,
          );
        } else if (action.action === "tick") {
          assert(/^[a-f0-9-]{36}$/i.test(action.id));
          await sql(
            `set role service_role; select public.challenge_process_v1(${
              literal(action.id)
            }::uuid);`,
          );
        } else if (action.action === "lose") lose = true;
        else if (action.action === "gate") {
          enabled = action.enabled === true;
          handler = edge();
        } else if (action.action === "suspend") {
          const actor = actors[action.actor];
          assert(actor);
          await sql(
            `set app.challenge_write_v1='on'; insert into app.challenge_suspensions_v1 values(${
              literal(actor.id)
            },${action.suspended === true},${
              literal(actors[0]!.id)
            },'Owned synthetic check',app.challenge_now_v1()) on conflict(actor_id) do update set suspended=excluded.suspended,recorded_at=excluded.recorded_at;`,
          );
        } else if (action.action === "stats") {
          return json({ trace, counters, synthetic_only: true });
        } else return json({ error: "unknown_control" }, 400);
        return json({ saved: true, now });
      }
      return json({ error: "unknown_fixture_route" }, 404);
    }
    if (path === "/functions/v1/ingest-challenge-health") {
      const data = await request.clone().text();
      const body = JSON.parse(data);
      const response = await handler(request);
      trace.push({
        endpoint: body.contract_version === "readiness_v1"
          ? "readiness"
          : Object.hasOwn(body, "challenge_id")
          ? "activity"
          : "readiness",
        actor: body.actor_id,
        bytes: data.length,
        status: response.status,
      });
      if (lose && response.ok) {
        lose = false;
        return json({ error: "synthetic_response_loss" }, 503);
      }
      return response;
    }
    if (path === "/functions/v1/activity-diagnostic") {
      const bytes = (await request.clone().arrayBuffer()).byteLength;
      const response = await diagnostic(request);
      trace.push({ endpoint: "diagnostic", actor: "synthetic", bytes, status: response.status });
      if (lose && response.ok) {
        lose = false;
        return json({ error: "synthetic_response_loss" }, 503);
      }
      return response;
    }
    if (path.startsWith("/rest/v1/")) {
      await pace(request, path);
      return fetch(
        new Request(`http://127.0.0.1:${manifest.rest_port}${path.slice(8)}${url.search}`, request),
        { redirect: "error" },
      );
    }
    if (path.startsWith("/auth/v1/")) {
      return fetch(
        new Request(`http://127.0.0.1:${manifest.auth_port}${path.slice(8)}${url.search}`, request),
        { redirect: "error" },
      );
    }
    return json({ error: "not_found" }, 404);
  } catch (error) {
    console.error(String(error));
    return json({ error: "local_control_failed" }, 500);
  }
});
const origin = `http://127.0.0.1:${(server.addr as Deno.NetAddr).port}`;
const database = { url: origin, serviceRoleKey: service };
function edge() {
  return createIngestChallengeHealthHandler({
    enabled,
    appId,
    verifyToken: createAccessTokenVerifier({
      kind: "legacy-hs256",
      secret: manifest.jwt_secret,
      expectedIssuer: `http://127.0.0.1:${manifest.auth_port}/auth/v1`,
      expectedAudience: "authenticated",
    }),
    publicKeyFor: deviceKeyLookup(database, ["development"]),
    ingest: realHealthDatabase(database),
    readiness: realHealthReadinessDatabase(database),
  });
}
handler = edge();
const diagnostic = createActivityDiagnosticHandler({
  appId,
  database: postgrestActivityDiagnosticDatabase(database),
  publicKeyFor: deviceKeyLookup(database, ["development"]),
  verifyToken: createAccessTokenVerifier({
    kind: "legacy-hs256",
    secret: manifest.jwt_secret,
    expectedIssuer: `http://127.0.0.1:${manifest.auth_port}/auth/v1`,
    expectedAudience: "authenticated",
  }),
});
try {
  for (let index = 0; index < devices.length; index++) {
    const email = `p9-${crypto.randomUUID()}@example.invalid`;
    const response = await fetch(`http://127.0.0.1:${manifest.auth_port}/admin/users`, {
      method: "POST",
      headers: { authorization: `Bearer ${service}`, "content-type": "application/json" },
      body: JSON.stringify({ email, password, email_confirm: true, role: "authenticated" }),
    });
    assert(response.ok, "owned Auth actor creation");
    const user = await response.json();
    const id = user.id, username = "p9_" + crypto.randomUUID().replaceAll("-", "").slice(0, 12);
    actors.push({ id, email, username });
    await sql(
      `insert into public.profiles(id,handle,display_name,timezone) values(${literal(id)},${
        literal(username)
      },'Synthetic P9','UTC');
      insert into public.device_attestations(key_id,user_id,public_key,environment) values(decode('${
        toHex(devices[index]!.keyId)
      }','hex'),${literal(id)},decode('${toHex(devices[index]!.publicKey)}','hex'),'development');
      insert into app.device_attestation_receipts(key_id,initial_receipt,current_receipt,current_receipt_verified_at) values(decode('${
        toHex(devices[index]!.keyId)
      }','hex'),'\\x01','\\x01',clock_timestamp());`,
    );
  }
  for (const actor of actors.slice(1)) {
    await sql(
      `insert into public.friendships(user_a,user_b,requested_by,status) values(least(${
        literal(actors[0]!.id)
      }::uuid,${literal(actor.id)}::uuid),greatest(${literal(actors[0]!.id)}::uuid,${
        literal(actor.id)
      }::uuid),${literal(actors[0]!.id)},'accepted');`,
    );
  }
  await sql(
    `set app.challenge_write_v1='on'; update app.challenge_runtime_v1 set admission=true,fixtures=true,actors=array[${
      actors.map((a) => literal(a.id) + "::uuid").join(",")
    }];
    insert into app.challenge_access_v1 select id,clock_timestamp() from public.profiles where id in (${
      actors.map((a) => literal(a.id)).join(",")
    }) on conflict do nothing;
    set role service_role; select public.challenge_real_health_runtime_v1(true,true,true);`,
  );
  await clock(now);
  await Deno.writeTextFile(
    outputPath,
    JSON.stringify({
      url: origin,
      key: "sb_publishable_p9_synthetic_loopback",
      controlToken,
      password,
      actors,
      synthetic_only: true,
      owner: manifest.owner,
    }),
    { mode: 0o600, createNew: true },
  );
  console.log("P9 owned loopback controller ready; manifest written privately.");
  await new Promise<void>((resolve) => {
    Deno.addSignalListener("SIGTERM", resolve);
    Deno.addSignalListener("SIGINT", resolve);
  });
} finally {
  await sql(priorClock);
  await sql(
    "set role service_role; select public.challenge_real_health_runtime_v1(false,false,false);",
  );
  if (actors.length) {
    await sql(
      `delete from auth.sessions where user_id in (${actors.map((a) => literal(a.id)).join(",")});`,
    );
  }
  await server.shutdown();
}
