-- SQL behavior adapter only. Real transaction boundaries are exercised by the
-- Python race harness and challenge_worker.run_once, not by this pgTAP helper.
create function pg_temp.beta_run_batch(r uuid,n integer) returns jsonb
language plpgsql as $$
declare batch jsonb; claim jsonb; response jsonb; processed jsonb := '[]'; failures integer := 0;
begin
 batch := public.challenge_claim_batch_v1(r,n);
 for claim in select value from jsonb_array_elements(batch->'claims') loop
  response := public.challenge_complete_claim_v1((claim->>'id')::uuid,(claim->>'claim_token')::uuid);
  processed := processed||jsonb_build_array(response);
  if response ? 'error_code' then failures := failures+1; end if;
 end loop;
 return jsonb_build_object('run_id',r,'processed',processed,'failed_count',failures,'server_time',batch->'server_time');
end $$;
