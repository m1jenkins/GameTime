#!/usr/bin/env python3
"""Rollback EXPLAIN ANALYZE/BUFFERS of RPCs and named source query fragments."""
from __future__ import annotations
import argparse,json,time
from oracles import load_live
from lab import Lab,save
from fixtures import q

SAFE_KEYS={'Node Type','Parent Relationship','Relation Name','Alias','Index Name','Join Type','Scan Direction',
 'Startup Cost','Total Cost','Plan Rows','Plan Width','Actual Startup Time','Actual Total Time','Actual Rows','Actual Loops',
 'Rows Removed by Filter','Rows Removed by Join Filter','Shared Hit Blocks','Shared Read Blocks','Shared Dirtied Blocks','Shared Written Blocks',
 'Local Hit Blocks','Local Read Blocks','Local Dirtied Blocks','Local Written Blocks','Temp Read Blocks','Temp Written Blocks',
 'I/O Read Time','I/O Write Time','Sort Method','Sort Space Used','Sort Space Type','Peak Memory Usage',
 'Heap Fetches','Planning Time','Execution Time','WAL Records','WAL FPI','WAL Bytes','Plans','Plan','Planning','Triggers',
 'Trigger Name','Constraint Name','Time','Calls','JIT','Functions','Options','Inlining','Optimization','Expressions','Deforming','Timing','Generation','Emission','Total'}

def sanitize(value):
    if isinstance(value,list):return [sanitize(v) for v in value]
    if isinstance(value,dict):return {k:sanitize(v) for k,v in value.items() if k in SAFE_KEYS}
    return value

def collect(lab,name):
    out=lab.data/name;out.mkdir(mode=0o700)
    live=load_live(lab)
    actor=lab.uid('actor',0);friend=live['friends']['0'];hist=live['history']['0'];community=live['community']
    rpc={
      'home_action':(0,"select public.challenge_section_v1('action',null,10)"),
      'home_active':(0,"select public.challenge_section_v1('active',null,10)"),
      'home_upcoming':(0,"select public.challenge_section_v1('upcoming',null,10)"),
      'home_history_hot':(0,"select public.challenge_section_v1('history',null,10)"),
      'detail_friend':(0,"select public.challenge_detail_v1(%s)"%q(friend)),
      'detail_history':(0,"select public.challenge_detail_v1(%s)"%q(hist)),
      'catalog':(0,'select public.challenge_community_catalog_v1()'),
      'join':(400,"select public.challenge_join_community_v1(%s,%s::jsonb)"%(q(lab.uid('plan-join',0)),q(json.dumps({'op':'join_community','id':community,'digest':live['community_digest'],'consent':True})))),
      'revision_write':('service',"select public.challenge_capture_fixture_v1(%s,%s,%s,99,'complete')"%(q(lab.uid('plan-capture',0)),q(live['personal']['95']),q(lab.uid('actor',95)))),
      'link_issue':(0,"select public.challenge_issue_link_v1(%s,%s)"%(q(lab.uid('plan-link',0)),q(live['pending']))),
      'report_write':(0,"select public.challenge_report_v1(%s,%s,'unwanted_contact')"%(q(lab.uid('plan-report',0)),q(lab.uid('actor',1)))),
      'operator_reports':(1999,"select public.challenge_operator_reports_v1(%s)"%q(friend)),
      'operator_cases':(1999,"select public.challenge_operator_cases_v1(%s)"%q(hist)),
      'worker_status':('service','select public.challenge_operations_status_v1()'),
      'worker_batch':('service',"select public.challenge_run_batch_v1(%s,20)"%q(lab.uid('plan-worker',0)))
    }
    # Inner fragments preserve the predicates/order of the effective source and expose nodes hidden inside PL/pgSQL.
    fragments={
      'session_lookup':("select id,not_after from auth.sessions where id::text=%s and user_id=%s and (not_after is null or not_after>clock_timestamp()) for share"%(q(lab.uid('session',0)),q(actor)), '20260909123228_challenge_session_lock_expiry_v1.sql:15'),
      'member_latest_fact':("select p.actor_id,f.revision,f.state from app.challenge_members_v1 p left join lateral(select * from app.challenge_facts_v1 where challenge_id=p.challenge_id and actor_id=p.actor_id order by revision desc limit 1) f on true where p.challenge_id=%s"%q(hist),'20260908050701_challenge_community_entry_v1.sql:69'),
      'report_scope':("select r.id,r.subject,r.reason,r.created_at from app.challenge_reports_v1 r where exists(select 1 from app.challenge_members_v1 where challenge_id=%s and actor_id=r.reporter) and exists(select 1 from app.challenge_members_v1 where challenge_id=%s and actor_id=r.subject) order by r.created_at"%(q(friend),q(friend)), '20260908062409_challenge_operations_v1.sql:64'),
      'worker_discovery':('select * from app.challenge_work_v1() where due_at<=app.challenge_now_v1() order by due_at,id limit 20','20260908062409_challenge_operations_v1.sql:44'),
      'journal_exact':("select * from app.challenge_requests_v1 where actor_id=%s and request_id=%s"%(q(actor),q(lab.uid('age-retry',0))),'20260908050901_challenge_access_links_safety_v1.sql:41'),
      'link_lookup':("select * from app.challenge_links_v1 where challenge_id=%s and revoked_at is null"%q(live['pending']),'20260908050901_challenge_access_links_safety_v1.sql:60')
    }
    index={'started_unix':time.time(),'project':lab.m['project'],'parent':lab.m['parent'],'plans':[],'failures':[]}
    for label,(identity,query) in rpc.items():
        if identity=='service':auth='set local role service_role;'
        else:
            claims=json.dumps({'sub':lab.uid('actor',identity),'session_id':lab.uid('session',identity)})
            auth='set local request.jwt.claims=%s; set local role authenticated;'%q(claims)
        explain(lab,out,label,query,auth,index,'public RPC wrapper; rollback')
    for label,(query,source) in fragments.items():explain(lab,out,label,query,'',index,'supabase/migrations/'+source)
    index['finished_unix']=time.time();save(out/'index.json',index)
    print(json.dumps({'plans':len(index['plans']),'failures':index['failures']}))
    if index['failures']:raise SystemExit(1)

def explain(lab,out,label,query,auth,index,source):
    try:
        result=lab.sql("begin; set local statement_timeout='20s'; set local lock_timeout='5s'; "+auth+
            ' explain (analyze,buffers,wal,settings,format json) '+query+'; rollback;','plan-'+label,timeout=45)
        parsed=json.loads(result)
        save(out/(label+'.json'),sanitize(parsed))
        index['plans'].append({'name':label,'source':source,'file':label+'.json','execution_ms':parsed[0].get('Execution Time')})
    except Exception as e:
        index['failures'].append({'name':label,'error':type(e).__name__})

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('run_root');parser.add_argument('--name',required=True)
    args=parser.parse_args()
    if not args.name.replace('-','').isalnum():raise ValueError('simple plan name required')
    collect(Lab(args.run_root),args.name)
if __name__=='__main__':main()
