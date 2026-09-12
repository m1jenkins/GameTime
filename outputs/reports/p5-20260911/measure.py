import json,os,pathlib,subprocess,sys,time,uuid,math
ROOT=pathlib.Path('/private/tmp/gametime-p5-20260911');NS=uuid.UUID('0a3f1438-9c69-4472-8b7c-4b2c7c304761');lane=sys.argv[1]
out=ROOT/lane;out.mkdir(exist_ok=True)
def q(sql):
 p=subprocess.run(['psql','postgresql://postgres:postgres@127.0.0.1:59622/postgres','-XqAt','-v','ON_ERROR_STOP=1'],input=sql,text=True,capture_output=True,timeout=90,env={k:v for k,v in os.environ.items() if not k.startswith('PG')})
 if p.returncode:raise RuntimeError(p.stderr)
 return p.stdout.strip()
actor=str(uuid.uuid5(NS,'actor:0'));session=str(uuid.uuid5(NS,'session:0'))
login="set local role authenticated; set local request.jwt.claims = '"+json.dumps({'sub':actor,'session_id':session})+"'; set local request.jwt.claim.sub='"+actor+"';"
queries={
'home_history':(login,"select public.challenge_section_v1('history',null,50)"),
'home_active':(login,"select public.challenge_section_v1('active',null,10)"),
'home_upcoming':(login,"select public.challenge_section_v1('upcoming',null,10)"),
'home_action':(login,"select public.challenge_section_v1('action',null,10)"),
'detail':(login,"select public.challenge_detail_v1('"+str(uuid.uuid5(NS,'history:0'))+"')"),
'work_inventory':('',"select * from app.challenge_work_v1()"),
'worker_status':('set local role service_role;',"select public.challenge_operations_status_v1()"),
'claim_batch':('set local role service_role;',"select public.challenge_claim_batch_v1('b5500000-0000-0000-0000-000000000001',20)"),
'history_ids':('',"select array_agg(c.id order by coalesce(f.recorded_at,c.ends_at) desc,c.starts_at,c.id) from app.challenge_lobbies_v1 c join app.challenge_members_v1 m on m.challenge_id=c.id left join app.challenge_finals_v1 f on f.challenge_id=c.id where m.actor_id='"+actor+"' and (m.exited_at is not null or c.status in ('final','void','cancelled'))"),
'recent_failures':('',"select coalesce(sum(coalesce((result->>'failed_count')::integer,0)+case when result ? 'error_code' then 1 else 0 end),0) from app.challenge_worker_runs_v1 where recorded_at>='2026-09-30'")}
results={}
for name,(setup,sql) in queries.items():
 plans=[]
 for i in range(7):
  result=([json.loads((out/(name+'.json')).read_text())[i]] if (out/(name+'.json')).exists() else json.loads(q('begin;'+setup+'explain(analyze,buffers,wal,format json) '+sql+';rollback;')))
  plans.append(result[0])
 (out/(name+'.json')).write_text(json.dumps(plans,indent=2))
 times=sorted(p['Execution Time'] for p in plans[1:]);results[name]={'warm_median_ms':(times[2]+times[3])/2,'warm_p95_ms':times[-1],'first_ms':plans[0]['Execution Time'],'shared_hits':plans[-1]['Plan']['Shared Hit Blocks'],'shared_reads':plans[-1]['Plan']['Shared Read Blocks']}
 print(name,results[name],flush=True)
(out/'summary.json').write_text(json.dumps(results,indent=2))
projection_ids=q("select array_agg(id) from (select id from app.challenge_lobbies_v1 where creator_id='"+actor+"' order by id limit 50) x")
# Same current projections and eligible work; exclude only per-call clocks/UUIDs.
for name,sql in {
'work':"select jsonb_agg(to_jsonb(w) order by id) from app.challenge_work_v1() w",
'history_order':"select jsonb_agg(id order by rank) from (select c.id,row_number() over(order by coalesce(f.recorded_at,c.ends_at) desc,c.starts_at,c.id) rank from app.challenge_lobbies_v1 c join app.challenge_members_v1 m on m.challenge_id=c.id left join app.challenge_finals_v1 f on f.challenge_id=c.id where m.actor_id='"+actor+"' and (m.exited_at is not null or c.status in ('final','void','cancelled'))) t",
'projections':"select jsonb_agg(public.challenge_detail_v1(id) order by id) from unnest('"+projection_ids+"'::uuid[]) id"
}.items():
 (out/(name+'-result.json')).write_text(q('begin;'+(login if name=='projections' else '')+sql+';rollback;'))
(out/'summary.json').write_text(json.dumps(results,indent=2))
