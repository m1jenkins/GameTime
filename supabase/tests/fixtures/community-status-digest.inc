-- Test-only digest; never emits the rows or sequence values it reads.
create function pg_temp.data_digest() returns text language plpgsql as $$
declare r record; d text; parts text := ''; begin
 for r in select n.nspname,c.relname,c.relkind from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('app','public','auth') and c.relkind in ('r','p','S') order by n.nspname,c.relname loop
  if r.relkind='S' then
   execute format('select md5(row(last_value,is_called)::text) from %I.%I',r.nspname,r.relname) into d;
  else
   execute format('select md5(coalesce(string_agg(v,E''\n'' order by v),'''')) from (select to_jsonb(t)::text v from %I.%I t) s',r.nspname,r.relname) into d;
  end if;
  parts:=parts||r.nspname||'.'||r.relname||':'||d;
 end loop;
 return md5(parts);
end $$;
