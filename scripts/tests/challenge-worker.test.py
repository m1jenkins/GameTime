import sys
from pathlib import Path
import threading
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from challenge_worker import run_once


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
        self.assertEqual(result['failed_count'],1)
        self.assertEqual(result['processed'][0],{'id':'0','claim_token':'token0','request_failed':'TimeoutError'})
        self.assertNotIn('private',str(result))

    def test_claim_failure_is_reported_and_does_not_start_completions(self):
        attempted=[]
        def rpc(name,payload):
            attempted.append(name)
            raise RuntimeError('claim failed')
        with self.assertRaises(RuntimeError): run_once(rpc,'run')
        self.assertEqual(attempted,['challenge_claim_batch_v1'])


if __name__=='__main__': unittest.main()
