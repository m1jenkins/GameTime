#!/usr/bin/env python3
"""Live synthetic state and preflight oracles on the unchanged RPC interfaces."""
from __future__ import annotations
import argparse,json
from lab import Lab,save
from fixtures import q,history,NOW
from runner import Client,mixed
from oracles import refresh_live_metadata,write_preflight,response_errors,require,structural

def setup(lab):
    history(lab,count=4100,start_index=4000)
    values=[]
    for i in range(100):values.append('(%s::uuid,%s::uuid,%s)'%(q(lab.uid('personal',i)),q(lab.uid('actor',i)),q('personal_'+['steps','exercise','distance','timed'][i%4]+'_goal_v1')))
    for i in range(50):values.append('(%s::uuid,%s::uuid,%s)'%(q(lab.uid('friend',i)),q(lab.uid('actor',i*2)),q('friend_steps_goal_v1')))
    lab.owner_sql("""
      create temp table live_seed(id uuid,actor uuid,policy text) on commit drop;
      insert into live_seed values %s;
      insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,agreement_version,created_at,minimum,capacity)
      select id,actor,policy,app.challenge_window_v1('{"start_date":"2026-09-30","days":2,"timezone":"UTC","amount_cents":100}'::jsonb
       ||case when policy like '%%timed%%' then '{"distance_mm":5000000}'::jsonb else '{}' end,'2026-09-27'),
       '2026-09-30','2026-10-02','active',1,'2026-09-27',case when policy like 'personal%%' then 1 else 2 end,case when policy like 'personal%%' then 1 else 2 end from live_seed;
      insert into app.challenge_members_v1(challenge_id,actor_id,selected,target) select id,actor,true,100 from live_seed;
      insert into app.challenge_members_v1(challenge_id,actor_id,selected,target)
        select s.id,b.id,true,100 from live_seed s join challenge_load_fixture.actors a on a.id=s.actor
        join challenge_load_fixture.actors b on b.ordinal=a.ordinal+1 where s.policy like 'friend%%';
      insert into app.challenge_slots_v1 select c.id,m.actor_id,split_part(c.policy,'_',1),split_part(c.policy,'_',2),c.starts_at,c.ends_at
        from live_seed s join app.challenge_lobbies_v1 c on c.id=s.id join app.challenge_members_v1 m on m.challenge_id=c.id;
      insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at)
        select c.id,1,challenge_load_fixture.terms(c.id,1),c.created_at
        from live_seed s join app.challenge_lobbies_v1 c on c.id=s.id;
      insert into app.challenge_consents_v1 select ag.challenge_id,1,m.actor_id,ag.digest,ag.created_at+interval '1 hour'
        from live_seed s join app.challenge_agreements_v1 ag on ag.challenge_id=s.id join app.challenge_members_v1 m on m.challenge_id=s.id;
      """%','.join(values),'live-active')
    actors='array['+','.join(q(lab.uid('actor',i))+'::uuid' for i in range(100))+']'
    lab.service_sql("select public.challenge_runtime_v1(true,true,true,%s,'%s');"%(actors,NOW),'runtime-on')
    client=Client(lab)
    config={'start_date':'2026-10-03','days':1,'timezone':'UTC','amount_cents':100}
    pending=client.require('challenge_command_v1',{'p_request_id':lab.uid('pending-create',0),'p_payload':{'op':'create','policy':'friend_steps_goal_v1','config':config}})['id']
    link_request=lab.uid('pending-link',0)
    issued=client.require('challenge_issue_link_v1',{'p_request_id':link_request,'p_id':pending})
    # Actual link redemptions create pending entrants; no synthetic bypass of the twenty-person link bound.
    for i in range(350,370):
        client.require('challenge_command_v1',{'p_request_id':lab.uid('pending-redeem',i),'p_payload':{'op':'redeem_link','token':issued['token']}},i)
    community=client.require('challenge_publish_community_fixture_v1',{'p_request_id':lab.uid('community-publish',0),'p_operator':lab.uid('actor',0),'p_config':config,'p_target':100,'p_minimum':2,'p_capacity':100,'p_fixture_only':True},service=True)
    client.require('challenge_discovery_fixture_v1',{'p_enabled':True},service=True)
    finish_setup(lab,pending,community,link_request)

def finish_setup(lab,pending,community,link_request):
    client=Client(lab)
    catalog=client.require('challenge_community_catalog_v1',{},0)
    live={'personal':{str(i):lab.uid('personal',i) for i in range(100)},'friends':{str(i):lab.uid('friend',i) for i in range(50)},
          'history':{str(i):lab.uid('history',4000+i) for i in range(100)},'pending':pending,'link_request':link_request,
          'community':community,'community_digest':catalog[0]['digest']}
    # Independent operator grants are created through the real scoped service RPC.
    for cid,cap in [(live['friends']['0'],'moderate'),(live['history']['0'],'review'),(community,'moderate')]:
        client.require('challenge_grant_operator_v1',{'p_actor':lab.uid('actor',1999),'p_id':cid,'p_capability':cap,'p_expires':'2026-10-05'},service=True)
    # One expired unfrozen draft per creator: valid due work, deliberately exposes repeated cancelled discovery.
    values=','.join('(%s::uuid,%s::uuid)'%(q(lab.uid('due-draft',i)),q(lab.uid('actor',i))) for i in range(100))
    lab.owner_sql("""insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,created_at)
      select id,actor,'friend_steps_goal_v1',app.challenge_window_v1('{"start_date":"2026-09-28","days":1,"timezone":"UTC","amount_cents":100}','2026-09-25'),
      '2026-09-28','2026-09-29','lobby_open','2026-09-25' from (values %s) t(id,actor);
      insert into app.challenge_members_v1(challenge_id,actor_id,selected) select id,creator_id,true from app.challenge_lobbies_v1
      where id in(select id from(values %s)t(id,actor));"""%(values,values),'due-drafts')
    for i in range(100):client.require('challenge_confirm_age_v1',{'p_request_id':lab.uid('age-retry',i),'p_confirmed':True},i)
    live=refresh_live_metadata(lab,live,2000)
    # All operation classes are exercised before any timed run. Endpoint failures are fatal.
    checks=[]
    for i in range(20):
        label,op,payload,actor,service=mixed(lab,live,i,'preflight')
        response=client.require(op,payload,actor,service)
        require(not response_errors(lab,live,label,payload,actor,response),'endpoint_oracle_'+label)
        checks.append(label)
    receipt=write_preflight(lab,live)
    print(json.dumps({'endpoint_classes_checked':len(checks),'independent_checks':receipt['checks'],'history_coverage':receipt['coverage']}),flush=True)

def invariants(lab):
    return structural(lab)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('run_root');parser.add_argument('--verify-only',action='store_true')
    parser.add_argument('--resume-after-discovery',action='store_true',help='Recover an interrupted setup only after journaled publication and discovery succeeded')
    args=parser.parse_args();lab=Lab(args.run_root)
    if args.verify_only:print(json.dumps(invariants(lab)))
    elif args.resume_after_discovery:
        require(lab.sql('select discovery from app.challenge_runtime_v1;','resume-discovery')=='t','resume_discovery')
        def saved_id(kind):
            return lab.sql("select response->>'id' from app.challenge_requests_v1 where actor_id=%s and request_id=%s;"%(q(lab.uid('actor',0)),q(lab.uid(kind,0))),'resume-'+kind)
        finish_setup(lab,saved_id('pending-create'),saved_id('community-publish'),lab.uid('pending-link',0))
    else:setup(lab)
if __name__=='__main__':main()
