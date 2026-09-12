exec(open('/private/tmp/gametime-p5-20260911/measure.py').read().split('queries={')[0])
queries={
'worker_receipt_insert':("", "insert into app.challenge_worker_runs_v1 select md5('p5-write:'||n)::uuid,'{\"version\":\"challenge_claim_batch_v1\",\"limit\":20}','{\"claims\":[]}','2026-10-01' from generate_series(1,1000) n"),
'live_lobby_insert':("", "insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at) select md5('p5-write-lobby:'||n)::uuid,'"+actor+"','friend_steps_goal_v1','{}','2026-10-03','2026-10-04','lobby_open','2026-09-30' from generate_series(1,100) n"),
'history_member_insert':("insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at) select md5('p5-write-history:'||n)::uuid,'"+actor+"','friend_steps_goal_v1','{}','2026-09-03','2026-09-04','cancelled','2026-08-30' from generate_series(1,100) n;", "insert into app.challenge_members_v1(challenge_id,actor_id,selected) select md5('p5-write-history:'||n)::uuid,'"+actor+"',true from generate_series(1,100) n")}
for name,(setup,sql) in queries.items():
 plans=[]
 for i in range(5):
  # SET LOCAL avoids SELECT output in the JSON stream.
  plans.append(json.loads(q("begin;set local app.challenge_write_v1='on';"+setup+"explain(analyze,buffers,wal,format json) "+sql+';rollback;'))[0])
 (out/(name+'.json')).write_text(json.dumps(plans,indent=2))
 print(name,[(p['Execution Time'],p['Plan'].get('WAL Bytes',0)) for p in plans],flush=True)
