import sys
from pathlib import Path
import threading
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from challenge_worker import run_once, snapshot_once


class WorkerTests(unittest.TestCase):
    def test_failure_does_not_abandon_the_rest_of_the_batch(self):
        attempted=[]
        lock=threading.Lock()
        def rpc(name,payload):
            if name=='challenge_claim_batch_v1':
                return {'claims':[{'id':str(i),'claim_token':'token'+str(i)} for i in range(20)],'server_time':'fixture'}
            with lock: attempted.append(payload['p_id'])
            if payload['p_id']=='0': raise TimeoutError('private response must not be retained')
            return {'id':payload['p_id'],'status':'review'}
        result=run_once(rpc,'run',20)
        self.assertEqual(len(set(attempted)),20)
        self.assertEqual(attempted.count('0'),3)
        self.assertEqual(result['failed_count'],1)
        self.assertEqual(result['processed'][0],{'id':'0','claim_token':'token0','request_failed':'transport_timeout'})
        self.assertNotIn('private',str(result))

    def test_claim_failure_is_reported_and_does_not_start_completions(self):
        attempted=[]
        def rpc(name,payload):
            attempted.append(name)
            raise RuntimeError('claim failed')
        with self.assertRaises(RuntimeError): run_once(rpc,'run')
        self.assertEqual(attempted,['challenge_claim_batch_v1'] * 3)

    def test_scoped_invocation_is_prepared_before_dispatch_and_replayed_exactly(self):
        calls=[]
        scope={'version':'challenge_worker_scope_v1','kind':'due'}
        def rpc(name,payload):
            calls.append((name,payload.copy()))
            if name=='challenge_prepare_worker_invocation_v1':
                return {'invocation_id':payload['p_invocation_id'],'status':'prepared'}
            if name=='challenge_dispatch_worker_invocation_v1':
                return {'invocation_id':payload['p_invocation_id'],'status':'dispatched',
                        'claims':[],'server_time':'fixture'}
            raise AssertionError(name)
        result=run_once(rpc,'invocation',20,scope=scope)
        self.assertEqual(result['status'],'dispatched')
        self.assertEqual([name for name,_ in calls], [
            'challenge_prepare_worker_invocation_v1',
            'challenge_dispatch_worker_invocation_v1',
        ])
        self.assertEqual(calls[0][1]['p_scope'],scope)
        self.assertEqual(calls[0][1]['p_limit'],20)

    def test_snapshot_uses_same_invocation_identity_for_prepare_and_dispatch(self):
        calls=[]
        def rpc(name,payload):
            calls.append((name,payload.copy()))
            return {'invocation_id':payload.get('p_invocation_id'),'status':'checked'}
        result=snapshot_once(rpc,'invocation','challenge')
        self.assertEqual(result['status'],'checked')
        self.assertEqual(calls[0][1]['p_invocation_id'],calls[1][1]['p_invocation_id'])
        self.assertEqual(calls[0][1]['p_id'],'challenge')


if __name__=='__main__': unittest.main()
