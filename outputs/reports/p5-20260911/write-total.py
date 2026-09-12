exec(open('/private/tmp/gametime-p5-20260911/write-cost.py').read().split('for name,(setup,sql)')[0])
remove='''drop trigger challenge_history_lobby on app.challenge_lobbies_v1;
drop trigger challenge_history_member on app.challenge_members_v1;
drop trigger challenge_history_final on app.challenge_finals_v1;
drop index app.challenge_history_order_v1,app.challenge_live_creator_v1,app.challenge_worker_runs_recorded_v1;'''
for phase in ['without-p5-maintenance','with-p5-maintenance']:
 result={}
 for name,(setup,sql) in queries.items():
  samples=[]
  for i in range(6):
   raw=q("begin;set local app.challenge_write_v1='on';"+(remove if phase.startswith('without') else '')+setup+"\nselect pg_current_wal_insert_lsn() as bench_start \\gset\nexplain(analyze,buffers,wal,format json) "+sql+";select jsonb_build_object('transaction_wal_bytes',pg_wal_lsn_diff(pg_current_wal_insert_lsn(),:'bench_start'::pg_lsn));rollback;")
   plan,end=json.JSONDecoder().raw_decode(raw);total=json.loads(raw[end:].strip());samples.append({'plan':plan[0],**total})
  result[name]=samples
  print(phase,name,[(x['plan']['Execution Time'],x['transaction_wal_bytes']) for x in samples],flush=True)
 (out/(phase+'.json')).write_text(json.dumps(result,indent=2))
