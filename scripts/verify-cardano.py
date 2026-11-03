#!/usr/bin/env python3
"""Verify frozen Cardano source, blueprints and native Plutus script hashes offline."""
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
sha=lambda data:hashlib.sha256(data).hexdigest()
packages=json.loads((root/'packages.json').read_text())['cardano']
count=0
for package in packages:
 folder=root/package['directory'];lock=json.loads((folder/'artifacts/published.lock').read_text());artifact=json.loads((folder/'artifacts/scripts.json').read_text());blueprint=json.loads((folder/'plutus.json').read_text())
 assert lock['status']=='published' and artifact['compiler']==package['compiler']
 for name,digest in lock['sha256'].items():
  path=pathlib.PurePosixPath(name);assert not path.is_absolute() and '..' not in path.parts
  assert sha((folder/name).read_bytes())==digest,(package['id'],name)
 for name,digest in artifact['sources'].items():assert sha((folder/name).read_bytes())==digest,(package['id'],name)
 if (folder/'artifacts/source.json').exists():
  source=json.loads((folder/'artifacts/source.json').read_text())
  for name,text in source['sources'].items():assert (folder/name).read_text()==text,(package['id'],name)
 for name,script in artifact['scripts'].items():
  code=bytes.fromhex(script['cbor']);assert hashlib.blake2b(b'\x03'+code,digest_size=28).hexdigest()==script['hash'],name
  assert any(v['hash']==script['hash'] and v['compiledCode']==script['cbor'] for v in blueprint['validators']),name
  if 'bytes' in script:assert len(code)==script['bytes']
  count+=1
 print(package['id']+': frozen sources, blueprint and script hashes verified')
print(json.dumps({'result':'passed','packages':len(packages),'scripts':count,'network_requests':0,'broadcasts':0}))
