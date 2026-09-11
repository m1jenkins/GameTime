#!/usr/bin/env python3
"""Final owned-fixture counts and worker outcomes; run outside timed load windows."""
from __future__ import annotations
import argparse,json,time
from lab import Lab,save,digest
from oracles import load_live,check_preflight,postflight

QUERIES={
 'exact_challenge_rows':"select jsonb_object_agg(tablename,n) from (select tablename,(xpath('/row/c/text()',query_to_xml(format('select count(*) c from app.%I',tablename),false,true,'')))[1]::text::bigint n from pg_tables where schemaname='app' and tablename like 'challenge_%_v1') t;",
 'storage':"select jsonb_build_object('database_bytes',pg_database_size(current_database()),'tables',(select jsonb_agg(jsonb_build_object('table',relname,'total_bytes',pg_total_relation_size(relid),'index_bytes',pg_indexes_size(relid),'heap_bytes',pg_relation_size(relid)) order by relname) from pg_stat_user_tables where schemaname='app' and relname like 'challenge_%_v1'));",
 'accounts':"select jsonb_build_object('fixture_accounts',(select count(*) from challenge_load_fixture.actors),'auth_users',(select count(*) from auth.users),'auth_sessions',(select count(*) from auth.sessions),'accounts_with_membership',(select count(distinct actor_id) from app.challenge_members_v1),'historical_challenges',(select count(*) from challenge_load_fixture.history));",
 'policy_and_roster_shapes':"select jsonb_agg(to_jsonb(s) order by policy,roster_size) from (select policy,roster_size,count(*) challenges from (select c.policy,(select count(*) from app.challenge_members_v1 m where m.challenge_id=c.id) roster_size from app.challenge_lobbies_v1 c join challenge_load_fixture.history h on h.id=c.id) shapes group by policy,roster_size) s;",
 'facts':"select jsonb_build_object('states',(select jsonb_object_agg(state,n) from(select state,count(*) n from app.challenge_facts_v1 group by state)s),'min_revision',(select min(revision) from app.challenge_facts_v1),'max_revision',(select max(revision) from app.challenge_facts_v1),'revision_streams',(select count(*) from(select challenge_id,actor_id from app.challenge_facts_v1 group by challenge_id,actor_id)s));",
 'worker_receipts':"""select jsonb_build_object(
  'runs',(select count(*) from app.challenge_worker_runs_v1),
  'failed_items',(select coalesce(sum((result->>'failed_count')::integer),0) from app.challenge_worker_runs_v1),
  'processed_entries',(select count(*) from app.challenge_worker_runs_v1 w cross join lateral jsonb_array_elements(w.result->'processed') x),
  'distinct_processed_challenges',(select count(distinct x->>'id') from app.challenge_worker_runs_v1 w cross join lateral jsonb_array_elements(w.result->'processed') x),
  'outcomes',(select jsonb_object_agg(status,n) from(select coalesce(x->>'status',x->>'error_code') status,count(*) n from app.challenge_worker_runs_v1 w cross join lateral jsonb_array_elements(w.result->'processed') x group by 1)s),
  'cancelled_without_finals',(select count(*) from app.challenge_lobbies_v1 c where c.status='cancelled' and not exists(select 1 from app.challenge_finals_v1 f where f.challenge_id=c.id)),
  'eligible_due_by_status',(select jsonb_object_agg(status,n) from(select status,count(*) n from app.challenge_work_v1() where due_at<=app.challenge_now_v1() group by status)s));""",
 'gates':"select to_jsonb(r)-'actors'-'fictional_now'||jsonb_build_object('actor_allowlist_size',cardinality(actors),'fictional_clock_set',fictional_now is not null) from app.challenge_runtime_v1 r where singleton;"
}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('run_root');parser.add_argument('--name',required=True)
    args=parser.parse_args()
    if not args.name.replace('-','').isalnum():raise ValueError('simple audit name required')
    lab=Lab(args.run_root);lab.fixture_owner();live=load_live(lab);receipt=check_preflight(lab,live)
    destination=lab.data/args.name;destination.mkdir(mode=0o700)
    result={'parent':lab.m['parent'],'project':lab.m['project'],'fixture_accounts':live['accounts'],
      'started_unix':time.time(),'audit_source_sha256':digest(__file__),'results':{},'failures':[]}
    for label,query in QUERIES.items():
        try:result['results'][label]=json.loads(lab.sql(query,'audit-'+label,timeout=180))
        except Exception as error:result['failures'].append({'check':label,'error':type(error).__name__})
    try:postflight(lab,receipt,destination/'postflight.json')
    except Exception as error:result['failures'].append({'check':'postflight','error':type(error).__name__})
    result['finished_unix']=time.time();result['passed']=not result['failures']
    save(destination/'audit.json',result)
    print(json.dumps({'passed':result['passed'],'failures':result['failures'],'fixture_accounts':live['accounts'],
      'exact_challenge_rows':sum(result['results'].get('exact_challenge_rows',{}).values())}))
    if not result['passed']:raise SystemExit(1)

if __name__=='__main__':main()
