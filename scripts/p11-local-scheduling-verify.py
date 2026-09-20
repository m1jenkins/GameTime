#!/usr/bin/env python3
"""Owned local verifier for the P11 Cron-to-Edge scheduling boundary.

``prepare`` creates an isolated P8 stack, advances it using the immutable P9
source snapshot, and leaves pg_cron globally disabled. ``apply-forward``
applies exactly one supplied P11 migration to both the retained populated
upgrade database and its independent fresh database. Nothing here can select a
hosted project or reuse a development stack.

The later bounded activation phase deliberately enables only the three P11
jobs, after every historical job has been deactivated through cron.alter_job.
Its Edge-process and machine-contract checks are kept separate from migration
setup so that a failed HTTP proof cannot be mistaken for a safe migration.
"""
import argparse
import base64
import hashlib
import hmac
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import sys
import time
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
P8_PATH = ROOT / "scripts" / "p8-real-health-verify.py"
P8_BASELINE = "848ef6ee02d95b57bdad4b36d3c7600a4ba3f192"
P9_BASELINE = "fa97cb26b5e13e6ebf86e9acebd02f255c3b50e8"
P11_JOB_NAMES = {
    "worker": "challenge-worker-v1",
    "snapshot": "challenge-snapshot-v1",
    "monitor": "challenge-monitor-v1",
}
OPERATING_FIXTURE = ROOT / "scripts" / "fixtures" / "p11-machine-operating.sql"
SELECTED_COMMUNITY_ID = "be000000-0000-0000-0000-000000052531"
UNSELECTED_COMMUNITY_ID = "be000000-0000-0000-0000-000000052532"
REAL_GOAL_ID = "be000000-0000-0000-0000-000000052530"


def load_p8():
    spec = importlib.util.spec_from_file_location("p8_real_health_verify", P8_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load the P8 owned-stack helpers")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


P8 = load_p8()


def write_private(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    os.chmod(path, 0o600)


def read_private(path):
    try:
        if path.stat().st_mode & 0o077:
            raise RuntimeError("manifest must be mode 0600")
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError("cannot read private P11 manifest") from error


def load_manifest(path):
    manifest = read_private(path)
    required = {"kind", "p8_manifest", "p9_migrations", "p9_agreement_digest",
                "receipt_dir", "state"}
    if manifest.get("kind") != "gametime-p11-local-scheduling-v1" or not required.issubset(manifest):
        raise RuntimeError("manifest is not a P11 local scheduling stack")
    if manifest.get("p9_baseline") != P9_BASELINE:
        raise RuntimeError("manifest P9 baseline does not match the immutable verifier baseline")
    base_path = Path(manifest["p8_manifest"])
    base = P8.load_manifest(base_path)
    # P8 helpers write receipts through this object. P11 owns all post-baseline
    # receipts, while the P8 preparation receipts stay alongside its manifest.
    base["receipt_dir"] = manifest["receipt_dir"]
    return manifest, base


def immutable_p9_migrations():
    paths = P8.command([
        "git", "diff", "--name-only", P8_BASELINE + ".." + P9_BASELINE,
        "--", "supabase/migrations",
    ]).stdout.splitlines()
    paths = sorted(path for path in paths if path.endswith(".sql"))
    if not paths:
        raise RuntimeError("immutable P9 migration set is unavailable")
    records = []
    for relative in paths:
        if not re.fullmatch(r"supabase/migrations/[0-9]{14}_[a-z0-9_]+[.]sql", relative):
            raise RuntimeError("immutable P9 contains an unexpected migration path")
        contents = P8.command(["git", "show", P9_BASELINE + ":" + relative]).stdout
        records.append({"path": relative, "sha256": hashlib.sha256(contents.encode()).hexdigest(),
                        "contents": contents})
    return records


def assert_cron_quiet(base, *, fresh=False):
    container = P8.prepare_fresh_test_database(base)["container"] if fresh else None
    if P8.sql(base, "show cron.launch_active_jobs", container=container) != "off":
        raise RuntimeError("pg_cron was enabled during a migration phase")
    if P8.sql(base, "select count(*) from cron.job_run_details", container=container) != "0":
        raise RuntimeError("a cron job ran during a migration phase")


def apply_sql_records(base, records, *, fresh=False, label_prefix=""):
    container = P8.prepare_fresh_test_database(base)["container"] if fresh else None
    for record in records:
        P8.sql(base, record["contents"], label_prefix + Path(record["path"]).name + ".log",
               single_transaction=True, container=container)
        assert_cron_quiet(base, fresh=fresh)


def expected_p9_records():
    return [{"path": row["path"], "sha256": row["sha256"]}
            for row in immutable_p9_migrations()]


def private_receipt_dir(path):
    receipt_dir = path.parent / (path.stem + "-receipts")
    receipt_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(receipt_dir, 0o700)
    return receipt_dir


def prepare(args):
    if args.manifest.exists():
        raise RuntimeError("prepare needs a new manifest path")
    p8_manifest = args.manifest.parent / (args.manifest.stem + "-p8-base.json")
    if p8_manifest.exists():
        raise RuntimeError("refusing to replace an existing P8 base manifest")
    # P8 prepares an owner-labelled network, loopback-only containers, random
    # private credentials and both populated/fresh databases. It starts pg_cron
    # disabled before *any* migration is applied.
    P8.prepare(SimpleNamespace(manifest=p8_manifest))
    base = P8.load_manifest(p8_manifest)
    receipt_dir = private_receipt_dir(args.manifest)
    base["receipt_dir"] = str(receipt_dir)
    try:
        assert_cron_quiet(base)
        assert_cron_quiet(base, fresh=True)
        records = immutable_p9_migrations()
        apply_sql_records(base, records)
        apply_sql_records(base, records, fresh=True, label_prefix="fresh-")
        if P8.agreement_digest(base) != base["baseline_agreement_digest"]:
            raise RuntimeError("immutable P9 migration changed populated historical agreements")
        assert_cron_quiet(base)
        assert_cron_quiet(base, fresh=True)
        manifest = {
            "kind": "gametime-p11-local-scheduling-v1",
            "p8_manifest": str(p8_manifest),
            "p9_baseline": P9_BASELINE,
            "p9_migrations": expected_p9_records(),
            "p9_agreement_digest": P8.agreement_digest(base),
            "receipt_dir": str(receipt_dir),
            "state": "p9_prepared",
        }
        write_private(args.manifest, manifest)
        print(json.dumps({"manifest": str(args.manifest), "state": manifest["state"],
                          "p9_migration_count": len(manifest["p9_migrations"])}, sort_keys=True))
    except BaseException:
        # The delegated cleanup validates the owner label before removal.
        try:
            P8.cleanup(p8_manifest, P8.load_manifest(p8_manifest))
        finally:
            args.manifest.unlink(missing_ok=True)
        raise


def forward_record(path):
    resolved = path.resolve()
    expected_parent = (ROOT / "supabase" / "migrations").resolve()
    if resolved.parent != expected_parent or not re.fullmatch(
            r"[0-9]{14}_challenge_machine_scheduling_v1[.]sql", resolved.name):
        raise RuntimeError("forward migration must be the one P11 scheduling migration")
    contents = resolved.read_text()
    if not contents.strip():
        raise RuntimeError("forward migration is empty")
    return {"path": str(resolved.relative_to(ROOT)),
            "sha256": hashlib.sha256(contents.encode()).hexdigest(), "contents": contents}


def active_jobs(base):
    rows = P8.sql(base, "select jobid::text || E'\\t' || jobname from cron.job where active order by jobid")
    return [] if not rows else [line.split("\t", 1) for line in rows.splitlines()]


def disable_all_jobs(base):
    # pg_cron explicitly documents cron.alter_job as the supported control.
    for jobid, _ in active_jobs(base):
        if not re.fullmatch(r"[0-9]+", jobid):
            raise RuntimeError("cron returned an invalid job id")
        P8.sql(base, "select cron.alter_job(" + jobid + ", active := false)", "cron-disable-" + jobid + ".log")
    if active_jobs(base):
        raise RuntimeError("a historical cron job remained active")


def p11_jobs(base):
    rows = P8.sql(base, "select jobid::text || E'\\t' || jobname || E'\\t' || active::text || E'\\t' || schedule "
                        "from cron.job where jobname = any(array['challenge-worker-v1','challenge-snapshot-v1','challenge-monitor-v1']) order by jobname")
    result = {}
    for row in ([] if not rows else rows.splitlines()):
        fields = row.split("\t")
        if len(fields) != 4 or fields[1] not in P11_JOB_NAMES.values() or not re.fullmatch(r"[0-9]+", fields[0]):
            raise RuntimeError("P11 cron registry has an invalid job row")
        if fields[1] in result:
            raise RuntimeError("P11 cron registry has a duplicate job name")
        result[fields[1]] = {"id": fields[0], "active": fields[2] == "true", "schedule": fields[3]}
    if set(result) != set(P11_JOB_NAMES.values()):
        raise RuntimeError("P11 migration did not register exactly the fixed scheduler jobs")
    expected_schedules = {"challenge-worker-v1": "* * * * *", "challenge-snapshot-v1": "*/15 * * * *",
                          "challenge-monitor-v1": "* * * * *"}
    if {name: row["schedule"] for name, row in result.items()} != expected_schedules:
        raise RuntimeError("P11 cron schedules differ from the bounded local defaults")
    return result


def assert_preserved(manifest, base):
    if manifest["p9_migrations"] != expected_p9_records():
        raise RuntimeError("immutable P9 migration record differs from this verifier")
    if P8.agreement_digest(base) != manifest["p9_agreement_digest"]:
        raise RuntimeError("a P11 operation changed populated historical agreements")


def apply_forward(args, manifest, base):
    if manifest["state"] not in ("p9_prepared", "forward_applied"):
        raise RuntimeError("forward migration requires a P9-prepared owned stack")
    assert_cron_quiet(base)
    assert_cron_quiet(base, fresh=True)
    record = forward_record(args.forward_migration)
    prior = manifest.get("forward_migration")
    if prior is not None and prior != {key: record[key] for key in ("path", "sha256")}:
        raise RuntimeError("forward migration bytes changed; rebuild the owned stack")
    if prior is None:
        apply_sql_records(base, [record])
        apply_sql_records(base, [record], fresh=True, label_prefix="fresh-")
        manifest["forward_migration"] = {key: record[key] for key in ("path", "sha256")}
        manifest["state"] = "forward_applied"
        write_private(args.manifest, manifest)
    disable_all_jobs(base)
    jobs = p11_jobs(base)
    if any(row["active"] for row in jobs.values()):
        raise RuntimeError("P11 jobs must be registered inactive")
    assert_preserved(manifest, base)
    print(json.dumps({"manifest": str(args.manifest), "state": manifest["state"],
                      "jobs": sorted(jobs)}, sort_keys=True))


def check(args, manifest, base):
    P8.inspect_owned(base, "network", base["network"])
    P8.check_loopback(base, base["db"], "5432/tcp", base["db_port"])
    P8.check_loopback(base, base["auth"], "9999/tcp", base["auth_port"])
    P8.check_loopback(base, base["rest"], "3000/tcp", base["rest_port"])
    fresh = P8.prepare_fresh_test_database(base)
    P8.inspect_owned(base, "container", fresh["container"])
    assert_preserved(manifest, base)
    if manifest["state"] == "p9_prepared":
        assert_cron_quiet(base)
        assert_cron_quiet(base, fresh=True)
    elif manifest["state"] in ("forward_applied", "bounded_complete"):
        recorded = manifest["forward_migration"]
        actual = forward_record(ROOT / recorded["path"])
        if recorded["sha256"] != actual["sha256"]:
            raise RuntimeError("checked migration bytes differ from the applied candidate")
        # The dedicated activation phase may create only P11 run details. No
        # historical cron job is ever allowed back on.
        if active_jobs(base):
            raise RuntimeError("a non-P11 cron job is active")
        jobs = p11_jobs(base)
        if manifest["state"] == "forward_applied" and any(row["active"] for row in jobs.values()):
            raise RuntimeError("forward-only stack left a P11 job active")
        if manifest["state"] == "bounded_complete":
            closed = P8.sql(base, """
              select (select not worker_enabled and not snapshot_enabled and not monitor_enabled and edge_base_url is null
                and community_id is null and worker_secret_id is null and monitor_secret_id is null
                from app.challenge_schedule_config_v1 where singleton)
              and (select not admission and not fixtures and not processing and not discovery and fictional_now is null
                and cardinality(actors)=0 from app.challenge_runtime_v1 where singleton)
              and (select not admission_enabled and not ingestion_enabled and not processing_enabled
                from app.challenge_real_health_runtime_v1 where singleton)
              and not exists(select 1 from cron.job_run_details d join cron.job j using(jobid)
                where j.jobname not in ('challenge-worker-v1','challenge-snapshot-v1','challenge-monitor-v1'));
            """)
            if closed != "t":
                raise RuntimeError("completed local acceptance did not leave every owned operating gate closed")
    else:
        raise RuntimeError("unknown P11 manifest state")
    if args.tap:
        P8.run_tap(base, args.tap, label_prefix="fresh-", container=fresh["container"])


def sql_literal(value):
    return "'" + value.replace("'", "''") + "'"


def service_jwt(secret, role="service_role"):
    """Mint the short-lived local service JWT without placing it on argv."""
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=").decode()
    now = int(time.time())
    header = encode(b'{"alg":"HS256","typ":"JWT"}')
    claims = encode(json.dumps({"role": role, "aud": "authenticated", "iat": now,
                                "exp": now + 300}, separators=(",", ":")).encode())
    signature = encode(hmac.new(secret.encode(), (header + "." + claims).encode(), hashlib.sha256).digest())
    return header + "." + claims + "." + signature


def stage_edge_runtime(manifest):
    """Make a private minimal service tree; never mount the repository itself."""
    stage = Path(manifest["receipt_dir"]).parent / (Path(manifest["receipt_dir"]).name + "-edge-stage")
    if stage.exists():
        raise RuntimeError("refusing to reuse an existing Edge Runtime stage")
    sources = [
        "supabase/functions/_shared/challenge_machine.ts",
        "supabase/functions/challenge-worker/handler.ts",
        "supabase/functions/challenge-worker/database.ts",
        "supabase/functions/challenge-snapshot/handler.ts",
        "supabase/functions/challenge-snapshot/database.ts",
        "supabase/functions/challenge-monitor/handler.ts",
        "supabase/functions/challenge-monitor/database.ts",
    ]
    stage.mkdir(mode=0o700)
    hashes = {}
    try:
        for relative in sources:
            source = ROOT / relative
            contents = source.read_bytes()
            if re.search(rb"(?:https?:|npm:|jsr:)", contents):
                raise RuntimeError("minimal Edge Runtime stage has a network import: " + relative)
            destination = stage / relative.replace("supabase/functions/", "functions/", 1)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(contents)
            os.chmod(destination, 0o600)
            hashes[relative] = hashlib.sha256(contents).hexdigest()
            if hashlib.sha256(destination.read_bytes()).hexdigest() != hashes[relative]:
                raise RuntimeError("Edge Runtime stage byte hash did not match production source")
        # The copied modules import PostgrestConfig only as a TypeScript type.
        # This private shim makes that erased type import resolvable without
        # bringing the broad shared database module or its dependencies in.
        shim = stage / "functions/_shared/database.ts"
        shim.write_text("export interface PostgrestConfig { url: string; serviceRoleKey: string; authorizationBearer?: boolean }\n")
        os.chmod(shim, 0o600)
        entrypoint = stage / "index.ts"
        entrypoint.write_text("""const port = Number(Deno.env.get('P11_ROUTER_PORT'));
const postgrest = Deno.env.get('P11_POSTGREST_URL');
if (!Number.isSafeInteger(port) || !postgrest) throw new Error('local Edge configuration missing');
const upstream = globalThis.fetch;
globalThis.fetch = (input, init) => {
  const request = new Request(input, init); const url = new URL(request.url);
  if (url.origin === postgrest && url.pathname.startsWith('/rest/v1/')) {
    url.pathname = url.pathname.slice('/rest/v1'.length); return upstream(new Request(url, request));
  }
  return upstream(request);
};
const workerSecret = Deno.env.get('GAMETIME_CHALLENGE_WORKER_SECRET') ?? '';
const monitorSecret = Deno.env.get('GAMETIME_CHALLENGE_MONITOR_SECRET') ?? '';
const config = { url: postgrest, serviceRoleKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '' };
const { createChallengeWorkerHandler } = await import('./functions/challenge-worker/handler.ts');
const { postgrestChallengeWorkerDatabase } = await import('./functions/challenge-worker/database.ts');
const { createChallengeSnapshotHandler } = await import('./functions/challenge-snapshot/handler.ts');
const { postgrestChallengeSnapshotDatabase } = await import('./functions/challenge-snapshot/database.ts');
const { createChallengeMonitorHandler } = await import('./functions/challenge-monitor/handler.ts');
const { postgrestChallengeMonitorDatabase } = await import('./functions/challenge-monitor/database.ts');
const worker = createChallengeWorkerHandler({ workerSecret, monitorSecret, database: postgrestChallengeWorkerDatabase(config) });
const snapshot = createChallengeSnapshotHandler({ workerSecret, monitorSecret, database: postgrestChallengeSnapshotDatabase(config) });
const monitor = createChallengeMonitorHandler({ workerSecret, monitorSecret, database: postgrestChallengeMonitorDatabase(config) });
Deno.serve({ hostname: '0.0.0.0', port }, (request) => {
  const path = new URL(request.url).pathname;
  if (path === '/_p11/health' && request.method === 'GET') return Response.json({ status: 'ready' });
  if (path === '/functions/v1/challenge-worker') return worker(request);
  if (path === '/functions/v1/challenge-snapshot') return snapshot(request);
  if (path === '/functions/v1/challenge-monitor') return monitor(request);
  return Response.json({ error: 'not_found' }, { status: 404 });
});
""")
        os.chmod(entrypoint, 0o600)
        return stage, hashes
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def start_router(base, manifest):
    """Start production handlers in the cached local Supabase Edge Runtime."""
    port = 9000
    worker_secret = secrets.token_urlsafe(36)
    monitor_secret = secrets.token_urlsafe(36)
    if worker_secret == monitor_secret:
        raise RuntimeError("could not create distinct local machine secrets")
    router = base["owner"] + "-edge-runtime"
    network = base["owner"] + "-edge-internal"
    image = "public.ecr.aws/supabase/edge-runtime:v1.74.2"
    inspected_image = json.loads(P8.command(["docker", "image", "inspect", image]).stdout)[0]
    if not inspected_image.get("Id") or not inspected_image.get("RepoDigests"):
        raise RuntimeError("cached Edge Runtime image has no local provenance")
    environment = {
        "P11_ROUTER_PORT": "9000",
        # Both the owned database caller and PostgREST adapter reach this
        # runtime only over the internal Docker network. No port is published.
        "SUPABASE_URL": "http://" + base["rest"] + ":3000",
        "P11_POSTGREST_URL": "http://" + base["rest"] + ":3000",
        "SUPABASE_SERVICE_ROLE_KEY": service_jwt(base["jwt_secret"]),
        "GAMETIME_CHALLENGE_WORKER_SECRET": worker_secret,
        "GAMETIME_CHALLENGE_MONITOR_SECRET": monitor_secret,
    }
    # Docker's default pools may be occupied by other local work. Read their
    # subnets, choose a disjoint tiny private one, and never remove those nets.
    network_ids = P8.command(["docker", "network", "ls", "-q"]).stdout.split()
    occupied = []
    if network_ids:
        for row in json.loads(P8.command(["docker", "network", "inspect", *network_ids]).stdout):
            occupied.extend(ipaddress.ip_network(config["Subnet"]) for config in (row.get("IPAM", {}).get("Config") or []) if config.get("Subnet"))
    subnet = next((candidate for candidate in ipaddress.ip_network("10.253.0.0/16").subnets(new_prefix=28)
                   if not any(candidate.version == old.version and candidate.overlaps(old) for old in occupied)), None)
    if subnet is None:
        raise RuntimeError("no unused private P11 Edge subnet is available")
    stage, stage_hashes = stage_edge_runtime(manifest)
    try:
        P8.command(["docker", "network", "create", "--internal", "--subnet", str(subnet),
                    "--label", "owner=" + base["owner"], network],
                   label="edge-internal-network.log", manifest=base)
        inspected = json.loads(P8.command(["docker", "network", "inspect", network]).stdout)[0]
        if not inspected.get("Internal") or inspected.get("Labels", {}).get("owner") != base["owner"]:
            raise RuntimeError("P11 Edge network is not the labelled internal network")
        P8.command(["docker", "network", "connect", network, base["rest"]], label="edge-rest-connect.log", manifest=base)
        P8.command(["docker", "network", "connect", network, base["db"]], label="edge-db-connect.log", manifest=base)
    except BaseException:
        P8.command(["docker", "network", "disconnect", network, base["rest"]], check=False)
        P8.command(["docker", "network", "disconnect", network, base["db"]], check=False)
        P8.command(["docker", "network", "rm", network], check=False)
        shutil.rmtree(stage, ignore_errors=True)
        raise
    command = ["docker", "run", "-d", "--name", router, "--label", "owner=" + base["owner"],
               "--network", network, "--cap-drop=ALL", "--security-opt=no-new-privileges",
               "-v", str(stage) + ":/app:ro"]
    for key in environment:
        command.extend(["-e", key])
    command.extend([image, "start", "--port", "9000",
                    "--main-service", "/app"])
    try:
        P8.command(command, env=dict(os.environ, **environment), label="edge-runtime-start.log", manifest=base)
    except BaseException:
        P8.command(["docker", "rm", "-fv", router], check=False)
        P8.command(["docker", "network", "disconnect", network, base["rest"]], check=False)
        P8.command(["docker", "network", "disconnect", network, base["db"]], check=False)
        P8.command(["docker", "network", "rm", network], check=False)
        shutil.rmtree(stage, ignore_errors=True)
        raise
    try:
        inspection = P8.inspect_owned(base, "container", router)
        address = inspection["NetworkSettings"]["Networks"][network]["IPAddress"]
        if ipaddress.ip_address(address) not in subnet or set(inspection["NetworkSettings"]["Networks"]) != {network}:
            raise RuntimeError("Edge Runtime is not confined to its private internal network")
        connection = {"container": router, "network": network, "stage": stage,
                      "hashes": stage_hashes, "ip": address}
        for probe in range(15):
            running = P8.command(["docker", "inspect", "-f", "{{.State.Running}}", router], check=False)
            if running.returncode or running.stdout.strip() != "true":
                raise RuntimeError("local Edge router exited before readiness")
            try:
                status, _ = internal_http(base, connection, "/_p11/health", timeout=1)
                if status == 200:
                    return connection, port, worker_secret, monitor_secret
            except OSError:
                time.sleep(0.25)
        raise RuntimeError("local Edge router did not become ready")
    except BaseException:
        P8.command(["docker", "logs", router], label="edge-runtime-readiness-failure.log", manifest=base, check=False)
        P8.command(["docker", "rm", "-fv", router], check=False)
        P8.command(["docker", "network", "disconnect", network, base["rest"]], check=False)
        P8.command(["docker", "network", "disconnect", network, base["db"]], check=False)
        P8.command(["docker", "network", "rm", network], check=False)
        shutil.rmtree(stage, ignore_errors=True)
        raise


def stop_router(base, router):
    errors = []
    try:
        exists = P8.command(["docker", "container", "inspect", router["container"]], check=False).returncode == 0
        if exists:
            P8.inspect_owned(base, "container", router["container"])
            P8.command(["docker", "rm", "-fv", router["container"]], label="edge-runtime-stop.log", manifest=base)
    except Exception as error:
        errors.append(str(error))
    try:
        exists = P8.command(["docker", "network", "inspect", router["network"]], check=False).returncode == 0
        if exists:
            P8.inspect_owned(base, "network", router["network"])
            P8.command(["docker", "network", "disconnect", router["network"], base["rest"]], check=False)
            P8.command(["docker", "network", "disconnect", router["network"], base["db"]], check=False)
            P8.command(["docker", "network", "rm", router["network"]], label="edge-internal-network-stop.log", manifest=base)
    except Exception as error:
        errors.append(str(error))
    expected_stage = Path(base["receipt_dir"] + "-edge-stage").resolve()
    if Path(router["stage"]).resolve() != expected_stage:
        errors.append("refusing an unowned Edge source stage")
    else:
        shutil.rmtree(expected_stage, ignore_errors=True)
    if errors:
        raise RuntimeError("Edge cleanup incomplete: " + "; ".join(errors))


def prepare_operating_fixture(base):
    if not OPERATING_FIXTURE.is_file():
        raise RuntimeError("P11 synthetic operating fixture is unavailable")
    source = OPERATING_FIXTURE.read_text()
    if SELECTED_COMMUNITY_ID not in source or UNSELECTED_COMMUNITY_ID not in source:
        raise RuntimeError("P11 operating fixture does not contain the fixed community identities")
    # Fixture owns its explicit BEGIN/COMMIT so a failure leaves no partial
    # synthetic state; do not nest it in psql's --single-transaction wrapper.
    P8.sql(base, source, "operating-fixture.log")
    P8.sql(base, """
      select public.challenge_runtime_v1(false,false,true,'{}'::uuid[],null);
      select public.challenge_real_health_runtime_v1(false,false,true);
      do $$ begin
        if exists(select 1 from app.challenge_runtime_v1 where singleton and (admission or fixtures or discovery or fictional_now is not null or cardinality(actors)>0))
          or exists(select 1 from app.challenge_real_health_runtime_v1 where singleton and (admission_enabled or ingestion_enabled or not processing_enabled)) then
          raise exception 'p11_fixture_runtime_not_closed';
        end if;
      end $$;
    """, "operating-runtime.log", single_transaction=True)


def configure_local_dispatch(base, port, worker_secret, monitor_secret):
    """Write secrets via stdin to private Vault rows; never to argv or receipts."""
    source = """
      with worker as (
        select vault.create_secret(%s, 'p11-local-worker-'||gen_random_uuid(), 'disposable local P11 worker secret') as id
      ), monitor as (
        select vault.create_secret(%s, 'p11-local-monitor-'||gen_random_uuid(), 'disposable local P11 monitor secret') as id
      )
      update app.challenge_schedule_config_v1 config
         set edge_base_url=%s,
             worker_secret_id=(select id from worker),
             monitor_secret_id=(select id from monitor),
             worker_enabled=true, snapshot_enabled=true, monitor_enabled=true,
             community_id=%s
       where singleton;
    """ % (sql_literal(worker_secret), sql_literal(monitor_secret),
           sql_literal("http://host.docker.internal:" + str(port) + "/functions/v1"),
           sql_literal(SELECTED_COMMUNITY_ID))
    P8.sql(base, source, "local-dispatch-config.log", single_transaction=True)


def restart_primary_with_cron(base, router):
    """Restart only the labelled primary DB after all non-P11 jobs are inactive."""
    P8.inspect_owned(base, "container", base["db"])
    image = base["owner"] + "-p11-cron-runtime"
    P8.command(["docker", "commit", "--change", "LABEL owner=" + base["owner"], base["db"], image],
               label="cron-runtime-commit.log", manifest=base)
    try:
        P8.command(["docker", "rm", "-f", base["db"]], label="cron-runtime-stop.log", manifest=base)
        P8.command([
            "docker", "run", "-d", "--name", base["db"], "--label", "owner=" + base["owner"],
            "--network", base["network"], "-p", "127.0.0.1:" + str(base["db_port"]) + ":5432",
            "--add-host", "host.docker.internal:" + router["ip"],
            "-e", "POSTGRES_PASSWORD", image, "postgres", "-D", "/etc/postgresql",
            "-c", "cron.launch_active_jobs=on", "-c", "cron.database_name=postgres", "-c", "listen_addresses=*",
        ], env=dict(os.environ, POSTGRES_PASSWORD=base["db_password"]), label="cron-runtime-start.log", manifest=base)
        P8.command(["docker", "network", "connect", router["network"], base["db"]])
        for _ in range(60):
            result = P8.command(["docker", "exec", base["db"], "psql", "-XqAt", "-U", "postgres", "-d", "postgres",
                                 "-c", "select 1"], check=False)
            if result.returncode == 0:
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Cron-enabled owned database did not restart")
        P8.check_loopback(base, base["db"], "5432/tcp", base["db_port"])
        if P8.sql(base, "show cron.launch_active_jobs") != "on":
            raise RuntimeError("Cron-enabled owned database did not report launch_active_jobs=on")
    except BaseException:
        raise
    return image


def enable_only_p11_jobs(base):
    disable_all_jobs(base)
    jobs = p11_jobs(base)
    for row in jobs.values():
        P8.sql(base, "select cron.alter_job(" + row["id"] + ", active := true)",
               "cron-enable-" + row["id"] + ".log")
    names = {name for _, name in active_jobs(base)}
    if names - set(P11_JOB_NAMES.values()):
        raise RuntimeError("a historical Cron job became active")


def internal_http(base, router, path, body=None, headers=None, timeout=55):
    """Send bounded local HTTP from the owned DB without publishing Edge ports.

    Curl configuration (including temporary headers) travels only on stdin;
    it is never part of a command argument, output receipt or source mount.
    """
    source = "url = " + json.dumps("http://" + router["ip"] + ":9000" + path) + "\n"
    source += 'write-out = "\\n%{http_code}"\n'
    if body is not None:
        source += 'request = "POST"\n'
        source += "data-binary = " + json.dumps(json.dumps(body, separators=(",", ":"))) + "\n"
        for key, value in {"content-type": "application/json", **(headers or {})}.items():
            source += "header = " + json.dumps(key + ": " + value) + "\n"
    result = P8.command(["docker", "exec", "-i", base["db"], "/usr/bin/curl", "--silent", "--show-error",
                         "--noproxy", "*", "--max-time", str(timeout), "--config", "-"], source=source, check=False)
    if result.returncode:
        raise OSError("owned internal HTTP connection failed")
    content, status = result.stdout.rsplit("\n", 1)
    return int(status), json.loads(content)


def machine_request(base, router, kind, body, headers=None):
    return internal_http(base, router, "/functions/v1/challenge-" + kind, body, headers)


def app_fingerprint(base):
    # Private comparison only: never export rows, health values, or identities.
    return P8.sql(base, """
      create temporary table p11_read_hash(value text);
      do $$ declare relation record; digest text; begin
        for relation in select tablename from pg_tables where schemaname='app' and tablename like 'challenge_%' order by tablename loop
          execute format('select md5(coalesce(string_agg(to_jsonb(t)::text,''|'' order by to_jsonb(t)::text),'''')) from app.%I t',relation.tablename) into digest;
          insert into p11_read_hash values(relation.tablename||':'||digest);
        end loop;
      end $$;
      select md5(string_agg(value,'|' order by value)) from p11_read_hash;
    """)


def assert_sanitized(value, secrets_to_hide=()):
    encoded = json.dumps(value, sort_keys=True)
    if re.search(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", encoded, re.I):
        raise RuntimeError("machine output disclosed an identifier")
    for forbidden in (*secrets_to_hide, "claim_token", "run_token", "actor_id", "challenge_id",
                      "invocation_id", "joined", "participant", "member_count", "payload", "fact", "handle"):
        if forbidden in encoded:
            raise RuntimeError("machine output was not sanitized")


def credential_checks(base, router, worker_secret, monitor_secret):
    """An unreachable adapter makes authentication-before-DB observable."""
    before = app_fingerprint(base)
    count = 0
    P8.command(["docker", "network", "disconnect", router["network"], base["rest"]])
    try:
        for kind in ("worker", "snapshot", "monitor"):
            header = "x-gametime-monitor-secret" if kind == "monitor" else "x-gametime-worker-secret"
            right = monitor_secret if kind == "monitor" else worker_secret
            wrong_role = worker_secret if kind == "monitor" else monitor_secret
            body = {} if kind == "monitor" else {"invocation_id": REAL_GOAL_ID}
            credentials = [{}, {header: "incorrect"}, {header: wrong_role}]
            for role in ("anon", "authenticated", "service_role"):
                token = service_jwt(base["jwt_secret"], role)
                credentials.append({"authorization": "Bearer " + token, "apikey": token})
            for headers in credentials:
                status, result = machine_request(base, router, kind, body, headers)
                if status != 401 or result != {"error": "unauthorized"}:
                    raise RuntimeError("machine credential separation failed")
                count += 1
            for extra in ({"rpc": "challenge_runtime_v1"}, {"community_id": UNSELECTED_COMMUNITY_ID},
                          {"scope": {"kind": "all"}}):
                status, result = machine_request(base, router, kind, {**body, **extra}, {header: right})
                if status != 400 or result != {"error": "bad_request"}:
                    raise RuntimeError("machine interface allowed caller-selected operations")
                count += 1
        status, result = machine_request(base, router, "monitor", {}, {"x-gametime-monitor-secret": monitor_secret})
        if status != 503 or result.get("state") != "unavailable":
            raise RuntimeError("monitor did not honestly report an unavailable adapter")
        assert_sanitized(result, (worker_secret, monitor_secret))
    finally:
        P8.command(["docker", "network", "connect", router["network"], base["rest"]])
    if app_fingerprint(base) != before:
        raise RuntimeError("denied machine requests changed application state")
    return count


def close_local_dispatch(base):
    disable_all_jobs(base)
    jobs = P8.sql(base, "select jobid from cron.job where jobname='challenge-snapshot-v1'")
    if jobs:
        P8.sql(base, "select cron.alter_job(" + jobs + ",schedule := '*/15 * * * *', active := false)")
    P8.sql(base, """
      delete from vault.secrets where id in
        (select worker_secret_id from app.challenge_schedule_config_v1 union select monitor_secret_id from app.challenge_schedule_config_v1);
      update app.challenge_schedule_config_v1 set worker_enabled=false,snapshot_enabled=false,monitor_enabled=false,
        edge_base_url=null,worker_secret_id=null,monitor_secret_id=null,community_id=null;
      select public.challenge_runtime_v1(false,false,false,'{}'::uuid[],null);
      select public.challenge_real_health_runtime_v1(false,false,false);
    """, "closed-local-dispatch.log", single_transaction=True)


def bounded_acceptance(args, manifest, base):
    if manifest["state"] != "forward_applied":
        raise RuntimeError("bounded acceptance requires a forward-applied P11 stack")
    assert_preserved(manifest, base)
    disable_all_jobs(base)
    router = None
    evidence = {"kind": "p11-local-scheduling-acceptance-v1", "result": "failed"}
    receipt = Path(manifest["receipt_dir"]) / "bounded-acceptance.json"
    try:
        if "operating_fixture_sha256" not in manifest:
            prepare_operating_fixture(base)
            manifest["operating_fixture_sha256"] = hashlib.sha256(OPERATING_FIXTURE.read_bytes()).hexdigest()
            write_private(args.manifest, manifest)
        else:
            # A failed harness run closes processing. Reopen only synthetic
            # processing for this attempt, never admission or fixture gates.
            P8.sql(base, "select public.challenge_runtime_v1(false,false,true,'{}'::uuid[],null); select public.challenge_real_health_runtime_v1(false,false,true)")
        router, port, worker_secret, monitor_secret = start_router(base, manifest)
        manifest["edge_runtime"] = {**router, "stage": str(router["stage"])}
        write_private(args.manifest, manifest)
        evidence["production_source_hashes"] = router["hashes"]
        evidence["credential_and_operation_denials"] = credential_checks(base, router, worker_secret, monitor_secret)
        evidence["unavailable_transport_reported"] = True
        configure_local_dispatch(base, port, worker_secret, monitor_secret)
        # Save cleanup ownership before creating the temporary runtime image.
        manifest["cron_runtime_image"] = base["owner"] + "-p11-cron-runtime"
        write_private(args.manifest, manifest)
        restart_primary_with_cron(base, router)
        for _ in range(10):
            status, ready = machine_request(base, router, "monitor", {}, {"x-gametime-monitor-secret": monitor_secret})
            if status == 200:
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("owned PostgREST did not reconnect after database restart")
        enable_only_p11_jobs(base)
        # One disposable snapshot tick is accelerated to the same minute as
        # worker/monitor. The private SQL throttle remains 900 seconds, and the
        # registered default is restored even on failure.
        snapshot_job = p11_jobs(base)["challenge-snapshot-v1"]["id"]
        P8.sql(base, "select cron.alter_job(" + snapshot_job + ", schedule := '* * * * *')")
        evidence["snapshot_test_schedule_override"] = "one bounded minute; restored to */15 * * * *"
        deadline = time.monotonic() + 75
        responses = {}
        invocations = {}
        while time.monotonic() < deadline:
            rows = json.loads(P8.sql(base, """
              select coalesce(jsonb_object_agg(t.kind,jsonb_build_object('http_status',r.status_code,'body',r.content::jsonb,
                'invocation_id',(select m.invocation_id from app.challenge_machine_runs_v1 m
                  where m.kind=t.kind and m.last_queued_at=t.last_queued_at))),'{}')
              from app.challenge_schedule_ticks_v1 t join net._http_response r on r.id=t.last_request_id
              where r.status_code=200;
            """))
            if set(rows) == {"worker", "snapshot", "monitor"}:
                responses = rows
                invocations = {kind: value.pop("invocation_id") for kind, value in rows.items()}
                break
            time.sleep(1)
        else:
            P8.sql(base, "select jobname,status,return_message from cron.job_run_details join cron.job using(jobid)",
                   "cron-failure-details.log")
            P8.sql(base, "select status_code,error_msg from net._http_response", "http-failure-categories.log")
            raise RuntimeError("P11 Cron jobs did not produce local pg_net responses")
        assert_sanitized(responses, (worker_secret, monitor_secret))
        if responses["worker"]["body"].get("completed_count", 0) < 1 or responses["worker"]["body"].get("status") != "completed":
            raise RuntimeError("actual scheduled worker did not finish nonempty real-contract work")
        if responses["snapshot"]["body"].get("status") != "checked" or not responses["snapshot"]["body"].get("last_capture_at"):
            raise RuntimeError("actual scheduled snapshot did not capture the selected cohort")
        # All IDs below stay inside this private owned-stack query.
        assertions = P8.sql(base, """
          select jsonb_build_object(
            'real_notice', (select count(*)=1 from app.challenge_notices_v1 where challenge_id=%s),
            'no_legacy_facts',not exists(select 1 from app.challenge_facts_v1 where challenge_id=%s),
            'selected_capture', (select count(*)=1 and min(joined)=5 from app.challenge_community_snapshots_v1 where challenge_id=%s),
            'unselected_private',not exists(select 1 from app.challenge_community_snapshots_v1 where challenge_id=%s)
              and not exists(select 1 from app.challenge_snapshot_invocations_v1 where challenge_id=%s),
            'prepared_before_http_completion', (select bool_and(m.prepared_at<=h.created and m.prepared_at<=m.finished_at)
              from app.challenge_machine_runs_v1 m join app.challenge_schedule_ticks_v1 t using(kind)
              join net._http_response h on h.id=t.last_request_id where m.state='finished'),
            'legacy_gates_closed',(select not admission and not fixtures and not discovery and fictional_now is null
              and cardinality(actors)=0 from app.challenge_runtime_v1 where singleton),
            'only_new_jobs_ran',not exists(select 1 from cron.job_run_details d join cron.job j using(jobid)
              where j.jobname not in ('challenge-worker-v1','challenge-snapshot-v1','challenge-monitor-v1')));
        """ % tuple(sql_literal(x) for x in (REAL_GOAL_ID, REAL_GOAL_ID, SELECTED_COMMUNITY_ID, UNSELECTED_COMMUNITY_ID, UNSELECTED_COMMUNITY_ID)))
        evidence["operating_assertions"] = json.loads(assertions)
        if not all(value is True for value in evidence["operating_assertions"].values()):
            raise RuntimeError("scheduled real processing or cohort isolation assertion failed")
        P8.sql(base, "select public.challenge_runtime_v1(false,false,false,'{}'::uuid[],null); select public.challenge_real_health_runtime_v1(false,false,false)")
        status, paused = machine_request(base, router, "monitor", {}, {"x-gametime-monitor-secret": monitor_secret})
        if status != 200 or paused.get("state") != "paused" or paused.get("worker", {}).get("processing_state") != "paused":
            raise RuntimeError("actual monitor did not report paused processing")
        assert_sanitized(paused, (worker_secret, monitor_secret))
        evidence["paused_monitor"] = paused
        disable_all_jobs(base)
        P8.sql(base, "select cron.alter_job(" + snapshot_job + ", schedule := '*/15 * * * *')")
        # Recover lost public replies after a real process restart using only
        # saved server-prepared identities. No broad operation is exposed.
        P8.command(["docker", "restart", router["container"]], label="edge-runtime-restart.log", manifest=base)
        time.sleep(1)
        for kind, header in (("worker", "x-gametime-worker-secret"), ("snapshot", "x-gametime-worker-secret")):
            invocation = invocations[kind]
            status, saved = machine_request(base, router, kind, {"invocation_id": invocation}, {header: worker_secret})
            if status != 200 or saved != responses[kind]["body"]:
                raise RuntimeError("process restart did not replay the exact committed machine result")
        before = app_fingerprint(base)
        sink = []
        for _ in range(2):
            status, result = machine_request(base, router, "monitor", {}, {"x-gametime-monitor-secret": monitor_secret})
            if status != 200 or result.get("state") != "disabled":
                raise RuntimeError("inactive scheduling was not reported disabled")
            assert_sanitized(result, (worker_secret, monitor_secret))
            sink.append(result)
        if app_fingerprint(base) != before:
            raise RuntimeError("monitor reads wrote application state")
        write_private(Path(manifest["receipt_dir"]) / "monitor-local-sink.json", sink)
        evidence["monitor_read_only"] = True
        evidence["process_restart_exact_replay"] = True
        evidence["cron_responses"] = responses
        stop_router(base, router)
        router = None
        manifest.pop("edge_runtime", None)
        manifest["state"] = "bounded_complete"
        evidence["result"] = "passed"
        write_private(args.manifest, manifest)
        print(json.dumps({"manifest": str(args.manifest), "state": manifest["state"],
                          "responses": len(responses), "credential_and_operation_denials": evidence["credential_and_operation_denials"]}, sort_keys=True))
    finally:
        write_private(receipt, evidence)
        try:
            close_local_dispatch(base)
        finally:
            if router is not None:
                stop_router(base, router)
                manifest.pop("edge_runtime", None)
                write_private(args.manifest, manifest)


def cleanup(path, manifest, base):
    # Disable the complete registry before removal. This has no effect outside
    # this labelled disposable DB and retains the P8 ownership guard.
    errors = []
    try:
        close_local_dispatch(base)
    except Exception as error:
        errors.append(str(error))
    try:
        router = manifest.get("edge_runtime")
        if router:
            stop_router(base, router)
    except Exception as error:
        errors.append(str(error))
    try:
        p8_path = Path(manifest["p8_manifest"])
        P8.cleanup(p8_path, P8.load_manifest(p8_path))
    except Exception as error:
        errors.append(str(error))
    try:
        image = manifest.get("cron_runtime_image")
        if isinstance(image, str) and image.startswith(base["owner"] + "-"):
            result = P8.command(["docker", "image", "inspect", image], check=False)
            if result.returncode == 0:
                if json.loads(result.stdout)[0].get("Config", {}).get("Labels", {}).get("owner") != base["owner"]:
                    raise RuntimeError("refusing an unowned Cron runtime image")
                P8.command(["docker", "image", "rm", image])
    except Exception as error:
        errors.append(str(error))
    if errors:
        raise RuntimeError("owned P11 cleanup incomplete: " + "; ".join(errors))
    path.unlink(missing_ok=True)
    print("owned P11 local scheduling stack removed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "apply-forward", "bounded-acceptance", "check", "cleanup"))
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--forward-migration", type=Path,
                        help="the one P11 scheduling migration; required for apply-forward")
    parser.add_argument("--tap", action="append", default=[],
                        help="focused pgTAP basename, without .test.sql")
    args = parser.parse_args()
    os.umask(0o077)
    if args.mode == "prepare":
        prepare(args)
        return
    manifest, base = load_manifest(args.manifest)
    if args.mode == "apply-forward":
        if args.forward_migration is None:
            raise RuntimeError("apply-forward requires --forward-migration")
        apply_forward(args, manifest, base)
    elif args.mode == "bounded-acceptance":
        bounded_acceptance(args, manifest, base)
    elif args.mode == "check":
        check(args, manifest, base)
    else:
        cleanup(args.manifest, manifest, base)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("error: " + str(error), file=sys.stderr)
        raise SystemExit(1)
