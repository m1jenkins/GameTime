#!/usr/bin/env python3
"""Summarize retained, sanitized event files without connecting to any service."""
from __future__ import annotations
import argparse,collections,hashlib,json,math,pathlib,time

def sha(raw):return hashlib.sha256(raw).hexdigest()

def optional_bytes(path):
    try:return path.read_bytes()
    except FileNotFoundError:return None

def captured_records(raw):
    boundary=raw.rfind(b'\n')+1
    return [json.loads(line) for line in raw[:boundary].splitlines()],len(raw)-boundary

def final_errors(source,spec,events,trailing):
    errors=[];complete=[e for e in events if 'finish_seconds' in e];dropped=[e for e in events if 'dropped' in e]
    def check(condition,label):
        if not condition:errors.append(label)
    check(not trailing,'incomplete_event_tail')
    check(len(complete)+len(dropped)==len(events),'unknown_event_disposition')
    check(bool(source.get('parent')) and bool(source.get('project')),'source_identity')
    if 'profile' in source:
        check(isinstance(spec,dict),'missing_spec')
        if isinstance(spec,dict):
            for key,value in spec.items():check(source.get(key)==value,'spec_binding_'+key)
        counts=source.get('counts',{});duration=source.get('duration_seconds',0)
        check(isinstance(duration,(int,float)) and duration>0,'duration')
        planned=sum(math.floor(d*r) for d,r in source.get('stages',[]))
        check(duration==sum(d for d,r in source.get('stages',[])),'stage_duration')
        inside=sum(e['finish_seconds']<=duration for e in complete)
        failed=sum(e.get('status')!=200 or bool(e.get('oracle_failures')) for e in complete)
        for key,value in [('completed',len(complete)),('started',len(complete)),('dropped',len(dropped)),('completed_in_window',inside),('failed',failed),('oracle_failures',sum(len(e.get('oracle_failures',[])) for e in complete))]:
            check(counts.get(key,0)==value,'count_'+key)
        check(source.get('offered')==len(events),'offered')
        check(source.get('planned_offers')==planned and planned>=len(events),'planned')
        check(source.get('not_offered_after_abort')==planned-len(events),'not_offered')
        check(source.get('completed_after_window')==len(complete)-inside,'drain_count')
        if duration>0:
            check(math.isclose(source.get('offered_rps',-1),len(events)/duration,abs_tol=1e-9),'offered_rate')
            check(math.isclose(source.get('completed_in_window_rps',-1),inside/duration,abs_tol=1e-9),'completed_rate')
        check(source.get('elapsed_seconds',-1)>=max([e['finish_seconds'] for e in complete]+[0]),'elapsed_window')
        check({e.get('index') for e in events}==set(range(len(events))),'contiguous_arrival_indexes')
        check(source.get('accounting_ok') is True,'source_accounting')
        if source.get('capacity_pass'):
            check(not source.get('aborted') and len(events)==planned and inside==planned and not failed and not dropped and source.get('postflight_passed') is True and not source.get('monitor_errors'),'capacity_disposition')
    elif source.get('kind') in ('foreground','join'):
        check(bool(source.get('harness_sha256')) and bool(source.get('preflight_sha256')),'burst_source_binding')
        check(not dropped and source.get('completed_requests')==len(complete),'burst_completed')
        check(source.get('offered_requests',0)-len(complete)==source.get('generator_dropped_requests'),'burst_dropped')
        check(source.get('accepted')==sum(e.get('status')==200 for e in complete),'burst_accepted')
        check(source.get('expected_capacity_refusals')==sum(e.get('expected_capacity',False) for e in complete),'burst_capacity')
        check(source.get('unexpected_failures')==sum(e.get('status')!=200 and not e.get('expected_capacity') for e in complete),'burst_failures')
        check(source.get('finish_unix',0)-source.get('start_unix',0)>=max([e['finish_seconds'] for e in complete]+[0])-.01,'burst_window')
        if source.get('passed'):check(not source.get('generator_errors') and not source.get('unexpected_failures') and bool(source.get('oracles')) and all(source['oracles'].values()),'burst_disposition')
    else:errors.append('unknown_summary_producer')
    return errors

def distribution(values):
    ordered=sorted(values)
    def at(p):return ordered[min(len(ordered)-1,math.ceil(len(ordered)*p)-1)] if ordered else None
    return {'count':len(ordered),'p50':at(.5),'p95':at(.95),'p99':at(.99),'max':ordered[-1] if ordered else None}

def overlap(events):
    edges=[]
    for event in events:
        if 'dispatch_seconds' in event and 'finish_seconds' in event:
            edges.extend([(event['dispatch_seconds'],1),(event['finish_seconds'],-1)])
    current=peak=0
    for _,change in sorted(edges):current+=change;peak=max(peak,current)
    return peak

def summarize(directory):
    captured_at=time.time()
    # Presence is defined before capturing events. A later publication requires a new report.
    summary_raw=optional_bytes(directory/'summary.json');spec_raw=optional_bytes(directory/'spec.json')
    reporter_raw=pathlib.Path(__file__).read_bytes()
    event_path=directory/'events.jsonl'
    event_raw=event_path.read_bytes();events,trailing=captured_records(event_raw)
    complete=[e for e in events if 'finish_seconds' in e]
    dropped=[e for e in events if 'dropped' in e]
    failures=[e for e in complete if e.get('status')!=200 or e.get('oracle_failures')]
    recovered=[e for e in complete if e.get('recovery')]
    operations={}
    for operation in sorted({e['operation'] for e in complete}):
        selected=[e for e in complete if e['operation']==operation]
        operations[operation]={}
        for label,predicate in [('success',lambda e:e.get('status')==200 and not e.get('oracle_failures')),
          ('expected_capacity',lambda e:e.get('expected_capacity',False)),
          ('unexpected_failure',lambda e:(e.get('status')!=200 or e.get('oracle_failures')) and not e.get('expected_capacity'))]:
            subset=[e for e in selected if predicate(e)]
            operations[operation][label]={'http_seconds':distribution([e['seconds'] for e in subset if 'seconds' in e]),
              'arrival_to_finish_seconds':distribution([e['finish_seconds']-e.get('scheduled_seconds',e['dispatch_seconds']) for e in subset]),
              'response_bytes':sum(e.get('bytes',0) for e in subset)}
    result={'scenario':directory.name,'events_sha256':sha(event_raw),'events_captured_bytes':len(event_raw),'unparsed_trailing_bytes':trailing,
      'capture_started_unix':captured_at,'reporter_sha256':sha(reporter_raw),'reporter':'scripts/challenge-load/summarize.py',
      'spec_sha256':sha(spec_raw) if spec_raw is not None else None,
      'event_records':len(events),'completed_primary_operations':len(complete),'dropped':len(dropped),
      'non_200_or_oracle_failure':len(failures),'expected_capacity_refusals':sum(e.get('expected_capacity',False) for e in complete),
      'failure_codes':dict(collections.Counter(str(e.get('code')) for e in failures)),
      'oracle_failure_labels':dict(collections.Counter(label for e in complete for label in e.get('oracle_failures',[]))),
      'drop_reasons':dict(collections.Counter(e['dropped'] for e in dropped)),
      'additional_recovery_http_attempts':sum(e['recovery']['attempts'] for e in recovered),
      'primary_plus_recovery_http_attempts':len(complete)+sum(e['recovery']['attempts'] for e in recovered),
      'distinct_primary_actor_ordinals':len({e['actor_ordinal'] for e in complete if 'actor_ordinal' in e}),
      'peak_dispatched_logical_operations':overlap(complete),
      'peak_scope':'dispatch-to-finish overlap, including client cursor serialization and recovery; not a database connection count',
      'dispatch_lag_seconds':distribution([e['dispatch_seconds']-e['scheduled_seconds'] for e in complete if 'scheduled_seconds' in e]),
      'operations':operations,'latency_population':'all completed primary operations, including drain; first HTTP attempt only for HTTP duration/bytes',
      'transport_scope':'primary completed operations plus their recorded recovery attempts; excludes unfinished work, canary/preflight calls and join-winner verification retries',
      'final_summary_present_at_capture_start':summary_raw is not None,'final_summary_available':False,'snapshot_kind':'partial'}
    spec=json.loads(spec_raw) if spec_raw is not None else None
    result['source_identity']={k:spec[k] for k in ['parent','project','name','profile','start_unix','harness_hashes','preflight_sha256'] if isinstance(spec,dict) and k in spec}
    if summary_raw is not None:
        result['summary_sha256']=sha(summary_raw)
        try:
            source=json.loads(summary_raw);errors=final_errors(source,spec,events,trailing)
        except (ValueError,KeyError,TypeError) as error:errors=['invalid_final_summary_'+type(error).__name__]
        result['final_consistency_errors']=errors
        result['snapshot_kind']='inconsistent' if errors else 'finalized_attempt'
        if not errors:
            result['final_summary_available']=True
            result['final_disposition']={k:source[k] for k in ['capacity_pass','passed','aborted','duration_seconds','elapsed_seconds','offered','planned_offers','completed_after_window','drain_seconds','completed_in_window_rps','offered_rps','not_offered_after_abort','accounting_ok','postflight_passed','oracles'] if k in source}
            result['planned_window_completed']=(not source.get('aborted') and source.get('not_offered_after_abort')==0 and source.get('elapsed_seconds',0)>=source.get('duration_seconds',float('inf'))) if 'profile' in source else None
            result['source_identity'].update({k:source[k] for k in ['parent','project','kind','start_unix','finish_unix','harness_sha256','preflight_sha256'] if k in source})
    result['interpretation']='Final source disposition bound to captured event accounting; reporter success is not capacity acceptance.' if result['final_summary_available'] else 'Partial or inconsistent snapshot only; no final disposition imported. Capture a new uniquely named report after completion.'
    return result

def summarize_observer(directory):
    raw=(directory/'samples.jsonl').read_bytes();samples,trailing=captured_records(raw)
    valid=[s for s in samples if 'db' in s and not s.get('observer_error')]
    database={};tables={};docker=collections.defaultdict(list)
    if valid:
        before=valid[0]['db'];after=valid[-1]['db']
        for key in ['xact_commit','xact_rollback','blks_read','blks_hit','tup_returned','tup_fetched','tup_inserted','tup_updated','tup_deleted','conflicts','temp_files','temp_bytes','deadlocks']:
            start=before.get('database',{}).get(key);end=after.get('database',{}).get(key)
            if isinstance(start,(int,float)) and isinstance(end,(int,float)):
                database[key]={'start':start,'end':end,'delta':end-start if end>=start else None,'counter_decreased':end<start}
        start_tables={t['name']:t for t in before.get('tables',[])}
        for table in after.get('tables',[]):
            original=start_tables.get(table['name'],{});row={'final_rows_estimate':table.get('rows_estimate'),'final_dead_rows_estimate':table.get('dead_rows_estimate')}
            for key in ['seq_scan','seq_tup_read','idx_scan','idx_tup_fetch','inserts','updates','deletes']:
                start=original.get(key);end=table.get(key)
                if isinstance(start,(int,float)) and isinstance(end,(int,float)):row[key+'_delta']=end-start if end>=start else None
            tables[table['name']]=row
        for sample in valid:
            for container in sample.get('docker',[]):
                try:docker[container['Name']].append(float(container['CPUPerc'].rstrip('%')))
                except (KeyError,ValueError):pass
    return {'observer':directory.name,'samples_sha256':sha(raw),'samples_captured_bytes':len(raw),'unparsed_trailing_bytes':trailing,
      'capture_unix':time.time(),'reporter_sha256':sha(pathlib.Path(__file__).read_bytes()),'snapshot_kind':'observer_snapshot_no_completion_claim',
      'samples':len(samples),'complete_samples':len(valid),'observer_errors':[{'unix':s['unix'],'error':s['observer_error']} for s in samples if s.get('observer_error')],
      'docker_command_failures':sum(s.get('docker_exit_code',0)!=0 for s in samples),
      'sample_time_gaps_seconds':distribution([b['unix']-a['unix'] for a,b in zip(samples,samples[1:])]),
      'covered_seconds':samples[-1]['unix']-samples[0]['unix'] if len(samples)>1 else 0,
      'host_load_1m':distribution([s['host_load'][0] for s in samples]),
      'db_size_bytes':{'first':valid[0]['db']['db_size_bytes'],'last':valid[-1]['db']['db_size_bytes']} if valid else None,
      'sampled_lock_waiting_sessions':distribution([sum(s.get('wait_event_type')=='Lock' for s in sample['db'].get('sessions',[])) for sample in valid]),
      'wait_event_counts':dict(collections.Counter(str(s.get('wait_event_type'))+'/'+str(s.get('wait_event')) for sample in valid for s in sample['db'].get('sessions',[]) if s.get('state')=='active')),
      'ungranted_lock_mode_samples':dict(collections.Counter(l['locktype']+'/'+l['mode'] for sample in valid for l in sample['db'].get('locks',[]) if not l.get('granted'))),
      'docker_cpu_percent':{name:distribution(values) for name,values in sorted(docker.items())},
      'database_counter_deltas':database,'table_counter_deltas':tables,
      'interpretation':'Sampled observations, not per-request lock attribution. CPU percent uses Docker core-relative units; statistics deltas include the observer and structural checks. Row counts here are estimates; use audit.json for exact counts.'}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('scenario_directory');parser.add_argument('--out',required=True);parser.add_argument('--observer',action='store_true')
    args=parser.parse_args();destination=pathlib.Path(args.out)
    result=(summarize_observer if args.observer else summarize)(pathlib.Path(args.scenario_directory))
    with destination.open('x') as stream:stream.write(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'evidence':str(destination),'event_records':result.get('event_records'),'samples':result.get('samples'),'final_summary_available':result.get('final_summary_available')}))

if __name__=='__main__':main()
