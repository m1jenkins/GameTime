#!/usr/bin/env python3
"""Batched, constrained synthetic snapshots, plus live RPC fixtures. Never disables triggers."""
from __future__ import annotations
import argparse, json, time, pathlib
from lab import Lab, save

POLICIES = [m+'_'+metric+'_'+competition+'_v1'
            for m in ['friend','personal'] for metric in ['steps','exercise','distance','timed']
            for competition in (['goal','leaderboard'] if m=='friend' else ['goal'])]+['community_steps_goal_v1']
NOW = '2026-10-01T00:00:00Z'

def q(value):
    return "'"+str(value).replace("'","''")+"'"

def accounts(lab, count):
    if count not in (2000,25000):
        raise ValueError('only explicit 2k/25k tiers')
    existing=int(lab.sql('select count(*) from challenge_load_fixture.actors;','actor-count'))
    if existing not in (0,2000) or count<=existing:
        raise ValueError('fixture expansion must be 0->2000 or 2000->25000')
    for start in range(existing,count,1000):
        values=','.join('(%d,%s::uuid,%s::uuid)'%(i,q(lab.uid('actor',i)),q(lab.uid('session',i))) for i in range(start,min(count,start+1000)))
        lab.owner_sql("""
        insert into challenge_load_fixture.actors values %s;
        insert into auth.users(id) select id from challenge_load_fixture.actors where ordinal>=%d and ordinal<%d;
        insert into public.profiles(id,handle,display_name,timezone)
          select id,'cl_%s_'||ordinal,'Synthetic load actor','UTC' from challenge_load_fixture.actors where ordinal>=%d and ordinal<%d;
        insert into auth.sessions(id,user_id) select session_id,id from challenge_load_fixture.actors where ordinal>=%d and ordinal<%d;
        insert into app.challenge_age_v1 select id,'age_21_v1','%s' from challenge_load_fixture.actors where ordinal>=%d and ordinal<%d;
        insert into app.challenge_access_v1 select id,'%s' from challenge_load_fixture.actors where ordinal>=%d and ordinal<%d;
        insert into app.challenge_readiness_v1(actor_id,recorded_at,source,metric)
          select id,'%s','fictional_'||metric||'_v1',metric from challenge_load_fixture.actors
          cross join unnest(array['steps','exercise','distance','timed']) metric where ordinal>=%d and ordinal<%d;
        """%(values,start,start+1000,lab.namespace.hex[:8],start,start+1000,start,start+1000,
               NOW,start,start+1000,NOW,start,start+1000,NOW,start,start+1000),'accounts-'+str(start))

def history(lab, count=4000, start_index=0):
    # Registry is positively owned by this newly created database and never exposed to REST.
    values=[]
    for i in range(start_index,count):
        policy=POLICIES[i%13]
        roster=1 if policy.startswith('personal') else (6 if i%101==0 else 2)
        if policy.startswith('friend') and i%97==0:roster=5
        if i in (12,25,38): roster=[5,50,100][(i-12)//13]
        creator=i-4000 if i>=4000 else 0 if i%16==0 else 350+(i%1650)
        values.append('(%d,%s::uuid,%s,%d,%d)'%(i,q(lab.uid('history',i)),q(policy),roster,creator))
    lab.owner_sql('insert into challenge_load_fixture.history values '+','.join(values)+';','history-registry')
    for start in range(start_index,count,200):
        sql="""
        create temp table batch on commit drop as select h.*,
          ('2026-01-01'::timestamptz+(ordinal%%100)*interval '1 day') s
          from challenge_load_fixture.history h where ordinal>=%(start)d and ordinal<%(end)d;
        insert into app.challenge_lobbies_v1(id,creator_id,policy,config,starts_at,ends_at,status,revision,agreement_version,created_at,minimum,capacity)
        select b.id,a.id,policy,
          app.challenge_window_v1(jsonb_build_object('start_date',s::date,'days',1,'timezone','UTC','amount_cents',100)
           ||case when policy like '%%timed%%' then '{"distance_mm":5000000}'::jsonb else '{}' end,s-interval '3 days'),
          s,s+interval '1 day','final',1+roster*120,case when b.ordinal%%101=0 and policy like 'friend%%' then 2 else 1 end,s-interval '3 days',case when roster=1 then 1 else 2 end,roster
        from batch b join challenge_load_fixture.actors a on a.ordinal=b.creator;
        insert into app.challenge_members_v1(challenge_id,actor_id,selected,target,exited_at)
        select b.id,a.id,true,case when policy like '%%leaderboard%%' then null else 100 end,
          case when b.ordinal%%37=0 and person=roster-1 then s+interval '2 hours' end
        from batch b cross join lateral generate_series(0,b.roster-1) person
        join challenge_load_fixture.actors a on a.ordinal=case when person=0 then b.creator else 350+((b.creator-350+person+1650)%%1650) end;
        insert into app.challenge_agreements_v1(challenge_id,version,terms,created_at)
        select c.id,v,challenge_load_fixture.terms(c.id,v),c.created_at+interval '1 hour'*(v-1)
        from app.challenge_lobbies_v1 c join batch b on b.id=c.id cross join lateral generate_series(1,c.agreement_version) v;
        insert into app.challenge_consents_v1 select a.challenge_id,a.version,m.actor_id,a.digest,a.created_at+interval '30 minutes'
          from app.challenge_agreements_v1 a join batch b on b.id=a.challenge_id join app.challenge_members_v1 m using(challenge_id);
        insert into app.challenge_facts_v1
        select m.challenge_id,m.actor_id,r,
          case when r<120 then case when r%%5 not in (0,1) then case when r%%2=0 then 100 else 90 end end
           when b.ordinal%%4=0 or (b.ordinal%%4=3 and row_number() over(partition by b.id,r order by m.actor_id)=b.roster) then null
           when b.ordinal%%4=2 and row_number() over(partition by b.id,r order by m.actor_id)>3 then case when b.policy like '%%timed%%' then 101 else 90 end
           else case when b.policy like '%%timed%%' then 99 else 100 end end,
          case when r<120 then case when r%%5=0 then 'deleted' when r%%5=1 then 'unresolved' else 'complete' end
           when b.ordinal%%4=0 then 'deleted' when b.ordinal%%4=3 and row_number() over(partition by b.id,r order by m.actor_id)=b.roster then 'unresolved' else 'complete' end,
          b.s+interval '1 minute'*r,
          md5(%(ns)s||':fact:'||m.challenge_id||':'||m.actor_id||':'||r)::uuid
        from batch b join app.challenge_members_v1 m on m.challenge_id=b.id cross join generate_series(1,120) r;
        -- Separate request-journal volume uses valid age-confirmation receipts, not fictional capture receipts.
        insert into app.challenge_requests_v1 select f.actor_id,
          md5(%(ns)s||':journal:'||f.request_id)::uuid,'{"op":"confirm_age","confirmed":true}',
          '{"confirmed":true,"policy":"age_21_v1"}',f.recorded_at
          from app.challenge_facts_v1 f join batch b on b.id=f.challenge_id;
        insert into app.challenge_notices_v1
        select c.id,1,app.challenge_evaluate_policy_v1(c.policy,
          (select jsonb_agg(jsonb_build_object('actor_id',m.actor_id,'target',m.target,'excluded',m.exited_at is not null,'state',f.state,'value',f.value) order by m.actor_id)
          from app.challenge_members_v1 m join app.challenge_facts_v1 f on f.challenge_id=m.challenge_id and f.actor_id=m.actor_id and f.revision=120 where m.challenge_id=c.id),100,c.minimum,false),
          c.ends_at+interval '49 hours',c.ends_at+interval '97 hours'
          from app.challenge_lobbies_v1 c join batch b on b.id=c.id;
        insert into app.challenge_reviews_v1
          select md5(%(ns)s||':review:'||m.challenge_id||':'||m.actor_id)::uuid,m.challenge_id,1,m.actor_id,
          'missing_activity',b.s+interval '74 hours',b.s+interval '146 hours'
          from batch b join app.challenge_members_v1 m on m.challenge_id=b.id;
        insert into app.challenge_resolutions_v1 select r.id,'upheld',%(operator)s::uuid,r.filed_at+interval '2 hours'
          from app.challenge_reviews_v1 r join batch b on b.id=r.challenge_id;
        insert into app.challenge_finals_v1 select n.challenge_id,n.result,b.s+interval '8 days',c.revision
          from app.challenge_notices_v1 n join batch b on b.id=n.challenge_id join app.challenge_lobbies_v1 c on c.id=b.id;
        update app.challenge_lobbies_v1 c set status=case when f.result->>'outcome'='void' then 'void' else 'final' end
          from batch b join app.challenge_finals_v1 f on f.challenge_id=b.id where b.id=c.id;
        insert into app.challenge_exits_v1 select md5(%(ns)s||':exit:'||m.challenge_id||':'||m.actor_id)::uuid,
          m.challenge_id,m.actor_id,'left',m.exited_at from app.challenge_members_v1 m join batch b on b.id=m.challenge_id where m.exited_at is not null;
        insert into app.challenge_links_v1
          select md5(%(ns)s||':link:'||c.id)::uuid,c.id,c.creator_id,encode(extensions.digest(%(ns)s||':token:'||c.id,'sha256'),'hex'),
          c.created_at,c.created_at+interval '30 days',c.ends_at from app.challenge_lobbies_v1 c join batch b on b.id=c.id where c.policy like 'friend%%';
        insert into app.challenge_redemptions_v1 select l.id,m.actor_id,l.issued_at+interval '30 minutes'
          from app.challenge_links_v1 l join batch b on b.id=l.challenge_id join app.challenge_members_v1 m on m.challenge_id=l.challenge_id where m.actor_id<>l.issuer;
        insert into app.challenge_reports_v1 select md5(%(ns)s||':report:'||m.challenge_id||':'||m.actor_id)::uuid,
          c.creator_id,m.actor_id,'unwanted_contact',c.ends_at+interval '1 hour'
          from app.challenge_members_v1 m join batch b on b.id=m.challenge_id join app.challenge_lobbies_v1 c on c.id=b.id where m.actor_id<>c.creator_id;
        """%{'start':start,'end':start+200,'ns':q(str(lab.namespace)),'operator':q(lab.uid('actor',349))}
        lab.owner_sql(sql,'history-'+str(start),timeout=180)
        print(json.dumps({'history_seeded':min(count,start+200)}),flush=True)

def setup(lab):
    if lab.sql("select to_regnamespace('challenge_load_fixture') is null;",'fixture-absent')!='t':
        raise ValueError('fixture schema already exists; seed is create-exclusive')
    lab.owner_sql("""create schema challenge_load_fixture;
      revoke all on schema challenge_load_fixture from public,anon,authenticated,service_role;
      create table challenge_load_fixture.identity(namespace uuid primary key,project text not null);
      insert into challenge_load_fixture.identity values (%s,%s);
      create table challenge_load_fixture.actors(ordinal integer primary key,id uuid unique not null,session_id uuid unique not null);
      create table challenge_load_fixture.history(ordinal integer primary key,id uuid unique not null,policy text not null,roster integer not null,creator integer not null);
      """%(q(str(lab.namespace)),q(lab.m['project'])),'fixture-schema')
    lab.owner_sql(pathlib.Path(__file__).with_name('fixture-terms.sql').read_text(),'fixture-terms')
    accounts(lab,2000)
    history(lab)
    # Directed blocks are disjoint from timed active actors, retained historical data.
    lab.owner_sql("insert into public.blocks(blocker_id,blocked_id) select a.id,b.id from challenge_load_fixture.actors a join challenge_load_fixture.actors b on b.ordinal=a.ordinal+1 where a.ordinal between 1800 and 1898 and a.ordinal%2=0;",'blocks')
    counts=lab.sql("select jsonb_object_agg(tablename,n) from (select tablename,(xpath('/row/c/text()',query_to_xml(format('select count(*) c from app.%I',tablename),false,true,'')))[1]::text::bigint n from pg_tables where schemaname='app' and tablename like 'challenge_%_v1') t;",'counts')
    save(lab.data/'fixture-counts-2000.json',json.loads(counts))
    print(json.dumps({'synthetic_accounts':2000,'challenge_rows':sum(json.loads(counts).values())}),flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['seed','expand-25000'])
    parser.add_argument('run_root')
    args=parser.parse_args();lab=Lab(args.run_root)
    if args.action=='seed':setup(lab)
    else:accounts(lab,25000)

if __name__=='__main__':main()
