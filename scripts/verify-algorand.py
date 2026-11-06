"""Offline integrity checks for the published immutable Algorand releases."""
import base64,hashlib,json,pathlib

ROOT=pathlib.Path(__file__).resolve().parents[1]
def load(path):return json.loads((ROOT/path).read_text())
def digest(data):return hashlib.sha256(data).hexdigest()
files=0;programs=0
for package in load('packages.json')['algorand']:
 root=ROOT/package['directory'];lock=json.loads((root/'published.lock').read_text())
 for name,expected in lock['files'].items():
  assert not pathlib.PurePosixPath(name).is_absolute() and '..' not in pathlib.PurePosixPath(name).parts
  assert digest((root/name).read_bytes())==expected,f'Frozen file changed: {name}'
  files+=1
 source=load(package['source'])
 assert source['compiler']=='puyapy 5.10.1' and source['algorand_python']=='4.0.0'
 for name,text in source['files'].items():assert (root/name).read_text()==text,f'Source bundle differs: {name}'
 artifact=load(package['artifact']);apps=artifact.get('apps',{'tokens':artifact})
 for kind,app in apps.items():
  for program in ('approval','clear'):
   raw=base64.b64decode(app[program+'_program'],validate=True)
   assert digest(raw)==app[program+'_sha256']
   assert raw==(root/'artifacts'/(app['name']+'.'+program+'.bin')).read_bytes()
   assert raw[0]==11,'Unexpected AVM version'
  size=sum(len(base64.b64decode(app[p+'_program'])) for p in ('approval','clear'))
  assert size==app['program_bytes'] and size<=8192 and (size+2047)//2048-1==app['extra_pages']
  spec=json.loads((root/'artifacts'/(app['name']+'.arc56.json')).read_text())
  for key,expected in [('methods',app['methods']),('structs',app['structs'])]:assert spec[key]==expected
  assert spec['state']['schema']==app['schema']
  programs+=1
 if 'escrow_account' in artifact:
  escrow=json.loads((root/'artifacts/escrow-account.json').read_text())
  assert artifact['escrow_account']==escrow and base64.b64decode(escrow['template'])[0]==8
  assert digest((root/'escrow-account.teal').read_bytes())==escrow['source_sha256']
print(json.dumps({'result':'passed','packages':2,'app_programs':programs,'frozen_files':files,'network_requests':0,'broadcasts':0}))
