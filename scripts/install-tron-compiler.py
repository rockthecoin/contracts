#!/usr/bin/env python3
"""Install the checksum-pinned official Linux x86-64 TRON compiler."""
import hashlib,json,os,pathlib,sys,urllib.request
pin=json.loads(pathlib.Path('toolchains/tron-solidity.json').read_text())
target=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else '.toolchains/tron-solc')
if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()==pin['sha256']:
    print(target.resolve());raise SystemExit(0)
with urllib.request.urlopen(pin['url'],timeout=60) as response:binary=response.read(50_000_001)
if len(binary)>50_000_000 or hashlib.sha256(binary).hexdigest()!=pin['sha256']:raise SystemExit('TRON compiler checksum mismatch')
target.parent.mkdir(parents=True,exist_ok=True);temporary=target.with_suffix('.download');temporary.write_bytes(binary);temporary.chmod(0o755);os.replace(temporary,target);print(target.resolve())
