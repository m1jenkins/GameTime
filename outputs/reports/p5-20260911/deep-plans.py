exec(open('/private/tmp/gametime-p5-20260911/measure.py').read().split('queries={')[0])
after=json.loads(q("select jsonb_build_array(sort_at,starts_at,challenge_id) from app.challenge_history_v1 where actor_id='"+actor+"' order by sort_at desc,starts_at,challenge_id offset 9950 limit 1"))
body=q("select prosrc from pg_proc where oid='app.challenge_history_slice_v1(uuid,timestamptz,timestamptz,uuid,integer)'::regprocedure")
# PREPARE the exact inner body under a generic plan, not a constant-folded proxy.
for word,param in [('after_time','$2'),('after_start','$3'),('after_id','$4'),('bound','$5')]:body=__import__('re').sub(r'\b'+word+r'\b',param,body)
body=__import__('re').sub(r'\ba\b','$1',body)
for label,args in [('first',"'"+actor+"',null,null,null,51"),('deep',"'"+actor+"','"+after[0]+"','"+after[1]+"','"+after[2]+"',51")]:
 sql='begin;set local plan_cache_mode=force_generic_plan;prepare p5_slice(uuid,timestamptz,timestamptz,uuid,integer) as '+body+';explain(analyze,buffers,format json) execute p5_slice('+args+');rollback;'
 plan=json.loads(q(sql));(out/(label+'-generic.json')).write_text(json.dumps(plan,indent=2))
 print(label,plan[0]['Execution Time'],plan[0]['Plan']['Shared Hit Blocks'])
body=q("select prosrc from pg_proc where oid='app.challenge_work_v1()'::regprocedure")
(out/'work-inner-final.json').write_text(q('explain(analyze,buffers,format json) '+body+';'))
indexes=q("select jsonb_agg(jsonb_build_object('name',c.relname,'bytes',pg_relation_size(c.oid))) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and c.relname in ('challenge_history_v1','challenge_history_v1_pkey','challenge_history_revisions_v1','challenge_history_revisions_v1_pkey','challenge_history_order_v1','challenge_live_creator_v1','challenge_worker_runs_recorded_v1')")
(out/'storage.json').write_text(indexes)
# Exercise every boundary in the dense corpus, then compare the full order.
sql="begin;create temp table chain_ids(n bigint generated always as identity,id uuid);grant all on chain_ids to authenticated;"+login+"""
do $$ declare cur jsonb;page jsonb;calls integer:=0;begin
 loop
  page:=public.challenge_section_v1('history',cur,50);calls:=calls+1;
  if calls>1000 then raise exception 'P5 page loop';end if;
  insert into chain_ids(id) select (r->>'id')::uuid from jsonb_array_elements(page->'rows') r;
  cur:=page->'next_cursor';exit when cur='null'::jsonb;
 end loop;
end $$;reset role;
select jsonb_build_object('returned',(select count(*) from chain_ids),'unique',(select count(distinct id) from chain_ids),
'exact_order',(select jsonb_agg(id order by n) from chain_ids)=(select jsonb_agg(challenge_id order by sort_at desc,starts_at,challenge_id) from app.challenge_history_v1 where actor_id='"""+actor+"""'),'stored_ids',(select max(cardinality(ids)) from app.challenge_pages_v1 where history_revision is not null));rollback;
"""
(out/'dense-chain.json').write_text(q(sql));print((out/'dense-chain.json').read_text())
