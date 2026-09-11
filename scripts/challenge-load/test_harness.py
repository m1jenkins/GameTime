"""Safety and offered-load regressions; no database or lifecycle operations."""
import base64, hashlib, hmac, json, pathlib, unittest, time
from unittest.mock import patch
from lab import ROOT, copied_config, init, Lab, committed_inputs
from runner import schedule, token, Client
from arrivals import execute
from contracts import expected_terms,allocation
from oracles import response_errors,canonical

class HarnessTests(unittest.TestCase):
    def test_collision_stops_before_any_write_or_start(self):
        with patch('lab.inventory',return_value='retained'),patch('lab.probe_ports',side_effect=OSError('occupied')),patch('lab.shutil.copytree') as copy,patch('lab.command') as command:
            with self.assertRaisesRegex(OSError,'occupied'):init('/does-not-exist-challenge-load-test')
            copy.assert_not_called();command.assert_not_called()

    def test_existing_run_is_never_reused(self):
        with patch('lab.inventory') as inv,patch('lab.command') as command:
            with self.assertRaisesRegex(ValueError,'must not exist'):init(str(ROOT))
            inv.assert_not_called();command.assert_not_called()

    def test_copied_config_uses_allocated_ports_and_no_seed(self):
        source=(ROOT/'supabase/config.toml').read_text()
        result=copied_config(source,'challenge-load-0123456789ab')
        self.assertIn('project_id = "gametime"',source)
        self.assertNotRegex(result,r'(?m)^\w*port = 5432')
        self.assertIn('port = 41321',result)
        self.assertIn('enabled = false',result.split('[db.seed]')[1].split('[')[0])
        self.assertIn('max_rows = 1000',result)
        self.assertIn('major_version = 17',result)

    def test_arrivals_do_not_depend_on_completion(self):
        offsets=list(schedule([(2,25),(1,150)]))
        self.assertEqual(len(offsets),200)
        self.assertEqual(offsets[50],2)
        self.assertAlmostEqual(offsets[-1],2+149/150)
        self.assertEqual(len(list(schedule([(7200,10)]))),72000)

    def test_auth_token_binds_actual_session_and_actor(self):
        jwt=token('local-test-secret','actor-id','session-id')
        content,signature=jwt.rsplit('.',1)
        expected=base64.urlsafe_b64encode(hmac.new(b'local-test-secret',content.encode(),hashlib.sha256).digest()).decode().rstrip('=')
        self.assertEqual(signature,expected)
        claims=json.loads(base64.urlsafe_b64decode(content.split('.')[1]+'==='))
        self.assertEqual((claims['sub'],claims['session_id'],claims['role']),('actor-id','session-id','authenticated'))

    def test_void_rpc_204_is_success(self):
        client=object.__new__(Client)
        with patch.object(client,'request',return_value=({'status':204},None)):
            self.assertIsNone(client.require('fixture_rpc',{},service=True))

    def test_privileged_sql_cannot_inherit_hostaddr_or_service(self):
        lab=object.__new__(Lab);lab.data=pathlib.Path('/not-written');lab.m={'db_port':41322};lab.cluster_id='123456789'
        poison={'PGHOSTADDR':'203.0.113.7','PGSERVICE':'retained','PGSERVICEFILE':'/must-not-be-read','PGPORT':'54322','PGOPTIONS':'-c search_path=unsafe'}
        with patch.dict('os.environ',poison),patch.object(lab,'check_owner'),patch('lab.command',return_value='') as command:
            lab.owner_sql('delete from synthetic_only;','negative-test')
        args,kwargs=command.call_args
        self.assertIn('hostaddr=127.0.0.1',args[0][-1]);self.assertIn('port=41322',args[0][-1])
        for key in poison:self.assertNotIn(key,kwargs['env'])
        self.assertLess(kwargs['input_text'].index('pg_control_system'),kwargs['input_text'].index('delete from'))
        self.assertIn("<> '123456789'",kwargs['input_text'])

    def test_product_drift_is_rejected_without_any_process_start(self):
        root=pathlib.Path('/controlled');sql=root/'supabase/migrations/a.sql';config=root/'supabase/config.toml'
        tracked=['supabase/config.toml','supabase/migrations/a.sql']
        def git(args,**kwargs):return '\n'.join(tracked) if args[1]=='ls-tree' else b'committed'
        for drift in ['dirty','untracked','symlink','product-changing-descendant']:
            files=[sql]+([root/'supabase/migrations/extra.sql'] if drift=='untracked' else [])
            with self.subTest(drift=drift),patch('lab.ROOT',root),patch('lab.subprocess.check_output',side_effect=git),patch('pathlib.Path.rglob',return_value=files),patch('pathlib.Path.is_file',return_value=True),patch('pathlib.Path.is_symlink',side_effect=lambda:drift=='symlink'),patch('pathlib.Path.read_bytes',return_value=b'changed' if drift in ('dirty','product-changing-descendant') else b'committed'):
                with self.assertRaises(ValueError):committed_inputs()

    def test_empty_or_foreign_api_identity_fails_before_mutation(self):
        class Fake:
            m={'api_port':41321};credentials={'API_URL':'http://127.0.0.1:41321'}
        with patch.object(Client,'request',return_value=({'status':200},{})) as request:
            with self.assertRaisesRegex(ValueError,'identity'):Client(Fake())
            self.assertEqual(request.call_args.args[0],'challenge_access_status_v1')

    def test_slow_successes_with_drops_fail_capacity(self):
        def slow(_):time.sleep(.04);return {'status':200,'seconds':.04,'oracle_failures':[]}
        result,events=execute([(.15,100)],1,slow,lambda _:None)
        self.assertTrue(result['accounting_ok']);self.assertGreater(result['counts']['dropped'],0)
        self.assertFalse(result['capacity_pass'])
        self.assertIn('completed_after_window',result)

    def test_first_oracle_failure_stops_new_dispatch(self):
        result,events=execute([(1,10)],1,lambda _:{'status':200,'oracle_failures':['wrong_receipt']},lambda _:None)
        self.assertTrue(result['aborted']);self.assertEqual(result['offered'],1)
        self.assertEqual(result['not_offered_after_abort'],9);self.assertFalse(result['capacity_pass'])

    def test_empty_page_and_changed_receipt_fail_closed(self):
        class Fake:
            def uid(self,*_):return 'actor'
        live={'authorized_ids':{},'exact_receipts':{'age':canonical({'confirmed':True})}}
        self.assertEqual(response_errors(Fake(),live,'section_history',{'p_section':'history'},0,{}),['page_shape'])
        self.assertEqual(response_errors(Fake(),live,'journal_exact_retry',{},0,{'confirmed':False}),['changed_exact_receipt'])

    def test_literal_leaderboard_and_community_contracts(self):
        for metric in ['steps','exercise','distance','timed']:
            terms=expected_terms('friend_'+metric+'_leaderboard_v1',{},[{'actor_id':'a','target':None}],2,6)
            self.assertEqual(terms['missing_rule'],'void_if_any_unresolved')
            self.assertEqual(terms['allocation_rule'],'co_winners_split_active_pool_remainder_unallocated')
            self.assertEqual(terms['participants'],[{'actor_id':'a'}])
            self.assertNotIn('common_target',terms)
        community=expected_terms('community_steps_goal_v1',{},[],2,100)
        self.assertEqual(community['common_target'],100);self.assertNotIn('participants',community);self.assertNotIn('version',community)

    def test_tie_remainder_and_strict_timed_boundary(self):
        people=[{'actor_id':str(i),'target':None,'excluded':False,'state':'complete','value':100 if i<3 else 90} for i in range(5)]
        outcome=allocation('friend_steps_leaderboard_v1',people,2)
        self.assertEqual(outcome['unallocated_cents'],2)
        self.assertEqual(outcome['participants']['0'],{'status':'winner','returned_cents':166})
        timed=allocation('personal_timed_goal_v1',[dict(people[0],target=100,value=100)],1)
        self.assertEqual(timed['participants']['0']['status'],'missed')

if __name__=='__main__':unittest.main()
