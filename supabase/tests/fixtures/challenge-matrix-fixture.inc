-- Fictional SQL-role helper shared by the policy acceptance matrix.
create function pg_temp.matrix_create(p text,a integer) returns uuid language plpgsql as $$
declare cfg jsonb; preview jsonb; c uuid; m text:=split_part(p,'_',2); begin
 perform set_config('role','none',true);perform pg_temp.clock_beta('2026-10-01T12:00Z');
 perform public.challenge_readiness_metric_fixture_v1(pg_temp.ba(a),m);
 perform pg_temp.login_beta(a);
 cfg:='{"start_date":"2026-10-03","days":1,"timezone":"UTC","amount_cents":100}';
 if m='timed' then cfg:=cfg||'{"distance_mm":1609344}';end if;
 if split_part(p,'_',1)='personal' then
  preview:=public.challenge_personal_preview_v1(p,cfg,100);
  c:=(public.challenge_mutate_v1(extensions.gen_random_uuid(),jsonb_build_object('op','personal_commit','policy',p,'config',cfg,'target',100,'digest',preview->>'digest','consent',true))->>'id')::uuid;
  perform set_config('role','none',true);return c;
 end if;
 c:=(public.challenge_mutate_v1(extensions.gen_random_uuid(),jsonb_build_object('op','create','policy',p,'config',cfg))->>'id')::uuid;
 if split_part(p,'_',3)='goal' then perform pg_temp.beta_mutate(c,'target','{"target":100}');end if;
 if split_part(p,'_',1)='friend' then
  perform pg_temp.beta_mutate(c,'invite',jsonb_build_object('username','betafixture'||lpad((a+1)::text,4,'0')));
  perform set_config('role','none',true);perform public.challenge_readiness_metric_fixture_v1(pg_temp.ba(a+1),m);
  perform pg_temp.login_beta(a+1);
  if split_part(p,'_',3)='goal' then perform pg_temp.beta_mutate(c,'target','{"target":100}');end if;
  perform pg_temp.login_beta(a);perform pg_temp.beta_mutate(c,'select',jsonb_build_object('actor_id',pg_temp.ba(a+1),'selected',true));
 end if;
 perform pg_temp.beta_mutate(c,'freeze');
 perform pg_temp.beta_mutate(c,'consent',jsonb_build_object('consent',true,'digest',public.challenge_detail_v1(c)->'agreement'->>'digest'));
 if split_part(p,'_',1)='friend' then
  perform pg_temp.login_beta(a+1);perform pg_temp.beta_mutate(c,'consent',jsonb_build_object('consent',true,'digest',public.challenge_detail_v1(c)->'agreement'->>'digest'));
 end if;
 perform set_config('role','none',true); return c;
end $$;
