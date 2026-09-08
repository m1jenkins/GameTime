#!/usr/bin/env python3
"""Authenticated local operator CLI acceptance, wholly fictional inputs."""
import importlib.util
import json
from pathlib import Path
import subprocess
import uuid

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('beta_native_support',ROOT/'scripts/beta-native-smoke.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

def main():
    smoke=module.Smoke();checks=[]
    def check(value,label):
        assert value,label
        checks.append(label);print('PASS: '+label,flush=True)
    def cli(*args,actor=None,ok=True):
        command=[str(ROOT/'scripts/beta-operator.py'),'--owned-project','gametime-finish-b7']
        if actor:command+=['--local-actor',str(actor)]
        result=subprocess.run(command+list(args),capture_output=True,text=True)
        if not ok:
            check(result.returncode!=0 and '42501' in result.stderr,'unassigned authenticated operator is rejected');return
        assert result.returncode==0,result.stderr
        return json.loads(result.stdout)
    def rpc(name,body,headers):
        status,data=module.local_http('POST','/rest/v1/rpc/'+name,headers,json.dumps(body))
        assert status<300,(name,status)
        return json.loads(data) if data else None
    def mutate(i,cid,op,**fields):
        if cid:
            row=rpc('challenge_detail_v1',{'p_id':cid},auth[i]);fields.update(id=cid,revision=row['revision'])
        return rpc('challenge_command_v1',{'p_request_id':str(uuid.uuid4()),'p_payload':dict(op=op,**fields)},auth[i])
    auth=[];config_path=ROOT/'tmp/beta-operator-community.json'
    try:
        smoke.setup()
        for i in [0,1]:
            status,raw=module.local_http('POST','/auth/v1/token?grant_type=password',{'apikey':smoke.key,'Content-Type':'application/json'},json.dumps({'email':smoke.actors[i]['email'],'password':smoke.password}))
            assert status==200
            auth.append({'apikey':smoke.key,'Authorization':'Bearer '+json.loads(raw)['access_token'],'Content-Type':'application/json'})
            mutate(i,None,'confirm_age',confirmed=True)
        config={'start_date':'2026-10-03','days':1,'timezone':'UTC','amount_cents':100}
        cid=mutate(0,None,'create',config=config)['id'];mutate(0,cid,'target',target=100)
        mutate(0,cid,'invite',username=smoke.actors[1]['username']);mutate(1,cid,'target',target=100)
        mutate(0,cid,'select',actor_id=smoke.actors[1]['id'],selected=True);mutate(0,cid,'freeze')
        for i in [0,1]:
            row=rpc('challenge_detail_v1',{'p_id':cid},auth[i]);mutate(i,cid,'consent',consent=True,digest=row['agreement']['digest'])
        smoke.clock('2026-10-03T12:00:00Z')
        for i in [0,1]:smoke.control_call({'action':'capture','id':cid,'actor':smoke.actors[i]['id'],'value':200})
        smoke.clock('2026-10-06T12:00:00Z');smoke.control_call({'action':'process','id':cid})
        mutate(0,cid,'review',notice_revision=1,reason='wrong_total')
        cli('cases','--challenge',cid,actor=1,ok=False)
        cli('grant','--actor',smoke.actors[6]['id'],'--challenge',cid,'--capability','review','--expires','2026-10-10T12:00:00Z')
        cases=cli('cases','--challenge',cid,actor=7);check(len(cases)==1,'assigned authenticated CLI reviewer sees the structured case')
        context=cases[0]['context']
        check(context['target']==100 and context['fact']['value']==200 and context['provisional']['returned_cents']==100 and 'participants' not in context and 'username' not in context,'review context includes only agreed policy and filer’s normalized result')
        request=str(uuid.uuid4());args=['resolve','--challenge',cid,'--review',cases[0]['id'],'--decision','upheld','--request-id',request]
        receipt=cli(*args,actor=7);check(receipt['saved'],'authenticated CLI resolves its assigned case')
        check(cli(*args,actor=7)==receipt,'operator exact recovery works across separate sign-ins')
        smoke.clock('2026-10-08T12:00:00Z')
        run=str(uuid.uuid4());batch=cli('run-once','--run-id',run,'--limit','10')
        check(batch['failed_count']==0 and any(row['id']==cid and row['status']=='final' for row in batch['processed']),'bounded CLI worker reaches final')
        check(cli('run-once','--run-id',run,'--limit','10')==batch,'worker exact retry is stable')
        final=rpc('challenge_detail_v1',{'p_id':cid},auth[0])['final']
        check(final['result']['participants'][smoke.actors[0]['id']]['returned_cents']==100,'operator logout leaves another participant session working')
        rpc('challenge_report_v1',{'p_request_id':str(uuid.uuid4()),'p_subject':smoke.actors[1]['id'],'p_reason':'username'},auth[0])
        cli('grant','--actor',smoke.actors[6]['id'],'--challenge',cid,'--capability','moderate','--expires','2026-10-10T12:00:00Z')
        reports=cli('reports','--challenge',cid,actor=7);check(len(reports)==1 and reports[0]['reason']=='username','moderator CLI reads only its assigned structured reports')
        cli('suspend','--challenge',cid,'--subject',smoke.actors[1]['id'],'--reason','username','--request-id',str(uuid.uuid4()),actor=7)
        hidden=rpc('challenge_detail_v1',{'p_id':cid},auth[1])
        check(hidden['social_hidden'] and len(hidden['members'])==1 and hidden['final']['result']['own']['returned_cents']==100,'post-final suspension hides shared detail and preserves own final return')
        config.update(start_date='2026-10-10');config_path.write_text(json.dumps(config))
        community=cli('publish-fixture','--operator',smoke.actors[6]['id'],'--config-file',str(config_path),'--target','100','--minimum','2','--capacity','6','--request-id',str(uuid.uuid4()),'--fictional')
        cli('grant','--actor',smoke.actors[6]['id'],'--challenge',community,'--capability','moderate','--expires','2026-10-12T12:00:00Z')
        closed=cli('close-community','--challenge',community,'--request-id',str(uuid.uuid4()),actor=7)
        check(closed['status']=='cancelled','fixture-only publication and authenticated scoped closure work')
        (ROOT/'tmp/beta-operator-report.json').write_text(json.dumps({'evidence':'authenticated local CLI and Auth-server; fictional data','checks':checks,'count':len(checks)},indent=2)+'\n')
    finally:
        config_path.unlink(missing_ok=True);smoke.cleanup()
        print('Owned fixture gates off and only this run’s actor sessions revoked.',flush=True)
if __name__=='__main__':main()
