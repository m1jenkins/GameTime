#!/usr/bin/env python3
"""Owned, loopback-only challenge lab. Python 3.9 stdlib; no hosted target option."""
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, re, shutil, socket, subprocess, sys, time, uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
PARENT = '7c34d52bc0250053819e35342a2b4fd9ed5d7382'
PORTS = list(range(41320, 41330)) # fresh round-2 allocation; 4232x is retained evidence
EXCLUDE = 'analytics,edge-runtime,functions,imgproxy,inbucket,meta,realtime,storage,studio,vector'

def digest(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()

def pg_environment(environ=None):
    # libpq environment/service/passfile/hostaddr/options must never redirect a privileged connection.
    original=os.environ if environ is None else environ
    result={k:v for k,v in original.items() if not k.upper().startswith('PG')}
    result['PGPASSWORD']='postgres' # disposable local CLI database only; never placed in argv
    result['PGPASSFILE']='/dev/null'
    return result

def pg_arguments(port,label):
    if port not in (41322,42322,5432) or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}',label):
        raise ValueError('unowned SQL connection arguments')
    connection='host=127.0.0.1 hostaddr=127.0.0.1 port=%d dbname=postgres user=postgres sslmode=disable gssencmode=disable connect_timeout=5 application_name=%s'%(port,label)
    return ['psql','-X','-qAt','-v','ON_ERROR_STOP=1','--dbname',connection]

def identity_guard(cluster_id):
    if not re.fullmatch(r'[0-9]{1,30}',cluster_id):raise ValueError('invalid database identity')
    return "do $owned$ begin if (select system_identifier::text from pg_control_system()) <> '%s' or current_database()<>'postgres' or session_user<>'postgres' or inet_server_port()<>5432 then raise exception 'challenge_load_wrong_database'; end if; end $owned$;\n"%cluster_id

def committed_inputs():
    paths=subprocess.check_output(['git','ls-tree','-r','--name-only',PARENT,'supabase/migrations','supabase/config.toml'],cwd=ROOT,text=True).splitlines()
    expected={path:subprocess.check_output(['git','show',PARENT+':'+path],cwd=ROOT) for path in paths}
    actual={str(p.relative_to(ROOT)) for p in (ROOT/'supabase/migrations').rglob('*') if p.is_file() or p.is_symlink()}|{'supabase/config.toml'}
    if set(expected)!=actual:raise ValueError('untracked or missing product input')
    for path,contents in expected.items():
        item=ROOT/path
        if item.is_symlink() or any(parent.is_symlink() for parent in item.parents if parent!=ROOT.parent):
            raise ValueError('symlink product input')
        if item.read_bytes()!=contents:raise ValueError('product input differs from exact committed parent')
    return expected

def save(path, value):
    path = pathlib.Path(path)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    path.chmod(0o600)

def command(argv, destination, *, input_text=None, env=None, timeout=180):
    """Private output, append-only command receipt. Never put credentials in argv."""
    destination = pathlib.Path(destination)
    started = time.time()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open('x') as output:
        destination.chmod(0o600)
        try:
            result = subprocess.run(argv, input=input_text, text=True, stdout=output,
                                    stderr=subprocess.STDOUT, env=env, timeout=timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
        except OSError as error:
            output.write(type(error).__name__+'\n')
            code = 127
    receipt = {'argv': argv, 'started_unix': started, 'elapsed_seconds': time.time()-started,
               'exit_code': code, 'output': str(destination), 'output_sha256': digest(destination),
               'stdin_sha256': hashlib.sha256((input_text or '').encode()).hexdigest()}
    with (destination.parent / 'commands.jsonl').open('a') as f:
        f.write(json.dumps(receipt) + '\n')
    if code:
        raise RuntimeError('command failed (%s); inspect private log %s' % (code, destination))
    return destination.read_text()

def inventory():
    return subprocess.check_output(['docker', 'ps', '-a', '--format', '{{.Names}}\t{{.ID}}\t{{.Ports}}'], text=True)

def probe_ports():
    held = []
    try:
        for port in PORTS:
            for family, address in [(socket.AF_INET, '127.0.0.1'), (socket.AF_INET6, '::1')]:
                s = socket.socket(family, socket.SOCK_STREAM)
                if family == socket.AF_INET6:
                    s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
                held.append(s)
                s.bind((address, port))
    finally:
        for s in held:
            s.close()

def copied_config(source, project):
    text = source
    text = re.sub(r'^project_id = .*$', 'project_id = "'+project+'"', text, flags=re.M)
    for old in range(54320,54330):
        text = re.sub(r'(?m)^(\w*port = )'+str(old)+r'$', r'\g<1>'+str(old-13000), text)
    text = re.sub(r'(?m)^inspector_port = 8083$', 'inspector_port = 41328', text)
    for section in ['db.seed','studio','local_smtp','storage','storage.vector','edge_runtime','auth.external.apple']:
        text, count = re.subn(r'(\['+re.escape(section)+r'\]\n(?:(?!\[).)*?enabled = )true', r'\g<1>false', text, flags=re.S)
        if count != 1:
            raise ValueError('expected exactly one enabled setting in '+section)
    # Apple is disabled only in this SQL-provisioned identity lab; app Auth semantics are not tested.
    return text

def init(data):
    data = pathlib.Path(data).resolve()
    if data.exists() or data.is_symlink():
        raise ValueError('run root must not exist')
    if subprocess.check_output(['git','rev-parse','--show-toplevel'], cwd=ROOT, text=True).strip()!=str(ROOT):
        raise ValueError('repository boundary mismatch')
    if subprocess.run(['git','merge-base','--is-ancestor',PARENT,'HEAD'],cwd=ROOT).returncode:
        raise ValueError('required parent absent')
    if subprocess.run(['git','diff','--quiet',PARENT,'--','supabase/config.toml','supabase/migrations'],cwd=ROOT).returncode:
        raise ValueError('product database source differs from fixed parent')
    inputs=committed_inputs()
    current = inventory()
    probe_ports()
    project = 'challenge-load-'+uuid.uuid4().hex[:12]
    if project in current:
        raise ValueError('project already exists')
    data.mkdir(mode=0o700)
    (data/'private').mkdir(mode=0o700)
    stack = data/'stack'
    (stack/'supabase').mkdir(parents=True)
    # Extract the verified commit bytes, not a mutable working directory copy.
    (stack/'supabase/migrations').mkdir()
    for path,contents in inputs.items():
        if path.startswith('supabase/migrations/'):(stack/path).write_bytes(contents)
    config = copied_config(inputs['supabase/config.toml'].decode(),project)
    (stack/'supabase/config.toml').write_text(config)
    migration_hashes = {p.name:digest(p) for p in sorted((stack/'supabase/migrations').glob('*.sql'))}
    manifest = {'version':1,'run_root':str(data),'project':project,'namespace':str(uuid.uuid4()),
                'parent':PARENT,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                'api_port':41321,'db_port':41322,'ports_reserved':PORTS,'created_unix':time.time(),
                'source_config_sha256':hashlib.sha256(inputs['supabase/config.toml']).hexdigest(),
                'lab_config_sha256':digest(stack/'supabase/config.toml'),'migration_hashes':migration_hashes,
                'excluded_services':EXCLUDE,'container_ids':{}}
    save(data/'manifest.json',manifest)
    (data/'inventory-before.txt').write_text(current)
    print(str(data), flush=True)
    # Only the just-created namespace can ever reach this start. There is no reset/stop command.
    env = dict(pg_environment(), DO_NOT_TRACK='1')
    command(['supabase','start','--workdir',str(stack),'-x',EXCLUDE],data/'private/start.log',env=env,timeout=600)
    status = command(['supabase','status','--workdir',str(stack),'-o','json'],data/'private/status.log',env=env)
    # CLI warnings may precede JSON. Preserve full private receipt, select the final JSON object.
    start = status.find('{')
    keys = json.JSONDecoder().raw_decode(status[start:])[0]
    save(data/'private/credentials.json',keys)
    owned = subprocess.check_output(['docker','ps','--filter','name='+project,'--format','{{.Names}}\t{{.ID}}'],text=True)
    manifest['container_ids'] = dict(line.split('\t') for line in owned.splitlines())
    if 'supabase_db_'+project not in manifest['container_ids']:
        raise RuntimeError('new database identity missing')
    save(data/'manifest.json',manifest)
    bind_cluster_identity(data)
    print(json.dumps({'project':project,'containers':manifest['container_ids'],'ports':PORTS}),flush=True)

def bind_cluster_identity(data):
    """Bootstrap via positively identified container-local psql, never a host network connection."""
    lab=Lab(data,require_identity=False)
    container='supabase_db_'+lab.m['project']
    argv=['docker','exec','-i',container,'env','-i','PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','PGPASSWORD=postgres','PGPASSFILE=/dev/null']+pg_arguments(5432,'challenge-load-bootstrap')
    value=command(argv,lab.data/'private'/('cluster-identity-'+str(time.time_ns())+'.log'),input_text='select system_identifier::text from pg_control_system();',env=pg_environment()).strip()
    if not re.fullmatch(r'[0-9]{1,30}',value):raise ValueError('invalid local cluster identity')
    save(lab.data/'cluster-identity.json',{'project':lab.m['project'],'container_id':lab.m['container_ids'][container],'system_identifier':value})

class Lab:
    def __init__(self, data,require_identity=True):
        self.data = pathlib.Path(data).resolve()
        if pathlib.Path(data).is_symlink():
            raise ValueError('symlink run root refused')
        self.m = json.loads((self.data/'manifest.json').read_text())
        if self.m['run_root']!=str(self.data) or self.m['parent']!=PARENT:
            raise ValueError('manifest ownership mismatch')
        ports=self.m['ports_reserved']
        if ports not in (PORTS,list(range(42320,42330))) or self.m['api_port']!=ports[1] or self.m['db_port']!=ports[2] or not re.fullmatch(r'challenge-load-[0-9a-f]{12}',self.m['project']):
            raise ValueError('unowned project/port')
        uuid.UUID(self.m['namespace'])
        self.namespace = uuid.UUID(self.m['namespace'])
        self.credentials = json.loads((self.data/'private/credentials.json').read_text())
        baseline=committed_inputs()
        expected={path.split('/')[-1]:hashlib.sha256(contents).hexdigest() for path,contents in baseline.items() if path.startswith('supabase/migrations/')}
        if expected!=self.m['migration_hashes'] or hashlib.sha256(baseline['supabase/config.toml']).hexdigest()!=self.m['source_config_sha256']:
            raise ValueError('manifest does not describe the exact product parent')
        self.check_owner()
        if require_identity:
            identity=json.loads((self.data/'cluster-identity.json').read_text())
            if identity['project']!=self.m['project'] or identity['container_id']!=self.m['container_ids']['supabase_db_'+self.m['project']]:
                raise ValueError('cluster identity binding mismatch')
            self.cluster_id=identity['system_identifier']

    def uid(self, kind, number):
        return str(uuid.uuid5(self.namespace, '%s:%s' % (kind,number)))

    def check_owner(self):
        config=self.data/'stack/supabase/config.toml'
        if config.is_symlink() or any(p.is_symlink() for p in config.parents) or digest(config)!=self.m['lab_config_sha256']:
            raise ValueError('lab configuration changed')
        for name, sha in self.m['migration_hashes'].items():
            item=self.data/'stack/supabase/migrations'/name
            if item.is_symlink() or digest(item)!=sha:
                raise ValueError('copied migration changed')
        actual={p.name for p in (self.data/'stack/supabase/migrations').iterdir()}
        if actual!=set(self.m['migration_hashes']):raise ValueError('copied migration file-set changed')
        required={'supabase_'+kind+'_'+self.m['project'] for kind in ['db','kong','auth','rest']}
        if set(self.m['container_ids'])!=required:
            raise ValueError('owned service set mismatch')
        fmt='{"name":{{json .Name}},"id":{{json .Id}},"running":{{json .State.Running}},"ports":{{json .NetworkSettings.Ports}}}'
        observed=subprocess.check_output(['docker','inspect','--format',fmt]+sorted(required),text=True)
        for line in observed.splitlines():
            item=json.loads(line);name=item['name'].lstrip('/')
            if not item['running'] or not item['id'].startswith(self.m['container_ids'].get(name,'INVALID')):
                raise ValueError('owned container identity mismatch')
            for kind,internal,external in [('db','5432/tcp',str(self.m['db_port'])),('kong','8000/tcp',str(self.m['api_port']))]:
                if name=='supabase_'+kind+'_'+self.m['project'] and not any(x['HostPort']==external for x in item['ports'].get(internal,[]) or []):
                    raise ValueError('owned '+kind+' binding mismatch')

    def fixture_owner(self):
        identity=json.loads(self.sql('select to_jsonb(i) from challenge_load_fixture.identity i;','fixture-owner'))
        if identity!={'namespace':str(self.namespace),'project':self.m['project']}:
            raise ValueError('database fixture namespace mismatch')
        actors=json.loads(self.sql("select jsonb_agg(jsonb_build_object('ordinal',a.ordinal,'id',a.id,'session_id',a.session_id,'handle',p.handle)) from challenge_load_fixture.actors a left join public.profiles p on p.id=a.id;",'fixture-registry'))
        if not isinstance(actors,list) or len(actors) not in (2000,25000) or {a['ordinal'] for a in actors}!=set(range(len(actors))):
            raise ValueError('fixture registry shape mismatch')
        for actor in actors:
            number=actor['ordinal']
            if actor['id']!=self.uid('actor',number) or actor['session_id']!=self.uid('session',number) or actor['handle']!='cl_'+self.namespace.hex[:8]+'_'+str(number):
                raise ValueError('foreign actor in fixture registry')

    def sql(self, query, label, *, timeout=180):
        self.check_owner()
        stamp=str(time.time_ns())
        text=command(pg_arguments(self.m['db_port'],'challenge-load-'+label),self.data/'private'/(stamp+'-'+label+'.log'),
                     input_text=identity_guard(self.cluster_id)+query,env=pg_environment(),timeout=timeout)
        return text.strip()

    def owner_sql(self, query, label, *, timeout=180):
        return self.sql("begin; set local statement_timeout='120s'; set local lock_timeout='15s'; set local app.challenge_write_v1='on';\n"+query+'\ncommit;',label,timeout=timeout)

    def service_sql(self, query, label):
        return self.sql('begin; set local role service_role;\n'+query+'\ncommit;',label)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['init','verify','gates-off','cleanup-sessions'])
    parser.add_argument('run_root')
    args=parser.parse_args()
    if args.action=='init':
        init(args.run_root)
        return
    lab=Lab(args.run_root)
    if args.action in ('gates-off','cleanup-sessions'):
        lab.service_sql('select public.challenge_discovery_fixture_v1(false); select public.challenge_runtime_v1(false,false,false,\'{}\',null);','gates-off')
    if args.action=='cleanup-sessions':
        lab.fixture_owner()
        # Immutable challenge rows cannot be deleted without changing product semantics.
        # A positive registry of UUIDv5 actors AND matching synthetic handles is required.
        counts=lab.owner_sql("delete from app.challenge_pages_v1 where actor_id in (select id from challenge_load_fixture.actors); delete from auth.sessions where user_id in (select a.id from challenge_load_fixture.actors a join public.profiles p on p.id=a.id where p.handle::text like 'cl_"+lab.namespace.hex[:8]+"_%'); select count(*) from auth.sessions where user_id in (select id from challenge_load_fixture.actors);",'cleanup-sessions')
        print(json.dumps({'remaining_owned_sessions':counts,'immutable_ledger':'retained; deletion prohibited by unchanged guards'}))
    else:
        print(json.dumps({'verified':lab.m['project'],'parent':PARENT}))

if __name__=='__main__':
    main()
