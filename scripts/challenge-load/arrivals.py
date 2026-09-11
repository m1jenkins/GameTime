"""Open arrivals independent of service time, with explicit capacity and abort disposition."""
from __future__ import annotations
import collections,concurrent.futures,math,threading,time

def schedule(stages):
    offset=0.0
    for duration,rate in stages:
        for i in range(math.floor(duration*rate)):yield offset+i/rate
        offset+=duration

def execute(stages,cap,perform,emit,stop=None):
    stop=stop or threading.Event();lock=threading.Lock();slots=threading.BoundedSemaphore(cap)
    duration=sum(d for d,r in stages);planned=sum(math.floor(d*r) for d,r in stages)
    counts=collections.Counter();started=time.monotonic();all_events=[]
    def event(value):
        with lock:all_events.append(value);emit(value)
    def invoke(index,offset):
        dispatch=time.monotonic()-started
        try:sample=perform(index)
        except Exception as error:sample={'status':0,'code':type(error).__name__,'oracle_failures':['uncaught_worker_failure'],'operation':'generator'}
        finish=time.monotonic()-started
        failed=sample.get('status')!=200 or bool(sample.get('oracle_failures'))
        with lock:
            counts['completed']+=1;counts['completed_in_window']+=finish<=duration
            counts['failed']+=failed;counts['oracle_failures']+=len(sample.get('oracle_failures',[]))
            if sample.get('oracle_failures') or (counts['completed']>=100 and counts['failed']/counts['completed']>.5):stop.set()
        event({'index':index,'scheduled_seconds':offset,'dispatch_seconds':dispatch,'finish_seconds':finish,**sample})
        slots.release()
    offered=0
    with concurrent.futures.ThreadPoolExecutor(max_workers=cap) as pool:
        for index,offset in enumerate(schedule(stages)):
            if stop.is_set():break
            delay=started+offset-time.monotonic()
            if delay>0 and stop.wait(delay):break
            if stop.is_set():break
            offered+=1
            reason='scheduler_lag' if time.monotonic()-started-offset>1 else None
            if reason is None and not slots.acquire(blocking=False):reason='inflight_cap'
            if reason:
                counts['dropped']+=1;event({'index':index,'scheduled_seconds':offset,'dropped':reason})
            else:counts['started']+=1;pool.submit(invoke,index,offset)
        dispatch_ended=time.monotonic()-started
        if not stop.is_set():stop.wait(max(0,started+duration-time.monotonic()))
    elapsed=time.monotonic()-started
    result={'planned_offers':planned,'offered':offered,'not_offered_after_abort':planned-offered,'duration_seconds':duration,
      'elapsed_seconds':elapsed,'dispatch_ended_seconds':dispatch_ended,'drain_seconds':max(0,elapsed-duration),
      'completed_after_window':counts['completed']-counts['completed_in_window'],'counts':dict(counts),
      'aborted':stop.is_set(),'offered_rps':offered/duration,'completed_in_window_rps':counts['completed_in_window']/duration,
      'completed_including_drain_rps':counts['completed']/elapsed,
      'accounting_ok':counts['started']==counts['completed'] and counts['started']+counts['dropped']==offered}
    result['capacity_pass']=result['accounting_ok'] and not result['aborted'] and offered==planned and counts['dropped']==0 and counts['failed']==0 and counts['completed_in_window']==planned
    return result,all_events
