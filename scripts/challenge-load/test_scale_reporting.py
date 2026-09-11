"""Cross-tier publication and evidence-capture races; no real HTTP/SQL/lifecycle."""
import contextlib,hashlib,io,json,pathlib,tempfile,types,unittest,uuid
from unittest.mock import patch
import oracles,runner,scale,summarize

class OwnedTempTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory(prefix='.evidence-test-',dir=pathlib.Path(__file__).parent)
        self.addCleanup(self.directory.cleanup);self.root=pathlib.Path(self.directory.name)

class ScalePublicationTests(OwnedTempTests):
    def prepare(self,changed):
        (self.root/'private').mkdir();(self.root/'private/live-2000.json').write_text(json.dumps({'accounts':2000}))
        lab=types.SimpleNamespace(data=self.root,m={'parent':'parent','project':'project'},cluster_id='123',namespace=uuid.UUID(int=2),count=2000,hashes={'notices':'old'})
        lab.sql=lambda *_args,**_kwargs:str(lab.count)
        old={'passed':True,'accounts':2000,'parent':'parent','project':'project','cluster_id':'123','namespace':str(lab.namespace),
          'core_hashes':oracles.core_hashes(),'live_sha256':oracles.digest(self.root/'private/live-2000.json'),'history_hashes':dict(lab.hashes)}
        (self.root/'preflight-2000.json').write_text(json.dumps(old))
        def expand_accounts(_lab,_count):lab.count=25000;lab.hashes={'notices':'changed' if changed else 'old'}
        def refresh(_lab,live,count):
            result=dict(live,accounts=count);(self.root/'private/live-25000.json').write_text(json.dumps(result));return result
        stack=contextlib.ExitStack();self.addCleanup(stack.close)
        for target,kwargs in [('scale.accounts',{'side_effect':expand_accounts}),('scale.refresh_live_metadata',{'side_effect':refresh}),
          ('scale.history_hash',{'side_effect':lambda _:dict(lab.hashes)}),('oracles.history_hash',{'side_effect':lambda _:dict(lab.hashes)}),
          ('oracles.structural',{'return_value':[]}),('oracles.validate_history',{'return_value':{}}),('oracles.private_checks',{'return_value':[]})]:stack.enter_context(patch(target,**kwargs))
        return lab

    def test_changed_history_never_publishes_tier_and_independent_runner_refuses(self):
        lab=self.prepare(changed=True)
        with self.assertRaisesRegex(AssertionError,'expansion_preserves_2000_history'):scale.expand(lab)
        self.assertFalse((self.root/'preflight-25000.json').exists())
        self.assertFalse(json.loads((self.root/'tier-history-comparison.json').read_text())['passed'])
        with patch.object(runner,'Client') as client:
            with self.assertRaises(FileNotFoundError):runner.run(lab,'independent','smoke')
            client.assert_not_called()

    def test_matching_history_publishes_independently_admissible_tier(self):
        lab=self.prepare(changed=False)
        with contextlib.redirect_stdout(io.StringIO()):receipt=scale.expand(lab)
        independently_checked=oracles.check_preflight(lab,oracles.load_live(lab))
        self.assertEqual(independently_checked,receipt);self.assertEqual(receipt['accounts'],25000)
        self.assertTrue(json.loads((self.root/'tier-history-comparison.json').read_text())['passed'])

class ReportingCaptureTests(OwnedTempTests):
    def setUp(self):
        super().setUp()
        self.event={'index':0,'scheduled_seconds':0,'dispatch_seconds':0,'finish_seconds':.1,'operation':'access','actor_ordinal':0,'status':200,'seconds':.1,'bytes':2,'oracle_failures':[]}
        self.raw=(json.dumps(self.event)+'\n').encode();(self.root/'events.jsonl').write_bytes(self.raw)
        self.spec={'name':'scenario','profile':'smoke','parent':'parent','project':'project','stages':[[1,1]],'start_unix':1,'harness_hashes':{'runner.py':'pinned'},'preflight_sha256':'preflight'}
        (self.root/'spec.json').write_text(json.dumps(self.spec))
        self.final=dict(self.spec,counts={'started':1,'completed':1,'completed_in_window':1,'failed':0,'oracle_failures':0},duration_seconds=1,
          elapsed_seconds=1,offered=1,planned_offers=1,not_offered_after_abort=0,completed_after_window=0,offered_rps=1,completed_in_window_rps=1,
          accounting_ok=True,capacity_pass=True,aborted=False,postflight_passed=True,monitor_errors=[])

    def test_append_after_capture_keeps_exact_count_and_hash(self):
        original=pathlib.Path.read_bytes;reads=[]
        def read(path):
            raw=original(path)
            if path==self.root/'events.jsonl':
                reads.append(path);path.write_bytes(raw+self.raw)
            return raw
        with patch.object(pathlib.Path,'read_bytes',read):result=summarize.summarize(self.root)
        self.assertEqual(len(reads),1);self.assertEqual(result['event_records'],1)
        self.assertEqual(result['events_sha256'],hashlib.sha256(self.raw).hexdigest())
        self.assertEqual(result['snapshot_kind'],'partial');self.assertNotIn('final_disposition',result)

    def test_final_publication_during_capture_remains_partial(self):
        original=pathlib.Path.read_bytes
        def read(path):
            raw=original(path)
            if path==self.root/'events.jsonl':(self.root/'summary.json').write_text(json.dumps(self.final))
            return raw
        with patch.object(pathlib.Path,'read_bytes',read):result=summarize.summarize(self.root)
        self.assertTrue((self.root/'summary.json').exists())
        self.assertFalse(result['final_summary_present_at_capture_start']);self.assertFalse(result['final_summary_available'])
        self.assertNotIn('final_disposition',result)

    def test_final_accounting_mismatch_never_imports_pass(self):
        wrong=dict(self.final,offered=2);(self.root/'summary.json').write_text(json.dumps(wrong))
        result=summarize.summarize(self.root)
        self.assertEqual(result['snapshot_kind'],'inconsistent');self.assertIn('offered',result['final_consistency_errors'])
        self.assertNotIn('final_disposition',result)

    def test_matching_final_binds_events_spec_summary_and_reporter(self):
        raw=json.dumps(self.final).encode();(self.root/'summary.json').write_bytes(raw)
        result=summarize.summarize(self.root)
        self.assertTrue(result['final_summary_available']);self.assertTrue(result['final_disposition']['capacity_pass'])
        self.assertEqual(result['summary_sha256'],hashlib.sha256(raw).hexdigest())
        self.assertEqual(result['events_sha256'],hashlib.sha256(self.raw).hexdigest())
        self.assertEqual(result['source_identity']['harness_hashes'],{'runner.py':'pinned'});self.assertTrue(result['reporter_sha256'])

    def test_partial_tail_is_hashed_but_not_counted_or_final(self):
        raw=self.raw+b'{"index":1';(self.root/'events.jsonl').write_bytes(raw);(self.root/'summary.json').write_text(json.dumps(self.final))
        result=summarize.summarize(self.root)
        self.assertEqual(result['event_records'],1);self.assertEqual(result['events_sha256'],hashlib.sha256(raw).hexdigest())
        self.assertEqual(result['unparsed_trailing_bytes'],10);self.assertFalse(result['final_summary_available'])

    def test_aborted_final_is_not_a_completed_planned_window(self):
        spec=dict(self.spec,stages=[[7200,1]]);(self.root/'spec.json').write_text(json.dumps(spec))
        source=dict(self.final,**spec,duration_seconds=7200,planned_offers=7200,not_offered_after_abort=7199,
          elapsed_seconds=.2,aborted=True,capacity_pass=False,offered_rps=1/7200,completed_in_window_rps=1/7200)
        (self.root/'summary.json').write_text(json.dumps(source));result=summarize.summarize(self.root)
        self.assertEqual(result['snapshot_kind'],'finalized_attempt');self.assertTrue(result['final_summary_available'])
        self.assertFalse(result['planned_window_completed']);self.assertTrue(result['final_disposition']['aborted'])

if __name__=='__main__':unittest.main()
