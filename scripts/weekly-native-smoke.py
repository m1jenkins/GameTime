#!/usr/bin/env python3
"""Disposable loopback-only native weekly 2/5/community/recovery acceptance.
Starts only on the dedicated 5632x stack with gates off. Auth identities are
fictional; no email is sent. Cleanup disables gates and revokes these sessions,
retaining fictional history for inspection. Pass --simulator to run and clean up.
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
API = "http://127.0.0.1:56321"
DB = "postgresql://postgres:postgres@127.0.0.1:56322/postgres"
CONFIG = ROOT / "tmp/weekly-native-smoke.json"
REPORT = ROOT / "tmp/weekly-native-smoke-report.json"


def sql(statement):
    return subprocess.run(
        ["psql", DB, "--no-psqlrc", "-XAt", "-v", "ON_ERROR_STOP=1"],
        input=statement, text=True, capture_output=True, check=True,
    ).stdout.strip()


def local_http(method, path, headers, body=None):
    connection = http.client.HTTPConnection("127.0.0.1", 56321, timeout=25)
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
        self.service_key = settings["SERVICE_ROLE_KEY"]
        self.admin = {"apikey": settings["SERVICE_ROLE_KEY"], "Authorization": "Bearer " + settings["SERVICE_ROLE_KEY"], "Content-Type": "application/json"}
        self.token = secrets.token_urlsafe(32)
        self.password = secrets.token_urlsafe(32)
        self.actors = []
        self.trace = []
        self.lock = threading.Lock()
        self.arm = None
        self.held = threading.Event()
        self.release = threading.Event()
        self.owned_admission = False
        self.cohort = str(uuid.uuid4())

    def admin_call(self, method, path, payload):
        status, _, data = local_http(method, "/auth/v1/admin/" + path, self.admin, json.dumps(payload).encode())
        if status >= 300:
            raise RuntimeError(f"Local Auth admin {method} failed: HTTP {status}")
        return json.loads(data)

    def setup(self):
        if sql("select not enabled and not fixture_enabled and not worker_enabled and cardinality(actor_ids)=0 from app.weekly_runtime where singleton;") != "t":
            raise RuntimeError("Weekly gates must start off with an empty allowlist")
        for index in range(6):
            email = f"weekly-smoke-{uuid.uuid4().hex}@example.invalid"
            user = self.admin_call("POST", "users", {"email": email, "password": self.password, "email_confirm": True})
            actor = str(uuid.UUID(user["id"]))
            self.actors.append({"id": actor, "email": email})
            sql(f"insert into public.profiles(id,handle,display_name,timezone) values ('{actor}','weekly_{uuid.uuid4().hex[:16]}','Fictional Walker {index + 1}','America/Chicago');")
        a = self.actors[0]["id"]
        for other in self.actors[1:5]:
            b = other["id"]
            sql(f"insert into public.friendships(user_a,user_b,requested_by,status) values(least('{a}'::uuid,'{b}'::uuid),greatest('{a}'::uuid,'{b}'::uuid),'{a}','accepted');")
        self.owned_admission = True
        self.gate(True)
        seeded = subprocess.run(["deno", "run", "--config", "supabase/functions/deno.json", "--allow-run=psql", "scripts/weekly-native-lifecycle-seed.ts", a, self.actors[1]["id"]], cwd=ROOT, text=True, capture_output=True, check=True)
        self.history = json.loads(seeded.stdout)
        # One official future cohort; the numeric target is deliberately a fixture.
        sql("begin; set local role service_role; select public.curate_weekly_cohort_v1(" +
            f"'{self.cohort}',(date_trunc('week',clock_timestamp() at time zone 'America/Chicago')+interval '14 days')::date,'America/Chicago',12000,10); commit;")
        CONFIG.parent.mkdir(exist_ok=True)
        with CONFIG.open("x") as stream:
            os.chmod(CONFIG,0o600)
            json.dump({"url":"http://127.0.0.1:56329","key":self.key,"controlToken":self.token,"actors":self.actors,"cohortID":self.cohort,"history":self.history},stream)

    def gate(self, enabled):
        actors = ",".join(f"'{a['id']}'::uuid" for a in self.actors) if enabled else ""
        sql("begin; set local role service_role; select public.set_weekly_runtime_v1(" +
            f"{'true' if enabled else 'false'},false,false,array[{actors}]::uuid[]); commit;")

    def login_sql(self, actor):
        return f"""select set_config('request.jwt.claim.sub','{actor}',true);
        select set_config('request.jwt.claims',jsonb_build_object('sub','{actor}','role','authenticated','session_id',
        (select id from auth.sessions where user_id='{actor}' order by created_at desc limit 1))::text,true);
        set local role authenticated;"""

    def snapshot(self):
        ids = ",".join(f"'{a['id']}'::uuid" for a in self.actors) or "null::uuid"
        value = json.loads(sql(f"select jsonb_build_object('agreements',(select count(*) from app.weekly_agreements where creator_id in ({ids})),'requests',(select count(*) from app.weekly_requests where actor_id in ({ids})),'admission',enabled,'allowlist',cardinality(actor_ids)) from app.weekly_runtime where singleton;"))
        value["trace"] = list(self.trace)
        value["held"] = self.held.is_set()
        return value

    def cleanup(self):
        self.release.set()
        if self.owned_admission:
            self.gate(False)
        for actor in self.actors:
            # Ban and revoke these disposable identities; no external message is sent.
            self.admin_call("PUT","users/"+actor["id"],{"password":secrets.token_urlsafe(48),"ban_duration":"876000h"})
            sql(f"delete from auth.sessions where user_id='{actor['id']}'; delete from auth.refresh_tokens where user_id='{actor['id']}';")
        CONFIG.unlink(missing_ok=True)
        if self.owned_admission:
            REPORT.write_text(json.dumps(self.snapshot(),indent=2)+"\n")


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
                elif action == "finalize-history":
                    history = smoke.history
                    subprocess.run(["deno", "run", "--config", "supabase/functions/deno.json", "--allow-run=psql", "scripts/weekly-native-lifecycle-seed.ts", smoke.actors[0]["id"], smoke.actors[1]["id"], "finalize", history["reviewID"], history["reviewRequestID"]], cwd=ROOT, text=True, check=True, capture_output=True)
                elif action == "worker":
                    actor_ids = [a["id"] for a in smoke.actors]
                    challenge = str(uuid.UUID(json.loads(body)["challengeID"]))
                    assert sql(f"select creator_id from app.weekly_agreements where id='{challenge}';") in actor_ids
                    ids = ",".join(f"'{a}'::uuid" for a in actor_ids)
                    sql(f"begin; set local role service_role; select public.set_weekly_runtime_v1(true,false,true,array[{ids}]::uuid[]); commit;")
                    try:
                        environment = dict(os.environ, WEEKLY_LOCAL_URL=API, WEEKLY_LOCAL_SERVICE_ROLE_KEY=smoke.service_key)
                        subprocess.run(["deno","run","--allow-env=WEEKLY_LOCAL_URL,WEEKLY_LOCAL_SERVICE_ROLE_KEY","--allow-net=127.0.0.1:56321",str(ROOT / "scripts/weekly-lifecycle-local-worker.ts"),challenge],env=environment,check=True,capture_output=True)
                    finally:
                        smoke.gate(True)
                elif action == "revoke-sessions":
                    actor = str(uuid.UUID(json.loads(body)["actorID"]))
                    assert actor in [a["id"] for a in smoke.actors]
                    sql(f"delete from auth.sessions where user_id='{actor}'; "
                        f"delete from auth.refresh_tokens where user_id='{actor}';")
                elif action == "arm":
                    arm = json.loads(body)
                    assert arm["mode"] in ("lose", "hold", "drop")
                    assert arm["rpc"] in ("create_weekly_friend_v1", "get_weekly_v1", "list_my_weekly_v1", "accept_weekly_v1", "join_weekly_cohort_v1")
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
            rpc_before = self.path.split("/rpc/")[-1] if "/rpc/" in self.path else None
            with smoke.lock:
                if smoke.arm and smoke.arm["rpc"] == rpc_before and smoke.arm["mode"] == "drop":
                    smoke.arm = None
                    params = json.loads(body)
                    smoke.trace.append({"rpc":rpc_before,"status":504,"requestID":params.get("p_request_id"),"payloadHash":hashlib.sha256(body).hexdigest()})
                    return self.reply(504,{"message":"request intentionally never sent upstream"})
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
    parser.add_argument("--derived-data", type=Path, default=ROOT / "DerivedData/Codex-WeeklyAcceptance")
    args = parser.parse_args()
    if CONFIG.exists():
        raise RuntimeError(f"Another smoke manifest exists: {CONFIG}")
    smoke = Smoke(json.loads(args.status_file.read_text()))
    # Bind before seeding to prevent concurrent controllers owning admission.
    server = ThreadingHTTPServer(("127.0.0.1", 56329), Handler)
    server.daemon_threads = True
    server.smoke = smoke
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    running = False
    exit_code = 0
    try:
        smoke.setup()
        print("READY: local native smoke on 127.0.0.1:56329; six fictional participants admitted.", flush=True)
        if args.simulator:
            # Xcode destination lookup is case-sensitive for simulator UDIDs.
            simulator = str(uuid.UUID(args.simulator)).upper()
            threading.Thread(target=server.serve_forever, daemon=True).start()
            running = True
            stamp = uuid.uuid4().hex[:8]
            result = ROOT / f"tmp/weekly-native-{stamp}.xcresult"
            log = ROOT / f"tmp/weekly-native-{stamp}.log"
            command = ["xcodebuild", "-project", str(ROOT / "ios/GameTime/GameTime.xcodeproj"),
                "-scheme", "GameTime", "-configuration", "Debug", "-destination",
                f"platform=iOS Simulator,id={simulator}", "-derivedDataPath", str(args.derived_data),
                "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                "-only-testing:GameTimeTests/WeeklyNativeSmokeTests", "CODE_SIGNING_ALLOWED=NO",
                "SUPABASE_URL=http://127.0.0.1:56329", "SUPABASE_PUBLISHABLE_KEY=" + smoke.key, "test"]
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
