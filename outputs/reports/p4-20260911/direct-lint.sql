begin;
create extension if not exists plpgsql_check with schema extensions;
create temp table p4_lint(function_name text,details jsonb);
do $$ declare f record; e record; begin
 for f in select p.oid,p.oid::regprocedure::text name from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname in ('app','public') and l.lanname='plpgsql' and p.prorettype<>'trigger'::regtype loop
  begin
   for e in select * from extensions.plpgsql_check_function_tb(f.oid) loop
    insert into p4_lint values(f.name,to_jsonb(e));
   end loop;
  exception when others then insert into p4_lint values(f.name,jsonb_build_object('level','checker_error','sqlstate',sqlstate));
  end;
 end loop;
end $$;
select jsonb_build_object('function',function_name,'details',details) from p4_lint order by function_name;
rollback;
