exec(open('/private/tmp/gametime-p5-20260911/measure.py').read().split('queries={')[0])
# Rollback-only constrained 250-person fixture; no published product setting.
setup="""insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at,capacity)
values(md5('p5-community-write')::uuid,'"""+actor+"""','community_steps_goal_v1','{}','2026-10-03','2026-10-04','scheduled','2026-09-30',250);
insert into app.challenge_members_v1(challenge_id,actor_id,selected) select md5('p5-community-write')::uuid,id,true from challenge_load_fixture.actors where ordinal<250;"""
samples=[]
for i in range(4):
 raw=q("begin;set local app.challenge_write_v1='on';"+setup+"\nselect pg_current_wal_insert_lsn() as bench_start \\gset\nexplain(analyze,buffers,wal,format json) update app.challenge_members_v1 set exited_at='2026-10-01' where challenge_id=md5('p5-community-write')::uuid; select jsonb_build_object('transaction_wal_bytes',pg_wal_lsn_diff(pg_current_wal_insert_lsn(),:'bench_start'::pg_lsn),'history_rows',(select count(*) from app.challenge_history_v1 where challenge_id=md5('p5-community-write')::uuid));rollback;")
 plan,end=json.JSONDecoder().raw_decode(raw);total=json.loads(raw[end:].strip());samples.append({'plan':plan[0],**total})
(out/'250-member-exit.json').write_text(json.dumps(samples,indent=2))
print([(s['plan']['Execution Time'],s['transaction_wal_bytes'],s['history_rows']) for s in samples])
