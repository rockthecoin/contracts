#!/usr/bin/env python3
"""Check and rebuild Cardano validators in temporary copies; preserve frozen packages."""
import hashlib,json,os,pathlib,shutil,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1];pin=json.loads((root/'toolchains/aiken.json').read_text());compiler=pathlib.Path(os.environ.get('AIKEN',root/'.toolchains/aiken')).resolve()
assert hashlib.sha256(compiler.read_bytes()).hexdigest()==pin['binary_sha256'],'Aiken compiler checksum mismatch'
assert subprocess.check_output([str(compiler),'--version'],text=True).strip()==pin['version']
packages=json.loads((root/'packages.json').read_text())['cardano'];passed=0
for package in packages:
 folder=root/package['directory'];lock=json.loads((folder/'artifacts/published.lock').read_text());expected=json.loads((folder/'plutus.json').read_text())
 with tempfile.TemporaryDirectory(prefix='rtc-cardano-build-') as directory:
  target=pathlib.Path(directory)
  for name,digest in lock['sha256'].items():
   if name.endswith('.ak') or name in ['aiken.toml','aiken.lock']:
    data=(folder/name).read_bytes();assert hashlib.sha256(data).hexdigest()==digest;out=target/name;out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(data)
  for action in ['check','build']:
   result=subprocess.run([str(compiler),action],cwd=target,capture_output=True,text=True,timeout=180)
   if result.returncode:raise SystemExit(package['id']+' '+action+' failed\n'+result.stdout[-5000:]+'\n'+result.stderr[-5000:])
   if action=='check':
    report=json.loads(result.stdout);summary=report.get('summary',{});assert summary.get('failed',0)==0;passed+=int(summary.get('passed',0))
  actual=json.loads((target/'plutus.json').read_text());select=lambda bp:{v['title']:(v['compiledCode'],v['hash']) for v in bp['validators']}
  assert select(actual)==select(expected),package['id']+' compiled validators differ'
 print(package['id']+': Aiken checks and validator reproduction passed')
print(json.dumps({'result':'passed','packages':len(packages),'aiken_checks':passed,'broadcasts':0}))
