"""Required burst fault regressions; fake HTTP/SQL only, no lab lifecycle."""
import contextlib,io,json,pathlib,tempfile,types,unittest,uuid
from unittest.mock import patch
import bursts

class BurstFaultTests(unittest.TestCase):
    def setUp(self):
        # Only this test's own new directory is removed by TemporaryDirectory.
        self.directory=tempfile.TemporaryDirectory(prefix='.burst-test-',dir=pathlib.Path(__file__).parent)
        self.addCleanup(self.directory.cleanup)
        self.root=pathlib.Path(self.directory.name)
        self.lab=types.SimpleNamespace(data=self.root,m={'parent':'test-parent','project':'test-project'},
          cluster_id='123',namespace=uuid.UUID(int=1),uid=lambda kind,number:'actor-'+str(number))
        self.live={'accounts':2000,'authorized_ids':{str(i):['owned'] for i in range(100)}}
        (self.root/'private').mkdir()
        (self.root/'private/live-2000.json').write_text('{}')

    def response(self,operation,payload,actor):
        if operation=='challenge_section_v1':
            body={'section':payload['p_section'],'projection_revision':'snapshot','server_time':'now','expires_at':'later','rows':[],'next_cursor':None}
        else:body={}
        return {'status':200,'seconds':.001,'bytes':2,'code':None},body

    def invoke(self,request,post_error=None):
        (self.root/'preflight-2000.json').write_text('{}')
        fake=types.SimpleNamespace(request=request)
        with patch.object(bursts,'load_live',return_value=self.live),patch.object(bursts,'check_preflight',return_value={}),patch.object(bursts,'Client',return_value=fake),patch.object(bursts,'postflight',side_effect=post_error),contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as failed:bursts.run(self.lab,'fault','foreground')
        self.assertEqual(failed.exception.code,1)
        return json.loads((self.root/'fault/summary.json').read_text())

    def test_http_200_empty_page_fails_burst(self):
        summary=self.invoke(lambda *_:({'status':200,'seconds':.001,'bytes':2,'code':None},{}))
        self.assertFalse(summary['passed']);self.assertFalse(summary['oracles']['response_invariants'])
        self.assertLess(summary['completed_requests'],600)

    def test_http_200_foreign_page_fails_burst(self):
        def foreign(operation,payload,actor):
            sample,body=self.response(operation,payload,actor)
            if operation=='challenge_section_v1':body['rows']=[{'id':'foreign','policy':'friend_steps_goal_v1','status':'active','members':[],
              'social_hidden':False,'agreement':None,'reviews':[],'final':None}]
            return sample,body
        summary=self.invoke(foreign)
        self.assertFalse(summary['passed']);self.assertFalse(summary['oracles']['response_invariants'])

    def test_missing_preflight_refuses_before_http(self):
        with patch.object(bursts,'load_live',return_value=self.live),patch.object(bursts,'Client') as client:
            with self.assertRaises(FileNotFoundError):bursts.run(self.lab,'missing','foreground')
            client.assert_not_called()

    def test_stale_preflight_refuses_before_http(self):
        (self.root/'preflight-2000.json').write_text(json.dumps({'passed':False}))
        with patch.object(bursts,'load_live',return_value=self.live),patch.object(bursts,'Client') as client:
            with self.assertRaisesRegex(AssertionError,'preflight_binding_passed'):bursts.run(self.lab,'stale','foreground')
            client.assert_not_called()

    def test_postflight_failure_fails_otherwise_successful_burst(self):
        summary=self.invoke(self.response,AssertionError('historical_immutability'))
        self.assertEqual(summary['completed_requests'],600)
        self.assertTrue(summary['oracles']['response_invariants']);self.assertFalse(summary['oracles']['postflight'])
        self.assertFalse(summary['passed'])

if __name__=='__main__':unittest.main()
