#!/usr/bin/env python3
"""Disposable loopback controller for DuelNativeLocalSmokeTests; no hosted access.

Pass --simulator UUID to build and run the native test, or leave this running
while using XcodeBuildMCP as documented in docs/DUEL_NATIVE_V1_ACCEPTANCE.md.
Completion or Ctrl-C closes admission, cancels this run's
open agreements, revokes its sessions and removes its temporary credentials.
Historical fictional agreements are retained through the normal RPCs.
"""
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
API = "http://127.0.0.1:54321"
DB = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
CONFIG = ROOT / "tmp/duel-native-smoke.json"
REPORT = ROOT / "tmp/duel-native-smoke-report.json"


def sql(statement):
    return subprocess.run(
        ["psql", DB, "--no-psqlrc", "-XAt", "-v", "ON_ERROR_STOP=1"],
        input=statement, text=True, capture_output=True, check=True,
    ).stdout.strip()


def local_http(method, path, headers, body=None):
    connection = http.client.HTTPConnection("127.0.0.1", 54321, timeout=25)
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
        # Refuse to alter another local experiment's active admission.
        if sql("select not admission_enabled and not exists "
               "(select 1 from app.duel_beta_allowlist) from app.duel_runtime;") != "t":
            raise RuntimeError("Local duel admission must already be off with an empty allowlist")
        if sql("select not enabled from app.duel_lifecycle_runtime;") != "t":
            raise RuntimeError("Local lifecycle gate must already be off")
        for label in ("a", "b"):
            email = f"duel-smoke-{uuid.uuid4().hex}@example.invalid"
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
        sql("begin; set local role service_role; "
            f"select public.curate_duel_fixture_event_v1('{self.event}',"
            "clock_timestamp()+interval '7 days',clock_timestamp()+interval '7 days 2 hours',"
            "'America/Chicago'); commit;")
        CONFIG.parent.mkdir(exist_ok=True)
        with CONFIG.open("x") as stream:
            os.chmod(CONFIG, 0o600)
            json.dump({"url": "http://127.0.0.1:54329", "key": self.key,
                       "controlToken": self.token,
                       "actors": self.actors, "eventID": self.event}, stream)

    def gate(self, enabled):
        actors = ",".join(f"'{a['id']}'::uuid" for a in self.actors) if enabled else ""
        sql("begin; set local role service_role; "
            f"select public.set_duel_admission_v1({'true' if enabled else 'false'},"
            f"array[{actors}]::uuid[]); commit;")

    def seed_lifecycle(self):
        if self.lifecycle_id:
            return
        a, b = (actor["id"] for actor in self.actors)
        self.owned_lifecycle = True
        self.gate(True)
        try:
            output = sql(f"""
            begin;
            select public.set_duel_lifecycle_enabled_v1(true);
            do $local$
            declare t timestamptz:=clock_timestamp()-interval '10 days';
              e uuid:=extensions.gen_random_uuid(); c uuid; i jsonb; d jsonb;
            begin
              perform public.curate_duel_fixture_event_v1(e,t+interval '3 days',t+interval '3 days 2 hours','America/Chicago');
              perform set_config('request.jwt.claim.sub','{a}',true);
              c:=app.create_duel_at_v1(extensions.gen_random_uuid(),'{b}',e,'duel-fixture-5k-v1',true,t);
              perform set_config('request.jwt.claim.sub','{b}',true);
              perform app.respond_duel_at_v1('accept_duel_v1',extensions.gen_random_uuid(),c,'duel-fixture-5k-v1',
                (select terms_digest from public.duel_challenges where id=c),t+interval '1 hour');
              i:=app.duel_lifecycle_load_at_v1(c,clock_timestamp()-interval '1 hour');
              d:=jsonb_build_object('version','duel-fixture-official-5k-v1','challengeId',c,
                'termsDigest',i->'agreement'->'terms_digest','phase','provisional','proofRevision',0,
                'outcome',jsonb_build_object('kind','void','reason','unresolved_proof'),
                'disputeClosesAt',null,'reviewDueAt',null,'supportCorrectionRequired',false);
              perform app.duel_lifecycle_commit_at_v1(i,d,clock_timestamp()-interval '1 hour');
              perform set_config('duel.smoke_id',c::text,true);
            end; $local$;
            select public.set_duel_lifecycle_enabled_v1(false);
            select current_setting('duel.smoke_id');
            commit;
            """)
            self.lifecycle_id = str(uuid.UUID(output.splitlines()[-2]))
        finally:
            self.gate(False)

    def lifecycle_worker(self):
        assert self.lifecycle_id
        sql("select public.set_duel_lifecycle_enabled_v1(true);")
        try:
            env = {**os.environ, "DUEL_LOCAL_URL": API,
                   "DUEL_LOCAL_SERVICE_ROLE_KEY": self.admin["apikey"]}
            subprocess.run(["deno", "run", "--config", "supabase/functions/deno.json",
                "--allow-env=DUEL_LOCAL_URL,DUEL_LOCAL_SERVICE_ROLE_KEY", "--allow-net=127.0.0.1:54321",
                "scripts/duel-lifecycle-local-worker.ts", self.lifecycle_id], cwd=ROOT, env=env,
                capture_output=True, check=True, timeout=30)
        finally:
            sql("select public.set_duel_lifecycle_enabled_v1(false);")

    def snapshot(self):
        actors = ",".join(f"'{a['id']}'::uuid" for a in self.actors)
        value = sql("select json_build_object("
            "'agreements', (select count(*) from public.duel_challenges "
            f"where creator_id in ({actors})),"
            "'requests', (select count(*) from app.duel_requests "
            f"where actor_id in ({actors})),"
            "'consents', (select count(*) from public.duel_participants "
            f"where actor_id in ({actors}) and accepted_at is not null),"
            "'openSlots', (select count(*) from app.duel_enrollments "
            f"where actor_id in ({actors}) and released_at is null),"
            "'admission', (select admission_enabled from app.duel_runtime),"
            "'allowlist', (select count(*) from app.duel_beta_allowlist),"
            f"'sessions', (select count(*) from auth.sessions where user_id in ({actors})),"
            f"'refreshTokens', (select count(*) from auth.refresh_tokens where user_id::uuid in ({actors})),"
            f"'event', (select row_to_json(e) from public.duel_event_fixtures e where id='{self.event}'));")
        with self.lock:
            trace = list(self.trace)
        return {**json.loads(value), "held": self.held.is_set(), "trace": trace,
                "lifecycleID": self.lifecycle_id,
                "reviewCases": int(sql("select count(*) from app.duel_lifecycle_cases "
                    f"where actor_id in ({actors});")),
                "lifecycleGate": sql("select enabled from app.duel_lifecycle_runtime;") == "t"}

    def cleanup(self):
        self.release.set()
        if self.owned_admission:
            self.gate(False)
            # Cancel only agreements created by this run; never delete history
            # or disable immutability triggers for cleanup.
            for actor in self.actors:
                sql("begin; set local role authenticated; "
                    f"set local request.jwt.claim.sub='{actor['id']}'; "
                    "select public.cancel_duel_v1(extensions.gen_random_uuid(),id) "
                    f"from public.duel_challenges where creator_id='{actor['id']}' "
                    "and status in ('invited','scheduled') and starts_at>clock_timestamp(); commit;")
        if self.lifecycle_id:
            # Close only this experiment if its participant exit was never reached.
            needs_exit = sql("select not exists(select 1 from app.duel_lifecycle_closures "
                f"where challenge_id='{self.lifecycle_id}') and not exists(select 1 from app.duel_lifecycle_results "
                f"where challenge_id='{self.lifecycle_id}');") == "t"
            if needs_exit:
                sql("begin; set local role service_role; "
                    f"select public.cancel_duel_event_v1(extensions.gen_random_uuid(),'{self.lifecycle_id}'); commit;")
            self.lifecycle_worker()
        if self.owned_lifecycle:
            sql("select public.set_duel_lifecycle_enabled_v1(false);")
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
                elif action == "lifecycle-worker":
                    smoke.lifecycle_worker()
                elif action == "lifecycle-block":
                    a, b = (actor["id"] for actor in smoke.actors)
                    sql(f"insert into public.blocks(blocker_id,blocked_id) values('{a}','{b}') on conflict do nothing;")
                elif action == "lifecycle-unblock":
                    a, b = sorted(actor["id"] for actor in smoke.actors)
                    sql(f"delete from public.blocks where (blocker_id,blocked_id) in (('{a}','{b}'),('{b}','{a}'));"
                        f"insert into public.friendships(user_a,user_b,requested_by,status) values('{a}','{b}','{a}','accepted') "
                        "on conflict(user_a,user_b) do update set status='accepted';")
                elif action == "arm":
                    arm = json.loads(body)
                    assert arm["mode"] in ("lose", "hold")
                    assert arm["rpc"] in ("create_duel_v1", "accept_duel_v1", "get_duel_v1",
                        "get_duel_lifecycle_v1", "file_duel_review_v1", "exit_duel_v1",
                        "rematch_duel_v1", "issue_duel_link_v1", "get_my_duel_link_v1", "resolve_duel_link_v1", "revoke_duel_link_v1")
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
            self.reply(500, {"error": "local smoke controller failed"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status-file", required=True, type=Path)
    parser.add_argument("--simulator", help="Run xcodebuild test on this simulator UUID, then clean up")
    parser.add_argument("--derived-data", type=Path, default=ROOT / "DerivedData/Codex-DuelAcceptance")
    args = parser.parse_args()
    if CONFIG.exists():
        raise RuntimeError(f"Another smoke manifest exists: {CONFIG}")
    smoke = Smoke(json.loads(args.status_file.read_text()))
    # Bind before seeding to prevent concurrent controllers owning admission.
    server = ThreadingHTTPServer(("127.0.0.1", 54329), Handler)
    server.daemon_threads = True
    server.smoke = smoke
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    running = False
    exit_code = 0
    try:
        smoke.setup()
        print("READY: local native smoke on 127.0.0.1:54329; two fictional accounts admitted.", flush=True)
        if args.simulator:
            # Xcode destination lookup is case-sensitive for simulator UDIDs.
            simulator = str(uuid.UUID(args.simulator)).upper()
            threading.Thread(target=server.serve_forever, daemon=True).start()
            running = True
            stamp = uuid.uuid4().hex[:8]
            result = ROOT / f"tmp/duel-native-{stamp}.xcresult"
            log = ROOT / f"tmp/duel-native-{stamp}.log"
            command = ["xcodebuild", "-project", str(ROOT / "ios/GameTime/GameTime.xcodeproj"),
                "-scheme", "GameTime", "-configuration", "Debug", "-destination",
                f"platform=iOS Simulator,id={simulator}", "-derivedDataPath", str(args.derived_data),
                "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                "-only-testing:GameTimeTests/DuelNativeLocalSmokeTests", "CODE_SIGNING_ALLOWED=NO",
                "SUPABASE_URL=http://127.0.0.1:54329", "SUPABASE_PUBLISHABLE_KEY=" + smoke.key, "test"]
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
