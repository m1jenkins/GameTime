#!/usr/bin/env python3
"""Own a disposable P8 real-health verification stack.

The stack is strictly local: cached Docker images, generated fictional actors and
credentials, numeric loopback ports, and an owner label on every resource.
``prepare`` applies exactly the committed 848ef6e migration set and creates
historical challenge agreements. ``apply-forward`` then applies the ordered
approved P8 migration set to that retained stack. ``cleanup`` refuses any
resource that does not bear the manifest's owner label.
"""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
BASELINE = "848ef6ee02d95b57bdad4b36d3c7600a4ba3f192"
DB_IMAGE = "public.ecr.aws/supabase/postgres:17.6.1.143"
AUTH_IMAGE = "public.ecr.aws/supabase/gotrue:v2.192.0"
REST_IMAGE = "public.ecr.aws/supabase/postgrest:v14.14"
FORWARD_DIR = ROOT / "supabase/migrations"


def local_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "rebuild", "apply-forward", "overlay-ingest", "check", "cleanup"))
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--forward-migration", type=Path, action="append", default=[],
                        help="Repeatable approved P8 migration path; defaults to all 20260920 P8 migrations.")
    parser.add_argument("--tap", action="append", default=[],
                        help="A focused supabase/tests basename, without .test.sql")
    args = parser.parse_args()
    os.umask(0o077)
    if args.mode == "prepare":
        prepare(args)
    else:
        manifest = load_manifest(args.manifest)
        if args.mode == "rebuild":
            # A changed forward file must never be claimed against a database
            # where an earlier draft of that file already ran.  This destroys
            # only resources whose owner label matches this private manifest.
            cleanup(args.manifest, manifest)
            prepare(args)
        elif args.mode == "apply-forward":
            apply_forward(args, manifest)
        elif args.mode == "overlay-ingest":
            overlay_ingest(args, manifest)
        elif args.mode == "check":
            check_stack(args, manifest)
        else:
            cleanup(args.manifest, manifest)


def command(argv, *, source=None, env=None, label=None, manifest=None, check=True):
    result = subprocess.run(argv, input=source, text=True, capture_output=True,
                            timeout=180, env=env)
    if label and manifest:
        receipt = Path(manifest["receipt_dir"]) / label
        receipt.write_text(result.stdout + result.stderr)
        os.chmod(receipt, 0o600)
    if check and result.returncode:
        raise RuntimeError("command failed; private receipt: " + (label or argv[0]))
    return result


def write_manifest(path, manifest):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise RuntimeError("refusing to replace an existing manifest")
    path.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    os.chmod(path, 0o600)


def load_manifest(path):
    try:
        if path.stat().st_mode & 0o077:
            raise RuntimeError("manifest must be mode 0600")
        manifest = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError("cannot read private manifest") from error
    required = {"owner", "db", "auth", "rest", "db_port", "auth_port", "rest_port",
                "db_password", "jwt_secret", "receipt_dir", "baseline"}
    if not required.issubset(manifest):
        raise RuntimeError("manifest is not a P8 local-stack manifest")
    if manifest["baseline"] != BASELINE:
        raise RuntimeError("manifest baseline does not match P8 checkpoint")
    for key in ("db_port", "auth_port", "rest_port"):
        if not isinstance(manifest[key], int) or not 1 <= manifest[key] <= 65535:
            raise RuntimeError("manifest has an invalid loopback port")
    return manifest


def sql(manifest, source, label=None, check=True, database="postgres", single_transaction=False, container=None):
    argv = ["docker", "exec", "-i", container or manifest["db"], "psql", "-XqAt",
            "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", database]
    if single_transaction:
        argv.append("--single-transaction")
    return command(argv,
                   source=source, label=label, manifest=manifest, check=check).stdout.strip()


def inspect_owned(manifest, kind, name):
    result = command(["docker", kind, "inspect", name], check=False)
    if result.returncode:
        raise RuntimeError("owned resource is unavailable: " + name)
    row = json.loads(result.stdout)[0]
    labels = row["Config"]["Labels"] if kind == "container" else row["Labels"]
    if labels.get("owner") != manifest["owner"]:
        raise RuntimeError("refusing an unowned resource: " + name)
    return row


def check_loopback(manifest, name, container_port, expected_port):
    row = inspect_owned(manifest, "container", name)
    expected = {container_port: [{"HostIp": "127.0.0.1", "HostPort": str(expected_port)}]}
    if row["HostConfig"]["PortBindings"] != expected:
        raise RuntimeError("container is not bound only to numeric loopback: " + name)


def baseline_migrations():
    paths = command(["git", "ls-tree", "-r", "--name-only", BASELINE, "--", "supabase/migrations"]).stdout.splitlines()
    if not paths:
        raise RuntimeError("P8 baseline migrations are unavailable")
    result = []
    for relative in sorted(paths):
        contents = command(["git", "show", BASELINE + ":" + relative]).stdout
        result.append((relative, contents, hashlib.sha256(contents.encode()).hexdigest()))
    return result


def forward_migrations(args):
    selected = args.forward_migration or sorted(FORWARD_DIR.glob("20260920*_challenge_real_health_*_v1.sql"))
    paths = sorted({path.resolve() for path in selected}, key=lambda path: path.name)
    if not paths:
        raise RuntimeError("no approved P8 forward migrations were found")
    for path in paths:
        if path.parent != FORWARD_DIR.resolve() or not path.name.startswith("20260920"):
            raise RuntimeError("forward migration is outside the approved P8 migration location")
    return paths


def agreement_digest(manifest):
    keys = manifest.get("historical_agreement_keys")
    if not isinstance(keys, list) or not all(isinstance(key, str) and re.fullmatch(
            r"[0-9a-f-]{36}:[1-9][0-9]*", key) for key in keys):
        raise RuntimeError("manifest has no historical agreement key snapshot")
    quoted = ",".join("'" + key + "'" for key in keys)
    return sql(manifest, """
      with rows as (
        select 'agreement' as kind, challenge_id::text as challenge_id, version::text as version,
               null::text as actor_id, digest as value
          from app.challenge_agreements_v1
         where challenge_id::text || ':' || version::text in (""" + quoted + """)
        union all
        select 'consent', challenge_id::text, version::text, actor_id::text, digest
          from app.challenge_consents_v1
         where challenge_id::text || ':' || version::text in (""" + quoted + """)
      )
      select encode(extensions.digest(coalesce(string_agg(
        kind || ':' || challenge_id || ':' || version || ':' || coalesce(actor_id, '') || ':' || value,
        '|' order by kind, challenge_id, version, actor_id, value), ''), 'sha256'), 'hex')
      from rows;
    """)


def historical_agreement_keys(manifest):
    snapshot = sql(manifest, """
      select coalesce(json_agg(challenge_id::text || ':' || version order by challenge_id, version), '[]')
      from app.challenge_agreements_v1;
    """)
    try:
        keys = json.loads(snapshot)
    except json.JSONDecodeError as error:
        raise RuntimeError("could not snapshot historical agreement keys") from error
    if not keys:
        raise RuntimeError("historical fixture created no agreement")
    return keys


def run_tap(manifest, names, database="postgres", label_prefix="", container=None):
    if not names:
        return {}
    target = container or manifest["db"]
    command(["docker", "exec", target, "rm", "-rf", "/tmp/p8-tests"],
            label="tests-clear.log", manifest=manifest)
    command(["docker", "cp", str(ROOT / "supabase/tests"), target + ":/tmp/p8-tests"],
            label="tests-copy.log", manifest=manifest)
    result = {}
    for name in names:
        if not re.fullmatch(r"[0-9]{3}_[a-z0-9_]+", name):
            raise RuntimeError("invalid focused pgTAP name")
        output = command(["docker", "exec", target, "psql", "-XqAt",
                          "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", database,
                          "-f", "/tmp/p8-tests/" + name + ".test.sql"],
                         label=label_prefix + name + ".tap", manifest=manifest)
        assertions = re.findall(r"^(?:not )?ok (\d+)\b", output.stdout, re.M)
        plan = re.findall(r"^1\.\.(\d+)$", output.stdout, re.M)
        if len(plan) != 1 or list(map(int, assertions)) != list(range(1, int(plan[0]) + 1)) or re.search(r"^not ok|^ERROR:", output.stdout + output.stderr, re.M | re.I):
            raise RuntimeError(name + " pgTAP failed")
        result[name] = int(plan[0])
    return result


def prepare_fresh_test_database(manifest):
    fresh = manifest.get("fresh_database")
    if not isinstance(fresh, dict) or fresh.get("container") != manifest["owner"] + "-fresh-db":
        raise RuntimeError("prepared stack has no isolated fresh baseline database")
    return fresh


def prepare(args):
    if args.manifest.exists():
        raise RuntimeError("prepare needs a new manifest path")
    owner = "gametime-p8-real-health-" + uuid.uuid4().hex[:12]
    receipt_dir = args.manifest.parent / (args.manifest.stem + "-receipts")
    # Rebuild retains prior private failure receipts as evidence; a new manifest
    # is still generated only after the new owned stack reaches its baseline.
    receipt_dir.mkdir(parents=True, mode=0o700, exist_ok=True)
    os.chmod(receipt_dir, 0o700)
    manifest = {"owner": owner, "baseline": BASELINE, "db": owner + "-db",
                "auth": owner + "-auth", "rest": owner + "-rest", "network": owner,
                "db_port": local_port(), "auth_port": local_port(), "rest_port": local_port(),
                "db_password": secrets.token_hex(24), "jwt_secret": secrets.token_hex(32),
                "receipt_dir": str(receipt_dir), "state": "creating"}
    if len({manifest["db_port"], manifest["auth_port"], manifest["rest_port"]}) != 3:
        raise RuntimeError("loopback port allocation collision; retry prepare")
    env = dict(os.environ, DO_NOT_TRACK="1", POSTGRES_PASSWORD=manifest["db_password"],
               GOTRUE_JWT_SECRET=manifest["jwt_secret"], GOTRUE_DB_DRIVER="postgres",
               GOTRUE_DB_DATABASE_URL="postgres://supabase_auth_admin:" + manifest["db_password"] + "@" + manifest["db"] + ":5432/postgres",
               GOTRUE_SITE_URL="http://127.0.0.1", API_EXTERNAL_URL="http://127.0.0.1:" + str(manifest["auth_port"]) + "/auth/v1",
               PGRST_DB_URI="postgres://authenticator:" + manifest["db_password"] + "@" + manifest["db"] + ":5432/postgres",
               PGRST_JWT_SECRET=manifest["jwt_secret"], PGRST_DB_SCHEMAS="public", PGRST_DB_ANON_ROLE="anon")
    created = []
    try:
        for image in (DB_IMAGE, AUTH_IMAGE, REST_IMAGE):
            command(["docker", "image", "inspect", image], env=env)
        network_ids = command(["docker", "network", "ls", "-q"], env=env).stdout.split()
        networks = json.loads(command(["docker", "network", "inspect", *network_ids], env=env).stdout) if network_ids else []
        occupied = [ipaddress.ip_network(config["Subnet"]) for network in networks
                    for config in (network.get("IPAM", {}).get("Config") or [])
                    if config.get("Subnet") and ":" not in config["Subnet"]]
        subnet = next(str(candidate) for candidate in ipaddress.ip_network("10.252.0.0/16").subnets(new_prefix=24)
                      if not any(candidate.overlaps(net) for net in occupied))
        command(["docker", "network", "create", "--subnet", subnet, "--label", "owner=" + owner, owner], env=env)
        created.append(("network", owner))
        command(["docker", "run", "-d", "--name", manifest["db"], "--label", "owner=" + owner,
                 "--network", owner, "-p", "127.0.0.1:" + str(manifest["db_port"]) + ":5432",
                 "-e", "POSTGRES_PASSWORD", DB_IMAGE, "postgres", "-D", "/etc/postgresql",
                 "-c", "cron.launch_active_jobs=off", "-c", "cron.database_name=postgres", "-c", "listen_addresses=*"], env=env,
                label="db-start.log", manifest=manifest)
        created.append(("container", manifest["db"]))
        for _ in range(60):
            ready = command(["docker", "exec", "-e", "PGPASSWORD", manifest["db"], "psql", "-h", "127.0.0.1", "-XAt", "-U", "postgres", "-d", "postgres", "-c", "select to_regclass('auth.users') is not null"], env=env, check=False)
            if ready.returncode == 0 and ready.stdout.strip() == "t":
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("owned database did not initialize")
        check_loopback(manifest, manifest["db"], "5432/tcp", manifest["db_port"])
        command(["docker", "exec", "-i", manifest["db"], "psql", "-XqAt", "-v", "ON_ERROR_STOP=1", "-U", "supabase_admin", "-d", "postgres"],
                source="alter role supabase_auth_admin password '" + manifest["db_password"] + "'; alter role authenticator password '" + manifest["db_password"] + "';", env=env,
                label="roles.log", manifest=manifest)
        command(["docker", "run", "--rm", "--name", manifest["auth"] + "-migrate", "--label", "owner=" + owner, "--network", owner,
                 "-e", "GOTRUE_JWT_SECRET", "-e", "GOTRUE_DB_DRIVER", "-e", "GOTRUE_DB_DATABASE_URL", "-e", "GOTRUE_SITE_URL", "-e", "API_EXTERNAL_URL", AUTH_IMAGE, "auth", "migrate"], env=env,
                label="auth-migrate.log", manifest=manifest)
        applied = []
        for relative, contents, digest in baseline_migrations():
            sql(manifest, "begin;\n" + contents + "\ncommit;", Path(relative).name + ".log")
            applied.append({"path": relative, "sha256": digest})
        if sql(manifest, "show cron.launch_active_jobs") != "off" or sql(manifest, "select count(*) from cron.job_run_details") != "0":
            raise RuntimeError("cron was not disabled before baseline migrations")
        sql(manifest, "create extension if not exists pgtap with schema extensions; create extension if not exists dblink with schema extensions;", "pgtap-install.log")
        manifest["baseline_migrations"] = applied
        manifest["baseline_tap"] = run_tap(manifest, ["490_challenge_steps"])
        # A second canonical Postgres database isolates rollback pgTAP from
        # the populated upgrade proof. It is a container, rather than a second
        # database, because this image's pg_cron can only be installed in its
        # configured `postgres` database.
        fresh_db = owner + "-fresh-db"
        command(["docker", "run", "-d", "--name", fresh_db, "--label", "owner=" + owner,
                 "--network", owner, "-e", "POSTGRES_PASSWORD", DB_IMAGE, "postgres", "-D", "/etc/postgresql",
                 "-c", "cron.launch_active_jobs=off", "-c", "cron.database_name=postgres", "-c", "listen_addresses=*"], env=env,
                label="fresh-db-start.log", manifest=manifest)
        created.append(("container", fresh_db))
        for _ in range(60):
            ready = command(["docker", "exec", "-e", "PGPASSWORD", fresh_db, "psql", "-h", "127.0.0.1", "-XAt", "-U", "postgres", "-d", "postgres", "-c", "select to_regclass('auth.users') is not null"], env=env, check=False)
            if ready.returncode == 0 and ready.stdout.strip() == "t":
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("owned fresh database did not initialize")
        command(["docker", "exec", "-i", fresh_db, "psql", "-XqAt", "-v", "ON_ERROR_STOP=1", "-U", "supabase_admin", "-d", "postgres"],
                source="alter role supabase_auth_admin password '" + manifest["db_password"] + "'; alter role authenticator password '" + manifest["db_password"] + "';", env=env,
                label="fresh-roles.log", manifest=manifest)
        fresh_env = dict(env, GOTRUE_DB_DATABASE_URL="postgres://supabase_auth_admin:" + manifest["db_password"] + "@" + fresh_db + ":5432/postgres")
        command(["docker", "run", "--rm", "--name", owner + "-fresh-auth-migrate", "--label", "owner=" + owner, "--network", owner,
                 "-e", "GOTRUE_JWT_SECRET", "-e", "GOTRUE_DB_DRIVER", "-e", "GOTRUE_DB_DATABASE_URL", "-e", "GOTRUE_SITE_URL", "-e", "API_EXTERNAL_URL", AUTH_IMAGE, "auth", "migrate"],
                env=fresh_env, label="fresh-auth-migrate.log", manifest=manifest)
        for relative, contents, _ in baseline_migrations():
            sql(manifest, "begin;\n" + contents + "\ncommit;", "fresh-" + Path(relative).name + ".log", container=fresh_db)
        sql(manifest, "create extension if not exists pgtap with schema extensions; create extension if not exists dblink with schema extensions;", "fresh-pgtap-install.log", container=fresh_db)
        sql(manifest, "alter database postgres set search_path = '$user', public, extensions", "fresh-search-path.log", container=fresh_db)
        manifest["fresh_database"] = {"container": fresh_db, "baseline_migrations": applied,
                                      "baseline_tap": run_tap(manifest, ["490_challenge_steps"], label_prefix="fresh-", container=fresh_db)}
        fixture = (ROOT / "supabase/tests/fixtures/challenge-fixture.inc").read_text()
        historical = sql(manifest, "begin;\n" + fixture + "\nselect pg_temp.beta_group(1,2);\ncommit;", "historical-fixture.log")
        manifest["historical_challenge_id"] = historical.splitlines()[-1]
        manifest["historical_agreement_keys"] = historical_agreement_keys(manifest)
        manifest["baseline_agreement_digest"] = agreement_digest(manifest)
        if not manifest["baseline_agreement_digest"]:
            raise RuntimeError("historical agreement digest was not populated")
        command(["docker", "run", "-d", "--name", manifest["auth"], "--label", "owner=" + owner,
                 "--network", owner, "-p", "127.0.0.1:" + str(manifest["auth_port"]) + ":9999",
                 "-e", "GOTRUE_JWT_SECRET", "-e", "GOTRUE_DB_DRIVER", "-e", "GOTRUE_DB_DATABASE_URL", "-e", "GOTRUE_SITE_URL", "-e", "API_EXTERNAL_URL", "-e", "GOTRUE_DISABLE_SIGNUP=true", "-e", "GOTRUE_EXTERNAL_EMAIL_ENABLED=false", AUTH_IMAGE], env=env,
                label="auth-start.log", manifest=manifest)
        created.append(("container", manifest["auth"]))
        command(["docker", "run", "-d", "--name", manifest["rest"], "--label", "owner=" + owner,
                 "--network", owner, "-p", "127.0.0.1:" + str(manifest["rest_port"]) + ":3000",
                 "-e", "PGRST_DB_URI", "-e", "PGRST_JWT_SECRET", "-e", "PGRST_DB_SCHEMAS", "-e", "PGRST_DB_ANON_ROLE", REST_IMAGE], env=env,
                label="rest-start.log", manifest=manifest)
        created.append(("container", manifest["rest"]))
        check_loopback(manifest, manifest["auth"], "9999/tcp", manifest["auth_port"])
        check_loopback(manifest, manifest["rest"], "3000/tcp", manifest["rest_port"])
        manifest["state"] = "baseline_prepared"
        write_manifest(args.manifest, manifest)
        print(json.dumps({"manifest": str(args.manifest), "db_port": manifest["db_port"], "auth_port": manifest["auth_port"], "rest_port": manifest["rest_port"], "state": manifest["state"]}, sort_keys=True))
    except BaseException:
        for kind, name in reversed(created):
            command(["docker", "rm", "-fv", name] if kind == "container" else ["docker", "network", "rm", name], env=env, check=False)
        raise


def apply_forward(args, manifest):
    requested_tap, args.tap = args.tap, []
    check_stack(args, manifest)
    args.tap = requested_tap
    if manifest.get("state") not in ("baseline_prepared", "forward_applied"):
        raise RuntimeError("forward migration requires a prepared baseline")
    migrations = forward_migrations(args)
    records = [{"path": str(migration.relative_to(ROOT)), "sha256": hashlib.sha256(migration.read_bytes()).hexdigest()}
               for migration in migrations]
    signature = "public.challenge_real_health_ingest_v1(uuid,jsonb,uuid,timestamptz,bytea,bigint,bytea,boolean)"
    applied = sql(manifest, "select to_regprocedure('" + signature + "') is not null") == "t"
    prior = manifest.get("forward_migrations")
    if manifest.get("state") == "forward_applied":
        if prior != records or not applied:
            raise RuntimeError("forward migration set differs from applied database; rebuild the owned baseline")
    elif applied:
        raise RuntimeError("prepared baseline already has the forward function; rebuild the owned baseline")
    else:
        for migration in migrations:
            sql(manifest, migration.read_text(), migration.name + ".log", single_transaction=True)
    if agreement_digest(manifest) != manifest["baseline_agreement_digest"]:
        raise RuntimeError("forward migration changed populated historical agreement digests")
    # PostgREST started before the forward migration. Refresh only its local
    # schema cache so the later supplied Edge-driver can reach the new RPC.
    sql(manifest, "notify pgrst, 'reload schema';", "postgrest-schema-reload.log")
    manifest["forward_migrations"] = records
    manifest["state"] = "forward_applied"
    # Record the primary upgrade before provisioning the independent test DB.
    # A later fresh-db setup failure must not make a committed migration look
    # absent and invite a second apply on the populated upgrade database.
    Path(args.manifest).write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    os.chmod(args.manifest, 0o600)
    fresh = prepare_fresh_test_database(manifest)
    # Persist the fresh database identity before a focused test runs, so a
    # failing pgTAP receipt is repeatable rather than leaving an untracked DB.
    Path(args.manifest).write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    os.chmod(args.manifest, 0o600)
    fresh_applied = sql(manifest, "select to_regprocedure('" + signature + "') is not null", container=fresh["container"]) == "t"
    if not fresh_applied:
        for migration in migrations:
            sql(manifest, migration.read_text(), "fresh-" + migration.name + ".log", single_transaction=True, container=fresh["container"])
    manifest["forward_tap"] = run_tap(manifest, args.tap, label_prefix="fresh-", container=fresh["container"])
    Path(args.manifest).write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    os.chmod(args.manifest, 0o600)
    print(json.dumps({"manifest": str(args.manifest), "state": manifest["state"], "focused_tap": manifest["forward_tap"]}, sort_keys=True))


def overlay_ingest(args, manifest):
    """Temporarily replace just the ingress RPC for an owned HTTP proof.

    This never changes `forward_migration` or `state`: only a later clean
    single-transaction apply may claim the full migration was verified.
    """
    check_stack(args, manifest)
    source = forward_migrations(args)[0].read_text()
    match = re.search(r"(?ms)^create function public[.]challenge_real_health_ingest_v1[(].*?^[$][$];", source)
    if match is None:
        raise RuntimeError("current migration has no ingest function to overlay")
    definition = match.group(0).replace("create function public.challenge_real_health_ingest_v1(",
                                        "create or replace function public.challenge_real_health_ingest_v1(", 1)
    digest = hashlib.sha256(definition.encode()).hexdigest()
    sql(manifest, definition, "overlay-ingest-" + digest[:12] + ".sql.log", single_transaction=True)
    overlays = manifest.setdefault("overlays", [])
    overlays.append({"kind": "ingest_function_only", "sha256": digest})
    Path(args.manifest).write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    os.chmod(args.manifest, 0o600)
    print(json.dumps({"manifest": str(args.manifest), "overlay": "ingest_function_only", "sha256": digest}, sort_keys=True))


def check_stack(args, manifest):
    inspect_owned(manifest, "network", manifest["network"])
    check_loopback(manifest, manifest["db"], "5432/tcp", manifest["db_port"])
    check_loopback(manifest, manifest["auth"], "9999/tcp", manifest["auth_port"])
    check_loopback(manifest, manifest["rest"], "3000/tcp", manifest["rest_port"])
    if sql(manifest, "show cron.launch_active_jobs") != "off" or sql(manifest, "select count(*) from cron.job_run_details") != "0":
        raise RuntimeError("owned stack has cron activity")
    fresh = manifest.get("fresh_database")
    if isinstance(fresh, dict) and fresh.get("container"):
        inspect_owned(manifest, "container", fresh["container"])
        if sql(manifest, "show cron.launch_active_jobs", container=fresh["container"]) != "off" or sql(manifest, "select count(*) from cron.job_run_details", container=fresh["container"]) != "0":
            raise RuntimeError("owned fresh stack has cron activity")
    if agreement_digest(manifest) != manifest["baseline_agreement_digest"]:
        raise RuntimeError("historical agreement digest changed")
    if args.tap:
        fresh = prepare_fresh_test_database(manifest)
        run_tap(manifest, args.tap, label_prefix="fresh-", container=fresh["container"])


def cleanup(path, manifest):
    fresh = manifest.get("fresh_database") if isinstance(manifest.get("fresh_database"), dict) else {}
    resources = [("container", manifest["rest"]), ("container", manifest["auth"])]
    if fresh.get("container"):
        resources.append(("container", fresh["container"]))
    resources.extend((("container", manifest["db"]), ("network", manifest["network"])))
    for kind, name in resources:
        result = command(["docker", kind, "inspect", name], check=False)
        if result.returncode:
            continue
        row = json.loads(result.stdout)[0]
        labels = row["Config"]["Labels"] if kind == "container" else row["Labels"]
        if labels.get("owner") != manifest["owner"]:
            raise RuntimeError("refusing cleanup of unowned resource")
        command(["docker", "rm", "-fv", name] if kind == "container" else ["docker", "network", "rm", name])
    path.unlink(missing_ok=True)
    print("owned P8 stack removed")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("error: " + str(error), file=sys.stderr)
        raise SystemExit(1)
