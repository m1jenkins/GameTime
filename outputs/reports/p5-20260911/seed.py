import sys,uuid,pathlib,subprocess,os
sys.path.insert(0,str(pathlib.Path.cwd()/'scripts/challenge-load'))
import fixtures
ROOT=pathlib.Path('/private/tmp/gametime-p5-20260911')
class Lab:
 namespace=uuid.UUID('0a3f1438-9c69-4472-8b7c-4b2c7c304761')
 m={'project':'gametime-p5-20260911'}
 data=ROOT
 def uid(self,kind,index):return str(uuid.uuid5(self.namespace,f'{kind}:{index}'))
 def sql(self,sql,name,timeout=180):
  p=subprocess.run(['psql','postgresql://postgres:postgres@127.0.0.1:59622/postgres','-XqAt','-v','ON_ERROR_STOP=1'],input=sql,text=True,capture_output=True,timeout=timeout,env={k:v for k,v in os.environ.items() if not k.startswith('PG')})
  (ROOT/(name+'.log')).write_text(p.stdout+p.stderr)
  if p.returncode:raise RuntimeError(p.stderr[-2000:])
  return p.stdout.strip()
 def owner_sql(self,sql,name,timeout=180):return self.sql("begin;select set_config('app.challenge_write_v1','on',true);"+sql+';commit;',name,timeout)
lab=Lab()
lab.owner_sql('''create schema challenge_load_fixture;
revoke all on schema challenge_load_fixture from public,anon,authenticated,service_role;
create table challenge_load_fixture.actors(ordinal integer primary key,id uuid unique not null,session_id uuid unique not null);
create table challenge_load_fixture.history(ordinal integer primary key,id uuid unique not null,policy text not null,roster integer not null,creator integer not null);''','schema')
lab.owner_sql(pathlib.Path('scripts/challenge-load/fixture-terms.sql').read_text(),'terms')
fixtures.accounts(lab,2000)
fixtures.history(lab,count=400)
lab.owner_sql('''
insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at)
select md5('p5-dense:'||n)::uuid,a.id,'friend_steps_goal_v1',app.challenge_window_v1('{"start_date":"2026-09-01","days":1,"timezone":"UTC","amount_cents":100}','2026-08-28'),
'2026-09-01','2026-09-02','cancelled','2026-08-28' from generate_series(1,10000) n cross join challenge_load_fixture.actors a where a.ordinal=0;
insert into app.challenge_members_v1(challenge_id,actor_id,selected)
select c.id,c.creator_id,true from app.challenge_lobbies_v1 c where status='cancelled';
insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at)
select md5('p5-live:'||n)::uuid,a.id,'friend_steps_goal_v1',app.challenge_window_v1('{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}','2026-09-30'),
case when n<=20 then '2026-09-28'::timestamptz else '2026-10-03' end,'2026-10-04','lobby_open','2026-09-30'
from generate_series(1,1000) n join challenge_load_fixture.actors a on a.ordinal=n%100;
insert into app.challenge_members_v1(challenge_id,actor_id,selected)
select c.id,a.id,true from app.challenge_lobbies_v1 c join challenge_load_fixture.actors owner on owner.id=c.creator_id
join challenge_load_fixture.actors a on a.ordinal between owner.ordinal and owner.ordinal+5 where c.status='lobby_open';
select public.challenge_runtime_v1(true,true,true,array(select id from challenge_load_fixture.actors where ordinal<100),'2026-10-01');
insert into app.challenge_worker_runs_v1
select md5('p5-old-run:'||n)::uuid,'{"version":"challenge_batch_v1","limit":20}',jsonb_build_object('failed_count',case when n%1000=0 then 1 else 0 end),'2026-01-01'
from generate_series(1,100000) n;
insert into app.challenge_worker_runs_v1 values(md5('p5-recent-failure')::uuid,'{"version":"challenge_batch_v1","limit":20}','{"failed_count":3}','2026-10-01');
''','dense',timeout=300)
lab.sql('analyze;','analyze')
print('Seeded 2,000 actors, 400 P2 histories, 10,000 dense cancelled histories, 1,000 live six-person drafts and 100,001 worker receipts.')
