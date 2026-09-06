#!/usr/bin/env python3
"""Disposable loopback controller for PerformanceCommitmentNativeSmokeTests; no hosted access.

Pass --simulator UUID to build and run the native test, or leave this running
while using XcodeBuildMCP as documented in
docs/PERFORMANCE_COMMITMENT_NATIVE_V1_ACCEPTANCE.md.
Completion or Ctrl-C closes admission, cancels this run's
open agreements, revokes its sessions and removes its temporary credentials.
Historical fictional agreements are retained through the normal RPCs.
Requires a fresh disposable 5732x stack; the ordinary development stack is never used.
"""
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import sys
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
API = "http://127.0.0.1:57321"
DB = "postgresql://postgres:postgres@127.0.0.1:57322/postgres"
CONFIG = ROOT / "tmp/performance-commitment-native-smoke.json"
REPORT = ROOT / "tmp/performance-commitment-native-smoke-report.json"


def sql(statement):
    return subprocess.run(
        ["psql", DB, "--no-psqlrc", "-XAt", "-v", "ON_ERROR_STOP=1"],
        input=statement, text=True, capture_output=True, check=True,
    ).stdout.strip()


def local_http(method, path, headers, body=None):
    connection = http.client.HTTPConnection("127.0.0.1", 57321, timeout=25)
    try:
        connection.request(method, path, body, headers)
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        connection.close()


class Smoke:
    def __init__(self, settings):
        assert settings["API_URL"] == API and settings["DB_URL"] == DB
        self.key = settings["PUBLISHABLE_KEY"]
        self.admin = {"apikey": settings["SERVICE_ROLE_KEY"],
                      "Authorization": "Bearer " + settings["SERVICE_ROLE_KEY"],
                      "Content-Type": "application/json"}
        self.token = secrets.token_urlsafe(32)
        self.password = secrets.token_urlsafe(32)
        self.actors = []
        # This event exists only for the controller's fictional proof history.
        self.event = str(uuid.uuid4())
        self.trace = []
        self.lock = threading.Lock()
        self.arm = None
        self.held = threading.Event()
        self.release = threading.Event()
        self.owned_admission = False
        self.lifecycle_id = None
        self.owned_lifecycle = False

    def admin_call(self, method, path, payload):
        status, _, data = local_http(method, "/auth/v1/admin/" + path, self.admin,
                               json.dumps(payload).encode())
        if status >= 300:
            raise RuntimeError(f"Local Auth admin {method} failed: HTTP {status}")
        return json.loads(data)

    def setup(self):
        # This dedicated stack must be idle before the controller takes ownership.
        if sql("select not admission_enabled and not exists "
               "(select 1 from app.performance_commitment_beta_allowlist) "
               "from app.performance_commitment_runtime;") != "t":
            raise RuntimeError("Commitment admission must be off with an empty allowlist")
        if sql("select not enabled from app.performance_lifecycle_runtime;") != "t":
            raise RuntimeError("Lifecycle gate must already be off")
        if sql("select not enabled from app.performance_attempt_runtime;") != "t":
            raise RuntimeError("Attempt gate must already be off")
        for label in ("a", "b"):
            email = f"commitment-smoke-{uuid.uuid4().hex}@example.invalid"
            user = self.admin_call("POST", "users", {
                "email": email, "password": self.password, "email_confirm": True,
            })
            actor = str(uuid.UUID(user["id"]))
            self.actors.append({"id": actor, "email": email})
            sql(f"insert into public.profiles(id,handle,display_name,timezone) values "
                f"('{actor}','smoke_{uuid.uuid4().hex[:16]}','Fictional Runner {label.upper()}',"
                "'America/Chicago');")
        self.owned_admission = True
        self.gate(True)
        CONFIG.parent.mkdir(exist_ok=True)
        with CONFIG.open("x") as stream:
            os.chmod(CONFIG, 0o600)
            json.dump({"url": "http://127.0.0.1:57329", "key": self.key,
                       "controlToken": self.token, "actors": self.actors}, stream)

    def gate(self, enabled):
        actors = ",".join(f"'{a['id']}'::uuid" for a in self.actors) if enabled else ""
        sql("begin; set local role service_role; "
            f"select public.set_performance_commitment_admission_v1({'true' if enabled else 'false'},"
            f"array[{actors}]::uuid[]); commit;")

    def login_sql(self, actor):
        # Select the real current GoTrue session, without exporting its JWT.
        return f"""
        select set_config('request.jwt.claim.sub','{actor}',true);
        select set_config('request.jwt.claims',jsonb_build_object('sub','{actor}',
          'role','authenticated','session_id',(select id from auth.sessions
          where user_id='{actor}' and (not_after is null or not_after>clock_timestamp())
          order by created_at desc limit 1))::text,true);
        set local role authenticated;
        """

    def seed_lifecycle(self):
        if self.lifecycle_id:
            return
        a = self.actors[0]["id"]
        self.owned_lifecycle = True
        self.gate(True)
        try:
            # Historical clock only in private SQL test seams; immutable terms
            # and consents are created through the existing agreement function.
            output = sql(f"""
            begin;
            create function pg_temp.create_fixture() returns uuid language plpgsql
            security definer set search_path='' as $fixture$
            declare s timestamptz:=clock_timestamp()-interval '32 days';
              d timestamptz:=s+interval '28 days'; t jsonb;
            begin
              t:=app.performance_commitment_terms_v1(auth.uid(),1500,s,d,'America/Chicago',
                'performance-commitment-fixture-5k-v1');
              return app.create_performance_commitment_at_v1(extensions.gen_random_uuid(),1500,s,d,
                'America/Chicago','performance-commitment-fixture-5k-v1',
                encode(extensions.digest(t::text,'sha256'),'hex'),true,s-interval '1 day');
            end; $fixture$;
            {self.login_sql(a)}
            select pg_temp.create_fixture();
            commit;
            """)
            self.lifecycle_id = str(uuid.UUID(output.splitlines()[-2]))
            self.seed_proof(1499, False)
            self.tick("clock_timestamp()-interval '4 hours'", False)
        finally:
            self.gate(False)

    def seed_proof(self, seconds, correction):
        assert self.lifecycle_id
        a, b = (actor["id"] for actor in self.actors)
        c = self.lifecycle_id
        proof_clock = "clock_timestamp()" if correction else "clock_timestamp()-interval '30 hours'"
        sql("select public.set_commitment_attempts_enabled_v1(true);")
        try:
            sql(f"""
            begin;
            create function pg_temp.nominate_fixture(c uuid,e uuid) returns uuid language sql
            security definer set search_path='' as $fixture$
              select app.nominate_commitment_attempt_at_v1(extensions.gen_random_uuid(),c,e,'fictional-bib',
                (select starts_at-interval '1 hour' from app.performance_commitment_agreements where id=c))
            $fixture$;
            create function pg_temp.review_fixture(c uuid,s uuid) returns integer language sql
            security definer set search_path='' as $fixture$
              select app.review_commitment_attempt_at_v1(extensions.gen_random_uuid(),c,s,
                (select max(revision) from app.performance_attempt_revisions where commitment_id=c),true,
                {proof_clock})
            $fixture$;
            create function pg_temp.latest_source(c uuid) returns uuid language sql
            security definer set search_path='' as $fixture$
              select id from app.performance_attempt_sources where commitment_id=c order by captured_at desc limit 1
            $fixture$;
            select public.set_commitment_attempt_reviewer_v1(extensions.gen_random_uuid(),'{c}','{b}',true);
            select public.curate_commitment_fixture_event_v1('{self.event}',starts_at+interval '2 days',
              starts_at+interval '2 days 2 hours') from app.performance_commitment_agreements where id='{c}';
            {self.login_sql(a)}
            {'' if correction else f"select pg_temp.nominate_fixture('{c}','{self.event}');"}
            reset role;
            select app.capture_commitment_attempt_at_v1('{uuid.uuid4()}','{c}',n.id,
              jsonb_build_object('source','fixture_official_5k_v1','event_id',n.event_id,'distance_meters',5000,
                'timing_basis','organizer_chip','precision_ms',1000,'published_bib','fictional-bib',
                'status','finished','chip_seconds',{seconds},'started_at',e.starts_at,
                'finished_at',e.starts_at+{seconds}*interval '1 second'),
              {proof_clock})
              from app.performance_attempt_nominations n join app.performance_attempt_events e on e.id=n.event_id
              where n.commitment_id='{c}';
            {self.login_sql(b)}
            select public.get_commitment_attempt_source_v1('{c}',pg_temp.latest_source('{c}'));
            select pg_temp.review_fixture('{c}',pg_temp.latest_source('{c}'));
            commit;
            """)
        finally:
            sql("select public.set_commitment_attempts_enabled_v1(false);")

    def tick(self, clock, settle):
        assert self.lifecycle_id
        sql("select public.set_commitment_lifecycle_enabled_v1(true);")
        try:
            at = sql(f"select {clock};")
            payload = sql(f"select app.performance_lifecycle_load_at_v1('{self.lifecycle_id}','{at}');")
            result = subprocess.run(["deno", "run", "--config", "supabase/functions/deno.json",
                "scripts/examples/performance-commitment-native-evaluate.ts"], cwd=ROOT,
                input=payload, capture_output=True, text=True, check=True, timeout=30)
            # JSON is data; use SQL literal quoting rather than shell interpolation.
            decision = result.stdout.strip().replace("'", "''")
            payload = payload.replace("'", "''")
            status = sql(f"select app.performance_lifecycle_commit_at_v1('{payload}'::jsonb,"
                         f"'{decision}'::jsonb,'{at}');")
            if status == "stale":
                raise RuntimeError("Fixture unexpectedly changed during evaluation")
            if settle and status == "final":
                sql(f"select app.performance_lifecycle_settle_at_v1('{self.lifecycle_id}','{at}');")
            return status
        finally:
            sql("select public.set_commitment_lifecycle_enabled_v1(false);")

    def snapshot(self):
        actors = ",".join(f"'{a['id']}'::uuid" for a in self.actors)
        value = sql("select json_build_object("
            "'agreements', (select count(*) from app.performance_commitment_agreements "
            f"where actor_id in ({actors})),"
            "'requests', (select count(*) from app.performance_commitment_requests "
            f"where actor_id in ({actors})),"
            "'openSlots', (select count(*) from app.performance_commitment_enrollments "
            f"where actor_id in ({actors}) and released_at is null),"
            "'admission', (select admission_enabled from app.performance_commitment_runtime),"
            "'allowlist', (select count(*) from app.performance_commitment_beta_allowlist),"
            f"'sessions', (select count(*) from auth.sessions where user_id in ({actors})),"
            f"'refreshTokens', (select count(*) from auth.refresh_tokens where user_id::uuid in ({actors})),"
            "'reviewCases', (select count(*) from app.performance_lifecycle_cases k join "
            f"app.performance_commitment_agreements c on c.id=k.commitment_id where c.actor_id in ({actors})),"
            "'lifecycleGate', (select enabled from app.performance_lifecycle_runtime),"
            "'attemptGate', (select enabled from app.performance_attempt_runtime));")
        with self.lock:
            trace = list(self.trace)
        return {**json.loads(value), "held": self.held.is_set(), "trace": trace,
                "lifecycleID": self.lifecycle_id}

    def cleanup(self):
        self.release.set()
        if self.owned_admission:
            self.gate(False)
            for actor in self.actors:
                # Historical receipts remain immutable; only normal safe exits.
                ids = sql("select id from app.performance_commitment_agreements c "
                    f"where actor_id='{actor['id']}' and status='open' and not exists "
                    "(select 1 from app.performance_lifecycle_results r where r.commitment_id=c.id);")
                if ids:
                    link = self.admin_call('POST', 'generate_link', {'type': 'magiclink', 'email': actor['email']})
                    status, _, _ = local_http('POST', '/auth/v1/verify',
                        {'apikey': self.key, 'Content-Type': 'application/json'},
                        json.dumps({'token_hash': link['hashed_token'], 'type': 'magiclink'}).encode())
                    if status >= 300:
                        raise RuntimeError('Could not open cleanup session')
                for commitment in ids.splitlines():
                    reason = sql("select case when starts_at>clock_timestamp() then 'cancel' else 'injury' end "
                                 f"from app.performance_commitment_agreements where id='{commitment}';")
                    sql(f"begin; {self.login_sql(actor['id'])} select public.close_performance_commitment_v1("
                        f"extensions.gen_random_uuid(),'{commitment}','{reason}'); commit;")
        if self.owned_lifecycle:
            sql("select public.set_commitment_lifecycle_enabled_v1(false); "
                "select public.set_commitment_attempts_enabled_v1(false);")
        for actor in self.actors:
            self.admin_call("PUT", "users/" + actor["id"], {
                "password": secrets.token_urlsafe(48), "ban_duration": "876000h",
            })
            sql(f"delete from auth.sessions where user_id='{actor['id']}'; "
                f"delete from auth.refresh_tokens where user_id='{actor['id']}';")
        CONFIG.unlink(missing_ok=True)
        if self.owned_admission:
            REPORT.write_text(json.dumps(self.snapshot(), indent=2) + "\n")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log Authorization, credentials, or private response bodies.

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.dispatch()

    def do_POST(self):
        self.dispatch()

    def do_PATCH(self):
        self.dispatch()

    def dispatch(self):
        smoke = self.server.smoke
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        try:
            if self.path.startswith("/__smoke/"):
                if not secrets.compare_digest(self.headers.get("X-Smoke-Token", ""), smoke.token):
                    return self.reply(403, {"error": "control token required"})
                action = self.path.removeprefix("/__smoke/")
                if action == "gate-off":
                    smoke.gate(False)
                elif action == "gate-on":
                    smoke.gate(True)
                elif action == "lifecycle-seed":
                    smoke.seed_lifecycle()
                elif action == "lifecycle-correct":
                    smoke.seed_proof(1500, True)
                    smoke.tick("clock_timestamp()", False)
                elif action == "lifecycle-final":
                    smoke.tick("clock_timestamp()", False)
                elif action == "lifecycle-settle":
                    smoke.tick("clock_timestamp()", True)
                elif action == "revoke-sessions":
                    actor = str(uuid.UUID(json.loads(body)["actorID"]))
                    assert actor in [a["id"] for a in smoke.actors]
                    sql(f"delete from auth.sessions where user_id='{actor}'; "
                        f"delete from auth.refresh_tokens where user_id='{actor}';")
                elif action == "arm":
                    arm = json.loads(body)
                    assert arm["mode"] in ("lose", "hold")
                    assert arm["rpc"] in ("create_performance_commitment_v1", "get_performance_commitment_v1",
                        "get_commitment_lifecycle_v1", "file_commitment_review_v1", "close_performance_commitment_v1")
                    with smoke.lock:
                        assert smoke.arm is None
                        smoke.held.clear()
                        smoke.release.clear()
                        smoke.arm = arm
                elif action == "release":
                    smoke.release.set()
                elif action == "login-token":
                    actor_id = json.loads(body)["actorID"]
                    actor = next(a for a in smoke.actors if a["id"] == actor_id.lower())
                    link = smoke.admin_call("POST", "generate_link", {
                        "type": "magiclink", "email": actor["email"],
                    })
                    return self.reply(200, {"tokenHash": link["hashed_token"]})
                elif action != "state":
                    return self.reply(404, {})
                return self.reply(200, smoke.snapshot())
            # No arbitrary targets, redirects, service keys, or admin proxy.
            if not (self.path.startswith("/rest/v1/") or self.path.startswith("/auth/v1/token")
                    or self.path.startswith("/auth/v1/logout") or self.path == "/auth/v1/verify"):
                return self.reply(403, {})
            if self.headers.get("apikey") != smoke.key:
                return self.reply(403, {})
            headers = {k: v for k, v in self.headers.items()
                       if k.lower() not in ("host", "connection", "content-length", "accept-encoding")}
            status, response_headers, data = local_http(self.command, self.path, headers, body)
            rpc = self.path.split("/rpc/")[-1] if "/rpc/" in self.path else None
            arm = None
            if rpc:
                params = json.loads(body) if body else {}
                with smoke.lock:
                    smoke.trace.append({"rpc": rpc, "status": status,
                        "requestID": params.get("p_request_id"),
                        "payloadHash": hashlib.sha256(body).hexdigest()})
                    if smoke.arm and smoke.arm["rpc"] == rpc and status < 300:
                        arm, smoke.arm = smoke.arm, None
                if arm and arm["mode"] == "lose":
                    # Upstream committed, but its response never reaches Swift.
                    # A synthetic gateway timeout avoids URLSession auto-retry.
                    return self.reply(504, {"message": "deliberately lost local response"})
                if arm and arm["mode"] == "hold":
                    smoke.held.set()
                    if not smoke.release.wait(45):
                        return self.reply(504, {"message": "local hold timed out"})
            self.send_response(status)
            self.send_header("Content-Type", response_headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as error:
            print(f"Controller failed: {type(error).__name__}", flush=True)
            if isinstance(error, subprocess.CalledProcessError) and error.stderr:
                # Database error names help debug fictional fixtures; omit SQL,
                # Auth data, response bodies and every contextual statement.
                for line in error.stderr.splitlines():
                    plain = re.sub(r"\x1b\[[0-9;]*m", "", line)
                    if plain.startswith("ERROR:") or plain.startswith("error:"):
                        print(plain, flush=True)
            self.reply(500, {"error": "local smoke controller failed"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status-file", required=True, type=Path)
    parser.add_argument("--simulator", help="Run xcodebuild test on this simulator UUID, then clean up")
    parser.add_argument("--derived-data", type=Path, default=ROOT / "DerivedData/Codex-CommitmentAcceptance")
    args = parser.parse_args()
    if CONFIG.exists():
        raise RuntimeError(f"Another smoke manifest exists: {CONFIG}")
    smoke = Smoke(json.loads(args.status_file.read_text()))
    # Bind before seeding to prevent concurrent controllers owning admission.
    server = ThreadingHTTPServer(("127.0.0.1", 57329), Handler)
    server.daemon_threads = True
    server.smoke = smoke
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    running = False
    exit_code = 0
    try:
        smoke.setup()
        print("READY: local native smoke on 127.0.0.1:57329; two fictional owners admitted.", flush=True)
        if args.simulator:
            # Xcode destination lookup is case-sensitive for simulator UDIDs.
            simulator = str(uuid.UUID(args.simulator)).upper()
            threading.Thread(target=server.serve_forever, daemon=True).start()
            running = True
            stamp = uuid.uuid4().hex[:8]
            result = ROOT / f"tmp/performance-commitment-native-{stamp}.xcresult"
            log = ROOT / f"tmp/performance-commitment-native-{stamp}.log"
            command = ["xcodebuild", "-project", str(ROOT / "ios/GameTime/GameTime.xcodeproj"),
                "-scheme", "GameTime", "-configuration", "Debug", "-destination",
                f"platform=iOS Simulator,id={simulator}", "-derivedDataPath", str(args.derived_data),
                "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                "-only-testing:GameTimeTests/PerformanceCommitmentNativeSmokeTests", "CODE_SIGNING_ALLOWED=NO",
                "SUPABASE_URL=http://127.0.0.1:57329", "SUPABASE_PUBLISHABLE_KEY=" + smoke.key, "test"]
            with log.open("w") as stream:
                exit_code = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT).returncode
            print(f"Native test exit {exit_code}; result: {result}; log: {log}", flush=True)
        else:
            server.serve_forever()
    except KeyboardInterrupt:
        exit_code = 130
    finally:
        if running:
            server.shutdown()
        server.server_close()
        smoke.cleanup()
        print(f"CLEAN: admission off, sessions revoked; retained report: {REPORT}", flush=True)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
