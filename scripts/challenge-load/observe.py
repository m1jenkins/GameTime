#!/usr/bin/env python3
"""Read-only sampling of the owned database and containers; no query text or secrets."""
from __future__ import annotations
import argparse,json,os,pathlib,subprocess,time
from lab import Lab,save

SNAPSHOT="""select jsonb_build_object(
 'db_size_bytes',pg_database_size(current_database()),
 'database',(select to_jsonb(d)-'stats_reset' from pg_stat_database d where datname=current_database()),
 'locks',(select coalesce(jsonb_agg(jsonb_build_object('pid',pid,'locktype',locktype,'relation',relation::regclass::text,'page',page,'tuple',tuple,'transactionid',transactionid,'virtualxid',virtualxid,'mode',mode,'granted',granted,'waitstart',waitstart)),'[]') from pg_locks where database=(select oid from pg_database where datname=current_database()) or pid in(select pid from pg_stat_activity where datname=current_database())),
 'sessions',(select coalesce(jsonb_agg(jsonb_build_object('pid',pid,'application_name',application_name,'state',state,
   'wait_event_type',wait_event_type,'wait_event',wait_event,'blocking_pids',pg_blocking_pids(pid),
   'transaction_age_seconds',extract(epoch from clock_timestamp()-xact_start))), '[]') from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid()),
 'tables',(select jsonb_agg(jsonb_build_object('name',relname,'rows_estimate',n_live_tup,'dead_rows_estimate',n_dead_tup,
   'seq_scan',seq_scan,'seq_tup_read',seq_tup_read,'idx_scan',idx_scan,'idx_tup_fetch',idx_tup_fetch,'inserts',n_tup_ins,'updates',n_tup_upd,'deletes',n_tup_del))
   from pg_stat_user_tables where schemaname='app' and relname like 'challenge_%%'));
"""

def observe(lab,name,seconds):
    destination=lab.data/name
    destination.mkdir(mode=0o700)
    names=list(lab.m['container_ids'])
    settings=lab.sql("select jsonb_object_agg(name,setting) from pg_settings where name in ('server_version','max_connections','shared_buffers','work_mem','effective_cache_size','statement_timeout','track_io_timing','shared_preload_libraries','track_functions','jit','default_transaction_isolation');",'db-settings')
    host={'cpu_count':os.cpu_count(),'platform':os.uname().sysname,'machine':os.uname().machine}
    for key,argv in [('host_memory',['sysctl','-n','hw.memsize']),('docker_resources',['docker','info','--format','{{json .MemTotal}} {{json .NCPU}}'])]:
        proc=subprocess.run(argv,text=True,capture_output=True);host[key]={'exit_code':proc.returncode,'output':proc.stdout.strip()}
    save(destination/'environment.json',{'database_settings':json.loads(settings),'host':host,'project':lab.m['project']})
    start=time.monotonic()
    with (destination/'samples.jsonl').open('x',buffering=1) as f:
        while time.monotonic()-start<seconds:
            begin=time.monotonic()
            sample={'unix':time.time(),'elapsed_seconds':begin-start,'host_load':os.getloadavg()}
            try:
                sample['db']=json.loads(lab.sql(SNAPSHOT,'observe',timeout=45))
                process=subprocess.run(['docker','stats','--no-stream','--format','{{json .}}']+names,text=True,capture_output=True,timeout=15)
                sample['docker_exit_code']=process.returncode
                sample['docker']=[json.loads(line) for line in process.stdout.splitlines()]
            except Exception as e:
                sample['observer_error']=type(e).__name__
            f.write(json.dumps(sample,separators=(',',':'))+'\n')
            time.sleep(max(0,min(30-(time.monotonic()-begin),seconds-(time.monotonic()-start))))
    print(json.dumps({'observer_complete':name,'elapsed_seconds':time.monotonic()-start}))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('run_root');parser.add_argument('--name',required=True);parser.add_argument('--seconds',type=int,default=7200)
    args=parser.parse_args()
    if not args.name.replace('-','').isalnum():raise ValueError('simple observer name required')
    observe(Lab(args.run_root),args.name,args.seconds)
if __name__=='__main__':main()
