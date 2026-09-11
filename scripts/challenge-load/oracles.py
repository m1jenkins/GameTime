"""Fail-closed load correctness checks, tied to the exact fixture and product identity."""
from __future__ import annotations
import hashlib,json,pathlib,time
from lab import digest,save
from fixtures import q
from contracts import expected_terms,allocation

CORE=['lab.py','fixtures.py','fixture-terms.sql','contracts.py','live.py','oracles.py','runner.py','arrivals.py']
def core_hashes():return {name:digest(pathlib.Path(__file__).with_name(name)) for name in CORE}
def canonical(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def require(condition,label):
    if not condition:raise AssertionError(label)

def load_live(lab):
    count=int(lab.sql('select count(*) from challenge_load_fixture.actors;','live-count'))
    return json.loads((lab.data/'private'/('live-'+str(count)+'.json')).read_text())

def history_hash(lab):
    result={}
    for table,key in [('lobbies','id'),('members','challenge_id'),('agreements','challenge_id'),('consents','challenge_id'),('facts','challenge_id'),('notices','challenge_id'),('reviews','challenge_id'),('exits','challenge_id'),('finals','challenge_id')]:
        query="select md5(string_agg(row_hash,'' order by row_hash)) from (select md5(to_jsonb(t)::text) row_hash from app.challenge_%s_v1 t join challenge_load_fixture.history h on h.id=t.%s) rows;"%(table,key)
        result[table]=lab.sql(query,'history-hash-'+table,timeout=180)
    result['resolutions']=lab.sql("select md5(string_agg(md5(to_jsonb(s)::text),'' order by s.review_id)) from app.challenge_resolutions_v1 s join app.challenge_reviews_v1 r on r.id=s.review_id join challenge_load_fixture.history h on h.id=r.challenge_id;",'history-hash-resolutions')
    require(all(result.values()),'historical_hash_empty')
    return result

def structural(lab):
    tests={
      'accounts':"select count(*) in (2000,25000) from auth.users;",
      'actor_bindings':"select bool_and(app.is_active_actor(id)) from challenge_load_fixture.actors;",
      'slot_bound':"select not exists(select 1 from app.challenge_slots_v1 group by actor_id having count(*)>3);",
      'agreement_and_consent_present':"select not exists(select 1 from app.challenge_slots_v1 s join app.challenge_lobbies_v1 c on c.id=s.challenge_id left join app.challenge_agreements_v1 ag on ag.challenge_id=c.id and ag.version=c.agreement_version left join app.challenge_consents_v1 co on co.challenge_id=c.id and co.version=c.agreement_version and co.actor_id=s.actor_id where ag.challenge_id is null or co.challenge_id is null or co.digest is distinct from ag.digest);",
      'revision_sequence':"select not exists(select 1 from app.challenge_facts_v1 group by challenge_id,actor_id having min(revision)<>1 or max(revision)<>count(*) or max(revision)>128);",
      'external_gates_off':"select not ingestion and not steps_source and not exercise_source and not distance_source and not timed_source and not analytics and cardinality(actors)<=100 from app.challenge_runtime_v1 where singleton;",
      'final_fields_and_conservation':"select not exists(select 1 from app.challenge_finals_v1 f where not (f.result ?& array['entry_cents','unallocated_cents','participants','outcome','simulation']) or jsonb_typeof(f.result->'entry_cents') is distinct from 'number' or jsonb_typeof(f.result->'unallocated_cents') is distinct from 'number' or jsonb_typeof(f.result->'participants') is distinct from 'object' or (select count(*) from jsonb_each(f.result->'participants'))=0 or exists(select 1 from jsonb_each(f.result->'participants') where jsonb_typeof(value->'returned_cents') is distinct from 'number' or value->>'status' is null) or (f.result->>'entry_cents')::bigint is distinct from (f.result->>'unallocated_cents')::bigint+(select sum((value->>'returned_cents')::bigint) from jsonb_each(f.result->'participants')));",
      'final_slots_released':"select not exists(select 1 from app.challenge_slots_v1 s join app.challenge_finals_v1 f using(challenge_id));"
    }
    for label,query in tests.items():require(lab.sql(query,'oracle-'+label)=='t',label)
    return list(tests)

def validate_history(lab):
    rows=json.loads(lab.sql("""select jsonb_agg(jsonb_build_object('id',c.id,'policy',c.policy,'config',c.config,'minimum',c.minimum,'capacity',c.capacity,
      'agreements',(select jsonb_agg(jsonb_build_object('version',ag.version,'terms',ag.terms)) from app.challenge_agreements_v1 ag where ag.challenge_id=c.id),
      'people',(select jsonb_agg(jsonb_build_object('actor_id',m.actor_id,'target',m.target,'excluded',m.exited_at is not null,'state',f.state,'value',f.value))
       from app.challenge_members_v1 m join app.challenge_facts_v1 f on f.challenge_id=m.challenge_id and f.actor_id=m.actor_id and f.revision=120 where m.challenge_id=c.id),
      'result',final.result)) from challenge_load_fixture.history h join app.challenge_lobbies_v1 c on c.id=h.id join app.challenge_finals_v1 final on final.challenge_id=c.id;""",'independent-history',timeout=180))
    require(len(rows)==4100,'history_shape_count')
    policies=set();outcomes=set();reopened=0;remainders=0;ties=0
    for row in rows:
        people=row['people'];participants=[{'actor_id':p['actor_id'],'target':p['target']} for p in people]
        for agreement in row['agreements']:
            expected=expected_terms(row['policy'],row['config'],participants,row['minimum'],row['capacity'],agreement['version'])
            require(agreement['terms']==expected,'independent_frozen_terms_'+row['policy'])
        expected=allocation(row['policy'],people,row['minimum'])
        require(row['result']==expected,'independent_allocation_'+row['policy'])
        policies.add(row['policy']);outcomes.add(expected['outcome']);reopened+=len(row['agreements'])>1
        remainders+=expected['unallocated_cents']>0
        ties+=sum(p['status']=='winner' for p in expected['participants'].values())>1
    require(len(policies)==13 and outcomes=={'void','scored'} and reopened>0 and remainders>0 and ties>0,'representative_history_outcomes')
    return {'policies':len(policies),'histories':len(rows),'reopened':reopened,'nonzero_remainders':remainders,'tied_leaderboards':ties}

def detail_errors(body,actor_id,allowed):
    if not isinstance(body,dict) or not {'id','policy','status','members','social_hidden','agreement','reviews','final'}.issubset(body):return ['detail_shape']
    errors=[]
    if body['id'] not in allowed:errors.append('unauthorized_challenge_identity')
    if not isinstance(body['members'],list) or not isinstance(body['social_hidden'],bool):return errors+['member_shape']
    if body['social_hidden']:
        if body.get('creator_id') not in (None,actor_id):errors.append('hidden_creator_identity')
        if any(m.get('actor_id')!=actor_id for m in body['members']):errors.append('hidden_counterpart')
        agreement=body.get('agreement')
        if body['policy']!='community_steps_goal_v1' and agreement and agreement.get('terms') is not None:errors.append('hidden_agreement')
        if body['policy']=='community_steps_goal_v1' and agreement and isinstance(agreement.get('terms'),dict) and 'participants' in agreement['terms']:errors.append('community_identity_roster')
        for key in ['notice','final']:
            row=body.get(key)
            if row and row.get('result') is not None and set(row['result'])!={'own'}:errors.append('hidden_result')
    for member in body['members']:
        if member.get('exited') and member.get('actor_id')!=actor_id and (member.get('username')!='' or member.get('target') is not None or member.get('fact') is not None):errors.append('departed_identity_or_fact')
    return errors

def response_errors(lab,live,label,payload,actor,body):
    actor_id=lab.uid('actor',actor);allowed=set(live['authorized_ids'].get(str(actor),[]))
    if label.startswith('section_') or label=='cursor':
        needed={'section','projection_revision','server_time','expires_at','rows','next_cursor'}
        if not isinstance(body,dict) or not needed.issubset(body) or not isinstance(body['rows'],list):return ['page_shape']
        errors=[]
        if body['section']!=payload['p_section'] or len(body['rows'])>payload.get('p_limit',10):errors.append('page_binding')
        ids=[]
        for row in body['rows']:
            errors+=detail_errors(row,actor_id,allowed)
            if isinstance(row,dict):ids.append(row.get('id'))
        if len(ids)!=len(set(ids)):errors.append('duplicate_page_identity')
        return errors
    if label=='detail':return detail_errors(body,actor_id,allowed)
    if label in ('link_exact_retry','journal_exact_retry'):
        expected=live['exact_receipts']['link' if label=='link_exact_retry' else 'age']
        return [] if canonical(body)==expected else ['changed_exact_receipt']
    if label=='worker_batch':return [] if isinstance(body,dict) and body.get('run_id')==payload['p_run_id'] and body.get('failed_count')==0 and isinstance(body.get('processed'),list) else ['worker_receipt']
    if label=='revision_write':return [] if type(body) is int and 1<=body<=128 else ['revision_receipt']
    if label=='report_write':return [] if body=={'saved':True} else ['report_receipt']
    return []

def private_checks(lab,live):
    from runner import Client
    client=Client(lab);checks=[]
    # Pending entrants see their own context; outsiders cannot borrow another actor's challenge/cursor.
    pending=client.require('challenge_detail_v1',{'p_id':live['pending']},350)
    require(pending.get('social_hidden') is True and {m['actor_id'] for m in pending['members']}=={lab.uid('actor',350)},'pending_privacy')
    checks.append('pending_privacy')
    blocked=json.loads(lab.sql("select jsonb_build_object('id',m.challenge_id,'actor',a.ordinal) from public.blocks b join app.challenge_members_v1 m on m.actor_id=b.blocker_id join app.challenge_members_v1 other on other.challenge_id=m.challenge_id and other.actor_id=b.blocked_id join challenge_load_fixture.actors a on a.id=b.blocker_id where m.exited_at is null and other.exited_at is null and m.selected and other.selected limit 1;",'blocked-projection-fixture'))
    view=client.require('challenge_detail_v1',{'p_id':blocked['id']},blocked['actor'])
    require(view.get('social_hidden') is True and not detail_errors(view,lab.uid('actor',blocked['actor']),{blocked['id']}),'blocked_privacy');checks.append('blocked_privacy')
    departed=json.loads(lab.sql("select jsonb_build_object('id',m.challenge_id,'departed',m.actor_id,'actor',a.ordinal) from app.challenge_members_v1 m join app.challenge_members_v1 other on other.challenge_id=m.challenge_id and other.actor_id<>m.actor_id join challenge_load_fixture.actors a on a.id=other.actor_id where m.exited_at is not null and other.exited_at is null limit 1;",'departed-projection-fixture'))
    view=client.require('challenge_detail_v1',{'p_id':departed['id']},departed['actor'])
    require(any(m.get('actor_id')==departed['departed'] for m in view.get('members',[])) and not detail_errors(view,lab.uid('actor',departed['actor']),{departed['id']}),'departed_privacy');checks.append('departed_privacy')
    denied,_=client.request('challenge_issue_link_v1',{'p_request_id':live['link_request'],'p_id':live['pending']},1)
    require(denied['code']=='42501','exact_request_actor_ownership');checks.append('exact_request_actor_ownership')
    denied,_=client.request('challenge_detail_v1',{'p_id':live['personal']['0']},1200)
    require(denied['code']=='42501','cross_actor_detail_denied');checks.append('cross_actor_detail_denied')
    page=client.require('challenge_section_v1',{'p_section':'history','p_limit':10},0)
    require(page.get('next_cursor') is not None,'cursor_fixture_has_next_page')
    first={r['id'] for r in page['rows']};cursor=page['next_cursor']
    next_page=client.require('challenge_section_v1',{'p_section':'history','p_limit':10,'p_cursor':cursor},0)
    require(not first.intersection(r['id'] for r in next_page['rows']),'cursor_no_overlap')
    require(next_page['projection_revision']==page['projection_revision'],'cursor_snapshot_binding')
    denied,_=client.request('challenge_section_v1',{'p_section':'history','p_limit':10,'p_cursor':cursor},1)
    require(denied['code']=='55000','cursor_actor_binding');checks+=['cursor_no_overlap','cursor_snapshot_binding','cursor_actor_binding']
    # Simulate an unknown commit by intentionally discarding the first successful receipt, then recover exactly.
    request=lab.uid('unknown-commit-proof',0);payload={'p_request_id':request,'p_subject':lab.uid('actor',1),'p_reason':'unwanted_contact'}
    client.require('challenge_report_v1',payload,0)
    second=client.require('challenge_report_v1',payload,0);third=client.require('challenge_report_v1',payload,0)
    require(second==third=={'saved':True},'unknown_commit_exact_receipt')
    count=lab.sql('select count(*) from app.challenge_reports_v1 where id=%s;'%q(request),'unknown-commit-count')
    require(count=='1','unknown_commit_single_effect');checks+=['unknown_commit_exact_receipt','unknown_commit_single_effect']
    changed,_=client.request('challenge_report_v1',dict(payload,p_reason='username'),0)
    require(changed['code']=='22023','changed_exact_payload_rejected');checks.append('changed_exact_payload_rejected')
    return checks

def refresh_live_metadata(lab,live,count):
    rows=json.loads(lab.sql("select jsonb_object_agg(ordinal,ids) from (select a.ordinal,coalesce(jsonb_agg(m.challenge_id) filter(where m.challenge_id is not null),'[]') ids from challenge_load_fixture.actors a left join app.challenge_members_v1 m on m.actor_id=a.id where a.ordinal<1000 or a.ordinal=1999 group by a.ordinal) rows;",'authorized-identities'))
    live=dict(live,authorized_ids=rows,accounts=count)
    from runner import Client
    client=Client(lab)
    live['exact_receipts']={'age':canonical(client.require('challenge_confirm_age_v1',{'p_request_id':lab.uid('age-retry',0),'p_confirmed':True},0)),
      'link':canonical(client.require('challenge_issue_link_v1',{'p_request_id':live['link_request'],'p_id':live['pending']},0))}
    path=lab.data/'private'/('live-'+str(count)+'.json')
    require(not path.exists(),'live_manifest_create_exclusive');save(path,live)
    return live

def write_preflight(lab,live):
    count=live['accounts'];destination=lab.data/('preflight-'+str(count)+'.json')
    require(not destination.exists(),'preflight_create_exclusive')
    checks=structural(lab);coverage=validate_history(lab);checks+=private_checks(lab,live)
    hashes=history_hash(lab)
    receipt={'passed':True,'accounts':count,'project':lab.m['project'],'cluster_id':lab.cluster_id,'parent':lab.m['parent'],'namespace':str(lab.namespace),
       'core_hashes':core_hashes(),'live_sha256':digest(lab.data/'private'/('live-'+str(count)+'.json')),'history_hashes':hashes,'checks':checks,'coverage':coverage,'unix':time.time()}
    save(destination,receipt);return receipt

def check_preflight(lab,live):
    receipt=json.loads((lab.data/('preflight-'+str(live['accounts'])+'.json')).read_text())
    for key,expected in [('passed',True),('accounts',live['accounts']),('project',lab.m['project']),('cluster_id',lab.cluster_id),('parent',lab.m['parent']),('namespace',str(lab.namespace)),('core_hashes',core_hashes()),('live_sha256',digest(lab.data/'private'/('live-'+str(live['accounts'])+'.json')))]:
        require(receipt.get(key)==expected,'preflight_binding_'+key)
    structural(lab);require(history_hash(lab)==receipt['history_hashes'],'pre_run_historical_immutability')
    return receipt

def postflight(lab,receipt,destination):
    checks=structural(lab);hashes=history_hash(lab)
    require(hashes==receipt['history_hashes'],'post_run_historical_immutability')
    result={'passed':True,'checks':checks+['historical_immutability'],'history_hashes':hashes,'unix':time.time()}
    save(destination,result);return result
