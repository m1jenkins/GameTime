#!/usr/bin/env python3
"""Bounded real-session P5 races on an explicitly owned loopback database."""
import argparse,json,os,re,select,subprocess,time,uuid
from pathlib import Path
from urllib.parse import urlparse

class Session:
    def __init__(self,url):
        self.p=subprocess.Popen(['psql',url,'-XqAt','-v','ON_ERROR_STOP=1'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env={k:v for k,v in os.environ.items() if not k.startswith('PG')})
    def start(self,sql):
        self.p.stdin.write(sql+';\n\\echo p5_done\n');self.p.stdin.flush()
    def finish(self,timeout=10):
        data=b'';deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            if not select.select([self.p.stdout],[],[],max(0,deadline-time.monotonic()))[0]:break
            chunk=os.read(self.p.stdout.fileno(),65536)
            if not chunk:return data.decode()+self.p.stderr.read()
            data+=chunk
            if data.splitlines() and data.splitlines()[-1]==b'p5_done':
                return data.decode().rsplit('p5_done',1)[0].strip()
        raise TimeoutError('P5 SQL session timed out')
    def query(self,sql):self.start(sql);return self.finish()
    def close(self):
        if self.p.poll() is None:self.p.terminate()
        self.p.communicate(timeout=5)

def main():
    p=argparse.ArgumentParser();p.add_argument('--db-url',required=True);p.add_argument('--owned-root',type=Path,required=True);p.add_argument('--owned-project',required=True);args=p.parse_args()
    config=(args.owned_root/'supabase/config.toml').read_text();u=urlparse(args.db_url)
    assert u.hostname=='127.0.0.1' and f'project_id = "{args.owned_project}"' in config
    assert u.port==int(re.search(r'^port = (\d+)$',config.split('[db]\n')[1].split('\n[')[0],re.M).group(1))
    a=str(uuid.uuid4());sid=str(uuid.uuid4());cid=str(uuid.uuid4());key=55195501;sessions=[];checks=[]
    def conn():
        s=Session(args.db_url);sessions.append(s);return s
    db=conn();holder=conn()
    login="set local role authenticated;set local request.jwt.claim.sub='"+a+"';set local request.jwt.claims='"+json.dumps({'sub':a,'session_id':sid})+"';"
    try:
        db.query(f"""begin;insert into auth.users(id) values('{a}');insert into public.profiles(id,handle,display_name,timezone) values('{a}','p5race_{a[:8]}','Fictional race','UTC');insert into auth.sessions(id,user_id) values('{sid}','{a}');
set local app.challenge_write_v1='on';select public.challenge_runtime_v1(true,true,true,array['{a}'::uuid],'2026-10-01');insert into app.challenge_age_v1 values('{a}','age_21_v1','2026-10-01');insert into app.challenge_access_v1 values('{a}','2026-10-01');
insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at) values('{cid}','{a}','friend_steps_goal_v1','{{}}','2026-10-03','2026-10-04','lobby_open','2026-09-30');
insert into app.challenge_members_v1(challenge_id,actor_id,selected) values('{cid}','{a}',true);
create function app.p5_test_page_pause() returns trigger language plpgsql as $$begin perform pg_advisory_xact_lock({key});return new;end $$;
create trigger p5_test_page_pause before insert on app.challenge_pages_v1 for each row when(new.actor_id='{a}'::uuid) execute function app.p5_test_page_pause();commit""")
        for section in ['history','upcoming']:
            db.query(f"update auth.sessions set not_after=clock_timestamp()+interval '1 second' where id='{sid}'")
            holder.query(f'begin;select pg_advisory_xact_lock({key})')
            reader=conn();reader.start('begin;'+login+f"select public.challenge_section_v1('{section}',null,50);commit")
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                if db.query(f"select exists(select 1 from pg_locks where locktype='advisory' and objid={key} and not granted)").strip()=='t':break
                time.sleep(.02)
            else:raise AssertionError('reader never reached page pause')
            time.sleep(1.05);holder.query('commit');result=reader.finish()
            assert 'challenge_session_required' in result,result
            checks.append(section+': wall expiry during page generation rejected')
        db.query(f"update auth.sessions set not_after=null where id='{sid}'")
        holder.query(f'begin;select pg_advisory_xact_lock({key})')
        reader=conn();reader.start('begin;'+login+"select public.challenge_section_v1('history',null,50);commit")
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            if db.query(f"select exists(select 1 from pg_locks where locktype='advisory' and objid={key} and not granted)").strip()=='t':break
            time.sleep(.02)
        else:raise AssertionError('reader never reached page pause')
        mutation=db.query('begin;'+login+"select public.challenge_mutate_v1('"+str(uuid.uuid4())+"','"+json.dumps({'id':cid,'op':'cancel','revision':1})+"');commit")
        assert 'cancelled' in mutation,mutation
        checks.append('safe cancellation commits while history read waits')
        holder.query('commit');result=reader.finish();assert 'challenge_page_expired' in result,result
        checks.append('concurrent history insertion expires in-flight page')
        fresh=db.query('begin;'+login+"select public.challenge_section_v1('history',null,50)->'rows'->0->>'id';commit")
        assert cid in fresh,fresh;checks.append('fresh page includes newly cancelled agreement')
        print(json.dumps({'passed':len(checks),'checks':checks},indent=2))
    finally:
        for s in sessions[1:]:s.close()
        # Only our test trigger/function and fictional gates. Keep fixture rows.
        db.query('drop trigger if exists p5_test_page_pause on app.challenge_pages_v1;drop function if exists app.p5_test_page_pause();select public.challenge_runtime_v1(false,false,false,\'{}\',null)')
        db.close()

if __name__=='__main__':main()
