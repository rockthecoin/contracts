"""Reproduce programs in temporary directories. Never overwrite published artifacts."""
import argparse,importlib.metadata,json,pathlib,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
assert sys.version_info[:2]==(3,12),'Use Python 3.12'
for name,version in [('algorand-python','4.0.0'),('puyapy','5.10.1')]:assert importlib.metadata.version(name)==version,f'{name} version mismatch'
compiler=str(pathlib.Path(sys.executable).parent/'puyapy');assert pathlib.Path(compiler).is_file(),'Install the pinned toolchain into a virtual environment'
parser=argparse.ArgumentParser();parser.add_argument('--package',choices=['algorand-suite-v1','algorand-token-v2']);args=parser.parse_args()
specs=[('algorand-suite-v1',['tokens.py','nft_collections.py','escrows.py']),('algorand-token-v2',['tokens.py'])]
if args.package:specs=[x for x in specs if x[0]==args.package]
for package,sources in specs:
 root=ROOT/'contracts'/package
 with tempfile.TemporaryDirectory(prefix='rtc-algorand-build-') as temp:
  subprocess.run([compiler,*sources,'--out-dir',temp,'--output-bytecode','--resource-encoding','index','--debug-level','0','--log-level','warning'],cwd=root,check=True,timeout=300)
  artifact=json.loads((root/'artifacts'/('suite.json' if package.endswith('v1') else 'token.json')).read_text())
  for app in artifact.get('apps',{'tokens':artifact}).values():
   for suffix in ('approval.bin','clear.bin','arc56.json'):
    built=pathlib.Path(temp)/(app['name']+'.'+suffix);original=root/'artifacts'/built.name
    if suffix.endswith('.json'):assert json.loads(built.read_text())==json.loads(original.read_text()),'ABI/schema differs: '+built.name
    else:assert built.read_bytes()==original.read_bytes(),'Bytecode differs: '+built.name
   print(json.dumps({'package':package,'program':app['name'],'reproduced':True,'approval_sha256':app['approval_sha256']}))
subprocess.run([sys.executable,str(ROOT/'scripts/verify-algorand.py')],cwd=ROOT,check=True)
